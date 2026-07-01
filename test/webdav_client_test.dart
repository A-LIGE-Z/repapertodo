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

  test('ignores invalid WebDAV content lengths', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        if (request.method == 'HEAD') {
          return http.Response(
            '',
            200,
            headers: {'content-length': '-1'},
          );
        }
        if (request.method == 'PROPFIND') {
          return http.Response('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/negative.json</D:href>
    <D:propstat>
      <D:prop><D:getcontentlength>-42</D:getcontentlength></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/malformed.json</D:href>
    <D:propstat>
      <D:prop><D:getcontentlength>not-a-number</D:getcontentlength></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''', 207);
        }
        return http.Response('unexpected ${request.method}', 500);
      }),
    );

    final metadata = await client.metadata('repapertodo/manifest.json');
    final entries = await client.list('repapertodo');

    expect(metadata?.contentLength, isNull);
    expect(entries.map((entry) => entry.contentLength), [null, null]);
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

  test('rejects requests after closing owned HTTP clients', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
    );

    client.close();
    client.close();

    await expectLater(
      client.metadata('repapertodo/manifest.json'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'WebDAV client is closed.',
        ),
      ),
    );
  });

  test('reports malformed multistatus responses as WebDAV errors', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('<D:multistatus', 207);
      }),
    );

    await expectLater(
      client.list('repapertodo'),
      throwsA(
        isA<WebDavException>()
            .having((error) => error.statusCode, 'statusCode', 207)
            .having(
              (error) => error.message,
              'message',
              contains('Malformed WebDAV multistatus response'),
            )
            .having(
              (error) => error.responseBody,
              'responseBody',
              '<D:multistatus',
            ),
      ),
    );
  });

  test('rejects non-multistatus PROPFIND responses', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('<html>not webdav</html>', 207);
      }),
    );

    await expectLater(
      client.list('repapertodo'),
      throwsA(
        isA<WebDavException>()
            .having((error) => error.statusCode, 'statusCode', 207)
            .having(
              (error) => error.message,
              'message',
              contains('multistatus root element'),
            )
            .having(
              (error) => error.responseBody,
              'responseBody',
              '<html>not webdav</html>',
            ),
      ),
    );
  });

  test('accepts default WebDAV namespace multistatus responses', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('''
<multistatus xmlns="DAV:">
  <response>
    <href>/remote.php/dav/files/user/repapertodo/manifest.json</href>
    <propstat>
      <prop>
        <getetag>"manifest-v1"</getetag>
        <getcontentlength>42</getcontentlength>
      </prop>
    </propstat>
  </response>
</multistatus>
''', 207);
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries, hasLength(1));
    expect(
      entries.single.href,
      '/remote.php/dav/files/user/repapertodo/manifest.json',
    );
    expect(entries.single.etag, 'manifest-v1');
    expect(entries.single.contentLength, 42);
  });

  test('rejects non-WebDAV namespace multistatus responses', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('''
<x:multistatus xmlns:x="urn:not-webdav">
  <x:response>
    <x:href>/remote.php/dav/files/user/repapertodo/manifest.json</x:href>
  </x:response>
</x:multistatus>
''', 207);
      }),
    );

    await expectLater(
      client.list('repapertodo'),
      throwsA(
        isA<WebDavException>()
            .having((error) => error.statusCode, 'statusCode', 207)
            .having(
              (error) => error.message,
              'message',
              contains('DAV: multistatus root element'),
            )
            .having(
              (error) => error.responseBody,
              'responseBody',
              contains('urn:not-webdav'),
            ),
      ),
    );
  });

  test('rejects non-WebDAV namespace response entries', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('''
<D:multistatus xmlns:D="DAV:" xmlns:x="urn:not-webdav">
  <x:response>
    <x:href>/remote.php/dav/files/user/repapertodo/manifest.json</x:href>
  </x:response>
</D:multistatus>
''', 207);
      }),
    );

    await expectLater(
      client.list('repapertodo'),
      throwsA(
        isA<WebDavException>()
            .having((error) => error.statusCode, 'statusCode', 207)
            .having(
              (error) => error.message,
              'message',
              contains('DAV: response elements'),
            )
            .having(
              (error) => error.responseBody,
              'responseBody',
              contains('urn:not-webdav'),
            ),
      ),
    );
  });

  test('rejects response entries without WebDAV href elements', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('''
<D:multistatus xmlns:D="DAV:" xmlns:x="urn:not-webdav">
  <D:response>
    <x:href>/remote.php/dav/files/user/repapertodo/manifest.json</x:href>
  </D:response>
</D:multistatus>
''', 207);
      }),
    );

    await expectLater(
      client.list('repapertodo'),
      throwsA(
        isA<WebDavException>()
            .having((error) => error.statusCode, 'statusCode', 207)
            .having(
              (error) => error.message,
              'message',
              contains('DAV: href element'),
            )
            .having(
              (error) => error.responseBody,
              'responseBody',
              contains('urn:not-webdav'),
            ),
      ),
    );
  });

  test('ignores properties from failed WebDAV propstat entries', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"missing-etag"</D:getetag>
      </D:prop>
      <D:status>HTTP/1.1 404 Not Found</D:status>
    </D:propstat>
    <D:propstat>
      <D:prop>
        <D:resourcetype><D:collection /></D:resourcetype>
        <D:getcontentlength>42</D:getcontentlength>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>
''', 207);
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries, hasLength(1));
    expect(entries.single.href, '/remote.php/dav/files/user/repapertodo/');
    expect(entries.single.etag, isNull);
    expect(entries.single.contentLength, 42);
    expect(entries.single.isCollection, true);
  });

  test('ignores WebDAV-looking values outside prop containers', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/manifest.json</D:href>
    <D:propstat>
      <D:status>HTTP/1.1 200 OK</D:status>
      <D:getetag>"outside-prop"</D:getetag>
      <D:resourcetype><D:collection /></D:resourcetype>
      <D:prop>
        <D:getcontentlength>42</D:getcontentlength>
        <D:extension>
          <D:getlastmodified>Thu, 02 Jul 2026 10:00:00 GMT</D:getlastmodified>
        </D:extension>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''', 207);
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries, hasLength(1));
    expect(entries.single.etag, isNull);
    expect(entries.single.contentLength, 42);
    expect(entries.single.lastModified, isNull);
    expect(entries.single.isCollection, false);
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
