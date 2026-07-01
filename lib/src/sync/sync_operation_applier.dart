import '../core/model/app_state.dart';
import '../core/model/json_helpers.dart';
import '../core/model/paper_data.dart';
import '../core/model/paper_item.dart';
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
    final sortedOperations =
        operations.map(_normalizeOperation).whereType<SyncOperation>().toList()
          ..sort((a, b) {
            final deviceComparison = a.deviceId.compareTo(b.deviceId);
            if (deviceComparison != 0) {
              return deviceComparison;
            }
            return a.sequence.compareTo(b.sequence);
          });

    var appliedCount = 0;
    for (final operation in sortedOperations) {
      final previousSequence = sequences[operation.deviceId] ?? 0;
      if (operation.sequence <= previousSequence) {
        continue;
      }
      _applyOperation(state, operation);
      sequences[operation.deviceId] = operation.sequence;
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
    if (deviceId.isEmpty || operation.sequence <= 0) {
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
    final paperJson = _jsonMapOrNull(payload['paper']);
    if (paperJson == null) {
      return;
    }
    final paper = PaperData.fromJson(paperJson);
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
        state.papers.indexWhere((candidate) => candidate.id == paper.id);
    if (index < 0) {
      state.papers.add(paper);
    } else {
      state.papers[index] = paper;
    }
  }

  void _deletePaper(AppState state, JsonMap payload, DateTime deletedAtUtc) {
    final paperId = stringValue(payload['paperId'], '');
    if (paperId.isEmpty) {
      return;
    }
    state.sync.markPaperDeleted(paperId, deletedAtUtc);
    state.papers.removeWhere((paper) => paper.id == paperId);
    for (final paper in state.papers) {
      for (final item in paper.items) {
        if (item.linkedNoteId == paperId) {
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
    final paperId = stringValue(payload['paperId'], '');
    final itemJson = _jsonMapOrNull(payload['item']);
    if (paperId.isEmpty || itemJson == null) {
      return;
    }
    final paperDeletedAtUtc = state.sync.paperDeletedAtUtc(paperId);
    if (paperDeletedAtUtc != null &&
        !_isNewerOperation(createdAtUtc, paperDeletedAtUtc)) {
      return;
    }
    final paper =
        state.papers.where((paper) => paper.id == paperId).firstOrNull;
    if (paper == null || !paper.isTodo) {
      return;
    }
    state.sync.clearPaperDeleted(paperId);
    final item = PaperItem.fromJson(itemJson);
    if (_shouldSkipTodoItemUpsert(
      state,
      paperId,
      item.id,
      createdAtUtc,
    )) {
      return;
    }
    final index =
        paper.items.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) {
      paper.items.add(item);
    } else {
      paper.items[index] = item;
    }
  }

  void _deleteTodoItem(AppState state, JsonMap payload, DateTime deletedAtUtc) {
    final paperId = stringValue(payload['paperId'], '');
    final itemId = stringValue(payload['itemId'], '');
    if (paperId.isEmpty || itemId.isEmpty) {
      return;
    }
    state.sync.markTodoItemDeleted(paperId, itemId, deletedAtUtc);
    final paper =
        state.papers.where((paper) => paper.id == paperId).firstOrNull;
    if (paper == null || !paper.isTodo) {
      return;
    }
    paper.items.removeWhere((item) => item.id == itemId);
  }

  void _updateNoteContent(
    AppState state,
    JsonMap payload,
    DateTime createdAtUtc,
  ) {
    final paperId = stringValue(payload['paperId'], '');
    final content = stringValue(payload['content'], '');
    if (paperId.isEmpty) {
      return;
    }
    final paperDeletedAtUtc = state.sync.paperDeletedAtUtc(paperId);
    if (paperDeletedAtUtc != null &&
        !_isNewerOperation(createdAtUtc, paperDeletedAtUtc)) {
      return;
    }
    final paper =
        state.papers.where((paper) => paper.id == paperId).firstOrNull;
    if (paper == null || !paper.isNote) {
      return;
    }
    state.sync.clearPaperDeleted(paperId);
    paper.content = content;
  }

  void _updateSettings(AppState state, JsonMap payload) {
    final settings = _jsonMapOrNull(payload['settings']);
    if (settings == null || settings.isEmpty) {
      return;
    }
    final merged = {
      ...state.toJson(),
      ...settings,
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

JsonMap? _jsonMapOrNull(Object? value) {
  return value is Map ? Map<String, Object?>.from(value) : null;
}
