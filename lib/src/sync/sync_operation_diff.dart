import 'package:collection/collection.dart';

import '../core/model/app_state.dart';
import '../core/model/json_helpers.dart';
import '../core/model/paper_data.dart';
import '../core/model/paper_item.dart';
import 'sync_device_id.dart';
import 'sync_operation.dart';

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
        {'paperId': after.id.trim(), 'content': after.content},
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
          'paperId': after.id.trim(),
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
          'paperId': after.id.trim(),
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
    return _withoutKeys(state.toJson(), const {'papers', 'sync'});
  }

  Map<String, PaperData> _paperMap(List<PaperData> papers) {
    return {
      for (final paper in papers)
        if (paper.id.trim().isNotEmpty) paper.id.trim(): paper,
    };
  }

  Map<String, PaperItem> _itemMap(List<PaperItem> items) {
    return {
      for (final item in items)
        if (item.id.trim().isNotEmpty) item.id.trim(): item,
    };
  }

  JsonMap _withoutKeys(JsonMap source, Set<String> keys) {
    return {
      for (final entry in source.entries)
        if (!keys.contains(entry.key)) entry.key: entry.value,
    };
  }

  JsonMap _paperJsonForDiff(PaperData paper) {
    final json = paper.toJson();
    json['id'] = stringValue(json['id'], '').trim();
    json['items'] = [
      for (final item in jsonMapList(json['items'])) _itemJsonMapForDiff(item),
    ];
    return json;
  }

  JsonMap _itemJsonForDiff(PaperItem item) {
    return _itemJsonMapForDiff(item.toJson());
  }

  JsonMap _itemJsonMapForDiff(JsonMap item) {
    return {
      ...item,
      'id': stringValue(item['id'], '').trim(),
    };
  }
}

const _deepEquals = DeepCollectionEquality();
