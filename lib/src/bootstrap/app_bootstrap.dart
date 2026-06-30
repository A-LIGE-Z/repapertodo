import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_controller.dart';
import '../core/storage/state_store.dart';
import '../core/startup/startup_command.dart';
import '../platform/noop_platform_services.dart';
import '../platform/platform_services.dart';

class BootstrappedApp {
  const BootstrappedApp({
    required this.controller,
    required this.store,
  });

  final RePaperTodoController controller;
  final StateStore store;
}

class AppBootstrap {
  const AppBootstrap._();

  static Future<BootstrappedApp> load(
    List<String> args, {
    PlatformServices? platform,
    StateStore? store,
  }) async {
    final resolvedStore = store ?? StateStore(filePath: await defaultStateFilePath());
    final state = await resolvedStore.load();
    final resolvedPlatform = platform ?? NoopPlatformServices();
    final startupCommand = StartupCommand.parse(args);
    final controller = RePaperTodoController(
      initialState: state,
      platform: resolvedPlatform,
    );
    await controller.start(startupCommand: startupCommand);
    await resolvedStore.save(controller.state);
    return BootstrappedApp(
      controller: controller,
      store: resolvedStore,
    );
  }

  static Future<String> defaultStateFilePath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return p.join(p.dirname(Platform.resolvedExecutable), 'data.json');
    }
    return p.join(Directory.current.path, 'data.json');
  }
}
