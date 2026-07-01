import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

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

class WebDavResourceMetadata {
  const WebDavResourceMetadata({
    this.etag,
    this.contentLength,
    this.lastModified,
  });

  final String? etag;
  final int? contentLength;
  final DateTime? lastModified;
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
    return await metadata(path) != null;
  }

  Future<WebDavResourceMetadata?> metadata(String path) async {
    final response = await _send('HEAD', path);
    if (response.statusCode == 404) {
      return null;
    }
    _throwIfUnexpected(response, expected: {200, 204});
    return WebDavResourceMetadata(
      etag: response.headers['etag'],
      contentLength: int.tryParse(response.headers['content-length'] ?? ''),
      lastModified: response.headers['last-modified'] == null
          ? null
          : _tryParseHttpDate(response.headers['last-modified']!),
    );
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
    final segments = _normalizeRequestPathSegments(path);
    return _baseUri.resolveUri(Uri(pathSegments: segments));
  }
}

Uri _normalizeBaseUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'WebDAV base URI must use http or https and include a host.',
    );
  }
  if (uri.userInfo.isNotEmpty) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'WebDAV base URI must not include embedded credentials.',
    );
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'WebDAV base URI must not contain query or fragment components.',
    );
  }
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
  final document = XmlDocument.parse(xml);
  return _descendantElements(document)
      .where((element) => element.name.local == 'response')
      .map(_parseEntry)
      .toList(growable: false);
}

WebDavEntry _parseEntry(XmlElement element) {
  final href = _firstElementText(element, 'href') ?? '';
  final etag = _stripQuotes(_firstElementText(element, 'getetag'));
  final lengthText = _firstElementText(element, 'getcontentlength');
  final lastModifiedText = _firstElementText(element, 'getlastmodified');
  return WebDavEntry(
    href: href,
    etag: etag,
    contentLength: lengthText == null ? null : int.tryParse(lengthText),
    lastModified:
        lastModifiedText == null ? null : _tryParseHttpDate(lastModifiedText),
    isCollection: _descendantElements(element)
        .any((child) => child.name.local == 'collection'),
  );
}

DateTime? _tryParseHttpDate(String value) {
  try {
    return HttpDate.parse(value);
  } on FormatException {
    return null;
  }
}

String? _firstElementText(XmlElement element, String localName) {
  final matches = _descendantElements(element)
      .where((child) => child.name.local == localName);
  if (matches.isEmpty) {
    return null;
  }
  return matches.first.innerText.trim();
}

Iterable<XmlElement> _descendantElements(XmlNode node) {
  return node.descendants.whereType<XmlElement>();
}

String? _stripQuotes(String? value) {
  if (value == null) {
    return null;
  }
  return value.replaceAll('"', '');
}

List<String> _normalizeRequestPathSegments(String path) {
  final withForwardSlashes = path.trim().replaceAll('\\', '/');
  late final String decoded;
  try {
    decoded = Uri.decodeComponent(withForwardSlashes);
  } on FormatException catch (error) {
    throw ArgumentError.value(
      path,
      'path',
      'WebDAV path contains invalid percent encoding: ${error.message}',
    );
  }
  if (decoded.startsWith('//') || (Uri.tryParse(decoded)?.hasScheme ?? false)) {
    throw ArgumentError.value(
      path,
      'path',
      'WebDAV path must be relative to the configured endpoint.',
    );
  }
  final segments = <String>[];
  for (final segment in decoded.split('/')) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty || trimmed == '.') {
      continue;
    }
    if (trimmed == '..') {
      throw ArgumentError.value(
        path,
        'path',
        'WebDAV path must not contain parent-directory segments.',
      );
    }
    segments.add(segment);
  }
  return segments;
}
