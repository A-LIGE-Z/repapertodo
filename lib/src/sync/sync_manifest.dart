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
      stringValue(_wireValue(json, 'updatedAtUtc'), ''),
    );
    return SyncManifest(
      schemaVersion: _schemaVersionFromWire(_wireValue(json, 'schemaVersion')),
      updatedAtUtc: updatedAtUtc,
      latestSnapshotPath:
          _latestSnapshotPathFromWire(_wireValue(json, 'latestSnapshotPath')),
      deviceSequences: _deviceSequencesFromWire(
        _wireValue(json, 'deviceSequences'),
      ),
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

Object? _wireValue(JsonMap json, String key) {
  if (json.containsKey(key)) {
    return json[key];
  }
  final normalizedKey = key.toLowerCase();
  for (final entry in json.entries) {
    if (entry.key.toLowerCase() == normalizedKey) {
      return entry.value;
    }
  }
  return null;
}

int _schemaVersionFromWire(Object? value) {
  final schemaVersion = _positiveIntegerFromWire(value);
  if (schemaVersion != null) {
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
  if (value == null) {
    return const <String, int>{};
  }
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
  final sequence = _positiveIntegerFromWire(value);
  if (sequence != null) {
    return sequence;
  }
  throw FormatException(
    'Sync manifest device sequence must be a positive integer: $value',
  );
}

int? _positiveIntegerFromWire(Object? value) {
  if (value is num && value.isFinite && value % 1 == 0) {
    final integer = value.toInt();
    return integer > 0 ? integer : null;
  }
  if (value is String) {
    final integer = int.tryParse(value.trim());
    if (integer != null && integer > 0) {
      return integer;
    }
  }
  return null;
}

DateTime _updatedAtUtcFromWire(String value) {
  final parsed = DateTime.tryParse(value.trim())?.toUtc();
  if (parsed == null) {
    throw FormatException('Sync manifest updatedAtUtc must be valid: $value');
  }
  return parsed;
}
