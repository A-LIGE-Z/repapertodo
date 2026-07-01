import '../core/model/json_helpers.dart';
import 'sync_device_id.dart';

class SyncManifest {
  SyncManifest({
    required this.schemaVersion,
    required this.updatedAtUtc,
    required this.latestSnapshotPath,
    Map<String, int>? deviceSequences,
  }) : deviceSequences = normalizeSyncDeviceSequences(deviceSequences);

  final int schemaVersion;
  final DateTime updatedAtUtc;
  final String latestSnapshotPath;
  final Map<String, int> deviceSequences;

  factory SyncManifest.empty() {
    return SyncManifest(
      schemaVersion: 1,
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      latestSnapshotPath: '',
    );
  }

  factory SyncManifest.fromJson(JsonMap json) {
    final rawSequences = json['deviceSequences'];
    final updatedAtUtc = _updatedAtUtcFromWire(
      stringValue(json['updatedAtUtc'], ''),
    );
    return SyncManifest(
      schemaVersion: intValue(json['schemaVersion'], 1),
      updatedAtUtc: updatedAtUtc,
      latestSnapshotPath: stringValue(json['latestSnapshotPath'], ''),
      deviceSequences: {
        if (rawSequences is Map)
          for (final entry in rawSequences.entries)
            if (entry.key is String && entry.value is num)
              entry.key as String: (entry.value as num).round(),
      },
    );
  }

  JsonMap toJson() {
    return {
      'schemaVersion': schemaVersion,
      'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
      'latestSnapshotPath': latestSnapshotPath,
      'deviceSequences': deviceSequences,
    };
  }
}

DateTime _updatedAtUtcFromWire(String value) {
  final parsed = DateTime.tryParse(value.trim())?.toUtc();
  if (parsed == null) {
    throw FormatException('Sync manifest updatedAtUtc must be valid: $value');
  }
  return parsed;
}
