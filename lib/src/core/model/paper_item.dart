import 'json_helpers.dart';
import 'paper_constants.dart';

class PaperItem {
  PaperItem({
    required this.id,
    this.text = '',
    this.done = false,
    this.order = 0,
    this.todoColumnCount = 1,
    List<String>? todoExtraColumns,
    List<double>? todoColumnWidths,
    this.linkedNoteId,
    this.dueAtLocal,
    this.reminderIntervalValue,
    this.reminderIntervalUnit,
    JsonMap? extra,
  })  : todoExtraColumns = todoExtraColumns ?? <String>[],
        todoColumnWidths = todoColumnWidths ?? <double>[],
        extra = extra ?? <String, Object?>{};

  static const _knownKeys = {
    'id',
    'text',
    'done',
    'order',
    'todoColumnCount',
    'todoExtraColumns',
    'todoColumnWidths',
    'linkedNoteId',
    'dueAtLocal',
    'reminderIntervalValue',
    'reminderIntervalUnit',
  };

  String id;
  String text;
  bool done;
  int order;
  int todoColumnCount;
  List<String> todoExtraColumns;
  List<double> todoColumnWidths;
  String? linkedNoteId;
  String? dueAtLocal;
  int? reminderIntervalValue;
  String? reminderIntervalUnit;
  JsonMap extra;

  factory PaperItem.fromJson(JsonMap json) {
    return PaperItem(
      id: stringValue(json['id'], ''),
      text: stringValue(json['text'], ''),
      done: boolValue(json['done'], false),
      order: intValue(json['order'], 0),
      todoColumnCount: intValue(json['todoColumnCount'], 1),
      todoExtraColumns: stringList(json['todoExtraColumns']),
      todoColumnWidths: doubleList(json['todoColumnWidths']),
      linkedNoteId: json['linkedNoteId'] is String
          ? json['linkedNoteId'] as String
          : null,
      dueAtLocal:
          json['dueAtLocal'] is String ? json['dueAtLocal'] as String : null,
      reminderIntervalValue: json['reminderIntervalValue'] == null
          ? null
          : intValue(json['reminderIntervalValue'], 0),
      reminderIntervalUnit: json['reminderIntervalUnit'] is String
          ? json['reminderIntervalUnit'] as String
          : null,
      extra: preserveUnknown(json, _knownKeys),
    )..normalize();
  }

  void normalize() {
    if (id.trim().isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    }
    todoExtraColumns = [...todoExtraColumns];
    todoColumnWidths = [...todoColumnWidths];
    todoColumnCount = todoColumnCount
        .clamp(TodoColumnLimits.minCount, TodoColumnLimits.maxCount)
        .toInt();
    while (todoExtraColumns.length < todoColumnCount - 1) {
      todoExtraColumns.add('');
    }
    if (todoExtraColumns.length > todoColumnCount - 1) {
      todoExtraColumns = todoExtraColumns.sublist(0, todoColumnCount - 1);
    }
    while (todoColumnWidths.length < todoColumnCount) {
      todoColumnWidths.add(1);
    }
    if (todoColumnWidths.length > todoColumnCount) {
      todoColumnWidths = todoColumnWidths.sublist(0, todoColumnCount);
    }
    todoColumnWidths = [
      for (final width in todoColumnWidths) _normalizeColumnWidth(width),
    ];
    dueAtLocal = _normalizeDueAtLocal(dueAtLocal);
    if (reminderIntervalValue != null && reminderIntervalValue! <= 0) {
      reminderIntervalValue = null;
      reminderIntervalUnit = null;
    } else if (reminderIntervalValue != null) {
      reminderIntervalValue = reminderIntervalValue!.clamp(1, 240).toInt();
      reminderIntervalUnit =
          TodoReminderIntervalUnits.normalize(reminderIntervalUnit);
    }
  }

  JsonMap toJson() {
    return {
      ...extra,
      'id': id,
      'text': text,
      'done': done,
      'order': order,
      'todoColumnCount': todoColumnCount,
      'todoExtraColumns': [...todoExtraColumns],
      'todoColumnWidths': [...todoColumnWidths],
      if (linkedNoteId != null) 'linkedNoteId': linkedNoteId,
      if (dueAtLocal != null) 'dueAtLocal': dueAtLocal,
      if (reminderIntervalValue != null)
        'reminderIntervalValue': reminderIntervalValue,
      if (reminderIntervalUnit != null)
        'reminderIntervalUnit': reminderIntervalUnit,
    };
  }
}

double _normalizeColumnWidth(double value) {
  if (!value.isFinite || value <= 0) {
    return 1;
  }
  final rounded = (value * 1000).roundToDouble() / 1000;
  return rounded
      .clamp(TodoColumnLimits.minWidth, TodoColumnLimits.maxWidth)
      .toDouble();
}

String? _normalizeDueAtLocal(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  final dueAt = DateTime.tryParse(trimmed)?.toLocal();
  if (dueAt == null) {
    return null;
  }
  return [
    dueAt.year.toString().padLeft(4, '0'),
    '-',
    dueAt.month.toString().padLeft(2, '0'),
    '-',
    dueAt.day.toString().padLeft(2, '0'),
    'T',
    dueAt.hour.toString().padLeft(2, '0'),
    ':',
    dueAt.minute.toString().padLeft(2, '0'),
    ':',
    dueAt.second.toString().padLeft(2, '0'),
  ].join();
}
