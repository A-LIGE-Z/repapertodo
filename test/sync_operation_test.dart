import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('normalizes device ids when decoding operations', () {
    final operation = SyncOperation.fromJson({
      'id': 'legacy-operation-id',
      'deviceId': ' Device A ',
      'sequence': 2,
      'kind': 'updateNoteContent',
      'createdAtUtc': '2026-07-01T10:00:00+08:00',
      'payload': {'paperId': 'note', 'content': 'Remote'},
    });

    expect(operation.id, 'legacy-operation-id');
    expect(operation.deviceId, 'device-a');
    expect(operation.sequence, 2);
    expect(operation.kind, SyncOperationKind.updateNoteContent);
    expect(operation.createdAtUtc, DateTime.utc(2026, 7, 1, 2));
    expect(operation.payload, {'paperId': 'note', 'content': 'Remote'});
  });

  test('keeps invalid decoded device ids empty', () {
    final operation = SyncOperation.fromJson({
      'id': 'invalid-device-id',
      'deviceId': 'bad',
      'sequence': 3,
      'kind': 'deletePaper',
      'createdAtUtc': '2026-07-01T09:00:00Z',
      'payload': {'paperId': 'ignored'},
    });

    expect(operation.deviceId, isEmpty);
    expect(operation.kind, SyncOperationKind.deletePaper);
  });
}
