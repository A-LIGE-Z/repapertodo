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
        PaperData(id: 'paper-remote', type: PaperTypes.note, title: 'Remote'),
      ],
      sync: _configuredSyncSettings(autoSyncOnStart: true),
    );
    final syncService = AppSyncService(
      webDavFactory: (_) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
          );
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
    expect((await store.load()).papers.single.title, 'Remote');
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

class _FakeWebDavStateSyncService extends WebDavStateSyncService {
  _FakeWebDavStateSyncService({required _FakeSync onSync})
      : _onSync = onSync,
        super(
          client: WebDavClient(
            baseUri: Uri.parse('https://unused.example.test/'),
            credentials:
                const WebDavCredentials(username: 'unused', password: 'unused'),
          ),
        );

  final _FakeSync _onSync;

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
