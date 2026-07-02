import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  test('normalizes WebDAV metadata headers', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'HEAD');
        if (request.url.path.endsWith('/with-etag.json')) {
          return http.Response(
            '',
            200,
            headers: {
              'etag': ' "manifest-v1" ',
              'content-length': ' 42 ',
              'last-modified': ' Wed, 01 Jul 2026 09:01:00 GMT ',
            },
          );
        }
        return http.Response(
          '',
          200,
          headers: {'etag': '  '},
        );
      }),
    );

    final metadata = await client.metadata('repapertodo/with-etag.json');
    final blankEtagMetadata =
        await client.metadata('repapertodo/blank-etag.json');

    expect(metadata?.etag, '"manifest-v1"');
    expect(metadata?.contentLength, 42);
    expect(metadata?.lastModified, DateTime.utc(2026, 7, 1, 9, 1));
    expect(blankEtagMetadata?.etag, isNull);
  });

  test('falls back to PROPFIND metadata when HEAD is unsupported', () async {
    final requests = <http.Request>[];
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD') {
          return http.Response('', 405);
        }
        if (request.method == 'PROPFIND') {
          expect(request.headers['depth'], '0');
          return http.Response('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/manifest.json</D:href>
    <D:propstat>
      <D:prop>
        <D:getetag>"manifest-v1"</D:getetag>
        <D:getcontentlength>42</D:getcontentlength>
        <D:getlastmodified>Wed, 01 Jul 2026 09:01:00 GMT</D:getlastmodified>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''', 207);
        }
        return http.Response('unexpected ${request.method}', 500);
      }),
    );

    final metadata = await client.metadata('repapertodo/manifest.json');

    expect(requests.map((request) => request.method), ['HEAD', 'PROPFIND']);
    expect(metadata?.etag, 'manifest-v1');
    expect(metadata?.contentLength, 42);
    expect(metadata?.lastModified, DateTime.utc(2026, 7, 1, 9, 1));
  });

  test('sends PROPFIND bodies with the XML declaration first', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(String.fromCharCodes(request.bodyBytes), startsWith('<?xml'));
        return http.Response('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/manifest.json</D:href>
  </D:response>
</D:multistatus>
''', 207);
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries, hasLength(1));
  });

  test('returns null when PROPFIND metadata fallback is missing', () async {
    final requests = <http.Request>[];
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'HEAD') {
          return http.Response('', 501);
        }
        if (request.method == 'PROPFIND') {
          expect(request.headers['depth'], '0');
          return http.Response('', 404);
        }
        return http.Response('unexpected ${request.method}', 500);
      }),
    );

    final metadata = await client.metadata('repapertodo/missing.json');

    expect(requests.map((request) => request.method), ['HEAD', 'PROPFIND']);
    expect(metadata, isNull);
  });

  test('omits blank WebDAV condition headers', () async {
    final requests = <http.Request>[];
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
    );

    await client.putBytes(
      'repapertodo/manifest.json',
      const [1],
      ifMatch: '  ',
    );
    await client.delete('repapertodo/manifest.json', ifMatch: '\t');
    await client.putBytes(
      'repapertodo/manifest.json',
      const [2],
      ifMatch: ' "manifest-v1" ',
    );
    await client.delete(
      'repapertodo/manifest.json',
      ifMatch: '"manifest-v2"',
    );

    expect(requests.map((request) => request.method), [
      'PUT',
      'DELETE',
      'PUT',
      'DELETE',
    ]);
    expect(requests[0].headers.containsKey('if-match'), false);
    expect(requests[1].headers.containsKey('if-match'), false);
    expect(requests[2].headers['if-match'], '"manifest-v1"');
    expect(requests[3].headers['if-match'], '"manifest-v2"');
  });

  test('accepts common successful MKCOL statuses', () async {
    final statuses = [200, 201, 204, 405];
    final requests = <http.Request>[];
    var cursor = 0;
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', statuses[cursor++]);
      }),
    );

    for (final path in const [
      'repapertodo',
      'repapertodo/snapshots',
      'repapertodo/ops',
      'repapertodo/existing',
    ]) {
      await client.makeCollection(path);
    }

    expect(requests.map((request) => request.method), [
      'MKCOL',
      'MKCOL',
      'MKCOL',
      'MKCOL',
    ]);
    expect(requests.map((request) => request.url.path), [
      '/remote.php/dav/files/user/repapertodo',
      '/remote.php/dav/files/user/repapertodo/snapshots',
      '/remote.php/dav/files/user/repapertodo/ops',
      '/remote.php/dav/files/user/repapertodo/existing',
    ]);
  });

  test('rejects failed MKCOL statuses', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        return http.Response('quota exceeded', 507);
      }),
    );

    await expectLater(
      client.makeCollection('repapertodo'),
      throwsA(
        isA<WebDavException>()
            .having((error) => error.statusCode, 'statusCode', 507)
            .having(
              (error) => error.message,
              'message',
              'WebDAV storage quota is full.',
            )
            .having(
              (error) => error.responseBody,
              'responseBody',
              'quota exceeded',
            ),
      ),
    );
  });

  test('reports common WebDAV failure statuses with actionable messages',
      () async {
    for (final caseData in const <({int statusCode, String message})>[
      (
        statusCode: 400,
        message: 'WebDAV request was rejected by the provider.',
      ),
      (
        statusCode: 401,
        message:
            'WebDAV authentication failed. Check the username and app password.',
      ),
      (
        statusCode: 403,
        message:
            'WebDAV permission denied. Check account access and remote folder permissions.',
      ),
      (
        statusCode: 409,
        message: 'WebDAV parent folder is missing or the remote file changed.',
      ),
      (
        statusCode: 412,
        message: 'WebDAV precondition failed because the remote file changed.',
      ),
      (
        statusCode: 423,
        message: 'WebDAV resource is locked by the provider.',
      ),
      (
        statusCode: 429,
        message: 'WebDAV provider rate limit reached. Try again later.',
      ),
      (
        statusCode: 500,
        message: 'WebDAV provider returned a server error.',
      ),
      (
        statusCode: 503,
        message: 'WebDAV provider is temporarily unavailable. Try again later.',
      ),
      (
        statusCode: 507,
        message: 'WebDAV storage quota is full.',
      ),
    ]) {
      final client = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials:
            const WebDavCredentials(username: 'user', password: 'pass'),
        httpClient: MockClient((request) async {
          return http.Response('failure body', caseData.statusCode);
        }),
      );

      await expectLater(
        client.getBytes('repapertodo/manifest.json'),
        throwsA(
          isA<WebDavException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                caseData.statusCode,
              )
              .having((error) => error.message, 'message', caseData.message)
              .having(
                (error) => error.responseBody,
                'responseBody',
                'failure body',
              ),
        ),
        reason: caseData.statusCode.toString(),
      );
    }
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
      'repapertodo/\nmanifest.json',
      'repapertodo/%0Amanifest.json',
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

  test('times out stalled WebDAV requests', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      requestTimeout: const Duration(milliseconds: 10),
      httpClient: MockClient((request) => Completer<http.Response>().future),
    );

    await expectLater(
      client.metadata('repapertodo/manifest.json'),
      throwsA(
        isA<WebDavException>()
            .having((error) => error.statusCode, 'statusCode', 0)
            .having(
              (error) => error.message,
              'message',
              'WebDAV request timed out after 10ms.',
            ),
      ),
    );
  });

  test('wraps lower-level WebDAV timeout failures as WebDAV errors', () async {
    for (final caseData in <({TimeoutException error, String message})>[
      (
        error: TimeoutException('upstream timed out'),
        message: 'WebDAV request timed out: upstream timed out',
      ),
      (
        error: TimeoutException(''),
        message: 'WebDAV request timed out.',
      ),
    ]) {
      final client = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials:
            const WebDavCredentials(username: 'user', password: 'pass'),
        httpClient: MockClient((request) async => throw caseData.error),
      );

      await expectLater(
        client.metadata('repapertodo/manifest.json'),
        throwsA(
          isA<WebDavException>()
              .having((exception) => exception.statusCode, 'statusCode', 0)
              .having(
                (exception) => exception.message,
                'message',
                caseData.message,
              ),
        ),
        reason: caseData.error.toString(),
      );
    }
  });

  test('wraps WebDAV transport failures as WebDAV errors', () async {
    for (final caseData in <({Object error, String message})>[
      (
        error: http.ClientException('connection reset'),
        message: 'WebDAV request failed: connection reset',
      ),
      (
        error: const SocketException('offline'),
        message: 'WebDAV request failed: offline',
      ),
      (
        error: http.ClientException(''),
        message: 'WebDAV request failed: Network request failed.',
      ),
    ]) {
      final client = WebDavClient(
        baseUri:
            Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
        credentials:
            const WebDavCredentials(username: 'user', password: 'pass'),
        httpClient: MockClient((request) async => throw caseData.error),
      );

      await expectLater(
        client.metadata('repapertodo/manifest.json'),
        throwsA(
          isA<WebDavException>()
              .having((exception) => exception.statusCode, 'statusCode', 0)
              .having(
                (exception) => exception.message,
                'message',
                caseData.message,
              ),
        ),
        reason: caseData.error.toString(),
      );
    }
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

  test('decodes multistatus responses with declared charsets', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response.bytes(
          latin1.encode('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/café.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"café-v1"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
'''),
          207,
          headers: {'content-type': 'application/xml; charset=iso-8859-1'},
        );
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries, hasLength(1));
    expect(
      entries.single.href,
      '/remote.php/dav/files/user/repapertodo/café.json',
    );
    expect(entries.single.etag, 'café-v1');
  });

  test('decodes multistatus responses with XML-declared encodings', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response.bytes(
          latin1.encode('''<?xml version="1.0" encoding="ISO-8859-1"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/café.xml</D:href>
    <D:propstat>
      <D:prop><D:getetag>"café-v2"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
'''),
          207,
        );
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries, hasLength(1));
    expect(
      entries.single.href,
      '/remote.php/dav/files/user/repapertodo/café.xml',
    );
    expect(entries.single.etag, 'café-v2');
  });

  test('decodes charset-less multistatus responses as UTF-8', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response.bytes(
          utf8.encode('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/论文.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"论文-v1"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
'''),
          207,
        );
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries, hasLength(1));
    expect(
      entries.single.href,
      '/remote.php/dav/files/user/repapertodo/论文.json',
    );
    expect(entries.single.etag, '论文-v1');
  });

  test('ignores UTF-8 BOMs before multistatus responses', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response.bytes(
          utf8.encode('''\uFEFF<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/manifest.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"manifest-v1"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
'''),
          207,
        );
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries, hasLength(1));
    expect(entries.single.etag, 'manifest-v1');
  });

  test('normalizes WebDAV etags without deleting internal quotes', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/strong.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>"strong-v1"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/weak.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>W/"weak-v1"</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/internal-quote.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>bad"etag</D:getetag></D:prop>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/empty.json</D:href>
    <D:propstat>
      <D:prop><D:getetag>""</D:getetag></D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>
''', 207);
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries.map((entry) => entry.etag), [
      'strong-v1',
      'W/"weak-v1"',
      'bad"etag',
      null,
    ]);
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

  test('ignores properties from malformed WebDAV propstat statuses', () async {
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
      <D:prop>
        <D:getetag>"malformed-status"</D:getetag>
      </D:prop>
      <D:status>status text says 200 but is not an HTTP status line</D:status>
    </D:propstat>
    <D:propstat>
      <D:prop>
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
    expect(entries.single.etag, isNull);
    expect(entries.single.contentLength, 42);
  });

  test('ignores WebDAV response entries with failed direct statuses', () async {
    final client = WebDavClient(
      baseUri: Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
      credentials: const WebDavCredentials(username: 'user', password: 'pass'),
      httpClient: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        return http.Response('''
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/available.json</D:href>
    <D:status>HTTP/1.1 200 OK</D:status>
    <D:propstat>
      <D:prop><D:getetag>"available-v1"</D:getetag></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/missing.json</D:href>
    <D:status>HTTP/1.1 404 Not Found</D:status>
    <D:propstat>
      <D:prop><D:getetag>"stale-v1"</D:getetag></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/locked.json</D:href>
    <D:status>HTTP/1.1 423 Locked</D:status>
  </D:response>
  <D:response>
    <D:href>/remote.php/dav/files/user/repapertodo/malformed-status.json</D:href>
    <D:status>not an HTTP status line</D:status>
  </D:response>
</D:multistatus>
''', 207);
      }),
    );

    final entries = await client.list('repapertodo');

    expect(entries, hasLength(1));
    expect(
      entries.single.href,
      '/remote.php/dav/files/user/repapertodo/available.json',
    );
    expect(entries.single.etag, 'available-v1');
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
      Uri.parse('https://dav.example.test/dav/%0Afiles/'),
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

  test('rejects non-positive WebDAV request timeouts', () {
    for (final timeout in const [
      Duration.zero,
      Duration(milliseconds: -1),
    ]) {
      expect(
        () => WebDavClient(
          baseUri:
              Uri.parse('https://dav.example.test/remote.php/dav/files/user/'),
          credentials:
              const WebDavCredentials(username: 'user', password: 'pass'),
          requestTimeout: timeout,
        ),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'requestTimeout')
              .having((error) => error.invalidValue, 'invalidValue', timeout),
        ),
        reason: timeout.toString(),
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
