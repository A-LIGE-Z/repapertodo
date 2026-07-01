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
      sync: _configuredSyncSettings(autoSyncOnStart: true),
    );
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
      platform: NoopPlatformServices(),
      syncService: syncService,
    );

    expect(bootstrap, isNotNull);
    expect(bootstrap!.controller.state.papers.single.title, 'Remote');
    expect(bootstrap.controller.state.papers.single.content, 'Merged body');
    final stored = await store.load();
    expect(stored.papers.single.title, 'Remote');
    expect(stored.papers.single.content, 'Merged body');
    expect(stored.sync.operationDeviceSequences, {'device-a': 1});
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
}

SyncSettings _configuredSyncSettings({required bool autoSyncOnStart}) {
  return SyncSettings(
    enabled: true,
    provider: SyncProviderIds.webDav,
    webDav: WebDavSyncSettings(
      endpoint: 'https://dav.example.test/',
      username: 'user',
      password: 'pass',
      rootPath: 'repapertodo',
      autoSyncOnStart: autoSyncOnStart,
    ),
  );
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

class _FakeWebDavStateSyncService extends WebDavStateSyncService {
  _FakeWebDavStateSyncService({
    required _FakeSync onSync,
    _FakeListOperationLogs? onListOperationLogs,
    _FakeDownloadOperationLog? onDownloadOperationLog,
  })  : _onSync = onSync,
        _onListOperationLogs = onListOperationLogs,
        _onDownloadOperationLog = onDownloadOperationLog,
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
    final onDownloadOperationLog = _onDownloadOperationLog;
    if (onDownloadOperationLog == null) {
      throw StateError('Unexpected downloadOperationLog call.');
    }
    return onDownloadOperationLog(operationLogPath);
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
