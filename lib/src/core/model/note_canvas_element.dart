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
    id = id.trim();
    if (id.isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    }
    type = NoteCanvasElementTypes.normalize(type);
    x = _normalizeCoordinate(x, 32).clamp(-2000, 8000).toDouble();
    y = _normalizeCoordinate(y, 32).clamp(-2000, 8000).toDouble();
    width = _normalizeDimension(width, 220, 72).clamp(72, 1600).toDouble();
    height = _normalizeDimension(height, 110, 48).clamp(48, 1600).toDouble();
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

double _normalizeCoordinate(double value, double fallback) {
  return value.isFinite ? value : fallback;
}

double _normalizeDimension(double value, double fallback, double min) {
  return !value.isFinite || value < min ? fallback : value;
}
