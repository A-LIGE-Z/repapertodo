import 'dart:async';
import 'dart:math' as math;

import 'core/model/app_state.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
import 'core/model/paper_item.dart';
import 'core/model/paper_titles.dart';
import 'core/script/script_capsule.dart';
import 'core/startup/startup_command.dart';
import 'platform/platform_services.dart';

class RePaperTodoController {
  RePaperTodoController({
    required AppState initialState,
    required PlatformServices platform,
  })  : state = initialState,
        _platform = platform {
    state.normalize();
  }

  AppState state;
  final PlatformServices _platform;
  StartupCommand? _pendingUiStartupCommand;
  final Set<String> _paperIdsPendingWorkAreaRescue = <String>{};
  final Set<String> _paperIdsPendingDeepCapsuleStripClamp = <String>{};

  Stream<PaperData> get paperSurfaceUpdates =>
      _platform.paperWindows.surfaceUpdates;

  Stream<String> get paperOpenRequests =>
      _platform.paperWindows.paperOpenRequests;

  Stream<StartupCommand> get startupCommands => _platform.startup.commands;

  bool get supportsStartupAtLogin =>
      _platform.systemIntegration.supportsStartupAtLogin;

  bool get supportsWindowSwitcherVisibility =>
      _platform.systemIntegration.supportsWindowSwitcherVisibility;

  bool get supportsFullscreenTopmostMode =>
      _platform.systemIntegration.supportsFullscreenTopmostMode;

  bool get supportsGlobalHotkeys =>
      _platform.systemIntegration.supportsGlobalHotkeys;

  bool get supportsScriptCapsules =>
      _platform.scriptCapsules.supportsScriptCapsules;

  bool get canCreatePaper => state.papers.length < PaperLimits.maxPapers;

  Future<void> start(
      {StartupCommand startupCommand =
          const StartupCommand(StartupCommandKind.none)}) async {
    await _platform.tray.initialize();
    await _applyStateSettingsToPlatform();

    if (state.papers.isEmpty &&
        !startupCommand.createsPaper &&
        startupCommand.kind != StartupCommandKind.exit) {
      createPaper(PaperTypes.todo);
    }

    await _rescuePapersIntoWorkAreas();
    await _preparePendingNewPapersForFirstShow();
    await _platform.paperWindows.restoreAll(state);
    await executeStartupCommand(startupCommand);
    if (startupCommand.kind == StartupCommandKind.exit) {
      return;
    }
    await _platform.tray.rebuildMenu(state);
  }

  PaperData createPaper(String type, {PaperData? sourcePaper}) {
    final paper = tryCreatePaper(type, sourcePaper: sourcePaper);
    if (paper == null) {
      throw StateError('Paper limit reached.');
    }
    return paper;
  }

  PaperData? tryCreatePaper(String type, {PaperData? sourcePaper}) {
    if (!canCreatePaper) {
      return null;
    }
    final normalizedType = PaperTypes.normalize(type);
    final initialPosition = _newPaperInitialPosition(sourcePaper);
    final paper = PaperData(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
      type: normalizedType,
      title: _defaultTitle(normalizedType),
      x: initialPosition.x,
      y: initialPosition.y,
      width: normalizedType == PaperTypes.note
          ? PaperLayoutDefaults.noteDefaultWidth
          : PaperLayoutDefaults.todoDefaultWidth,
      height: normalizedType == PaperTypes.note
          ? PaperLayoutDefaults.noteDefaultHeight
          : PaperLayoutDefaults.todoDefaultHeight,
      items: normalizedType == PaperTypes.todo
          ? [
              PaperItem(
                  id: DateTime.now().microsecondsSinceEpoch.toRadixString(16))
            ]
          : const [],
      alwaysOnTop: sourcePaper?.alwaysOnTop ?? false,
    );
    if (state.useCapsuleMode && state.useDeepCapsuleMode) {
      _initializeNewPaperCapsuleQueue(paper, sourcePaper);
      if (sourcePaper == null) {
        paper.y = state.deepCapsuleStartTopMargin;
      }
    } else if (sourcePaper != null) {
      _inheritSourcePaperCapsuleQueue(paper, sourcePaper);
    }
    state.papers.add(paper);
    if (paper.isVisible) {
      _paperIdsPendingWorkAreaRescue.add(paper.id);
    }
    if (_canClampNewPaperAwayFromDeepCapsuleStrip(paper)) {
      _paperIdsPendingDeepCapsuleStripClamp.add(paper.id);
    }
    return paper;
  }

  void replaceState(AppState newState) {
    state = newState;
    state.normalize();
  }

  Future<void> applyCurrentStateToPlatform() async {
    state.normalize();
    await _applyStateSettingsToPlatform(stopPersistentWhenDisabled: true);
    await _rescuePapersIntoWorkAreas();
    await _preparePendingNewPapersForFirstShow();
    await _platform.paperWindows.restoreAll(state);
    await _platform.tray.rebuildMenu(state);
  }

  void applyCapsuleSettings({
    required bool useCapsuleMode,
    required bool useDeepCapsuleMode,
    required bool useCapsuleCollapseAll,
    required bool capsuleCollapseAllActive,
    required String deepCapsuleSide,
    required double deepCapsuleStartTopMargin,
    required String deepCapsuleMonitorDeviceName,
    required bool showDeepCapsuleWhileExpanded,
    required bool collapseExpandedDeepCapsuleOnClick,
    required bool hideDeepCapsulesWhenCovered,
  }) {
    state
      ..useCapsuleMode = useCapsuleMode
      ..useDeepCapsuleMode = useDeepCapsuleMode
      ..useCapsuleCollapseAll = useCapsuleCollapseAll
      ..capsuleCollapseAllActive = capsuleCollapseAllActive
      ..deepCapsuleSide = deepCapsuleSide
      ..deepCapsuleStartTopMargin = deepCapsuleStartTopMargin
      ..deepCapsuleMonitorDeviceName = deepCapsuleMonitorDeviceName
      ..showDeepCapsuleWhileExpanded = showDeepCapsuleWhileExpanded
      ..collapseExpandedDeepCapsuleOnClick = collapseExpandedDeepCapsuleOnClick
      ..hideDeepCapsulesWhenCovered = hideDeepCapsulesWhenCovered;

    if (!state.useCapsuleMode) {
      state
        ..useDeepCapsuleMode = false
        ..showDeepCapsuleWhileExpanded = false
        ..collapseExpandedDeepCapsuleOnClick = false
        ..hideDeepCapsulesWhenCovered = false;
      for (final paper in state.papers) {
        paper.isCollapsed = false;
      }
      _clearDeepCapsuleCollapseAllState();
    } else if (!state.useDeepCapsuleMode) {
      state
        ..showDeepCapsuleWhileExpanded = false
        ..collapseExpandedDeepCapsuleOnClick = false
        ..hideDeepCapsulesWhenCovered = false;
      _clearDeepCapsuleCollapseAllState();
    }

    state.normalize();
  }

  void _clearDeepCapsuleCollapseAllState() {
    state
      ..useCapsuleCollapseAll = false
      ..capsuleCollapseAllActive = false
      ..capsuleCollapseAllActiveQueues = <String, bool>{}
      ..deepCapsuleStartTopMargin =
          PaperLayoutDefaults.deepCapsuleStartTopMargin
      ..deepCapsuleQueueStartTopMargins = <String, double>{};
  }

  Future<void> updatePaperSurface(PaperData paper) async {
    await _platform.paperWindows.updatePaperSurface(paper);
  }

  Future<void> capturePaperSurfaceBounds(PaperData paper) async {
    await _platform.paperWindows.capturePaperSurfaceBounds(paper);
  }

  void setPaperAlwaysOnTop(PaperData paper, bool enabled) {
    paper.alwaysOnTop = enabled;
    if (enabled) {
      paper.isPinnedToDesktop = false;
    }
    state.normalize();
  }

  void setPaperPinnedToDesktop(PaperData paper, bool pinned) {
    paper.isPinnedToDesktop = pinned;
    if (pinned) {
      paper
        ..isVisible = true
        ..isCollapsed = false
        ..alwaysOnTop = false;
      state
        ..useCapsuleMode = true
        ..useDeepCapsuleMode = true
        ..showDeepCapsuleWhileExpanded = true;
      if (paper.capsuleSide.trim().isEmpty) {
        paper.capsuleSide = state.deepCapsuleSide;
      }
      if (paper.capsuleMonitorDeviceName.trim().isEmpty) {
        paper.capsuleMonitorDeviceName = state.deepCapsuleMonitorDeviceName;
      }
    } else if (paper.isCollapsed) {
      paper.isCollapsed = false;
    }
    state.normalize();
  }

  Future<void> rebuildTrayMenu() async {
    await _platform.tray.rebuildMenu(state);
  }

  StartupCommand? takePendingUiStartupCommand() {
    final command = _pendingUiStartupCommand;
    _pendingUiStartupCommand = null;
    return command;
  }

  Future<void> setStartupAtLogin(bool enabled) async {
    state.startAtLogin = enabled;
    if (!_platform.systemIntegration.supportsStartupAtLogin) {
      return;
    }
    await _platform.systemIntegration.setStartupAtLogin(enabled);
  }

  Future<void> setHideFromWindowSwitcher(bool enabled) async {
    state.hidePapersFromWindowSwitcher = enabled;
    if (!_platform.systemIntegration.supportsWindowSwitcherVisibility) {
      return;
    }
    await _platform.systemIntegration.setHideFromWindowSwitcher(enabled);
  }

  Future<void> setFullscreenTopmostMode(String mode) async {
    state.fullscreenTopmostMode = mode;
    state.normalize();
    if (!_platform.systemIntegration.supportsFullscreenTopmostMode) {
      return;
    }
    await _platform.systemIntegration
        .setFullscreenTopmostMode(state.fullscreenTopmostMode);
  }

  Future<void> registerGlobalHotkeys() async {
    state.normalize();
    if (!_platform.systemIntegration.supportsGlobalHotkeys) {
      return;
    }
    await _platform.systemIntegration.registerGlobalHotkeys(state);
  }

  Future<void> openExternalFile(String path) async {
    await _platform.externalFiles.openFile(path);
  }

  Future<String> documentsDirectoryPath() {
    return _platform.storage.documentsDirectoryPath();
  }

  Future<void> openUri(String uri) async {
    await _platform.uriOpener.openUri(uri);
  }

  Future<void> runScriptCapsule(ScriptCapsuleSpec spec) async {
    await _platform.scriptCapsules.runScriptCapsule(
      ScriptCapsuleRunRequest(
        engine: spec.engine,
        script: spec.script,
        usePersistentProcess: spec.usePersistentProcess,
        usePersistentPowerShellProcess: state.usePersistentPowerShellProcess,
        preferPowerShell7: state.preferPowerShell7,
        hideScriptRunWindow: state.hideScriptRunWindow,
      ),
    );
  }

  Future<void> stopPersistentScriptCapsules() async {
    if (!_platform.scriptCapsules.supportsScriptCapsules) {
      return;
    }
    await _platform.scriptCapsules.stopPersistentProcesses();
  }

  Future<void> preparePersistentScriptCapsules() async {
    if (!_platform.scriptCapsules.supportsScriptCapsules) {
      return;
    }
    await _platform.scriptCapsules.preparePersistentProcess(
      preferPowerShell7: state.preferPowerShell7,
      hideScriptRunWindow: state.hideScriptRunWindow,
    );
  }

  Future<void> showPaper(PaperData paper) async {
    if (paper.isCollapsed && !_canPaperDisplayAsCapsule(paper)) {
      paper.isCollapsed = false;
    }
    paper.isVisible = true;
    await _prepareNewPaperForFirstShow(paper);
    await _platform.paperWindows.showPaper(paper);
  }

  Future<void> hidePaper(PaperData paper) async {
    paper
      ..isPinnedToDesktop = false
      ..isVisible = false
      ..isCollapsed = false;
    state.normalize();
    await _platform.paperWindows.hidePaper(paper);
  }

  Future<void> executeStartupCommand(StartupCommand command) async {
    switch (command.kind) {
      case StartupCommandKind.none:
        return;
      case StartupCommandKind.show:
        for (final paper in state.papers) {
          await showPaper(paper);
        }
      case StartupCommandKind.hide:
        for (final paper in state.papers) {
          await hidePaper(paper);
        }
      case StartupCommandKind.toggle:
        final shouldHide = state.papers.any((paper) => paper.isVisible);
        await executeStartupCommand(
          StartupCommand(
              shouldHide ? StartupCommandKind.hide : StartupCommandKind.show),
        );
      case StartupCommandKind.newTodo:
        final paper = tryCreatePaper(PaperTypes.todo);
        if (paper != null) {
          await showPaper(paper);
        }
      case StartupCommandKind.newNote:
        final paper = tryCreatePaper(PaperTypes.note);
        if (paper != null) {
          await showPaper(paper);
        }
      case StartupCommandKind.settings:
        _pendingUiStartupCommand = command;
        return;
      case StartupCommandKind.exit:
        if (_platform.systemIntegration.supportsGlobalHotkeys) {
          await _platform.systemIntegration.unregisterGlobalHotkeys();
        }
        await _platform.tray.dispose();
        await _platform.systemIntegration.exitApplication();
    }
  }

  String _defaultTitle(String type) {
    final sameTypeCount =
        state.papers.where((paper) => paper.type == type).length + 1;
    return PaperTitles.defaultTitle(type, sameTypeCount);
  }

  ({double x, double y}) _newPaperInitialPosition(PaperData? sourcePaper) {
    final offset = sourcePaper == null
        ? state.papers.length * PaperLayoutDefaults.newPaperCascadeOffset
        : PaperLayoutDefaults.newPaperSourceOffset;
    var x = sourcePaper == null
        ? PaperLayoutDefaults.newPaperBaseLeft + offset
        : sourcePaper.x + offset;
    var y = sourcePaper == null
        ? PaperLayoutDefaults.newPaperBaseTop + offset
        : sourcePaper.y + offset;
    while (state.papers.any(
      (paper) =>
          (paper.x - x).abs() <
              PaperLayoutDefaults.newPaperCollisionThreshold &&
          (paper.y - y).abs() < PaperLayoutDefaults.newPaperCollisionThreshold,
    )) {
      x += PaperLayoutDefaults.newPaperCollisionNudge;
      y += PaperLayoutDefaults.newPaperCollisionNudge;
    }
    return (x: x, y: y);
  }

  void _initializeNewPaperCapsuleQueue(
    PaperData paper,
    PaperData? sourcePaper,
  ) {
    final sourceSide = sourcePaper?.capsuleSide.trim() ?? '';
    final sourceMonitor = sourcePaper?.capsuleMonitorDeviceName.trim() ?? '';
    paper.capsuleSide = sourceSide.isEmpty
        ? state.deepCapsuleSide
        : DeepCapsuleSides.normalize(sourceSide);
    paper.capsuleMonitorDeviceName = sourceMonitor.isEmpty
        ? state.deepCapsuleMonitorDeviceName
        : sourceMonitor;
  }

  bool _inheritSourcePaperCapsuleQueue(
    PaperData paper,
    PaperData? sourcePaper,
  ) {
    final sourceSide = sourcePaper?.capsuleSide.trim() ?? '';
    final sourceMonitor = sourcePaper?.capsuleMonitorDeviceName.trim() ?? '';
    if (sourceSide.isEmpty && sourceMonitor.isEmpty) {
      return false;
    }
    if (sourceSide.isNotEmpty) {
      paper.capsuleSide = DeepCapsuleSides.normalize(sourceSide);
    }
    paper.capsuleMonitorDeviceName = sourceMonitor;
    return true;
  }

  Future<void> _preparePendingNewPapersForFirstShow() async {
    if (_paperIdsPendingWorkAreaRescue.isEmpty &&
        _paperIdsPendingDeepCapsuleStripClamp.isEmpty) {
      return;
    }
    for (final paper in state.papers.toList()) {
      await _prepareNewPaperForFirstShow(paper);
    }
  }

  Future<void> _rescuePapersIntoWorkAreas() async {
    for (final paper in state.papers.toList()) {
      final area = await _workAreaForPaper(paper);
      if (area == null || !area.isUsable) {
        continue;
      }
      _rescuePaperIntoWorkArea(paper, area);
      _paperIdsPendingWorkAreaRescue.remove(paper.id);
    }
  }

  Future<void> _prepareNewPaperForFirstShow(PaperData paper) async {
    final rescueIntoWorkArea =
        _paperIdsPendingWorkAreaRescue.remove(paper.id) && paper.isVisible;
    final clampAwayFromDeepCapsuleStrip =
        _paperIdsPendingDeepCapsuleStripClamp.remove(paper.id) &&
            _canClampNewPaperAwayFromDeepCapsuleStrip(paper);
    if (!rescueIntoWorkArea && !clampAwayFromDeepCapsuleStrip) {
      return;
    }

    final area = await _workAreaForPaper(paper);
    if (area == null || !area.isUsable) {
      return;
    }
    if (rescueIntoWorkArea) {
      _rescuePaperIntoWorkArea(paper, area);
    }
    if (clampAwayFromDeepCapsuleStrip &&
        _canClampNewPaperAwayFromDeepCapsuleStrip(paper)) {
      _clampNewPaperAwayFromDeepCapsuleStrip(paper, area);
    }
  }

  Future<PaperWorkArea?> _workAreaForPaper(PaperData paper) async {
    try {
      return await _platform.paperWindows.workAreaForPaper(paper);
    } catch (_) {
      return null;
    }
  }

  void _rescuePaperIntoWorkArea(PaperData paper, PaperWorkArea area) {
    final maxWidth = math.max(
      PaperLayoutDefaults.minWidth,
      area.width - PaperLayoutDefaults.newPaperWorkAreaResizeInset,
    );
    final maxHeight = math.max(
      PaperLayoutDefaults.minHeight,
      area.height - PaperLayoutDefaults.newPaperWorkAreaResizeInset,
    );
    paper.width = _clampPaperDimension(
      paper.width,
      paper.isNote
          ? PaperLayoutDefaults.noteDefaultWidth
          : PaperLayoutDefaults.todoDefaultWidth,
      PaperLayoutDefaults.minWidth,
      maxWidth,
    );
    paper.height = _clampPaperDimension(
      paper.height,
      paper.isNote
          ? PaperLayoutDefaults.noteDefaultHeight
          : PaperLayoutDefaults.todoDefaultHeight,
      PaperLayoutDefaults.minHeight,
      maxHeight,
    );

    const margin = PaperLayoutDefaults.newPaperWorkAreaMargin;
    final minX = area.x + margin;
    final maxX = math.max(minX, area.right - paper.width - margin);
    final minY = area.y + margin;
    final maxY = math.max(minY, area.bottom - paper.height - margin);
    paper.x = paper.x.clamp(minX, maxX).roundToDouble();
    paper.y = paper.y.clamp(minY, maxY).roundToDouble();
  }

  double _clampPaperDimension(
    double value,
    double fallback,
    double min,
    double max,
  ) {
    final normalized = value.isFinite && value > 0 ? value : fallback;
    return normalized.clamp(min, max).toDouble().roundToDouble();
  }

  void _clampNewPaperAwayFromDeepCapsuleStrip(
    PaperData paper,
    PaperWorkArea area,
  ) {
    const margin = PaperLayoutDefaults.deepCapsuleEdgeMargin;
    final width = math.max(paper.width, PaperLayoutDefaults.minWidth);
    final height = math.max(paper.height, PaperLayoutDefaults.minHeight);
    final edgeInset = math.min(
      math.max(
        PaperLayoutDefaults.deepCapsuleExpandedEdgeInset,
        PaperLayoutDefaults.capsuleWidth + PaperLayoutDefaults.deepCapsuleGap,
      ),
      math.max(0, area.width - width),
    );

    var minX = area.x + margin;
    var maxX = math.max(minX, area.right - width - margin);
    if (paper.capsuleSide == DeepCapsuleSides.left) {
      minX = math.min(maxX, math.max(minX, area.x + edgeInset));
    } else {
      maxX = math.max(
        minX,
        math.min(maxX, area.right - width - edgeInset),
      );
    }

    final minY = area.y + margin;
    final maxY = math.max(minY, area.bottom - height - margin);
    paper.x = paper.x.clamp(minX, maxX).roundToDouble();
    paper.y = paper.y.clamp(minY, maxY).roundToDouble();
  }

  bool _canClampNewPaperAwayFromDeepCapsuleStrip(PaperData paper) {
    return paper.isVisible &&
        state.useCapsuleMode &&
        state.useDeepCapsuleMode &&
        state.showDeepCapsuleWhileExpanded &&
        _canPaperDisplayAsCapsule(paper);
  }

  bool _canPaperDisplayAsCapsule(PaperData paper) {
    if (!state.useCapsuleMode) {
      return false;
    }
    if (!state.enableTodoNoteLinks ||
        !state.hideLinkedNotesFromCapsules ||
        !paper.isNote) {
      return true;
    }
    return !state.papers
        .where((sourcePaper) => sourcePaper.isTodo)
        .expand((sourcePaper) => sourcePaper.items)
        .any((item) => item.linkedNoteId == paper.id);
  }

  Future<void> _applyStateSettingsToPlatform({
    bool stopPersistentWhenDisabled = false,
  }) async {
    Future<void> ignorePlatformFailure(Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        return;
      }
    }

    if (_platform.systemIntegration.supportsGlobalHotkeys) {
      await ignorePlatformFailure(
        () => _platform.systemIntegration.registerGlobalHotkeys(state),
      );
    }
    if (_platform.systemIntegration.supportsStartupAtLogin) {
      await ignorePlatformFailure(
        () => _platform.systemIntegration.setStartupAtLogin(state.startAtLogin),
      );
    }
    if (_platform.systemIntegration.supportsWindowSwitcherVisibility) {
      await ignorePlatformFailure(
        () => _platform.systemIntegration
            .setHideFromWindowSwitcher(state.hidePapersFromWindowSwitcher),
      );
    }
    if (_platform.systemIntegration.supportsFullscreenTopmostMode) {
      await ignorePlatformFailure(
        () => _platform.systemIntegration
            .setFullscreenTopmostMode(state.fullscreenTopmostMode),
      );
    }
    if (state.usePersistentPowerShellProcess &&
        _platform.scriptCapsules.supportsScriptCapsules) {
      await ignorePlatformFailure(preparePersistentScriptCapsules);
    } else if (stopPersistentWhenDisabled) {
      await ignorePlatformFailure(stopPersistentScriptCapsules);
    }
  }
}
