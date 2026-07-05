import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('push uploads a state snapshot and manifest', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.push(
      AppState(
        papers: [
          PaperData(
            id: 'paper-1',
            type: PaperTypes.todo,
            title: 'Sync me',
          ),
        ],
      ),
      updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
    );

    expect(result.status, WebDavStateSyncStatus.uploaded);
    expect(
      requests.map((request) => request.method),
      ['MKCOL', 'MKCOL', 'MKCOL', 'PUT', 'PUT', 'PUT'],
    );

    final snapshotRequest = requests.firstWhere((request) =>
        request.method == 'PUT' &&
        request.url.path.endsWith(
            '/snapshots/snapshot-20260630T100000000Z-test-device-seq-000000000001.json'));
    expect(snapshotRequest.headers['if-none-match'], '*');
    final snapshot = jsonDecode(utf8.decode(snapshotRequest.bodyBytes))
        as Map<String, Object?>;
    final papers = snapshot['papers'] as List<Object?>;
    expect((papers.single as Map<String, Object?>)['title'], 'Sync me');

    final operationRequest = requests.firstWhere((request) =>
        request.method == 'PUT' &&
        request.url.path.endsWith('/ops/test-device-000000000001.jsonl'));
    expect(operationRequest.headers['if-none-match'], '*');
    final operation = jsonDecode(utf8.decode(operationRequest.bodyBytes).trim())
        as Map<String, Object?>;
    expect(operation['kind'], 'stateSnapshot');
    expect(operation['deviceId'], 'test-device');
    expect(operation['sequence'], 1);
    expect(operation['payload'], {
      'snapshotPath':
          'repapertodo/snapshots/snapshot-20260630T100000000Z-test-device-seq-000000000001.json',
      'paperCount': 1,
    });

    final manifestRequest = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.endsWith('/manifest.json'));
    final manifest = jsonDecode(utf8.decode(manifestRequest.bodyBytes))
        as Map<String, Object?>;
    expect(
      manifest['latestSnapshotPath'],
      'repapertodo/snapshots/snapshot-20260630T100000000Z-test-device-seq-000000000001.json',
    );
    expect(
      result.snapshotPath,
      'repapertodo/snapshots/snapshot-20260630T100000000Z-test-device-seq-000000000001.json',
    );
    expect(manifest['updatedAtUtc'], '2026-06-30T10:00:00.000Z');
    expect(manifest['deviceSequences'], {'test-device': 1});
  });

  test('redacts local WebDAV settings from uploaded snapshots', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );
    final pushedState = AppState(
      papers: [
        PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'Private sync'),
      ],
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings(
          endpoint: 'https://dav.example.test/dav/',
          username: 'private-user',
          password: 'private-password',
          encryptionPassphrase: 'private-sync-secret',
          rootPath: 'PrivateRoot',
          autoSyncIntervalMinutes: 99,
          requestTimeoutSeconds: 99,
        ),
        operationDeviceSequences: {'phone-device': 2},
      ),
    );
    pushedState.sync.markPaperDeleted(
      'deleted-paper',
      DateTime.utc(2026, 7, 1),
    );

    await service.push(
      pushedState,
      updatedAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    final snapshotRequest = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.contains('/snapshots/'));
    final snapshot = jsonDecode(utf8.decode(snapshotRequest.bodyBytes))
        as Map<String, Object?>;
    final sync = snapshot['sync'] as Map<String, Object?>;
    final snapshotWebDav = sync['webDav'] as Map<String, Object?>;

    expect(sync['enabled'], false);
    expect(sync['provider'], SyncProviderIds.none);
    expect(sync['operationDeviceSequences'], {'phone-device': 2});
    expect(sync['deletedPaperTombstones'], {
      'deleted-paper': DateTime.utc(2026, 7, 1).toIso8601String(),
    });
    expect(snapshotWebDav['endpoint'], '');
    expect(snapshotWebDav['username'], '');
    expect(snapshotWebDav['password'], '');
    expect(snapshotWebDav['encryptionPassphrase'], '');
    expect(snapshotWebDav['rootPath'], 'repapertodo');
    expect(snapshotWebDav['autoSyncIntervalMinutes'], 15);
    expect(snapshotWebDav['requestTimeoutSeconds'], 30);
  });

  test('creates nested WebDAV collections before upload', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      paths:
          const WebDavStateSyncPaths(rootPath: '/ Team Space / RePaperTodo /'),
      deviceId: 'test-device',
    );

    final result = await service.push(
      AppState(),
      updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
    );

    final mkcolPaths = requests
        .where((request) => request.method == 'MKCOL')
        .map((request) => request.url.pathSegments.skip(4).join('/'))
        .toList(growable: false);
    final putPaths = requests
        .where((request) => request.method == 'PUT')
        .map((request) => request.url.pathSegments.skip(4).join('/'))
        .toList(growable: false);

    expect(result.status, WebDavStateSyncStatus.uploaded);
    expect(mkcolPaths, [
      'Team Space',
      'Team Space/RePaperTodo',
      'Team Space/RePaperTodo/snapshots',
      'Team Space/RePaperTodo/ops',
    ]);
    expect(putPaths, contains('Team Space/RePaperTodo/manifest.json'));
    expect(
      result.snapshotPath,
      'Team Space/RePaperTodo/snapshots/snapshot-20260630T100000000Z-test-device-seq-000000000001.json',
    );
  });

  test('rejects blank WebDAV state sync path components before upload',
      () async {
    for (final paths in const [
      WebDavStateSyncPaths(manifestFileName: ' '),
      WebDavStateSyncPaths(snapshotDirectoryName: ' '),
      WebDavStateSyncPaths(operationDirectoryName: ' '),
    ]) {
      final requests = <http.Request>[];
      final webDavClient = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials:
            const WebDavCredentials(username: 'user', password: 'pass'),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('network should not be reached', 500);
        }),
      );
      final service = WebDavStateSyncService(
        client: webDavClient,
        paths: paths,
        deviceId: 'test-device',
      );

      await expectLater(
        service.push(
          AppState(),
          updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
        ),
        throwsA(isA<WebDavSyncConfigurationException>()),
        reason: paths.toString(),
      );
      expect(requests, isEmpty, reason: paths.toString());
    }
  });

  test('rejects blank WebDAV state sync root path before upload', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      paths: const WebDavStateSyncPaths(rootPath: ''),
      deviceId: 'test-device',
    );

    await expectLater(
      service.push(
        AppState(),
        updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test('rejects blank-normalized device ids before upload', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: '!!!',
    );

    await expectLater(
      service.push(
        AppState(),
        updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test('rejects blank WebDAV state sync root path before listing snapshots',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      paths: const WebDavStateSyncPaths(rootPath: ''),
      deviceId: 'test-device',
    );

    await expectLater(
      service.listSnapshots(),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test(
      'rejects blank WebDAV state sync root path before listing operation logs',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      paths: const WebDavStateSyncPaths(rootPath: ''),
      deviceId: 'test-device',
    );

    await expectLater(
      service.listOperationLogs(),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test('rejects blank WebDAV state sync root path before downloading snapshots',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      paths: const WebDavStateSyncPaths(rootPath: ''),
      deviceId: 'test-device',
    );

    await expectLater(
      service.downloadSnapshot(
        'snapshots/snapshot-20260630T100000000Z-test-device-seq-000000000001.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test(
      'rejects blank WebDAV state sync root path before downloading operation logs',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      paths: const WebDavStateSyncPaths(rootPath: ''),
      deviceId: 'test-device',
    );

    await expectLater(
      service.downloadOperationLogWithMetadata(
        'ops/test-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test(
      'rejects blank WebDAV state sync root path before uploading operation logs',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      paths: const WebDavStateSyncPaths(rootPath: ''),
      deviceId: 'test-device',
    );

    await expectLater(
      service.uploadOperationLogs([
        SyncOperation(
          id: 'test-device-1',
          deviceId: 'test-device',
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9),
          payload: {'paperId': 'note', 'content': 'Fresh'},
        ),
      ]),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test('skips blank-normalized operation log device ids before upload',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.uploadOperationLogs([
      SyncOperation(
        id: 'blank-device-1',
        deviceId: '!!!',
        sequence: 1,
        kind: SyncOperationKind.updateNoteContent,
        createdAtUtc: DateTime.utc(2026, 7, 1, 9),
        payload: {'paperId': 'note', 'content': 'Ignored'},
      ),
      SyncOperation(
        id: 'short-device-1',
        deviceId: 'bad',
        sequence: 1,
        kind: SyncOperationKind.updateNoteContent,
        createdAtUtc: DateTime.utc(2026, 7, 1, 9, 1),
        payload: {'paperId': 'note', 'content': 'Also ignored'},
      ),
    ]);

    expect(result.uploadedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.acceptedDeviceSequences, isEmpty);
    expect(requests, isEmpty);
  });

  test(
      'rejects blank WebDAV state sync root path before migrating operation logs',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      paths: const WebDavStateSyncPaths(rootPath: ''),
      payloadCodec: EncryptedWebDavPayloadCodec(
        passphrase: 'shared sync secret',
        kdfIterations: 100000,
        random: Random(3),
      ),
      deviceId: 'test-device',
    );

    await expectLater(
      service.migrateLegacyPlainOperationLog(
        const WebDavOperationLogRecord(
          path: 'ops/test-device-000000000001.jsonl',
          deviceId: 'test-device',
          sequence: 1,
          etag: 'op-v1',
        ),
        downloadedResult: WebDavOperationLogDownloadResult(
          path: 'ops/test-device-000000000001.jsonl',
          payloadFormat: WebDavPayloadFormat.plainJson,
          operations: [
            SyncOperation(
              id: 'test-device-1',
              deviceId: 'test-device',
              sequence: 1,
              kind: SyncOperationKind.updateNoteContent,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9),
              payload: const {'paperId': 'note', 'content': 'Legacy'},
            ),
          ],
        ),
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test('rejects multi-segment WebDAV state sync path components before upload',
      () async {
    for (final paths in const [
      WebDavStateSyncPaths(manifestFileName: 'meta/manifest.json'),
      WebDavStateSyncPaths(snapshotDirectoryName: 'snapshots/archive'),
      WebDavStateSyncPaths(operationDirectoryName: 'ops/archive'),
    ]) {
      final requests = <http.Request>[];
      final webDavClient = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials:
            const WebDavCredentials(username: 'user', password: 'pass'),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('network should not be reached', 500);
        }),
      );
      final service = WebDavStateSyncService(
        client: webDavClient,
        paths: paths,
        deviceId: 'test-device',
      );

      await expectLater(
        service.push(
          AppState(),
          updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
        ),
        throwsA(isA<WebDavSyncConfigurationException>()),
        reason: paths.toString(),
      );
      expect(requests, isEmpty, reason: paths.toString());
    }
  });

  test('rejects invalid generated remote sequences', () {
    final paths = WebDavStateSyncPaths();
    final updatedAtUtc = DateTime.utc(2026, 6, 30, 10);
    const overWideSequence = maxSyncDeviceSequence + 1;

    expect(
      () => paths.snapshotPath(
        updatedAtUtc,
        'test-device',
        sequence: 0,
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      () => paths.snapshotPath(
        updatedAtUtc,
        'test-device',
        sequence: -1,
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      () => paths.operationLogPath('test-device', 0),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      () => paths.operationLogPath('test-device', -1),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      () => paths.snapshotPath(
        updatedAtUtc,
        'test-device',
        sequence: overWideSequence,
      ),
      throwsA(
        isA<WebDavSyncConfigurationException>().having(
          (error) => error.message,
          'message',
          contains('1 through $maxSyncDeviceSequence'),
        ),
      ),
    );
    expect(
      () => paths.operationLogPath('test-device', overWideSequence),
      throwsA(
        isA<WebDavSyncConfigurationException>().having(
          (error) => error.message,
          'message',
          contains('1 through $maxSyncDeviceSequence'),
        ),
      ),
    );
    expect(
      () => paths.snapshotPath(
        updatedAtUtc,
        '!!!',
        sequence: 1,
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      () => paths.operationLogPath('!!!', 1),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
  });

  test('rejects exhausted device sequences before upload', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    await expectLater(
      service.push(
        AppState(),
        updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
        previousDeviceSequences: const {'test-device': maxSyncDeviceSequence},
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test('accepts matching existing snapshots during push retry', () async {
    const codec = AppStateCodec();
    final requests = <http.Request>[];
    final pushedState = AppState(
      papers: [
        PaperData(
          id: 'paper-1',
          type: PaperTypes.todo,
          title: 'Sync me',
        ),
      ],
    );
    List<int>? existingSnapshotBytes;
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/snapshots/')) {
          existingSnapshotBytes = request.bodyBytes;
          return http.Response('already exists', 412);
        }
        if (request.method == 'GET' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response.bytes(existingSnapshotBytes ?? const [], 200);
        }
        if (request.method == 'PUT') {
          return http.Response('', 201);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      codec: codec,
      deviceId: 'test-device',
    );

    final result = await service.push(
      pushedState,
      updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
    );

    expect(result.status, WebDavStateSyncStatus.uploaded);
    expect(
      requests
          .where((request) => request.url.path.contains('/snapshots/'))
          .map((request) => request.method),
      ['PUT', 'GET'],
    );
    expect(
      requests.any((request) =>
          request.method == 'PUT' && request.url.path.contains('/ops/')),
      true,
    );
    expect(
      requests.any((request) =>
          request.method == 'PUT' &&
          request.url.path.endsWith('/manifest.json')),
      true,
    );
  });

  test('accepts matching existing snapshots after provider conflict', () async {
    const codec = AppStateCodec();
    final requests = <http.Request>[];
    final pushedState = AppState(
      papers: [
        PaperData(
          id: 'paper-1',
          type: PaperTypes.todo,
          title: 'Sync me',
        ),
      ],
    );
    List<int>? existingSnapshotBytes;
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/snapshots/')) {
          existingSnapshotBytes = request.bodyBytes;
          return http.Response('already exists', 409);
        }
        if (request.method == 'GET' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response.bytes(existingSnapshotBytes ?? const [], 200);
        }
        if (request.method == 'PUT') {
          return http.Response('', 201);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      codec: codec,
      deviceId: 'test-device',
    );

    final result = await service.push(
      pushedState,
      updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
    );

    expect(result.status, WebDavStateSyncStatus.uploaded);
    expect(
      requests
          .where((request) => request.url.path.contains('/snapshots/'))
          .map((request) => request.method),
      ['PUT', 'GET'],
    );
  });

  test(
      'preserves snapshot provider conflicts when existing content is unreadable',
      () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response('already exists', 409);
        }
        if (request.method == 'GET' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response('not json', 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    await expectLater(
      service.push(
        AppState(
          papers: [
            PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'Sync me'),
          ],
        ),
        updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
      ),
      throwsA(isA<WebDavException>()
          .having((error) => error.statusCode, 'statusCode', 409)),
    );
  });

  test('accepts matching encrypted snapshots during push retry', () async {
    const codec = AppStateCodec();
    final pushedState = AppState(
      papers: [
        PaperData(
          id: 'paper-1',
          type: PaperTypes.note,
          title: 'Encrypted',
          content: 'Same logical snapshot',
        ),
      ],
    );
    final existingSnapshotBytes = await EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(1),
    ).encodeSnapshot(pushedState, codec);
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/snapshots/')) {
          expect(
            const ListEquality<int>().equals(
              request.bodyBytes,
              existingSnapshotBytes,
            ),
            false,
          );
          return http.Response('already exists', 412);
        }
        if (request.method == 'GET' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response.bytes(existingSnapshotBytes, 200);
        }
        if (request.method == 'PUT') {
          return http.Response('', 201);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      codec: codec,
      payloadCodec: EncryptedWebDavPayloadCodec(
        passphrase: 'shared sync secret',
        kdfIterations: 100000,
        random: Random(2),
      ),
      deviceId: 'test-device',
    );

    final result = await service.push(
      pushedState,
      updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
    );

    expect(result.status, WebDavStateSyncStatus.uploaded);
    expect(
      requests
          .where((request) => request.url.path.contains('/snapshots/'))
          .map((request) => request.method),
      ['PUT', 'GET'],
    );
    expect(
      requests.any((request) =>
          request.method == 'PUT' && request.url.path.contains('/ops/')),
      true,
    );
    expect(
      requests.any((request) =>
          request.method == 'PUT' &&
          request.url.path.endsWith('/manifest.json')),
      true,
    );
  });

  test('rejects conflicting existing snapshots during push retry', () async {
    const codec = AppStateCodec();
    final requests = <http.Request>[];
    final pushedState = AppState(
      papers: [
        PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'Sync me'),
      ],
    );
    final existingState = AppState(
      papers: [
        PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'Different'),
      ],
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response('already exists', 412);
        }
        if (request.method == 'GET' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response(codec.encode(existingState), 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      codec: codec,
      deviceId: 'test-device',
    );

    await expectLater(
      service.push(
        pushedState,
        updatedAtUtc: DateTime.utc(2026, 6, 30, 10),
      ),
      throwsA(isA<WebDavException>()),
    );
    expect(
      requests.any((request) => request.url.path.contains('/ops/')),
      false,
    );
    expect(
      requests.any((request) => request.url.path.endsWith('/manifest.json')),
      false,
    );
  });

  test('pull downloads and decodes the remote snapshot', () async {
    const codec = AppStateCodec();
    final remoteState = AppState(
      papers: [
        PaperData(
          id: 'paper-remote',
          type: PaperTypes.note,
          title: 'Remote note',
          content: 'From WebDAV',
        ),
      ],
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
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
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath:
                    'repapertodo/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json',
                deviceSequences: {'other-device': 2, 'test-device': 4},
              ).toJson(),
            ),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json')) {
          return http.Response(codec.encode(remoteState), 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.pull();

    expect(result.status, WebDavStateSyncStatus.downloaded);
    expect(result.manifest?.updatedAtUtc, DateTime.utc(2026, 6, 30, 11));
    expect(result.manifestEtag, '"manifest-v1"');
    expect(result.snapshotPayloadFormat, WebDavPayloadFormat.plainJson);
    expect(
      result.snapshotPath,
      'repapertodo/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json',
    );
    expect(result.state?.papers.single.title, 'Remote');
    expect(result.state?.papers.single.content, 'From WebDAV');
  });

  test('pull accepts legacy-cased manifest wire keys and string sequences',
      () async {
    const codec = AppStateCodec();
    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json';
    final remoteState = AppState(
      papers: [
        PaperData(
          id: 'paper-legacy-manifest',
          type: PaperTypes.note,
          title: 'Legacy manifest note',
          content: 'From uppercase manifest keys',
        ),
      ],
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200, headers: {'etag': '"manifest-v1"'});
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode({
              'SCHEMAVERSION': '1',
              'UPDATEDATUTC': '2026-06-30T11:00:00Z',
              'LATESTSNAPSHOTPATH': snapshotPath,
              'DEVICESEQUENCES': {'other-device': '4'},
            }),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json')) {
          return http.Response(codec.encode(remoteState), 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.pull();

    expect(result.status, WebDavStateSyncStatus.downloaded);
    expect(result.manifest?.updatedAtUtc, DateTime.utc(2026, 6, 30, 11));
    expect(result.manifest?.latestSnapshotPath, snapshotPath);
    expect(result.manifest?.deviceSequences, {'other-device': 4});
    expect(result.manifestEtag, '"manifest-v1"');
    expect(result.state?.papers.single.title, 'Legacy');
    expect(result.state?.papers.single.content, 'From uppercase manifest keys');
  });

  test('pull accepts manifests without device sequences', () async {
    const codec = AppStateCodec();
    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json';
    final remoteState = AppState(
      papers: [
        PaperData(
          id: 'paper-missing-sequences',
          type: PaperTypes.note,
          title: 'Missing sequences',
          content: 'Pulled from a minimal manifest',
        ),
      ],
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200, headers: {'etag': '"manifest-v1"'});
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'updatedAtUtc': '2026-06-30T11:00:00Z',
              'latestSnapshotPath': snapshotPath,
            }),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json')) {
          return http.Response(codec.encode(remoteState), 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.pull();

    expect(result.status, WebDavStateSyncStatus.downloaded);
    expect(result.manifest?.updatedAtUtc, DateTime.utc(2026, 6, 30, 11));
    expect(result.manifest?.latestSnapshotPath, snapshotPath);
    expect(result.manifest?.deviceSequences, isEmpty);
    expect(result.manifestEtag, '"manifest-v1"');
    expect(result.state?.papers.single.id, 'paper-missing-sequences');
    expect(
        result.state?.papers.single.content, 'Pulled from a minimal manifest');
  });

  test('pull accepts UTF-8 BOM-prefixed manifests', () async {
    const codec = AppStateCodec();
    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260630T110000000Z-bom-device-seq-000000000001.json';
    final remoteState = AppState(
      papers: [
        PaperData(
          id: 'paper-bom-manifest',
          type: PaperTypes.note,
          title: 'BOM manifest',
          content: 'Pulled after stripping manifest BOM',
        ),
      ],
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200, headers: {'etag': '"manifest-bom"'});
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response.bytes(
            utf8.encode(
              '\uFEFF${jsonEncode({
                    'schemaVersion': 1,
                    'updatedAtUtc': '2026-06-30T11:00:00Z',
                    'latestSnapshotPath': snapshotPath,
                    'deviceSequences': {'bom-device': 1},
                  })}',
            ),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/snapshots/snapshot-20260630T110000000Z-bom-device-seq-000000000001.json')) {
          return http.Response(codec.encode(remoteState), 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.pull();

    expect(result.status, WebDavStateSyncStatus.downloaded);
    expect(result.manifestEtag, '"manifest-bom"');
    expect(result.manifest?.deviceSequences, {'bom-device': 1});
    expect(result.state?.papers.single.id, 'paper-bom-manifest');
    expect(
      result.state?.papers.single.content,
      'Pulled after stripping manifest BOM',
    );
  });

  test('pull downloads and decodes encrypted remote snapshots', () async {
    const codec = AppStateCodec();
    final remoteState = AppState(
      papers: [
        PaperData(
          id: 'encrypted-remote-note',
          type: PaperTypes.note,
          title: 'Crypt',
          content: 'From encrypted WebDAV',
        ),
      ],
    );
    final encryptedSnapshotBytes = await EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(1),
    ).encodeSnapshot(remoteState, codec);
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200, headers: {'etag': '"manifest-v2"'});
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 7, 2, 11),
                latestSnapshotPath:
                    'repapertodo/snapshots/snapshot-20260702T110000000Z-other-device-seq-000000000003.json',
                deviceSequences: {'other-device': 3},
              ).toJson(),
            ),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/snapshots/snapshot-20260702T110000000Z-other-device-seq-000000000003.json')) {
          return http.Response.bytes(encryptedSnapshotBytes, 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      payloadCodec: EncryptedWebDavPayloadCodec(
        passphrase: 'shared sync secret',
        kdfIterations: 100000,
      ),
      deviceId: 'test-device',
    );

    final result = await service.pull();

    expect(result.status, WebDavStateSyncStatus.downloaded);
    expect(result.manifestEtag, '"manifest-v2"');
    expect(result.snapshotPayloadFormat, WebDavPayloadFormat.encrypted);
    expect(result.snapshotPath,
        'repapertodo/snapshots/snapshot-20260702T110000000Z-other-device-seq-000000000003.json');
    expect(result.state?.papers.single.title, 'Crypt');
    expect(result.state?.papers.single.content, 'From encrypted WebDAV');
  });

  test('encrypted settings can pull legacy plain remote snapshots', () async {
    final service = WebDavStateSyncService.fromSettings(
      WebDavSyncSettings(
        endpoint: 'https://dav.example.test/remote.php/dav/files/user/',
        username: 'user',
        password: 'pass',
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
      ),
      deviceId: 'test-device',
      httpClient: MockClient((request) async {
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200, headers: {'etag': '"manifest-v3"'});
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 7, 2, 12),
                latestSnapshotPath:
                    'repapertodo/snapshots/snapshot-20260702T120000000Z-windows-device-seq-000000000008.json',
                deviceSequences: {'windows-device': 8},
              ).toJson(),
            ),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/snapshots/snapshot-20260702T120000000Z-windows-device-seq-000000000008.json')) {
          return http.Response(
            _legacyPaperTodoSnapshotJson(
              id: 'legacy-plain-note',
              title: 'Legacy cloud note',
              content: 'Plain before encryption',
            ),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );

    final result = await service.pull();

    expect(result.status, WebDavStateSyncStatus.downloaded);
    expect(result.manifestEtag, '"manifest-v3"');
    expect(result.snapshotPayloadFormat, WebDavPayloadFormat.plainJson);
    expect(result.state?.papers.single.id, 'legacy-plain-note');
    expect(result.state?.papers.single.title, 'Legacy');
    expect(result.state?.papers.single.content, 'Plain before encryption');
  });

  test('reports encrypted remote snapshots with the wrong passphrase',
      () async {
    const codec = AppStateCodec();
    final encryptedSnapshotBytes = await EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(1),
    ).encodeSnapshot(
      AppState(
        papers: [
          PaperData(
            id: 'encrypted-remote-note',
            type: PaperTypes.note,
            title: 'Encrypted remote',
          ),
        ],
      ),
      codec,
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 7, 2, 11),
                latestSnapshotPath:
                    'repapertodo/snapshots/snapshot-20260702T110000000Z-other-device-seq-000000000003.json',
                deviceSequences: {'other-device': 3},
              ).toJson(),
            ),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/snapshots/snapshot-20260702T110000000Z-other-device-seq-000000000003.json')) {
          return http.Response.bytes(encryptedSnapshotBytes, 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      payloadCodec: EncryptedWebDavPayloadCodec(
        passphrase: 'wrong sync secret',
        kdfIterations: 100000,
      ),
      deviceId: 'test-device',
    );

    await expectLater(
      service.pull(),
      throwsA(
        isA<WebDavPayloadDecryptionException>().having(
          (error) => error.message,
          'message',
          contains('sync encryption passphrase'),
        ),
      ),
    );
  });

  test('rejects manifests with invalid timestamps before snapshot download',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'updatedAtUtc': 'not-a-date',
              'latestSnapshotPath':
                  'repapertodo/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json',
              'deviceSequences': {'other-device': 2},
            }),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('updatedAtUtc must be valid'),
        ),
      ),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test(
      'rejects manifests with unsupported schema versions before snapshot download',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode({
              'schemaVersion': 2,
              'updatedAtUtc': '2026-06-30T11:00:00Z',
              'latestSnapshotPath':
                  'repapertodo/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json',
              'deviceSequences': {'other-device': 2},
            }),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported sync manifest schemaVersion'),
        ),
      ),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test('rejects manifests with invalid snapshot path types before download',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'updatedAtUtc': '2026-06-30T11:00:00Z',
              'latestSnapshotPath': ['bad-snapshot.json'],
              'deviceSequences': {'other-device': 2},
            }),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('latestSnapshotPath must be a string'),
        ),
      ),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test(
      'rejects manifests with invalid device sequences before snapshot download',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'updatedAtUtc': '2026-06-30T11:00:00Z',
              'latestSnapshotPath':
                  'repapertodo/snapshots/snapshot-20260630T110000000Z-other-device-seq-000000000004.json',
              'deviceSequences': {'other-device': 1.2},
            }),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('device sequence must be a positive integer'),
        ),
      ),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test('rejects manifest snapshots outside the snapshot collection', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath: 'repapertodo/manifest.json',
                deviceSequences: {'other-device': 2},
              ).toJson(),
            ),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test('rejects manifest snapshots with blank-normalized device ids', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath:
                    'repapertodo/snapshots/snapshot-20260630T110000000Z-!!!-seq-000000000004.json',
                deviceSequences: {'other-device': 2},
              ).toJson(),
            ),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test('rejects manifest snapshots with invalid snapshot timestamps', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath:
                    'repapertodo/snapshots/snapshot-20261301T110000000Z-phone-device-seq-000000000004.json',
                deviceSequences: {'phone-device': 2},
              ).toJson(),
            ),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test('rejects manifest snapshots with zero snapshot sequences', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath:
                    'repapertodo/snapshots/snapshot-20260630T110000000Z-phone-device-seq-000000000000.json',
                deviceSequences: {'phone-device': 2},
              ).toJson(),
            ),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test('rejects manifest snapshots with overlong snapshot sequences', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath:
                    'repapertodo/snapshots/snapshot-20260630T110000000Z-phone-device-seq-${maxSyncDeviceSequence + 1}.json',
                deviceSequences: {'phone-device': 2},
              ).toJson(),
            ),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test('rejects manifest snapshots with encoded parent-directory segments',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath:
                    'repapertodo/snapshots/%2e%2e/other/snapshot-20260630T110000000Z-other-device-seq-000000000004.json',
                deviceSequences: {'other-device': 2},
              ).toJson(),
            ),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.pull(),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      requests
          .where((request) =>
              request.method == 'GET' &&
              !request.url.path.endsWith('/manifest.json'))
          .map((request) => request.url.path),
      isEmpty,
    );
  });

  test('sync creates the manifest only when it is still missing', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 404);
        }
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.sync(
      localState: AppState(),
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, WebDavStateSyncStatus.uploaded);
    final manifestRequest = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.endsWith('/manifest.json'));
    expect(manifestRequest.headers['if-none-match'], '*');
  });

  test('sync recreates the manifest conditionally when GET turns missing',
      () async {
    for (final statusCode in const [404, 410]) {
      final requests = <http.Request>[];
      final webDavClient = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials:
            const WebDavCredentials(username: 'user', password: 'pass'),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'HEAD' &&
              request.url.path.endsWith('/manifest.json')) {
            return http.Response('', 200, headers: {'etag': '"manifest-v1"'});
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/manifest.json')) {
            return http.Response('', statusCode);
          }
          return switch (request.method) {
            'MKCOL' => http.Response('', 201),
            'PUT' => http.Response('', 201),
            _ => http.Response('unexpected ${request.method}', 500),
          };
        }),
      );
      final service = WebDavStateSyncService(
        client: webDavClient,
        deviceId: 'test-device',
      );

      final result = await service.sync(
        localState: AppState(),
        localUpdatedAtUtc: DateTime.utc(2026, 7),
      );

      expect(result.status, WebDavStateSyncStatus.uploaded);
      final manifestRequest = requests.firstWhere((request) =>
          request.method == 'PUT' &&
          request.url.path.endsWith('/manifest.json'));
      expect(manifestRequest.headers['if-none-match'], '*');
      expect(
        manifestRequest.headers.containsKey('if-match'),
        false,
        reason: statusCode.toString(),
      );
    }
  });

  test('sync uses PROPFIND metadata etag when HEAD is unsupported', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('method not allowed', 405);
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/manifest.json')) {
          expect(request.headers['depth'], '0');
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/manifest.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"manifest-v1"</D:getetag>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath: 'repapertodo/state.json',
                deviceSequences: {'other-device': 2, 'test-device': 4},
              ).toJson(),
            ),
            200,
          );
        }
        if (request.method == 'MKCOL') {
          return http.Response('', 405);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/manifest.json')) {
          expect(request.headers['if-match'], '"manifest-v1"');
          return http.Response('', 204);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.sync(
      localState: AppState(
        papers: [
          PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
        ],
      ),
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, WebDavStateSyncStatus.uploaded);
    expect(
      requests.map((request) => request.method),
      [
        'HEAD',
        'PROPFIND',
        'GET',
        'MKCOL',
        'MKCOL',
        'MKCOL',
        'PUT',
        'PUT',
        'PUT'
      ],
    );
    final manifestRequest = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.endsWith('/manifest.json'));
    expect(manifestRequest.headers['if-match'], '"manifest-v1"');
    expect(manifestRequest.headers, isNot(contains('if-none-match')));
  });

  test('sync advances legacy manifest string device sequences before upload',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200, headers: {'etag': '"manifest-v4"'});
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode({
              'SCHEMAVERSION': '1',
              'UPDATEDATUTC': '2026-06-30T11:00:00Z',
              'LATESTSNAPSHOTPATH':
                  'repapertodo/snapshots/snapshot-20260630T110000000Z-phone-device-seq-000000000003.json',
              'DEVICESEQUENCES': {
                ' TEST-DEVICE ': '4',
                'phone-device': '3',
              },
            }),
            200,
          );
        }
        if (request.method == 'MKCOL') {
          return http.Response('', 405);
        }
        if (request.method == 'PUT') {
          return http.Response('', 204);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.sync(
      localState: AppState(
        papers: [
          PaperData(
            id: 'paper-local',
            type: PaperTypes.note,
            title: 'Local newer',
          ),
        ],
      ),
      localUpdatedAtUtc: DateTime.utc(2026, 7, 1),
    );

    final operationRequest = requests.firstWhere((request) =>
        request.method == 'PUT' &&
        request.url.path.endsWith('/ops/test-device-000000000005.jsonl'));
    final operation = jsonDecode(utf8.decode(operationRequest.bodyBytes).trim())
        as Map<String, Object?>;
    final manifestRequest = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.endsWith('/manifest.json'));
    final manifest = jsonDecode(utf8.decode(manifestRequest.bodyBytes))
        as Map<String, Object?>;

    expect(result.status, WebDavStateSyncStatus.uploaded);
    expect(result.manifest?.deviceSequences, {
      'test-device': 5,
      'phone-device': 3,
    });
    expect(operation['sequence'], 5);
    expect(manifestRequest.headers['if-match'], '"manifest-v4"');
    expect(manifest['deviceSequences'], {
      'test-device': 5,
      'phone-device': 3,
    });
    expect(
      manifest['latestSnapshotPath'],
      contains('-test-device-seq-000000000005.json'),
    );
  });

  test('sync reports a conflict when manifest conditional write fails',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
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
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath: 'repapertodo/state.json',
                deviceSequences: {'other-device': 2, 'test-device': 4},
              ).toJson(),
            ),
            200,
          );
        }
        if (request.method == 'MKCOL') {
          return http.Response('', 405);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/manifest.json')) {
          expect(request.headers['if-match'], '"manifest-v1"');
          return http.Response('precondition failed', 412);
        }
        if (request.method == 'DELETE' && request.url.path.contains('/ops/')) {
          return http.Response('', 204);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.sync(
      localState: AppState(
        papers: [
          PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
        ],
      ),
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, WebDavStateSyncStatus.conflict);
    expect(
      result.snapshotPath,
      'repapertodo/snapshots/snapshot-20260701T000000000Z-test-device-seq-000000000005.json',
    );
    final snapshotRequest = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.contains('/snapshots/'));
    expect(snapshotRequest.headers['if-none-match'], '*');
    expect(result.manifest?.deviceSequences, {
      'other-device': 2,
      'test-device': 5,
    });
    final operationRequests =
        requests.where((request) => request.url.path.contains('/ops/'));
    expect(operationRequests.map((request) => request.method), [
      'PUT',
      'DELETE',
    ]);
    expect(operationRequests.map((request) => request.url.path).toSet(), {
      '/remote.php/dav/files/user/repapertodo/ops/test-device-000000000005.jsonl',
    });
  });

  test('sync treats weak manifest etags as conditional conflicts', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200, headers: {'etag': 'W/"manifest-v1"'});
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath: 'repapertodo/state.json',
                deviceSequences: {'other-device': 2, 'test-device': 4},
              ).toJson(),
            ),
            200,
          );
        }
        if (request.method == 'MKCOL') {
          return http.Response('', 405);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
          return http.Response('', 201);
        }
        if (request.method == 'DELETE' && request.url.path.contains('/ops/')) {
          return http.Response('', 204);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.sync(
      localState: AppState(
        papers: [
          PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
        ],
      ),
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, WebDavStateSyncStatus.conflict);
    expect(
      requests.where((request) =>
          request.method == 'PUT' &&
          request.url.path.endsWith('/manifest.json')),
      isEmpty,
    );
    expect(
      requests.where((request) =>
          request.method == 'DELETE' && request.url.path.contains('/ops/')),
      hasLength(1),
    );
  });

  test('sync treats missing manifest etags as conditional conflicts', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response('', 200);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode(
              SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
                latestSnapshotPath: 'repapertodo/state.json',
                deviceSequences: {'other-device': 2, 'test-device': 4},
              ).toJson(),
            ),
            200,
          );
        }
        if (request.method == 'MKCOL') {
          return http.Response('', 405);
        }
        if (request.method == 'PUT' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
          return http.Response('', 201);
        }
        if (request.method == 'DELETE' && request.url.path.contains('/ops/')) {
          return http.Response('', 204);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      deviceId: 'test-device',
    );

    final result = await service.sync(
      localState: AppState(
        papers: [
          PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
        ],
      ),
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, WebDavStateSyncStatus.conflict);
    expect(
      requests.where((request) =>
          request.method == 'PUT' &&
          request.url.path.endsWith('/manifest.json')),
      isEmpty,
    );
    expect(
      requests.where((request) =>
          request.method == 'DELETE' && request.url.path.contains('/ops/')),
      hasLength(1),
    );
  });

  test('lists remote snapshots for conflict recovery', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/</D:href>
    <D:propstat>
      <D:prop><D:resourcetype><D:collection /></D:resourcetype></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260701T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"phone-v1"</D:getetag>
        <D:getcontentlength>2048</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/repapertodo/user/repapertodo/snapshots/snapshot-20260702T080000000Z-laptop-seq-000000000006.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"laptop-v6"</D:getetag>
        <D:getcontentlength>3072</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 08:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260630T210000000Z-win-device.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"win-v1"</D:getetag>
        <D:getcontentlength>1024</D:getcontentlength>
        <D:getlastmodified>Tue, 30 Jun 2026 21:02:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/readme.txt</D:href>
    <D:propstat><D:prop /></D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20261301T090000000Z-bad-date-seq-000000000001.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"bad-date"</D:getetag>
        <D:getcontentlength>2048</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260701T240000000Z-bad-time-seq-000000000001.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"bad-time"</D:getetag>
        <D:getcontentlength>2048</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260701T096000000Z-bad-minute-seq-000000000001.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"bad-minute"</D:getetag>
        <D:getcontentlength>2048</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260701T090060000Z-bad-second-seq-000000000001.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"bad-second"</D:getetag>
        <D:getcontentlength>2048</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260701T090000000Z-overlong-seq-${maxSyncDeviceSequence + 1}.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"overlong-seq"</D:getetag>
        <D:getcontentlength>2048</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/../other/snapshot-20260702T090000000Z-escaped-seq-000000000001.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"escaped"</D:getetag>
        <D:getcontentlength>4096</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 09:00:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/%2e%2e/other/snapshot-20260702T100000000Z-encoded-seq-000000000001.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"encoded"</D:getetag>
        <D:getcontentlength>4096</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 10:00:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/bad%/snapshot-20260702T110000000Z-bad-seq-000000000001.json</D:href>
    <D:propstat><D:prop /></D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();

    expect(snapshots, hasLength(3));
    expect(snapshots.map((snapshot) => snapshot.deviceId), [
      'laptop',
      'phone',
      'win-device',
    ]);
    expect(snapshots.first.path,
        'repapertodo/snapshots/snapshot-20260702T080000000Z-laptop-seq-000000000006.json');
    expect(snapshots.first.updatedAtUtc, DateTime.utc(2026, 7, 2, 8));
    expect(snapshots.first.etag, 'laptop-v6');
    expect(snapshots.first.contentLength, 3072);
    expect(snapshots.first.lastModifiedUtc, DateTime.utc(2026, 7, 2, 8, 1));
  });

  test('deduplicates snapshot records by stable metadata preference', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260702T080000000Z-laptop-seq-000000000006.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"same-v6"</D:getetag>
        <D:getcontentlength>1024</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 08:02:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260702T080000000Z-laptop-seq-000000000006.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"same-v6"</D:getetag>
        <D:getcontentlength>3072</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 08:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260701T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"phone-v4"</D:getetag>
        <D:getcontentlength>2048</D:getcontentlength>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();

    expect(snapshots, hasLength(2));
    expect(
      snapshots.map((snapshot) => snapshot.path),
      [
        'repapertodo/snapshots/snapshot-20260702T080000000Z-laptop-seq-000000000006.json',
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone-seq-000000000004.json',
      ],
    );
    expect(snapshots.first.etag, 'same-v6');
    expect(snapshots.first.contentLength, 1024);
    expect(snapshots.first.lastModifiedUtc, DateTime.utc(2026, 7, 2, 8, 2));
  });

  test('orders same-time snapshot records deterministically', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260702T080000000Z-z-device-seq-000000000001.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"z"</D:getetag>
        <D:getcontentlength>2</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 08:02:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260702T080000000Z-a-device-seq-000000000001.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"a"</D:getetag>
        <D:getcontentlength>1</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 08:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();

    expect(
      snapshots.map((snapshot) => snapshot.path),
      [
        'repapertodo/snapshots/snapshot-20260702T080000000Z-a-device-seq-000000000001.json',
        'repapertodo/snapshots/snapshot-20260702T080000000Z-z-device-seq-000000000001.json',
      ],
    );
  });

  test('normalizes snapshot record device ids from filenames', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260702T090000000Z-Phone Device-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-device-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260703T090000000Z-!!!-seq-000000000005.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"blank-device-v5"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone-device');
    expect(snapshots.single.etag, 'phone-device-v4');
  });

  test('lists no snapshots when the snapshot collection is missing', () async {
    for (final statusCode in const [404, 410]) {
      final webDavClient = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials:
            const WebDavCredentials(username: 'user', password: 'pass'),
        httpClient: MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/repapertodo/snapshots')) {
            return http.Response('', statusCode);
          }
          return http.Response(
              'unexpected ${request.method} ${request.url}', 500);
        }),
      );
      final service = WebDavStateSyncService(client: webDavClient);

      expect(await service.listSnapshots(), isEmpty, reason: '$statusCode');
    }
  });

  test('lists entries from absolute encoded WebDAV hrefs', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/Team%20Space/RePaperTodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>https://dav.example.test/dav/Team%20Space/RePaperTodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"phone-v4"</D:getetag>
        <D:getcontentlength>4096</D:getcontentlength>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/Team%20Space/RePaperTodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>https://dav.example.test/dav/Team%20Space/RePaperTodo/ops/android-device-000000000002.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"android-op-v2"</D:getetag>
        <D:getcontentlength>512</D:getcontentlength>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      paths: const WebDavStateSyncPaths(rootPath: 'Team Space/RePaperTodo'),
    );

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(
      snapshots.single.path,
      'Team Space/RePaperTodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json',
    );
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(snapshots.single.contentLength, 4096);
    expect(operationLogs, hasLength(1));
    expect(
      operationLogs.single.path,
      'Team Space/RePaperTodo/ops/android-device-000000000002.jsonl',
    );
    expect(operationLogs.single.deviceId, 'android-device');
    expect(operationLogs.single.sequence, 2);
    expect(operationLogs.single.etag, 'android-op-v2');
    expect(operationLogs.single.contentLength, 512);
  });

  test('ignores ambiguous encoded absolute WebDAV href paths', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>https://dav.example.test/dav%2Frepapertodo/snapshots/snapshot-20260703T090000000Z-encoded-base-seq-000000000009.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"encoded-base-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/dav/repapertodo%2F..%2Fother/snapshots/snapshot-20260703T100000000Z-encoded-slash-seq-000000000010.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"encoded-slash-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/dav/repapertodo/snapshots/snapshot-20260703T110000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>https://dav.example.test/dav%2Frepapertodo/ops/encoded-base-000000000009.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"encoded-base-op-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/dav/repapertodo%2F..%2Fother/ops/encoded-slash-000000000010.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"encoded-slash-op-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/dav/repapertodo/ops/phone-device-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-op-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(operationLogs, hasLength(1));
    expect(operationLogs.single.deviceId, 'phone-device');
    expect(operationLogs.single.sequence, 4);
    expect(operationLogs.single.etag, 'phone-op-v4');
  });

  test('ignores cross-origin absolute WebDAV hrefs in listings', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>https://evil.example.test/dav/repapertodo/snapshots/snapshot-20260703T090000000Z-evil-seq-000000000009.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"evil-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/dav/repapertodo/snapshots/snapshot-20260703T100000000Z-query-seq-000000000010.json?download=1</D:href>
    <D:propstat>
      <D:prop><D:getetag>"query-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/other/repapertodo/snapshots/snapshot-20260703T110000000Z-other-seq-000000000011.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"other-v11"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/dav/repapertodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>https://evil.example.test/dav/repapertodo/ops/evil-000000000009.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"evil-op-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/dav/repapertodo/ops/query-device-000000000010.jsonl#download</D:href>
    <D:propstat>
      <D:prop><D:getetag>"query-op-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/other/repapertodo/ops/other-device-000000000011.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"other-op-v11"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/dav/repapertodo/ops/phone-device-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-op-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(operationLogs, hasLength(1));
    expect(operationLogs.single.deviceId, 'phone-device');
    expect(operationLogs.single.sequence, 4);
    expect(operationLogs.single.etag, 'phone-op-v4');
  });

  test('ignores network-path WebDAV hrefs in listings', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>//evil.example.test/dav/repapertodo/snapshots/snapshot-20260703T090000000Z-evil-seq-000000000009.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"evil-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>//evil.example.test/dav/repapertodo/ops/evil-device-000000000009.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"evil-op-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo/ops/phone-device-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-op-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(operationLogs, hasLength(1));
    expect(operationLogs.single.deviceId, 'phone-device');
    expect(operationLogs.single.sequence, 4);
    expect(operationLogs.single.etag, 'phone-op-v4');
  });

  test('ignores encoded absolute-looking WebDAV hrefs in listings', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>%2F%2Fevil.example.test%2Fdav%2Frepapertodo%2Fsnapshots%2Fsnapshot-20260703T090000000Z-network-path-seq-000000000009.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"network-path-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https%3A%2F%2Fevil.example.test%2Fdav%2Frepapertodo%2Fsnapshots%2Fsnapshot-20260703T100000000Z-absolute-seq-000000000010.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"absolute-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>%2F%2Fevil.example.test%2Fdav%2Frepapertodo%2Fops%2Fnetwork-path-000000000009.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"network-path-op-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https%3A%2F%2Fevil.example.test%2Fdav%2Frepapertodo%2Fops%2Fabsolute-device-000000000010.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"absolute-op-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo/ops/phone-device-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-op-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(operationLogs, hasLength(1));
    expect(operationLogs.single.deviceId, 'phone-device');
    expect(operationLogs.single.sequence, 4);
    expect(operationLogs.single.etag, 'phone-op-v4');
  });

  test('ignores prefixed relative WebDAV hrefs outside the sync root',
      () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>other/repapertodo/snapshots/snapshot-20260703T090000000Z-prefixed-seq-000000000009.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"prefixed-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>other/repapertodo/ops/prefixed-device-000000000009.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"prefixed-op-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/ops/phone-device-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-op-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(operationLogs, hasLength(1));
    expect(operationLogs.single.deviceId, 'phone-device');
    expect(operationLogs.single.sequence, 4);
    expect(operationLogs.single.etag, 'phone-op-v4');
  });

  test('ignores WebDAV hrefs with encoded path separators in listings',
      () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>repapertodo%2Fsnapshots%2Fsnapshot-20260703T090000000Z-relative-seq-000000000009.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"relative-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav%2Frepapertodo/snapshots/snapshot-20260703T100000000Z-server-seq-000000000010.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"server-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>repapertodo%2Fops%2Frelative-device-000000000009.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"relative-op-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav%2Frepapertodo/ops/server-device-000000000010.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"server-op-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/ops/phone-device-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-op-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(operationLogs, hasLength(1));
    expect(operationLogs.single.deviceId, 'phone-device');
    expect(operationLogs.single.sequence, 4);
    expect(operationLogs.single.etag, 'phone-op-v4');
  });

  test('ignores WebDAV hrefs with collapsible blank path segments in listings',
      () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>repapertodo/%20/snapshots/snapshot-20260703T090000000Z-relative-seq-000000000009.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"relative-blank-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo//snapshots/snapshot-20260703T093000000Z-relative-empty-seq-000000000011.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"relative-empty-v11"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo/%20/snapshots/snapshot-20260703T100000000Z-server-seq-000000000010.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"server-blank-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo//snapshots/snapshot-20260703T103000000Z-server-empty-seq-000000000012.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"server-empty-v12"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>repapertodo/%20/ops/relative-blank-000000000009.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"relative-blank-op-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo//ops/relative-empty-000000000011.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"relative-empty-op-v11"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo/%20/ops/server-blank-000000000010.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"server-blank-op-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo//ops/server-empty-000000000012.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"server-empty-op-v12"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/ops/phone-device-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-op-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(operationLogs, hasLength(1));
    expect(operationLogs.single.deviceId, 'phone-device');
    expect(operationLogs.single.sequence, 4);
    expect(operationLogs.single.etag, 'phone-op-v4');
  });

  test('ignores WebDAV hrefs with encoded control characters in listings',
      () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>repapertodo/snapshots/snapshot-20260703T090000000Z-nul%00device-seq-000000000009.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"nul-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo/snapshots/snapshot-20260703T100000000Z-del%7Fdevice-seq-000000000010.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"del-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>repapertodo/ops/nul%00device-000000000009.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"nul-op-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/repapertodo/ops/del%7Fdevice-000000000010.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"del-op-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/ops/phone-device-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-op-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(operationLogs, hasLength(1));
    expect(operationLogs.single.deviceId, 'phone-device');
    expect(operationLogs.single.sequence, 4);
    expect(operationLogs.single.etag, 'phone-op-v4');
  });

  test(
      'ignores WebDAV hrefs with edge-spaced decoded path segments in listings',
      () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/dav/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>repapertodo%20/snapshots/snapshot-20260703T090000000Z-root-seq-000000000009.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"root-edge-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/%20snapshots/snapshot-20260703T100000000Z-collection-seq-000000000010.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"collection-edge-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/snapshots/%20snapshot-20260703T110000000Z-file-seq-000000000011.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"file-edge-v11"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/snapshots/snapshot-20260702T090000000Z-phone-seq-000000000004.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>repapertodo%20/ops/root-edge-000000000009.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"root-edge-op-v9"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/%20ops/collection-edge-000000000010.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"collection-edge-op-v10"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/ops/%20file-edge-000000000011.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"file-edge-op-v11"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>repapertodo/ops/phone-device-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop><D:getetag>"phone-op-v4"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final snapshots = await service.listSnapshots();
    final operationLogs = await service.listOperationLogs();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, 'phone');
    expect(snapshots.single.etag, 'phone-v4');
    expect(operationLogs, hasLength(1));
    expect(operationLogs.single.deviceId, 'phone-device');
    expect(operationLogs.single.sequence, 4);
    expect(operationLogs.single.etag, 'phone-op-v4');
  });

  test('lists remote operation logs for merge inputs', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/</D:href>
    <D:propstat>
      <D:prop><D:resourcetype><D:collection /></D:resourcetype></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/win-device-000000000003.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"win-op-v3"</D:getetag>
        <D:getcontentlength>256</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:03:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/android-device-000000000001.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"android-op-v1"</D:getetag>
        <D:getcontentlength>128</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/repapertodo/user/repapertodo/ops/tablet-device-000000000002.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"tablet-op-v2"</D:getetag>
        <D:getcontentlength>192</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:02:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/readme.txt</D:href>
    <D:propstat><D:prop /></D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/zero-device-000000000000.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"zero-op"</D:getetag>
        <D:getcontentlength>512</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 08:00:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/android-device-${maxSyncDeviceSequence + 1}.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"overlong-op"</D:getetag>
        <D:getcontentlength>512</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 08:15:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/!!!-000000000004.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"blank-device-op"</D:getetag>
        <D:getcontentlength>512</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 08:30:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/../snapshots/escaped-device-000000000001.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"escaped-op"</D:getetag>
        <D:getcontentlength>512</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 09:00:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/%2e%2e/snapshots/encoded-device-000000000001.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"encoded-op"</D:getetag>
        <D:getcontentlength>512</D:getcontentlength>
        <D:getlastmodified>Thu, 02 Jul 2026 10:00:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/bad%/bad-device-000000000001.jsonl</D:href>
    <D:propstat><D:prop /></D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final logs = await service.listOperationLogs();

    expect(logs, hasLength(3));
    expect(logs.map((log) => '${log.deviceId}:${log.sequence}'), [
      'android-device:1',
      'tablet-device:2',
      'win-device:3',
    ]);
    expect(
        logs.first.path, 'repapertodo/ops/android-device-000000000001.jsonl');
    expect(logs.first.etag, 'android-op-v1');
    expect(logs.first.contentLength, 128);
    expect(logs.first.lastModifiedUtc, DateTime.utc(2026, 7, 1, 9, 1));
    expect(logs[1].path, 'repapertodo/ops/tablet-device-000000000002.jsonl');
    expect(logs[1].etag, 'tablet-op-v2');
    expect(logs[1].contentLength, 192);
    expect(logs[1].lastModifiedUtc, DateTime.utc(2026, 7, 1, 9, 2));
  });

  test('deduplicates operation log records by normalized device sequence',
      () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/Android-Device-000000000001.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"upper-op-v1"</D:getetag>
        <D:getcontentlength>256</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:02:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/android-device-000000000001.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"canonical-op-v1"</D:getetag>
        <D:getcontentlength>128</D:getcontentlength>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/android-device-000000000002.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"android-op-v2"</D:getetag>
        <D:getcontentlength>192</D:getcontentlength>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final logs = await service.listOperationLogs();

    expect(logs.map((log) => '${log.deviceId}:${log.sequence}'), [
      'android-device:1',
      'android-device:2',
    ]);
    expect(
        logs.first.path, 'repapertodo/ops/android-device-000000000001.jsonl');
    expect(logs.first.etag, 'canonical-op-v1');
    expect(logs.first.contentLength, 128);
    expect(logs.last.path, 'repapertodo/ops/android-device-000000000002.jsonl');
  });

  test('deduplicates operation logs by stable metadata preference', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response(
            '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/ops/android-device-000000000001.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"same-op-v1"</D:getetag>
        <D:getcontentlength>128</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:02:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>https://dav.example.test/remote.php/dav/files/user/repapertodo/ops/android-device-000000000001.jsonl</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"same-op-v1"</D:getetag>
        <D:getcontentlength>384</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''',
            207,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final logs = await service.listOperationLogs();

    expect(logs, hasLength(1));
    expect(
      logs.single.path,
      'repapertodo/ops/android-device-000000000001.jsonl',
    );
    expect(logs.single.deviceId, 'android-device');
    expect(logs.single.sequence, 1);
    expect(logs.single.etag, 'same-op-v1');
    expect(logs.single.contentLength, 128);
    expect(logs.single.lastModifiedUtc, DateTime.utc(2026, 7, 1, 9, 2));
  });

  test('lists no operation logs when the operation collection is missing',
      () async {
    for (final statusCode in const [404, 410]) {
      final webDavClient = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials:
            const WebDavCredentials(username: 'user', password: 'pass'),
        httpClient: MockClient((request) async {
          if (request.method == 'PROPFIND' &&
              request.url.path.endsWith('/repapertodo/ops')) {
            return http.Response('', statusCode);
          }
          return http.Response(
              'unexpected ${request.method} ${request.url}', 500);
        }),
      );
      final service = WebDavStateSyncService(client: webDavClient);

      expect(await service.listOperationLogs(), isEmpty, reason: '$statusCode');
    }
  });

  test('downloads a selected operation log', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/repapertodo/ops/android-device-000000000001.jsonl')) {
          return http.Response(
            [
              jsonEncode({
                'id': 'legacy-android-op',
                'deviceId': ' Wrong Device ',
                'sequence': 99,
                'kind': 'stateSnapshot',
                'createdAtUtc': DateTime.utc(2026, 7, 1, 9).toIso8601String(),
                'payload': {
                  'snapshotPath': 'repapertodo/snapshots/snapshot-android.json',
                },
              }),
              '',
            ].join('\n'),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final operations = await service.downloadOperationLog(
      '/repapertodo/ops/android-device-000000000001.jsonl',
    );

    expect(operations, hasLength(1));
    expect(operations.single.id, 'android-device-1');
    expect(operations.single.deviceId, 'android-device');
    expect(operations.single.sequence, 1);
    expect(operations.single.kind, SyncOperationKind.stateSnapshot);
    expect(operations.single.payload['snapshotPath'],
        'repapertodo/snapshots/snapshot-android.json');
  });

  test('downloads operation logs at the maximum remote sequence', () async {
    final maxOperationLogPath =
        '/repapertodo/ops/android-device-$maxSyncDeviceSequence.jsonl';
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith(maxOperationLogPath)) {
          return http.Response(
            '${jsonEncode({
                  'id': 'legacy-android-op',
                  'deviceId': 'android-device',
                  'sequence': 1,
                  'kind': 'updateSettings',
                  'createdAtUtc': DateTime.utc(2026, 7, 1, 9).toIso8601String(),
                  'payload': const <String, Object?>{},
                })}\n',
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final operations = await service.downloadOperationLog(
      maxOperationLogPath,
    );

    expect(operations, hasLength(1));
    expect(operations.single.id, 'android-device-$maxSyncDeviceSequence');
    expect(operations.single.deviceId, 'android-device');
    expect(operations.single.sequence, maxSyncDeviceSequence);
  });

  test('migrates downloaded legacy plain operation logs to encrypted payloads',
      () async {
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Legacy plain body'},
    );
    final requests = <http.Request>[];
    List<int>? uploadedBytes;
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path
                .endsWith('/repapertodo/ops/device-a-000000000001.jsonl')) {
          return http.Response('${jsonEncode(operation.toJson())}\n', 200);
        }
        if (request.method == 'PUT' &&
            request.url.path
                .endsWith('/repapertodo/ops/device-a-000000000001.jsonl')) {
          uploadedBytes = request.bodyBytes;
          return http.Response('', 204);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final payloadCodec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(2),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      payloadCodec: payloadCodec,
    );

    final downloadResult = await service.downloadOperationLogWithMetadata(
      'repapertodo/ops/device-a-000000000001.jsonl',
    );
    final migrated = await service.migrateLegacyPlainOperationLog(
      const WebDavOperationLogRecord(
        path: 'repapertodo/ops/device-a-000000000001.jsonl',
        deviceId: 'device-a',
        sequence: 1,
        etag: ' op-v1 ',
      ),
      downloadedResult: downloadResult,
    );

    expect(migrated, true);
    expect(downloadResult.payloadFormat, WebDavPayloadFormat.plainJson);
    expect(
      requests.map((request) => request.method),
      ['GET', 'PUT'],
    );
    expect(requests.last.headers['if-match'], '"op-v1"');
    final uploadText = utf8.decode(uploadedBytes ?? const []);
    expect(uploadText, startsWith('RePaperTodo-Encrypted-Payload-v1\n'));
    expect(uploadText, isNot(contains('Legacy plain body')));
    final decodedOperations = await EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
    ).decodeOperationLog(uploadedBytes ?? const []);
    expect(decodedOperations.single.payload, {
      'paperId': 'note',
      'content': 'Legacy plain body',
    });
  });

  test('skips legacy plain operation log migration without a strong ETag',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      payloadCodec: EncryptedWebDavPayloadCodec(
        passphrase: 'shared sync secret',
        kdfIterations: 100000,
      ),
    );

    for (final etag in const <String?>[null, ' ', 'W/"op-v1"', ' w/"op-v1" ']) {
      final migrated = await service.migrateLegacyPlainOperationLog(
        WebDavOperationLogRecord(
          path: 'repapertodo/ops/device-a-000000000001.jsonl',
          deviceId: 'device-a',
          sequence: 1,
          etag: etag,
        ),
        downloadedResult: WebDavOperationLogDownloadResult(
          path: 'repapertodo/ops/device-a-000000000001.jsonl',
          payloadFormat: WebDavPayloadFormat.plainJson,
          operations: [
            SyncOperation(
              id: 'device-a-1',
              deviceId: 'device-a',
              sequence: 1,
              kind: SyncOperationKind.stateSnapshot,
              createdAtUtc: DateTime.utc(2026, 7, 1),
              payload: const {},
            ),
          ],
        ),
      );

      expect(migrated, false, reason: etag.toString());
    }
    expect(requests, isEmpty);
  });

  test('skips legacy plain operation log migration with mismatched identity',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      payloadCodec: EncryptedWebDavPayloadCodec(
        passphrase: 'shared sync secret',
        kdfIterations: 100000,
      ),
    );

    final migrated = await service.migrateLegacyPlainOperationLog(
      const WebDavOperationLogRecord(
        path: 'repapertodo/ops/device-a-000000000001.jsonl',
        deviceId: 'device-b',
        sequence: 2,
        etag: 'op-v1',
      ),
      downloadedResult: WebDavOperationLogDownloadResult(
        path: 'repapertodo/ops/device-a-000000000001.jsonl',
        payloadFormat: WebDavPayloadFormat.plainJson,
        operations: [
          SyncOperation(
            id: 'device-a-1',
            deviceId: 'device-a',
            sequence: 1,
            kind: SyncOperationKind.stateSnapshot,
            createdAtUtc: DateTime.utc(2026, 7, 1),
            payload: const {},
          ),
        ],
      ),
    );

    expect(migrated, false);
    expect(requests, isEmpty);
  });

  test(
      'skips legacy plain operation log migration with mismatched download path',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      payloadCodec: EncryptedWebDavPayloadCodec(
        passphrase: 'shared sync secret',
        kdfIterations: 100000,
      ),
    );

    final migrated = await service.migrateLegacyPlainOperationLog(
      const WebDavOperationLogRecord(
        path: 'repapertodo/ops/device-a-000000000001.jsonl',
        deviceId: 'device-a',
        sequence: 1,
        etag: 'op-v1',
      ),
      downloadedResult: WebDavOperationLogDownloadResult(
        path: 'repapertodo/ops/device-b-000000000001.jsonl',
        payloadFormat: WebDavPayloadFormat.plainJson,
        operations: [
          SyncOperation(
            id: 'device-b-1',
            deviceId: 'device-b',
            sequence: 1,
            kind: SyncOperationKind.stateSnapshot,
            createdAtUtc: DateTime.utc(2026, 7, 1),
            payload: const {},
          ),
        ],
      ),
    );

    expect(migrated, false);
    expect(requests, isEmpty);
  });

  test('skips legacy plain operation log migration for non-plain results',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      payloadCodec: EncryptedWebDavPayloadCodec(
        passphrase: 'shared sync secret',
        kdfIterations: 100000,
      ),
    );
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.stateSnapshot,
      createdAtUtc: DateTime.utc(2026, 7, 1),
      payload: const {},
    );

    for (final result in [
      WebDavOperationLogDownloadResult(
        path: 'repapertodo/ops/device-a-000000000001.jsonl',
        payloadFormat: WebDavPayloadFormat.encrypted,
        operations: [operation],
      ),
      WebDavOperationLogDownloadResult(
        path: 'repapertodo/ops/device-a-000000000001.jsonl',
        payloadFormat: WebDavPayloadFormat.plainJson,
        operations: [operation, operation],
      ),
    ]) {
      final migrated = await service.migrateLegacyPlainOperationLog(
        const WebDavOperationLogRecord(
          path: 'repapertodo/ops/device-a-000000000001.jsonl',
          deviceId: 'device-a',
          sequence: 1,
          etag: 'op-v1',
        ),
        downloadedResult: result,
      );

      expect(migrated, false, reason: result.payloadFormat.name);
    }
    expect(requests, isEmpty);
  });

  test('rejects empty operation logs', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/repapertodo/ops/android-device-000000000001.jsonl')) {
          return http.Response('\n \n', 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadOperationLog(
        '/repapertodo/ops/android-device-000000000001.jsonl',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('exactly one operation'),
        ),
      ),
    );
  });

  test('rejects operation logs with multiple operations', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/repapertodo/ops/android-device-000000000001.jsonl')) {
          return http.Response(
            [
              jsonEncode({
                'id': 'android-device-1',
                'deviceId': 'android-device',
                'sequence': 1,
                'kind': 'stateSnapshot',
                'createdAtUtc': DateTime.utc(2026, 7, 1, 9).toIso8601String(),
                'payload': const <String, Object?>{},
              }),
              jsonEncode({
                'id': 'android-device-1-duplicate',
                'deviceId': 'android-device',
                'sequence': 1,
                'kind': 'updateSettings',
                'createdAtUtc':
                    DateTime.utc(2026, 7, 1, 9, 1).toIso8601String(),
                'payload': const <String, Object?>{},
              }),
            ].join('\n'),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadOperationLog(
        '/repapertodo/ops/android-device-000000000001.jsonl',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('exactly one operation'),
        ),
      ),
    );
  });

  test('rejects operation logs with unknown operation kinds', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/repapertodo/ops/android-device-000000000001.jsonl')) {
          return http.Response(
            '${jsonEncode({
                  'id': 'android-device-1',
                  'deviceId': 'android-device',
                  'sequence': 1,
                  'kind': 'futureOperation',
                  'createdAtUtc': DateTime.utc(2026, 7, 1, 9).toIso8601String(),
                  'payload': const <String, Object?>{},
                })}\n',
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadOperationLog(
        '/repapertodo/ops/android-device-000000000001.jsonl',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unknown sync operation kind'),
        ),
      ),
    );
  });

  test('rejects operation logs with invalid operation sequences', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/repapertodo/ops/android-device-000000000001.jsonl')) {
          return http.Response(
            '${jsonEncode({
                  'id': 'android-device-1',
                  'deviceId': 'android-device',
                  'sequence': maxSyncDeviceSequence + 1,
                  'kind': 'updateSettings',
                  'createdAtUtc': DateTime.utc(2026, 7, 1, 9).toIso8601String(),
                  'payload': const <String, Object?>{},
                })}\n',
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadOperationLog(
        '/repapertodo/ops/android-device-000000000001.jsonl',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('sequence must be a positive integer no greater than'),
        ),
      ),
    );
  });

  test('rejects operation logs with invalid operation timestamps', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/repapertodo/ops/android-device-000000000001.jsonl')) {
          return http.Response(
            '${jsonEncode({
                  'id': 'android-device-1',
                  'deviceId': 'android-device',
                  'sequence': 1,
                  'kind': 'updateSettings',
                  'createdAtUtc': 'not-a-date',
                  'payload': const <String, Object?>{},
                })}\n',
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadOperationLog(
        '/repapertodo/ops/android-device-000000000001.jsonl',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('createdAtUtc must be valid'),
        ),
      ),
    );
  });

  test('rejects operation logs with invalid operation payloads', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/repapertodo/ops/android-device-000000000001.jsonl')) {
          return http.Response(
            '${jsonEncode({
                  'id': 'android-device-1',
                  'deviceId': 'android-device',
                  'sequence': 1,
                  'kind': 'updateSettings',
                  'createdAtUtc': DateTime.utc(2026, 7, 1, 9).toIso8601String(),
                  'payload': 'bad-payload',
                })}\n',
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadOperationLog(
        '/repapertodo/ops/android-device-000000000001.jsonl',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('payload must be a JSON object'),
        ),
      ),
    );
  });

  test('uploads prepared operation logs and advances device sequences',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.uploadOperationLogs(
      [
        SyncOperation(
          id: 'covered',
          deviceId: 'Device A',
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9),
          payload: {'paperId': 'note', 'content': 'Covered'},
        ),
        SyncOperation(
          id: 'new-note',
          deviceId: 'Device A',
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 1),
          payload: {'paperId': 'note', 'content': 'Fresh'},
        ),
        SyncOperation(
          id: 'android-1',
          deviceId: 'android-device',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 2),
          payload: {
            'paper': PaperData(
              id: 'paper-android',
              type: PaperTypes.note,
              title: 'Android',
            ).toJson(),
          },
        ),
        SyncOperation(
          id: 'invalid',
          deviceId: '',
          sequence: 3,
          kind: SyncOperationKind.deletePaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 3),
          payload: {'paperId': 'ignored'},
        ),
        SyncOperation(
          id: 'short-invalid-device',
          deviceId: 'bad',
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 4),
          payload: {'paperId': 'note', 'content': 'Ignored'},
        ),
      ],
      previousDeviceSequences: {' Device A ': 1},
    );

    expect(result.uploadedCount, 2);
    expect(result.deviceSequences, {
      'device-a': 2,
      'android-device': 1,
    });
    expect(result.acceptedDeviceSequences, {
      'device-a': 2,
      'android-device': 1,
    });
    expect(
      requests.map((request) => request.method),
      ['MKCOL', 'MKCOL', 'MKCOL', 'PUT', 'PUT'],
    );

    final operationRequests =
        requests.where((request) => request.method == 'PUT').toList();
    expect(
      operationRequests.map((request) => request.headers['if-none-match']),
      ['*', '*'],
    );
    expect(operationRequests.map((request) => request.url.path), [
      '/remote.php/dav/files/user/repapertodo/ops/android-device-000000000001.jsonl',
      '/remote.php/dav/files/user/repapertodo/ops/device-a-000000000002.jsonl',
    ]);

    final androidOperation = jsonDecode(
      utf8.decode(operationRequests.first.bodyBytes).trim(),
    ) as Map<String, Object?>;
    expect(androidOperation['id'], 'android-device-1');
    expect(androidOperation['kind'], 'upsertPaper');
    expect(androidOperation['deviceId'], 'android-device');
    expect(androidOperation['sequence'], 1);

    final noteOperation = jsonDecode(
      utf8.decode(operationRequests.last.bodyBytes).trim(),
    ) as Map<String, Object?>;
    expect(noteOperation['id'], 'device-a-2');
    expect(noteOperation['kind'], 'updateNoteContent');
    expect(noteOperation['deviceId'], 'device-a');
    expect(noteOperation['sequence'], 2);
    expect(noteOperation['payload'], {
      'paperId': 'note',
      'content': 'Fresh',
    });
  });

  test('skips operation logs outside the remote sequence range before upload',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.uploadOperationLogs(
      [
        SyncOperation(
          id: 'max-device-${maxSyncDeviceSequence + 1}',
          deviceId: 'max-device',
          sequence: maxSyncDeviceSequence + 1,
          kind: SyncOperationKind.updateNoteContent,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9),
          payload: {'paperId': 'note', 'content': 'Too far'},
        ),
      ],
      previousDeviceSequences: {'max-device': maxSyncDeviceSequence},
    );

    expect(result.uploadedCount, 0);
    expect(result.deviceSequences, {'max-device': maxSyncDeviceSequence});
    expect(result.acceptedDeviceSequences, isEmpty);
    expect(requests, isEmpty);
  });

  test('skips conflicting duplicate operation sequences before upload',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.uploadOperationLogs([
      SyncOperation(
        id: 'device-a-1',
        deviceId: 'device-a',
        sequence: 1,
        kind: SyncOperationKind.updateNoteContent,
        createdAtUtc: DateTime.utc(2026, 7, 1, 9),
        payload: {'paperId': 'note', 'content': 'First'},
      ),
      SyncOperation(
        id: 'device-a-1-conflict',
        deviceId: 'device-a',
        sequence: 1,
        kind: SyncOperationKind.updateNoteContent,
        createdAtUtc: DateTime.utc(2026, 7, 1, 9),
        payload: {'paperId': 'note', 'content': 'Conflicting'},
      ),
    ]);

    expect(result.uploadedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.acceptedDeviceSequences, isEmpty);
    expect(requests, isEmpty);
  });

  test('uploads matching duplicate operation sequences once', () async {
    final requests = <http.Request>[];
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Fresh'},
    );
    final duplicate = SyncOperation.fromJson(operation.toJson());
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.uploadOperationLogs([operation, duplicate]);

    expect(result.uploadedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.acceptedDeviceSequences, {'device-a': 1});
    expect(
      requests.map((request) => request.method),
      ['MKCOL', 'MKCOL', 'MKCOL', 'PUT'],
    );
    expect(
      requests.where((request) => request.method == 'PUT').single.url.path,
      '/remote.php/dav/files/user/repapertodo/ops/device-a-000000000001.jsonl',
    );
  });

  test('accepts matching existing operation logs during upload retry',
      () async {
    final requests = <http.Request>[];
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Fresh'},
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
          return http.Response('already exists', 412);
        }
        if (request.method == 'GET' && request.url.path.contains('/ops/')) {
          return http.Response('${jsonEncode(operation.toJson())}\n', 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.uploadOperationLogs([operation]);

    expect(result.uploadedCount, 0);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.acceptedDeviceSequences, {'device-a': 1});
    expect(
      requests
          .where((request) => request.url.path.contains('/ops/'))
          .map((request) => request.method),
      ['PUT', 'GET'],
    );
  });

  test('accepts matching existing operation logs after provider conflict',
      () async {
    final requests = <http.Request>[];
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Fresh'},
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
          return http.Response('already exists', 409);
        }
        if (request.method == 'GET' && request.url.path.contains('/ops/')) {
          return http.Response('${jsonEncode(operation.toJson())}\n', 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.uploadOperationLogs([operation]);

    expect(result.uploadedCount, 0);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.acceptedDeviceSequences, {'device-a': 1});
    expect(
      requests
          .where((request) => request.url.path.contains('/ops/'))
          .map((request) => request.method),
      ['PUT', 'GET'],
    );
  });

  test(
      'preserves operation provider conflicts when existing content is unreadable',
      () async {
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Fresh'},
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
          return http.Response('already exists', 409);
        }
        if (request.method == 'GET' && request.url.path.contains('/ops/')) {
          return http.Response('not json', 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.uploadOperationLogs([operation]),
      throwsA(isA<WebDavException>()
          .having((error) => error.statusCode, 'statusCode', 409)),
    );
  });

  test('accepts matching encrypted operation logs during upload retry',
      () async {
    final requests = <http.Request>[];
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Fresh'},
    );
    final existingOperationBytes = await EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(1),
    ).encodeOperationLog(operation);
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
          expect(
            const ListEquality<int>().equals(
              request.bodyBytes,
              existingOperationBytes,
            ),
            false,
          );
          return http.Response('already exists', 412);
        }
        if (request.method == 'GET' && request.url.path.contains('/ops/')) {
          return http.Response.bytes(existingOperationBytes, 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      payloadCodec: EncryptedWebDavPayloadCodec(
        passphrase: 'shared sync secret',
        kdfIterations: 100000,
        random: Random(2),
      ),
    );

    final result = await service.uploadOperationLogs([operation]);

    expect(result.uploadedCount, 0);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.acceptedDeviceSequences, {'device-a': 1});
    expect(
      requests
          .where((request) => request.url.path.contains('/ops/'))
          .map((request) => request.method),
      ['PUT', 'GET'],
    );
  });

  test('counts only newly created operation logs during mixed upload retry',
      () async {
    final requests = <http.Request>[];
    final existingOperation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'First'},
    );
    final newOperation = SyncOperation(
      id: 'device-a-2',
      deviceId: 'device-a',
      sequence: 2,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9, 1),
      payload: {'paperId': 'note', 'content': 'Second'},
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/ops/device-a-000000000001.jsonl')) {
          return http.Response('already exists', 412);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/ops/device-a-000000000001.jsonl')) {
          return http.Response(
              '${jsonEncode(existingOperation.toJson())}\n', 200);
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/ops/device-a-000000000002.jsonl')) {
          return http.Response('', 201);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.uploadOperationLogs([
      existingOperation,
      newOperation,
    ]);

    expect(result.uploadedCount, 1);
    expect(result.deviceSequences, {'device-a': 2});
    expect(result.acceptedDeviceSequences, {'device-a': 2});
    expect(
      requests
          .where((request) => request.url.path.contains('/ops/'))
          .map((request) => request.method),
      ['PUT', 'GET', 'PUT'],
    );
  });

  test('rejects conflicting existing operation logs during upload retry',
      () async {
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Fresh'},
    );
    final existingOperation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Different'},
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT' && request.url.path.contains('/ops/')) {
          return http.Response('already exists', 412);
        }
        if (request.method == 'GET' && request.url.path.contains('/ops/')) {
          return http.Response(
            '${jsonEncode(existingOperation.toJson())}\n',
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    await expectLater(
      service.uploadOperationLogs([operation]),
      throwsA(isA<WebDavException>()),
    );
  });

  test('uploads only contiguous operation logs per device', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.uploadOperationLogs(
      [
        SyncOperation(
          id: 'device-a-1',
          deviceId: 'device-a',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9),
          payload: {
            'paper': PaperData(
              id: 'device-a-first',
              type: PaperTypes.note,
              title: 'Device A first',
            ).toJson(),
          },
        ),
        SyncOperation(
          id: 'device-a-3',
          deviceId: 'device-a',
          sequence: 3,
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 1),
          payload: {
            'paper': PaperData(
              id: 'device-a-third',
              type: PaperTypes.note,
              title: 'Device A third',
            ).toJson(),
          },
        ),
        SyncOperation(
          id: 'device-b-1',
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 2),
          payload: {
            'paper': PaperData(
              id: 'device-b-first',
              type: PaperTypes.note,
              title: 'Device B first',
            ).toJson(),
          },
        ),
      ],
    );

    expect(result.uploadedCount, 2);
    expect(result.deviceSequences, {'device-a': 1, 'device-b': 1});
    expect(result.acceptedDeviceSequences, {
      'device-a': 1,
      'device-b': 1,
    });
    final operationRequests =
        requests.where((request) => request.method == 'PUT').toList();
    expect(
      operationRequests.map((request) => request.headers['if-none-match']),
      ['*', '*'],
    );
    expect(operationRequests.map((request) => request.url.path), [
      '/remote.php/dav/files/user/repapertodo/ops/device-a-000000000001.jsonl',
      '/remote.php/dav/files/user/repapertodo/ops/device-b-000000000001.jsonl',
    ]);
  });

  test(
      'deduplicates matching upload candidates and blocks conflicts per device',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);
    final firstAndroidOperation = SyncOperation(
      id: 'android-device-1-a',
      deviceId: 'android-device',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Fresh'},
    );
    final duplicateAndroidOperation = SyncOperation(
      id: 'android-device-1-b',
      deviceId: 'android-device',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'note', 'content': 'Fresh'},
    );

    final result = await service.uploadOperationLogs(
      [
        SyncOperation(
          id: 'device-a-1',
          deviceId: 'device-a',
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9),
          payload: {'paperId': 'note', 'content': 'First'},
        ),
        SyncOperation(
          id: 'device-a-1-conflict',
          deviceId: 'device-a',
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9),
          payload: {'paperId': 'note', 'content': 'Different'},
        ),
        SyncOperation(
          id: 'device-a-2',
          deviceId: 'device-a',
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 1),
          payload: {'paperId': 'note', 'content': 'Blocked'},
        ),
        firstAndroidOperation,
        duplicateAndroidOperation,
        SyncOperation(
          id: 'android-device-2',
          deviceId: 'android-device',
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 2),
          payload: {'paperId': 'note', 'content': 'Next'},
        ),
      ],
    );

    expect(result.uploadedCount, 2);
    expect(result.deviceSequences, {'android-device': 2});
    expect(result.acceptedDeviceSequences, {'android-device': 2});
    final operationRequests =
        requests.where((request) => request.method == 'PUT').toList();
    expect(operationRequests.map((request) => request.url.path), [
      '/remote.php/dav/files/user/repapertodo/ops/android-device-000000000001.jsonl',
      '/remote.php/dav/files/user/repapertodo/ops/android-device-000000000002.jsonl',
    ]);
  });

  test('downloads a selected snapshot for recovery', () async {
    const codec = AppStateCodec();
    final snapshotState = AppState(
      papers: [
        PaperData(
          id: 'snapshot-paper',
          type: PaperTypes.note,
          title: 'Recovered snapshot',
        ),
      ],
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith(
                '/repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json')) {
          return http.Response(codec.encode(snapshotState), 200);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.downloadSnapshot(
      '/repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json',
    );

    expect(result.status, WebDavStateSyncStatus.downloaded);
    expect(result.snapshotPath,
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json');
    expect(result.state?.papers.single.title, 'Recove');
  });

  test('rejects snapshot downloads outside the snapshot collection', () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadSnapshot('repapertodo/manifest.json'),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/../other/snapshot-20260701T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/%2e%2e/other/snapshot-20260701T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/bad%/snapshot-20260701T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/%0Aother/snapshot-20260701T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/%20/snapshot-20260701T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots//snapshot-20260701T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/archive/snapshot-20260701T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots%2Fsnapshot-20260701T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/%20snapshot-20260701T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json%20',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/snapshot-20260701T090000000Z-!!!.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/snapshot-20261301T090000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/snapshot-20260701T240000000Z-phone.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone-seq-000000000000.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadSnapshot(
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone-seq-${maxSyncDeviceSequence + 1}.json',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test('rejects operation log downloads outside the operation collection',
      () async {
    final requests = <http.Request>[];
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadOperationLog('repapertodo/snapshots/local.json'),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/../snapshots/android-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/%2e%2e/snapshots/android-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/bad%/android-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/%0Aother/android-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/%20/android-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/%20android-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/android-device-000000000001.jsonl%20',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops//android-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/archive/android-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops%2Fandroid-device-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/android-device-000000000000.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/android-device-${maxSyncDeviceSequence + 1}.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(
      service.downloadOperationLog(
        'repapertodo/ops/!!!-000000000001.jsonl',
      ),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
    expect(requests, isEmpty);
  });

  test('uses the payload codec for snapshots and operation logs', () async {
    final requests = <http.Request>[];
    final remoteSnapshotState = AppState(
      papers: [
        PaperData(
          id: 'remote-note',
          type: PaperTypes.note,
          title: 'Tagged',
        ),
      ],
    );
    final remoteOperation = SyncOperation(
      id: 'ignored',
      deviceId: 'ignored-device',
      sequence: 99,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
      payload: {'paperId': 'remote-note', 'content': 'Decoded'},
    );
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT') {
          return http.Response('', 201);
        }
        if (request.method == 'GET' &&
            request.url.path.contains('/snapshots/')) {
          return http.Response(
            _TaggedWebDavPayloadCodec.snapshotText(remoteSnapshotState),
            200,
          );
        }
        if (request.method == 'GET' && request.url.path.contains('/ops/')) {
          return http.Response(
            _TaggedWebDavPayloadCodec.operationText(remoteOperation),
            200,
          );
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(
      client: webDavClient,
      payloadCodec: const _TaggedWebDavPayloadCodec(),
      deviceId: 'device-a',
    );

    await service.push(
      AppState(
        papers: [
          PaperData(id: 'local-note', type: PaperTypes.note, title: 'Local'),
        ],
      ),
      updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
    );
    final downloadedSnapshot = await service.downloadSnapshot(
      'repapertodo/snapshots/snapshot-20260701T090000000Z-device-a.json',
    );
    final downloadedOperations = await service.downloadOperationLog(
      'repapertodo/ops/device-a-000000000001.jsonl',
    );

    final snapshotUpload = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.contains('/snapshots/'));
    final operationUpload = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.contains('/ops/'));
    expect(utf8.decode(snapshotUpload.bodyBytes), startsWith('snapshot:'));
    expect(utf8.decode(operationUpload.bodyBytes), startsWith('operation:'));
    expect(downloadedSnapshot.state?.papers.single.title, 'Tagged');
    expect(downloadedOperations.single.id, 'device-a-1');
    expect(downloadedOperations.single.deviceId, 'device-a');
    expect(downloadedOperations.single.sequence, 1);
    expect(downloadedOperations.single.payload, {
      'paperId': 'remote-note',
      'content': 'Decoded',
    });
  });

  test('encrypts payloads from configured WebDAV settings', () async {
    final requests = <http.Request>[];
    final service = WebDavStateSyncService.fromSettings(
      WebDavSyncSettings(
        endpoint: 'https://dav.example.test/remote.php/dav/files/user/',
        username: 'user',
        password: 'pass',
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
      ),
      deviceId: 'device-a',
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );

    await service.push(
      AppState(
        papers: [
          PaperData(
            id: 'secret-note',
            type: PaperTypes.note,
            title: 'Secret',
            content: 'Encrypted over WebDAV',
          ),
        ],
      ),
      updatedAtUtc: DateTime.utc(2026, 7, 2, 10),
    );

    final snapshotRequest = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.contains('/snapshots/'));
    final snapshotText = utf8.decode(snapshotRequest.bodyBytes);
    expect(snapshotText, startsWith('RePaperTodo-Encrypted-Payload-v1\n'));
    expect(snapshotText, isNot(contains('Encrypted over WebDAV')));

    final decodedState = await EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
    ).decodeSnapshot(snapshotRequest.bodyBytes, const AppStateCodec());
    expect(decodedState.papers.single.content, 'Encrypted over WebDAV');
  });

  test('rejects configured WebDAV endpoints with encoded control characters',
      () {
    for (final endpoint in const [
      'https://dav.example.test/remote.php/dav/%0Afiles/user/',
      'https://dav.example.test/remote.php/dav/%7Ffiles/user/',
    ]) {
      var requestCount = 0;

      expect(
        () => WebDavStateSyncService.fromSettings(
          WebDavSyncSettings(
            endpoint: endpoint,
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
          deviceId: 'device-a',
          httpClient: MockClient((request) async {
            requestCount += 1;
            return http.Response('network should not be reached', 500);
          }),
        ),
        throwsA(isA<WebDavSyncConfigurationException>()),
        reason: endpoint,
      );
      expect(requestCount, 0, reason: endpoint);
    }
  });

  test('rejects configured WebDAV credentials with unsafe characters', () {
    for (final settings in [
      WebDavSyncSettings(
        endpoint: 'https://dav.example.test/remote.php/dav/files/user/',
        username: 'user:name',
        password: 'pass',
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
      ),
      WebDavSyncSettings(
        endpoint: 'https://dav.example.test/remote.php/dav/files/user/',
        username: 'user',
        password: 'bad\npass',
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
      ),
    ]) {
      expect(
        () => WebDavStateSyncService.fromSettings(
          settings,
          deviceId: 'device-a',
          httpClient: MockClient((request) async {
            return http.Response('network should not be reached', 500);
          }),
        ),
        throwsA(isA<WebDavSyncConfigurationException>()),
      );
    }
  });

  test('rejects configured WebDAV root paths with encoded control characters',
      () {
    for (final rootPath in const [
      'repapertodo/%0Aother',
      'repapertodo/%7Fother',
    ]) {
      var requestCount = 0;

      expect(
        () => WebDavStateSyncService.fromSettings(
          WebDavSyncSettings(
            endpoint: 'https://dav.example.test/remote.php/dav/files/user/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: rootPath,
          ),
          deviceId: 'device-a',
          httpClient: MockClient((request) async {
            requestCount += 1;
            return http.Response('network should not be reached', 500);
          }),
        ),
        throwsA(isA<WebDavSyncConfigurationException>()),
        reason: rootPath,
      );
      expect(requestCount, 0, reason: rootPath);
    }
  });

  test('uses configured WebDAV request timeout seconds', () async {
    final service = WebDavStateSyncService.fromSettings(
      WebDavSyncSettings(
        endpoint: 'https://dav.example.test/remote.php/dav/files/user/',
        username: 'user',
        password: 'pass',
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        requestTimeoutSeconds: 1,
      ),
      deviceId: 'test-device',
      httpClient: MockClient((request) => Completer<http.Response>().future),
    );

    await expectLater(
      service.pull(),
      throwsA(
        isA<WebDavException>()
            .having((error) => error.statusCode, 'statusCode', 0)
            .having(
              (error) => error.message,
              'message',
              'WebDAV request timed out after 1s.',
            ),
      ),
    );
  });

  test('creates a sync service from Jianguoyun WebDAV settings', () async {
    final requests = <http.Request>[];
    final service = WebDavStateSyncService.fromSettings(
      WebDavSyncSettings.jianguoyun(
        username: 'user@example.com',
        password: 'app-password',
      ),
      deviceId: 'test-device',
      httpClient: MockClient((request) async {
        requests.add(request);
        return switch (request.method) {
          'MKCOL' => http.Response('', 201),
          'PUT' => http.Response('', 201),
          _ => http.Response('unexpected ${request.method}', 500),
        };
      }),
    );

    final result = await service.push(AppState());

    expect(result.status, WebDavStateSyncStatus.uploaded);
    expect(requests.first.url.toString(),
        'https://dav.jianguoyun.com/dav/RePaperTodo');
    expect(
      requests
          .where((request) => request.method == 'PUT')
          .map((request) => request.url.path),
      contains('/dav/RePaperTodo/manifest.json'),
    );
  });
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

class _TaggedWebDavPayloadCodec implements WebDavPayloadCodec {
  const _TaggedWebDavPayloadCodec();

  static String snapshotText(AppState state) {
    return 'snapshot:${const AppStateCodec().encodeRemoteSnapshot(state)}';
  }

  static String operationText(SyncOperation operation) {
    return 'operation:${jsonEncode(operation.toJson())}\n';
  }

  @override
  WebDavPayloadFormat inspectPayloadFormat(List<int> bytes) {
    return WebDavPayloadFormat.unknown;
  }

  @override
  AppState decodeSnapshot(List<int> bytes, AppStateCodec appStateCodec) {
    final text = utf8.decode(bytes);
    if (!text.startsWith('snapshot:')) {
      throw const FormatException('Missing tagged snapshot prefix.');
    }
    return appStateCodec.decode(text.substring('snapshot:'.length));
  }

  @override
  List<SyncOperation> decodeOperationLog(List<int> bytes) {
    final lines = utf8
        .decode(bytes)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return [
      for (final line in lines) _decodeOperation(line),
    ];
  }

  @override
  List<int> encodeOperationLog(SyncOperation operation) {
    return utf8.encode(operationText(operation));
  }

  @override
  List<int> encodeSnapshot(AppState state, AppStateCodec appStateCodec) {
    return utf8.encode('snapshot:${appStateCodec.encodeRemoteSnapshot(state)}');
  }

  SyncOperation _decodeOperation(String line) {
    if (!line.startsWith('operation:')) {
      throw const FormatException('Missing tagged operation prefix.');
    }
    final decoded = jsonDecode(line.substring('operation:'.length));
    if (decoded is! Map) {
      throw const FormatException('Tagged operation must be a JSON object.');
    }
    return SyncOperation.fromJson(Map<String, Object?>.from(decoded));
  }
}
