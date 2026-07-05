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

    await _clampPendingNewPapersAwayFromDeepCapsuleStrip();
    await _platform.paperWindows.restoreAll(state);
    await executeStartupCommand(startupCommand);
    if (startupCommand.kind == StartupCommandKind.exit) {
      return;
    }
    await _platform.tray.rebuildMenu(state);
  }

  PaperData createPaper(String type) {
    final normalizedType = PaperTypes.normalize(type);
    final paper = PaperData(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
      type: normalizedType,
      title: _defaultTitle(normalizedType),
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
    );
    if (state.useCapsuleMode && state.useDeepCapsuleMode) {
      paper.capsuleSide = state.deepCapsuleSide;
      paper.capsuleMonitorDeviceName = state.deepCapsuleMonitorDeviceName;
      paper.y = state.deepCapsuleStartTopMargin;
    }
    state.papers.add(paper);
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
    await _platform.paperWindows.restoreAll(state);
    await _platform.tray.rebuildMenu(state);
  }

  Future<void> updatePaperSurface(PaperData paper) async {
    await _platform.paperWindows.updatePaperSurface(paper);
  }

  Future<void> capturePaperSurfaceBounds(PaperData paper) async {
    await _platform.paperWindows.capturePaperSurfaceBounds(paper);
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
    paper.isVisible = true;
    await _clampNewPaperAwayFromDeepCapsuleStrip(paper);
    await _platform.paperWindows.showPaper(paper);
  }

  Future<void> hidePaper(PaperData paper) async {
    paper.isVisible = false;
    await _platform.paperWindows.hidePaper(paper);
  }

  Future<void> executeStartupCommand(StartupCommand command) async {
    switch (command.kind) {
      case StartupCommandKind.none:
        return;
      case StartupCommandKind.show:
        for (final paper in state.papers) {
          paper.isVisible = true;
          await _platform.paperWindows.showPaper(paper);
        }
      case StartupCommandKind.hide:
        for (final paper in state.papers) {
          paper.isVisible = false;
          await _platform.paperWindows.hidePaper(paper);
        }
      case StartupCommandKind.toggle:
        final shouldHide = state.papers.any((paper) => paper.isVisible);
        await executeStartupCommand(
          StartupCommand(
              shouldHide ? StartupCommandKind.hide : StartupCommandKind.show),
        );
      case StartupCommandKind.newTodo:
        await showPaper(createPaper(PaperTypes.todo));
      case StartupCommandKind.newNote:
        await showPaper(createPaper(PaperTypes.note));
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

  Future<void> _clampPendingNewPapersAwayFromDeepCapsuleStrip() async {
    if (_paperIdsPendingDeepCapsuleStripClamp.isEmpty) {
      return;
    }
    for (final paper in state.papers.toList()) {
      await _clampNewPaperAwayFromDeepCapsuleStrip(paper);
    }
  }

  Future<void> _clampNewPaperAwayFromDeepCapsuleStrip(PaperData paper) async {
    if (!_paperIdsPendingDeepCapsuleStripClamp.remove(paper.id) ||
        !_canClampNewPaperAwayFromDeepCapsuleStrip(paper)) {
      return;
    }
    final PaperWorkArea? area;
    try {
      area = await _platform.paperWindows.workAreaForPaper(paper);
    } catch (_) {
      return;
    }
    if (area == null || !area.isUsable) {
      return;
    }

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
