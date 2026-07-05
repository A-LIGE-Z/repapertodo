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

    final lowerZOperation = SyncOperation.fromJson({
      'id': 'lower-z-operation',
      'deviceId': 'device-a',
      'sequence': 3,
      'kind': 'updateSettings',
      'createdAtUtc': '2026-07-01T10:00:00z',
      'payload': const <String, Object?>{},
    });
    expect(lowerZOperation.createdAtUtc, DateTime.utc(2026, 7, 1, 10));
  });

  test('decodes legacy operation wire keys case-insensitively', () {
    final operation = SyncOperation.fromJson({
      'ID': 'legacy-operation-id',
      'DEVICEID': ' Device A ',
      'SEQUENCE': '7',
      'KIND': 'UpdateNoteContent',
      'CREATEDATUTC': '2026-07-01T10:00:00+08:00',
      'PAYLOAD': {'PaperId': 'note', 'Content': 'Remote'},
    });

    expect(operation.id, 'legacy-operation-id');
    expect(operation.deviceId, 'device-a');
    expect(operation.sequence, 7);
    expect(operation.kind, SyncOperationKind.updateNoteContent);
    expect(operation.createdAtUtc, DateTime.utc(2026, 7, 1, 2));
    expect(operation.payload, {'PaperId': 'note', 'Content': 'Remote'});
  });

  test('keeps modern operation wire keys ahead of legacy duplicates', () {
    final operation = SyncOperation.fromJson({
      'ID': 'legacy-id',
      'id': 'modern-id',
      'DeviceId': 'device-legacy',
      'deviceId': 'device-modern',
      'Sequence': 1,
      'sequence': 2,
      'Kind': 'deletePaper',
      'kind': 'updateSettings',
      'CreatedAtUtc': '2026-07-01T09:00:00Z',
      'createdAtUtc': '2026-07-01T10:00:00Z',
      'Payload': {'legacy': true},
      'payload': {'modern': true},
    });

    expect(operation.id, 'modern-id');
    expect(operation.deviceId, 'device-modern');
    expect(operation.sequence, 2);
    expect(operation.kind, SyncOperationKind.updateSettings);
    expect(operation.createdAtUtc, DateTime.utc(2026, 7, 1, 10));
    expect(operation.payload, {'modern': true});
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

  test('accepts maximum operation sequence wire values', () {
    for (final sequence in const <Object?>[
      maxSyncDeviceSequence,
      '$maxSyncDeviceSequence',
    ]) {
      final operation = SyncOperation.fromJson({
        'id': 'max-sequence',
        'deviceId': 'device-a',
        'sequence': sequence,
        'kind': 'updateSettings',
        'createdAtUtc': '2026-07-01T09:00:00Z',
        'payload': const <String, Object?>{},
      });

      expect(operation.sequence, maxSyncDeviceSequence, reason: '$sequence');
    }
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
    for (final sequence in const <Object?>[
      null,
      0,
      -1,
      1.2,
      '1.2',
      ' 1',
      '1 ',
      'not-a-number',
      maxSyncDeviceSequence + 1,
      '${maxSyncDeviceSequence + 1}',
    ]) {
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
    for (final createdAtUtc in const [
      '',
      'not-a-date',
      '2026-13-01T09:00:00Z',
      '2026-02-30T09:00:00Z',
      '2026-07-01T24:00:00Z',
      '2026-07-01T09:00:00',
      '2026-07-01T09:00:00.1234567Z',
      ' 2026-07-01T09:00:00Z',
      '2026-07-01T09:00:00Z ',
    ]) {
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
