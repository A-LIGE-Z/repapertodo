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

  test('rejects unknown operation kinds', () {
    for (final kind in const ['', 'futureOperation']) {
      expect(
        () => SyncOperation.fromJson({
          'id': 'future-operation',
          'deviceId': 'device-a',
          'sequence': 4,
          'kind': kind,
          'createdAtUtc': '2026-07-01T09:00:00Z',
          'payload': const <String, Object?>{},
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unknown sync operation kind'),
          ),
        ),
        reason: kind,
      );
    }
  });

  test('rejects invalid operation sequences', () {
    for (final sequence in const <Object?>[null, 0, -1, 1.2, '1']) {
      expect(
        () => SyncOperation.fromJson({
          'id': 'invalid-sequence',
          'deviceId': 'device-a',
          'sequence': sequence,
          'kind': 'updateSettings',
          'createdAtUtc': '2026-07-01T09:00:00Z',
          'payload': const <String, Object?>{},
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('sequence must be a positive integer'),
          ),
        ),
        reason: '$sequence',
      );
    }
  });

  test('rejects invalid operation payloads', () {
    for (final payload in const <Object?>[
      null,
      'bad-payload',
      ['bad'],
    ]) {
      expect(
        () => SyncOperation.fromJson({
          'id': 'invalid-payload',
          'deviceId': 'device-a',
          'sequence': 5,
          'kind': 'updateSettings',
          'createdAtUtc': '2026-07-01T09:00:00Z',
          'payload': payload,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('payload must be a JSON object'),
          ),
        ),
        reason: '$payload',
      );
    }
  });

  test('rejects invalid operation timestamps', () {
    for (final createdAtUtc in const ['', 'not-a-date']) {
      expect(
        () => SyncOperation.fromJson({
          'id': 'invalid-timestamp',
          'deviceId': 'device-a',
          'sequence': 5,
          'kind': 'updateSettings',
          'createdAtUtc': createdAtUtc,
          'payload': const <String, Object?>{},
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('createdAtUtc must be valid'),
          ),
        ),
        reason: createdAtUtc,
      );
    }
  });
}
