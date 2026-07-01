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
      webDavFactory: (_, {deviceId}) =>
          throw StateError('WebDAV should not be created'),
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
    var forwardedDeviceId = '';
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        forwardedDeviceId = deviceId ?? '';
        return _FakeWebDavStateSyncService(
          onSync: ({required localState, localUpdatedAtUtc}) async {
            uploadedStateTitle = localState.papers.single.title;
            return const WebDavStateSyncResult(
              status: WebDavStateSyncStatus.uploaded,
              snapshotPath: 'repapertodo/snapshots/local.json',
            );
          },
        );
      },
    );

    final result = await service.syncNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 6, 30),
    );

    expect(result.status, AppSyncStatus.uploaded);
    expect(result.snapshotPath, 'repapertodo/snapshots/local.json');
    expect(uploadedStateTitle, 'Local');
    expect(forwardedDeviceId, startsWith('device-'));
    expect((await store.load()).papers.single.title, 'Local');
    expect(
      await File(p.join(directory.path, 'sync-device-id')).readAsString(),
      forwardedDeviceId,
    );
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
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
            snapshotPath: 'repapertodo/snapshots/remote.json',
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
    expect(result.snapshotPath, 'repapertodo/snapshots/remote.json');
    expect(result.state?.papers.single.title, 'Remote');
    expect((await store.load()).papers.single.title, 'Remote');
  });

  test('reports WebDAV conflicts without saving local state', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_conflict_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return const WebDavStateSyncResult(
            status: WebDavStateSyncStatus.conflict,
            snapshotPath: 'repapertodo/snapshots/conflict-local.json',
          );
        },
      ),
    );

    final result = await service.syncNow(
      localState: AppState(
        papers: [
          PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
        ],
        sync: _configuredSyncSettings(),
      ),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, AppSyncStatus.conflict);
    expect(result.snapshotPath, 'repapertodo/snapshots/conflict-local.json');
    expect(result.message, contains('conflict-local.json'));
    expect(await File(store.filePath).exists(), isFalse);
  });

  test('lists recovery snapshots through configured WebDAV', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_list_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var forwardedDeviceId = '';
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        forwardedDeviceId = deviceId ?? '';
        return _FakeWebDavStateSyncService(
          onListSnapshots: () async {
            return [
              WebDavSnapshotRecord(
                path: 'repapertodo/snapshots/snapshot.json',
                deviceId: forwardedDeviceId,
                updatedAtUtc: DateTime.utc(2026, 7),
              ),
            ];
          },
        );
      },
    );

    final snapshots = await service.listRecoverySnapshots(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
    );

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, startsWith('device-'));
    expect(forwardedDeviceId, snapshots.single.deviceId);
  });

  test('restores a selected recovery snapshot', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_restore_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final snapshotState = AppState(
      papers: [
        PaperData(id: 'snapshot-paper', type: PaperTypes.note, title: 'Snap'),
      ],
      sync: _configuredSyncSettings(),
    );
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onDownloadSnapshot: (snapshotPath) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: snapshotState,
            snapshotPath: snapshotPath,
          );
        },
      ),
    );

    final result = await service.restoreRecoverySnapshot(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      snapshotPath: 'repapertodo/snapshots/snapshot.json',
    );

    expect(result.status, AppSyncStatus.downloaded);
    expect(result.message, 'Snapshot restored.');
    expect(result.snapshotPath, 'repapertodo/snapshots/snapshot.json');
    expect((await store.load()).papers.single.title, 'Snap');
  });

  test('returns no recovery snapshots when sync is disabled', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_no_list_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) =>
          throw StateError('WebDAV should not be created'),
    );

    final snapshots = await service.listRecoverySnapshots(
      localState: AppState(),
      store: store,
    );

    expect(snapshots, isEmpty);
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

typedef _FakeListSnapshots = Future<List<WebDavSnapshotRecord>> Function();

typedef _FakeDownloadSnapshot = Future<WebDavStateSyncResult> Function(
  String snapshotPath,
);

class _FakeWebDavStateSyncService extends WebDavStateSyncService {
  _FakeWebDavStateSyncService({
    _FakeSync? onSync,
    _FakeListSnapshots? onListSnapshots,
    _FakeDownloadSnapshot? onDownloadSnapshot,
  })  : _onSync = onSync,
        _onListSnapshots = onListSnapshots,
        _onDownloadSnapshot = onDownloadSnapshot,
        super(
          client: WebDavClient(
            baseUri: Uri.parse('https://unused.example.test/'),
            credentials:
                const WebDavCredentials(username: 'unused', password: 'unused'),
          ),
        );

  final _FakeSync? _onSync;
  final _FakeListSnapshots? _onListSnapshots;
  final _FakeDownloadSnapshot? _onDownloadSnapshot;

  @override
  Future<WebDavStateSyncResult> sync({
    required AppState localState,
    DateTime? localUpdatedAtUtc,
  }) {
    final onSync = _onSync;
    if (onSync == null) {
      throw StateError('Unexpected sync call.');
    }
    return onSync(
      localState: localState,
      localUpdatedAtUtc: localUpdatedAtUtc,
    );
  }

  @override
  Future<List<WebDavSnapshotRecord>> listSnapshots() {
    final onListSnapshots = _onListSnapshots;
    if (onListSnapshots == null) {
      throw StateError('Unexpected listSnapshots call.');
    }
    return onListSnapshots();
  }

  @override
  Future<WebDavStateSyncResult> downloadSnapshot(String snapshotPath) {
    final onDownloadSnapshot = _onDownloadSnapshot;
    if (onDownloadSnapshot == null) {
      throw StateError('Unexpected downloadSnapshot call.');
    }
    return onDownloadSnapshot(snapshotPath);
  }
}
