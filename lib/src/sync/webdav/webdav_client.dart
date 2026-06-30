import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class WebDavCredentials {
  const WebDavCredentials({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  String get authorizationHeader {
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }
}

class WebDavEntry {
  const WebDavEntry({
    required this.href,
    this.etag,
    this.contentLength,
    this.lastModified,
    this.isCollection = false,
  });

  final String href;
  final String? etag;
  final int? contentLength;
  final DateTime? lastModified;
  final bool isCollection;
}

class WebDavClient {
  WebDavClient({
    required Uri baseUri,
    required WebDavCredentials credentials,
    http.Client? httpClient,
  })  : _baseUri = _normalizeBaseUri(baseUri),
        _credentials = credentials,
        _httpClient = httpClient ?? http.Client();

  final Uri _baseUri;
  final WebDavCredentials _credentials;
  final http.Client _httpClient;

  Future<bool> exists(String path) async {
    final response = await _send('HEAD', path);
    if (response.statusCode == 404) {
      return false;
    }
    _throwIfUnexpected(response, expected: {200, 204});
    return true;
  }

  Future<List<int>> getBytes(String path) async {
    final response = await _send('GET', path);
    _throwIfUnexpected(response, expected: {200});
    return response.bodyBytes;
  }

  Future<void> putBytes(
    String path,
    List<int> bytes, {
    String? ifMatch,
    bool createOnly = false,
  }) async {
    final headers = <String, String>{
      'content-type': 'application/octet-stream',
      if (ifMatch != null) 'if-match': ifMatch,
      if (createOnly) 'if-none-match': '*',
    };
    final response = await _send('PUT', path, headers: headers, body: bytes);
    _throwIfUnexpected(response, expected: {200, 201, 204});
  }

  Future<void> makeCollection(String path) async {
    final response = await _send('MKCOL', path);
    if (response.statusCode == 405) {
      return;
    }
    _throwIfUnexpected(response, expected: {201});
  }

  Future<void> delete(String path, {String? ifMatch}) async {
    final response = await _send(
      'DELETE',
      path,
      headers: {if (ifMatch != null) 'if-match': ifMatch},
    );
    if (response.statusCode == 404) {
      return;
    }
    _throwIfUnexpected(response, expected: {200, 202, 204});
  }

  Future<List<WebDavEntry>> list(String path) async {
    final body = utf8.encode('''
<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:resourcetype/>
    <D:getetag/>
    <D:getcontentlength/>
    <D:getlastmodified/>
  </D:prop>
</D:propfind>
''');
    final response = await _send(
      'PROPFIND',
      path,
      headers: {
        'depth': '1',
        'content-type': 'application/xml; charset=utf-8',
      },
      body: body,
    );
    _throwIfUnexpected(response, expected: {207});
    return _parseMultiStatus(utf8.decode(response.bodyBytes));
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final request = http.Request(method, _resolve(path));
    request.headers.addAll({
      'authorization': _credentials.authorizationHeader,
      ...?headers,
    });
    if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body is String) {
      request.body = body;
    }
    return _httpClient.send(request).then(http.Response.fromStream);
  }

  Uri _resolve(String path) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return _baseUri.resolve(cleanPath);
  }
}

Uri _normalizeBaseUri(Uri uri) {
  final text = uri.toString();
  return text.endsWith('/') ? uri : Uri.parse('$text/');
}

void _throwIfUnexpected(http.Response response, {required Set<int> expected}) {
  if (expected.contains(response.statusCode)) {
    return;
  }
  throw WebDavException(
    'Unexpected WebDAV status ${response.statusCode}.',
    statusCode: response.statusCode,
    responseBody: response.body,
  );
}

class WebDavException implements Exception {
  const WebDavException(
    this.message, {
    required this.statusCode,
    this.responseBody = '',
  });

  final String message;
  final int statusCode;
  final String responseBody;

  @override
  String toString() {
    return 'WebDavException($statusCode): $message';
  }
}

List<WebDavEntry> _parseMultiStatus(String xml) {
  final responsePattern = RegExp(r'<[^:>]*:?response[\s\S]*?</[^:>]*:?response>', caseSensitive: false);
  return [
    for (final match in responsePattern.allMatches(xml))
      _parseEntry(match.group(0)!),
  ];
}

WebDavEntry _parseEntry(String xml) {
  final href = _firstTagText(xml, 'href') ?? '';
  final etag = _stripQuotes(_firstTagText(xml, 'getetag'));
  final lengthText = _firstTagText(xml, 'getcontentlength');
  final lastModifiedText = _firstTagText(xml, 'getlastmodified');
  return WebDavEntry(
    href: href,
    etag: etag,
    contentLength: lengthText == null ? null : int.tryParse(lengthText),
    lastModified: lastModifiedText == null ? null : _tryParseHttpDate(lastModifiedText),
    isCollection: RegExp(r'<[^:>]*:?collection\s*/?>', caseSensitive: false).hasMatch(xml),
  );
}

DateTime? _tryParseHttpDate(String value) {
  try {
    return HttpDate.parse(value);
  } on FormatException {
    return null;
  }
}

String? _firstTagText(String xml, String localName) {
  final pattern = RegExp(
    '<[^:>]*:?' '$localName' r'[^>]*>([\s\S]*?)</[^:>]*:?' '$localName' '>',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(xml);
  if (match == null) {
    return null;
  }
  return htmlUnescape(match.group(1)!.trim());
}

String? _stripQuotes(String? value) {
  if (value == null) {
    return null;
  }
  return value.replaceAll('"', '');
}

String htmlUnescape(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}
