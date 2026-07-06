import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('auto syncs from WebDAV on startup when enabled', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_bootstrap_sync_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(
      AppState(
        papers: [
          PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
        ],
        pinnedTodoHotKey: 'Ctrl+Alt+L',
        sync: _configuredSyncSettings(autoSyncOnStart: true),
      ),
    );
    final remoteState = AppState(
      papers: [
        PaperData(
          id: 'paper-remote',
          type: PaperTypes.note,
          title: 'Remote',
          content: 'Snapshot body',
        ),
      ],
      pinnedTodoHotKey: 'Ctrl+Alt+R',
      sync: _configuredSyncSettings(autoSyncOnStart: true),
    );
    final platform = _RecordingBootstrapPlatformServices();
    final syncService = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
          );
        },
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000001.jsonl',
              deviceId: 'device-a',
              sequence: 1,
            ),
          ];
        },
        onDownloadOperationLog: (operationLogPath) async {
          return [
            SyncOperation(
              id: 'device-a-1',
              deviceId: 'device-a',
              sequence: 1,
              kind: SyncOperationKind.updateNoteContent,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9),
              payload: {
                'paperId': 'paper-remote',
                'content': 'Merged body',
              },
            ),
          ];
        },
      ),
    );

    final bootstrap = await AppBootstrap.load(
      const [],
      store: store,
      platform: platform,
      syncService: syncService,
    );

    expect(bootstrap, isNotNull);
    expect(bootstrap!.controller.state.papers.single.title, 'Remote');
    expect(bootstrap.controller.state.papers.single.content, 'Merged body');
    final stored = await store.load();
    expect(stored.papers.single.title, 'Remote');
    expect(stored.papers.single.content, 'Merged body');
    expect(stored.sync.operationDeviceSequences, {'device-a': 1});
    expect(platform.paperWindows.restoredTitles, ['Local', 'Remote']);
    expect(platform.tray.rebuiltTitles, [
      ['Local'],
      ['Remote'],
    ]);
    expect(platform.systemIntegration.registeredTodoHotkeys, [
      'Ctrl+Alt+L',
      'Ctrl+Alt+R',
    ]);
  });

  test('keeps startup settings request after startup WebDAV sync', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_bootstrap_settings_sync_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(
      AppState(
        papers: [
          PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
        ],
        sync: _configuredSyncSettings(autoSyncOnStart: true),
      ),
    );
    final platform = _RecordingBootstrapPlatformServices();
    final syncService = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: AppState(
              papers: [
                PaperData(
                  id: 'paper-remote',
                  type: PaperTypes.note,
                  title: 'Remote',
                ),
              ],
              sync: _configuredSyncSettings(autoSyncOnStart: true),
            ),
          );
        },
        onListOperationLogs: () async => const [],
      ),
    );

    final bootstrap = await AppBootstrap.load(
      const ['--settings'],
      store: store,
      platform: platform,
      syncService: syncService,
    );

    expect(bootstrap, isNotNull);
    expect(
      bootstrap!.controller.takePendingUiStartupCommand()?.kind,
      StartupCommandKind.settings,
    );
    expect(bootstrap.controller.state.papers.single.title, 'Remote');
  });

  test('keeps local data usable when startup WebDAV sync fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_bootstrap_sync_failure_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(
      AppState(
        papers: [
          PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
        ],
        pinnedTodoHotKey: 'Ctrl+Alt+L',
        sync: _configuredSyncSettings(autoSyncOnStart: true),
      ),
    );
    final platform = _RecordingBootstrapPlatformServices();

    final bootstrap = await AppBootstrap.load(
      const [],
      store: store,
      platform: platform,
      syncService: _FailingStartupSyncService(),
    );

    expect(bootstrap, isNotNull);
    expect(bootstrap!.controller.state.papers.single.title, 'Local');
    final stored = await store.load();
    expect(stored.papers.single.title, 'Local');
    expect(platform.paperWindows.restoredTitles, ['Local']);
    expect(platform.tray.rebuiltTitles, [
      ['Local'],
    ]);
    expect(platform.systemIntegration.registeredTodoHotkeys, ['Ctrl+Alt+L']);
  });

  test('skips startup WebDAV sync until settings are complete', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_bootstrap_incomplete_sync_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(
      AppState(
        papers: [
          PaperData(
            id: 'paper-local',
            type: PaperTypes.todo,
            title: 'Local',
          ),
        ],
        pinnedTodoHotKey: 'Ctrl+Alt+L',
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            rootPath: 'repapertodo',
            autoSyncOnStart: true,
          ),
        ),
      ),
    );
    final platform = _RecordingBootstrapPlatformServices();
    final syncService = _CountingStartupSyncService();

    final bootstrap = await AppBootstrap.load(
      const [],
      store: store,
      platform: platform,
      syncService: syncService,
    );

    expect(bootstrap, isNotNull);
    expect(syncService.calls, 0);
    expect(bootstrap!.controller.state.papers.single.title, 'Local');
    final stored = await store.load();
    expect(stored.papers.single.title, 'Local');
    expect(platform.paperWindows.restoredTitles, ['Local']);
    expect(platform.tray.rebuiltTitles, [
      ['Local'],
    ]);
    expect(platform.systemIntegration.registeredTodoHotkeys, ['Ctrl+Alt+L']);
  });

  test('boots from legacy PaperTodo data and rewrites the migrated state',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_bootstrap_legacy_data_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString(_legacyPaperTodoJson(
      title: 'Legacy startup note',
      content: 'Loaded from the old data file',
      pinnedTodoHotKey: 'Ctrl+Alt+T',
    ));
    final platform = _RecordingBootstrapPlatformServices();

    final bootstrap = await AppBootstrap.load(
      const [],
      store: store,
      platform: platform,
    );

    expect(bootstrap, isNotNull);
    expect(bootstrap!.controller.state.papers.single.id, 'legacy-note');
    expect(bootstrap.controller.state.papers.single.title, 'Legacy');
    expect(
      bootstrap.controller.state.papers.single.content,
      'Loaded from the old data file',
    );
    expect(platform.paperWindows.restoredTitles, ['Legacy']);
    expect(platform.tray.rebuiltTitles, [
      ['Legacy'],
    ]);
    expect(platform.systemIntegration.registeredTodoHotkeys, ['Ctrl+Alt+T']);

    final savedText = await File(store.filePath).readAsString();
    expect(savedText, contains('"papers"'));
    expect(savedText, isNot(contains('"Papers"')));
    final stored = await store.load();
    expect(stored.papers.single.id, 'legacy-note');
    expect(stored.papers.single.title, 'Legacy');
    expect(stored.pinnedTodoHotKey, 'Ctrl+Alt+T');
  });

  test('forwards startup args when another instance owns the app', () async {
    final platform = _ForwardingPlatformServices();

    final bootstrap = await AppBootstrap.load(
      const ['--new-note'],
      platform: platform,
    );

    expect(bootstrap, isNull);
    expect(platform.startup.forwardedArgs, [
      ['--new-note'],
    ]);
  });

  test('returns null after primary startup exit command', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_bootstrap_exit_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString('''
{
  "Theme": "dark",
  "Papers": []
}
''');
    final platform = _RecordingBootstrapPlatformServices();

    final bootstrap = await AppBootstrap.load(
      const ['--exit'],
      store: store,
      platform: platform,
    );

    expect(bootstrap, isNull);
    expect(platform.systemIntegration.exitApplicationCount, 1);
    expect(platform.tray.rebuiltTitles, isEmpty);
    expect(platform.paperWindows.restoredTitles, isEmpty);
    expect((await store.load()).papers, isEmpty);
    final savedJson = await File(store.filePath).readAsString();
    expect(savedJson, contains('"theme": "dark"'));
    expect(savedJson, isNot(contains('"Theme"')));
  });

  test('keeps desktop state file beside the executable', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_desktop_path_');
    addTearDown(() => directory.delete(recursive: true));

    final path = await AppBootstrap.defaultStateFilePathForPlatform(
      isDesktop: true,
      desktopExecutablePath: ' ${p.join(directory.path, 'repapertodo.exe')} ',
      mobileDocumentsDirectoryPath: () {
        throw StateError('Unexpected mobile directory lookup.');
      },
    );

    expect(path, p.join(directory.path, 'data.json'));

    await expectLater(
      AppBootstrap.defaultStateFilePathForPlatform(
        isDesktop: true,
        desktopExecutablePath: '   ',
        mobileDocumentsDirectoryPath: () {
          throw StateError('Unexpected mobile directory lookup.');
        },
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('stores mobile state file in the app documents directory', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_mobile_path_');
    addTearDown(() => directory.delete(recursive: true));

    final path = await AppBootstrap.defaultStateFilePathForPlatform(
      isDesktop: false,
      desktopExecutablePath: p.join(directory.path, 'repapertodo.exe'),
      mobileDocumentsDirectoryPath: () async => ' ${directory.path} ',
    );

    expect(path, p.join(directory.path, 'data.json'));
  });
}

class _FailingStartupSyncService extends AppSyncService {
  @override
  Future<AppSyncRunResult> syncAndMergeNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    throw StateError('Temporary startup sync failure');
  }
}

class _CountingStartupSyncService extends AppSyncService {
  var calls = 0;

  @override
  Future<AppSyncRunResult> syncAndMergeNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    calls += 1;
    throw StateError('Unexpected startup sync call');
  }
}

SyncSettings _configuredSyncSettings({required bool autoSyncOnStart}) {
  return SyncSettings(
    enabled: true,
    provider: SyncProviderIds.webDav,
    webDav: WebDavSyncSettings(
      endpoint: 'https://dav.example.test/',
      username: 'user',
      password: 'pass',
      encryptionPassphrase: 'shared sync secret',
      rootPath: 'repapertodo',
      autoSyncOnStart: autoSyncOnStart,
    ),
  );
}

String _legacyPaperTodoJson({
  required String title,
  required String content,
  required String pinnedTodoHotKey,
}) {
  return '''
{
  "PinnedTodoHotKey": "$pinnedTodoHotKey",
  "Papers": [
    {
      "Id": "legacy-note",
      "Type": "note",
      "Title": "$title",
      "Content": "$content"
    }
  ]
}
''';
}

typedef _FakeSync = Future<WebDavStateSyncResult> Function({
  required AppState localState,
  DateTime? localUpdatedAtUtc,
});

typedef _FakeListOperationLogs = Future<List<WebDavOperationLogRecord>>
    Function();

typedef _FakeDownloadOperationLog = Future<List<SyncOperation>> Function(
  String operationLogPath,
);

typedef _FakeDownloadOperationLogWithMetadata
    = Future<WebDavOperationLogDownloadResult> Function(
  String operationLogPath,
);

class _FakeWebDavStateSyncService extends WebDavStateSyncService {
  _FakeWebDavStateSyncService({
    required _FakeSync onSync,
    _FakeListOperationLogs? onListOperationLogs,
    _FakeDownloadOperationLog? onDownloadOperationLog,
    _FakeDownloadOperationLogWithMetadata? onDownloadOperationLogWithMetadata,
  })  : _onSync = onSync,
        _onListOperationLogs = onListOperationLogs,
        _onDownloadOperationLog = onDownloadOperationLog,
        _onDownloadOperationLogWithMetadata =
            onDownloadOperationLogWithMetadata,
        super(
          client: WebDavClient(
            baseUri: Uri.parse('https://unused.example.test/'),
            credentials:
                const WebDavCredentials(username: 'unused', password: 'unused'),
          ),
        );

  final _FakeSync _onSync;
  final _FakeListOperationLogs? _onListOperationLogs;
  final _FakeDownloadOperationLog? _onDownloadOperationLog;
  final _FakeDownloadOperationLogWithMetadata?
      _onDownloadOperationLogWithMetadata;

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
  Future<List<WebDavOperationLogRecord>> listOperationLogs() {
    final onListOperationLogs = _onListOperationLogs;
    if (onListOperationLogs == null) {
      throw StateError('Unexpected listOperationLogs call.');
    }
    return onListOperationLogs();
  }

  @override
  Future<List<SyncOperation>> downloadOperationLog(String operationLogPath) {
    final onDownloadOperationLogWithMetadata =
        _onDownloadOperationLogWithMetadata;
    if (onDownloadOperationLogWithMetadata != null) {
      return onDownloadOperationLogWithMetadata(operationLogPath).then(
        (result) => result.operations,
      );
    }
    final onDownloadOperationLog = _onDownloadOperationLog;
    if (onDownloadOperationLog == null) {
      throw StateError('Unexpected downloadOperationLog call.');
    }
    return onDownloadOperationLog(operationLogPath);
  }

  @override
  Future<WebDavOperationLogDownloadResult> downloadOperationLogWithMetadata(
    String operationLogPath,
  ) async {
    final onDownloadOperationLogWithMetadata =
        _onDownloadOperationLogWithMetadata;
    if (onDownloadOperationLogWithMetadata != null) {
      return onDownloadOperationLogWithMetadata(operationLogPath);
    }
    final onDownloadOperationLog = _onDownloadOperationLog;
    if (onDownloadOperationLog == null) {
      throw StateError('Unexpected downloadOperationLogWithMetadata call.');
    }
    return WebDavOperationLogDownloadResult(
      path: operationLogPath,
      operations: await onDownloadOperationLog(operationLogPath),
    );
  }
}

class _ForwardingPlatformServices implements PlatformServices {
  @override
  final PaperWindowHost paperWindows = NoopPaperWindowHost();

  @override
  final TrayHost tray = NoopTrayHost();

  @override
  final _ForwardingStartupHost startup;

  @override
  final SystemIntegrationHost systemIntegration = NoopSystemIntegrationHost();

  @override
  final ExternalFileHost externalFiles = NoopExternalFileHost();

  @override
  final UriOpenHost uriOpener = NoopUriOpenHost();

  @override
  final ScriptCapsuleHost scriptCapsules = NoopScriptCapsuleHost();

  @override
  final AppStorageHost storage = NoopAppStorageHost();

  _ForwardingPlatformServices() : startup = _ForwardingStartupHost();
}

class _ForwardingStartupHost extends NoopStartupHost {
  final forwardedArgs = <List<String>>[];

  @override
  Future<bool> acquireSingleInstance() async => false;

  @override
  Future<void> forwardToPrimary(List<String> args) async {
    forwardedArgs.add(List<String>.from(args));
  }
}

class _RecordingBootstrapPlatformServices implements PlatformServices {
  @override
  final _RecordingBootstrapPaperWindowHost paperWindows =
      _RecordingBootstrapPaperWindowHost();

  @override
  final _RecordingBootstrapTrayHost tray = _RecordingBootstrapTrayHost();

  @override
  final StartupHost startup = NoopStartupHost();

  @override
  final _RecordingBootstrapSystemIntegrationHost systemIntegration =
      _RecordingBootstrapSystemIntegrationHost();

  @override
  final ExternalFileHost externalFiles = NoopExternalFileHost();

  @override
  final UriOpenHost uriOpener = NoopUriOpenHost();

  @override
  final ScriptCapsuleHost scriptCapsules = NoopScriptCapsuleHost();

  @override
  final AppStorageHost storage = NoopAppStorageHost();
}

class _RecordingBootstrapPaperWindowHost extends NoopPaperWindowHost {
  final restoredTitles = <String>[];

  @override
  Future<void> restoreAll(AppState state) async {
    restoredTitles.addAll(state.papers.map((paper) => paper.title));
  }
}

class _RecordingBootstrapTrayHost extends NoopTrayHost {
  final rebuiltTitles = <List<String>>[];

  @override
  Future<void> rebuildMenu(AppState state) async {
    rebuiltTitles.add(state.papers.map((paper) => paper.title).toList());
  }
}

class _RecordingBootstrapSystemIntegrationHost
    extends NoopSystemIntegrationHost {
  @override
  bool get supportsGlobalHotkeys => true;

  final registeredTodoHotkeys = <String>[];
  var exitApplicationCount = 0;

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {
    registeredTodoHotkeys.add(state.pinnedTodoHotKey);
  }

  @override
  Future<void> exitApplication() async {
    exitApplicationCount += 1;
  }
}
