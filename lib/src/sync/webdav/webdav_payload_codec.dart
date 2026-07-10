import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../core/model/app_state.dart';
import '../../core/model/json_helpers.dart';
import '../../core/state/app_state_codec.dart';
import '../sync_operation.dart';

enum WebDavPayloadFormat {
  unknown,
  plainJson,
  encrypted,
}

abstract interface class WebDavPayloadCodec {
  WebDavPayloadFormat inspectPayloadFormat(List<int> bytes);

  FutureOr<List<int>> encodeSnapshot(
    AppState state,
    AppStateCodec appStateCodec,
  );

  FutureOr<AppState> decodeSnapshot(
    List<int> bytes,
    AppStateCodec appStateCodec,
  );

  FutureOr<List<int>> encodeOperationLog(SyncOperation operation);

  FutureOr<List<SyncOperation>> decodeOperationLog(List<int> bytes);
}

class WebDavPayloadDecryptionException implements Exception {
  const WebDavPayloadDecryptionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    return message;
  }
}

class PlainWebDavPayloadCodec implements WebDavPayloadCodec {
  const PlainWebDavPayloadCodec();

  @override
  WebDavPayloadFormat inspectPayloadFormat(List<int> bytes) {
    return _looksLikePlainJsonPayload(bytes)
        ? WebDavPayloadFormat.plainJson
        : WebDavPayloadFormat.unknown;
  }

  @override
  AppState decodeSnapshot(List<int> bytes, AppStateCodec appStateCodec) {
    return appStateCodec.decode(_decodePlainPayloadText(bytes));
  }

  @override
  List<SyncOperation> decodeOperationLog(List<int> bytes) {
    final operations = <SyncOperation>[];
    var lineNumber = 0;
    for (final rawLine in _splitPhysicalLines(_decodePlainPayloadText(bytes))) {
      lineNumber += 1;
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      operations.add(_decodeOperationLogLine(line, lineNumber));
    }
    if (operations.length != 1) {
      throw const FormatException(
        'Operation log must contain exactly one operation.',
      );
    }
    return operations;
  }

  @override
  List<int> encodeOperationLog(SyncOperation operation) {
    return utf8.encode('${jsonEncode(operation.toJson())}\n');
  }

  @override
  List<int> encodeSnapshot(AppState state, AppStateCodec appStateCodec) {
    return utf8.encode(appStateCodec.encodeRemoteSnapshot(state));
  }
}

class EncryptedWebDavPayloadCodec implements WebDavPayloadCodec {
  EncryptedWebDavPayloadCodec({
    required String passphrase,
    int kdfIterations = _defaultKdfIterations,
    Random? random,
  })  : _passphrase = passphrase.trim(),
        _kdfIterations = kdfIterations,
        _random = random ?? Random.secure() {
    if (_passphrase.isEmpty) {
      throw ArgumentError.value(
        passphrase,
        'passphrase',
        'WebDAV encryption passphrase must not be empty.',
      );
    }
    if (_hasControlCharacter(_passphrase)) {
      throw ArgumentError.value(
        passphrase,
        'passphrase',
        'WebDAV encryption passphrase must not contain control characters.',
      );
    }
    if (kdfIterations < _minimumKdfIterations) {
      throw ArgumentError.value(
        kdfIterations,
        'kdfIterations',
        'WebDAV encryption KDF iterations are too low.',
      );
    }
    if (kdfIterations > _maximumKdfIterations) {
      throw ArgumentError.value(
        kdfIterations,
        'kdfIterations',
        'WebDAV encryption KDF iterations are too high.',
      );
    }
  }

  static const _magic = 'RePaperTodo-Encrypted-Payload-v1\n';
  static const _algorithmName = 'aes-gcm-256';
  static const _kdfName = 'pbkdf2-hmac-sha256';
  static const _defaultKdfIterations = 210000;
  static const _minimumKdfIterations = 100000;
  static const _maximumKdfIterations = 1000000;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;

  final String _passphrase;
  final int _kdfIterations;
  final Random _random;
  final PlainWebDavPayloadCodec _plain = const PlainWebDavPayloadCodec();
  final AesGcm _cipher = AesGcm.with256bits();

  @override
  WebDavPayloadFormat inspectPayloadFormat(List<int> bytes) {
    if (_isEncryptedPayload(bytes)) {
      return WebDavPayloadFormat.encrypted;
    }
    return _looksLikePlainJsonPayload(bytes)
        ? WebDavPayloadFormat.plainJson
        : WebDavPayloadFormat.unknown;
  }

  @override
  Future<AppState> decodeSnapshot(
    List<int> bytes,
    AppStateCodec appStateCodec,
  ) async {
    if (!_isEncryptedPayload(bytes)) {
      return _plain.decodeSnapshot(bytes, appStateCodec);
    }
    final clearBytes = await _decryptOrThrowUserFacing(bytes);
    return _plain.decodeSnapshot(clearBytes, appStateCodec);
  }

  @override
  Future<List<SyncOperation>> decodeOperationLog(List<int> bytes) async {
    if (!_isEncryptedPayload(bytes)) {
      return _plain.decodeOperationLog(bytes);
    }
    final clearBytes = await _decryptOrThrowUserFacing(bytes);
    return _plain.decodeOperationLog(clearBytes);
  }

  @override
  Future<List<int>> encodeOperationLog(SyncOperation operation) {
    return _encrypt(_plain.encodeOperationLog(operation));
  }

  @override
  Future<List<int>> encodeSnapshot(
    AppState state,
    AppStateCodec appStateCodec,
  ) {
    return _encrypt(_plain.encodeSnapshot(state, appStateCodec));
  }

  Future<List<int>> _encrypt(List<int> clearBytes) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _cipher.newNonce();
    final secretKey = await _deriveKey(salt, _kdfIterations);
    final secretBox = await _cipher.encrypt(
      clearBytes,
      secretKey: secretKey,
      nonce: nonce,
    );
    final envelope = <String, Object?>{
      'version': 1,
      'algorithm': _algorithmName,
      'kdf': _kdfName,
      'kdfIterations': _kdfIterations,
      'salt': _base64UrlNoPadding(salt),
      'nonce': _base64UrlNoPadding(secretBox.nonce),
      'cipherText': _base64UrlNoPadding(secretBox.cipherText),
      'mac': _base64UrlNoPadding(secretBox.mac.bytes),
    };
    return utf8.encode('$_magic${jsonEncode(envelope)}\n');
  }

  Future<List<int>> _decryptOrThrowUserFacing(List<int> encryptedBytes) async {
    try {
      return await _decrypt(encryptedBytes);
    } on WebDavPayloadDecryptionException {
      rethrow;
    } on FormatException catch (error) {
      throw WebDavPayloadDecryptionException(
        'Encrypted WebDAV sync payload is unsupported or corrupted.',
        error,
      );
    } on Object catch (error) {
      throw WebDavPayloadDecryptionException(
        'Unable to decrypt WebDAV sync payload. Check the sync encryption passphrase.',
        error,
      );
    }
  }

  Future<List<int>> _decrypt(List<int> encryptedBytes) async {
    final text = utf8.decode(encryptedBytes);
    if (!text.startsWith(_magic)) {
      throw const FormatException('Encrypted WebDAV payload is missing magic.');
    }
    final envelope = _decodeJsonObject(text.substring(_magic.length).trim());
    final version = envelope['version'];
    final algorithm = envelope['algorithm'];
    final kdf = envelope['kdf'];
    final iterations = envelope['kdfIterations'];
    if (version != 1 || algorithm != _algorithmName || kdf != _kdfName) {
      throw const FormatException('Unsupported encrypted WebDAV payload.');
    }
    if (iterations is! int ||
        iterations < _minimumKdfIterations ||
        iterations > _maximumKdfIterations) {
      throw const FormatException(
        'Encrypted WebDAV payload has invalid KDF settings.',
      );
    }
    final salt = _base64UrlField(envelope, 'salt');
    final nonce = _base64UrlField(envelope, 'nonce');
    final cipherText = _base64UrlField(envelope, 'cipherText');
    final mac = _base64UrlField(envelope, 'mac');
    if (salt.length != _saltLength ||
        nonce.length != _nonceLength ||
        mac.length != _macLength) {
      throw const FormatException(
        'Encrypted WebDAV payload has invalid envelope field sizes.',
      );
    }
    final secretKey = await _deriveKey(salt, iterations);
    return _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: secretKey,
    );
  }

  Future<SecretKey> _deriveKey(List<int> salt, int iterations) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(
      secretKey: SecretKey(utf8.encode(_passphrase)),
      nonce: salt,
    );
  }

  List<int> _randomBytes(int length) {
    return [
      for (var index = 0; index < length; index += 1) _random.nextInt(256),
    ];
  }

  bool _isEncryptedPayload(List<int> bytes) {
    if (bytes.length < _magic.length) {
      return false;
    }
    final magicBytes = _magic.codeUnits;
    for (var index = 0; index < magicBytes.length; index += 1) {
      if (bytes[index] != magicBytes[index]) {
        return false;
      }
    }
    return true;
  }
}

SyncOperation _decodeOperationLogLine(String line, int lineNumber) {
  try {
    return SyncOperation.fromJson(_decodeJsonObject(line));
  } on FormatException catch (error) {
    throw FormatException(
      'Invalid WebDAV operation log line $lineNumber: ${error.message}',
      error.source,
      error.offset,
    );
  }
}

JsonMap _decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  final map = jsonMapOrNull(decoded);
  if (map == null) {
    throw const FormatException('Sync payload must be a JSON object.');
  }
  return map;
}

String _decodePlainPayloadText(List<int> bytes) {
  final text = utf8.decode(bytes);
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

Iterable<String> _splitPhysicalLines(String text) sync* {
  var start = 0;
  for (var index = 0; index < text.length; index += 1) {
    final char = text[index];
    if (char != '\r' && char != '\n') {
      continue;
    }
    yield text.substring(start, index);
    if (char == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
      index += 1;
    }
    start = index + 1;
  }
  yield text.substring(start);
}

bool _looksLikePlainJsonPayload(List<int> bytes) {
  late final String text;
  try {
    text = _decodePlainPayloadText(bytes).trimLeft();
  } on FormatException {
    return false;
  }
  return text.startsWith('{') || text.startsWith('[');
}

bool _hasControlCharacter(String value) {
  return value.runes.any(
    (rune) => rune <= 0x1F || (rune >= 0x7F && rune <= 0x9F),
  );
}

String _stringField(JsonMap map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Encrypted WebDAV payload field is invalid: $key.');
  }
  return value;
}

List<int> _base64UrlField(JsonMap map, String key) {
  final value = _stringField(map, key);
  if (value.contains('=') ||
      value.length % 4 == 1 ||
      !_base64UrlNoPaddingPattern.hasMatch(value)) {
    throw FormatException('Encrypted WebDAV payload field is invalid: $key.');
  }
  return _base64UrlDecode(value);
}

final _base64UrlNoPaddingPattern = RegExp(r'^[A-Za-z0-9_-]+$');

String _base64UrlNoPadding(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

List<int> _base64UrlDecode(String value) {
  final normalized =
      value.padRight(value.length + (4 - value.length % 4) % 4, '=');
  return base64Url.decode(normalized);
}
