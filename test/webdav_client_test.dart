import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('resolves sanitized paths below the configured endpoint', () async {
    final requests = <http.Request>[];
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204, headers: {'etag': '"manifest-v1"'});
      }),
    );

    final metadata = await client.metadata('/repapertodo/./manifest.json');

    expect(metadata?.etag, '"manifest-v1"');
    expect(requests, hasLength(1));
    expect(requests.single.method, 'HEAD');
    expect(
      requests.single.url.toString(),
      'https://dav.example.test/remote.php/dav/files/user/repapertodo/manifest.json',
    );
    expect(
      requests.single.headers['authorization'],
      const WebDavCredentials(username: 'user', password: 'pass')
          .authorizationHeader,
    );
  });

  test('rejects unsafe request paths before sending', () async {
    var requestCount = 0;
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requestCount += 1;
        return http.Response('network should not be reached', 500);
      }),
    );

    for (final path in const [
      '../manifest.json',
      'repapertodo/%2e%2e/manifest.json',
      r'repapertodo\..\manifest.json',
      'https://evil.example.test/manifest.json',
      '//evil.example.test/manifest.json',
      '%2F%2Fevil.example.test/manifest.json',
    ]) {
      await expectLater(
        client.getBytes(path),
        throwsA(isA<ArgumentError>()),
      );
    }
    expect(requestCount, 0);
  });

  test('reports malformed request path encoding before sending', () async {
    var requestCount = 0;
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requestCount += 1;
        return http.Response('network should not be reached', 500);
      }),
    );

    await expectLater(
      client.getBytes('repapertodo/bad%'),
      throwsA(
        isA<ArgumentError>()
            .having((error) => error.name, 'name', 'path')
            .having(
              (error) => error.invalidValue,
              'invalidValue',
              'repapertodo/bad%',
            ),
      ),
    );
    expect(requestCount, 0);
  });

  test('does not close injected HTTP clients', () async {
    var requestCount = 0;
    var closeCount = 0;
    final httpClient = _CloseTrackingClient(
      (request) async {
        requestCount += 1;
        return http.Response('', 204, headers: {'etag': '"manifest-v1"'});
      },
      onClose: () => closeCount += 1,
    );
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: httpClient,
    );

    client.close();
    client.close();
    final metadata = await client.metadata('repapertodo/manifest.json');

    expect(metadata?.etag, '"manifest-v1"');
    expect(requestCount, 1);
    expect(closeCount, 0);

    httpClient.close();
    expect(closeCount, 1);
  });

  test('rejects invalid Basic Auth usernames before sending', () async {
    for (final username in const [
      '',
      'user:name',
      'user\nname',
      'user\u007Fname',
    ]) {
      var requestCount = 0;
      final client = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials: WebDavCredentials(username: username, password: 'pass'),
        httpClient: MockClient((request) async {
          requestCount += 1;
          return http.Response('network should not be reached', 500);
        }),
      );

      await expectLater(
        client.metadata('repapertodo/manifest.json'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'username',
          ),
        ),
        reason: username,
      );
      expect(requestCount, 0, reason: username);
    }
  });

  test('rejects invalid Basic Auth passwords before sending', () async {
    for (final password in const [
      '',
      '   ',
      'app\npassword',
      'app\u007Fpassword',
    ]) {
      var requestCount = 0;
      final client = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials: WebDavCredentials(username: 'user', password: password),
        httpClient: MockClient((request) async {
          requestCount += 1;
          return http.Response('network should not be reached', 500);
        }),
      );

      await expectLater(
        client.metadata('repapertodo/manifest.json'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'password',
          ),
        ),
        reason: password,
      );
      expect(requestCount, 0, reason: password);
    }
  });

  test('rejects unsupported base URIs', () {
    for (final baseUri in [
      Uri.parse('ftp://dav.example.test/dav/'),
      Uri.parse('file:///tmp/dav/'),
      Uri.parse('https://user:pass@dav.example.test/dav/'),
      Uri.parse('https://dav.example.test/dav/?token=secret'),
      Uri.parse('https://dav.example.test/dav/#sync-root'),
      Uri.parse('https://dav.example.test/dav/%5C..%5Cfiles/'),
    ]) {
      expect(
        () => WebDavClient(
          baseUri: baseUri,
          credentials:
              const WebDavCredentials(username: 'user', password: 'pass'),
        ),
        throwsA(isA<ArgumentError>()),
        reason: baseUri.toString(),
      );
    }
  });
}

class _CloseTrackingClient extends http.BaseClient {
  _CloseTrackingClient(
    this._handler, {
    required this.onClose,
  });

  final Future<http.Response> Function(http.Request request) _handler;
  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }

  @override
  void close() {
    onClose();
  }
}
