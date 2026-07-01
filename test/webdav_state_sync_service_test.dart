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
    expect(result.manifest?.deviceSequences, {
      'other-device': 2,
      'test-device': 5,
    });
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
