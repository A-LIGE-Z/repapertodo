import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/model/app_state.dart';
import '../../core/model/sync_settings.dart';
import '../../core/state/app_state_codec.dart';
import '../sync_manifest.dart';
import 'webdav_client.dart';

enum WebDavStateSyncStatus {
  uploaded,
  downloaded,
  remoteMissing,
  conflict,
}

class WebDavStateSyncPaths {
  const WebDavStateSyncPaths({
    this.rootPath = 'repapertodo',
    this.manifestFileName = 'manifest.json',
    this.snapshotFileName = 'state.json',
  });

  final String rootPath;
  final String manifestFileName;
  final String snapshotFileName;

  String get rootCollectionPath => _normalizeRemotePath(rootPath);

  String get manifestPath =>
      _joinRemotePath(rootCollectionPath, manifestFileName);

  String get snapshotPath =>
      _joinRemotePath(rootCollectionPath, snapshotFileName);
}

class WebDavStateSyncResult {
  const WebDavStateSyncResult({
    required this.status,
    this.state,
    this.manifest,
  });

  final WebDavStateSyncStatus status;
  final AppState? state;
  final SyncManifest? manifest;
}

class WebDavStateSyncService {
  WebDavStateSyncService({
    required WebDavClient client,
    AppStateCodec codec = const AppStateCodec(),
    WebDavStateSyncPaths paths = const WebDavStateSyncPaths(),
  })  : _client = client,
        _codec = codec,
        _paths = paths;

  factory WebDavStateSyncService.fromSettings(
    WebDavSyncSettings settings, {
    AppStateCodec codec = const AppStateCodec(),
    http.Client? httpClient,
  }) {
    settings.normalize();
    final endpoint = settings.endpointUri;
    if (endpoint == null || !settings.isConfigured) {
      throw const WebDavSyncConfigurationException(
          'WebDAV sync settings are incomplete.');
    }
    return WebDavStateSyncService(
      client: WebDavClient(
        baseUri: endpoint,
        credentials: WebDavCredentials(
          username: settings.username,
          password: settings.password,
        ),
        httpClient: httpClient,
      ),
      codec: codec,
      paths: WebDavStateSyncPaths(rootPath: settings.rootPath),
    );
  }

  final WebDavClient _client;
  final AppStateCodec _codec;
  final WebDavStateSyncPaths _paths;

  Future<WebDavStateSyncResult> push(
    AppState state, {
    DateTime? updatedAtUtc,
    String? expectedManifestEtag,
    bool manifestKnownMissing = false,
  }) async {
    final stamp = (updatedAtUtc ?? DateTime.now().toUtc()).toUtc();
    await _ensureRootCollection();
    await _client.putBytes(
      _paths.snapshotPath,
      utf8.encode(_codec.encode(state)),
    );
    final manifest = SyncManifest(
      schemaVersion: 1,
      updatedAtUtc: stamp,
      latestSnapshotPath: _paths.snapshotPath,
    );
    final manifestUploaded = await _putManifest(
      manifest,
      expectedManifestEtag: expectedManifestEtag,
      createOnly: manifestKnownMissing,
    );
    if (!manifestUploaded) {
      return WebDavStateSyncResult(
        status: WebDavStateSyncStatus.conflict,
        manifest: manifest,
      );
    }
    return WebDavStateSyncResult(
      status: WebDavStateSyncStatus.uploaded,
      manifest: manifest,
    );
  }

  Future<WebDavStateSyncResult> pull() async {
    final manifest = await _loadManifest();
    if (manifest == null || manifest.latestSnapshotPath.isEmpty) {
      return const WebDavStateSyncResult(
          status: WebDavStateSyncStatus.remoteMissing);
    }
    return _downloadSnapshot(manifest);
  }

  Future<WebDavStateSyncResult> sync({
    required AppState localState,
    DateTime? localUpdatedAtUtc,
  }) async {
    final remoteManifest = await _loadManifestWithMetadata();
    final manifest = remoteManifest?.manifest;
    if (manifest == null || manifest.latestSnapshotPath.isEmpty) {
      return push(
        localState,
        updatedAtUtc: localUpdatedAtUtc,
        manifestKnownMissing: remoteManifest == null,
      );
    }

    final localStamp = localUpdatedAtUtc?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    if (manifest.updatedAtUtc.isAfter(localStamp)) {
      return _downloadSnapshot(manifest);
    }

    return push(
      localState,
      updatedAtUtc: localStamp,
      expectedManifestEtag: remoteManifest?.etag,
    );
  }

  Future<SyncManifest?> _loadManifest() async {
    return (await _loadManifestWithMetadata())?.manifest;
  }

  Future<_RemoteManifest?> _loadManifestWithMetadata() async {
    final metadata = await _client.metadata(_paths.manifestPath);
    if (metadata == null) {
      return null;
    }
    final bytes = await _client.getBytes(_paths.manifestPath);
    return _RemoteManifest(
      manifest: SyncManifest.fromJson(decodeJsonObject(utf8.decode(bytes))),
      etag: metadata.etag,
    );
  }

  Future<WebDavStateSyncResult> _downloadSnapshot(SyncManifest manifest) async {
    final bytes = await _client.getBytes(manifest.latestSnapshotPath);
    return WebDavStateSyncResult(
      status: WebDavStateSyncStatus.downloaded,
      state: _codec.decode(utf8.decode(bytes)),
      manifest: manifest,
    );
  }

  Future<void> _ensureRootCollection() async {
    final root = _paths.rootCollectionPath;
    if (root.isEmpty) {
      return;
    }
    await _client.makeCollection(root);
  }

  Future<bool> _putManifest(
    SyncManifest manifest, {
    String? expectedManifestEtag,
    bool createOnly = false,
  }) async {
    try {
      await _client.putBytes(
        _paths.manifestPath,
        utf8.encode(jsonEncode(manifest.toJson())),
        ifMatch: expectedManifestEtag,
        createOnly: createOnly,
      );
      return true;
    } on WebDavException catch (error) {
      if (error.statusCode == 412) {
        return false;
      }
      rethrow;
    }
  }
}

class _RemoteManifest {
  const _RemoteManifest({
    required this.manifest,
    this.etag,
  });

  final SyncManifest manifest;
  final String? etag;
}

String _joinRemotePath(String base, String child) {
  final normalizedChild = _normalizeRemotePath(child);
  if (base.isEmpty) {
    return normalizedChild;
  }
  return '$base/$normalizedChild';
}

String _normalizeRemotePath(String path) {
  return path
      .trim()
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .join('/');
}

class WebDavSyncConfigurationException implements Exception {
  const WebDavSyncConfigurationException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
