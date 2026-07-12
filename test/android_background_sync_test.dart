import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/repapertodo.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android background sync initializes the dispatcher on Android',
      () async {
    final scheduler = _RecordingBackgroundScheduler();

    await initializeRePaperTodoAndroidBackgroundSync(
      isAndroid: true,
      scheduler: scheduler,
    );

    expect(scheduler.initializedCallbacks, hasLength(1));
    expect(scheduler.registeredPeriodicTasks, isEmpty);
    expect(scheduler.cancelledUniqueNames, isEmpty);
  });

  test('Android background sync registers periodic WebDAV work when configured',
      () async {
    final scheduler = _RecordingBackgroundScheduler();

    await configureRePaperTodoAndroidBackgroundSync(
      sync: _configuredSyncSettings(),
      stateFilePath: r' C:\Users\tester\Documents\RePaperTodo\data.json ',
      isAndroid: true,
      scheduler: scheduler,
    );

    expect(scheduler.cancelledUniqueNames, isEmpty);
    expect(scheduler.registeredPeriodicTasks, hasLength(1));
    final task = scheduler.registeredPeriodicTasks.single;
    expect(task.uniqueName, androidBackgroundSyncUniqueName);
    expect(task.taskName, androidBackgroundSyncTaskName);
    expect(task.frequency, const Duration(minutes: 15));
    expect(task.constraints?.networkType, NetworkType.connected);
    expect(task.existingWorkPolicy, ExistingPeriodicWorkPolicy.update);
    expect(task.backoffPolicy, BackoffPolicy.exponential);
    expect(task.backoffPolicyDelay, const Duration(minutes: 5));
    expect(task.tag, androidBackgroundSyncTag);
    expect(task.inputData, {
      androidBackgroundSyncStateFilePathKey:
          r'C:\Users\tester\Documents\RePaperTodo\data.json',
    });
  });

  test('Android background sync accepts POSIX absolute state paths', () async {
    final scheduler = _RecordingBackgroundScheduler();

    await configureRePaperTodoAndroidBackgroundSync(
      sync: _configuredSyncSettings(),
      stateFilePath: ' /data/user/0/com.aligez.repapertodo/files/data.json ',
      isAndroid: true,
      scheduler: scheduler,
    );

    expect(scheduler.cancelledUniqueNames, isEmpty);
    expect(scheduler.registeredPeriodicTasks, hasLength(1));
    expect(scheduler.registeredPeriodicTasks.single.inputData, {
      androidBackgroundSyncStateFilePathKey:
          '/data/user/0/com.aligez.repapertodo/files/data.json',
    });
  });

  test('Android background sync cancels periodic work for unsafe state paths',
      () async {
    for (final stateFilePath in const [
      '',
      '   ',
      'relative/data.json',
      r'.\data.json',
      r'C:\Users\tester\Documents\RePaperTodo\state.json',
      '/data/user/0/com.aligez.repapertodo/files/state.json',
      'build/data.json\nbad',
      '\u0085build/data.json',
    ]) {
      final scheduler = _RecordingBackgroundScheduler();

      await configureRePaperTodoAndroidBackgroundSync(
        sync: _configuredSyncSettings(),
        stateFilePath: stateFilePath,
        isAndroid: true,
        scheduler: scheduler,
      );

      expect(
        scheduler.registeredPeriodicTasks,
        isEmpty,
        reason: stateFilePath,
      );
      expect(
        scheduler.cancelledUniqueNames,
        [androidBackgroundSyncUniqueName],
        reason: stateFilePath,
      );
    }
  });

  test('Android background sync cancels periodic work when not configured',
      () async {
    final scheduler = _RecordingBackgroundScheduler();

    await configureRePaperTodoAndroidBackgroundSync(
      sync: SyncSettings(enabled: true),
      stateFilePath: r'C:\Users\tester\Documents\RePaperTodo\data.json',
      isAndroid: true,
      scheduler: scheduler,
    );

    expect(scheduler.registeredPeriodicTasks, isEmpty);
    expect(scheduler.cancelledUniqueNames, [androidBackgroundSyncUniqueName]);
  });

  test('Android background sync reuses WebDAV sync service and saves state',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_background_sync_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(
      AppState(
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.note,
            title: 'Local',
            content: 'Local before background sync',
          ),
        ],
        sync: _configuredSyncSettings(),
      ),
    );
    final syncService = _RecordingBackgroundSyncService(
      resultState: AppState(
        papers: [
          PaperData(
            id: 'remote-paper',
            type: PaperTypes.note,
            title: 'Synced',
            content: 'Synced in Android background',
          ),
        ],
        sync: _configuredSyncSettings(),
      ),
    );

    final success = await runRePaperTodoBackgroundSync(
      {androidBackgroundSyncStateFilePathKey: store.filePath},
      syncService: syncService,
    );

    expect(success, true);
    expect(syncService.calls, 1);
    expect(syncService.localContents, ['Local before background sync']);
    expect((await store.load()).papers.single.content,
        'Synced in Android background');
  });

  test('Android background sync flushes a persisted durable operation batch',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_background_sync_durable_outbox_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final deviceIdPath = p.join(directory.path, 'sync-device-id');
    await File(deviceIdPath).writeAsString('device-android');
    final beforeState = AppState(
      papers: [
        PaperData(
          id: 'background-note',
          type: PaperTypes.note,
          content: 'Before background edit',
        ),
      ],
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-android': 7},
    );
    final afterState = AppState.fromJson(beforeState.toJson())
      ..papers.single.content = 'Saved before background worker';
    final preparationService = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(filePath: deviceIdPath),
    );
    final prepared = await preparationService.preparePendingLocalOperationBatch(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: DateTime.utc(2026, 7, 11, 12, 30),
    );
    await store.save(prepared);
    final uploadedIds = <String>[];
    final syncService = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(filePath: deviceIdPath),
      webDavFactory: (_, {deviceId}) => _BackgroundWebDavStateSyncService(
        onUploadOperationLogs: (
          operations, {
          previousDeviceSequences,
        }) async {
          uploadedIds.addAll(operations.map((operation) => operation.id));
          expect(previousDeviceSequences, {'device-android': 7});
          return const WebDavOperationLogUploadResult(
            deviceSequences: {'device-android': 8},
            uploadedCount: 1,
            acceptedDeviceSequences: {'device-android': 8},
          );
        },
        onSync: ({required localState, localUpdatedAtUtc}) async {
          expect(
            localState.papers.single.content,
            'Saved before background worker',
          );
          expect(localState.sync.pendingOperationBatch, isNotNull);
          return const WebDavStateSyncResult(
            status: WebDavStateSyncStatus.uploaded,
          );
        },
      ),
    );

    final success = await runRePaperTodoBackgroundSync(
      {androidBackgroundSyncStateFilePathKey: store.filePath},
      syncService: syncService,
    );

    expect(success, true);
    expect(uploadedIds, ['device-android-8']);
    final stored = await store.load();
    expect(stored.papers.single.content, 'Saved before background worker');
    expect(stored.sync.pendingOperationBatch, isNull);
    expect(stored.sync.operationDeviceSequences, {'device-android': 8});
  });

  test('Android background sync skips incomplete WebDAV settings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_background_sync_disabled_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(
      AppState(
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.todo,
            title: 'Local',
          ),
        ],
      ),
    );
    final syncService = _RecordingBackgroundSyncService(
      resultState: AppState(papers: [
        PaperData(
          id: 'remote-paper',
          type: PaperTypes.todo,
          title: 'Should not sync',
        ),
      ]),
    );

    final success = await runRePaperTodoBackgroundSync(
      {androidBackgroundSyncStateFilePathKey: store.filePath},
      syncService: syncService,
    );

    expect(success, true);
    expect(syncService.calls, 0);
    expect((await store.load()).papers.single.id, 'local-paper');
  });

  test('Android background sync treats unreadable payloads as non-retryable',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_background_sync_payload_unreadable_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(
      AppState(
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.note,
            title: 'Local',
            content: 'Needs passphrase fix',
          ),
        ],
        sync: _configuredSyncSettings(),
      ),
    );
    final syncService = _RecordingBackgroundSyncService(
      status: AppSyncStatus.payloadUnreadable,
      resultState: AppState(
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.note,
            title: 'Local',
            content: 'Needs passphrase fix',
          ),
        ],
        sync: _configuredSyncSettings(),
      ),
    );

    final success = await runRePaperTodoBackgroundSync(
      {androidBackgroundSyncStateFilePathKey: store.filePath},
      syncService: syncService,
    );

    expect(success, true);
    expect(syncService.calls, 1);
  });

  test('Android background sync reports conflicts as retryable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_background_sync_conflict_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(
      AppState(
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.todo,
            title: 'Local',
          ),
        ],
        sync: _configuredSyncSettings(),
      ),
    );
    final syncService = _RecordingBackgroundSyncService(
      status: AppSyncStatus.conflict,
      resultState: AppState(
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.todo,
            title: 'Local',
          ),
        ],
        sync: _configuredSyncSettings(),
      ),
    );

    final success = await runRePaperTodoBackgroundSync(
      {androidBackgroundSyncStateFilePathKey: store.filePath},
      syncService: syncService,
    );

    expect(success, false);
    expect(syncService.calls, 1);
  });

  test('Android background sync rejects unsafe state file paths', () async {
    for (final stateFilePath in const [
      '',
      '   ',
      'relative/data.json',
      r'.\data.json',
      r'C:\Users\tester\Documents\RePaperTodo\state.json',
      '/data/user/0/com.aligez.repapertodo/files/state.json',
      'build/data.json\nbad',
      '\u0085build/data.json',
    ]) {
      final success = await runRePaperTodoBackgroundSync(
        {androidBackgroundSyncStateFilePathKey: stateFilePath},
        syncService: _RecordingBackgroundSyncService(resultState: AppState()),
      );

      expect(success, false, reason: stateFilePath);
    }
  });
}

SyncSettings _configuredSyncSettings() {
  return SyncSettings(
    enabled: true,
    provider: SyncProviderIds.webDav,
    webDav: WebDavSyncSettings(
      endpoint: 'https://dav.example.test/',
      username: 'user',
      password: 'pass',
      encryptionPassphrase: 'shared sync secret',
      rootPath: 'repapertodo',
    ),
  );
}

class _RecordingBackgroundSyncService extends AppSyncService {
  _RecordingBackgroundSyncService({
    required this.resultState,
    this.status = AppSyncStatus.uploaded,
  });

  final AppState resultState;
  final AppSyncStatus status;
  final localContents = <String>[];
  int calls = 0;

  @override
  Future<AppSyncRunResult> syncAndMergeNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    calls += 1;
    localContents.addAll(localState.papers.map((paper) => paper.content));
    return AppSyncRunResult(
      syncResult: AppSyncResult(
        status: status,
        state: resultState,
        message: 'Local data uploaded.',
      ),
      state: resultState,
    );
  }
}

typedef _BackgroundSync = Future<WebDavStateSyncResult> Function({
  required AppState localState,
  DateTime? localUpdatedAtUtc,
});

typedef _BackgroundUploadOperationLogs = Future<WebDavOperationLogUploadResult>
    Function(
  Iterable<SyncOperation> operations, {
  Map<String, int>? previousDeviceSequences,
});

class _BackgroundWebDavStateSyncService extends WebDavStateSyncService {
  _BackgroundWebDavStateSyncService({
    required _BackgroundSync onSync,
    required _BackgroundUploadOperationLogs onUploadOperationLogs,
  })  : _onSync = onSync,
        _onUploadOperationLogs = onUploadOperationLogs,
        super(
          client: WebDavClient(
            baseUri: Uri.parse('https://unused.example.test/'),
            credentials:
                const WebDavCredentials(username: 'unused', password: 'unused'),
          ),
        );

  final _BackgroundSync _onSync;
  final _BackgroundUploadOperationLogs _onUploadOperationLogs;

  @override
  Future<WebDavStateSyncResult> sync({
    required AppState localState,
    DateTime? localUpdatedAtUtc,
  }) {
    return _onSync(
      localState: localState,
      localUpdatedAtUtc: localUpdatedAtUtc,
    );
  }

  @override
  Future<WebDavOperationLogUploadResult> uploadOperationLogs(
    Iterable<SyncOperation> operations, {
    Map<String, int>? previousDeviceSequences,
  }) {
    return _onUploadOperationLogs(
      operations,
      previousDeviceSequences: previousDeviceSequences,
    );
  }

  @override
  Future<List<WebDavOperationLogRecord>> listOperationLogs() async => const [];
}

class _RecordingBackgroundScheduler
    implements RePaperTodoAndroidBackgroundScheduler {
  final initializedCallbacks = <Function>[];
  final registeredPeriodicTasks = <_RecordedPeriodicTask>[];
  final cancelledUniqueNames = <String>[];

  @override
  Future<void> initialize(Function callbackDispatcher) async {
    initializedCallbacks.add(callbackDispatcher);
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
  }) async {
    registeredPeriodicTasks.add(
      _RecordedPeriodicTask(
        uniqueName: uniqueName,
        taskName: taskName,
        frequency: frequency,
        constraints: constraints,
        existingWorkPolicy: existingWorkPolicy,
        backoffPolicy: backoffPolicy,
        backoffPolicyDelay: backoffPolicyDelay,
        tag: tag,
        inputData: inputData,
      ),
    );
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelledUniqueNames.add(uniqueName);
  }
}

class _RecordedPeriodicTask {
  const _RecordedPeriodicTask({
    required this.uniqueName,
    required this.taskName,
    this.frequency,
    this.constraints,
    this.existingWorkPolicy,
    this.backoffPolicy,
    this.backoffPolicyDelay,
    this.tag,
    this.inputData,
  });

  final String uniqueName;
  final String taskName;
  final Duration? frequency;
  final Constraints? constraints;
  final ExistingPeriodicWorkPolicy? existingWorkPolicy;
  final BackoffPolicy? backoffPolicy;
  final Duration? backoffPolicyDelay;
  final String? tag;
  final Map<String, dynamic>? inputData;
}
