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
      ['MKCOL', 'MKCOL', 'PUT', 'PUT'],
    );

    final snapshotRequest = requests.firstWhere((request) =>
        request.method == 'PUT' &&
        request.url.path.endsWith(
            '/snapshots/snapshot-20260630T100000000Z-test-device.json'));
    final snapshot = jsonDecode(utf8.decode(snapshotRequest.bodyBytes))
        as Map<String, Object?>;
    final papers = snapshot['papers'] as List<Object?>;
    expect((papers.single as Map<String, Object?>)['title'], 'Sync me');

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
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/manifest.json')) {
          expect(request.headers['if-match'], '"manifest-v1"');
          return http.Response('precondition failed', 412);
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
