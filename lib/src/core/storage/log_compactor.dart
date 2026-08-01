import '../../sync/sync_operation.dart';

/// Utility class for compacting operation logs to optimize memory and storage.
class OperationLogCompactor {
  const OperationLogCompactor();

  /// Compacts a list of [SyncOperation] entries by coalescing consecutive
  /// scalar updates targeting the same model ID and operation kind.
  List<SyncOperation> compact(List<SyncOperation> logs) {
    if (logs.length <= 1) return List<SyncOperation>.from(logs);

    final compacted = <SyncOperation>[];
    for (final log in logs) {
      if (compacted.isEmpty) {
        compacted.add(log);
        continue;
      }

      final last = compacted.last;
      // Coalesce if same device, same ID, same kind, and is a coalescable update
      if (last.deviceId == log.deviceId &&
          last.id == log.id &&
          last.kind == log.kind &&
          _isCoalescableKind(log.kind)) {
        // Replace last log with the newer log state while preserving initial start sequence
        compacted[compacted.length - 1] = SyncOperation(
          id: last.id,
          deviceId: last.deviceId,
          sequence: last.sequence,
          kind: log.kind,
          createdAtUtc: log.createdAtUtc,
          payload: log.payload,
        );
      } else {
        compacted.add(log);
      }
    }
    return compacted;
  }

  bool _isCoalescableKind(SyncOperationKind kind) {
    return kind == SyncOperationKind.upsertPaper ||
        kind == SyncOperationKind.upsertTodoItem ||
        kind == SyncOperationKind.updateNoteContent ||
        kind == SyncOperationKind.updateSettings;
  }
}
