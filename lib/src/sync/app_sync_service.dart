import 'dart:convert';

import 'package:collection/collection.dart';

import '../core/model/app_state.dart';
import '../core/model/sync_settings.dart';
import '../core/model/sync_wire_datetime.dart';
import '../core/state/app_state_codec.dart';
import '../core/storage/state_store.dart';
import 'sync_device_id.dart';
import 'sync_device_id_store.dart';
import 'sync_operation.dart';
import 'sync_operation_applier.dart';
import 'sync_operation_diff.dart';
import 'webdav/webdav_client.dart';
import 'webdav/webdav_payload_codec.dart';
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
  payloadUnreadable,
}

class AppSyncResult {
  const AppSyncResult({
    required this.status,
    this.state,
    this.message = '',
    this.snapshotPath = '',
    this.legacyPlainPayloadDetected = false,
    this.legacyPlainPayloadMigrated = false,
  });

  final AppSyncStatus status;
  final AppState? state;
  final String message;
  final String snapshotPath;
  final bool legacyPlainPayloadDetected;
  final bool legacyPlainPayloadMigrated;
}

class AppSyncOperationMergeResult {
  const AppSyncOperationMergeResult({
    required this.state,
    required this.deviceSequences,
    required this.appliedCount,
    this.legacyPlainOperationLogCount = 0,
    this.legacyPlainOperationLogMigratedCount = 0,
  });

  final AppState state;
  final Map<String, int> deviceSequences;
  final int appliedCount;
  final int legacyPlainOperationLogCount;
  final int legacyPlainOperationLogMigratedCount;
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
    this.stateChanged = false,
  });

  final AppState state;
  final Map<String, int> deviceSequences;
  final int generatedCount;
  final int uploadedCount;
  final bool stateChanged;
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

  Future<AppState> preparePendingLocalOperationBatch({
    required AppState beforeState,
    required AppState afterState,
    required StateStore store,
    DateTime? createdAtUtc,
  }) async {
    final beforeBatch = beforeState.sync.pendingOperationBatch;
    final afterBatch = afterState.sync.pendingOperationBatch;
    final normalizedBeforeState = _deepCloneAppStateForPreparation(beforeState);
    final preparedState = _deepCloneAppStateForPreparation(afterState);
    final existingBatch = beforeBatch ?? afterBatch;
    if (existingBatch != null) {
      preparedState.sync.pendingOperationBatch =
          _copyPendingOperationBatchOrSame(existingBatch);
      _pendingLocalOperationsEvaluation(preparedState);
      return preparedState;
    }

    final settings = preparedState.sync;
    if (!settings.enabled ||
        settings.provider != SyncProviderIds.webDav ||
        !settings.webDav.isSecurelyConfigured) {
      return preparedState;
    }

    final deviceId =
        await (_deviceIdStore ?? SyncDeviceIdStore.forStateStore(store))
            .loadOrCreate();
    final stamp = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();
    const codec = AppStateCodec();
    preparedState.sync.pendingOperationBatch = PendingSyncOperationBatch(
      baseState: decodeJsonObject(
        codec.encodeRemoteSnapshot(normalizedBeforeState),
      ),
      deviceId: deviceId,
      startSequence: preparedState.sync.operationDeviceSequences[deviceId] ?? 0,
      createdAtUtc: stamp,
    );
    preparedState.normalize();
    final evaluation = _pendingLocalOperationsEvaluation(preparedState);
    if (evaluation.isValid && evaluation.operations.isEmpty) {
      preparedState.sync.pendingOperationBatch = null;
      preparedState.normalize();
    }
    return preparedState;
  }

  List<SyncOperation> pendingLocalOperationsFor(AppState state) {
    return _pendingLocalOperationsEvaluation(state).operations;
  }

  _PendingLocalOperationsEvaluation _pendingLocalOperationsEvaluation(
    AppState state,
  ) {
    late final AppState normalizedState;
    late final PendingSyncOperationBatch batch;
    late final AppState baseState;
    try {
      normalizedState = _deepCloneAppState(state);
      final candidate = normalizedState.sync.pendingOperationBatch;
      if (candidate == null || !candidate.isValid) {
        return const _PendingLocalOperationsEvaluation.invalid();
      }
      batch = candidate;
      baseState = _deepCloneAppState(AppState.fromJson(batch.baseState));
    } on FormatException {
      return const _PendingLocalOperationsEvaluation.invalid();
    } on JsonUnsupportedObjectError {
      return const _PendingLocalOperationsEvaluation.invalid();
    } on TypeError {
      return const _PendingLocalOperationsEvaluation.invalid();
    }

    try {
      return _PendingLocalOperationsEvaluation.valid(
        _operationDiffBuilder.build(
          before: baseState,
          after: normalizedState,
          deviceId: batch.deviceId,
          startSequence: batch.startSequence,
          createdAtUtc: batch.createdAtUtc,
        ),
      );
    } on RangeError catch (error) {
      throw WebDavSyncConfigurationException(_rangeErrorMessage(error));
    }
  }

  _PendingSyncBatchCapture _capturePendingSyncBatch(AppState state) {
    if (state.sync.pendingOperationBatch == null) {
      return const _PendingSyncBatchCapture.none();
    }
    final evaluation = _pendingLocalOperationsEvaluation(state);
    if (!evaluation.isValid) {
      return const _PendingSyncBatchCapture.invalid();
    }
    return _PendingSyncBatchCapture.valid(
      batch: state.sync.pendingOperationBatch!.copy(),
      operations: evaluation.operations,
    );
  }

  AppState _replayPendingSyncBatch(
    AppState remoteState,
    _PendingSyncBatchCapture pendingBatch,
  ) {
    final batch = pendingBatch.batch!;
    final remoteSequences = normalizeSyncDeviceSequences(
      remoteState.sync.operationDeviceSequences,
    );
    final replaySequences = Map<String, int>.from(remoteSequences);
    if (batch.startSequence == 0) {
      replaySequences.remove(batch.deviceId);
    } else {
      replaySequences[batch.deviceId] = batch.startSequence;
    }
    final replayResult = _operationApplier.apply(
      remoteState,
      pendingBatch.operations,
      deviceSequences: replaySequences,
    );
    replayResult.state.sync.operationDeviceSequences = _mergeDeviceSequences(
      remoteSequences,
      replayResult.deviceSequences,
      {
        batch.deviceId: pendingBatch.lastSequence,
      },
    );
    replayResult.state.sync.pendingOperationBatch = batch.copy();
    replayResult.state.normalize();
    return replayResult.state;
  }

  Future<AppState> _uploadPendingSyncBatch({
    required AppState localState,
    required StateStore store,
    required _PendingSyncBatchCapture pendingBatch,
  }) async {
    final uploadState = _deepCloneAppState(localState);
    final tombstonesChanged = _markLocalDeleteTombstones(
      uploadState,
      pendingBatch.operations,
    );
    if (tombstonesChanged) {
      await store.save(uploadState);
    }
    final context = await _configuredClientContextOrNull(
      localState: uploadState,
      store: store,
    );
    if (context == null) {
      return uploadState;
    }
    final batch = pendingBatch.batch!;
    final previousSequences = normalizeSyncDeviceSequences(
      uploadState.sync.operationDeviceSequences,
    );
    previousSequences[batch.deviceId] = batch.startSequence;
    try {
      final uploadResult = await context.client.uploadOperationLogs(
        pendingBatch.operations,
        previousDeviceSequences: previousSequences,
      );
      final uploadedSequences = _mergeDeviceSequences(
        previousSequences,
        uploadResult.deviceSequences,
        uploadResult.acceptedDeviceSequences,
      );
      uploadState.sync.operationDeviceSequences = uploadedSequences;
      uploadState.normalize();
      if (!_deviceSequencesEqual(previousSequences, uploadedSequences)) {
        await store.save(uploadState);
      }
      return uploadState;
    } finally {
      context.client.close();
    }
  }

  Future<AppState> _completePendingSyncBatch({
    required AppState state,
    required StateStore store,
    required _PendingSyncBatchCapture pendingBatch,
  }) async {
    final completedState = _deepCloneAppState(state);
    final batch = pendingBatch.batch!;
    completedState.sync.operationDeviceSequences = _mergeDeviceSequences(
      completedState.sync.operationDeviceSequences,
      {
        batch.deviceId: pendingBatch.lastSequence,
      },
      const <String, int>{},
    );
    completedState.sync.pendingOperationBatch = null;
    completedState.normalize();
    await store.save(completedState);
    return completedState;
  }

  Future<AppSyncResult> syncNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    late final _PendingSyncBatchCapture pendingBatch;
    try {
      pendingBatch = _capturePendingSyncBatch(localState);
    } on WebDavSyncConfigurationException catch (error) {
      return AppSyncResult(
        status: AppSyncStatus.payloadUnreadable,
        state: localState,
        message: error.message,
      );
    }
    if (!pendingBatch.isValid) {
      return AppSyncResult(
        status: AppSyncStatus.payloadUnreadable,
        state: localState,
        message: 'The pending local sync operation batch is not readable.',
      );
    }
    final syncState = AppState.fromJson(localState.toJson())..normalize();
    final settings = syncState.sync;
    if (!settings.enabled) {
      return const AppSyncResult(
        status: AppSyncStatus.disabled,
        message: 'Sync is disabled.',
      );
    }
    if (settings.provider != SyncProviderIds.webDav ||
        !settings.webDav.isSecurelyConfigured) {
      return const AppSyncResult(
        status: AppSyncStatus.configurationMissing,
        message:
            'Complete WebDAV sync settings and encryption passphrase first.',
      );
    }

    final deviceId =
        await (_deviceIdStore ?? SyncDeviceIdStore.forStateStore(store))
            .loadOrCreate();
    final client = _webDavFactory(
      settings.webDav.copy(),
      deviceId: deviceId,
    );
    try {
      final result = await client.sync(
        localState: syncState,
        localUpdatedAtUtc: localUpdatedAtUtc ?? await store.lastModifiedUtc(),
      );

      switch (result.status) {
        case WebDavStateSyncStatus.uploaded:
        case WebDavStateSyncStatus.remoteMissing:
          _applyManifestDeviceSequences(syncState, result);
          await store.save(syncState);
          return AppSyncResult(
            status: AppSyncStatus.uploaded,
            state: syncState,
            message: 'Local data uploaded.',
            snapshotPath: result.snapshotPath,
          );
        case WebDavStateSyncStatus.downloaded:
          final downloadedState = result.state;
          if (downloadedState == null) {
            return const AppSyncResult(
              status: AppSyncStatus.configurationMissing,
              message: 'Remote snapshot is empty.',
            );
          }
          var remoteState = AppState.fromJson(downloadedState.toJson());
          _preserveLocalDeviceState(remoteState, syncState);
          _applyManifestDeviceSequences(remoteState, result);
          if (pendingBatch.hasBatch) {
            remoteState = _replayPendingSyncBatch(
              remoteState,
              pendingBatch,
            );
          }
          await store.save(remoteState);
          final legacyPlainPayloadDetected =
              _isLegacyPlainPayloadDownload(settings.webDav, result);
          final legacyPlainPayloadMigrated = legacyPlainPayloadDetected &&
              await _migrateLegacyPlainPayload(
                client: client,
                state: remoteState,
                downloadedResult: result,
                store: store,
              );
          return AppSyncResult(
            status: AppSyncStatus.downloaded,
            state: remoteState,
            message: _downloadedMessage(
              legacyPlainPayloadDetected: legacyPlainPayloadDetected,
              legacyPlainPayloadMigrated: legacyPlainPayloadMigrated,
              canAttemptLegacyPlainPayloadMigration:
                  _canAttemptLegacyPlainPayloadMigration(result),
            ),
            snapshotPath: result.snapshotPath,
            legacyPlainPayloadDetected: legacyPlainPayloadDetected,
            legacyPlainPayloadMigrated: legacyPlainPayloadMigrated,
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
    } on WebDavPayloadDecryptionException catch (error) {
      return AppSyncResult(
        status: AppSyncStatus.payloadUnreadable,
        message: error.message,
      );
    } on WebDavSyncConfigurationException catch (error) {
      return AppSyncResult(
        status: AppSyncStatus.payloadUnreadable,
        message: error.message,
      );
    } on FormatException catch (error) {
      return AppSyncResult(
        status: AppSyncStatus.payloadUnreadable,
        message: _formatExceptionMessage(error),
      );
    } finally {
      client.close();
    }
  }

  Future<AppSyncRunResult> syncAndMergeNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    late final _PendingSyncBatchCapture pendingBatch;
    try {
      pendingBatch = _capturePendingSyncBatch(localState);
    } on WebDavSyncConfigurationException {
      final syncResult = await syncNow(
        localState: localState,
        store: store,
        localUpdatedAtUtc: localUpdatedAtUtc,
      );
      return AppSyncRunResult(
        syncResult: syncResult,
        state: syncResult.state ?? localState,
      );
    }
    var syncInputState = localState;
    if (pendingBatch.isValid &&
        pendingBatch.hasBatch &&
        pendingBatch.operations.isNotEmpty) {
      syncInputState = await _uploadPendingSyncBatch(
        localState: localState,
        store: store,
        pendingBatch: pendingBatch,
      );
    }
    final syncResult = await syncNow(
      localState: syncInputState,
      store: store,
      localUpdatedAtUtc: localUpdatedAtUtc,
    );
    var state = syncResult.state ?? syncInputState;
    AppSyncOperationMergeResult? operationMergeResult;

    switch (syncResult.status) {
      case AppSyncStatus.uploaded:
      case AppSyncStatus.downloaded:
        try {
          operationMergeResult = await mergeRemoteOperations(
            localState: state,
            store: store,
          );
          state = operationMergeResult.state;
          if (pendingBatch.isValid && pendingBatch.hasBatch) {
            state = await _completePendingSyncBatch(
              state: state,
              store: store,
              pendingBatch: pendingBatch,
            );
            operationMergeResult = AppSyncOperationMergeResult(
              state: state,
              deviceSequences: state.sync.operationDeviceSequences,
              appliedCount: operationMergeResult.appliedCount,
              legacyPlainOperationLogCount:
                  operationMergeResult.legacyPlainOperationLogCount,
              legacyPlainOperationLogMigratedCount:
                  operationMergeResult.legacyPlainOperationLogMigratedCount,
            );
          }
        } on WebDavPayloadDecryptionException catch (error) {
          return AppSyncRunResult(
            syncResult: AppSyncResult(
              status: AppSyncStatus.payloadUnreadable,
              state: state,
              message: error.message,
              legacyPlainPayloadDetected: syncResult.legacyPlainPayloadDetected,
              legacyPlainPayloadMigrated: syncResult.legacyPlainPayloadMigrated,
            ),
            state: state,
          );
        } on WebDavSyncConfigurationException catch (error) {
          return AppSyncRunResult(
            syncResult: AppSyncResult(
              status: AppSyncStatus.payloadUnreadable,
              state: state,
              message: error.message,
              legacyPlainPayloadDetected: syncResult.legacyPlainPayloadDetected,
              legacyPlainPayloadMigrated: syncResult.legacyPlainPayloadMigrated,
            ),
            state: state,
          );
        } on FormatException catch (error) {
          return AppSyncRunResult(
            syncResult: AppSyncResult(
              status: AppSyncStatus.payloadUnreadable,
              state: state,
              message: _formatExceptionMessage(error),
              legacyPlainPayloadDetected: syncResult.legacyPlainPayloadDetected,
              legacyPlainPayloadMigrated: syncResult.legacyPlainPayloadMigrated,
            ),
            state: state,
          );
        }
      case AppSyncStatus.disabled:
      case AppSyncStatus.configurationMissing:
      case AppSyncStatus.conflict:
      case AppSyncStatus.payloadUnreadable:
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
    try {
      return await client.listSnapshots();
    } finally {
      client.close();
    }
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
    try {
      return await client.listOperationLogs();
    } finally {
      client.close();
    }
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
    try {
      return await client.downloadOperationLog(operationLogPath);
    } finally {
      client.close();
    }
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
    final previousSequences = normalizeSyncDeviceSequences(
      deviceSequences ?? localState.sync.operationDeviceSequences,
    );
    if (client == null) {
      return AppSyncOperationMergeResult(
        state: localState,
        deviceSequences: previousSequences,
        appliedCount: 0,
      );
    }

    try {
      final records = _contiguousOperationRecords(
        await client.listOperationLogs(),
        previousSequences,
        paths: _operationLogPathsFor(localState),
      );
      final operations = <SyncOperation>[];
      var legacyPlainOperationLogCount = 0;
      var legacyPlainOperationLogMigratedCount = 0;
      for (final record in records) {
        final downloadResult =
            await client.downloadOperationLogWithMetadata(record.path);
        if (_isLegacyPlainOperationLogDownload(
          localState.sync.webDav,
          downloadResult,
        )) {
          legacyPlainOperationLogCount += 1;
          if (await _migrateLegacyPlainOperationLog(
            client: client,
            record: record,
            downloadResult: downloadResult,
          )) {
            legacyPlainOperationLogMigratedCount += 1;
          }
        }
        operations.addAll(downloadResult.operations);
      }
      final result = _operationApplier.apply(
        localState,
        operations,
        deviceSequences: previousSequences,
      );
      result.state.sync.operationDeviceSequences = result.deviceSequences;
      result.state.normalize();
      final shouldSaveMergeResult = result.appliedCount > 0 ||
          (deviceSequences == null &&
              _syncMergeMetadataChanged(result.state.sync, localState.sync));
      if (shouldSaveMergeResult) {
        await store.save(result.state);
      }
      return AppSyncOperationMergeResult(
        state: result.state,
        deviceSequences: result.deviceSequences,
        appliedCount: result.appliedCount,
        legacyPlainOperationLogCount: legacyPlainOperationLogCount,
        legacyPlainOperationLogMigratedCount:
            legacyPlainOperationLogMigratedCount,
      );
    } finally {
      client.close();
    }
  }

  Future<AppSyncLocalOperationUploadResult> uploadLocalOperations({
    required AppState beforeState,
    required AppState afterState,
    required StateStore store,
    DateTime? createdAtUtc,
  }) async {
    final normalizedBeforeState = AppState.fromJson(beforeState.toJson())
      ..normalize();
    final previousSequences = normalizeSyncDeviceSequences(
      afterState.sync.operationDeviceSequences,
    );
    final uploadState = AppState.fromJson(afterState.toJson())
      ..sync.operationDeviceSequences = previousSequences
      ..normalize();
    final context = await _configuredClientContextOrNull(
      localState: uploadState,
      store: store,
    );
    if (context == null) {
      return AppSyncLocalOperationUploadResult(
        state: uploadState,
        deviceSequences: previousSequences,
        generatedCount: 0,
        uploadedCount: 0,
        stateChanged: false,
      );
    }

    try {
      final List<SyncOperation> operations;
      try {
        operations = _operationDiffBuilder.build(
          before: normalizedBeforeState,
          after: uploadState,
          deviceId: context.deviceId,
          startSequence: previousSequences[context.deviceId] ?? 0,
          createdAtUtc: createdAtUtc,
        );
      } on RangeError catch (error) {
        throw WebDavSyncConfigurationException(_rangeErrorMessage(error));
      }
      if (operations.isEmpty) {
        return AppSyncLocalOperationUploadResult(
          state: uploadState,
          deviceSequences: previousSequences,
          generatedCount: 0,
          uploadedCount: 0,
          stateChanged: false,
        );
      }

      final tombstonesChanged = _markLocalDeleteTombstones(
        uploadState,
        operations,
      );
      final uploadResult = await context.client.uploadOperationLogs(
        operations,
        previousDeviceSequences: previousSequences,
      );
      final uploadedDeviceSequences = _mergeDeviceSequences(
        previousSequences,
        uploadResult.deviceSequences,
        uploadResult.acceptedDeviceSequences,
      );
      final deviceSequencesChanged = !_deviceSequencesEqual(
        previousSequences,
        uploadedDeviceSequences,
      );
      uploadState.sync.operationDeviceSequences = uploadedDeviceSequences;
      uploadState.normalize();
      if (uploadResult.uploadedCount > 0 ||
          tombstonesChanged ||
          deviceSequencesChanged) {
        await store.save(uploadState);
      }
      final stateChanged = uploadResult.uploadedCount > 0 ||
          tombstonesChanged ||
          deviceSequencesChanged;
      return AppSyncLocalOperationUploadResult(
        state: uploadState,
        deviceSequences: uploadedDeviceSequences,
        generatedCount: operations.length,
        uploadedCount: uploadResult.uploadedCount,
        stateChanged: stateChanged,
      );
    } finally {
      context.client.close();
    }
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
        message:
            'Complete WebDAV sync settings and encryption passphrase first.',
      );
    }

    try {
      final result = await client.downloadSnapshot(snapshotPath);
      final downloadedSnapshotState = result.state;
      if (downloadedSnapshotState == null) {
        return const AppSyncResult(
          status: AppSyncStatus.configurationMissing,
          message: 'Remote snapshot is empty.',
        );
      }
      final snapshotState = AppState.fromJson(downloadedSnapshotState.toJson());
      _preserveLocalDeviceState(snapshotState, localState);
      await store.save(snapshotState);
      final legacyPlainPayloadDetected =
          _isLegacyPlainPayloadDownload(localState.sync.webDav, result);
      return AppSyncResult(
        status: AppSyncStatus.downloaded,
        state: snapshotState,
        message: _snapshotRestoredMessage(
          legacyPlainPayloadDetected: legacyPlainPayloadDetected,
        ),
        snapshotPath: result.snapshotPath,
        legacyPlainPayloadDetected: legacyPlainPayloadDetected,
      );
    } on WebDavPayloadDecryptionException catch (error) {
      return AppSyncResult(
        status: AppSyncStatus.payloadUnreadable,
        message: error.message,
      );
    } on WebDavSyncConfigurationException catch (error) {
      return AppSyncResult(
        status: AppSyncStatus.payloadUnreadable,
        message: error.message,
      );
    } on FormatException catch (error) {
      return AppSyncResult(
        status: AppSyncStatus.payloadUnreadable,
        message: _formatExceptionMessage(error),
      );
    } finally {
      client.close();
    }
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
    final normalizedState = AppState.fromJson(localState.toJson())..normalize();
    final settings = normalizedState.sync;
    if (!settings.enabled ||
        settings.provider != SyncProviderIds.webDav ||
        !settings.webDav.isSecurelyConfigured) {
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
    state.sync.operationDeviceSequences = _mergeDeviceSequences(
      state.sync.operationDeviceSequences,
      manifest.deviceSequences,
      const <String, int>{},
    );
    state.normalize();
  }

  void _preserveLocalDeviceState(AppState remoteState, AppState localState) {
    final remoteSync = remoteState.sync.copy()..normalize();
    final localSync = localState.sync;
    final preservedSync = localSync.copy()..normalize();
    preservedSync.operationDeviceSequences = _mergeDeviceSequences(
      preservedSync.operationDeviceSequences,
      remoteSync.operationDeviceSequences,
      const <String, int>{},
    );
    preservedSync.deletedPaperTombstones = _mergeTombstones(
      preservedSync.deletedPaperTombstones,
      remoteSync.deletedPaperTombstones,
    );
    preservedSync.deletedTodoItemTombstones = _mergeNestedTombstones(
      preservedSync.deletedTodoItemTombstones,
      remoteSync.deletedTodoItemTombstones,
    );
    remoteState.startAtLogin = localState.startAtLogin;
    remoteState.sync = preservedSync;
    remoteState.normalize();
  }

  bool _markLocalDeleteTombstones(
    AppState state,
    Iterable<SyncOperation> operations,
  ) {
    var changed = false;
    for (final operation in operations) {
      switch (operation.kind) {
        case SyncOperationKind.deletePaper:
          final paperId = _payloadString(operation.payload, 'paperId');
          if (paperId.trim().isNotEmpty) {
            changed =
                state.sync.markPaperDeleted(paperId, operation.createdAtUtc) ||
                    changed;
          }
        case SyncOperationKind.deleteTodoItem:
          final paperId = _payloadString(operation.payload, 'paperId');
          final itemId = _payloadString(operation.payload, 'itemId');
          if (paperId.trim().isNotEmpty && itemId.trim().isNotEmpty) {
            changed = state.sync.markTodoItemDeleted(
                  paperId,
                  itemId,
                  operation.createdAtUtc,
                ) ||
                changed;
          }
        case SyncOperationKind.stateSnapshot:
        case SyncOperationKind.upsertPaper:
        case SyncOperationKind.upsertTodoItem:
        case SyncOperationKind.updateNoteContent:
        case SyncOperationKind.updateSettings:
          break;
      }
    }
    return changed;
  }
}

AppState _deepCloneAppState(AppState state) {
  return AppState.fromJson(
    decodeJsonObject(jsonEncode(state.toJson())),
  )..normalize();
}

AppState _deepCloneAppStateForPreparation(AppState state) {
  try {
    return _deepCloneAppState(state);
  } on FormatException {
    return _deepCloneAppStateWithoutPendingBatch(state);
  } on JsonUnsupportedObjectError {
    return _deepCloneAppStateWithoutPendingBatch(state);
  } on TypeError {
    return _deepCloneAppStateWithoutPendingBatch(state);
  }
}

AppState _deepCloneAppStateWithoutPendingBatch(AppState state) {
  final batch = state.sync.pendingOperationBatch;
  if (batch == null) {
    return _deepCloneAppState(state);
  }
  state.sync.pendingOperationBatch = null;
  try {
    return _deepCloneAppState(state);
  } finally {
    state.sync.pendingOperationBatch = batch;
  }
}

PendingSyncOperationBatch _copyPendingOperationBatchOrSame(
  PendingSyncOperationBatch batch,
) {
  try {
    return batch.copy();
  } on FormatException {
    return batch;
  } on JsonUnsupportedObjectError {
    return batch;
  } on TypeError {
    return batch;
  }
}

class _PendingLocalOperationsEvaluation {
  const _PendingLocalOperationsEvaluation.valid(this.operations)
      : isValid = true;

  const _PendingLocalOperationsEvaluation.invalid()
      : operations = const [],
        isValid = false;

  final List<SyncOperation> operations;
  final bool isValid;
}

class _PendingSyncBatchCapture {
  const _PendingSyncBatchCapture.none()
      : batch = null,
        operations = const [],
        isValid = true;

  const _PendingSyncBatchCapture.invalid()
      : batch = null,
        operations = const [],
        isValid = false;

  const _PendingSyncBatchCapture.valid({
    required this.batch,
    required this.operations,
  }) : isValid = true;

  final PendingSyncOperationBatch? batch;
  final List<SyncOperation> operations;
  final bool isValid;

  bool get hasBatch => batch != null;

  int get lastSequence =>
      operations.isEmpty ? batch!.startSequence : operations.last.sequence;
}

String _payloadString(Map<String, Object?> payload, String key) {
  final value = _payloadValue(payload, key);
  if (value is! String || _hasControlCharacter(value)) {
    return '';
  }
  return value.trim();
}

Object? _payloadValue(Map<String, Object?> payload, String key) {
  if (payload.containsKey(key)) {
    return payload[key];
  }
  final normalizedKey = key.toLowerCase();
  for (final entry in payload.entries) {
    if (entry.key.toLowerCase() == normalizedKey) {
      return entry.value;
    }
  }
  return null;
}

bool _isLegacyPlainPayloadDownload(
  WebDavSyncSettings settings,
  WebDavStateSyncResult result,
) {
  return settings.usesEncryptedPayloads &&
      result.snapshotPayloadFormat == WebDavPayloadFormat.plainJson;
}

bool _isLegacyPlainOperationLogDownload(
  WebDavSyncSettings settings,
  WebDavOperationLogDownloadResult result,
) {
  return settings.usesEncryptedPayloads &&
      result.payloadFormat == WebDavPayloadFormat.plainJson;
}

bool _canAttemptLegacyPlainPayloadMigration(WebDavStateSyncResult result) {
  return result.manifest != null &&
      _strongRemoteEtagValue(result.manifestEtag) != null;
}

Future<bool> _migrateLegacyPlainPayload({
  required WebDavStateSyncService client,
  required AppState state,
  required WebDavStateSyncResult downloadedResult,
  required StateStore store,
}) async {
  final manifest = downloadedResult.manifest;
  final manifestEtag = _strongRemoteEtagValue(downloadedResult.manifestEtag);
  if (manifest == null || manifestEtag == null) {
    return false;
  }

  late final WebDavStateSyncResult uploadResult;
  try {
    uploadResult = await client.push(
      state,
      updatedAtUtc: _nextMigrationSnapshotTime(manifest.updatedAtUtc),
      expectedManifestEtag: manifestEtag,
      previousDeviceSequences: manifest.deviceSequences,
    );
  } on WebDavException {
    return false;
  } on WebDavSyncConfigurationException {
    return false;
  } on FormatException {
    return false;
  }
  if (uploadResult.status != WebDavStateSyncStatus.uploaded) {
    return false;
  }
  final uploadedManifest = uploadResult.manifest;
  if (uploadedManifest != null) {
    final migratedState = AppState.fromJson(state.toJson())
      ..sync.operationDeviceSequences = _mergeDeviceSequences(
        state.sync.operationDeviceSequences,
        uploadedManifest.deviceSequences,
        const <String, int>{},
      )
      ..normalize();
    try {
      await store.save(migratedState);
    } on StateStoreException {
      return false;
    }
    state.sync.operationDeviceSequences =
        migratedState.sync.operationDeviceSequences;
    state.normalize();
  }
  return true;
}

String? _strongRemoteEtagValue(String? etag) {
  final trimmed = etag?.trim();
  if (trimmed == null ||
      trimmed.isEmpty ||
      _hasControlCharacter(trimmed) ||
      !_hasValidRemoteEtagShape(trimmed)) {
    return null;
  }
  return trimmed.toLowerCase().startsWith('w/') ? null : trimmed;
}

bool _hasValidRemoteEtagShape(String value) {
  if (value.toLowerCase().startsWith('w/')) {
    return _isQuotedRemoteEtag(value.substring(2));
  }
  if (value.contains('"')) {
    return _isQuotedRemoteEtag(value);
  }
  return true;
}

bool _isQuotedRemoteEtag(String value) {
  if (value.length < 2 || !value.startsWith('"') || !value.endsWith('"')) {
    return false;
  }
  final inner = value.substring(1, value.length - 1);
  return inner.isNotEmpty &&
      !inner.contains('"') &&
      !_hasControlCharacter(inner);
}

bool _hasControlCharacter(String value) {
  return value.runes.any(
    (rune) => rune <= 0x1F || (rune >= 0x7F && rune <= 0x9F),
  );
}

Future<bool> _migrateLegacyPlainOperationLog({
  required WebDavStateSyncService client,
  required WebDavOperationLogRecord record,
  required WebDavOperationLogDownloadResult downloadResult,
}) async {
  try {
    return await client.migrateLegacyPlainOperationLog(
      record,
      downloadedResult: downloadResult,
    );
  } on WebDavException {
    return false;
  } on WebDavSyncConfigurationException {
    return false;
  } on FormatException {
    return false;
  }
}

DateTime _nextMigrationSnapshotTime(DateTime remoteUpdatedAtUtc) {
  final now = DateTime.now().toUtc();
  final minimum =
      remoteUpdatedAtUtc.toUtc().add(const Duration(milliseconds: 1));
  return now.isAfter(minimum) ? now : minimum;
}

String _downloadedMessage({
  required bool legacyPlainPayloadDetected,
  required bool legacyPlainPayloadMigrated,
  required bool canAttemptLegacyPlainPayloadMigration,
}) {
  if (!legacyPlainPayloadDetected) {
    return 'Remote data downloaded.';
  }
  if (legacyPlainPayloadMigrated) {
    return 'Remote data downloaded from legacy plain WebDAV data and migrated to encrypted payloads.';
  }
  if (canAttemptLegacyPlainPayloadMigration) {
    return 'Remote data downloaded from legacy plain WebDAV data. Automatic encryption migration could not complete; sync again to retry.';
  }
  return 'Remote data downloaded from legacy plain WebDAV data. The next successful upload will write encrypted payloads.';
}

String _snapshotRestoredMessage({
  required bool legacyPlainPayloadDetected,
}) {
  if (!legacyPlainPayloadDetected) {
    return 'Snapshot restored.';
  }
  return 'Snapshot restored from legacy plain WebDAV data. The next successful upload will write encrypted payloads.';
}

String _formatExceptionMessage(FormatException error) {
  final message = error.message.trim();
  return message.isEmpty ? 'Remote sync data is not readable.' : message;
}

String _rangeErrorMessage(RangeError error) {
  final message = error.message?.toString().trim();
  if (message != null && message.isNotEmpty) {
    return message;
  }
  return error.toString();
}

bool _deviceSequencesEqual(Map<String, int> left, Map<String, int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool _jsonEquals(Object? left, Object? right) {
  return const DeepCollectionEquality().equals(left, right);
}

bool _syncMergeMetadataChanged(SyncSettings left, SyncSettings right) {
  return !_jsonEquals(
        left.operationDeviceSequences,
        right.operationDeviceSequences,
      ) ||
      !_jsonEquals(left.deletedPaperTombstones, right.deletedPaperTombstones) ||
      !_jsonEquals(
        left.deletedTodoItemTombstones,
        right.deletedTodoItemTombstones,
      );
}

Map<String, int> _mergeDeviceSequences(
  Map<String, int> first,
  Map<String, int> second,
  Map<String, int> third,
) {
  final merged = <String, int>{};
  for (final source in [
    normalizeSyncDeviceSequences(first),
    normalizeSyncDeviceSequences(second),
    normalizeSyncDeviceSequences(third),
  ]) {
    for (final entry in source.entries) {
      final previous = merged[entry.key] ?? 0;
      if (entry.value > previous) {
        merged[entry.key] = entry.value;
      }
    }
  }
  return merged;
}

Map<String, String> _mergeTombstones(
  Map<String, String> first,
  Map<String, String> second,
) {
  final merged = <String, String>{};
  for (final source in [first, second]) {
    for (final entry in source.entries) {
      _putLatestTombstone(merged, entry.key, entry.value);
    }
  }
  return merged;
}

Map<String, Map<String, String>> _mergeNestedTombstones(
  Map<String, Map<String, String>> first,
  Map<String, Map<String, String>> second,
) {
  final merged = <String, Map<String, String>>{};
  for (final source in [first, second]) {
    for (final paperEntry in source.entries) {
      final paperId = _normalizeTombstoneId(paperEntry.key);
      if (paperId.isEmpty) {
        continue;
      }
      final itemTombstones = merged.putIfAbsent(
        paperId,
        () => <String, String>{},
      );
      for (final itemEntry in paperEntry.value.entries) {
        _putLatestTombstone(itemTombstones, itemEntry.key, itemEntry.value);
      }
    }
  }
  return {
    for (final entry in merged.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value,
  };
}

void _putLatestTombstone(
  Map<String, String> target,
  String rawId,
  String rawTimestamp,
) {
  final id = _normalizeTombstoneId(rawId);
  final timestamp = tryParseStrictSyncWireDateTimeUtc(rawTimestamp);
  if (id.isEmpty || timestamp == null) {
    return;
  }
  final previous = tryParseStrictSyncWireDateTimeUtc(target[id] ?? '');
  if (previous == null || timestamp.isAfter(previous)) {
    target[id] = timestamp.toIso8601String();
  }
}

String _normalizeTombstoneId(String value) {
  if (_hasControlCharacter(value)) {
    return '';
  }
  return value.trim();
}

class _ConfiguredWebDavClient {
  const _ConfiguredWebDavClient({
    required this.client,
    required this.deviceId,
  });

  final WebDavStateSyncService client;
  final String deviceId;
}

List<WebDavOperationLogRecord> _contiguousOperationRecords(
  Iterable<WebDavOperationLogRecord> records,
  Map<String, int> previousSequences, {
  WebDavStateSyncPaths paths = const WebDavStateSyncPaths(),
}) {
  final candidates = <_OperationLogCandidate>[];
  for (final record in records) {
    final deviceId = normalizeSyncDeviceId(record.deviceId, fallback: '');
    if (deviceId.isEmpty) {
      continue;
    }
    if (!isSyncDeviceSequenceInRange(record.sequence)) {
      continue;
    }
    if (record.sequence <= (previousSequences[deviceId] ?? 0)) {
      continue;
    }
    candidates.add(_OperationLogCandidate(record: record, deviceId: deviceId));
  }
  candidates.sort((a, b) {
    final deviceComparison = a.deviceId.compareTo(b.deviceId);
    if (deviceComparison != 0) {
      return deviceComparison;
    }
    final sequenceComparison = a.record.sequence.compareTo(b.record.sequence);
    if (sequenceComparison != 0) {
      return sequenceComparison;
    }
    final canonicalComparison =
        _compareCanonicalOperationLogRecords(a, b, paths);
    if (canonicalComparison != 0) {
      return canonicalComparison;
    }
    final metadataComparison = _operationLogMetadataScore(b.record).compareTo(
      _operationLogMetadataScore(a.record),
    );
    if (metadataComparison != 0) {
      return metadataComparison;
    }
    final pathComparison = a.record.path.compareTo(b.record.path);
    if (pathComparison != 0) {
      return pathComparison;
    }
    final etagComparison = (a.record.etag ?? '').compareTo(b.record.etag ?? '');
    if (etagComparison != 0) {
      return etagComparison;
    }
    final contentLengthComparison =
        (a.record.contentLength ?? -1).compareTo(b.record.contentLength ?? -1);
    if (contentLengthComparison != 0) {
      return contentLengthComparison;
    }
    return (a.record.lastModifiedUtc?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .compareTo(
      b.record.lastModifiedUtc?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });

  final selected = <WebDavOperationLogRecord>[];
  final expectedSequences = <String, int>{};
  final blockedDevices = <String>{};
  for (final candidate in candidates) {
    if (blockedDevices.contains(candidate.deviceId)) {
      continue;
    }
    final expectedSequence = expectedSequences.putIfAbsent(
      candidate.deviceId,
      () => (previousSequences[candidate.deviceId] ?? 0) + 1,
    );
    if (candidate.record.sequence < expectedSequence) {
      continue;
    }
    if (candidate.record.sequence > expectedSequence) {
      blockedDevices.add(candidate.deviceId);
      continue;
    }
    selected.add(candidate.record);
    expectedSequences[candidate.deviceId] = expectedSequence + 1;
  }
  return selected;
}

WebDavStateSyncPaths _operationLogPathsFor(AppState state) {
  final settings = state.sync.webDav.copy()..normalize();
  return WebDavStateSyncPaths(rootPath: settings.rootPath);
}

int _compareCanonicalOperationLogRecords(
  _OperationLogCandidate left,
  _OperationLogCandidate right,
  WebDavStateSyncPaths paths,
) {
  final leftIsCanonical = _isCanonicalOperationLogRecord(
    left.record,
    left.deviceId,
    paths,
  );
  final rightIsCanonical = _isCanonicalOperationLogRecord(
    right.record,
    right.deviceId,
    paths,
  );
  if (leftIsCanonical == rightIsCanonical) {
    return 0;
  }
  return leftIsCanonical ? -1 : 1;
}

bool _isCanonicalOperationLogRecord(
  WebDavOperationLogRecord record,
  String deviceId,
  WebDavStateSyncPaths paths,
) {
  try {
    return record.path == paths.operationLogPath(deviceId, record.sequence);
  } on WebDavSyncConfigurationException {
    return false;
  }
}

int _operationLogMetadataScore(WebDavOperationLogRecord record) {
  return (record.etag == null ? 0 : 4) +
      (record.contentLength == null ? 0 : 2) +
      (record.lastModifiedUtc == null ? 0 : 1);
}

class _OperationLogCandidate {
  const _OperationLogCandidate({
    required this.record,
    required this.deviceId,
  });

  final WebDavOperationLogRecord record;
  final String deviceId;
}
