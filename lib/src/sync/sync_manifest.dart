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
    final updatedAtUtc = _updatedAtUtcFromWire(
      stringValue(json['updatedAtUtc'], ''),
    );
    return SyncManifest(
      schemaVersion: _schemaVersionFromWire(json['schemaVersion']),
      updatedAtUtc: updatedAtUtc,
      latestSnapshotPath:
          _latestSnapshotPathFromWire(json['latestSnapshotPath']),
      deviceSequences: _deviceSequencesFromWire(json['deviceSequences']),
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

int _schemaVersionFromWire(Object? value) {
  if (value is num && value.isFinite && value % 1 == 0) {
    final schemaVersion = value.toInt();
    if (schemaVersion == 1) {
      return schemaVersion;
    }
  }
  throw FormatException(
    'Unsupported sync manifest schemaVersion: $value',
  );
}

String _latestSnapshotPathFromWire(Object? value) {
  if (value is String) {
    return value;
  }
  throw FormatException(
    'Sync manifest latestSnapshotPath must be a string: $value',
  );
}

Map<String, int> _deviceSequencesFromWire(Object? value) {
  if (value is! Map) {
    throw FormatException(
      'Sync manifest deviceSequences must be a JSON object: $value',
    );
  }
  final deviceSequences = <String, int>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException(
        'Sync manifest deviceSequences keys must be strings: $key',
      );
    }
    final deviceId = normalizeSyncDeviceId(key, fallback: '');
    if (deviceId.isEmpty) {
      throw FormatException(
        'Sync manifest deviceSequences contains invalid device id: $key',
      );
    }
    final sequence = _deviceSequenceFromWire(entry.value);
    final previous = deviceSequences[deviceId] ?? 0;
    if (sequence > previous) {
      deviceSequences[deviceId] = sequence;
    }
  }
  return deviceSequences;
}

int _deviceSequenceFromWire(Object? value) {
  if (value is num && value.isFinite && value % 1 == 0) {
    final sequence = value.toInt();
    if (sequence > 0) {
      return sequence;
    }
  }
  throw FormatException(
    'Sync manifest device sequence must be a positive integer: $value',
  );
}

DateTime _updatedAtUtcFromWire(String value) {
  final parsed = DateTime.tryParse(value.trim())?.toUtc();
  if (parsed == null) {
    throw FormatException('Sync manifest updatedAtUtc must be valid: $value');
  }
  return parsed;
}
