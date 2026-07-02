import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    final localState = AppState(
      papers: [
        PaperData(id: '', type: 'unknown-paper-type', title: 'Draft'),
      ],
    );
    final originalLocalStateJson = localState.toJson();

    final result = await service.syncNow(
      localState: localState,
      store: store,
    );

    expect(result.status, AppSyncStatus.disabled);
    expect(localState.toJson(), originalLocalStateJson);
  });

  test('requires an encryption passphrase for configured WebDAV sync',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_missing_passphrase_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) =>
          throw StateError('WebDAV should not be created'),
    );

    final localState = AppState(
      papers: [
        PaperData(id: '', type: 'unknown-paper-type', title: 'Draft'),
      ],
      sync: _configuredSyncSettings(encryptionPassphrase: ''),
    );
    final originalLocalStateJson = localState.toJson();

    final result = await service.syncNow(
      localState: localState,
      store: store,
    );

    expect(result.status, AppSyncStatus.configurationMissing);
    expect(result.message, contains('encryption passphrase'));
    expect(localState.toJson(), originalLocalStateJson);
  });

  test('does not create WebDAV clients for unsafe sync settings', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_unsafe_settings_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var createdCount = 0;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) {
        createdCount += 1;
        throw StateError('WebDAV should not be created');
      },
    );

    for (final syncSettings in [
      _configuredSyncSettings(
        endpoint: 'https://dav.example.test/dav/%0Afiles',
      ),
      _configuredSyncSettings(username: 'user:name'),
      _configuredSyncSettings(password: 'bad\npass'),
      _configuredSyncSettings(rootPath: 'repapertodo/%0Aother'),
    ]) {
      final localState = AppState(
        papers: [
          PaperData(id: '', type: 'unknown-paper-type', title: 'Draft'),
        ],
        sync: syncSettings,
      );
      final originalLocalStateJson = localState.toJson();
      final result = await service.syncNow(
        localState: localState,
        store: store,
      );

      expect(result.status, AppSyncStatus.configurationMissing);
      expect(result.message, contains('WebDAV sync settings'));
      expect(localState.toJson(), originalLocalStateJson);
    }

    expect(createdCount, 0);
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
    final originalLocalStateJson = localState.toJson();
    var uploadedStateTitle = '';
    var forwardedDeviceId = '';
    WebDavSyncSettings? forwardedSettings;
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (settings, {deviceId}) {
        forwardedSettings = settings;
        forwardedDeviceId = deviceId ?? '';
        return _FakeWebDavStateSyncService(
          onSync: ({required localState, localUpdatedAtUtc}) async {
            uploadedStateTitle = localState.papers.single.title;
            return WebDavStateSyncResult(
              status: WebDavStateSyncStatus.uploaded,
              snapshotPath: 'repapertodo/snapshots/local.json',
              manifest: SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30),
                latestSnapshotPath: 'repapertodo/snapshots/local.json',
                deviceSequences: {'remote-device': 4, 'local-device': 1},
              ),
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
    expect(result.state?.sync.operationDeviceSequences, {
      'remote-device': 4,
      'local-device': 1,
    });
    expect(localState.toJson(), originalLocalStateJson);
    expect(uploadedStateTitle, 'Local');
    expect(forwardedDeviceId, startsWith('device-'));
    expect(forwardedSettings?.encryptionPassphrase, 'shared sync secret');
    expect(forwardedSettings?.requestTimeoutSeconds, 45);
    final stored = await store.load();
    expect(stored.papers.single.title, 'Local');
    expect(stored.sync.operationDeviceSequences, {
      'remote-device': 4,
      'local-device': 1,
    });
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
    final originalRemoteStateJson = remoteState.toJson();
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
            snapshotPath: 'repapertodo/snapshots/remote.json',
            manifest: SyncManifest(
              schemaVersion: 1,
              updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
              latestSnapshotPath: 'repapertodo/snapshots/remote.json',
              deviceSequences: {'remote-device': 7},
            ),
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
    expect(remoteState.toJson(), originalRemoteStateJson);
    final stored = await store.load();
    expect(stored.papers.single.title, 'Remote');
    expect(stored.sync.operationDeviceSequences, {'remote-device': 7});
  });

  test('reports legacy plain WebDAV payloads when encryption is enabled',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_legacy_plain_payload_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final remoteState = AppState(
      papers: [
        PaperData(id: 'paper-remote', type: PaperTypes.note, title: 'Remote'),
      ],
    );
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
            snapshotPath: 'repapertodo/snapshots/plain.json',
            snapshotPayloadFormat: WebDavPayloadFormat.plainJson,
            manifest: SyncManifest(
              schemaVersion: 1,
              updatedAtUtc: DateTime.utc(2026, 7, 2, 12),
              latestSnapshotPath: 'repapertodo/snapshots/plain.json',
              deviceSequences: {'remote-device': 9},
            ),
          );
        },
      ),
    );

    final result = await service.syncNow(
      localState: AppState(
        sync: _configuredSyncSettings(
          encryptionPassphrase: 'shared sync secret',
        ),
      ),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7, 2, 11),
    );

    expect(result.status, AppSyncStatus.downloaded);
    expect(result.legacyPlainPayloadDetected, true);
    expect(result.message, contains('legacy plain WebDAV data'));
    expect(result.message, contains('next successful upload'));
    final stored = await store.load();
    expect(stored.sync.webDav.encryptionPassphrase, 'shared sync secret');
    expect(stored.sync.operationDeviceSequences, {'remote-device': 9});
  });

  test('migrates legacy plain WebDAV payloads when manifest ETag is available',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_migrate_legacy_plain_payload_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final deviceIdPath = p.join(directory.path, 'sync-device-id');
    await File(deviceIdPath).writeAsString('device-local');
    final remoteUpdatedAtUtc = DateTime.utc(2026, 7, 2, 12);
    final remoteState = AppState(
      papers: [
        PaperData(id: 'paper-remote', type: PaperTypes.note, title: 'Remote'),
      ],
    );
    var pushCalls = 0;
    String? pushExpectedManifestEtag;
    DateTime? pushUpdatedAtUtc;
    Map<String, int>? pushPreviousDeviceSequences;
    String? pushedPassphrase;
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(filePath: deviceIdPath),
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
            snapshotPath: 'repapertodo/snapshots/plain.json',
            snapshotPayloadFormat: WebDavPayloadFormat.plainJson,
            manifestEtag: '"manifest-v1"',
            manifest: SyncManifest(
              schemaVersion: 1,
              updatedAtUtc: remoteUpdatedAtUtc,
              latestSnapshotPath: 'repapertodo/snapshots/plain.json',
              deviceSequences: {'remote-device': 9},
            ),
          );
        },
        onPush: (
          state, {
          updatedAtUtc,
          expectedManifestEtag,
          manifestKnownMissing = false,
          previousDeviceSequences,
        }) async {
          pushCalls += 1;
          pushExpectedManifestEtag = expectedManifestEtag;
          pushUpdatedAtUtc = updatedAtUtc;
          pushPreviousDeviceSequences = previousDeviceSequences;
          pushedPassphrase = state.sync.webDav.encryptionPassphrase;
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.uploaded,
            snapshotPath: 'repapertodo/snapshots/encrypted.json',
            manifest: SyncManifest(
              schemaVersion: 1,
              updatedAtUtc: updatedAtUtc ?? remoteUpdatedAtUtc,
              latestSnapshotPath: 'repapertodo/snapshots/encrypted.json',
              deviceSequences: {
                'remote-device': 9,
                deviceId ?? 'device-local': 1,
              },
            ),
          );
        },
      ),
    );

    final result = await service.syncNow(
      localState: AppState(
        sync: _configuredSyncSettings(
          encryptionPassphrase: 'shared sync secret',
        ),
      ),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7, 2, 11),
    );

    expect(result.status, AppSyncStatus.downloaded);
    expect(result.legacyPlainPayloadDetected, true);
    expect(result.legacyPlainPayloadMigrated, true);
    expect(result.message, contains('migrated to encrypted payloads'));
    expect(pushCalls, 1);
    expect(pushExpectedManifestEtag, '"manifest-v1"');
    expect(pushPreviousDeviceSequences, {'remote-device': 9});
    expect(pushUpdatedAtUtc!.isAfter(remoteUpdatedAtUtc), true);
    expect(pushedPassphrase, 'shared sync secret');
    final stored = await store.load();
    expect(stored.sync.operationDeviceSequences, {
      'remote-device': 9,
      'device-local': 1,
    });
  });

  test('keeps downloaded state when legacy plain migration conflicts',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_migrate_legacy_plain_conflict_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final remoteState = AppState(
      papers: [
        PaperData(
          id: 'paper-remote',
          type: PaperTypes.note,
          title: 'Remote',
          content: 'Downloaded despite migration conflict',
        ),
      ],
    );
    var pushCalls = 0;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
            snapshotPath: 'repapertodo/snapshots/plain.json',
            snapshotPayloadFormat: WebDavPayloadFormat.plainJson,
            manifestEtag: '"manifest-v1"',
            manifest: SyncManifest(
              schemaVersion: 1,
              updatedAtUtc: DateTime.utc(2026, 7, 2, 12),
              latestSnapshotPath: 'repapertodo/snapshots/plain.json',
              deviceSequences: {'remote-device': 9},
            ),
          );
        },
        onPush: (
          state, {
          updatedAtUtc,
          expectedManifestEtag,
          manifestKnownMissing = false,
          previousDeviceSequences,
        }) async {
          pushCalls += 1;
          return const WebDavStateSyncResult(
            status: WebDavStateSyncStatus.conflict,
            snapshotPath: 'repapertodo/snapshots/local-preserved.json',
          );
        },
      ),
    );

    final result = await service.syncNow(
      localState: AppState(
        sync: _configuredSyncSettings(
          encryptionPassphrase: 'shared sync secret',
        ),
      ),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7, 2, 11),
    );

    expect(result.status, AppSyncStatus.downloaded);
    expect(result.legacyPlainPayloadDetected, true);
    expect(result.legacyPlainPayloadMigrated, false);
    expect(result.message, contains('could not complete'));
    expect(pushCalls, 1);
    final stored = await store.load();
    expect(
        stored.papers.single.content, 'Downloaded despite migration conflict');
    expect(stored.sync.operationDeviceSequences, {'remote-device': 9});
  });

  test('migrates legacy plain WebDAV payloads through real WebDAV requests',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_migrate_legacy_plain_http_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final deviceIdPath = p.join(directory.path, 'sync-device-id');
    await File(deviceIdPath).writeAsString('device-local');
    const stateCodec = AppStateCodec();
    final remoteUpdatedAtUtc = DateTime.utc(2026, 7, 2, 12);
    final legacySnapshotPath =
        'repapertodo/snapshots/snapshot-20260702T120000000Z-remote-device-seq-000000000009.json';
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      if (request.method == 'HEAD' &&
          request.url.path.endsWith('/manifest.json')) {
        return http.Response('', 200, headers: {'etag': '"manifest-v1"'});
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/manifest.json')) {
        return http.Response(
          jsonEncode(
            SyncManifest(
              schemaVersion: 1,
              updatedAtUtc: remoteUpdatedAtUtc,
              latestSnapshotPath: legacySnapshotPath,
              deviceSequences: {'remote-device': 9},
            ).toJson(),
          ),
          200,
        );
      }
      if (request.method == 'GET' &&
          request.url.path
              .endsWith('/${legacySnapshotPath.replaceAll('\\', '/')}')) {
        return http.Response.bytes(
          utf8.encode(_legacyPaperTodoSnapshotJson(
            id: 'paper-remote',
            title: 'Remote cloud note',
            content: 'Plain remote body',
          )),
          200,
        );
      }
      if (request.method == 'MKCOL') {
        return http.Response('', 201);
      }
      if (request.method == 'PUT' && request.url.path.contains('/snapshots/')) {
        return http.Response('', 201);
      }
      if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
        return http.Response('', 201);
      }
      if (request.method == 'PUT' &&
          request.url.path.endsWith('/manifest.json')) {
        return http.Response('', 201);
      }
      return http.Response('unexpected ${request.method} ${request.url}', 500);
    });
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(filePath: deviceIdPath),
      webDavFactory: (settings, {deviceId}) =>
          WebDavStateSyncService.fromSettings(
        settings,
        deviceId: deviceId,
        httpClient: httpClient,
      ),
    );

    final result = await service.syncNow(
      localState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
      ),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7, 2, 11),
    );

    expect(result.status, AppSyncStatus.downloaded);
    expect(result.legacyPlainPayloadDetected, true);
    expect(result.legacyPlainPayloadMigrated, true);
    expect(result.message, contains('migrated to encrypted payloads'));

    final snapshotUpload = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.contains('/snapshots/'));
    final snapshotText = utf8.decode(snapshotUpload.bodyBytes);
    expect(snapshotText, startsWith('RePaperTodo-Encrypted-Payload-v1\n'));
    expect(snapshotText, isNot(contains('Plain remote body')));
    final decodedSnapshot = await EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
    ).decodeSnapshot(snapshotUpload.bodyBytes, stateCodec);
    expect(decodedSnapshot.papers.single.id, 'paper-remote');
    expect(decodedSnapshot.papers.single.title, 'Remote');
    expect(decodedSnapshot.papers.single.content, 'Plain remote body');

    final operationUpload = requests.firstWhere(
      (request) =>
          request.method == 'PUT' && request.url.path.contains('/ops/'),
    );
    expect(utf8.decode(operationUpload.bodyBytes),
        startsWith('RePaperTodo-Encrypted-Payload-v1\n'));

    final manifestUpload = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.endsWith('/manifest.json'));
    expect(manifestUpload.headers['if-match'], '"manifest-v1"');
    final manifest = SyncManifest.fromJson(
      Map<String, Object?>.from(
        jsonDecode(utf8.decode(manifestUpload.bodyBytes)) as Map,
      ),
    );
    expect(manifest.latestSnapshotPath, contains('device-local'));
    expect(manifest.latestSnapshotPath, isNot(legacySnapshotPath));
    expect(manifest.deviceSequences, {
      'remote-device': 9,
      'device-local': 1,
    });
    expect(manifest.updatedAtUtc.isAfter(remoteUpdatedAtUtc), true);
    final stored = await store.load();
    expect(stored.papers.single.id, 'paper-remote');
    expect(stored.papers.single.title, 'Remote');
    expect(stored.papers.single.content, 'Plain remote body');
    expect(stored.sync.operationDeviceSequences, {
      'remote-device': 9,
      'device-local': 1,
    });
  });

  test('keeps local WebDAV settings when saving downloaded snapshots',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_download_keep_sync_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final localSync = _configuredSyncSettings();
    localSync.markPaperDeleted(
      'local-deleted',
      DateTime.utc(2026, 7, 1, 9),
    );
    final remoteSync = SyncSettings(
      enabled: false,
      provider: SyncProviderIds.none,
      webDav: WebDavSyncSettings(),
      operationDeviceSequences: {'snapshot-device': 3},
      deletedPaperTombstones: {
        'remote-deleted': DateTime.utc(2026, 7, 1, 10).toIso8601String(),
      },
    );
    final remoteState = AppState(
      papers: [
        PaperData(id: 'paper-remote', type: PaperTypes.note, title: 'Remote'),
      ],
      sync: remoteSync,
    );
    final originalRemoteStateJson = remoteState.toJson();
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
            snapshotPath: 'repapertodo/snapshots/remote.json',
            manifest: SyncManifest(
              schemaVersion: 1,
              updatedAtUtc: DateTime.utc(2026, 7, 1, 11),
              latestSnapshotPath: 'repapertodo/snapshots/remote.json',
              deviceSequences: {'manifest-device': 8},
            ),
          );
        },
      ),
    );

    final result = await service.syncNow(
      localState: AppState(
        sync: localSync
          ..operationDeviceSequences = {
            'local-device': 5,
            'manifest-device': 6,
          },
      ),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7, 1),
    );

    expect(result.status, AppSyncStatus.downloaded);
    expect(remoteState.toJson(), originalRemoteStateJson);
    final stored = await store.load();
    expect(stored.papers.single.title, 'Remote');
    expect(stored.sync.enabled, true);
    expect(stored.sync.provider, SyncProviderIds.webDav);
    expect(stored.sync.webDav.endpoint, 'https://dav.example.test/');
    expect(stored.sync.webDav.username, 'user');
    expect(stored.sync.webDav.password, 'pass');
    expect(stored.sync.webDav.requestTimeoutSeconds, 45);
    expect(stored.sync.operationDeviceSequences, {
      'local-device': 5,
      'manifest-device': 8,
      'snapshot-device': 3,
    });
    expect(stored.sync.isPaperDeleted('local-deleted'), true);
    expect(stored.sync.isPaperDeleted('remote-deleted'), true);
  });

  test('closes configured WebDAV clients after sync and merge', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_close_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var createdCount = 0;
    var closedCount = 0;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) {
        createdCount += 1;
        return _FakeWebDavStateSyncService(
          onSync: ({required localState, localUpdatedAtUtc}) async {
            return const WebDavStateSyncResult(
              status: WebDavStateSyncStatus.uploaded,
              snapshotPath: 'repapertodo/snapshots/local.json',
            );
          },
          onListOperationLogs: () async => const [],
          onClose: () => closedCount += 1,
        );
      },
    );

    final result = await service.syncAndMergeNow(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.syncResult.status, AppSyncStatus.uploaded);
    expect(createdCount, 2);
    expect(closedCount, 2);
  });

  test('closes configured WebDAV client when sync fails', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_close_error_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var closedCount = 0;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) {
        return _FakeWebDavStateSyncService(
          onSync: ({required localState, localUpdatedAtUtc}) async {
            throw StateError('network failed');
          },
          onClose: () => closedCount += 1,
        );
      },
    );

    await expectLater(
      service.syncNow(
        localState: AppState(sync: _configuredSyncSettings()),
        store: store,
        localUpdatedAtUtc: DateTime.utc(2026, 7),
      ),
      throwsA(isA<StateError>()),
    );

    expect(closedCount, 1);
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

  test('reports unreadable remote payloads without saving local state',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_unreadable_payload_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          throw const WebDavPayloadDecryptionException(
            'Unable to decrypt WebDAV sync payload. Check the sync encryption passphrase.',
          );
        },
      ),
    );
    final localState = AppState(
      papers: [
        PaperData(id: 'local', type: PaperTypes.note, title: 'Local'),
      ],
      sync: _configuredSyncSettings(),
    );

    final result = await service.syncNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, AppSyncStatus.payloadUnreadable);
    expect(result.message, contains('sync encryption passphrase'));
    expect(await File(store.filePath).exists(), isFalse);
  });

  test('reports malformed remote sync data without saving local state',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_malformed_remote_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var closed = false;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          throw const FormatException(
            'Remote sync manifest is not valid JSON.',
          );
        },
        onClose: () {
          closed = true;
        },
      ),
    );
    final localState = AppState(
      papers: [
        PaperData(id: 'local', type: PaperTypes.note, title: 'Local'),
      ],
      sync: _configuredSyncSettings(),
    );

    final result = await service.syncNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, AppSyncStatus.payloadUnreadable);
    expect(result.message, 'Remote sync manifest is not valid JSON.');
    expect(await File(store.filePath).exists(), isFalse);
    expect(closed, isTrue);
  });

  test('reports unsafe remote snapshot paths without saving local state',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_unsafe_remote_snapshot_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var closed = false;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          throw const WebDavSyncConfigurationException(
            'Snapshot path must be inside repapertodo/snapshots.',
          );
        },
        onClose: () {
          closed = true;
        },
      ),
    );
    final localState = AppState(
      papers: [
        PaperData(id: 'local', type: PaperTypes.note, title: 'Local'),
      ],
      sync: _configuredSyncSettings(),
    );

    final result = await service.syncNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, AppSyncStatus.payloadUnreadable);
    expect(result.message, contains('repapertodo/snapshots'));
    expect(await File(store.filePath).exists(), isFalse);
    expect(closed, isTrue);
  });

  test('syncAndMergeNow applies remote operations after sync succeeds',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_and_merge_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return const WebDavStateSyncResult(
            status: WebDavStateSyncStatus.uploaded,
            snapshotPath: 'repapertodo/snapshots/local.json',
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
              kind: SyncOperationKind.upsertPaper,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9),
              payload: {
                'paper': PaperData(
                  id: 'remote-note',
                  type: PaperTypes.note,
                  title: 'Merged',
                ).toJson(),
              },
            ),
          ];
        },
      ),
    );

    final result = await service.syncAndMergeNow(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.syncResult.status, AppSyncStatus.uploaded);
    expect(result.operationAppliedCount, 1);
    expect(result.state.papers.single.title, 'Merged');
    expect((await store.load()).papers.single.title, 'Merged');
  });

  test('syncAndMergeNow reports unreadable operation logs without merging',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_unreadable_payload_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final localState = AppState(
      sync: _configuredSyncSettings(),
      papers: [
        PaperData(id: 'local', type: PaperTypes.note, title: 'Local'),
      ],
    );
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return const WebDavStateSyncResult(
            status: WebDavStateSyncStatus.uploaded,
            snapshotPath: 'repapertodo/snapshots/local.json',
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
          throw const WebDavPayloadDecryptionException(
            'Unable to decrypt WebDAV sync payload. Check the sync encryption passphrase.',
          );
        },
      ),
    );

    final result = await service.syncAndMergeNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.syncResult.status, AppSyncStatus.payloadUnreadable);
    expect(result.syncResult.message, contains('sync encryption passphrase'));
    expect(result.operationMergeResult, isNull);
    expect(result.state.papers.single.title, 'Local');
    expect((await store.load()).papers.single.title, 'Local');
  });

  test('syncAndMergeNow reports malformed operation logs without merging',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_malformed_operation_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final localState = AppState(
      sync: _configuredSyncSettings(),
      papers: [
        PaperData(id: 'local', type: PaperTypes.note, title: 'Local'),
      ],
    );
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return const WebDavStateSyncResult(
            status: WebDavStateSyncStatus.uploaded,
            snapshotPath: 'repapertodo/snapshots/local.json',
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
          throw const FormatException('Operation log is not valid JSON.');
        },
      ),
    );

    final result = await service.syncAndMergeNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.syncResult.status, AppSyncStatus.payloadUnreadable);
    expect(result.syncResult.message, 'Operation log is not valid JSON.');
    expect(result.operationMergeResult, isNull);
    expect(result.state.papers.single.title, 'Local');
    expect((await store.load()).papers.single.title, 'Local');
  });

  test('syncAndMergeNow skips remote operations after sync conflict', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_and_merge_conflict_');
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
        onListOperationLogs: () async {
          throw StateError('Conflicted sync should not merge operations.');
        },
      ),
    );
    final localState = AppState(
      papers: [
        PaperData(id: 'local', type: PaperTypes.todo, title: 'Local'),
      ],
      sync: _configuredSyncSettings(),
    );

    final result = await service.syncAndMergeNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.syncResult.status, AppSyncStatus.conflict);
    expect(result.operationMergeResult, isNull);
    expect(result.state.papers.single.title, 'Local');
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

  test('lists operation logs through configured WebDAV', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_ops_');
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
          onListOperationLogs: () async {
            return [
              WebDavOperationLogRecord(
                path: 'repapertodo/ops/$forwardedDeviceId-000000000001.jsonl',
                deviceId: forwardedDeviceId,
                sequence: 1,
              ),
            ];
          },
        );
      },
    );

    final logs = await service.listRemoteOperationLogs(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
    );

    expect(logs, hasLength(1));
    expect(logs.single.deviceId, startsWith('device-'));
    expect(logs.single.sequence, 1);
    expect(forwardedDeviceId, logs.single.deviceId);
  });

  test('downloads operation logs through configured WebDAV', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_download_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onDownloadOperationLog: (operationLogPath) async {
          return [
            SyncOperation(
              id: 'device-1',
              deviceId: deviceId ?? '',
              sequence: 1,
              kind: SyncOperationKind.stateSnapshot,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9),
              payload: {'path': operationLogPath},
            ),
          ];
        },
      ),
    );

    final operations = await service.downloadRemoteOperationLog(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      operationLogPath: 'repapertodo/ops/device-000000000001.jsonl',
    );

    expect(operations, hasLength(1));
    expect(operations.single.kind, SyncOperationKind.stateSnapshot);
    expect(operations.single.payload['path'],
        'repapertodo/ops/device-000000000001.jsonl');
  });

  test('merges remote operation logs and saves applied state', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_merge_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000001.jsonl',
              deviceId: 'device-a',
              sequence: 1,
            ),
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000002.jsonl',
              deviceId: 'device-a',
              sequence: 2,
            ),
          ];
        },
        onDownloadOperationLog: (operationLogPath) async {
          if (operationLogPath.endsWith('000000000001.jsonl')) {
            return [
              SyncOperation(
                id: 'device-a-1',
                deviceId: 'device-a',
                sequence: 1,
                kind: SyncOperationKind.upsertPaper,
                createdAtUtc: DateTime.utc(2026, 7, 1, 9),
                payload: {
                  'paper': PaperData(
                    id: 'remote-note',
                    type: PaperTypes.note,
                    title: 'Remote',
                    content: 'Old',
                  ).toJson(),
                },
              ),
            ];
          }
          return [
            SyncOperation(
              id: 'device-a-2',
              deviceId: 'device-a',
              sequence: 2,
              kind: SyncOperationKind.updateNoteContent,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9, 1),
              payload: {
                'paperId': 'remote-note',
                'content': 'Merged body',
              },
            ),
          ];
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
    );

    expect(result.appliedCount, 2);
    expect(result.deviceSequences, {'device-a': 2});
    expect(result.state.sync.operationDeviceSequences, {'device-a': 2});
    expect(result.state.papers.single.title, 'Remote');
    expect(result.state.papers.single.content, 'Merged body');
    final stored = await store.load();
    expect(stored.papers.single.content, 'Merged body');
    expect(stored.sync.operationDeviceSequences, {'device-a': 2});
  });

  test('merges legacy-cased WebDAV operation log wire payloads', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_legacy_wire_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    const plainCodec = PlainWebDavPayloadCodec();
    final migratedPaths = <String>[];
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/legacy-device-000000000001.jsonl',
              deviceId: 'legacy-device',
              sequence: 1,
            ),
          ];
        },
        onDownloadOperationLogWithMetadata: (operationLogPath) async {
          final legacyOperationLogBytes = utf8.encode('''
{"ID":"legacy-device-1","DEVICEID":"legacy-device","SEQUENCE":"1","KIND":"UPSERTPAPER","CREATEDATUTC":"2026-07-01T09:00:00Z","PAYLOAD":{"PAPER":{"Id":"legacy-note","Type":"note","Title":"Legacy WebDAV","Content":"Decoded from old wire casing"}}}
''');
          return WebDavOperationLogDownloadResult(
            path: operationLogPath,
            payloadFormat: WebDavPayloadFormat.plainJson,
            operations: plainCodec.decodeOperationLog(legacyOperationLogBytes),
          );
        },
        onMigrateLegacyPlainOperationLog: (
          record, {
          downloadedResult,
        }) async {
          migratedPaths.add(record.path);
          expect(downloadedResult?.path, record.path);
          return false;
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
    );

    expect(result.appliedCount, 1);
    expect(result.legacyPlainOperationLogCount, 1);
    expect(result.legacyPlainOperationLogMigratedCount, 0);
    expect(result.deviceSequences, {'legacy-device': 1});
    expect(migratedPaths, [
      'repapertodo/ops/legacy-device-000000000001.jsonl',
    ]);
    expect(result.state.papers.single.id, 'legacy-note');
    expect(result.state.papers.single.title, 'Legacy WebDAV');
    expect(result.state.papers.single.content, 'Decoded from old wire casing');
    final stored = await store.load();
    expect(stored.papers.single.content, 'Decoded from old wire casing');
    expect(stored.sync.operationDeviceSequences, {'legacy-device': 1});
  });

  test('merge reports and migrates legacy plain operation log payloads',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_legacy_plain_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final migratedPaths = <String>[];
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000001.jsonl',
              deviceId: 'device-a',
              sequence: 1,
              etag: 'op-v1',
            ),
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000002.jsonl',
              deviceId: 'device-a',
              sequence: 2,
            ),
          ];
        },
        onDownloadOperationLogWithMetadata: (operationLogPath) async {
          if (operationLogPath.endsWith('000000000001.jsonl')) {
            return WebDavOperationLogDownloadResult(
              path: operationLogPath,
              payloadFormat: WebDavPayloadFormat.plainJson,
              operations: [
                SyncOperation(
                  id: 'device-a-1',
                  deviceId: 'device-a',
                  sequence: 1,
                  kind: SyncOperationKind.upsertPaper,
                  createdAtUtc: DateTime.utc(2026, 7, 1, 9),
                  payload: {
                    'paper': PaperData(
                      id: 'remote-note',
                      type: PaperTypes.note,
                      title: 'Remote',
                      content: 'Plain op 1',
                    ).toJson(),
                  },
                ),
              ],
            );
          }
          return WebDavOperationLogDownloadResult(
            path: operationLogPath,
            payloadFormat: WebDavPayloadFormat.plainJson,
            operations: [
              SyncOperation(
                id: 'device-a-2',
                deviceId: 'device-a',
                sequence: 2,
                kind: SyncOperationKind.updateNoteContent,
                createdAtUtc: DateTime.utc(2026, 7, 1, 9, 1),
                payload: {
                  'paperId': 'remote-note',
                  'content': 'Plain op 2',
                },
              ),
            ],
          );
        },
        onMigrateLegacyPlainOperationLog: (
          record, {
          downloadedResult,
        }) async {
          migratedPaths.add(record.path);
          expect(downloadedResult?.path, record.path);
          return record.etag != null;
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(
        sync: _configuredSyncSettings(
          encryptionPassphrase: 'shared sync secret',
        ),
      ),
      store: store,
    );

    expect(result.appliedCount, 2);
    expect(result.legacyPlainOperationLogCount, 2);
    expect(result.legacyPlainOperationLogMigratedCount, 1);
    expect(migratedPaths, [
      'repapertodo/ops/device-a-000000000001.jsonl',
      'repapertodo/ops/device-a-000000000002.jsonl',
    ]);
    expect(result.state.papers.single.content, 'Plain op 2');
    expect((await store.load()).papers.single.content, 'Plain op 2');
  });

  test('merge waits at gaps in remote operation sequences', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_gap_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final downloadedPaths = <String>[];
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000003.jsonl',
              deviceId: 'device-a',
              sequence: 3,
            ),
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000001.jsonl',
              deviceId: 'device-a',
              sequence: 1,
            ),
          ];
        },
        onDownloadOperationLog: (operationLogPath) async {
          downloadedPaths.add(operationLogPath);
          if (operationLogPath.endsWith('000000000003.jsonl')) {
            throw StateError('Gapped operation logs should not be downloaded.');
          }
          return [
            SyncOperation(
              id: 'device-a-1',
              deviceId: 'device-a',
              sequence: 1,
              kind: SyncOperationKind.upsertPaper,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9),
              payload: {
                'paper': PaperData(
                  id: 'remote-note',
                  type: PaperTypes.note,
                  title: 'First',
                ).toJson(),
              },
            ),
          ];
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.sync.operationDeviceSequences, {'device-a': 1});
    expect(result.state.papers.single.title, 'First');
    expect(downloadedPaths, ['repapertodo/ops/device-a-000000000001.jsonl']);
    final stored = await store.load();
    expect(stored.sync.operationDeviceSequences, {'device-a': 1});
    expect(stored.papers.single.title, 'First');
  });

  test('uploads local operation diffs and saves sequence progress', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_upload_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(p.join(directory.path, 'sync-device-id'))
        .writeAsString(' Device Local ');
    final beforeState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {' Device Local ': 4},
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'Before',
        ),
      ],
    );
    final afterState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {' Device Local ': 4},
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'After',
        ),
      ],
    );
    var forwardedDeviceId = '';
    WebDavSyncSettings? forwardedSettings;
    Map<String, int>? previousSequences;
    final uploadedOperations = <SyncOperation>[];
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (settings, {deviceId}) {
        forwardedSettings = settings;
        forwardedDeviceId = deviceId ?? '';
        return _FakeWebDavStateSyncService(
          onUploadOperationLogs: (
            operations, {
            previousDeviceSequences,
          }) async {
            previousSequences = previousDeviceSequences;
            uploadedOperations.addAll(operations);
            return WebDavOperationLogUploadResult(
              deviceSequences: {
                ...?previousDeviceSequences,
                forwardedDeviceId: operations.last.sequence,
              },
              uploadedCount: operations.length,
            );
          },
        );
      },
    );

    final result = await service.uploadLocalOperations(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(forwardedDeviceId, 'device-local');
    expect(forwardedSettings?.requestTimeoutSeconds, 45);
    expect(previousSequences, {'device-local': 4});
    expect(uploadedOperations, hasLength(1));
    expect(uploadedOperations.single.id, 'device-local-5');
    expect(uploadedOperations.single.deviceId, 'device-local');
    expect(uploadedOperations.single.sequence, 5);
    expect(uploadedOperations.single.kind, SyncOperationKind.updateNoteContent);
    expect(uploadedOperations.single.payload, {
      'paperId': 'note',
      'content': 'After',
    });
    expect(result.generatedCount, 1);
    expect(result.uploadedCount, 1);
    expect(result.stateChanged, true);
    expect(result.deviceSequences, {'device-local': 5});
    expect(result.state.sync.operationDeviceSequences, {'device-local': 5});
    expect((await store.load()).sync.operationDeviceSequences, {
      'device-local': 5,
    });
  });

  test('saves advanced device sequences when operation uploads are idempotent',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_upload_ops_idempotent_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(p.join(directory.path, 'sync-device-id'))
        .writeAsString('device-local');
    final beforeState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 4},
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'Before',
        ),
      ],
    );
    final afterState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 4},
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'After',
        ),
      ],
    );
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        return _FakeWebDavStateSyncService(
          onUploadOperationLogs: (
            operations, {
            previousDeviceSequences,
          }) async {
            expect(operations, hasLength(1));
            expect(operations.single.kind, SyncOperationKind.updateNoteContent);
            return WebDavOperationLogUploadResult(
              deviceSequences: {
                ...?previousDeviceSequences,
                deviceId ?? '': operations.single.sequence,
              },
              uploadedCount: 0,
            );
          },
        );
      },
    );

    final result = await service.uploadLocalOperations(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(result.generatedCount, 1);
    expect(result.uploadedCount, 0);
    expect(result.stateChanged, true);
    expect(result.deviceSequences, {'device-local': 5});
    expect(result.state.sync.operationDeviceSequences, {'device-local': 5});
    expect((await store.load()).sync.operationDeviceSequences, {
      'device-local': 5,
    });
  });

  test('does not infer device sequence progress from uploaded count alone',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_upload_ops_count_only_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(p.join(directory.path, 'sync-device-id'))
        .writeAsString('device-local');
    final beforeState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 4},
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'Before',
        ),
      ],
    );
    final afterState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 4},
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'After',
        ),
      ],
    );
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        return _FakeWebDavStateSyncService(
          onUploadOperationLogs: (
            operations, {
            previousDeviceSequences,
          }) async {
            expect(operations, hasLength(1));
            expect(operations.single.sequence, 5);
            return WebDavOperationLogUploadResult(
              deviceSequences: previousDeviceSequences ?? const {},
              uploadedCount: 1,
            );
          },
        );
      },
    );

    final result = await service.uploadLocalOperations(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(result.generatedCount, 1);
    expect(result.uploadedCount, 1);
    expect(result.stateChanged, true);
    expect(result.deviceSequences, {'device-local': 4});
    expect(result.state.sync.operationDeviceSequences, {'device-local': 4});
    expect((await store.load()).sync.operationDeviceSequences, {
      'device-local': 4,
    });
  });

  test('does not regress device sequences from operation upload results',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_upload_ops_no_regress_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(p.join(directory.path, 'sync-device-id'))
        .writeAsString('device-local');
    final beforeState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {
          'device-local': 4,
          'remote-device': 2,
        },
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'Before',
        ),
      ],
    );
    final afterState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {
          'device-local': 4,
          'remote-device': 2,
        },
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'After',
        ),
      ],
    );
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        return _FakeWebDavStateSyncService(
          onUploadOperationLogs: (
            operations, {
            previousDeviceSequences,
          }) async {
            expect(operations, hasLength(1));
            expect(operations.single.sequence, 5);
            return const WebDavOperationLogUploadResult(
              deviceSequences: {
                'device-local': 3,
                'remote-device': 1,
              },
              uploadedCount: 1,
              acceptedDeviceSequences: {
                'device-local': 5,
              },
            );
          },
        );
      },
    );

    final result = await service.uploadLocalOperations(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(result.uploadedCount, 1);
    expect(result.stateChanged, true);
    expect(result.deviceSequences, {
      'device-local': 5,
      'remote-device': 2,
    });
    expect((await store.load()).sync.operationDeviceSequences, {
      'device-local': 5,
      'remote-device': 2,
    });
  });

  test('uploads local delete diffs and saves tombstones', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_upload_delete_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(p.join(directory.path, 'sync-device-id'))
        .writeAsString('device-local');
    final beforeState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 8},
      papers: [
        PaperData(
          id: 'old-note',
          type: PaperTypes.note,
          title: 'Remove',
        ),
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'item-1', text: 'Remove item'),
            PaperItem(id: 'item-2', text: 'Keep item'),
          ],
        ),
      ],
    );
    final afterState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 8},
      papers: [
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'item-2', text: 'Keep item'),
          ],
        ),
      ],
    );
    final uploadedOperations = <SyncOperation>[];
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        return _FakeWebDavStateSyncService(
          onUploadOperationLogs: (
            operations, {
            previousDeviceSequences,
          }) async {
            uploadedOperations.addAll(operations);
            return WebDavOperationLogUploadResult(
              deviceSequences: {
                ...?previousDeviceSequences,
                deviceId ?? '': operations.last.sequence,
              },
              uploadedCount: operations.length,
            );
          },
        );
      },
    );

    final result = await service.uploadLocalOperations(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: DateTime.utc(2026, 7, 1, 12),
    );

    expect(
      uploadedOperations.map((operation) => operation.kind),
      [
        SyncOperationKind.deletePaper,
        SyncOperationKind.deleteTodoItem,
        SyncOperationKind.upsertTodoItem,
      ],
    );
    expect(result.generatedCount, 3);
    expect(result.uploadedCount, 3);
    expect(result.stateChanged, true);
    expect(result.state.sync.operationDeviceSequences, {'device-local': 11});
    expect(result.state.sync.deletedPaperTombstones['old-note'],
        DateTime.utc(2026, 7, 1, 12).toIso8601String());
    expect(result.state.sync.deletedTodoItemTombstones['todo']?['item-1'],
        DateTime.utc(2026, 7, 1, 12).toIso8601String());

    final stored = await store.load();
    expect(stored.sync.deletedPaperTombstones.containsKey('old-note'), true);
    expect(
      stored.sync.deletedTodoItemTombstones['todo']?.containsKey('item-1'),
      true,
    );
  });

  test('keeps pending local upload states unchanged when WebDAV upload fails',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_upload_delete_failure_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(p.join(directory.path, 'sync-device-id'))
        .writeAsString('device-local');
    final beforeState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 8},
      papers: [
        PaperData(id: 'old-note', type: PaperTypes.note, title: 'Remove'),
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'item-1', text: 'Remove item'),
            PaperItem(id: 'item-2', text: 'Keep item'),
          ],
        ),
      ],
    );
    final afterState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 8},
      papers: [
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'item-2', text: 'Keep item'),
          ],
        ),
      ],
    );
    final originalBeforeStateJson = beforeState.toJson();
    final originalAfterStateJson = afterState.toJson();
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        return _FakeWebDavStateSyncService(
          onUploadOperationLogs: (
            operations, {
            previousDeviceSequences,
          }) async {
            expect(operations.map((operation) => operation.kind), [
              SyncOperationKind.deletePaper,
              SyncOperationKind.deleteTodoItem,
              SyncOperationKind.upsertTodoItem,
            ]);
            throw const WebDavException(
              'WebDAV request failed: offline',
              statusCode: 0,
            );
          },
        );
      },
    );

    await expectLater(
      service.uploadLocalOperations(
        beforeState: beforeState,
        afterState: afterState,
        store: store,
        createdAtUtc: DateTime.utc(2026, 7, 1, 12),
      ),
      throwsA(isA<WebDavException>()),
    );

    expect(beforeState.toJson(), originalBeforeStateJson);
    expect(afterState.toJson(), originalAfterStateJson);
    expect(await File(store.filePath).exists(), isFalse);
  });

  test('saves updated tombstones when delete operation uploads are idempotent',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_upload_delete_idempotent_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(p.join(directory.path, 'sync-device-id'))
        .writeAsString('device-local');
    final oldDeletedAt = DateTime.utc(2026, 7, 1, 9);
    final newDeletedAt = DateTime.utc(2026, 7, 1, 12);
    final beforeState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 8},
      papers: [
        PaperData(
          id: 'old-note',
          type: PaperTypes.note,
          title: 'Remove',
        ),
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'item-1', text: 'Remove item'),
            PaperItem(id: 'item-2', text: 'Keep item'),
          ],
        ),
      ],
    );
    final afterState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 8}
        ..deletedPaperTombstones = {
          'old-note': oldDeletedAt.toIso8601String(),
        }
        ..deletedTodoItemTombstones = {
          'todo': {'item-1': oldDeletedAt.toIso8601String()},
        },
      papers: [
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'item-2', text: 'Keep item'),
          ],
        ),
      ],
    );
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        return _FakeWebDavStateSyncService(
          onUploadOperationLogs: (
            operations, {
            previousDeviceSequences,
          }) async {
            expect(operations.map((operation) => operation.kind), [
              SyncOperationKind.deletePaper,
              SyncOperationKind.deleteTodoItem,
              SyncOperationKind.upsertTodoItem,
            ]);
            return WebDavOperationLogUploadResult(
              deviceSequences: previousDeviceSequences ?? const {},
              uploadedCount: 0,
            );
          },
        );
      },
    );

    final result = await service.uploadLocalOperations(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: newDeletedAt,
    );

    expect(result.uploadedCount, 0);
    expect(result.stateChanged, true);
    expect(result.state.sync.deletedPaperTombstones['old-note'],
        newDeletedAt.toIso8601String());
    expect(result.state.sync.deletedTodoItemTombstones['todo']?['item-1'],
        newDeletedAt.toIso8601String());

    final stored = await store.load();
    expect(stored.sync.deletedPaperTombstones['old-note'],
        newDeletedAt.toIso8601String());
    expect(stored.sync.deletedTodoItemTombstones['todo']?['item-1'],
        newDeletedAt.toIso8601String());
  });

  test('merge skips operation logs covered by explicit device sequences',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_skip_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
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
          throw StateError('Covered operation logs should not be downloaded.');
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(
        papers: [
          PaperData(id: 'local', type: PaperTypes.todo, title: 'Local'),
        ],
        sync: _configuredSyncSettings(),
      ),
      store: store,
      deviceSequences: {' Device A ': 1},
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.papers.single.title, 'Local');
    expect(await File(store.filePath).exists(), isFalse);
  });

  test('merge skips operation logs covered by stored device sequences',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_stored_skip_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
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
          throw StateError('Covered operation logs should not be downloaded.');
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(
        papers: [
          PaperData(id: 'local', type: PaperTypes.todo, title: 'Local'),
        ],
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
          operationDeviceSequences: {' Device A ': 1},
        ),
      ),
      store: store,
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.papers.single.title, 'Local');
    expect(await File(store.filePath).exists(), isFalse);
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
      sync: SyncSettings(
        enabled: false,
        provider: SyncProviderIds.none,
        webDav: WebDavSyncSettings(
          endpoint: 'https://remote.example.test/',
          username: 'remote-user',
          password: 'remote-password',
          rootPath: 'RemoteRoot',
        ),
      ),
    );
    final originalSnapshotStateJson = snapshotState.toJson();
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
    expect(snapshotState.toJson(), originalSnapshotStateJson);
    final stored = await store.load();
    expect(stored.papers.single.title, 'Snap');
    expect(stored.sync.enabled, true);
    expect(stored.sync.provider, SyncProviderIds.webDav);
    expect(stored.sync.webDav.endpoint, 'https://dav.example.test/');
    expect(stored.sync.webDav.username, 'user');
    expect(stored.sync.webDav.password, 'pass');
    expect(stored.sync.webDav.encryptionPassphrase, 'shared sync secret');
    expect(stored.sync.webDav.requestTimeoutSeconds, 45);
  });

  test('reports unreadable recovery snapshots without replacing local state',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_restore_unreadable_payload_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final localState = AppState(
      sync: _configuredSyncSettings(),
      papers: [
        PaperData(id: 'local', type: PaperTypes.note, title: 'Local'),
      ],
    );
    await store.save(localState);
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onDownloadSnapshot: (snapshotPath) async {
          throw const WebDavPayloadDecryptionException(
            'Unable to decrypt WebDAV sync payload. Check the sync encryption passphrase.',
          );
        },
      ),
    );

    final result = await service.restoreRecoverySnapshot(
      localState: localState,
      store: store,
      snapshotPath: 'repapertodo/snapshots/snapshot.json',
    );

    expect(result.status, AppSyncStatus.payloadUnreadable);
    expect(result.message, contains('sync encryption passphrase'));
    expect((await store.load()).papers.single.title, 'Local');
  });

  test('reports malformed recovery snapshots without replacing local state',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_restore_malformed_payload_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final localState = AppState(
      sync: _configuredSyncSettings(),
      papers: [
        PaperData(id: 'local', type: PaperTypes.note, title: 'Local'),
      ],
    );
    await store.save(localState);
    var closed = false;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onDownloadSnapshot: (snapshotPath) async {
          throw const FormatException('Snapshot payload is not valid JSON.');
        },
        onClose: () {
          closed = true;
        },
      ),
    );

    final result = await service.restoreRecoverySnapshot(
      localState: localState,
      store: store,
      snapshotPath: 'repapertodo/snapshots/snapshot.json',
    );

    expect(result.status, AppSyncStatus.payloadUnreadable);
    expect(result.message, 'Snapshot payload is not valid JSON.');
    expect((await store.load()).papers.single.title, 'Local');
    expect(closed, isTrue);
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

  test('skips WebDAV helper entrypoints for unsafe sync settings', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_unsafe_helpers_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var createdCount = 0;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) {
        createdCount += 1;
        throw StateError('WebDAV should not be created');
      },
    );
    AppState unsafeState({
      required SyncSettings sync,
      String title = 'Local',
    }) {
      return AppState(
        sync: sync,
        papers: [
          PaperData(id: 'local-note', type: PaperTypes.note, title: title),
        ],
      );
    }

    for (final syncSettings in [
      _configuredSyncSettings(
        endpoint: 'https://dav.example.test/dav/%0Afiles',
      ),
      _configuredSyncSettings(rootPath: 'repapertodo/%0Aother'),
    ]) {
      final localState = unsafeState(sync: syncSettings);
      final editedState = unsafeState(sync: syncSettings, title: 'Edited');
      final originalLocalStateJson = localState.toJson();
      final originalEditedStateJson = editedState.toJson();
      final snapshots = await service.listRecoverySnapshots(
        localState: localState,
        store: store,
      );
      final logs = await service.listRemoteOperationLogs(
        localState: localState,
        store: store,
      );
      final operations = await service.downloadRemoteOperationLog(
        localState: localState,
        store: store,
        operationLogPath: 'repapertodo/ops/device-000000000001.jsonl',
      );
      final mergeResult = await service.mergeRemoteOperations(
        localState: localState,
        store: store,
      );
      final uploadResult = await service.uploadLocalOperations(
        beforeState: localState,
        afterState: editedState,
        store: store,
      );
      final restoreResult = await service.restoreRecoverySnapshot(
        localState: localState,
        store: store,
        snapshotPath: 'repapertodo/snapshots/snapshot.json',
      );

      expect(snapshots, isEmpty);
      expect(logs, isEmpty);
      expect(operations, isEmpty);
      expect(mergeResult.appliedCount, 0);
      expect(uploadResult.generatedCount, 0);
      expect(uploadResult.uploadedCount, 0);
      expect(restoreResult.status, AppSyncStatus.configurationMissing);
      expect(localState.toJson(), originalLocalStateJson);
      expect(editedState.toJson(), originalEditedStateJson);
    }
    expect(createdCount, 0);
  });

  test('returns no operation logs when sync is disabled', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_no_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) =>
          throw StateError('WebDAV should not be created'),
    );

    final logs = await service.listRemoteOperationLogs(
      localState: AppState(),
      store: store,
    );
    final operations = await service.downloadRemoteOperationLog(
      localState: AppState(),
      store: store,
      operationLogPath: 'repapertodo/ops/device-000000000001.jsonl',
    );

    expect(logs, isEmpty);
    expect(operations, isEmpty);
  });
}

SyncSettings _configuredSyncSettings({
  String endpoint = 'https://dav.example.test/',
  String username = 'user',
  String password = 'pass',
  String encryptionPassphrase = 'shared sync secret',
  String rootPath = 'repapertodo',
  int requestTimeoutSeconds = 45,
}) {
  return SyncSettings(
    enabled: true,
    provider: SyncProviderIds.webDav,
    webDav: WebDavSyncSettings(
      endpoint: endpoint,
      username: username,
      password: password,
      encryptionPassphrase: encryptionPassphrase,
      rootPath: rootPath,
      requestTimeoutSeconds: requestTimeoutSeconds,
    ),
  );
}

String _legacyPaperTodoSnapshotJson({
  required String id,
  required String title,
  required String content,
}) {
  return '''
{
  "Theme": "dark",
  "Papers": [
    {
      "Id": "$id",
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

typedef _FakePush = Future<WebDavStateSyncResult> Function(
  AppState state, {
  DateTime? updatedAtUtc,
  String? expectedManifestEtag,
  bool manifestKnownMissing,
  Map<String, int>? previousDeviceSequences,
});

typedef _FakeListSnapshots = Future<List<WebDavSnapshotRecord>> Function();

typedef _FakeListOperationLogs = Future<List<WebDavOperationLogRecord>>
    Function();

typedef _FakeDownloadSnapshot = Future<WebDavStateSyncResult> Function(
  String snapshotPath,
);

typedef _FakeDownloadOperationLog = Future<List<SyncOperation>> Function(
  String operationLogPath,
);

typedef _FakeDownloadOperationLogWithMetadata
    = Future<WebDavOperationLogDownloadResult> Function(
  String operationLogPath,
);

typedef _FakeMigrateLegacyPlainOperationLog = Future<bool> Function(
  WebDavOperationLogRecord record, {
  WebDavOperationLogDownloadResult? downloadedResult,
});

typedef _FakeUploadOperationLogs = Future<WebDavOperationLogUploadResult>
    Function(
  Iterable<SyncOperation> operations, {
  Map<String, int>? previousDeviceSequences,
});

typedef _FakeClose = void Function();

class _FakeWebDavStateSyncService extends WebDavStateSyncService {
  _FakeWebDavStateSyncService({
    _FakeSync? onSync,
    _FakePush? onPush,
    _FakeListSnapshots? onListSnapshots,
    _FakeDownloadSnapshot? onDownloadSnapshot,
    _FakeListOperationLogs? onListOperationLogs,
    _FakeDownloadOperationLog? onDownloadOperationLog,
    _FakeDownloadOperationLogWithMetadata? onDownloadOperationLogWithMetadata,
    _FakeMigrateLegacyPlainOperationLog? onMigrateLegacyPlainOperationLog,
    _FakeUploadOperationLogs? onUploadOperationLogs,
    _FakeClose? onClose,
  })  : _onSync = onSync,
        _onPush = onPush,
        _onListSnapshots = onListSnapshots,
        _onDownloadSnapshot = onDownloadSnapshot,
        _onListOperationLogs = onListOperationLogs,
        _onDownloadOperationLog = onDownloadOperationLog,
        _onDownloadOperationLogWithMetadata =
            onDownloadOperationLogWithMetadata,
        _onMigrateLegacyPlainOperationLog = onMigrateLegacyPlainOperationLog,
        _onUploadOperationLogs = onUploadOperationLogs,
        _onClose = onClose,
        super(
          client: WebDavClient(
            baseUri: Uri.parse('https://unused.example.test/'),
            credentials:
                const WebDavCredentials(username: 'unused', password: 'unused'),
          ),
        );

  final _FakeSync? _onSync;
  final _FakePush? _onPush;
  final _FakeListSnapshots? _onListSnapshots;
  final _FakeDownloadSnapshot? _onDownloadSnapshot;
  final _FakeListOperationLogs? _onListOperationLogs;
  final _FakeDownloadOperationLog? _onDownloadOperationLog;
  final _FakeDownloadOperationLogWithMetadata?
      _onDownloadOperationLogWithMetadata;
  final _FakeMigrateLegacyPlainOperationLog? _onMigrateLegacyPlainOperationLog;
  final _FakeUploadOperationLogs? _onUploadOperationLogs;
  final _FakeClose? _onClose;

  @override
  void close() {
    _onClose?.call();
    super.close();
  }

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
  Future<WebDavStateSyncResult> push(
    AppState state, {
    DateTime? updatedAtUtc,
    String? expectedManifestEtag,
    bool manifestKnownMissing = false,
    Map<String, int>? previousDeviceSequences,
  }) {
    final onPush = _onPush;
    if (onPush == null) {
      throw StateError('Unexpected push call.');
    }
    return onPush(
      state,
      updatedAtUtc: updatedAtUtc,
      expectedManifestEtag: expectedManifestEtag,
      manifestKnownMissing: manifestKnownMissing,
      previousDeviceSequences: previousDeviceSequences,
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
  Future<List<WebDavOperationLogRecord>> listOperationLogs() {
    final onListOperationLogs = _onListOperationLogs;
    if (onListOperationLogs == null) {
      throw StateError('Unexpected listOperationLogs call.');
    }
    return onListOperationLogs();
  }

  @override
  Future<WebDavStateSyncResult> downloadSnapshot(String snapshotPath) {
    final onDownloadSnapshot = _onDownloadSnapshot;
    if (onDownloadSnapshot == null) {
      throw StateError('Unexpected downloadSnapshot call.');
    }
    return onDownloadSnapshot(snapshotPath);
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

  @override
  Future<bool> migrateLegacyPlainOperationLog(
    WebDavOperationLogRecord record, {
    WebDavOperationLogDownloadResult? downloadedResult,
  }) {
    final onMigrateLegacyPlainOperationLog = _onMigrateLegacyPlainOperationLog;
    if (onMigrateLegacyPlainOperationLog == null) {
      throw StateError('Unexpected migrateLegacyPlainOperationLog call.');
    }
    return onMigrateLegacyPlainOperationLog(
      record,
      downloadedResult: downloadedResult,
    );
  }

  @override
  Future<WebDavOperationLogUploadResult> uploadOperationLogs(
    Iterable<SyncOperation> operations, {
    Map<String, int>? previousDeviceSequences,
  }) {
    final onUploadOperationLogs = _onUploadOperationLogs;
    if (onUploadOperationLogs == null) {
      throw StateError('Unexpected uploadOperationLogs call.');
    }
    return onUploadOperationLogs(
      operations,
      previousDeviceSequences: previousDeviceSequences,
    );
  }
}
