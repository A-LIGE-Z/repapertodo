import '../core/model/json_helpers.dart';
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
      stringValue(json['deviceId'], ''),
      fallback: '',
    );
    final kind = _kindFromWire(stringValue(json['kind'], ''));
    final createdAtUtc = _createdAtUtcFromWire(
      stringValue(json['createdAtUtc'], ''),
    );
    return SyncOperation(
      id: stringValue(json['id'], ''),
      deviceId: deviceId,
      sequence: _sequenceFromWire(json['sequence']),
      kind: kind,
      createdAtUtc: createdAtUtc,
      payload: json['payload'] is Map
          ? Map<String, Object?>.from(json['payload'] as Map)
          : <String, Object?>{},
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
  for (final kind in SyncOperationKind.values) {
    if (_kindToWire(kind) == value) {
      return kind;
    }
  }
  throw FormatException('Unknown sync operation kind: $value');
}

int _sequenceFromWire(Object? value) {
  if (value is num && value.isFinite && value % 1 == 0) {
    final sequence = value.toInt();
    if (sequence > 0) {
      return sequence;
    }
  }
  throw FormatException(
    'Sync operation sequence must be a positive integer: $value',
  );
}

DateTime _createdAtUtcFromWire(String value) {
  final parsed = DateTime.tryParse(value.trim())?.toUtc();
  if (parsed == null) {
    throw FormatException('Sync operation createdAtUtc must be valid: $value');
  }
  return parsed;
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
