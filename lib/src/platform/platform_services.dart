import 'dart:async';

import '../core/model/app_state.dart';
import '../core/model/paper_data.dart';
import '../core/startup/startup_command.dart';

abstract interface class PlatformServices {
  PaperWindowHost get paperWindows;
  TrayHost get tray;
  StartupHost get startup;
  SystemIntegrationHost get systemIntegration;
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
}
