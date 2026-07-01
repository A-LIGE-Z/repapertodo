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
    return SyncOperation(
      id: stringValue(json['id'], ''),
      deviceId: deviceId,
      sequence: intValue(json['sequence'], 0),
      kind: kind,
      createdAtUtc:
          DateTime.tryParse(stringValue(json['createdAtUtc'], ''))?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
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
