import 'dart:async';

import 'core/model/app_state.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
import 'core/model/paper_item.dart';
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

  Stream<PaperData> get paperSurfaceUpdates =>
      _platform.paperWindows.surfaceUpdates;

  Stream<String> get paperOpenRequests =>
      _platform.paperWindows.paperOpenRequests;

  Stream<StartupCommand> get startupCommands => _platform.startup.commands;

  Future<void> start(
      {StartupCommand startupCommand =
          const StartupCommand(StartupCommandKind.none)}) async {
    await _platform.tray.initialize();
    await _platform.systemIntegration.registerGlobalHotkeys(state);
    await _platform.systemIntegration.setStartupAtLogin(state.startAtLogin);
    await _platform.systemIntegration
        .setHideFromWindowSwitcher(state.hidePapersFromWindowSwitcher);
    await _platform.systemIntegration
        .setFullscreenTopmostMode(state.fullscreenTopmostMode);

    if (state.papers.isEmpty && !startupCommand.createsPaper) {
      createPaper(PaperTypes.todo);
    }

    await _platform.paperWindows.restoreAll(state);
    await executeStartupCommand(startupCommand);
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
    return paper;
  }

  void replaceState(AppState newState) {
    state = newState;
    state.normalize();
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

  Future<void> setStartupAtLogin(bool enabled) async {
    state.startAtLogin = enabled;
    await _platform.systemIntegration.setStartupAtLogin(enabled);
  }

  Future<void> setHideFromWindowSwitcher(bool enabled) async {
    state.hidePapersFromWindowSwitcher = enabled;
    await _platform.systemIntegration.setHideFromWindowSwitcher(enabled);
  }

  Future<void> setFullscreenTopmostMode(String mode) async {
    state.fullscreenTopmostMode = mode;
    state.normalize();
    await _platform.systemIntegration
        .setFullscreenTopmostMode(state.fullscreenTopmostMode);
  }

  Future<void> registerGlobalHotkeys() async {
    state.normalize();
    await _platform.systemIntegration.registerGlobalHotkeys(state);
  }

  Future<void> openExternalFile(String path) async {
    await _platform.externalFiles.openFile(path);
  }

  Future<void> showPaper(PaperData paper) async {
    paper.isVisible = true;
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
        await _platform.paperWindows.showPaper(createPaper(PaperTypes.todo));
      case StartupCommandKind.newNote:
        await _platform.paperWindows.showPaper(createPaper(PaperTypes.note));
      case StartupCommandKind.exit:
        await _platform.systemIntegration.unregisterGlobalHotkeys();
        await _platform.tray.dispose();
    }
  }

  String _defaultTitle(String type) {
    final sameTypeCount =
        state.papers.where((paper) => paper.type == type).length + 1;
    return type == PaperTypes.note
        ? 'Note$sameTypeCount'
        : 'Todo$sameTypeCount';
  }
}
