import 'package:collection/collection.dart';

import '../core/model/app_state.dart';
import '../core/model/json_helpers.dart' show JsonMap;
import '../core/model/paper_constants.dart';
import '../core/model/paper_data.dart';
import '../core/model/paper_item.dart';
import 'sync_device_id.dart';
import 'sync_operation.dart';
import 'sync_operation_payload.dart';

class SyncOperationDiffBuilder {
  const SyncOperationDiffBuilder();

  List<SyncOperation> build({
    required AppState before,
    required AppState after,
    required String deviceId,
    required int startSequence,
    DateTime? createdAtUtc,
  }) {
    final normalizedDeviceId = normalizeSyncDeviceId(deviceId, fallback: '');
    if (normalizedDeviceId.isEmpty) {
      return const [];
    }
    final stamp = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();
    final operations = <SyncOperation>[];
    var sequence = startSequence;

    void add(SyncOperationKind kind, JsonMap payload) {
      sequence += 1;
      if (!isSyncDeviceSequenceInRange(sequence)) {
        throw RangeError.value(
          sequence,
          'sequence',
          'Sync operation sequence must be between 1 and '
              '$maxSyncDeviceSequence.',
        );
      }
      operations.add(
        SyncOperation(
          id: '$normalizedDeviceId-$sequence',
          deviceId: normalizedDeviceId,
          sequence: sequence,
          kind: kind,
          createdAtUtc: stamp,
          payload: payload,
        ),
      );
    }

    final settingsDiff = _settingsDiff(before, after);
    if (settingsDiff.isNotEmpty) {
      add(SyncOperationKind.updateSettings, {'settings': settingsDiff});
    }

    final beforePapers = _paperMap(before.papers);
    final afterPapers = _paperMap(after.papers);
    for (final paperId in beforePapers.keys) {
      if (!afterPapers.containsKey(paperId)) {
        add(SyncOperationKind.deletePaper, {'paperId': paperId});
      }
    }
    for (final entry in afterPapers.entries) {
      final previous = beforePapers[entry.key];
      final current = entry.value;
      if (previous == null) {
        add(SyncOperationKind.upsertPaper,
            {'paper': _paperJsonForDiff(current)});
        continue;
      }
      _addPaperDiff(add, previous, current);
    }

    return operations;
  }

  void _addPaperDiff(
    void Function(SyncOperationKind kind, JsonMap payload) add,
    PaperData before,
    PaperData after,
  ) {
    final beforeJson = _paperJsonForDiff(before);
    final afterJson = _paperJsonForDiff(after);
    if (_deepEquals.equals(beforeJson, afterJson)) {
      return;
    }
    if (before.isNote &&
        after.isNote &&
        _deepEquals.equals(
          _withoutKeys(beforeJson, const {'content'}),
          _withoutKeys(afterJson, const {'content'}),
        )) {
      add(
        SyncOperationKind.updateNoteContent,
        {'paperId': _paperId(after), 'content': after.content},
      );
      return;
    }
    if (before.isTodo &&
        after.isTodo &&
        _deepEquals.equals(
          _withoutKeys(beforeJson, const {'items'}),
          _withoutKeys(afterJson, const {'items'}),
        )) {
      _addTodoItemDiff(add, before, after);
      return;
    }
    add(SyncOperationKind.upsertPaper, {'paper': afterJson});
  }

  void _addTodoItemDiff(
    void Function(SyncOperationKind kind, JsonMap payload) add,
    PaperData before,
    PaperData after,
  ) {
    final beforeItems = _itemMap(before.items);
    final afterItems = _itemMap(after.items);
    for (final itemId in beforeItems.keys) {
      if (!afterItems.containsKey(itemId)) {
        add(SyncOperationKind.deleteTodoItem, {
          'paperId': _paperId(after),
          'itemId': itemId,
        });
      }
    }
    for (final entry in afterItems.entries) {
      final previous = beforeItems[entry.key];
      final current = entry.value;
      if (previous == null ||
          !_deepEquals.equals(
            _itemJsonForDiff(previous),
            _itemJsonForDiff(current),
          )) {
        add(SyncOperationKind.upsertTodoItem, {
          'paperId': _paperId(after),
          'item': _itemJsonForDiff(current),
        });
      }
    }
  }

  JsonMap _settingsDiff(AppState before, AppState after) {
    final beforeSettings = _settingsJson(before);
    final afterSettings = _settingsJson(after);
    final diff = <String, Object?>{};
    for (final entry in afterSettings.entries) {
      if (!_deepEquals.equals(beforeSettings[entry.key], entry.value)) {
        diff[entry.key] = entry.value;
      }
    }
    return diff;
  }

  JsonMap _settingsJson(AppState state) {
    return canonicalSyncOperationSettingsPayload(state.toJson());
  }

  Map<String, PaperData> _paperMap(List<PaperData> papers) {
    return {
      for (final paper in papers)
        if (_paperId(paper).isNotEmpty) _paperId(paper): paper,
    };
  }

  Map<String, PaperItem> _itemMap(List<PaperItem> items) {
    return {
      for (final item in items)
        if (_itemId(item).isNotEmpty) _itemId(item): item,
    };
  }

  JsonMap _withoutKeys(JsonMap source, Set<String> keys) {
    return {
      for (final entry in source.entries)
        if (!keys.contains(entry.key)) entry.key: entry.value,
    };
  }

  JsonMap _paperJsonForDiff(PaperData paper) {
    return canonicalSyncOperationPaperPayload(
      PaperData.fromJson(paper.toJson()).toJson(),
    );
  }

  JsonMap _itemJsonForDiff(PaperItem item) {
    return canonicalSyncOperationTodoItemPayload(
      PaperItem.fromJson(item.toJson()).toJson(),
    );
  }

  String _paperId(PaperData paper) {
    return normalizeLocalModelId(paper.id);
  }

  String _itemId(PaperItem item) {
    return normalizeLocalModelId(item.id);
  }
}

const _deepEquals = DeepCollectionEquality();
