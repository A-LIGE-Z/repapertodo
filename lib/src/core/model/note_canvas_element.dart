import 'json_helpers.dart';
import 'paper_constants.dart';

class NoteCanvasElement {
  NoteCanvasElement({
    required this.id,
    this.type = NoteCanvasElementTypes.code,
    this.text = '',
    this.x = 32,
    this.y = 32,
    this.width = 180,
    this.height = 96,
    this.zIndex = 0,
    JsonMap? extra,
  }) : extra = extra ?? <String, Object?>{};

  static const _knownKeys = {
    'id',
    'type',
    'text',
    'x',
    'y',
    'width',
    'height',
    'zIndex',
  };

  String id;
  String type;
  String text;
  double x;
  double y;
  double width;
  double height;
  int zIndex;
  JsonMap extra;

  NoteCanvasElement copyWith({
    String? id,
    String? type,
    String? text,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    JsonMap? extra,
  }) {
    return NoteCanvasElement(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      zIndex: zIndex ?? this.zIndex,
      extra: extra ?? <String, Object?>{...this.extra},
    );
  }

  factory NoteCanvasElement.fromJson(JsonMap json) {
    return NoteCanvasElement(
      id: stringValue(json['id'], ''),
      type: stringValue(json['type'], NoteCanvasElementTypes.code),
      text: stringValue(json['text'], ''),
      x: doubleValue(json['x'], 32),
      y: doubleValue(json['y'], 32),
      width: doubleValue(json['width'], 180),
      height: doubleValue(json['height'], 96),
      zIndex: intValue(json['zIndex'], 0),
      extra: preserveUnknown(json, _knownKeys),
    )..normalize();
  }

  void normalize() {
    if (id.trim().isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    }
    type = NoteCanvasElementTypes.normalize(type);
    width = width.clamp(64, 4000).toDouble();
    height = height.clamp(48, 4000).toDouble();
  }

  JsonMap toJson() {
    return {
      ...extra,
      'id': id,
      'type': type,
      'text': text,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'zIndex': zIndex,
    };
  }
}
