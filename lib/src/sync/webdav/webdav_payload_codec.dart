import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../core/model/app_state.dart';
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
    return WebDavPayloadFormat.plainJson;
  }

  @override
  AppState decodeSnapshot(List<int> bytes, AppStateCodec appStateCodec) {
    return appStateCodec.decode(_decodePlainPayloadText(bytes));
  }

  @override
  List<SyncOperation> decodeOperationLog(List<int> bytes) {
    final lines = _decodePlainPayloadText(bytes)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return [
      for (final line in lines)
        SyncOperation.fromJson(
          Map<String, Object?>.from(_decodeJsonObject(line)),
        ),
    ];
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
    if (kdfIterations < _minimumKdfIterations) {
      throw ArgumentError.value(
        kdfIterations,
        'kdfIterations',
        'WebDAV encryption KDF iterations are too low.',
      );
    }
  }

  static const _magic = 'RePaperTodo-Encrypted-Payload-v1\n';
  static const _algorithmName = 'aes-gcm-256';
  static const _kdfName = 'pbkdf2-hmac-sha256';
  static const _defaultKdfIterations = 210000;
  static const _minimumKdfIterations = 100000;

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
    final salt = _randomBytes(16);
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
    if (iterations is! int || iterations < _minimumKdfIterations) {
      throw const FormatException(
        'Encrypted WebDAV payload has invalid KDF settings.',
      );
    }
    final salt = _base64UrlDecode(_stringField(envelope, 'salt'));
    final nonce = _base64UrlDecode(_stringField(envelope, 'nonce'));
    final cipherText = _base64UrlDecode(_stringField(envelope, 'cipherText'));
    final mac = _base64UrlDecode(_stringField(envelope, 'mac'));
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

Map<Object?, Object?> _decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('Sync payload must be a JSON object.');
  }
  return decoded;
}

String _decodePlainPayloadText(List<int> bytes) {
  final text = utf8.decode(bytes);
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
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

String _stringField(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Encrypted WebDAV payload field is invalid: $key.');
  }
  return value;
}

String _base64UrlNoPadding(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

List<int> _base64UrlDecode(String value) {
  final normalized =
      value.padRight(value.length + (4 - value.length % 4) % 4, '=');
  return base64Url.decode(normalized);
}
