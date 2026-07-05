import '../core/model/json_helpers.dart';
import '../core/model/sync_wire_datetime.dart';
import 'sync_device_id.dart';

enum SyncOperationKind {
  stateSnapshot,
  upsertPaper,
  deletePaper,
  upsertTodoItem,
  deleteTodoItem,
  updateNoteContent,
  updateSettings,
}

class SyncOperation {
  SyncOperation({
    required this.id,
    required this.deviceId,
    required this.sequence,
    required this.kind,
    required this.createdAtUtc,
    required this.payload,
  });

  final String id;
  final String deviceId;
  final int sequence;
  final SyncOperationKind kind;
  final DateTime createdAtUtc;
  final JsonMap payload;

  factory SyncOperation.fromJson(JsonMap json) {
    final deviceId = normalizeSyncDeviceId(
      stringValue(_wireValue(json, 'deviceId'), ''),
      fallback: '',
    );
    final kind = _kindFromWire(stringValue(_wireValue(json, 'kind'), ''));
    final createdAtUtc = _createdAtUtcFromWire(
      stringValue(_wireValue(json, 'createdAtUtc'), ''),
    );
    return SyncOperation(
      id: stringValue(_wireValue(json, 'id'), ''),
      deviceId: deviceId,
      sequence: _sequenceFromWire(_wireValue(json, 'sequence')),
      kind: kind,
      createdAtUtc: createdAtUtc,
      payload: _payloadFromWire(_wireValue(json, 'payload')),
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'sequence': sequence,
      'kind': _kindToWire(kind),
      'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      'payload': payload,
    };
  }
}

SyncOperationKind _kindFromWire(String value) {
  final normalizedValue = value.trim();
  for (final kind in SyncOperationKind.values) {
    if (_kindToWire(kind) == normalizedValue) {
      return kind;
    }
  }
  final lowerValue = normalizedValue.toLowerCase();
  for (final kind in SyncOperationKind.values) {
    if (_kindToWire(kind).toLowerCase() == lowerValue) {
      return kind;
    }
  }
  throw FormatException('Unknown sync operation kind: $value');
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

int _sequenceFromWire(Object? value) {
  if (value is String && value.trim() == value) {
    final sequence = int.tryParse(value);
    if (sequence != null && isSyncDeviceSequenceInRange(sequence)) {
      return sequence;
    }
  }
  if (value is num && value.isFinite && value % 1 == 0) {
    final sequence = value.toInt();
    if (isSyncDeviceSequenceInRange(sequence)) {
      return sequence;
    }
  }
  throw FormatException(
    'Sync operation sequence must be a positive integer no greater than '
    '$maxSyncDeviceSequence: $value',
  );
}

JsonMap _payloadFromWire(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'Sync operation payload must be a JSON object.',
    );
  }
  return Map<String, Object?>.from(value);
}

DateTime _createdAtUtcFromWire(String value) {
  return parseStrictSyncWireDateTimeUtc(
    value,
    fieldName: 'Sync operation createdAtUtc',
  );
}

String _kindToWire(SyncOperationKind kind) {
  return switch (kind) {
    SyncOperationKind.stateSnapshot => 'stateSnapshot',
    SyncOperationKind.upsertPaper => 'upsertPaper',
    SyncOperationKind.deletePaper => 'deletePaper',
    SyncOperationKind.upsertTodoItem => 'upsertTodoItem',
    SyncOperationKind.deleteTodoItem => 'deleteTodoItem',
    SyncOperationKind.updateNoteContent => 'updateNoteContent',
    SyncOperationKind.updateSettings => 'updateSettings',
  };
}
