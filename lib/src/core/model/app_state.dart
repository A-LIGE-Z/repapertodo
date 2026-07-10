import 'json_helpers.dart';
import 'paper_constants.dart';
import 'paper_data.dart';
import 'paper_titles.dart';
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
    this.maxTitleLength = 6,
    this.useCapsuleCollapseAll = false,
    this.capsuleCollapseAllActive = false,
    Map<String, bool>? capsuleCollapseAllActiveQueues,
    this.showDeepCapsuleWhileExpanded = true,
    this.collapseExpandedDeepCapsuleOnClick = false,
    this.hideDeepCapsulesWhenCovered = false,
    this.hideDeepCapsulesWhenFullscreen = false,
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
    'showTopBarNewPaperButtons',
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
    'hideDeepCapsulesWhenFullscreen',
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
  bool hideDeepCapsulesWhenFullscreen;
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
    final retiredTopBarButtons = json['showTopBarNewPaperButtons'];
    final syncJson = jsonMapOrNull(json['sync']);
    final topBarNewTodoButton = retiredTopBarButtons is bool
        ? retiredTopBarButtons
        : boolValue(json['showTopBarNewTodoButton'], true);
    final topBarNewNoteButton = retiredTopBarButtons is bool
        ? retiredTopBarButtons
        : boolValue(json['showTopBarNewNoteButton'], true);
    final hideDeepCapsulesWhenCovered =
        boolValue(json['hideDeepCapsulesWhenCovered'], false);
    final hideDeepCapsulesWhenFullscreen =
        boolValue(json['hideDeepCapsulesWhenFullscreen'], false);

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
      showTopBarNewTodoButton: topBarNewTodoButton,
      showTopBarNewNoteButton: topBarNewNoteButton,
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
      maxTitleLength: intValue(json['maxTitleLength'], 6),
      useCapsuleCollapseAll: boolValue(json['useCapsuleCollapseAll'], false),
      capsuleCollapseAllActive:
          boolValue(json['capsuleCollapseAllActive'], false),
      capsuleCollapseAllActiveQueues:
          boolMap(json['capsuleCollapseAllActiveQueues']),
      showDeepCapsuleWhileExpanded:
          boolValue(json['showDeepCapsuleWhileExpanded'], true),
      collapseExpandedDeepCapsuleOnClick:
          boolValue(json['collapseExpandedDeepCapsuleOnClick'], false),
      hideDeepCapsulesWhenCovered: hideDeepCapsulesWhenCovered,
      hideDeepCapsulesWhenFullscreen: hideDeepCapsulesWhenFullscreen,
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
      sync: syncJson == null ? null : SyncSettings.fromJson(syncJson),
      extra: preserveUnknown(json, _knownKeys),
    )..normalize(storageCompatibility: true);
  }

  void normalize({bool storageCompatibility = false}) {
    theme = _normalizeTheme(theme);
    customThemeColorHex = _normalizeColorHex(customThemeColorHex);
    colorScheme = ColorSchemes.normalize(colorScheme);
    markdownRenderMode = MarkdownRenderModes.normalize(markdownRenderMode);
    todoVisualSize = TodoVisualSizes.normalize(todoVisualSize);
    uiFontPreset = UiFontPresets.normalize(uiFontPreset);
    systemFontFamilyName = normalizeSystemFontFamilyName(
      systemFontFamilyName,
    );
    zoom = _normalizeZoom(zoom);
    todoDueYearDisplayMode =
        TodoDueYearDisplayModes.normalize(todoDueYearDisplayMode);
    todoLineSpacing = _normalizeLineSpacing(todoLineSpacing);
    noteLineSpacing = _normalizeLineSpacing(noteLineSpacing);
    todoReminderIntervalValue =
        _normalizePositiveIntRange(todoReminderIntervalValue, 10, 1, 240);
    todoReminderIntervalUnit =
        TodoReminderIntervalUnits.normalize(todoReminderIntervalUnit);
    todoReminderScope = TodoReminderScopes.normalize(todoReminderScope);
    todoReminderBubbleDurationSeconds = _normalizePositiveIntRange(
        todoReminderBubbleDurationSeconds, 5, 1, 600);
    maxTitleLength = PaperTitles.normalizeMaxTitleLength(maxTitleLength);
    pinnedTodoHotKey = _normalizeHotKeyForSettings(pinnedTodoHotKey);
    pinnedNoteHotKey = _normalizeHotKeyForSettings(pinnedNoteHotKey);
    fullscreenTopmostMode =
        FullscreenTopmostModes.normalize(fullscreenTopmostMode);
    if (!useCapsuleMode) {
      useDeepCapsuleMode = false;
    }
    if (!useCapsuleMode || !useDeepCapsuleMode) {
      hideDeepCapsulesWhenCovered = false;
      hideDeepCapsulesWhenFullscreen = false;
    }
    if (!useCapsuleMode || !useDeepCapsuleMode) {
      useCapsuleCollapseAll = false;
    }
    if (!useCapsuleCollapseAll) {
      capsuleCollapseAllActive = false;
      capsuleCollapseAllActiveQueues = <String, bool>{};
    } else {
      capsuleCollapseAllActiveQueues =
          _normalizeCollapseAllActiveQueues(capsuleCollapseAllActiveQueues);
      if (capsuleCollapseAllActiveQueues.isNotEmpty) {
        capsuleCollapseAllActive = true;
      }
    }
    deepCapsuleSide = DeepCapsuleSides.normalize(deepCapsuleSide);
    deepCapsuleMonitorDeviceName =
        normalizeCapsuleMonitorDeviceName(deepCapsuleMonitorDeviceName);
    final keepDeepCapsuleStartTopMargins =
        useCapsuleMode && useDeepCapsuleMode && useCapsuleCollapseAll;
    if (storageCompatibility && !keepDeepCapsuleStartTopMargins) {
      deepCapsuleStartTopMargin = 48;
      deepCapsuleQueueStartTopMargins = <String, double>{};
    } else {
      deepCapsuleStartTopMargin =
          deepCapsuleStartTopMargin.clamp(8, 10000).toDouble();
      deepCapsuleQueueStartTopMargins =
          _normalizeQueueStartTopMargins(deepCapsuleQueueStartTopMargins);
    }
    externalMarkdownExtension = _normalizeExtension(externalMarkdownExtension);
    sync.normalize();
    final usedPaperIds = <String>{};
    for (final paper in papers) {
      paper.id = normalizeLocalModelId(paper.id);
      if (paper.id.isEmpty || !usedPaperIds.add(paper.id)) {
        paper.id = _newUniqueId(usedPaperIds);
      }
      if (paper.isPinnedToDesktop) {
        paper.isVisible = true;
        paper.isCollapsed = false;
        useCapsuleMode = true;
        useDeepCapsuleMode = true;
        showDeepCapsuleWhileExpanded = true;
      }
      paper.normalize(
        maxTitleLength: maxTitleLength,
        storageCompatibility: storageCompatibility,
      );
      if (paper.capsuleSide.isEmpty) {
        paper.capsuleSide = deepCapsuleSide;
      }
      if (paper.capsuleMonitorDeviceName.isEmpty) {
        paper.capsuleMonitorDeviceName = deepCapsuleMonitorDeviceName;
      }
      if (!useCapsuleMode) {
        paper.isCollapsed = false;
      }
    }
    final noteIds =
        papers.where((paper) => paper.isNote).map((paper) => paper.id).toSet();
    final linkedNoteIds = <String>{};
    for (final paper in papers) {
      if (!paper.isTodo) {
        continue;
      }
      for (final item in paper.items) {
        final linkedNoteId = item.linkedNoteId;
        if (linkedNoteId != null && !noteIds.contains(linkedNoteId)) {
          item.linkedNoteId = null;
        } else if (linkedNoteId != null && linkedNoteId.trim().isNotEmpty) {
          linkedNoteIds.add(linkedNoteId);
        }
      }
    }
    if (enableTodoNoteLinks && hideLinkedNotesFromCapsules) {
      for (final paper in papers) {
        if (paper.isNote && linkedNoteIds.contains(paper.id)) {
          paper.isCollapsed = false;
        }
      }
    }
    _syncCapsuleCollapseAllQueuesWithPapers();
  }

  String capsuleQueueKeyFor(PaperData paper) {
    return _queueKey(paper.capsuleMonitorDeviceName, paper.capsuleSide);
  }

  void _syncCapsuleCollapseAllQueuesWithPapers() {
    if (!useCapsuleMode || !useDeepCapsuleMode || !useCapsuleCollapseAll) {
      return;
    }
    if (papers.isEmpty) {
      return;
    }

    final liveQueueKeys = <String>{};
    for (final paper in papers) {
      if (_paperCanOccupyDeepCapsuleQueue(paper)) {
        liveQueueKeys.add(capsuleQueueKeyFor(paper));
      }
    }

    final wasActive = capsuleCollapseAllActive;
    if (capsuleCollapseAllActiveQueues.isNotEmpty) {
      capsuleCollapseAllActiveQueues = {
        for (final entry in capsuleCollapseAllActiveQueues.entries)
          if (liveQueueKeys.contains(entry.key)) entry.key: true,
      };
      capsuleCollapseAllActive = capsuleCollapseAllActiveQueues.isNotEmpty;
    }

    if (wasActive &&
        capsuleCollapseAllActiveQueues.isEmpty &&
        liveQueueKeys.isNotEmpty) {
      capsuleCollapseAllActiveQueues = {
        for (final queueKey in liveQueueKeys) queueKey: true,
      };
      capsuleCollapseAllActive = true;
    } else if (capsuleCollapseAllActiveQueues.isEmpty) {
      capsuleCollapseAllActive = false;
    }
  }

  bool _paperCanOccupyDeepCapsuleQueue(PaperData paper) {
    if (!paper.isVisible || !_canPaperDisplayAsCapsule(paper)) {
      return false;
    }
    return paper.isCollapsed ||
        paper.isPinnedToDesktop ||
        showDeepCapsuleWhileExpanded;
  }

  bool _canPaperDisplayAsCapsule(PaperData paper) {
    if (!useCapsuleMode) {
      return false;
    }
    if (!enableTodoNoteLinks || !hideLinkedNotesFromCapsules || !paper.isNote) {
      return true;
    }
    return !papers
        .where((sourcePaper) => sourcePaper.isTodo)
        .expand((sourcePaper) => sourcePaper.items)
        .any((item) => item.linkedNoteId == paper.id);
  }

  bool isCapsuleCollapseAllActiveFor(PaperData paper) {
    if (!useCapsuleMode || !useCapsuleCollapseAll) {
      return false;
    }
    if (useDeepCapsuleMode && capsuleCollapseAllActiveQueues.isNotEmpty) {
      return capsuleCollapseAllActiveQueues[capsuleQueueKeyFor(paper)] ?? false;
    }
    return capsuleCollapseAllActive;
  }

  void setCapsuleCollapseAllActiveFor(PaperData? paper, bool active) {
    if (!useCapsuleMode || !useCapsuleCollapseAll) {
      capsuleCollapseAllActive = false;
      capsuleCollapseAllActiveQueues = <String, bool>{};
      return;
    }
    if (paper == null) {
      capsuleCollapseAllActive = active;
      capsuleCollapseAllActiveQueues = <String, bool>{};
      return;
    }
    if (!useDeepCapsuleMode) {
      capsuleCollapseAllActive = active;
      if (!active) {
        capsuleCollapseAllActiveQueues = <String, bool>{};
      }
      return;
    }

    final queueKey = capsuleQueueKeyFor(paper);
    if (active) {
      capsuleCollapseAllActiveQueues[queueKey] = true;
    } else {
      capsuleCollapseAllActiveQueues.remove(queueKey);
    }
    capsuleCollapseAllActive = capsuleCollapseAllActiveQueues.isNotEmpty;
  }

  void toggleCapsuleCollapseAllFor(PaperData? paper) {
    final active = paper == null
        ? capsuleCollapseAllActive
        : isCapsuleCollapseAllActiveFor(paper);
    setCapsuleCollapseAllActiveFor(paper, !active);
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
      'hideDeepCapsulesWhenFullscreen': hideDeepCapsulesWhenFullscreen,
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
  if (!value.isFinite || value <= 0) {
    return 1;
  }
  final rounded = (value * 100).roundToDouble() / 100;
  return rounded.clamp(0.8, 5.0).toDouble();
}

double _normalizeZoom(double value) {
  if (!value.isFinite || value <= 0) {
    return 1;
  }
  return value.clamp(0.5, 1.5).toDouble();
}

int _normalizePositiveIntRange(
  int value,
  int fallback,
  int min,
  int max,
) {
  final normalized = value <= 0 ? fallback : value;
  return normalized.clamp(min, max).toInt();
}

String _normalizeHotKeyForSettings(String value) {
  final cleaned = StringBuffer();
  for (final unit in value.codeUnits) {
    if (unit <= 0x1F || (unit >= 0x7F && unit <= 0x9F)) {
      continue;
    }
    cleaned.writeCharCode(unit);
  }
  final text = cleaned.toString().trim();
  return text.length > 64 ? text.substring(0, 64) : text;
}

String _normalizeTheme(String value) {
  return switch (value.trim().toLowerCase()) {
    'light' => 'light',
    'dark' => 'dark',
    'system' => 'system',
    _ => 'system',
  };
}

String normalizeSystemFontFamilyName(String value) {
  final cleaned = StringBuffer();
  for (final rune in value.runes) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      continue;
    }
    cleaned.writeCharCode(rune);
  }
  final text = cleaned.toString().trim();
  return text.length > 128 ? text.substring(0, 128) : text;
}

String _newUniqueId(Set<String> usedIds) {
  String id;
  do {
    id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  } while (!usedIds.add(id));
  return id;
}

Map<String, bool> _normalizeCollapseAllActiveQueues(Map<String, bool> source) {
  final normalized = <String, bool>{};
  for (final entry in source.entries) {
    final normalizedKey = _normalizeQueueKey(entry.key);
    if (normalizedKey == null) {
      continue;
    }
    if (!normalized.containsKey(normalizedKey) || entry.key == normalizedKey) {
      normalized[normalizedKey] = entry.value;
    }
  }
  for (final entry in [...normalized.entries]) {
    if (!entry.value) {
      normalized.remove(entry.key);
    }
  }
  return normalized;
}

Map<String, double> _normalizeQueueStartTopMargins(Map<String, double> source) {
  final normalized = <String, double>{};
  for (final entry in source.entries) {
    final normalizedKey = _normalizeQueueKey(entry.key);
    if (normalizedKey == null) {
      continue;
    }
    if (!normalized.containsKey(normalizedKey) || entry.key == normalizedKey) {
      normalized[normalizedKey] = entry.value.clamp(8, 10000).toDouble();
    }
  }
  return normalized;
}

String? _normalizeQueueKey(String? key) {
  if (key != null && hasRawControlCharacter(key)) {
    return null;
  }
  final value = (key ?? '').trim();
  final separator = value.lastIndexOf('|');
  if (separator < 0) {
    return _queueKey('', value);
  }
  return _queueKey(
      value.substring(0, separator), value.substring(separator + 1));
}

String _queueKey(String? monitorDeviceName, String? side) {
  final monitor = normalizeCapsuleMonitorDeviceName(monitorDeviceName);
  final normalizedSide = DeepCapsuleSides.normalize(side);
  return '$monitor|$normalizedSide';
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
  if (value.length < 2 ||
      value.length > 120 ||
      value.endsWith('.') ||
      value.endsWith(' ') ||
      _hasInvalidFileNameCharacter(value)) {
    return '.md';
  }
  return value.toLowerCase();
}

bool _hasInvalidFileNameCharacter(String value) {
  const invalid = {'<', '>', ':', '"', '/', '\\', '|', '?', '*'};
  return value.runes.any((rune) {
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      return true;
    }
    return invalid.contains(String.fromCharCode(rune));
  });
}
