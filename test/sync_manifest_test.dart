import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('decodes manifest timestamps as UTC', () {
    final manifest = SyncManifest.fromJson({
      'schemaVersion': 1,
      'updatedAtUtc': '2026-07-01T10:30:00+08:00',
      'latestSnapshotPath': 'repapertodo/snapshots/local.json',
      'deviceSequences': {
        'win-device': 2,
        ' Device A ': 1,
        'device-a': 3,
      },
    });

    expect(manifest.updatedAtUtc, DateTime.utc(2026, 7, 1, 2, 30));
    expect(manifest.deviceSequences, {
      'win-device': 2,
      'device-a': 3,
    });

    final lowerZManifest = SyncManifest.fromJson({
      'schemaVersion': 1,
      'updatedAtUtc': '2026-07-01T10:30:00z',
      'latestSnapshotPath': 'repapertodo/snapshots/local.json',
    });
    expect(lowerZManifest.updatedAtUtc, DateTime.utc(2026, 7, 1, 10, 30));
  });

  test('decodes manifest wire keys case-insensitively', () {
    final manifest = SyncManifest.fromJson({
      'SCHEMAVERSION': '1',
      'UPDATEDATUTC': '2026-07-01T10:30:00+08:00',
      'LATESTSNAPSHOTPATH': 'repapertodo/snapshots/legacy.json',
      'DEVICESEQUENCES': {
        ' Device A ': '1',
        'device-a': '3',
      },
    });

    expect(manifest.schemaVersion, 1);
    expect(manifest.updatedAtUtc, DateTime.utc(2026, 7, 1, 2, 30));
    expect(manifest.latestSnapshotPath, 'repapertodo/snapshots/legacy.json');
    expect(manifest.deviceSequences, {'device-a': 3});
  });

  test('keeps modern manifest wire keys ahead of duplicate legacy keys', () {
    final manifest = SyncManifest.fromJson({
      'schemaVersion': 1,
      'SCHEMAVERSION': 2,
      'updatedAtUtc': '2026-07-01T10:30:00Z',
      'UPDATEDATUTC': 'not-a-date',
      'latestSnapshotPath': 'repapertodo/snapshots/modern.json',
      'LATESTSNAPSHOTPATH': 7,
      'deviceSequences': {'device-modern': 4},
      'DEVICESEQUENCES': {'device-legacy': 1},
    });

    expect(manifest.schemaVersion, 1);
    expect(manifest.updatedAtUtc, DateTime.utc(2026, 7, 1, 10, 30));
    expect(manifest.latestSnapshotPath, 'repapertodo/snapshots/modern.json');
    expect(manifest.deviceSequences, {'device-modern': 4});
  });

  test('allows empty manifest snapshot paths', () {
    final manifest = SyncManifest.fromJson({
      'schemaVersion': 1,
      'updatedAtUtc': '1970-01-01T00:00:00.000Z',
      'latestSnapshotPath': '',
      'deviceSequences': const <String, Object?>{},
    });

    expect(manifest.latestSnapshotPath, isEmpty);
  });

  test('allows missing manifest device sequences as an empty map', () {
    final manifest = SyncManifest.fromJson({
      'schemaVersion': 1,
      'updatedAtUtc': '2026-07-01T10:30:00Z',
      'latestSnapshotPath': 'repapertodo/snapshots/local.json',
    });

    expect(manifest.deviceSequences, isEmpty);
  });

  test('accepts maximum manifest device sequence wire values', () {
    for (final sequence in const <Object?>[
      maxSyncDeviceSequence,
      '$maxSyncDeviceSequence',
    ]) {
      final manifest = SyncManifest.fromJson({
        'schemaVersion': 1,
        'updatedAtUtc': '2026-07-01T10:30:00Z',
        'latestSnapshotPath': 'repapertodo/snapshots/local.json',
        'deviceSequences': {'device-a': sequence},
      });

      expect(
        manifest.deviceSequences,
        {'device-a': maxSyncDeviceSequence},
        reason: '$sequence',
      );
    }
  });

  test('rejects unsupported manifest schema versions', () {
    for (final schemaVersion in const <Object?>[
      null,
      0,
      2,
      1.2,
      '1.2',
      ' 1',
      '1 ',
    ]) {
      expect(
        () => SyncManifest.fromJson({
          'schemaVersion': schemaVersion,
          'updatedAtUtc': '2026-07-01T10:30:00Z',
          'latestSnapshotPath': 'repapertodo/snapshots/local.json',
          'deviceSequences': const <String, Object?>{},
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported sync manifest schemaVersion'),
          ),
        ),
        reason: '$schemaVersion',
      );
    }
  });

  test('rejects invalid manifest snapshot paths', () {
    for (final latestSnapshotPath in const <Object?>[
      null,
      7,
      ['snapshot.json'],
    ]) {
      expect(
        () => SyncManifest.fromJson({
          'schemaVersion': 1,
          'updatedAtUtc': '2026-07-01T10:30:00Z',
          'latestSnapshotPath': latestSnapshotPath,
          'deviceSequences': const <String, Object?>{},
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('latestSnapshotPath must be a string'),
          ),
        ),
        reason: '$latestSnapshotPath',
      );
    }
  });

  test('rejects invalid manifest device sequence maps', () {
    for (final deviceSequences in const <Object?>[
      ['device-a'],
      {7: 1},
      {'bad': 1},
      {'device-a': 0},
      {'device-a': -1},
      {'device-a': 1.2},
      {'device-a': '1.2'},
      {'device-a': ' 1'},
      {'device-a': '1 '},
      {'device-a': maxSyncDeviceSequence + 1},
      {'device-a': '${maxSyncDeviceSequence + 1}'},
      {'device-a': 'not-a-number'},
    ]) {
      expect(
        () => SyncManifest.fromJson({
          'schemaVersion': 1,
          'updatedAtUtc': '2026-07-01T10:30:00Z',
          'latestSnapshotPath': 'repapertodo/snapshots/local.json',
          'deviceSequences': deviceSequences,
        }),
        throwsA(isA<FormatException>()),
        reason: '$deviceSequences',
      );
    }
  });

  test('rejects invalid manifest timestamps', () {
    for (final updatedAtUtc in const [
      '',
      'not-a-date',
      '2026-13-01T10:30:00Z',
      '2026-02-30T10:30:00Z',
      '2026-07-01T24:00:00Z',
      '2026-07-01T10:30:00',
      '2026-07-01T10:30:00.1234567Z',
      ' 2026-07-01T10:30:00Z',
      '2026-07-01T10:30:00Z ',
    ]) {
      expect(
        () => SyncManifest.fromJson({
          'schemaVersion': 1,
          'updatedAtUtc': updatedAtUtc,
          'latestSnapshotPath': 'repapertodo/snapshots/local.json',
          'deviceSequences': const <String, Object?>{},
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('updatedAtUtc must be valid'),
          ),
        ),
        reason: updatedAtUtc,
      );
    }
  });
}
