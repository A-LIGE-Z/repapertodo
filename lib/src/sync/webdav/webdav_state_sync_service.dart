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
    this.snapshotDirectoryName = 'snapshots',
  });

  final String rootPath;
  final String manifestFileName;
  final String snapshotDirectoryName;

  String get rootCollectionPath => _normalizeRemotePath(rootPath);

  String get manifestPath =>
      _joinRemotePath(rootCollectionPath, manifestFileName);

  String get snapshotCollectionPath =>
      _joinRemotePath(rootCollectionPath, snapshotDirectoryName);

  String snapshotPath(DateTime updatedAtUtc, String deviceId) {
    final stamp = _formatSnapshotStamp(updatedAtUtc);
    final safeDeviceId = _normalizeRemotePathSegment(deviceId);
    return _joinRemotePath(
      snapshotCollectionPath,
      'snapshot-$stamp-$safeDeviceId.json',
    );
  }
}

class WebDavStateSyncResult {
  const WebDavStateSyncResult({
    required this.status,
    this.state,
    this.manifest,
    this.snapshotPath = '',
  });

  final WebDavStateSyncStatus status;
  final AppState? state;
  final SyncManifest? manifest;
  final String snapshotPath;
}

class WebDavSnapshotRecord {
  const WebDavSnapshotRecord({
    required this.path,
    required this.deviceId,
    required this.updatedAtUtc,
    this.etag,
    this.contentLength,
    this.lastModifiedUtc,
  });

  final String path;
  final String deviceId;
  final DateTime updatedAtUtc;
  final String? etag;
  final int? contentLength;
  final DateTime? lastModifiedUtc;
}

class WebDavStateSyncService {
  WebDavStateSyncService({
    required WebDavClient client,
    AppStateCodec codec = const AppStateCodec(),
    WebDavStateSyncPaths paths = const WebDavStateSyncPaths(),
    String deviceId = 'local-device',
  })  : _client = client,
        _codec = codec,
        _paths = paths,
        _deviceId = _normalizeDeviceId(deviceId);

  factory WebDavStateSyncService.fromSettings(
    WebDavSyncSettings settings, {
    AppStateCodec codec = const AppStateCodec(),
    http.Client? httpClient,
    String? deviceId,
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
      deviceId: deviceId ?? 'local-device',
    );
  }

  final WebDavClient _client;
  final AppStateCodec _codec;
  final WebDavStateSyncPaths _paths;
  final String _deviceId;

  Future<WebDavStateSyncResult> push(
    AppState state, {
    DateTime? updatedAtUtc,
    String? expectedManifestEtag,
    bool manifestKnownMissing = false,
    Map<String, int>? previousDeviceSequences,
  }) async {
    final stamp = (updatedAtUtc ?? DateTime.now().toUtc()).toUtc();
    await _ensureCollections();
    final snapshotPath = _paths.snapshotPath(stamp, _deviceId);
    await _client.putBytes(
      snapshotPath,
      utf8.encode(_codec.encode(state)),
    );
    final deviceSequences =
        Map<String, int>.from(previousDeviceSequences ?? const {});
    deviceSequences[_deviceId] = (deviceSequences[_deviceId] ?? 0) + 1;
    final manifest = SyncManifest(
      schemaVersion: 1,
      updatedAtUtc: stamp,
      latestSnapshotPath: snapshotPath,
      deviceSequences: deviceSequences,
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
        snapshotPath: snapshotPath,
      );
    }
    return WebDavStateSyncResult(
      status: WebDavStateSyncStatus.uploaded,
      manifest: manifest,
      snapshotPath: snapshotPath,
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
        previousDeviceSequences: manifest?.deviceSequences,
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
      previousDeviceSequences: manifest.deviceSequences,
    );
  }

  Future<List<WebDavSnapshotRecord>> listSnapshots() async {
    try {
      final entries = await _client.list(_paths.snapshotCollectionPath);
      final snapshots = entries
          .where((entry) => !entry.isCollection)
          .map(_snapshotRecordFromEntry)
          .whereType<WebDavSnapshotRecord>()
          .toList();
      snapshots.sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
      return snapshots;
    } on WebDavException catch (error) {
      if (error.statusCode == 404) {
        return const [];
      }
      rethrow;
    }
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

  WebDavSnapshotRecord? _snapshotRecordFromEntry(WebDavEntry entry) {
    final path = _entryRemotePath(entry.href);
    final fileName = path.split('/').last;
    final match =
        RegExp(r'^snapshot-(\d{8}T\d{9}Z)-(.+)\.json$').firstMatch(fileName);
    if (match == null) {
      return null;
    }
    final updatedAtUtc = _tryParseSnapshotStamp(match.group(1)!);
    if (updatedAtUtc == null) {
      return null;
    }
    return WebDavSnapshotRecord(
      path: path,
      deviceId: match.group(2)!,
      updatedAtUtc: updatedAtUtc,
      etag: entry.etag,
      contentLength: entry.contentLength,
      lastModifiedUtc: entry.lastModified?.toUtc(),
    );
  }

  String _entryRemotePath(String href) {
    var path = Uri.decodeComponent(href).replaceAll('\\', '/');
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final root = _paths.rootCollectionPath;
    if (root.isNotEmpty) {
      final marker = '/$root/';
      final markerIndex = path.indexOf(marker);
      if (markerIndex >= 0) {
        return _normalizeRemotePath(path.substring(markerIndex + 1));
      }
      if (path.startsWith(root)) {
        return _normalizeRemotePath(path);
      }
    }
    return _normalizeRemotePath(path);
  }

  Future<WebDavStateSyncResult> _downloadSnapshot(SyncManifest manifest) async {
    final bytes = await _client.getBytes(manifest.latestSnapshotPath);
    return WebDavStateSyncResult(
      status: WebDavStateSyncStatus.downloaded,
      state: _codec.decode(utf8.decode(bytes)),
      manifest: manifest,
      snapshotPath: manifest.latestSnapshotPath,
    );
  }

  Future<void> _ensureCollections() async {
    final root = _paths.rootCollectionPath;
    if (root.isNotEmpty) {
      await _client.makeCollection(root);
    }
    await _client.makeCollection(_paths.snapshotCollectionPath);
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

String _normalizeRemotePathSegment(String value) {
  final normalized = _normalizeDeviceId(value);
  return normalized.isEmpty ? 'local-device' : normalized;
}

String _normalizeDeviceId(String value) {
  final normalized = value.trim().toLowerCase();
  final cleaned = normalized.replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
  final collapsed = cleaned.replaceAll(RegExp('-+'), '-');
  final trimmed = collapsed.replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
  if (trimmed.length < 8) {
    return 'local-device';
  }
  return trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed;
}

String _formatSnapshotStamp(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  String three(int number) => number.toString().padLeft(3, '0');
  return '${utc.year}'
      '${two(utc.month)}'
      '${two(utc.day)}T'
      '${two(utc.hour)}'
      '${two(utc.minute)}'
      '${two(utc.second)}'
      '${three(utc.millisecond)}Z';
}

DateTime? _tryParseSnapshotStamp(String value) {
  if (!RegExp(r'^\d{8}T\d{9}Z$').hasMatch(value)) {
    return null;
  }
  try {
    return DateTime.utc(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
      int.parse(value.substring(9, 11)),
      int.parse(value.substring(11, 13)),
      int.parse(value.substring(13, 15)),
      int.parse(value.substring(15, 18)),
    );
  } on FormatException {
    return null;
  }
}

class WebDavSyncConfigurationException implements Exception {
  const WebDavSyncConfigurationException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
