import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('returns disabled when sync is off', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_disabled_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_) => throw StateError('WebDAV should not be created'),
    );

    final result = await service.syncNow(
      localState: AppState(),
      store: store,
    );

    expect(result.status, AppSyncStatus.disabled);
  });

  test('uploads configured local state', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_upload_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final localState = AppState(
      papers: [
        PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
      ],
      sync: _configuredSyncSettings(),
    );
    var uploadedStateTitle = '';
    final service = AppSyncService(
      webDavFactory: (_) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          uploadedStateTitle = localState.papers.single.title;
          return const WebDavStateSyncResult(
              status: WebDavStateSyncStatus.uploaded);
        },
      ),
    );

    final result = await service.syncNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 6, 30),
    );

    expect(result.status, AppSyncStatus.uploaded);
    expect(uploadedStateTitle, 'Local');
    expect((await store.load()).papers.single.title, 'Local');
  });

  test('saves downloaded remote state', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_download_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final remoteState = AppState(
      papers: [
        PaperData(id: 'paper-remote', type: PaperTypes.note, title: 'Remote'),
      ],
      sync: _configuredSyncSettings(),
    );
    final service = AppSyncService(
      webDavFactory: (_) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
          );
        },
      ),
    );

    final result = await service.syncNow(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 6, 30),
    );

    expect(result.status, AppSyncStatus.downloaded);
    expect(result.state?.papers.single.title, 'Remote');
    expect((await store.load()).papers.single.title, 'Remote');
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
      rootPath: 'repapertodo',
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
