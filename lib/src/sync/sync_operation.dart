import '../core/model/json_helpers.dart';

enum SyncOperationKind {
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
    return SyncOperation(
      id: stringValue(json['id'], ''),
      deviceId: stringValue(json['deviceId'], ''),
      sequence: intValue(json['sequence'], 0),
      kind: _kindFromWire(stringValue(json['kind'], '')),
      createdAtUtc: DateTime.tryParse(stringValue(json['createdAtUtc'], ''))?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      payload: json['payload'] is Map ? Map<String, Object?>.from(json['payload'] as Map) : <String, Object?>{},
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
  return SyncOperationKind.values.firstWhere(
    (kind) => _kindToWire(kind) == value,
    orElse: () => SyncOperationKind.updateSettings,
  );
}

String _kindToWire(SyncOperationKind kind) {
  return switch (kind) {
    SyncOperationKind.upsertPaper => 'upsertPaper',
    SyncOperationKind.deletePaper => 'deletePaper',
    SyncOperationKind.upsertTodoItem => 'upsertTodoItem',
    SyncOperationKind.deleteTodoItem => 'deleteTodoItem',
    SyncOperationKind.updateNoteContent => 'updateNoteContent',
    SyncOperationKind.updateSettings => 'updateSettings',
  };
}

