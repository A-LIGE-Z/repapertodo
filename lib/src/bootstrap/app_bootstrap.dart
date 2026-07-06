import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_controller.dart';
import '../core/storage/state_store.dart';
import '../core/startup/startup_command.dart';
import '../platform/android_platform_services.dart';
import '../platform/noop_platform_services.dart';
import '../platform/platform_services.dart';
import '../platform/windows_platform_services.dart';
import '../sync/app_sync_service.dart';

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

  static Future<BootstrappedApp?> load(
    List<String> args, {
    PlatformServices? platform,
    StateStore? store,
    AppSyncService? syncService,
  }) async {
    final resolvedPlatform = platform ?? _defaultPlatformServices();
    final acquiredSingleInstance =
        await resolvedPlatform.startup.acquireSingleInstance();
    if (!acquiredSingleInstance) {
      await resolvedPlatform.startup.forwardToPrimary(args);
      return null;
    }

    final resolvedStore = store ??
        StateStore(
          filePath: await defaultStateFilePath(platform: resolvedPlatform),
        );
    final state = await resolvedStore.load();
    final startupCommand = StartupCommand.parse(args);
    final controller = RePaperTodoController(
      initialState: state,
      platform: resolvedPlatform,
    );
    await controller.start(startupCommand: startupCommand);
    if (startupCommand.kind == StartupCommandKind.exit) {
      await resolvedStore.save(controller.state);
      return null;
    }
    if (controller.state.sync.enabled &&
        controller.state.sync.webDav.autoSyncOnStart) {
      try {
        final result = await (syncService ?? AppSyncService()).syncAndMergeNow(
          localState: controller.state,
          store: resolvedStore,
        );
        controller.replaceState(result.state);
        await controller.applyCurrentStateToPlatform();
      } catch (_) {
        // Startup sync is opportunistic; local data must remain usable offline.
      }
    }
    await resolvedStore.save(controller.state);
    return BootstrappedApp(
      controller: controller,
      store: resolvedStore,
    );
  }

  static Future<String> defaultStateFilePath({
    PlatformServices? platform,
    Future<String> Function()? mobileDocumentsDirectoryPath,
  }) async {
    return defaultStateFilePathForPlatform(
      isDesktop: Platform.isWindows || Platform.isLinux || Platform.isMacOS,
      desktopExecutablePath: Platform.resolvedExecutable,
      mobileDocumentsDirectoryPath: mobileDocumentsDirectoryPath ??
          (platform ?? NoopPlatformServices()).storage.documentsDirectoryPath,
    );
  }

  static Future<String> defaultStateFilePathForPlatform({
    required bool isDesktop,
    required String desktopExecutablePath,
    required Future<String> Function() mobileDocumentsDirectoryPath,
  }) async {
    if (isDesktop) {
      final executablePath = desktopExecutablePath.trim();
      if (executablePath.isEmpty) {
        throw StateError('Desktop executable path is unavailable.');
      }
      return p.join(p.dirname(executablePath), 'data.json');
    }
    final directoryPath = (await mobileDocumentsDirectoryPath()).trim();
    if (directoryPath.isEmpty) {
      throw StateError('Mobile documents directory is unavailable.');
    }
    return p.join(directoryPath, 'data.json');
  }

  static PlatformServices _defaultPlatformServices() {
    if (Platform.isWindows) {
      return WindowsPlatformServices();
    }
    if (Platform.isAndroid) {
      return AndroidPlatformServices();
    }
    return NoopPlatformServices();
  }
}
