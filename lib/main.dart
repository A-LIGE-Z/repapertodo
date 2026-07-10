import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/bootstrap/app_bootstrap.dart';
import 'src/bootstrap/crash_recovery.dart';
import 'src/sync/android_background_sync.dart';

Future<void> main(List<String> args) async {
  BootstrappedApp? activeBootstrap;
  const crashRecovery = CrashRecoveryWriter();

  void preserveCrashRecovery(Object error, StackTrace? stackTrace) {
    final bootstrap = activeBootstrap;
    if (bootstrap == null) {
      return;
    }
    try {
      crashRecovery.saveSync(
        store: bootstrap.store,
        state: bootstrap.controller.state,
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {
      // Crash recovery must never replace the original failure.
    }
  }

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final bootstrap = await AppBootstrap.load(args);
      if (bootstrap == null) {
        return;
      }
      activeBootstrap = bootstrap;
      await initializeRePaperTodoAndroidBackgroundSync();
      await configureRePaperTodoAndroidBackgroundSync(
        sync: bootstrap.controller.state.sync,
        stateFilePath: bootstrap.store.filePath,
      );

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        preserveCrashRecovery(details.exception, details.stack);
      };
      PlatformDispatcher.instance.onError = (error, stackTrace) {
        preserveCrashRecovery(error, stackTrace);
        return false;
      };

      runApp(
        RePaperTodoApp(
          controller: bootstrap.controller,
          store: bootstrap.store,
        ),
      );
    },
    preserveCrashRecovery,
  );
}
