import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final root = Directory(options.rootPath)..createSync(recursive: true);
  final log = File(options.logPath)..parent.createSync(recursive: true);
  final server = await HttpServer.bind(InternetAddress.anyIPv4, options.port);
  File(options.readyPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode({
      'status': 'ready',
      'port': server.port,
      'rootPath': root.absolute.path,
    }));
  stdout.writeln('Local WebDAV server listening on ${server.port}.');
  await for (final request in server) {
    unawaited(_handle(request, options, root, log));
  }
}

Future<void> _handle(
  HttpRequest request,
  _Options options,
  Directory root,
  File log,
) async {
  final startedAt = DateTime.now().toUtc();
  var status = HttpStatus.internalServerError;
  try {
    if (!_authorized(request, options)) {
      request.response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic');
      request.response.statusCode = status = HttpStatus.unauthorized;
      return;
    }
    final target = _resolveTarget(root, request.uri.path);
    switch (request.method) {
      case 'MKCOL':
        if (target.existsSync()) {
          request.response.statusCode = status = HttpStatus.methodNotAllowed;
        } else {
          Directory(target.path).createSync(recursive: false);
          request.response.statusCode = status = HttpStatus.created;
        }
      case 'PUT':
        final file = File(target.path);
        if (!_preconditionsPass(request, file)) {
          request.response.statusCode = status = HttpStatus.preconditionFailed;
          break;
        }
        file.parent.createSync(recursive: true);
        final bytes = await request.fold<List<int>>(
          <int>[],
          (buffer, chunk) => buffer..addAll(chunk),
        );
        await file.writeAsBytes(bytes, flush: true);
        request.response.headers.set(HttpHeaders.etagHeader, _etag(file));
        request.response.statusCode = status = HttpStatus.created;
      case 'GET':
        final file = File(target.path);
        if (!file.existsSync()) {
          request.response.statusCode = status = HttpStatus.notFound;
          break;
        }
        request.response.headers.set(HttpHeaders.etagHeader, _etag(file));
        request.response.statusCode = status = HttpStatus.ok;
        await request.response.addStream(file.openRead());
      case 'HEAD':
        if (!target.existsSync()) {
          request.response.statusCode = status = HttpStatus.notFound;
          break;
        }
        if (target is File) {
          request.response.headers.set(HttpHeaders.etagHeader, _etag(target));
          request.response.contentLength = target.lengthSync();
        }
        request.response.statusCode = status = HttpStatus.ok;
      case 'PROPFIND':
        if (!target.existsSync()) {
          request.response.statusCode = status = HttpStatus.notFound;
          break;
        }
        final depth = request.headers.value('depth') ?? '0';
        final entities = <FileSystemEntity>[target];
        if (depth != '0' && target is Directory) {
          entities.addAll(target.listSync(followLinks: false));
        }
        request.response.headers.contentType = ContentType(
          'application',
          'xml',
          charset: 'utf-8',
        );
        request.response.statusCode = status = 207;
        request.response.write(_multiStatus(root, entities));
      case 'DELETE':
        if (!target.existsSync()) {
          request.response.statusCode = status = HttpStatus.notFound;
        } else {
          target.deleteSync(recursive: true);
          request.response.statusCode = status = HttpStatus.noContent;
        }
      default:
        request.response.statusCode = status = HttpStatus.methodNotAllowed;
    }
  } catch (error, stackTrace) {
    request.response.statusCode = status = HttpStatus.internalServerError;
    request.response.write('$error\n$stackTrace');
  } finally {
    await request.response.close();
    log.writeAsStringSync(
      '${jsonEncode({
            'atUtc': startedAt.toIso8601String(),
            'method': request.method,
            'path': request.uri.path,
            'status': status,
          })}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

bool _authorized(HttpRequest request, _Options options) {
  final expected =
      'Basic ${base64Encode(utf8.encode('${options.username}:${options.password}'))}';
  return request.headers.value(HttpHeaders.authorizationHeader) == expected;
}

FileSystemEntity _resolveTarget(Directory root, String requestPath) {
  final decoded = requestPath
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(Uri.decodeComponent)
      .toList();
  if (decoded.any((segment) => segment == '.' || segment == '..')) {
    throw const FormatException('Unsafe WebDAV path.');
  }
  var path = root.absolute.path;
  for (final segment in decoded) {
    path = '$path${Platform.pathSeparator}$segment';
  }
  if (File(path).existsSync()) {
    return File(path);
  }
  return Directory(path);
}

bool _preconditionsPass(HttpRequest request, File file) {
  final ifNoneMatch = request.headers.value(HttpHeaders.ifNoneMatchHeader);
  if (ifNoneMatch == '*' && file.existsSync()) {
    return false;
  }
  final ifMatch = request.headers.value(HttpHeaders.ifMatchHeader);
  return ifMatch == null || (file.existsSync() && ifMatch == _etag(file));
}

String _etag(File file) =>
    '"${file.lengthSync()}-${file.lastModifiedSync().toUtc().microsecondsSinceEpoch}"';

String _multiStatus(Directory root, List<FileSystemEntity> entities) {
  final buffer = StringBuffer(
    '<?xml version="1.0" encoding="utf-8"?>'
    '<d:multistatus xmlns:d="DAV:">',
  );
  for (final entity in entities) {
    final relative = entity.absolute.path
        .substring(root.absolute.path.length)
        .split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final isDirectory = entity is Directory;
    final href =
        '/${relative.isEmpty ? '' : '$relative${isDirectory ? '/' : ''}'}';
    buffer
      ..write('<d:response><d:href>$href</d:href><d:propstat><d:prop>')
      ..write(isDirectory
          ? '<d:resourcetype><d:collection/></d:resourcetype>'
          : '<d:resourcetype/><d:getetag>${_etag(entity as File)}</d:getetag>')
      ..write('</d:prop><d:status>HTTP/1.1 200 OK</d:status>'
          '</d:propstat></d:response>');
  }
  return '${buffer.toString()}</d:multistatus>';
}

class _Options {
  const _Options({
    required this.port,
    required this.rootPath,
    required this.readyPath,
    required this.logPath,
    required this.username,
    required this.password,
  });

  final int port;
  final String rootPath;
  final String readyPath;
  final String logPath;
  final String username;
  final String password;

  static _Options parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index + 1 < args.length; index += 2) {
      values[args[index]] = args[index + 1];
    }
    String required(String name) {
      final value = values[name];
      if (value == null || value.trim().isEmpty) {
        throw ArgumentError('Missing $name.');
      }
      return value;
    }

    final port = int.tryParse(values['--port'] ?? '') ?? 18080;
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, '--port');
    }
    return _Options(
      port: port,
      rootPath: required('--root'),
      readyPath: required('--ready'),
      logPath: required('--log'),
      username: values['--username'] ?? 'android',
      password: values['--password'] ?? 'password',
    );
  }
}
