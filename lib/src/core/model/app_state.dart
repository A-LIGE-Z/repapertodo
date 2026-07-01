import 'json_helpers.dart';
import 'paper_constants.dart';
import 'paper_data.dart';
import 'sync_settings.dart';

class AppState {
  AppState({
    List<PaperData>? papers,
    this.theme = 'system',
    this.colorScheme = ColorSchemes.warm,
    this.customThemeColorHex = '',
    this.markdownRenderMode = MarkdownRenderModes.enhanced,
    this.todoVisualSize = TodoVisualSizes.medium,
    this.uiFontPreset = 'default',
    this.systemFontFamilyName = '',
    this.externalMarkdownExtension = '.md',
    this.zoom = 1,
    this.useCapsuleMode = true,
    this.useDeepCapsuleMode = true,
    this.showTopBarNewTodoButton = true,
    this.showTopBarNewNoteButton = true,
    this.showTopBarExternalOpenButton = true,
    this.hidePapersFromWindowSwitcher = false,
    this.enableTodoNoteLinks = true,
    this.showTodoDueRelativeTime = false,
    this.todoDueYearDisplayMode = TodoDueYearDisplayModes.none,
    this.todoLineSpacing = 1,
    this.noteLineSpacing = 1,
    this.useTodoReminderInterval = false,
    this.todoReminderIntervalValue = 10,
    this.todoReminderIntervalUnit = TodoReminderIntervalUnits.minutes,
    this.todoReminderScope = TodoReminderScopes.all,
    this.todoReminderBubbleDurationSeconds = 5,
    this.showLinkedNoteName = false,
    this.allowLongLinkedNoteTitles = false,
    this.hideLinkedNotesFromCapsules = false,
    this.runLinkedScriptCapsulesOnClick = false,
    this.maxTitleLength = 18,
    this.useCapsuleCollapseAll = false,
    this.capsuleCollapseAllActive = false,
    Map<String, bool>? capsuleCollapseAllActiveQueues,
    this.showDeepCapsuleWhileExpanded = true,
    this.collapseExpandedDeepCapsuleOnClick = false,
    this.hideDeepCapsulesWhenCovered = false,
    this.enableAnimations = true,
    this.enableToolTips = true,
    this.startAtLogin = false,
    this.pinnedTodoHotKey = '',
    this.pinnedNoteHotKey = '',
    this.fullscreenTopmostMode = FullscreenTopmostModes.avoid,
    this.usePersistentPowerShellProcess = false,
    this.preferPowerShell7 = true,
    this.hideScriptRunWindow = true,
    this.deepCapsuleStartTopMargin = 48,
    Map<String, double>? deepCapsuleQueueStartTopMargins,
    this.deepCapsuleSide = DeepCapsuleSides.right,
    this.deepCapsuleMonitorDeviceName = '',
    SyncSettings? sync,
    JsonMap? extra,
  })  : papers = papers ?? <PaperData>[],
        capsuleCollapseAllActiveQueues =
            capsuleCollapseAllActiveQueues ?? <String, bool>{},
        deepCapsuleQueueStartTopMargins =
            deepCapsuleQueueStartTopMargins ?? <String, double>{},
        sync = sync ?? SyncSettings(),
        extra = extra ?? <String, Object?>{};

  static const _knownKeys = {
    'papers',
    'theme',
    'colorScheme',
    'customThemeColorHex',
    'markdownRenderMode',
    'todoVisualSize',
    'uiFontPreset',
    'systemFontFamilyName',
    'externalMarkdownExtension',
    'zoom',
    'useCapsuleMode',
    'useDeepCapsuleMode',
    'showTopBarNewTodoButton',
    'showTopBarNewNoteButton',
    'showTopBarExternalOpenButton',
    'hidePapersFromWindowSwitcher',
    'enableTodoNoteLinks',
    'showTodoDueRelativeTime',
    'todoDueYearDisplayMode',
    'todoLineSpacing',
    'noteLineSpacing',
    'useTodoReminderInterval',
    'todoReminderIntervalValue',
    'todoReminderIntervalUnit',
    'todoReminderScope',
    'todoReminderBubbleDurationSeconds',
    'showLinkedNoteName',
    'allowLongLinkedNoteTitles',
    'hideLinkedNotesFromCapsules',
    'runLinkedScriptCapsulesOnClick',
    'maxTitleLength',
    'useCapsuleCollapseAll',
    'capsuleCollapseAllActive',
    'capsuleCollapseAllActiveQueues',
    'showDeepCapsuleWhileExpanded',
    'collapseExpandedDeepCapsuleOnClick',
    'hideDeepCapsulesWhenCovered',
    'enableAnimations',
    'enableToolTips',
    'startAtLogin',
    'pinnedTodoHotKey',
    'pinnedNoteHotKey',
    'fullscreenTopmostMode',
    'usePersistentPowerShellProcess',
    'preferPowerShell7',
    'hideScriptRunWindow',
    'deepCapsuleStartTopMargin',
    'deepCapsuleQueueStartTopMargins',
    'deepCapsuleSide',
    'deepCapsuleMonitorDeviceName',
    'sync',
  };

  List<PaperData> papers;
  String theme;
  String colorScheme;
  String customThemeColorHex;
  String markdownRenderMode;
  String todoVisualSize;
  String uiFontPreset;
  String systemFontFamilyName;
  String externalMarkdownExtension;
  double zoom;
  bool useCapsuleMode;
  bool useDeepCapsuleMode;
  bool showTopBarNewTodoButton;
  bool showTopBarNewNoteButton;
  bool showTopBarExternalOpenButton;
  bool hidePapersFromWindowSwitcher;
  bool enableTodoNoteLinks;
  bool showTodoDueRelativeTime;
  String todoDueYearDisplayMode;
  double todoLineSpacing;
  double noteLineSpacing;
  bool useTodoReminderInterval;
  int todoReminderIntervalValue;
  String todoReminderIntervalUnit;
  String todoReminderScope;
  int todoReminderBubbleDurationSeconds;
  bool showLinkedNoteName;
  bool allowLongLinkedNoteTitles;
  bool hideLinkedNotesFromCapsules;
  bool runLinkedScriptCapsulesOnClick;
  int maxTitleLength;
  bool useCapsuleCollapseAll;
  bool capsuleCollapseAllActive;
  Map<String, bool> capsuleCollapseAllActiveQueues;
  bool showDeepCapsuleWhileExpanded;
  bool collapseExpandedDeepCapsuleOnClick;
  bool hideDeepCapsulesWhenCovered;
  bool enableAnimations;
  bool enableToolTips;
  bool startAtLogin;
  String pinnedTodoHotKey;
  String pinnedNoteHotKey;
  String fullscreenTopmostMode;
  bool usePersistentPowerShellProcess;
  bool preferPowerShell7;
  bool hideScriptRunWindow;
  double deepCapsuleStartTopMargin;
  Map<String, double> deepCapsuleQueueStartTopMargins;
  String deepCapsuleSide;
  String deepCapsuleMonitorDeviceName;
  SyncSettings sync;
  JsonMap extra;

  factory AppState.fromJson(JsonMap json) {
    return AppState(
      papers: jsonMapList(json['papers']).map(PaperData.fromJson).toList(),
      theme: stringValue(json['theme'], 'system'),
      colorScheme: stringValue(json['colorScheme'], ColorSchemes.warm),
      customThemeColorHex: stringValue(json['customThemeColorHex'], ''),
      markdownRenderMode:
          stringValue(json['markdownRenderMode'], MarkdownRenderModes.enhanced),
      todoVisualSize:
          stringValue(json['todoVisualSize'], TodoVisualSizes.medium),
      uiFontPreset: stringValue(json['uiFontPreset'], 'default'),
      systemFontFamilyName: stringValue(json['systemFontFamilyName'], ''),
      externalMarkdownExtension:
          stringValue(json['externalMarkdownExtension'], '.md'),
      zoom: doubleValue(json['zoom'], 1),
      useCapsuleMode: boolValue(json['useCapsuleMode'], true),
      useDeepCapsuleMode: boolValue(json['useDeepCapsuleMode'], true),
      showTopBarNewTodoButton: boolValue(json['showTopBarNewTodoButton'], true),
      showTopBarNewNoteButton: boolValue(json['showTopBarNewNoteButton'], true),
      showTopBarExternalOpenButton:
          boolValue(json['showTopBarExternalOpenButton'], true),
      hidePapersFromWindowSwitcher:
          boolValue(json['hidePapersFromWindowSwitcher'], false),
      enableTodoNoteLinks: boolValue(json['enableTodoNoteLinks'], true),
      showTodoDueRelativeTime:
          boolValue(json['showTodoDueRelativeTime'], false),
      todoDueYearDisplayMode: stringValue(
          json['todoDueYearDisplayMode'], TodoDueYearDisplayModes.none),
      todoLineSpacing: doubleValue(json['todoLineSpacing'], 1),
      noteLineSpacing: doubleValue(json['noteLineSpacing'], 1),
      useTodoReminderInterval:
          boolValue(json['useTodoReminderInterval'], false),
      todoReminderIntervalValue:
          intValue(json['todoReminderIntervalValue'], 10),
      todoReminderIntervalUnit: stringValue(
          json['todoReminderIntervalUnit'], TodoReminderIntervalUnits.minutes),
      todoReminderScope:
          stringValue(json['todoReminderScope'], TodoReminderScopes.all),
      todoReminderBubbleDurationSeconds:
          intValue(json['todoReminderBubbleDurationSeconds'], 5),
      showLinkedNoteName: boolValue(json['showLinkedNoteName'], false),
      allowLongLinkedNoteTitles:
          boolValue(json['allowLongLinkedNoteTitles'], false),
      hideLinkedNotesFromCapsules:
          boolValue(json['hideLinkedNotesFromCapsules'], false),
      runLinkedScriptCapsulesOnClick:
          boolValue(json['runLinkedScriptCapsulesOnClick'], false),
      maxTitleLength: intValue(json['maxTitleLength'], 18),
      useCapsuleCollapseAll: boolValue(json['useCapsuleCollapseAll'], false),
      capsuleCollapseAllActive:
          boolValue(json['capsuleCollapseAllActive'], false),
      capsuleCollapseAllActiveQueues:
          boolMap(json['capsuleCollapseAllActiveQueues']),
      showDeepCapsuleWhileExpanded:
          boolValue(json['showDeepCapsuleWhileExpanded'], true),
      collapseExpandedDeepCapsuleOnClick:
          boolValue(json['collapseExpandedDeepCapsuleOnClick'], false),
      hideDeepCapsulesWhenCovered:
          boolValue(json['hideDeepCapsulesWhenCovered'], false),
      enableAnimations: boolValue(json['enableAnimations'], true),
      enableToolTips: boolValue(json['enableToolTips'], true),
      startAtLogin: boolValue(json['startAtLogin'], false),
      pinnedTodoHotKey: stringValue(json['pinnedTodoHotKey'], ''),
      pinnedNoteHotKey: stringValue(json['pinnedNoteHotKey'], ''),
      fullscreenTopmostMode: stringValue(
          json['fullscreenTopmostMode'], FullscreenTopmostModes.avoid),
      usePersistentPowerShellProcess:
          boolValue(json['usePersistentPowerShellProcess'], false),
      preferPowerShell7: boolValue(json['preferPowerShell7'], true),
      hideScriptRunWindow: boolValue(json['hideScriptRunWindow'], true),
      deepCapsuleStartTopMargin:
          doubleValue(json['deepCapsuleStartTopMargin'], 48),
      deepCapsuleQueueStartTopMargins:
          doubleMap(json['deepCapsuleQueueStartTopMargins']),
      deepCapsuleSide:
          stringValue(json['deepCapsuleSide'], DeepCapsuleSides.right),
      deepCapsuleMonitorDeviceName:
          stringValue(json['deepCapsuleMonitorDeviceName'], ''),
      sync: json['sync'] is Map
          ? SyncSettings.fromJson(
              Map<String, Object?>.from(json['sync'] as Map))
          : null,
      extra: preserveUnknown(json, _knownKeys),
    )..normalize();
  }

  void normalize() {
    theme = switch (theme) {
      'light' || 'dark' || 'system' => theme,
      _ => 'system',
    };
    customThemeColorHex = _normalizeColorHex(customThemeColorHex);
    colorScheme = ColorSchemes.normalize(colorScheme);
    markdownRenderMode = MarkdownRenderModes.normalize(markdownRenderMode);
    todoVisualSize = TodoVisualSizes.normalize(todoVisualSize);
    uiFontPreset = UiFontPresets.normalize(uiFontPreset);
    systemFontFamilyName = systemFontFamilyName.trim();
    zoom = zoom.clamp(0.6, 1.8).toDouble();
    todoDueYearDisplayMode =
        TodoDueYearDisplayModes.normalize(todoDueYearDisplayMode);
    todoLineSpacing = _normalizeLineSpacing(todoLineSpacing);
    noteLineSpacing = _normalizeLineSpacing(noteLineSpacing);
    todoReminderIntervalValue = todoReminderIntervalValue.clamp(1, 240).toInt();
    todoReminderIntervalUnit =
        TodoReminderIntervalUnits.normalize(todoReminderIntervalUnit);
    todoReminderScope = TodoReminderScopes.normalize(todoReminderScope);
    todoReminderBubbleDurationSeconds =
        todoReminderBubbleDurationSeconds.clamp(1, 600).toInt();
    maxTitleLength = maxTitleLength.clamp(4, 80).toInt();
    pinnedTodoHotKey = pinnedTodoHotKey.trim();
    pinnedNoteHotKey = pinnedNoteHotKey.trim();
    fullscreenTopmostMode =
        FullscreenTopmostModes.normalize(fullscreenTopmostMode);
    deepCapsuleStartTopMargin =
        deepCapsuleStartTopMargin.clamp(8, 10000).toDouble();
    deepCapsuleQueueStartTopMargins = {
      for (final entry in deepCapsuleQueueStartTopMargins.entries)
        entry.key: entry.value.clamp(8, 10000).toDouble(),
    };
    deepCapsuleSide = DeepCapsuleSides.normalize(deepCapsuleSide);
    deepCapsuleMonitorDeviceName = deepCapsuleMonitorDeviceName.trim();
    externalMarkdownExtension = _normalizeExtension(externalMarkdownExtension);
    sync.normalize();
    for (final paper in papers) {
      paper.normalize();
      if (useCapsuleMode && useDeepCapsuleMode && paper.capsuleSide.isEmpty) {
        paper.capsuleSide = deepCapsuleSide;
      }
    }
    final noteIds =
        papers.where((paper) => paper.isNote).map((paper) => paper.id).toSet();
    for (final paper in papers) {
      if (!paper.isTodo) {
        continue;
      }
      for (final item in paper.items) {
        final linkedNoteId = item.linkedNoteId;
        if (linkedNoteId != null && !noteIds.contains(linkedNoteId)) {
          item.linkedNoteId = null;
        }
      }
    }
  }

  JsonMap toJson() {
    return {
      ...extra,
      'papers': papers.map((paper) => paper.toJson()).toList(),
      'theme': theme,
      'colorScheme': colorScheme,
      'customThemeColorHex': customThemeColorHex,
      'markdownRenderMode': markdownRenderMode,
      'todoVisualSize': todoVisualSize,
      'uiFontPreset': uiFontPreset,
      'systemFontFamilyName': systemFontFamilyName,
      'externalMarkdownExtension': externalMarkdownExtension,
      'zoom': zoom,
      'useCapsuleMode': useCapsuleMode,
      'useDeepCapsuleMode': useDeepCapsuleMode,
      'showTopBarNewTodoButton': showTopBarNewTodoButton,
      'showTopBarNewNoteButton': showTopBarNewNoteButton,
      'showTopBarExternalOpenButton': showTopBarExternalOpenButton,
      'hidePapersFromWindowSwitcher': hidePapersFromWindowSwitcher,
      'enableTodoNoteLinks': enableTodoNoteLinks,
      'showTodoDueRelativeTime': showTodoDueRelativeTime,
      'todoDueYearDisplayMode': todoDueYearDisplayMode,
      'todoLineSpacing': todoLineSpacing,
      'noteLineSpacing': noteLineSpacing,
      'useTodoReminderInterval': useTodoReminderInterval,
      'todoReminderIntervalValue': todoReminderIntervalValue,
      'todoReminderIntervalUnit': todoReminderIntervalUnit,
      'todoReminderScope': todoReminderScope,
      'todoReminderBubbleDurationSeconds': todoReminderBubbleDurationSeconds,
      'showLinkedNoteName': showLinkedNoteName,
      'allowLongLinkedNoteTitles': allowLongLinkedNoteTitles,
      'hideLinkedNotesFromCapsules': hideLinkedNotesFromCapsules,
      'runLinkedScriptCapsulesOnClick': runLinkedScriptCapsulesOnClick,
      'maxTitleLength': maxTitleLength,
      'useCapsuleCollapseAll': useCapsuleCollapseAll,
      'capsuleCollapseAllActive': capsuleCollapseAllActive,
      'capsuleCollapseAllActiveQueues': capsuleCollapseAllActiveQueues,
      'showDeepCapsuleWhileExpanded': showDeepCapsuleWhileExpanded,
      'collapseExpandedDeepCapsuleOnClick': collapseExpandedDeepCapsuleOnClick,
      'hideDeepCapsulesWhenCovered': hideDeepCapsulesWhenCovered,
      'enableAnimations': enableAnimations,
      'enableToolTips': enableToolTips,
      'startAtLogin': startAtLogin,
      'pinnedTodoHotKey': pinnedTodoHotKey,
      'pinnedNoteHotKey': pinnedNoteHotKey,
      'fullscreenTopmostMode': fullscreenTopmostMode,
      'usePersistentPowerShellProcess': usePersistentPowerShellProcess,
      'preferPowerShell7': preferPowerShell7,
      'hideScriptRunWindow': hideScriptRunWindow,
      'deepCapsuleStartTopMargin': deepCapsuleStartTopMargin,
      'deepCapsuleQueueStartTopMargins': deepCapsuleQueueStartTopMargins,
      'deepCapsuleSide': deepCapsuleSide,
      'deepCapsuleMonitorDeviceName': deepCapsuleMonitorDeviceName,
      'sync': sync.toJson(),
    };
  }
}

String _normalizeColorHex(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final withoutPrefix =
      trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(withoutPrefix)) {
    return '';
  }
  return '#${withoutPrefix.toUpperCase()}';
}

double _normalizeLineSpacing(double value) {
  return value.clamp(0.8, 2.4).toDouble();
}

String _normalizeExtension(String extension) {
  var value = extension.trim();
  if (value.isEmpty) {
    return '.md';
  }
  if (value.startsWith('*.')) {
    value = value.substring(1);
  }
  if (!value.startsWith('.')) {
    value = '.$value';
  }
  if (value.length < 2 || value.length > 32 || value.contains('..')) {
    return '.md';
  }
  return value.toLowerCase();
}
