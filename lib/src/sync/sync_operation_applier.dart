import 'package:collection/collection.dart';

import '../core/model/app_state.dart';
import '../core/model/json_helpers.dart';
import '../core/model/paper_data.dart';
import '../core/model/paper_item.dart';
import '../core/state/papertodo_legacy_migration.dart';
import 'sync_device_id.dart';
import 'sync_operation.dart';

class SyncOperationApplyResult {
  const SyncOperationApplyResult({
    required this.state,
    required this.deviceSequences,
    required this.appliedCount,
  });

  final AppState state;
  final Map<String, int> deviceSequences;
  final int appliedCount;
}

class SyncOperationApplier {
  const SyncOperationApplier();

  SyncOperationApplyResult apply(
    AppState baseState,
    Iterable<SyncOperation> operations, {
    Map<String, int>? deviceSequences,
  }) {
    final state = AppState.fromJson(baseState.toJson());
    final sequences = normalizeSyncDeviceSequences(deviceSequences);
    final operationsByDevice = <String, List<SyncOperation>>{};
    for (final operation
        in operations.map(_normalizeOperation).whereType<SyncOperation>()) {
      operationsByDevice
          .putIfAbsent(operation.deviceId, () => <SyncOperation>[])
          .add(operation);
    }
    for (final deviceOperations in operationsByDevice.values) {
      deviceOperations.sort(_compareDeviceOperations);
    }

    var appliedCount = 0;
    final blockedDevices = <String>{};
    final cursors = <String, int>{
      for (final deviceId in operationsByDevice.keys) deviceId: 0,
    };
    final expectedSequences = <String, int>{
      for (final deviceId in operationsByDevice.keys)
        deviceId: (sequences[deviceId] ?? 0) + 1,
    };
    while (true) {
      SyncOperation? nextOperation;
      for (final entry in operationsByDevice.entries) {
        final deviceId = entry.key;
        if (blockedDevices.contains(deviceId)) {
          continue;
        }
        final deviceOperations = entry.value;
        var cursor = cursors[deviceId] ?? 0;
        final expectedSequence = expectedSequences[deviceId] ?? 1;
        while (cursor < deviceOperations.length &&
            deviceOperations[cursor].sequence < expectedSequence) {
          cursor++;
        }
        cursors[deviceId] = cursor;
        if (cursor >= deviceOperations.length) {
          continue;
        }
        final candidate = deviceOperations[cursor];
        if (candidate.sequence > expectedSequence) {
          continue;
        }
        if (_hasConflictingDuplicateAt(deviceOperations, cursor)) {
          blockedDevices.add(deviceId);
          continue;
        }
        if (nextOperation == null ||
            _compareReadyOperations(candidate, nextOperation) < 0) {
          nextOperation = candidate;
        }
      }
      if (nextOperation == null) {
        break;
      }
      _applyOperation(state, nextOperation);
      sequences[nextOperation.deviceId] = nextOperation.sequence;
      expectedSequences[nextOperation.deviceId] = nextOperation.sequence + 1;
      cursors[nextOperation.deviceId] =
          (cursors[nextOperation.deviceId] ?? 0) + 1;
      appliedCount++;
    }
    state.normalize();
    return SyncOperationApplyResult(
      state: state,
      deviceSequences: sequences,
      appliedCount: appliedCount,
    );
  }

  SyncOperation? _normalizeOperation(SyncOperation operation) {
    final deviceId = normalizeSyncDeviceId(operation.deviceId, fallback: '');
    if (deviceId.isEmpty || !isSyncDeviceSequenceInRange(operation.sequence)) {
      return null;
    }
    return SyncOperation(
      id: '$deviceId-${operation.sequence}',
      deviceId: deviceId,
      sequence: operation.sequence,
      kind: operation.kind,
      createdAtUtc: operation.createdAtUtc,
      payload: Map<String, Object?>.from(operation.payload),
    );
  }

  void _applyOperation(AppState state, SyncOperation operation) {
    switch (operation.kind) {
      case SyncOperationKind.stateSnapshot:
        return;
      case SyncOperationKind.upsertPaper:
        _upsertPaper(state, operation.payload, operation.createdAtUtc);
      case SyncOperationKind.deletePaper:
        _deletePaper(state, operation.payload, operation.createdAtUtc);
      case SyncOperationKind.upsertTodoItem:
        _upsertTodoItem(state, operation.payload, operation.createdAtUtc);
      case SyncOperationKind.deleteTodoItem:
        _deleteTodoItem(state, operation.payload, operation.createdAtUtc);
      case SyncOperationKind.updateNoteContent:
        _updateNoteContent(state, operation.payload, operation.createdAtUtc);
      case SyncOperationKind.updateSettings:
        _updateSettings(state, operation.payload);
    }
  }

  void _upsertPaper(
    AppState state,
    JsonMap payload,
    DateTime createdAtUtc,
  ) {
    final paperJson = _jsonMapOrNull(_payloadValue(payload, 'paper'));
    if (paperJson == null) {
      return;
    }
    final paper = PaperData.fromJson(_migratePaperPayload(paperJson));
    paper.id = paper.id.trim();
    for (final item in paper.items) {
      item.id = item.id.trim();
    }
    final deletedAtUtc = state.sync.paperDeletedAtUtc(paper.id);
    if (deletedAtUtc != null &&
        !_isNewerOperation(createdAtUtc, deletedAtUtc)) {
      return;
    }
    state.sync.clearPaperDeleted(paper.id);
    if (paper.isTodo) {
      paper.items.removeWhere((item) {
        return _shouldSkipTodoItemUpsert(
          state,
          paper.id,
          item.id,
          createdAtUtc,
        );
      });
    }
    final index =
        state.papers.indexWhere((candidate) => _paperId(candidate) == paper.id);
    if (index < 0) {
      state.papers.add(paper);
    } else {
      state.papers[index] = paper;
    }
  }

  void _deletePaper(AppState state, JsonMap payload, DateTime deletedAtUtc) {
    final paperId = _payloadStringId(payload, 'paperId');
    if (paperId.isEmpty) {
      return;
    }
    state.sync.markPaperDeleted(paperId, deletedAtUtc);
    state.papers.removeWhere((paper) => _paperId(paper) == paperId);
    for (final paper in state.papers) {
      for (final item in paper.items) {
        if (item.linkedNoteId?.trim() == paperId) {
          item.linkedNoteId = null;
        }
      }
    }
  }

  void _upsertTodoItem(
    AppState state,
    JsonMap payload,
    DateTime createdAtUtc,
  ) {
    final paperId = _payloadStringId(payload, 'paperId');
    final itemJson = _jsonMapOrNull(_payloadValue(payload, 'item'));
    if (paperId.isEmpty || itemJson == null) {
      return;
    }
    final paperDeletedAtUtc = state.sync.paperDeletedAtUtc(paperId);
    if (paperDeletedAtUtc != null &&
        !_isNewerOperation(createdAtUtc, paperDeletedAtUtc)) {
      return;
    }
    final paper =
        state.papers.where((paper) => _paperId(paper) == paperId).firstOrNull;
    if (paper == null || !paper.isTodo) {
      return;
    }
    paper.id = paperId;
    state.sync.clearPaperDeleted(paperId);
    final item = PaperItem.fromJson(_migrateTodoItemPayload(itemJson));
    item.id = item.id.trim();
    if (_shouldSkipTodoItemUpsert(
      state,
      paperId,
      item.id,
      createdAtUtc,
    )) {
      return;
    }
    final index =
        paper.items.indexWhere((candidate) => _itemId(candidate) == item.id);
    if (index < 0) {
      paper.items.add(item);
    } else {
      paper.items[index] = item;
    }
  }

  void _deleteTodoItem(AppState state, JsonMap payload, DateTime deletedAtUtc) {
    final paperId = _payloadStringId(payload, 'paperId');
    final itemId = _payloadStringId(payload, 'itemId');
    if (paperId.isEmpty || itemId.isEmpty) {
      return;
    }
    state.sync.markTodoItemDeleted(paperId, itemId, deletedAtUtc);
    final paper =
        state.papers.where((paper) => _paperId(paper) == paperId).firstOrNull;
    if (paper == null || !paper.isTodo) {
      return;
    }
    paper.id = paperId;
    paper.items.removeWhere((item) => _itemId(item) == itemId);
  }

  void _updateNoteContent(
    AppState state,
    JsonMap payload,
    DateTime createdAtUtc,
  ) {
    final paperId = _payloadStringId(payload, 'paperId');
    final content = stringValue(_payloadValue(payload, 'content'), '');
    if (paperId.isEmpty) {
      return;
    }
    final paperDeletedAtUtc = state.sync.paperDeletedAtUtc(paperId);
    if (paperDeletedAtUtc != null &&
        !_isNewerOperation(createdAtUtc, paperDeletedAtUtc)) {
      return;
    }
    final paper =
        state.papers.where((paper) => _paperId(paper) == paperId).firstOrNull;
    if (paper == null || !paper.isNote) {
      return;
    }
    paper.id = paperId;
    state.sync.clearPaperDeleted(paperId);
    paper.content = content;
  }

  void _updateSettings(AppState state, JsonMap payload) {
    final settings = _jsonMapOrNull(_payloadValue(payload, 'settings'));
    if (settings == null || settings.isEmpty) {
      return;
    }
    final migratedSettings = migrateLegacyPaperTodoJson(settings);
    final safeSettings = Map<String, Object?>.from(migratedSettings)
      ..remove('sync');
    if (safeSettings.isEmpty) {
      return;
    }
    final merged = {
      ...state.toJson(),
      ...safeSettings,
      'papers': state.papers.map((paper) => paper.toJson()).toList(),
    };
    final updated = AppState.fromJson(merged);
    state
      ..theme = updated.theme
      ..colorScheme = updated.colorScheme
      ..customThemeColorHex = updated.customThemeColorHex
      ..markdownRenderMode = updated.markdownRenderMode
      ..todoVisualSize = updated.todoVisualSize
      ..uiFontPreset = updated.uiFontPreset
      ..systemFontFamilyName = updated.systemFontFamilyName
      ..externalMarkdownExtension = updated.externalMarkdownExtension
      ..zoom = updated.zoom
      ..useCapsuleMode = updated.useCapsuleMode
      ..useDeepCapsuleMode = updated.useDeepCapsuleMode
      ..showTopBarNewTodoButton = updated.showTopBarNewTodoButton
      ..showTopBarNewNoteButton = updated.showTopBarNewNoteButton
      ..showTopBarExternalOpenButton = updated.showTopBarExternalOpenButton
      ..hidePapersFromWindowSwitcher = updated.hidePapersFromWindowSwitcher
      ..enableTodoNoteLinks = updated.enableTodoNoteLinks
      ..showTodoDueRelativeTime = updated.showTodoDueRelativeTime
      ..todoDueYearDisplayMode = updated.todoDueYearDisplayMode
      ..todoLineSpacing = updated.todoLineSpacing
      ..noteLineSpacing = updated.noteLineSpacing
      ..useTodoReminderInterval = updated.useTodoReminderInterval
      ..todoReminderIntervalValue = updated.todoReminderIntervalValue
      ..todoReminderIntervalUnit = updated.todoReminderIntervalUnit
      ..todoReminderScope = updated.todoReminderScope
      ..todoReminderBubbleDurationSeconds =
          updated.todoReminderBubbleDurationSeconds
      ..showLinkedNoteName = updated.showLinkedNoteName
      ..allowLongLinkedNoteTitles = updated.allowLongLinkedNoteTitles
      ..hideLinkedNotesFromCapsules = updated.hideLinkedNotesFromCapsules
      ..runLinkedScriptCapsulesOnClick = updated.runLinkedScriptCapsulesOnClick
      ..maxTitleLength = updated.maxTitleLength
      ..useCapsuleCollapseAll = updated.useCapsuleCollapseAll
      ..capsuleCollapseAllActive = updated.capsuleCollapseAllActive
      ..capsuleCollapseAllActiveQueues = updated.capsuleCollapseAllActiveQueues
      ..showDeepCapsuleWhileExpanded = updated.showDeepCapsuleWhileExpanded
      ..collapseExpandedDeepCapsuleOnClick =
          updated.collapseExpandedDeepCapsuleOnClick
      ..hideDeepCapsulesWhenCovered = updated.hideDeepCapsulesWhenCovered
      ..enableAnimations = updated.enableAnimations
      ..enableToolTips = updated.enableToolTips
      ..startAtLogin = updated.startAtLogin
      ..pinnedTodoHotKey = updated.pinnedTodoHotKey
      ..pinnedNoteHotKey = updated.pinnedNoteHotKey
      ..fullscreenTopmostMode = updated.fullscreenTopmostMode
      ..usePersistentPowerShellProcess = updated.usePersistentPowerShellProcess
      ..preferPowerShell7 = updated.preferPowerShell7
      ..hideScriptRunWindow = updated.hideScriptRunWindow
      ..deepCapsuleStartTopMargin = updated.deepCapsuleStartTopMargin
      ..deepCapsuleQueueStartTopMargins =
          updated.deepCapsuleQueueStartTopMargins
      ..deepCapsuleSide = updated.deepCapsuleSide
      ..deepCapsuleMonitorDeviceName = updated.deepCapsuleMonitorDeviceName
      ..sync = updated.sync
      ..extra = updated.extra;
  }

  bool _shouldSkipTodoItemUpsert(
    AppState state,
    String paperId,
    String itemId,
    DateTime createdAtUtc,
  ) {
    final deletedAtUtc = state.sync.todoItemDeletedAtUtc(paperId, itemId);
    if (deletedAtUtc == null) {
      return false;
    }
    if (!_isNewerOperation(createdAtUtc, deletedAtUtc)) {
      return true;
    }
    state.sync.clearTodoItemDeleted(paperId, itemId);
    return false;
  }

  bool _isNewerOperation(DateTime operationTime, DateTime tombstoneTime) {
    return operationTime.toUtc().isAfter(tombstoneTime.toUtc());
  }
}

bool _hasConflictingDuplicateAt(
  List<SyncOperation> operations,
  int cursor,
) {
  final operation = operations[cursor];
  for (var index = cursor + 1; index < operations.length; index += 1) {
    final duplicate = operations[index];
    if (duplicate.sequence != operation.sequence) {
      break;
    }
    if (!_operationsMatch(operation, duplicate)) {
      return true;
    }
  }
  return false;
}

bool _operationsMatch(SyncOperation left, SyncOperation right) {
  return left.id == right.id &&
      left.deviceId == right.deviceId &&
      left.sequence == right.sequence &&
      left.kind == right.kind &&
      left.createdAtUtc.toUtc().isAtSameMomentAs(right.createdAtUtc.toUtc()) &&
      const DeepCollectionEquality().equals(left.payload, right.payload);
}

JsonMap? _jsonMapOrNull(Object? value) {
  return value is Map ? Map<String, Object?>.from(value) : null;
}

Object? _payloadValue(JsonMap payload, String key) {
  if (payload.containsKey(key)) {
    return payload[key];
  }
  final normalizedKey = key.toLowerCase();
  for (final entry in payload.entries) {
    if (entry.key.toLowerCase() == normalizedKey) {
      return entry.value;
    }
  }
  return null;
}

String _payloadStringId(JsonMap payload, String key) {
  return stringValue(_payloadValue(payload, key), '').trim();
}

String _paperId(PaperData paper) {
  return paper.id.trim();
}

String _itemId(PaperItem item) {
  return item.id.trim();
}

JsonMap _migratePaperPayload(JsonMap paperJson) {
  final migrated = migrateLegacyPaperTodoJson({
    'papers': [paperJson],
  });
  final papers = jsonMapList(migrated['papers']);
  return papers.isEmpty ? paperJson : papers.first;
}

JsonMap _migrateTodoItemPayload(JsonMap itemJson) {
  final migrated = migrateLegacyPaperTodoJson({
    'papers': [
      {
        'items': [itemJson],
      },
    ],
  });
  final papers = jsonMapList(migrated['papers']);
  if (papers.isEmpty) {
    return itemJson;
  }
  final items = jsonMapList(papers.first['items']);
  return items.isEmpty ? itemJson : items.first;
}

int _compareDeviceOperations(SyncOperation left, SyncOperation right) {
  final sequenceComparison = left.sequence.compareTo(right.sequence);
  if (sequenceComparison != 0) {
    return sequenceComparison;
  }
  return _compareReadyOperations(left, right);
}

int _compareReadyOperations(SyncOperation left, SyncOperation right) {
  final timeComparison =
      left.createdAtUtc.toUtc().compareTo(right.createdAtUtc.toUtc());
  if (timeComparison != 0) {
    return timeComparison;
  }
  final deviceComparison = left.deviceId.compareTo(right.deviceId);
  if (deviceComparison != 0) {
    return deviceComparison;
  }
  final sequenceComparison = left.sequence.compareTo(right.sequence);
  if (sequenceComparison != 0) {
    return sequenceComparison;
  }
  return left.id.compareTo(right.id);
}
