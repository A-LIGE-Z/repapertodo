import 'dart:convert';

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
            '/snapshots/snapshot-20260630T100000000Z-test-device.json'));
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
          'repapertodo/snapshots/snapshot-20260630T100000000Z-test-device.json',
      'paperCount': 1,
    });

    final manifestRequest = requests.firstWhere((request) =>
        request.method == 'PUT' && request.url.path.endsWith('/manifest.json'));
    final manifest = jsonDecode(utf8.decode(manifestRequest.bodyBytes))
        as Map<String, Object?>;
    expect(
      manifest['latestSnapshotPath'],
      'repapertodo/snapshots/snapshot-20260630T100000000Z-test-device.json',
    );
    expect(
      result.snapshotPath,
      'repapertodo/snapshots/snapshot-20260630T100000000Z-test-device.json',
    );
    expect(manifest['updatedAtUtc'], '2026-06-30T10:00:00.000Z');
    expect(manifest['deviceSequences'], {'test-device': 1});
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
        if (request.method == 'GET' &&
            request.url.path.endsWith('/state.json')) {
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
    expect(result.snapshotPath, 'repapertodo/state.json');
    expect(result.state?.papers.single.title, 'Remote');
    expect(result.state?.papers.single.content, 'From WebDAV');
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
      'repapertodo/snapshots/snapshot-20260701T000000000Z-test-device.json',
    );
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
    <D:href>/remote.php/dav/files/user/repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"phone-v1"</D:getetag>
        <D:getcontentlength>2048</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
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
    expect(snapshots.map((snapshot) => snapshot.deviceId), [
      'phone',
      'win-device',
    ]);
    expect(snapshots.first.path,
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json');
    expect(snapshots.first.updatedAtUtc, DateTime.utc(2026, 7, 1, 9));
    expect(snapshots.first.etag, 'phone-v1');
    expect(snapshots.first.contentLength, 2048);
    expect(snapshots.first.lastModifiedUtc, DateTime.utc(2026, 7, 1, 9, 1));
  });

  test('lists no snapshots when the snapshot collection is missing', () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/snapshots')) {
          return http.Response('', 404);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(await service.listSnapshots(), isEmpty);
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
    <D:href>/remote.php/dav/files/user/repapertodo/ops/readme.txt</D:href>
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

    expect(logs, hasLength(2));
    expect(logs.map((log) => '${log.deviceId}:${log.sequence}'), [
      'android-device:1',
      'win-device:3',
    ]);
    expect(
        logs.first.path, 'repapertodo/ops/android-device-000000000001.jsonl');
    expect(logs.first.etag, 'android-op-v1');
    expect(logs.first.contentLength, 128);
    expect(logs.first.lastModifiedUtc, DateTime.utc(2026, 7, 1, 9, 1));
  });

  test('lists no operation logs when the operation collection is missing',
      () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'PROPFIND' &&
            request.url.path.endsWith('/repapertodo/ops')) {
          return http.Response('', 404);
        }
        return http.Response(
            'unexpected ${request.method} ${request.url}', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(await service.listOperationLogs(), isEmpty);
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
      throwsA(isA<FormatException>()),
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
      ],
      previousDeviceSequences: {' Device A ': 1},
    );

    expect(result.uploadedCount, 2);
    expect(result.deviceSequences, {
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
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadSnapshot('repapertodo/manifest.json'),
      throwsA(isA<WebDavSyncConfigurationException>()),
    );
  });

  test('rejects operation log downloads outside the operation collection',
      () async {
    final webDavClient = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        return http.Response('network should not be reached', 500);
      }),
    );
    final service = WebDavStateSyncService(client: webDavClient);

    expect(
      service.downloadOperationLog('repapertodo/snapshots/local.json'),
      throwsA(isA<WebDavSyncConfigurationException>()),
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
