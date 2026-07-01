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
