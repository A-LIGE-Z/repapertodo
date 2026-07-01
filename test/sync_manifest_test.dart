import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('decodes manifest timestamps as UTC', () {
    final manifest = SyncManifest.fromJson({
      'schemaVersion': 1,
      'updatedAtUtc': '2026-07-01T10:30:00+08:00',
      'latestSnapshotPath': 'repapertodo/snapshots/local.json',
      'deviceSequences': {'win-device': 2},
    });

    expect(manifest.updatedAtUtc, DateTime.utc(2026, 7, 1, 2, 30));
    expect(manifest.deviceSequences, {'win-device': 2});
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

  test('rejects unsupported manifest schema versions', () {
    for (final schemaVersion in const <Object?>[null, 0, 2, 1.2, '1']) {
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

  test('rejects invalid manifest timestamps', () {
    for (final updatedAtUtc in const ['', 'not-a-date']) {
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
