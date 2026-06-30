import 'dart:async';

import '../core/model/app_state.dart';
import '../core/model/paper_data.dart';
import '../core/startup/startup_command.dart';
import 'platform_services.dart';

class NoopPlatformServices implements PlatformServices {
  NoopPlatformServices()
      : paperWindows = NoopPaperWindowHost(),
        tray = NoopTrayHost(),
        startup = NoopStartupHost(),
        systemIntegration = NoopSystemIntegrationHost();

  @override
  final PaperWindowHost paperWindows;

  @override
  final TrayHost tray;

  @override
  final StartupHost startup;

  @override
  final SystemIntegrationHost systemIntegration;
}

class NoopPaperWindowHost implements PaperWindowHost {
  @override
  Stream<PaperData> get surfaceUpdates => const Stream.empty();

  @override
  Future<void> capturePaperSurfaceBounds(PaperData paper) async {}

  @override
  Future<void> closePaperSurface(PaperData paper) async {}

  @override
  Future<void> hidePaper(PaperData paper) async {}

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
  Future<void> rebuildMenu(AppState state) async {}
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
  Future<bool> isForegroundFullscreen() async => false;

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {}

  @override
  Future<void> setStartupAtLogin(bool enabled) async {}

  @override
  Future<void> unregisterGlobalHotkeys() async {}
}
