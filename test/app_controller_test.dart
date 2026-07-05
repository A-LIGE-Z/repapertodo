import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('new papers inherit deep capsule defaults', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        deepCapsuleSide: DeepCapsuleSides.left,
        deepCapsuleMonitorDeviceName: '  Primary monitor  ',
        deepCapsuleStartTopMargin: 72,
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(PaperTypes.note);

    expect(paper.capsuleSide, DeepCapsuleSides.left);
    expect(paper.capsuleMonitorDeviceName, 'Primary monitor');
    expect(paper.y, 72);
  });

  test('new papers skip deep capsule defaults when disabled', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        deepCapsuleSide: DeepCapsuleSides.left,
        useDeepCapsuleMode: false,
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(PaperTypes.note);

    expect(paper.capsuleSide, isEmpty);
    expect(paper.capsuleMonitorDeviceName, isEmpty);
    expect(paper.y, 120);
  });

  test('startup show and hide commands apply every paper', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'First'),
          PaperData(
            id: 'paper-2',
            type: PaperTypes.note,
            title: 'Second',
            isVisible: false,
          ),
        ],
      ),
      platform: platform,
    );

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.hide),
    );

    expect(controller.state.papers.map((paper) => paper.isVisible), [
      false,
      false,
    ]);
    expect(platform.paperWindows.hiddenIds, ['paper-1', 'paper-2']);

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.show),
    );

    expect(controller.state.papers.map((paper) => paper.isVisible), [
      true,
      true,
    ]);
    expect(platform.paperWindows.shownIds, ['paper-1', 'paper-2']);
  });

  test('startup settings command is retained for the UI layer', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'paper-1',
            type: PaperTypes.todo,
            title: 'Todo',
          ),
        ],
      ),
      platform: platform,
    );

    await controller.start(
      startupCommand: const StartupCommand(StartupCommandKind.settings),
    );

    expect(
      controller.takePendingUiStartupCommand()?.kind,
      StartupCommandKind.settings,
    );
    expect(controller.takePendingUiStartupCommand(), isNull);
  });

  test('startup exit command cleans up platform integrations then exits',
      () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'First'),
        ],
      ),
      platform: platform,
    );

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.exit),
    );

    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.tray.disposeCount, 1);
    expect(platform.systemIntegration.exitApplicationCount, 1);
  });

  test('startup exit command does not create a default paper', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(papers: const []),
      platform: platform,
    );

    await controller.start(
      startupCommand: const StartupCommand(StartupCommandKind.exit),
    );

    expect(controller.state.papers, isEmpty);
    expect(platform.paperWindows.restoreAllCount, 1);
    expect(platform.tray.rebuildMenuCount, 0);
    expect(platform.systemIntegration.exitApplicationCount, 1);
  });

  test('start continues when a platform setting fails', () async {
    final platform = _RecordingPlatformServices();
    platform.systemIntegration.registerGlobalHotkeysError =
        StateError('Hotkeys unavailable');
    final controller = RePaperTodoController(
      initialState: AppState(
        startAtLogin: true,
        hidePapersFromWindowSwitcher: true,
        fullscreenTopmostMode: FullscreenTopmostModes.stayOnTop,
        usePersistentPowerShellProcess: true,
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'First'),
        ],
      ),
      platform: platform,
    );

    await controller.start();

    expect(platform.systemIntegration.registerGlobalHotkeysCalls, 1);
    expect(platform.systemIntegration.startupAtLoginValues, [true]);
    expect(platform.systemIntegration.hideFromWindowSwitcherValues, [true]);
    expect(platform.systemIntegration.fullscreenTopmostModes, [
      FullscreenTopmostModes.stayOnTop,
    ]);
    expect(platform.scriptCapsules.prepareCount, 1);
    expect(platform.paperWindows.restoreAllCount, 1);
    expect(platform.tray.rebuildMenuCount, 1);
  });
}

class _RecordingPlatformServices implements PlatformServices {
  @override
  final _RecordingPaperWindowHost paperWindows = _RecordingPaperWindowHost();

  @override
  final _RecordingTrayHost tray = _RecordingTrayHost();

  @override
  final StartupHost startup = NoopStartupHost();

  @override
  final _RecordingSystemIntegrationHost systemIntegration =
      _RecordingSystemIntegrationHost();

  @override
  final ExternalFileHost externalFiles = NoopExternalFileHost();

  @override
  final UriOpenHost uriOpener = NoopUriOpenHost();

  @override
  final _RecordingScriptCapsuleHost scriptCapsules =
      _RecordingScriptCapsuleHost();

  @override
  final AppStorageHost storage = NoopAppStorageHost();
}

class _RecordingTrayHost extends NoopTrayHost {
  var disposeCount = 0;
  var rebuildMenuCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }

  @override
  Future<void> rebuildMenu(AppState state) async {
    rebuildMenuCount += 1;
  }
}

class _RecordingPaperWindowHost extends NoopPaperWindowHost {
  final shownIds = <String>[];
  final hiddenIds = <String>[];
  var restoreAllCount = 0;

  @override
  Future<void> restoreAll(AppState state) async {
    restoreAllCount += 1;
  }

  @override
  Future<void> showPaper(PaperData paper) async {
    shownIds.add(paper.id);
  }

  @override
  Future<void> hidePaper(PaperData paper) async {
    hiddenIds.add(paper.id);
  }
}

class _RecordingSystemIntegrationHost extends NoopSystemIntegrationHost {
  @override
  bool get supportsStartupAtLogin => true;

  @override
  bool get supportsWindowSwitcherVisibility => true;

  @override
  bool get supportsFullscreenTopmostMode => true;

  @override
  bool get supportsGlobalHotkeys => true;

  final startupAtLoginValues = <bool>[];
  final hideFromWindowSwitcherValues = <bool>[];
  final fullscreenTopmostModes = <String>[];
  Object? registerGlobalHotkeysError;
  var registerGlobalHotkeysCalls = 0;
  var unregisterGlobalHotkeysCount = 0;
  var exitApplicationCount = 0;

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {
    registerGlobalHotkeysCalls += 1;
    final error = registerGlobalHotkeysError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setStartupAtLogin(bool enabled) async {
    startupAtLoginValues.add(enabled);
  }

  @override
  Future<void> setHideFromWindowSwitcher(bool enabled) async {
    hideFromWindowSwitcherValues.add(enabled);
  }

  @override
  Future<void> setFullscreenTopmostMode(String mode) async {
    fullscreenTopmostModes.add(mode);
  }

  @override
  Future<void> unregisterGlobalHotkeys() async {
    unregisterGlobalHotkeysCount += 1;
  }

  @override
  Future<void> exitApplication() async {
    exitApplicationCount += 1;
  }
}

class _RecordingScriptCapsuleHost extends NoopScriptCapsuleHost {
  @override
  bool get supportsScriptCapsules => true;

  var prepareCount = 0;

  @override
  Future<void> preparePersistentProcess({
    required bool preferPowerShell7,
    required bool hideScriptRunWindow,
  }) async {
    prepareCount += 1;
  }
}
