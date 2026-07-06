import 'json_helpers.dart';
import 'note_canvas_element.dart';
import 'paper_constants.dart';
import 'paper_item.dart';
import 'paper_titles.dart';

class PaperData {
  PaperData({
    required this.id,
    this.type = PaperTypes.todo,
    this.title = '',
    this.x = 120,
    this.y = 120,
    double? width,
    double? height,
    this.isVisible = true,
    this.alwaysOnTop = false,
    this.isCollapsed = false,
    this.isPinnedToDesktop = false,
    this.textZoom = 1,
    this.capsuleSide = '',
    this.capsuleMonitorDeviceName = '',
    List<PaperItem>? items,
    this.content = '',
    List<NoteCanvasElement>? noteCanvasElements,
    JsonMap? extra,
  })  : width = width ?? _defaultWidthForType(type),
        height = height ?? _defaultHeightForType(type),
        items = items ?? <PaperItem>[],
        noteCanvasElements = noteCanvasElements ?? <NoteCanvasElement>[],
        extra = extra ?? <String, Object?>{};

  static const _knownKeys = {
    'id',
    'type',
    'title',
    'x',
    'y',
    'width',
    'height',
    'isVisible',
    'alwaysOnTop',
    'isCollapsed',
    'isPinnedToDesktop',
    'textZoom',
    'capsuleSide',
    'capsuleMonitorDeviceName',
    'items',
    'content',
    'noteCanvasElements',
  };

  String id;
  String type;
  String title;
  double x;
  double y;
  double width;
  double height;
  bool isVisible;
  bool alwaysOnTop;
  bool isCollapsed;
  bool isPinnedToDesktop;
  double textZoom;
  String capsuleSide;
  String capsuleMonitorDeviceName;
  List<PaperItem> items;
  String content;
  List<NoteCanvasElement> noteCanvasElements;
  JsonMap extra;

  bool get isTodo => type == PaperTypes.todo;
  bool get isNote => type == PaperTypes.note;

  factory PaperData.fromJson(JsonMap json) {
    final type =
        PaperTypes.normalize(stringValue(json['type'], PaperTypes.todo));
    return PaperData(
      id: stringValue(json['id'], ''),
      type: type,
      title: stringValue(json['title'], ''),
      x: doubleValue(json['x'], 120),
      y: doubleValue(json['y'], 120),
      width: doubleValue(json['width'], _defaultWidthForType(type)),
      height: doubleValue(json['height'], _defaultHeightForType(type)),
      isVisible: boolValue(json['isVisible'], true),
      alwaysOnTop: boolValue(json['alwaysOnTop'], false),
      isCollapsed: boolValue(json['isCollapsed'], false),
      isPinnedToDesktop: boolValue(json['isPinnedToDesktop'], false),
      textZoom: doubleValue(json['textZoom'], 1),
      capsuleSide: stringValue(json['capsuleSide'], ''),
      capsuleMonitorDeviceName:
          stringValue(json['capsuleMonitorDeviceName'], ''),
      items: jsonMapList(json['items']).map(PaperItem.fromJson).toList(),
      content: stringValue(json['content'], ''),
      noteCanvasElements: jsonMapList(json['noteCanvasElements'])
          .map(NoteCanvasElement.fromJson)
          .toList(),
      extra: preserveUnknown(json, _knownKeys),
    )..normalize();
  }

  void normalize({
    int maxTitleLength = 40,
    bool storageCompatibility = false,
  }) {
    if (id.trim().isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    }
    type = PaperTypes.normalize(type);
    title = PaperTitles.cleanCustomTitle(
      title,
      maxLength:
          storageCompatibility ? maxTitleLength : PaperTitles.maxTitleLength,
    );
    x = _normalizeCoordinate(x, 120);
    y = _normalizeCoordinate(y, 120);
    width = _normalizePaperDimension(
      width,
      isNote
          ? PaperLayoutDefaults.noteDefaultWidth
          : PaperLayoutDefaults.todoDefaultWidth,
      PaperLayoutDefaults.minWidth,
    );
    height = _normalizePaperDimension(
      height,
      isNote
          ? PaperLayoutDefaults.noteDefaultHeight
          : PaperLayoutDefaults.todoDefaultHeight,
      PaperLayoutDefaults.minHeight,
    );
    textZoom = _normalizeTextZoom(
      textZoom,
      storageCompatibility: storageCompatibility,
    );
    capsuleSide = capsuleSide.trim().isEmpty
        ? ''
        : DeepCapsuleSides.normalize(capsuleSide);
    capsuleMonitorDeviceName = capsuleMonitorDeviceName.trim();
    final usedItemIds = <String>{};
    for (final item in items) {
      if (item.id.trim().isEmpty || !usedItemIds.add(item.id)) {
        item.id = _newUniqueId(usedItemIds);
      }
      item.normalize();
    }
    for (var index = 0; index < items.length; index++) {
      items[index].order = index;
    }
    if (isTodo && items.isEmpty) {
      items.add(PaperItem(id: '${id}_item0'));
    }
    final usedElementIds = <String>{};
    for (var index = 0; index < noteCanvasElements.length; index++) {
      final element = noteCanvasElements[index];
      if (element.id.trim().isEmpty || !usedElementIds.add(element.id)) {
        element.id = _newUniqueId(usedElementIds);
      }
      element.normalize();
      if (element.zIndex <= 0) {
        element.zIndex = (index + 1) * 10;
      }
    }
  }

  JsonMap toJson() {
    return {
      ...extra,
      'id': id,
      'type': type,
      'title': title,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'isVisible': isVisible,
      'alwaysOnTop': alwaysOnTop,
      'isCollapsed': isCollapsed,
      'isPinnedToDesktop': isPinnedToDesktop,
      'textZoom': textZoom,
      'capsuleSide': capsuleSide,
      'capsuleMonitorDeviceName': capsuleMonitorDeviceName,
      'items': items.map((item) => item.toJson()).toList(),
      'content': content,
      'noteCanvasElements':
          noteCanvasElements.map((element) => element.toJson()).toList(),
    };
  }
}

double _normalizeCoordinate(double value, double fallback) {
  return value.isFinite ? value : fallback;
}

double _defaultWidthForType(String? type) {
  return PaperTypes.normalize(type) == PaperTypes.note
      ? PaperLayoutDefaults.noteDefaultWidth
      : PaperLayoutDefaults.todoDefaultWidth;
}

double _defaultHeightForType(String? type) {
  return PaperTypes.normalize(type) == PaperTypes.note
      ? PaperLayoutDefaults.noteDefaultHeight
      : PaperLayoutDefaults.todoDefaultHeight;
}

double _normalizePaperDimension(double value, double fallback, double min) {
  if (!value.isFinite || value < min) {
    return fallback;
  }
  return value;
}

double _normalizeTextZoom(
  double value, {
  required bool storageCompatibility,
}) {
  if (!value.isFinite || value <= 0) {
    return 1;
  }
  final normalized =
      storageCompatibility ? (value * 10).roundToDouble() / 10 : value;
  return normalized.clamp(0.5, 1.5).toDouble();
}

String _newUniqueId(Set<String> usedIds) {
  String id;
  do {
    id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  } while (!usedIds.add(id));
  return id;
}
