import '../core/model/app_state.dart';
import '../core/model/sync_settings.dart';
import '../core/storage/state_store.dart';
import 'sync_device_id_store.dart';
import 'sync_operation.dart';
import 'sync_operation_applier.dart';
import 'webdav/webdav_state_sync_service.dart';

typedef WebDavStateSyncServiceFactory = WebDavStateSyncService Function(
  WebDavSyncSettings settings, {
  String? deviceId,
});

enum AppSyncStatus {
  disabled,
  configurationMissing,
  uploaded,
  downloaded,
  conflict,
}

class AppSyncResult {
  const AppSyncResult({
    required this.status,
    this.state,
    this.message = '',
    this.snapshotPath = '',
  });

  final AppSyncStatus status;
  final AppState? state;
  final String message;
  final String snapshotPath;
}

class AppSyncOperationMergeResult {
  const AppSyncOperationMergeResult({
    required this.state,
    required this.deviceSequences,
    required this.appliedCount,
  });

  final AppState state;
  final Map<String, int> deviceSequences;
  final int appliedCount;
}

class AppSyncService {
  AppSyncService({
    WebDavStateSyncServiceFactory? webDavFactory,
    SyncDeviceIdStore? deviceIdStore,
    SyncOperationApplier operationApplier = const SyncOperationApplier(),
  })  : _webDavFactory = webDavFactory ?? WebDavStateSyncService.fromSettings,
        _deviceIdStore = deviceIdStore,
        _operationApplier = operationApplier;

  final WebDavStateSyncServiceFactory _webDavFactory;
  final SyncDeviceIdStore? _deviceIdStore;
  final SyncOperationApplier _operationApplier;

  Future<AppSyncResult> syncNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    localState.normalize();
    final settings = localState.sync;
    if (!settings.enabled) {
      return const AppSyncResult(
        status: AppSyncStatus.disabled,
        message: 'Sync is disabled.',
      );
    }
    if (settings.provider != SyncProviderIds.webDav ||
        !settings.webDav.isConfigured) {
      return const AppSyncResult(
        status: AppSyncStatus.configurationMissing,
        message: 'Complete WebDAV sync settings first.',
      );
    }

    final deviceId =
        await (_deviceIdStore ?? SyncDeviceIdStore.forStateStore(store))
            .loadOrCreate();
    final client = _webDavFactory(
      settings.webDav.copy(),
      deviceId: deviceId,
    );
    final result = await client.sync(
      localState: localState,
      localUpdatedAtUtc: localUpdatedAtUtc ?? await store.lastModifiedUtc(),
    );

    switch (result.status) {
      case WebDavStateSyncStatus.uploaded:
      case WebDavStateSyncStatus.remoteMissing:
        await store.save(localState);
        return AppSyncResult(
          status: AppSyncStatus.uploaded,
          message: 'Local data uploaded.',
          snapshotPath: result.snapshotPath,
        );
      case WebDavStateSyncStatus.downloaded:
        final remoteState = result.state;
        if (remoteState == null) {
          return const AppSyncResult(
            status: AppSyncStatus.configurationMissing,
            message: 'Remote snapshot is empty.',
          );
        }
        await store.save(remoteState);
        return AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: remoteState,
          message: 'Remote data downloaded.',
          snapshotPath: result.snapshotPath,
        );
      case WebDavStateSyncStatus.conflict:
        final snapshotPath = result.snapshotPath;
        return AppSyncResult(
          status: AppSyncStatus.conflict,
          message: snapshotPath.isEmpty
              ? 'Remote data changed during sync. Pull again before upload.'
              : 'Remote data changed during sync. Local snapshot preserved at $snapshotPath.',
          snapshotPath: snapshotPath,
        );
    }
  }

  Future<List<WebDavSnapshotRecord>> listRecoverySnapshots({
    required AppState localState,
    required StateStore store,
  }) async {
    final client = await _configuredClientOrNull(
      localState: localState,
      store: store,
    );
    if (client == null) {
      return const [];
    }
    return client.listSnapshots();
  }

  Future<List<WebDavOperationLogRecord>> listRemoteOperationLogs({
    required AppState localState,
    required StateStore store,
  }) async {
    final client = await _configuredClientOrNull(
      localState: localState,
      store: store,
    );
    if (client == null) {
      return const [];
    }
    return client.listOperationLogs();
  }

  Future<List<SyncOperation>> downloadRemoteOperationLog({
    required AppState localState,
    required StateStore store,
    required String operationLogPath,
  }) async {
    final client = await _configuredClientOrNull(
      localState: localState,
      store: store,
    );
    if (client == null) {
      return const [];
    }
    return client.downloadOperationLog(operationLogPath);
  }

  Future<AppSyncOperationMergeResult> mergeRemoteOperations({
    required AppState localState,
    required StateStore store,
    Map<String, int>? deviceSequences,
  }) async {
    final client = await _configuredClientOrNull(
      localState: localState,
      store: store,
    );
    if (client == null) {
      return AppSyncOperationMergeResult(
        state: localState,
        deviceSequences: Map<String, int>.from(deviceSequences ?? const {}),
        appliedCount: 0,
      );
    }

    final records = await client.listOperationLogs();
    final operations = <SyncOperation>[];
    for (final record in records) {
      operations.addAll(await client.downloadOperationLog(record.path));
    }
    final result = _operationApplier.apply(
      localState,
      operations,
      deviceSequences: deviceSequences,
    );
    if (result.appliedCount > 0) {
      await store.save(result.state);
    }
    return AppSyncOperationMergeResult(
      state: result.state,
      deviceSequences: result.deviceSequences,
      appliedCount: result.appliedCount,
    );
  }

  Future<AppSyncResult> restoreRecoverySnapshot({
    required AppState localState,
    required StateStore store,
    required String snapshotPath,
  }) async {
    final client = await _configuredClientOrNull(
      localState: localState,
      store: store,
    );
    if (client == null) {
      final settings = localState.sync;
      if (!settings.enabled) {
        return const AppSyncResult(
          status: AppSyncStatus.disabled,
          message: 'Sync is disabled.',
        );
      }
      return const AppSyncResult(
        status: AppSyncStatus.configurationMissing,
        message: 'Complete WebDAV sync settings first.',
      );
    }

    final result = await client.downloadSnapshot(snapshotPath);
    final snapshotState = result.state;
    if (snapshotState == null) {
      return const AppSyncResult(
        status: AppSyncStatus.configurationMissing,
        message: 'Remote snapshot is empty.',
      );
    }
    await store.save(snapshotState);
    return AppSyncResult(
      status: AppSyncStatus.downloaded,
      state: snapshotState,
      message: 'Snapshot restored.',
      snapshotPath: result.snapshotPath,
    );
  }

  Future<WebDavStateSyncService?> _configuredClientOrNull({
    required AppState localState,
    required StateStore store,
  }) async {
    localState.normalize();
    final settings = localState.sync;
    if (!settings.enabled ||
        settings.provider != SyncProviderIds.webDav ||
        !settings.webDav.isConfigured) {
      return null;
    }
    final deviceId =
        await (_deviceIdStore ?? SyncDeviceIdStore.forStateStore(store))
            .loadOrCreate();
    return _webDavFactory(
      settings.webDav.copy(),
      deviceId: deviceId,
    );
  }
}
