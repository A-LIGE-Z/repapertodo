import 'json_helpers.dart';
import 'note_canvas_element.dart';
import 'paper_constants.dart';
import 'paper_item.dart';

class PaperData {
  PaperData({
    required this.id,
    this.type = PaperTypes.todo,
    this.title = '',
    this.x = 120,
    this.y = 120,
    this.width = PaperLayoutDefaults.todoDefaultWidth,
    this.height = PaperLayoutDefaults.todoDefaultHeight,
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
  })  : items = items ?? <PaperItem>[],
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
    return PaperData(
      id: stringValue(json['id'], ''),
      type: stringValue(json['type'], PaperTypes.todo),
      title: stringValue(json['title'], ''),
      x: doubleValue(json['x'], 120),
      y: doubleValue(json['y'], 120),
      width: doubleValue(json['width'], PaperLayoutDefaults.todoDefaultWidth),
      height: doubleValue(json['height'], PaperLayoutDefaults.todoDefaultHeight),
      isVisible: boolValue(json['isVisible'], true),
      alwaysOnTop: boolValue(json['alwaysOnTop'], false),
      isCollapsed: boolValue(json['isCollapsed'], false),
      isPinnedToDesktop: boolValue(json['isPinnedToDesktop'], false),
      textZoom: doubleValue(json['textZoom'], 1),
      capsuleSide: stringValue(json['capsuleSide'], ''),
      capsuleMonitorDeviceName: stringValue(json['capsuleMonitorDeviceName'], ''),
      items: jsonMapList(json['items']).map(PaperItem.fromJson).toList(),
      content: stringValue(json['content'], ''),
      noteCanvasElements:
          jsonMapList(json['noteCanvasElements']).map(NoteCanvasElement.fromJson).toList(),
      extra: preserveUnknown(json, _knownKeys),
    )..normalize();
  }

  void normalize() {
    if (id.trim().isEmpty) {
      id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    }
    type = PaperTypes.normalize(type);
    width = width.clamp(
      PaperLayoutDefaults.minWidth,
      10000,
    ).toDouble();
    height = height.clamp(
      PaperLayoutDefaults.minHeight,
      10000,
    ).toDouble();
    textZoom = textZoom.clamp(0.5, 1.5).toDouble();
    capsuleSide = capsuleSide.trim().isEmpty ? '' : DeepCapsuleSides.normalize(capsuleSide);
    capsuleMonitorDeviceName = capsuleMonitorDeviceName.trim();
    for (final item in items) {
      item.normalize();
    }
    items.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
    for (var index = 0; index < items.length; index++) {
      items[index].order = index;
    }
    if (isTodo && items.isEmpty) {
      items.add(PaperItem(id: '${id}_item0'));
    }
    for (final element in noteCanvasElements) {
      element.normalize();
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
      'noteCanvasElements': noteCanvasElements.map((element) => element.toJson()).toList(),
    };
  }
}
