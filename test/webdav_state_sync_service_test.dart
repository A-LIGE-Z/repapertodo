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
    final service = WebDavStateSyncService(client: webDavClient);

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
    expect(requests.map((request) => request.method), ['MKCOL', 'PUT', 'PUT']);

    final snapshotRequest = requests
        .firstWhere((request) => request.url.path.endsWith('/state.json'));
    final snapshot = jsonDecode(utf8.decode(snapshotRequest.bodyBytes))
        as Map<String, Object?>;
    final papers = snapshot['papers'] as List<Object?>;
    expect((papers.single as Map<String, Object?>)['title'], 'Sync me');

    final manifestRequest = requests
        .firstWhere((request) => request.url.path.endsWith('/manifest.json'));
    final manifest = jsonDecode(utf8.decode(manifestRequest.bodyBytes))
        as Map<String, Object?>;
    expect(manifest['latestSnapshotPath'], 'repapertodo/state.json');
    expect(manifest['updatedAtUtc'], '2026-06-30T10:00:00.000Z');
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
    final service = WebDavStateSyncService(client: webDavClient);

    final result = await service.pull();

    expect(result.status, WebDavStateSyncStatus.downloaded);
    expect(result.manifest?.updatedAtUtc, DateTime.utc(2026, 6, 30, 11));
    expect(result.state?.papers.single.title, 'Remote note');
    expect(result.state?.papers.single.content, 'From WebDAV');
  });
}
