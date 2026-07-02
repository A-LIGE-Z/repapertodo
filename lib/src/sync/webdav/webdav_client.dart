import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

const _webDavNamespace = 'DAV:';

class WebDavCredentials {
  const WebDavCredentials({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  String get authorizationHeader {
    if (!_isValidBasicAuthUsername(username)) {
      throw ArgumentError.value(
        username,
        'username',
        'WebDAV Basic Auth username must not be empty, contain colons, or contain control characters.',
      );
    }
    if (!_isValidBasicAuthPassword(password)) {
      throw ArgumentError.value(
        password,
        'password',
        'WebDAV Basic Auth password must not be blank or contain control characters.',
      );
    }
    final token = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $token';
  }
}

bool _isValidBasicAuthUsername(String value) {
  return value.isNotEmpty &&
      !value.contains(':') &&
      !_hasControlCharacter(value);
}

bool _isValidBasicAuthPassword(String value) {
  return value.trim().isNotEmpty && !_hasControlCharacter(value);
}

bool _hasControlCharacter(String value) {
  return value.codeUnits.any((unit) => unit <= 0x1F || unit == 0x7F);
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
    Duration requestTimeout = const Duration(seconds: 30),
  })  : _baseUri = _normalizeBaseUri(baseUri),
        _credentials = credentials,
        _requestTimeout = _normalizeRequestTimeout(requestTimeout),
        _ownsHttpClient = httpClient == null,
        _httpClient = httpClient ?? http.Client();

  final Uri _baseUri;
  final WebDavCredentials _credentials;
  final Duration _requestTimeout;
  final bool _ownsHttpClient;
  final http.Client _httpClient;
  bool _closed = false;

  void close() {
    if (_ownsHttpClient && !_closed) {
      _closed = true;
      _httpClient.close();
    }
  }

  Future<bool> exists(String path) async {
    return await metadata(path) != null;
  }

  Future<WebDavResourceMetadata?> metadata(String path) async {
    final response = await _send('HEAD', path);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode == 405 || response.statusCode == 501) {
      return _metadataFromPropFind(path);
    }
    _throwIfUnexpected(response, expected: {200, 204});
    return WebDavResourceMetadata(
      etag: _nonBlankHeaderValue(response.headers['etag']),
      contentLength: _tryParseContentLength(
        response.headers['content-length'],
      ),
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
    final normalizedIfMatch = _nonBlankHeaderValue(ifMatch);
    final headers = <String, String>{
      'content-type': 'application/octet-stream',
      if (normalizedIfMatch != null) 'if-match': normalizedIfMatch,
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
    _throwIfUnexpected(response, expected: {200, 201, 204});
  }

  Future<void> delete(String path, {String? ifMatch}) async {
    final normalizedIfMatch = _nonBlankHeaderValue(ifMatch);
    final response = await _send(
      'DELETE',
      path,
      headers: {if (normalizedIfMatch != null) 'if-match': normalizedIfMatch},
    );
    if (response.statusCode == 404) {
      return;
    }
    _throwIfUnexpected(response, expected: {200, 202, 204});
  }

  Future<List<WebDavEntry>> list(String path) async {
    return _propFind(path, depth: '1');
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    if (_closed) {
      throw StateError('WebDAV client is closed.');
    }
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
    try {
      return await _httpClient
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_requestTimeout, onTimeout: () {
        throw WebDavException(
          'WebDAV request timed out after ${_formatDuration(_requestTimeout)}.',
          statusCode: 0,
        );
      });
    } on WebDavException {
      rethrow;
    } on TimeoutException catch (error) {
      throw _timeoutException(error);
    } on http.ClientException catch (error) {
      throw _transportException(error);
    } on IOException catch (error) {
      throw _transportException(error);
    }
  }

  Uri _resolve(String path) {
    final segments = _normalizeRequestPathSegments(path);
    return _baseUri.resolveUri(Uri(pathSegments: segments));
  }

  Future<WebDavResourceMetadata?> _metadataFromPropFind(String path) async {
    final response = await _sendPropFind(path, depth: '0');
    if (response.statusCode == 404) {
      return null;
    }
    _throwIfUnexpected(response, expected: {207});
    final entries = _parseMultiStatusResponse(response);
    if (entries.isEmpty) {
      return null;
    }
    final entry = entries.first;
    return WebDavResourceMetadata(
      etag: entry.etag,
      contentLength: entry.contentLength,
      lastModified: entry.lastModified,
    );
  }

  Future<List<WebDavEntry>> _propFind(String path,
      {required String depth}) async {
    final response = await _sendPropFind(path, depth: depth);
    _throwIfUnexpected(response, expected: {207});
    return _parseMultiStatusResponse(response);
  }

  Future<http.Response> _sendPropFind(
    String path, {
    required String depth,
  }) {
    return _send(
      'PROPFIND',
      path,
      headers: {
        'depth': depth,
        'content-type': 'application/xml; charset=utf-8',
      },
      body: _propFindBody,
    );
  }
}

final _propFindBody = utf8.encode('''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:resourcetype/>
    <D:getetag/>
    <D:getcontentlength/>
    <D:getlastmodified/>
  </D:prop>
</D:propfind>
''');

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
  if (_hasUnsafeBaseUriPath(uri)) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'WebDAV base URI path must not contain dot-segments, backslashes, or control characters.',
    );
  }
  final text = uri.toString();
  return text.endsWith('/') ? uri : Uri.parse('$text/');
}

Duration _normalizeRequestTimeout(Duration timeout) {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(
      timeout,
      'requestTimeout',
      'WebDAV request timeout must be greater than zero.',
    );
  }
  return timeout;
}

String _formatDuration(Duration duration) {
  if (duration.inSeconds >= 1 && duration.inMilliseconds % 1000 == 0) {
    return '${duration.inSeconds}s';
  }
  return '${duration.inMilliseconds}ms';
}

bool _hasUnsafeBaseUriPath(Uri uri) {
  if (uri.toString().contains('\\')) {
    return true;
  }
  late final String decodedPath;
  try {
    decodedPath = Uri.decodeComponent(uri.path);
  } on ArgumentError {
    return true;
  } on FormatException {
    return true;
  }
  return decodedPath.replaceAll('\\', '/').split('/').any((segment) {
    if (_hasControlCharacter(segment)) {
      return true;
    }
    final trimmed = segment.trim();
    return trimmed == '.' || trimmed == '..';
  });
}

void _throwIfUnexpected(http.Response response, {required Set<int> expected}) {
  if (expected.contains(response.statusCode)) {
    return;
  }
  throw WebDavException(
    _unexpectedStatusMessage(response.statusCode),
    statusCode: response.statusCode,
    responseBody: response.body,
  );
}

String _unexpectedStatusMessage(int statusCode) {
  return switch (statusCode) {
    400 => 'WebDAV request was rejected by the provider.',
    401 => 'WebDAV authentication failed. Check the username and app password.',
    403 =>
      'WebDAV permission denied. Check account access and remote folder permissions.',
    404 => 'WebDAV resource was not found.',
    409 => 'WebDAV parent folder is missing or the remote file changed.',
    412 => 'WebDAV precondition failed because the remote file changed.',
    423 => 'WebDAV resource is locked by the provider.',
    429 => 'WebDAV provider rate limit reached. Try again later.',
    500 => 'WebDAV provider returned a server error.',
    502 ||
    503 ||
    504 =>
      'WebDAV provider is temporarily unavailable. Try again later.',
    507 => 'WebDAV storage quota is full.',
    _ => 'Unexpected WebDAV status $statusCode.',
  };
}

WebDavException _timeoutException(TimeoutException error) {
  final message = error.message?.trim();
  return WebDavException(
    message == null || message.isEmpty
        ? 'WebDAV request timed out.'
        : 'WebDAV request timed out: $message',
    statusCode: 0,
  );
}

WebDavException _transportException(Object error) {
  return WebDavException(
    'WebDAV request failed: ${_transportFailureMessage(error)}',
    statusCode: 0,
  );
}

String _transportFailureMessage(Object error) {
  final message = switch (error) {
    http.ClientException(:final message) => message,
    SocketException(:final message) => message,
    _ => error.toString(),
  }
      .trim();
  return message.isEmpty ? 'Network request failed.' : message;
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

List<WebDavEntry> _parseMultiStatusResponse(http.Response response) {
  try {
    return _parseMultiStatus(_decodeMultiStatusBody(response));
  } on FormatException catch (error) {
    throw WebDavException(
      'Malformed WebDAV multistatus response: ${error.message}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  } on XmlException catch (error) {
    throw WebDavException(
      'Malformed WebDAV multistatus response: ${error.message}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }
}

String _decodeMultiStatusBody(http.Response response) {
  final headerEncoding =
      _encodingFromContentType(response.headers['content-type']);
  if (headerEncoding != null) {
    return _stripLeadingByteOrderMark(
        headerEncoding.decode(response.bodyBytes));
  }
  final xmlEncoding = _encodingFromXmlDeclaration(response.bodyBytes);
  if (xmlEncoding != null) {
    return _stripLeadingByteOrderMark(xmlEncoding.decode(response.bodyBytes));
  }
  return _stripLeadingByteOrderMark(utf8.decode(response.bodyBytes));
}

String _stripLeadingByteOrderMark(String value) {
  return value.startsWith('\uFEFF') ? value.substring(1) : value;
}

Encoding? _encodingFromContentType(String? contentType) {
  if (contentType == null) {
    return null;
  }
  for (final part in contentType.split(';')) {
    final trimmed = part.trim();
    final separator = trimmed.indexOf('=');
    if (separator < 0) {
      continue;
    }
    if (trimmed.substring(0, separator).trim().toLowerCase() != 'charset') {
      continue;
    }
    return _encodingByName(trimmed.substring(separator + 1));
  }
  return null;
}

Encoding? _encodingFromXmlDeclaration(List<int> bytes) {
  final prefixLength = bytes.length < 256 ? bytes.length : 256;
  final prefix = ascii.decode(
    bytes.take(prefixLength).toList(growable: false),
    allowInvalid: true,
  );
  final match = RegExp(
    r'''<\?xml\s+[^>]*encoding\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(prefix);
  return match == null ? null : _encodingByName(match.group(1)!);
}

Encoding _encodingByName(String name) {
  final normalizedName = name.trim().replaceAll('"', '').replaceAll("'", '');
  final encoding = Encoding.getByName(normalizedName);
  if (encoding == null) {
    throw FormatException(
      'Unsupported WebDAV multistatus encoding: $normalizedName',
    );
  }
  return encoding;
}

List<WebDavEntry> _parseMultiStatus(String xml) {
  final document = XmlDocument.parse(xml);
  final rootName = document.rootElement.name;
  if (rootName.local != 'multistatus' ||
      rootName.namespaceUri != _webDavNamespace) {
    throw const FormatException(
      'WebDAV multistatus response must contain a DAV: multistatus root element.',
    );
  }
  final responseElements = document.rootElement.children
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'response')
      .toList(growable: false);
  if (responseElements.any(
    (element) => !_isWebDavElement(element, 'response'),
  )) {
    throw const FormatException(
      'WebDAV multistatus response entries must use DAV: response elements.',
    );
  }
  return responseElements
      .map(_parseEntry)
      .whereType<WebDavEntry>()
      .toList(growable: false);
}

WebDavEntry? _parseEntry(XmlElement element) {
  final href = _firstDirectElementText(element, 'href');
  if (href == null || href.isEmpty) {
    throw const FormatException(
      'WebDAV response entries must include a DAV: href element.',
    );
  }
  if (!_responseStatusIsSuccessful(element)) {
    return null;
  }
  final etag = _stripQuotes(_firstSuccessfulPropText(element, 'getetag'));
  final lengthText = _firstSuccessfulPropText(element, 'getcontentlength');
  final lastModifiedText = _firstSuccessfulPropText(
    element,
    'getlastmodified',
  );
  return WebDavEntry(
    href: href,
    etag: etag,
    contentLength: _tryParseContentLength(lengthText),
    lastModified:
        lastModifiedText == null ? null : _tryParseHttpDate(lastModifiedText),
    isCollection: _hasSuccessfulCollectionResourceType(element),
  );
}

bool _responseStatusIsSuccessful(XmlElement element) {
  final statusText = _firstDirectElementText(element, 'status');
  if (statusText == null || statusText.isEmpty) {
    return true;
  }
  final statusCode = _webDavStatusCode(statusText);
  return statusCode != null && statusCode >= 200 && statusCode < 300;
}

DateTime? _tryParseHttpDate(String value) {
  try {
    return HttpDate.parse(value.trim());
  } on FormatException {
    return null;
  }
}

int? _tryParseContentLength(String? value) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}

String? _firstDirectElementText(XmlElement element, String localName) {
  final matches = element.children
      .whereType<XmlElement>()
      .where((child) => _isWebDavElement(child, localName));
  if (matches.isEmpty) {
    return null;
  }
  return matches.first.innerText.trim();
}

String? _firstSuccessfulPropText(XmlElement element, String localName) {
  for (final prop in _successfulPropElements(element)) {
    final text = _firstDirectElementText(prop, localName);
    if (text != null) {
      return text;
    }
  }
  return null;
}

bool _hasSuccessfulCollectionResourceType(XmlElement element) {
  return _successfulPropElements(element).any((prop) {
    final resourceTypes = prop.children
        .whereType<XmlElement>()
        .where((child) => _isWebDavElement(child, 'resourcetype'));
    return resourceTypes.any(
      (resourceType) => _descendantElements(resourceType).any(
        (child) => _isWebDavElement(child, 'collection'),
      ),
    );
  });
}

Iterable<XmlElement> _successfulPropElements(XmlElement element) {
  return _successfulPropStatElements(element).expand((propStat) {
    return propStat.children
        .whereType<XmlElement>()
        .where((child) => _isWebDavElement(child, 'prop'));
  });
}

Iterable<XmlElement> _successfulPropStatElements(XmlElement element) {
  return element.children
      .whereType<XmlElement>()
      .where((child) => _isWebDavElement(child, 'propstat'))
      .where(_propStatIsSuccessful);
}

bool _propStatIsSuccessful(XmlElement propStat) {
  final statusText = _firstDirectElementText(propStat, 'status');
  if (statusText == null || statusText.isEmpty) {
    return true;
  }
  final statusCode = _webDavStatusCode(statusText);
  return statusCode != null && statusCode >= 200 && statusCode < 300;
}

int? _webDavStatusCode(String value) {
  final match = RegExp(
    r'^HTTP/\d+(?:\.\d+)?\s+(\d{3})(?:\s|$)',
  ).firstMatch(value.trim());
  return match == null ? null : int.tryParse(match.group(1)!);
}

Iterable<XmlElement> _descendantElements(XmlNode node) {
  return node.descendants.whereType<XmlElement>();
}

bool _isWebDavElement(XmlElement element, String localName) {
  return element.name.local == localName &&
      element.name.namespaceUri == _webDavNamespace;
}

String? _stripQuotes(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    final unquoted = trimmed.substring(1, trimmed.length - 1);
    return unquoted.isEmpty ? null : unquoted;
  }
  return trimmed;
}

String? _nonBlankHeaderValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

List<String> _normalizeRequestPathSegments(String path) {
  final withForwardSlashes = path.trim().replaceAll('\\', '/');
  late final String decoded;
  try {
    decoded = Uri.decodeComponent(withForwardSlashes);
  } on ArgumentError catch (error) {
    throw ArgumentError.value(
      path,
      'path',
      'WebDAV path contains invalid percent encoding: ${error.message}',
    );
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
    if (_hasControlCharacter(segment)) {
      throw ArgumentError.value(
        path,
        'path',
        'WebDAV path must not contain control characters.',
      );
    }
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
