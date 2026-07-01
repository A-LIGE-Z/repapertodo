import 'dart:async';

import '../core/model/app_state.dart';
import '../core/model/paper_data.dart';
import '../core/script/script_capsule.dart';
import '../core/startup/startup_command.dart';

abstract interface class PlatformServices {
  PaperWindowHost get paperWindows;
  TrayHost get tray;
  StartupHost get startup;
  SystemIntegrationHost get systemIntegration;
  ExternalFileHost get externalFiles;
  UriOpenHost get uriOpener;
  ScriptCapsuleHost get scriptCapsules;
}

abstract interface class PaperWindowHost {
  Stream<PaperData> get surfaceUpdates;
  Stream<String> get paperOpenRequests;

  Future<void> showPaper(PaperData paper);
  Future<void> hidePaper(PaperData paper);
  Future<void> closePaperSurface(PaperData paper);
  Future<void> updatePaperSurface(PaperData paper);
  Future<void> capturePaperSurfaceBounds(PaperData paper);
  Future<void> restoreAll(AppState state);
}

abstract interface class TrayHost {
  Future<void> initialize();
  Future<void> rebuildMenu(AppState state);
  Future<void> dispose();
}

abstract interface class StartupHost {
  Future<bool> acquireSingleInstance();
  Future<void> forwardToPrimary(List<String> args);
  Stream<StartupCommand> get commands;
}

abstract interface class SystemIntegrationHost {
  Future<void> registerGlobalHotkeys(AppState state);
  Future<void> unregisterGlobalHotkeys();
  Future<bool> isForegroundFullscreen();
  Future<void> setStartupAtLogin(bool enabled);
  Future<void> setHideFromWindowSwitcher(bool enabled);
  Future<void> setFullscreenTopmostMode(String mode);
}

abstract interface class ExternalFileHost {
  Future<void> openFile(String path);
}

abstract interface class UriOpenHost {
  Future<void> openUri(String uri);
}

abstract interface class ScriptCapsuleHost {
  Future<void> preparePersistentProcess({
    required bool preferPowerShell7,
    required bool hideScriptRunWindow,
  });
  Future<void> runScriptCapsule(ScriptCapsuleRunRequest request);
  Future<void> stopPersistentProcesses();
}
