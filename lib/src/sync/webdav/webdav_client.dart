import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

const _webDavNamespace = 'DAV:';
const _webDavUserAgent = 'RePaperTodo/1 WebDAV';

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
    final token = base64Encode(utf8.encode('${username.trim()}:$password'));
    return 'Basic $token';
  }
}

bool _isValidBasicAuthUsername(String value) {
  return value.trim().isNotEmpty &&
      !value.contains(':') &&
      !_hasControlCharacter(value);
}

bool _isValidBasicAuthPassword(String value) {
  return value.trim().isNotEmpty && !_hasControlCharacter(value);
}

bool _hasControlCharacter(String value) {
  return value.runes.any(
    (rune) => rune <= 0x1F || (rune >= 0x7F && rune <= 0x9F),
  );
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

  Uri get baseUri => _baseUri;

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<bool> exists(String path) async {
    return await metadata(path) != null;
  }

  Future<WebDavResourceMetadata?> metadata(String path) async {
    final response = await _send('HEAD', path);
    if (_shouldFallbackToPropFindForMetadata(response.statusCode)) {
      return _metadataFromPropFind(path);
    }
    if (_isMissingMetadataStatus(response.statusCode)) {
      return null;
    }
    _throwIfUnexpected(response, expected: {200, 204});
    final lastModified = _headerValue(response.headers, 'last-modified');
    return WebDavResourceMetadata(
      etag: _normalizedHeaderEtagValue(_headerValue(response.headers, 'etag')),
      contentLength: _tryParseContentLength(
        _headerValue(response.headers, 'content-length'),
      ),
      lastModified:
          lastModified == null ? null : _tryParseHttpDate(lastModified),
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
    final normalizedIfMatch = _normalizedIfMatchHeaderValue(ifMatch);
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
    if (response.statusCode == 405 ||
        _isAlreadyExistingCollectionResponse(response)) {
      return;
    }
    _throwIfUnexpected(response, expected: {200, 201, 204});
  }

  Future<void> delete(String path, {String? ifMatch}) async {
    final normalizedIfMatch = _normalizedIfMatchHeaderValue(ifMatch);
    final response = await _send(
      'DELETE',
      path,
      headers: {if (normalizedIfMatch != null) 'if-match': normalizedIfMatch},
    );
    if (_isMissingResourceStatus(response.statusCode)) {
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
    request.followRedirects = false;
    request.headers.addAll({
      'accept': '*/*',
      'authorization': _credentials.authorizationHeader,
      'user-agent': _webDavUserAgent,
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
    if (path.endsWith('/') && segments.isNotEmpty) {
      return _baseUri.resolveUri(
        Uri(pathSegments: [...segments, '']),
      );
    }
    return _baseUri.resolveUri(Uri(pathSegments: segments));
  }

  Future<WebDavResourceMetadata?> _metadataFromPropFind(String path) async {
    final response = await _sendPropFind(path, depth: '0');
    if (_isMissingMetadataStatus(response.statusCode)) {
      return null;
    }
    _throwIfUnexpected(response, expected: {207});
    final entries = _parseMultiStatusResponse(response);
    if (entries.isEmpty) {
      return null;
    }
    final entry = _entryForRequestPath(entries, _resolve(path), _baseUri);
    if (entry == null) {
      return null;
    }
    return WebDavResourceMetadata(
      etag: entry.etag,
      contentLength: entry.contentLength,
      lastModified: entry.lastModified,
    );
  }

  Future<List<WebDavEntry>> _propFind(String path,
      {required String depth}) async {
    var response = await _sendPropFind(path, depth: depth);
    if (_shouldRetryCollectionPropFindWithTrailingSlash(
      path: path,
      depth: depth,
      statusCode: response.statusCode,
    )) {
      response = await _sendPropFind(_withTrailingSlash(path), depth: depth);
    }
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
        'accept': 'application/xml, text/xml, */*',
        'content-type': 'application/xml; charset=utf-8',
      },
      body: _propFindBody,
    );
  }
}

bool _shouldRetryCollectionPropFindWithTrailingSlash({
  required String path,
  required String depth,
  required int statusCode,
}) {
  if (depth == '0' || path.trim().isEmpty || path.endsWith('/')) {
    return false;
  }
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308 ||
      statusCode == 404 ||
      statusCode == 405;
}

String _withTrailingSlash(String path) {
  return path.endsWith('/') ? path : '$path/';
}

WebDavEntry? _entryForRequestPath(
  List<WebDavEntry> entries,
  Uri requestUri,
  Uri baseUri,
) {
  for (final entry in entries) {
    if (_hrefMatchesRequestPath(entry.href, requestUri, baseUri)) {
      return entry;
    }
  }
  return null;
}

bool _hrefMatchesRequestPath(String href, Uri requestUri, Uri baseUri) {
  if (href != href.trim()) {
    return false;
  }
  final uri = Uri.tryParse(href);
  if (uri == null) {
    return false;
  }
  if (uri.hasQuery || uri.hasFragment) {
    return false;
  }
  if (uri.hasScheme || uri.hasAuthority) {
    if (!_hrefHasSameOrigin(uri, requestUri) || uri.userInfo.isNotEmpty) {
      return false;
    }
  }
  final rawPath = _rawHrefPath(href, uri);
  final hrefSegments = _safeDecodedHrefPathSegments(rawPath);
  if (hrefSegments == null) {
    return false;
  }
  if (rawPath.startsWith('/')) {
    return _pathSegmentsEqual(
      hrefSegments,
      _decodedUriPathSegments(requestUri),
    );
  }
  if (hrefSegments.isNotEmpty &&
      _pathSegmentsEqual(
        hrefSegments,
        _requestParentRelativePathSegments(requestUri, baseUri),
      )) {
    return true;
  }
  return hrefSegments.isNotEmpty &&
      _pathSegmentsEqual(
        hrefSegments,
        _relativeRequestPathSegments(requestUri, baseUri),
      );
}

List<String>? _safeDecodedHrefPathSegments(String path) {
  final segments = <String>[];
  final rawSegments = path.split('/');
  for (var index = 0; index < rawSegments.length; index += 1) {
    final rawSegment = rawSegments[index];
    if (rawSegment.isEmpty) {
      if (index == 0 || index == rawSegments.length - 1) {
        continue;
      }
      return null;
    }
    late final String decodedSegment;
    try {
      decodedSegment = Uri.decodeComponent(rawSegment);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
    if (decodedSegment.contains('/') ||
        decodedSegment.contains('\\') ||
        _hasControlCharacter(decodedSegment)) {
      return null;
    }
    final trimmed = decodedSegment.trim();
    if (rawSegment.isNotEmpty && trimmed.isEmpty) {
      return null;
    }
    if (decodedSegment != trimmed ||
        decodedSegment == '.' ||
        decodedSegment == '..') {
      return null;
    }
    segments.add(decodedSegment);
  }
  return segments;
}

String _rawHrefPath(String href, Uri uri) {
  final pathEnd = _firstIndexOfAny(href, ['?', '#']) ?? href.length;
  if (uri.hasScheme) {
    final schemeEnd = href.indexOf(':');
    if (schemeEnd < 0) {
      return href.substring(0, pathEnd);
    }
    final afterScheme = schemeEnd + 1;
    if (href.startsWith('//', afterScheme)) {
      return _rawPathAfterAuthority(href, afterScheme + 2, pathEnd);
    }
    return href.substring(afterScheme, pathEnd);
  }
  if (uri.hasAuthority) {
    return _rawPathAfterAuthority(href, 2, pathEnd);
  }
  return href.substring(0, pathEnd);
}

String _rawPathAfterAuthority(String href, int authorityStart, int pathEnd) {
  final pathStart = href.indexOf('/', authorityStart);
  if (pathStart < 0 || pathStart > pathEnd) {
    return '';
  }
  return href.substring(pathStart, pathEnd);
}

int? _firstIndexOfAny(String value, List<String> needles) {
  int? first;
  for (final needle in needles) {
    final index = value.indexOf(needle);
    if (index >= 0 && (first == null || index < first)) {
      first = index;
    }
  }
  return first;
}

List<String> _relativeRequestPathSegments(Uri requestUri, Uri baseUri) {
  final requestSegments = _decodedUriPathSegments(requestUri);
  final baseSegments = _decodedUriPathSegments(baseUri);
  if (baseSegments.length <= requestSegments.length) {
    var matchesBase = true;
    for (var index = 0; index < baseSegments.length; index += 1) {
      if (requestSegments[index] != baseSegments[index]) {
        matchesBase = false;
        break;
      }
    }
    if (matchesBase) {
      return requestSegments.skip(baseSegments.length).toList(growable: false);
    }
  }
  return requestSegments;
}

List<String> _requestParentRelativePathSegments(
  Uri requestUri,
  Uri baseUri,
) {
  final requestSegments = _relativeRequestPathSegments(requestUri, baseUri);
  if (requestSegments.isEmpty) {
    return const [];
  }
  return [requestSegments.last];
}

List<String> _decodedUriPathSegments(Uri uri) {
  return uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
}

bool _pathSegmentsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _hrefHasSameOrigin(Uri hrefUri, Uri requestUri) {
  return hrefUri.hasAuthority &&
      (!hrefUri.hasScheme ||
          hrefUri.scheme.toLowerCase() == requestUri.scheme.toLowerCase()) &&
      hrefUri.host.toLowerCase() == requestUri.host.toLowerCase() &&
      _effectiveHrefPort(hrefUri, requestUri) == _effectivePort(requestUri);
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => 0,
  };
}

int _effectiveHrefPort(Uri hrefUri, Uri requestUri) {
  if (hrefUri.hasPort) {
    return hrefUri.port;
  }
  if (!hrefUri.hasScheme) {
    return _effectivePort(requestUri);
  }
  return _effectivePort(hrefUri);
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
  if (_hasUnsafeBaseUriAuthority(uri)) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'WebDAV base URI authority must not contain encoded separators.',
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
      'WebDAV base URI path must not contain dot-segments, backslashes, control characters, encoded path separators, blank path segments, or path segments with leading or trailing whitespace.',
    );
  }
  final text = uri.toString();
  return text.endsWith('/') ? uri : Uri.parse('$text/');
}

bool _hasUnsafeBaseUriAuthority(Uri uri) {
  final authority = uri.authority.toLowerCase();
  for (final encodedSeparator in const [
    '%23',
    '%2f',
    '%3a',
    '%3f',
    '%40',
    '%5b',
    '%5c',
    '%5d',
  ]) {
    if (authority.contains(encodedSeparator)) {
      return true;
    }
  }
  return false;
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
  final rawSegments = uri.path.split('/');
  for (var index = 0; index < rawSegments.length; index += 1) {
    final rawSegment = rawSegments[index];
    if (rawSegment.isEmpty && index > 0 && index < rawSegments.length - 1) {
      return true;
    }
    late final String segment;
    try {
      segment = Uri.decodeComponent(rawSegment);
    } on ArgumentError {
      return true;
    } on FormatException {
      return true;
    }
    if (_hasControlCharacter(segment)) {
      return true;
    }
    if (segment.contains('/') || segment.contains('\\')) {
      return true;
    }
    final trimmed = segment.trim();
    if (segment != trimmed) {
      return true;
    }
    if (rawSegment.isNotEmpty && trimmed.isEmpty) {
      return true;
    }
    if (trimmed == '.' || trimmed == '..') {
      return true;
    }
  }
  return false;
}

void _throwIfUnexpected(http.Response response, {required Set<int> expected}) {
  if (expected.contains(response.statusCode)) {
    return;
  }
  throw WebDavException(
    _unexpectedStatusMessage(response),
    statusCode: response.statusCode,
    responseBody: _decodedResponseBody(response),
  );
}

String _unexpectedStatusMessage(http.Response response) {
  final message = switch (response.statusCode) {
    400 => 'WebDAV request was rejected by the provider.',
    401 => 'WebDAV authentication failed. Check the username and app password.',
    403 =>
      'WebDAV permission denied. Check account access and remote folder permissions.',
    301 ||
    302 ||
    303 ||
    307 ||
    308 =>
      'WebDAV provider redirected the request. Check the endpoint URL.',
    404 => 'WebDAV resource was not found.',
    409 => 'WebDAV parent folder is missing or the remote file changed.',
    410 => 'WebDAV resource is gone.',
    412 => 'WebDAV precondition failed because the remote file changed.',
    423 => 'WebDAV resource is locked by the provider.',
    429 => 'WebDAV provider rate limit reached. Try again later.',
    500 => 'WebDAV provider returned a server error.',
    502 ||
    503 ||
    504 =>
      'WebDAV provider is temporarily unavailable. Try again later.',
    507 => 'WebDAV storage quota is full.',
    _ => 'Unexpected WebDAV status ${response.statusCode}.',
  };
  return '$message${_retryAfterSuffix(
    _headerValue(response.headers, 'retry-after'),
  )}';
}

String? _headerValue(Map<String, String> headers, String name) {
  final directValue = headers[name];
  if (directValue != null) {
    return directValue;
  }
  final normalizedName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == normalizedName) {
      return entry.value;
    }
  }
  return null;
}

String _retryAfterSuffix(String? retryAfter) {
  final value = retryAfter?.trim();
  if (value == null || value.isEmpty) {
    return '';
  }
  final seconds = RegExp(r'^\d+$').hasMatch(value) ? int.tryParse(value) : null;
  if (seconds != null) {
    return ' Retry after $seconds ${seconds == 1 ? 'second' : 'seconds'}.';
  }
  try {
    final date = HttpDate.parse(value).toUtc();
    return ' Retry after ${date.toIso8601String()}.';
  } on HttpException {
    return '';
  }
}

bool _isMissingResourceStatus(int statusCode) {
  return statusCode == 404 || statusCode == 410;
}

bool _isMissingMetadataStatus(int statusCode) {
  return statusCode == 409 || _isMissingResourceStatus(statusCode);
}

bool _shouldFallbackToPropFindForMetadata(int statusCode) {
  return statusCode == 403 ||
      statusCode == 404 ||
      statusCode == 409 ||
      statusCode == 405 ||
      statusCode == 501;
}

bool _isAlreadyExistingCollectionResponse(http.Response response) {
  if (response.statusCode != 409 && response.statusCode != 412) {
    return false;
  }
  return _responseBodyCandidates(response).any((body) {
    return body.contains('already exist') ||
        body.contains('already-created') ||
        body.contains('\u5df2\u5b58\u5728') ||
        body.contains('\u5df2\u7ecf\u5b58\u5728') ||
        body.contains('已存在') ||
        body.contains('已经存在');
  });
}

Iterable<String> _responseBodyCandidates(http.Response response) sync* {
  final body = _fallbackDecodedResponseBody(response).toLowerCase();
  yield body;
  final headerEncoding = _encodingFromContentTypeOrNull(
      _headerValue(response.headers, 'content-type'));
  if (headerEncoding != null) {
    try {
      final decoded = headerEncoding.decode(response.bodyBytes).toLowerCase();
      if (decoded != body) {
        yield decoded;
      }
    } on FormatException {
      // Keep provider failures on the WebDAV error path even when the
      // declared response charset does not match the bytes actually returned.
    }
  }
  try {
    final utf8Body = utf8.decode(response.bodyBytes).toLowerCase();
    if (utf8Body != body) {
      yield utf8Body;
    }
  } on FormatException {
    return;
  }
}

String _decodedResponseBody(http.Response response) {
  final headerEncoding = _encodingFromContentTypeOrNull(
      _headerValue(response.headers, 'content-type'));
  if (headerEncoding != null) {
    try {
      return headerEncoding.decode(response.bodyBytes);
    } on FormatException {
      return _fallbackDecodedResponseBody(response);
    }
  }
  return _fallbackDecodedResponseBody(response);
}

String _fallbackDecodedResponseBody(http.Response response) {
  try {
    return response.body;
  } on FormatException {
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
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
      responseBody: _decodedResponseBody(response),
    );
  } on XmlException catch (error) {
    throw WebDavException(
      'Malformed WebDAV multistatus response: ${error.message}',
      statusCode: response.statusCode,
      responseBody: _decodedResponseBody(response),
    );
  }
}

String _decodeMultiStatusBody(http.Response response) {
  final headerEncoding =
      _encodingFromContentType(_headerValue(response.headers, 'content-type'));
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

Encoding? _encodingFromContentTypeOrNull(String? contentType) {
  try {
    return _encodingFromContentType(contentType);
  } on FormatException {
    return null;
  }
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
  final href = _firstDirectElementRawText(element, 'href');
  if (href == null || href.isEmpty) {
    throw const FormatException(
      'WebDAV response entries must include a DAV: href element.',
    );
  }
  if (!_responseStatusIsSuccessful(element)) {
    return null;
  }
  final etag = _normalizedPropEtagValue(
    _firstSuccessfulPropText(element, 'getetag'),
  );
  final lengthText = _firstSuccessfulPropRawText(element, 'getcontentlength');
  final lastModifiedText = _firstSuccessfulPropRawText(
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
  if (value != value.trim() || _hasControlCharacter(value)) {
    return null;
  }
  try {
    return HttpDate.parse(value);
  } on FormatException {
    return null;
  } on HttpException {
    return null;
  }
}

int? _tryParseContentLength(String? value) {
  if (value == null ||
      value != value.trim() ||
      _hasControlCharacter(value) ||
      !RegExp(r'^\d+$').hasMatch(value)) {
    return null;
  }
  return int.tryParse(value);
}

String? _firstDirectElementText(XmlElement element, String localName) {
  final text = _firstDirectElementRawText(element, localName);
  return text?.trim();
}

String? _firstDirectElementRawText(XmlElement element, String localName) {
  final matches = element.children
      .whereType<XmlElement>()
      .where((child) => _isWebDavElement(child, localName));
  if (matches.isEmpty) {
    return null;
  }
  return matches.first.innerText;
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

String? _firstSuccessfulPropRawText(XmlElement element, String localName) {
  for (final prop in _successfulPropElements(element)) {
    final text = _firstDirectElementRawText(prop, localName);
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

String? _normalizedHeaderEtagValue(String? value) {
  return _normalizedRemoteEtagValue(value, stripStrongQuotes: false);
}

String? _normalizedPropEtagValue(String? value) {
  return _normalizedRemoteEtagValue(value, stripStrongQuotes: true);
}

String? _normalizedRemoteEtagValue(
  String? value, {
  required bool stripStrongQuotes,
}) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty || _hasControlCharacter(trimmed)) {
    return null;
  }
  if (!_hasValidRemoteEtagShape(trimmed)) {
    return null;
  }
  if (stripStrongQuotes && _isQuotedRemoteEtag(trimmed)) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String? _normalizedIfMatchHeaderValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  if (_hasControlCharacter(trimmed) ||
      !_hasValidRemoteEtagShape(trimmed, allowWildcard: true)) {
    throw ArgumentError.value(
      value,
      'ifMatch',
      'WebDAV If-Match value must be a valid ETag without control characters.',
    );
  }
  if (trimmed == '*' ||
      trimmed.contains('"') ||
      trimmed.toLowerCase().startsWith('w/')) {
    return trimmed;
  }
  return '"$trimmed"';
}

bool _hasValidRemoteEtagShape(
  String value, {
  bool allowWildcard = false,
}) {
  if (value == '*') {
    return allowWildcard;
  }
  if (value.toLowerCase().startsWith('w/')) {
    return _isQuotedRemoteEtag(value.substring(2));
  }
  if (value.contains('"')) {
    return _isQuotedRemoteEtag(value);
  }
  return true;
}

bool _isQuotedRemoteEtag(String value) {
  if (value.length < 2 || !value.startsWith('"') || !value.endsWith('"')) {
    return false;
  }
  final inner = value.substring(1, value.length - 1);
  if (inner.isEmpty || inner.contains('"') || _hasControlCharacter(inner)) {
    return false;
  }
  return true;
}

List<String> _normalizeRequestPathSegments(String path) {
  final trimmedPath = path.trim();
  if (path != trimmedPath) {
    throw ArgumentError.value(
      path,
      'path',
      'WebDAV path must not contain leading or trailing whitespace.',
    );
  }
  if (trimmedPath.contains('\\')) {
    throw ArgumentError.value(
      path,
      'path',
      'WebDAV path must not contain backslashes.',
    );
  }
  late final String decoded;
  try {
    decoded = Uri.decodeComponent(trimmedPath);
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
  final rawSegments = trimmedPath.split('/');
  for (var index = 0; index < rawSegments.length; index += 1) {
    final rawSegment = rawSegments[index];
    if (rawSegment.isEmpty && index > 0 && index < rawSegments.length - 1) {
      throw ArgumentError.value(
        path,
        'path',
        'WebDAV path must not contain blank path segments.',
      );
    }
    late final String segment;
    try {
      segment = Uri.decodeComponent(rawSegment);
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
    if (_hasControlCharacter(segment)) {
      throw ArgumentError.value(
        path,
        'path',
        'WebDAV path must not contain control characters.',
      );
    }
    if (segment.contains('/') || segment.contains('\\')) {
      throw ArgumentError.value(
        path,
        'path',
        'WebDAV path segments must not decode to path separators.',
      );
    }
    final trimmed = segment.trim();
    if (segment != trimmed) {
      throw ArgumentError.value(
        path,
        'path',
        'WebDAV path segments must not contain leading or trailing whitespace.',
      );
    }
    if (rawSegment.isNotEmpty && trimmed.isEmpty) {
      throw ArgumentError.value(
        path,
        'path',
        'WebDAV path segments must not collapse to blank.',
      );
    }
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
