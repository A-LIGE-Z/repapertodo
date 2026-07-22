import 'dart:async';
import 'dart:io';

import '../core/model/app_state.dart';
import '../core/model/paper_data.dart';
import '../core/script/script_capsule.dart';
import '../core/startup/startup_command.dart';
import 'platform_services.dart';

class NoopPlatformServices implements PlatformServices {
  NoopPlatformServices()
      : paperWindows = NoopPaperWindowHost(),
        tray = NoopTrayHost(),
        startup = NoopStartupHost(),
        systemIntegration = NoopSystemIntegrationHost(),
        externalFiles = NoopExternalFileHost(),
        uriOpener = NoopUriOpenHost(),
        scriptCapsules = NoopScriptCapsuleHost(),
        storage = NoopAppStorageHost();

  @override
  final PaperWindowHost paperWindows;

  @override
  final TrayHost tray;

  @override
  final StartupHost startup;

  @override
  final SystemIntegrationHost systemIntegration;

  @override
  final ExternalFileHost externalFiles;

  @override
  final UriOpenHost uriOpener;

  @override
  final ScriptCapsuleHost scriptCapsules;

  @override
  final AppStorageHost storage;
}

class NoopPaperWindowHost implements PaperWindowHost {
  @override
  Stream<void> get coordinatorCloseRequests => const Stream.empty();

  @override
  Stream<String> get paperDeleteRequests => const Stream.empty();

  @override
  Stream<String> get paperOpenRequests => const Stream.empty();

  @override
  Stream<PaperData> get surfaceUpdates => const Stream.empty();

  @override
  Stream<PaperData> get paperEdits => const Stream.empty();

  @override
  Stream<PaperWindowActionRequest> get actionRequests => const Stream.empty();

  @override
  Stream<CapsuleDropRequest> get capsuleDrops => const Stream.empty();

  @override
  Future<PaperWorkArea?> workAreaForPaper(PaperData paper) async => null;

  @override
  Future<void> capturePaperSurfaceBounds(PaperData paper) async {}

  @override
  Future<void> closePaperSurface(PaperData paper) async {}

  @override
  Future<void> hidePaper(PaperData paper) async {}

  @override
  Future<void> hideCoordinatorWindow() async {}

  @override
  Future<void> setCoordinatorBackgroundColor(int argb) async {}

  @override
  Future<void> revealPinnedPaper(PaperData paper) async {}

  @override
  Future<bool> hasVisibleSurfaces(AppState state) async {
    return state.papers.any((paper) => paper.isVisible);
  }

  @override
  Future<bool> hasVisibleSurface(PaperData paper) async => paper.isVisible;

  @override
  Future<void> refreshSurfaceRegistry(AppState state) async {}

  @override
  Future<void> restoreAll(AppState state) async {}

  @override
  Future<void> showPaper(PaperData paper) async {}

  @override
  Future<void> updatePaperSurface(PaperData paper) async {}
}

class NoopTrayHost implements TrayHost {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> rebuildMenu(AppState state, {TrayMenuLabels? labels}) async {}
}

class NoopStartupHost implements StartupHost {
  @override
  Future<bool> acquireSingleInstance() async => true;

  @override
  Stream<StartupCommand> get commands => const Stream.empty();

  @override
  Future<void> forwardToPrimary(List<String> args) async {}
}

class NoopSystemIntegrationHost implements SystemIntegrationHost {
  @override
  bool get supportsStartupAtLogin => false;

  @override
  bool get supportsWindowSwitcherVisibility => false;

  @override
  bool get supportsFullscreenTopmostMode => false;

  @override
  bool get supportsGlobalHotkeys => false;

  @override
  bool get supportsCustomColorPicker => false;

  @override
  Future<bool> isForegroundFullscreen() async => false;

  @override
  Future<List<String>> installedFontFamilies() async => const [];

  @override
  Future<String?> chooseCustomColor(String initialColorHex) async => null;

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {}

  @override
  Future<void> setStartupAtLogin(bool enabled) async {}

  @override
  Future<void> setHideFromWindowSwitcher(bool enabled) async {}

  @override
  Future<void> setFullscreenTopmostMode(String mode) async {}

  @override
  Future<void> unregisterGlobalHotkeys() async {}

  @override
  Future<void> exitApplication() async {}
}

class NoopExternalFileHost implements ExternalFileHost {
  @override
  Future<void> openFile(String path) async {
    throw UnsupportedError('External file opening is not supported here.');
  }
}

class NoopUriOpenHost implements UriOpenHost {
  @override
  Future<void> openUri(String uri) async {}
}

class NoopScriptCapsuleHost implements ScriptCapsuleHost {
  @override
  bool get supportsScriptCapsules => false;

  @override
  Future<void> preparePersistentProcess({
    required bool preferPowerShell7,
    required bool hideScriptRunWindow,
  }) async {}

  @override
  Future<void> runScriptCapsule(ScriptCapsuleRunRequest request) async {}

  @override
  Future<void> stopPersistentProcesses() async {}
}

class NoopAppStorageHost implements AppStorageHost {
  @override
  bool get supportsDataDirectorySelection => false;

  @override
  Future<String> documentsDirectoryPath() async {
    return Directory.current.path;
  }

  @override
  Future<String?> chooseDataDirectory(String currentDirectoryPath) async =>
      null;

  @override
  Future<void> commitDataDirectory(String directoryPath) async {}
}
