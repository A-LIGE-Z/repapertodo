import 'package:collection/collection.dart';

import '../core/model/app_state.dart';
import '../core/model/json_helpers.dart';
import '../core/model/paper_data.dart';
import '../core/model/paper_item.dart';
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
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      return const [];
    }
    final stamp = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();
    final operations = <SyncOperation>[];
    var sequence = startSequence;

    void add(SyncOperationKind kind, JsonMap payload) {
      sequence += 1;
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
        add(SyncOperationKind.upsertPaper, {'paper': current.toJson()});
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
    final beforeJson = before.toJson();
    final afterJson = after.toJson();
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
        {'paperId': after.id, 'content': after.content},
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
          'paperId': after.id,
          'itemId': itemId,
        });
      }
    }
    for (final entry in afterItems.entries) {
      final previous = beforeItems[entry.key];
      final current = entry.value;
      if (previous == null ||
          !_deepEquals.equals(previous.toJson(), current.toJson())) {
        add(SyncOperationKind.upsertTodoItem, {
          'paperId': after.id,
          'item': current.toJson(),
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
        if (paper.id.trim().isNotEmpty) paper.id: paper,
    };
  }

  Map<String, PaperItem> _itemMap(List<PaperItem> items) {
    return {
      for (final item in items)
        if (item.id.trim().isNotEmpty) item.id: item,
    };
  }

  JsonMap _withoutKeys(JsonMap source, Set<String> keys) {
    return {
      for (final entry in source.entries)
        if (!keys.contains(entry.key)) entry.key: entry.value,
    };
  }
}

const _deepEquals = DeepCollectionEquality();
