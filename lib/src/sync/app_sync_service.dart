import '../core/model/app_state.dart';
import '../core/model/sync_settings.dart';
import '../core/storage/state_store.dart';
import 'sync_device_id_store.dart';
import 'sync_operation.dart';
import 'sync_operation_applier.dart';
import 'sync_operation_diff.dart';
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

class AppSyncRunResult {
  const AppSyncRunResult({
    required this.syncResult,
    required this.state,
    this.operationMergeResult,
  });

  final AppSyncResult syncResult;
  final AppState state;
  final AppSyncOperationMergeResult? operationMergeResult;

  int get operationAppliedCount => operationMergeResult?.appliedCount ?? 0;
}

class AppSyncLocalOperationUploadResult {
  const AppSyncLocalOperationUploadResult({
    required this.state,
    required this.deviceSequences,
    required this.generatedCount,
    required this.uploadedCount,
  });

  final AppState state;
  final Map<String, int> deviceSequences;
  final int generatedCount;
  final int uploadedCount;
}

class AppSyncService {
  AppSyncService({
    WebDavStateSyncServiceFactory? webDavFactory,
    SyncDeviceIdStore? deviceIdStore,
    SyncOperationApplier operationApplier = const SyncOperationApplier(),
    SyncOperationDiffBuilder operationDiffBuilder =
        const SyncOperationDiffBuilder(),
  })  : _webDavFactory = webDavFactory ?? WebDavStateSyncService.fromSettings,
        _deviceIdStore = deviceIdStore,
        _operationApplier = operationApplier,
        _operationDiffBuilder = operationDiffBuilder;

  final WebDavStateSyncServiceFactory _webDavFactory;
  final SyncDeviceIdStore? _deviceIdStore;
  final SyncOperationApplier _operationApplier;
  final SyncOperationDiffBuilder _operationDiffBuilder;

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
        _applyManifestDeviceSequences(localState, result);
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
        _applyManifestDeviceSequences(remoteState, result);
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

  Future<AppSyncRunResult> syncAndMergeNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    final syncResult = await syncNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: localUpdatedAtUtc,
    );
    var state = syncResult.state ?? localState;
    AppSyncOperationMergeResult? operationMergeResult;

    switch (syncResult.status) {
      case AppSyncStatus.uploaded:
      case AppSyncStatus.downloaded:
        operationMergeResult = await mergeRemoteOperations(
          localState: state,
          store: store,
        );
        state = operationMergeResult.state;
      case AppSyncStatus.disabled:
      case AppSyncStatus.configurationMissing:
      case AppSyncStatus.conflict:
        break;
    }

    return AppSyncRunResult(
      syncResult: syncResult,
      state: state,
      operationMergeResult: operationMergeResult,
    );
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
    final previousSequences =
        deviceSequences ?? localState.sync.operationDeviceSequences;
    if (client == null) {
      return AppSyncOperationMergeResult(
        state: localState,
        deviceSequences: Map<String, int>.from(previousSequences),
        appliedCount: 0,
      );
    }

    final records = (await client.listOperationLogs()).where((record) {
      return record.sequence > (previousSequences[record.deviceId] ?? 0);
    });
    final operations = <SyncOperation>[];
    for (final record in records) {
      operations.addAll(await client.downloadOperationLog(record.path));
    }
    final result = _operationApplier.apply(
      localState,
      operations,
      deviceSequences: previousSequences,
    );
    result.state.sync.operationDeviceSequences = result.deviceSequences;
    result.state.normalize();
    if (result.appliedCount > 0) {
      await store.save(result.state);
    }
    return AppSyncOperationMergeResult(
      state: result.state,
      deviceSequences: result.deviceSequences,
      appliedCount: result.appliedCount,
    );
  }

  Future<AppSyncLocalOperationUploadResult> uploadLocalOperations({
    required AppState beforeState,
    required AppState afterState,
    required StateStore store,
    DateTime? createdAtUtc,
  }) async {
    beforeState.normalize();
    afterState.normalize();
    final previousSequences = afterState.sync.operationDeviceSequences;
    final context = await _configuredClientContextOrNull(
      localState: afterState,
      store: store,
    );
    if (context == null) {
      return AppSyncLocalOperationUploadResult(
        state: afterState,
        deviceSequences: Map<String, int>.from(previousSequences),
        generatedCount: 0,
        uploadedCount: 0,
      );
    }

    final operations = _operationDiffBuilder.build(
      before: beforeState,
      after: afterState,
      deviceId: context.deviceId,
      startSequence: previousSequences[context.deviceId] ?? 0,
      createdAtUtc: createdAtUtc,
    );
    if (operations.isEmpty) {
      return AppSyncLocalOperationUploadResult(
        state: afterState,
        deviceSequences: Map<String, int>.from(previousSequences),
        generatedCount: 0,
        uploadedCount: 0,
      );
    }

    final uploadResult = await context.client.uploadOperationLogs(
      operations,
      previousDeviceSequences: previousSequences,
    );
    afterState.sync.operationDeviceSequences = uploadResult.deviceSequences;
    afterState.normalize();
    if (uploadResult.uploadedCount > 0) {
      await store.save(afterState);
    }
    return AppSyncLocalOperationUploadResult(
      state: afterState,
      deviceSequences: uploadResult.deviceSequences,
      generatedCount: operations.length,
      uploadedCount: uploadResult.uploadedCount,
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
    return (await _configuredClientContextOrNull(
      localState: localState,
      store: store,
    ))
        ?.client;
  }

  Future<_ConfiguredWebDavClient?> _configuredClientContextOrNull({
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
    return _ConfiguredWebDavClient(
      client: _webDavFactory(
        settings.webDav.copy(),
        deviceId: deviceId,
      ),
      deviceId: deviceId,
    );
  }

  void _applyManifestDeviceSequences(
    AppState state,
    WebDavStateSyncResult result,
  ) {
    final manifest = result.manifest;
    if (manifest == null) {
      return;
    }
    state.sync.operationDeviceSequences = manifest.deviceSequences;
    state.normalize();
  }
}

class _ConfiguredWebDavClient {
  const _ConfiguredWebDavClient({
    required this.client,
    required this.deviceId,
  });

  final WebDavStateSyncService client;
  final String deviceId;
}
