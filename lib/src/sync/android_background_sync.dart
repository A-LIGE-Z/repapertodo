import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/model/sync_settings.dart';
import '../core/storage/state_store.dart';
import 'app_sync_service.dart';

const androidBackgroundSyncUniqueName = 'repapertodo-periodic-webdav-sync';
const androidBackgroundSyncTaskName = 'repapertodo.webdav.sync';
const androidBackgroundSyncTag = 'repapertodo.webdav';
const androidBackgroundSyncStateFilePathKey = 'stateFilePath';

abstract interface class RePaperTodoAndroidBackgroundScheduler {
  Future<void> initialize(Function callbackDispatcher);

  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    Map<String, dynamic>? inputData,
  });

  Future<void> cancelByUniqueName(String uniqueName);
}

class WorkmanagerRePaperTodoAndroidBackgroundScheduler
    implements RePaperTodoAndroidBackgroundScheduler {
  WorkmanagerRePaperTodoAndroidBackgroundScheduler([Workmanager? workmanager])
      : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  @override
  Future<void> initialize(Function callbackDispatcher) {
    return _workmanager.initialize(callbackDispatcher);
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    Map<String, dynamic>? inputData,
  }) {
    return _workmanager.registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: frequency,
      constraints: constraints,
      existingWorkPolicy: existingWorkPolicy,
      backoffPolicy: backoffPolicy,
      backoffPolicyDelay: backoffPolicyDelay,
      tag: tag,
      inputData: inputData,
    );
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) {
    return _workmanager.cancelByUniqueName(uniqueName);
  }
}

@pragma('vm:entry-point')
void repapertodoBackgroundSyncDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != androidBackgroundSyncTaskName) {
      return true;
    }
    return runRePaperTodoBackgroundSync(inputData);
  });
}

Future<void> initializeRePaperTodoAndroidBackgroundSync({
  bool? isAndroid,
  Workmanager? workmanager,
  RePaperTodoAndroidBackgroundScheduler? scheduler,
}) async {
  if (!(isAndroid ?? Platform.isAndroid)) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  await (scheduler ??
          WorkmanagerRePaperTodoAndroidBackgroundScheduler(workmanager))
      .initialize(
    repapertodoBackgroundSyncDispatcher,
  );
}

Future<void> configureRePaperTodoAndroidBackgroundSync({
  required SyncSettings sync,
  required String stateFilePath,
  bool? isAndroid,
  Workmanager? workmanager,
  RePaperTodoAndroidBackgroundScheduler? scheduler,
}) async {
  if (!(isAndroid ?? Platform.isAndroid)) {
    return;
  }
  final manager = scheduler ??
      WorkmanagerRePaperTodoAndroidBackgroundScheduler(workmanager);
  final normalizedStateFilePath =
      _normalizeBackgroundStateFilePath(stateFilePath);
  if (!sync.enabled ||
      sync.provider != SyncProviderIds.webDav ||
      !sync.webDav.isSecurelyConfigured ||
      normalizedStateFilePath.isEmpty) {
    await manager.cancelByUniqueName(androidBackgroundSyncUniqueName);
    return;
  }
  await manager.registerPeriodicTask(
    androidBackgroundSyncUniqueName,
    androidBackgroundSyncTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 5),
    tag: androidBackgroundSyncTag,
    inputData: {
      androidBackgroundSyncStateFilePathKey: normalizedStateFilePath,
    },
  );
}

Future<bool> runRePaperTodoBackgroundSync(
  Map<String, dynamic>? inputData, {
  AppSyncService? syncService,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final rawPath = inputData?[androidBackgroundSyncStateFilePathKey];
  if (rawPath is! String) {
    return false;
  }
  final stateFilePath = _normalizeBackgroundStateFilePath(rawPath);
  if (stateFilePath.isEmpty) {
    return false;
  }

  final store = StateStore(filePath: stateFilePath);
  try {
    final state = await store.load();
    final sync = state.sync;
    if (!sync.enabled ||
        sync.provider != SyncProviderIds.webDav ||
        !sync.webDav.isSecurelyConfigured) {
      return true;
    }
    final result = await (syncService ?? AppSyncService()).syncAndMergeNow(
      localState: state,
      store: store,
    );
    await store.save(result.state);
    return _backgroundSyncCompletedWithoutRetry(result.syncResult.status);
  } catch (_) {
    return false;
  }
}

bool _backgroundSyncCompletedWithoutRetry(AppSyncStatus status) {
  return switch (status) {
    AppSyncStatus.disabled ||
    AppSyncStatus.configurationMissing ||
    AppSyncStatus.uploaded ||
    AppSyncStatus.downloaded ||
    AppSyncStatus.payloadUnreadable =>
      true,
    AppSyncStatus.conflict => false,
  };
}

String _normalizeBackgroundStateFilePath(String value) {
  if (_hasControlCharacter(value)) {
    return '';
  }
  final path = value.trim();
  if (!_isAbsoluteBackgroundStateFilePath(path)) {
    return '';
  }
  return path;
}

bool _isAbsoluteBackgroundStateFilePath(String value) {
  if (value.startsWith('/')) {
    return true;
  }
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
    return true;
  }
  return value.startsWith(r'\\');
}

bool _hasControlCharacter(String value) {
  return value.runes.any(
    (rune) => rune < 0x20 || (rune >= 0x7F && rune <= 0x9F),
  );
}
