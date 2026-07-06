import 'package:flutter/services.dart';

import '../core/model/external_uri_targets.dart';
import 'noop_platform_services.dart';
import 'platform_services.dart';

class AndroidPlatformServices implements PlatformServices {
  AndroidPlatformServices({
    MethodChannel channel = const MethodChannel('repapertodo/android'),
  })  : paperWindows = NoopPaperWindowHost(),
        tray = NoopTrayHost(),
        startup = NoopStartupHost(),
        systemIntegration = NoopSystemIntegrationHost(),
        externalFiles = AndroidExternalFileHost(channel),
        uriOpener = AndroidUriOpenHost(channel),
        scriptCapsules = NoopScriptCapsuleHost(),
        storage = AndroidAppStorageHost(channel);

  @override
  final PaperWindowHost paperWindows;

  @override
  final TrayHost tray;

  @override
  final StartupHost startup;

  @override
  final SystemIntegrationHost systemIntegration;

  @override
  final ExternalFileHost externalFiles;

  @override
  final UriOpenHost uriOpener;

  @override
  final ScriptCapsuleHost scriptCapsules;

  @override
  final AppStorageHost storage;
}

class AndroidUriOpenHost implements UriOpenHost {
  AndroidUriOpenHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> openUri(String uri) async {
    final trimmedUri = uri.trim();
    if (trimmedUri.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Android URI must not be blank.');
    }
    if (hasUnsafeExternalUriCharacter(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Android URI must not contain control characters.',
      );
    }
    if (hasMalformedExternalUriPercentEscape(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Android URI must not contain malformed percent escapes.',
      );
    }
    if (hasEncodedUnsafeExternalUriCharacter(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Android URI must not contain encoded control characters.',
      );
    }
    if (hasEncodedExternalUriAuthoritySeparator(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Android URI must not contain encoded authority separators.',
      );
    }
    if (!isAllowedExternalUriTarget(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Android URI scheme is not supported.',
      );
    }
    await _channel.invokeMethod<void>('openUri', trimmedUri);
  }
}

class AndroidExternalFileHost implements ExternalFileHost {
  AndroidExternalFileHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> openFile(String path) async {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      throw ArgumentError.value(
        path,
        'path',
        'Android external file path must not be blank.',
      );
    }
    if (_hasUnsafeExternalFilePathCharacter(path)) {
      throw ArgumentError.value(
        path,
        'path',
        'Android external file path must not contain control characters.',
      );
    }
    await _channel.invokeMethod<void>('openExternalFile', trimmedPath);
  }
}

class AndroidAppStorageHost implements AppStorageHost {
  AndroidAppStorageHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<String> documentsDirectoryPath() async {
    final path = await _channel.invokeMethod<String>('getFilesDirectory');
    final trimmedPath = path?.trim();
    if (trimmedPath == null || trimmedPath.isEmpty) {
      throw StateError('Android files directory is unavailable.');
    }
    return trimmedPath;
  }
}

bool _hasUnsafeExternalFilePathCharacter(String value) {
  return value.runes.any(_isControlRune);
}

bool _isControlRune(int rune) {
  return rune < 0x20 || (rune >= 0x7F && rune <= 0x9F);
}
