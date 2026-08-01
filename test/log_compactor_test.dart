import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/core/storage/log_compactor.dart';
import 'package:repapertodo/src/sync/sync_operation.dart';

void main() {
  test('OperationLogCompactor coalesces consecutive upsert operations', () {
    const compactor = OperationLogCompactor();
    final logs = [
      SyncOperation(
        id: 'op-1',
        deviceId: 'dev-1',
        sequence: 1,
        kind: SyncOperationKind.upsertPaper,
        createdAtUtc: DateTime.now().toUtc(),
        payload: {'title': 'A'},
      ),
      SyncOperation(
        id: 'op-1',
        deviceId: 'dev-1',
        sequence: 2,
        kind: SyncOperationKind.upsertPaper,
        createdAtUtc: DateTime.now().toUtc(),
        payload: {'title': 'AB'},
      ),
      SyncOperation(
        id: 'op-1',
        deviceId: 'dev-1',
        sequence: 3,
        kind: SyncOperationKind.upsertPaper,
        createdAtUtc: DateTime.now().toUtc(),
        payload: {'title': 'ABC'},
      ),
    ];

    final result = compactor.compact(logs);
    expect(result.length, 1);
    expect(result.first.sequence, 1);
    expect(result.first.payload['title'], 'ABC');
  });
}
