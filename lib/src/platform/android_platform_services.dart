import 'package:flutter/services.dart';

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
    await _channel.invokeMethod<void>('openUri', uri);
  }
}

class AndroidExternalFileHost implements ExternalFileHost {
  AndroidExternalFileHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> openFile(String path) async {
    await _channel.invokeMethod<void>('openExternalFile', path);
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
