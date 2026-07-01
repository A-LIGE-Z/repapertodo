import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/model/app_state.dart';
import '../../core/model/sync_settings.dart';
import '../../core/state/app_state_codec.dart';
import '../sync_device_id.dart';
import '../sync_manifest.dart';
import '../sync_operation.dart';
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
    this.operationDirectoryName = 'ops',
  });

  final String rootPath;
  final String manifestFileName;
  final String snapshotDirectoryName;
  final String operationDirectoryName;

  String get rootCollectionPath => _normalizeRemotePath(rootPath);

  String get manifestPath =>
      _joinRemotePath(rootCollectionPath, manifestFileName);

  String get snapshotCollectionPath =>
      _joinRemotePath(rootCollectionPath, snapshotDirectoryName);

  String get operationCollectionPath =>
      _joinRemotePath(rootCollectionPath, operationDirectoryName);

  String snapshotPath(DateTime updatedAtUtc, String deviceId) {
    final stamp = _formatSnapshotStamp(updatedAtUtc);
    final safeDeviceId = _normalizeRemotePathSegment(deviceId);
    return _joinRemotePath(
      snapshotCollectionPath,
      'snapshot-$stamp-$safeDeviceId.json',
    );
  }

  String operationLogPath(String deviceId, int sequence) {
    final safeDeviceId = _normalizeRemotePathSegment(deviceId);
    final safeSequence = sequence < 0 ? 0 : sequence;
    return _joinRemotePath(
      operationCollectionPath,
      '$safeDeviceId-${safeSequence.toString().padLeft(12, '0')}.jsonl',
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

class WebDavOperationLogRecord {
  const WebDavOperationLogRecord({
    required this.path,
    required this.deviceId,
    required this.sequence,
    this.etag,
    this.contentLength,
    this.lastModifiedUtc,
  });

  final String path;
  final String deviceId;
  final int sequence;
  final String? etag;
  final int? contentLength;
  final DateTime? lastModifiedUtc;
}

class WebDavOperationLogUploadResult {
  const WebDavOperationLogUploadResult({
    required this.deviceSequences,
    required this.uploadedCount,
  });

  final Map<String, int> deviceSequences;
  final int uploadedCount;
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
        normalizeSyncDeviceSequences(previousDeviceSequences);
    final nextSequence = (deviceSequences[_deviceId] ?? 0) + 1;
    deviceSequences[_deviceId] = nextSequence;
    await _putSnapshotOperation(
      state: state,
      updatedAtUtc: stamp,
      sequence: nextSequence,
      snapshotPath: snapshotPath,
    );
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

  Future<List<WebDavOperationLogRecord>> listOperationLogs() async {
    try {
      final entries = await _client.list(_paths.operationCollectionPath);
      final logs = entries
          .where((entry) => !entry.isCollection)
          .map(_operationLogRecordFromEntry)
          .whereType<WebDavOperationLogRecord>()
          .toList();
      logs.sort((a, b) {
        final deviceComparison = a.deviceId.compareTo(b.deviceId);
        if (deviceComparison != 0) {
          return deviceComparison;
        }
        return a.sequence.compareTo(b.sequence);
      });
      return logs;
    } on WebDavException catch (error) {
      if (error.statusCode == 404) {
        return const [];
      }
      rethrow;
    }
  }

  Future<WebDavStateSyncResult> downloadSnapshot(String snapshotPath) async {
    final normalizedPath = _normalizeSnapshotPath(snapshotPath);
    final bytes = await _client.getBytes(normalizedPath);
    return WebDavStateSyncResult(
      status: WebDavStateSyncStatus.downloaded,
      state: _codec.decode(utf8.decode(bytes)),
      snapshotPath: normalizedPath,
    );
  }

  Future<List<SyncOperation>> downloadOperationLog(
      String operationLogPath) async {
    final normalizedPath = _normalizeOperationLogPath(operationLogPath);
    final identity = _operationLogIdentityFromPath(normalizedPath);
    if (identity == null) {
      throw const WebDavSyncConfigurationException(
        'Operation log path must contain a valid device and sequence.',
      );
    }
    final bytes = await _client.getBytes(normalizedPath);
    final lines = utf8
        .decode(bytes)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length != 1) {
      throw const FormatException(
        'Operation log must contain exactly one operation.',
      );
    }
    return [
      _normalizeDownloadedOperation(
        _decodeOperation(lines.single),
        identity,
      ),
    ];
  }

  Future<WebDavOperationLogUploadResult> uploadOperationLogs(
    Iterable<SyncOperation> operations, {
    Map<String, int>? previousDeviceSequences,
  }) async {
    final deviceSequences =
        normalizeSyncDeviceSequences(previousDeviceSequences);
    final pendingOperations = operations
        .map(_normalizeOperationForUpload)
        .whereType<SyncOperation>()
        .where((operation) {
      return operation.sequence > (deviceSequences[operation.deviceId] ?? 0);
    }).toList()
      ..sort((a, b) {
        final deviceComparison = a.deviceId.compareTo(b.deviceId);
        if (deviceComparison != 0) {
          return deviceComparison;
        }
        return a.sequence.compareTo(b.sequence);
      });
    if (pendingOperations.isEmpty) {
      return WebDavOperationLogUploadResult(
        deviceSequences: deviceSequences,
        uploadedCount: 0,
      );
    }

    await _ensureCollections();
    for (final operation in pendingOperations) {
      await _putOperationLog(operation);
      deviceSequences[operation.deviceId] = operation.sequence;
    }
    return WebDavOperationLogUploadResult(
      deviceSequences: deviceSequences,
      uploadedCount: pendingOperations.length,
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

  WebDavOperationLogRecord? _operationLogRecordFromEntry(WebDavEntry entry) {
    final path = _entryRemotePath(entry.href);
    final identity = _operationLogIdentityFromPath(path);
    if (identity == null) {
      return null;
    }
    return WebDavOperationLogRecord(
      path: path,
      deviceId: identity.deviceId,
      sequence: identity.sequence,
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

  String _normalizeSnapshotPath(String snapshotPath) {
    final normalizedPath = _normalizeRemotePath(snapshotPath);
    final snapshotCollectionPath = _paths.snapshotCollectionPath;
    final expectedPrefix = '$snapshotCollectionPath/';
    if (!normalizedPath.startsWith(expectedPrefix)) {
      throw WebDavSyncConfigurationException(
        'Snapshot path must be inside $snapshotCollectionPath.',
      );
    }
    final fileName = normalizedPath.split('/').last;
    if (!RegExp(r'^snapshot-\d{8}T\d{9}Z-.+\.json$').hasMatch(fileName)) {
      throw const WebDavSyncConfigurationException(
        'Snapshot path must reference a RePaperTodo snapshot file.',
      );
    }
    return normalizedPath;
  }

  String _normalizeOperationLogPath(String operationLogPath) {
    final normalizedPath = _normalizeRemotePath(operationLogPath);
    final operationCollectionPath = _paths.operationCollectionPath;
    final expectedPrefix = '$operationCollectionPath/';
    if (!normalizedPath.startsWith(expectedPrefix)) {
      throw WebDavSyncConfigurationException(
        'Operation log path must be inside $operationCollectionPath.',
      );
    }
    final fileName = normalizedPath.split('/').last;
    if (!RegExp(r'^.+-\d{12}\.jsonl$').hasMatch(fileName)) {
      throw const WebDavSyncConfigurationException(
        'Operation log path must reference a RePaperTodo operation log file.',
      );
    }
    return normalizedPath;
  }

  SyncOperation _decodeOperation(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw const FormatException('Sync operation must be a JSON object.');
    }
    return SyncOperation.fromJson(Map<String, Object?>.from(decoded));
  }

  SyncOperation _normalizeDownloadedOperation(
    SyncOperation operation,
    _OperationLogIdentity identity,
  ) {
    return SyncOperation(
      id: '${identity.deviceId}-${identity.sequence}',
      deviceId: identity.deviceId,
      sequence: identity.sequence,
      kind: operation.kind,
      createdAtUtc: operation.createdAtUtc,
      payload: Map<String, Object?>.from(operation.payload),
    );
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
    await _client.makeCollection(_paths.operationCollectionPath);
  }

  Future<void> _putSnapshotOperation({
    required AppState state,
    required DateTime updatedAtUtc,
    required int sequence,
    required String snapshotPath,
  }) async {
    final operation = SyncOperation(
      id: '$_deviceId-$sequence',
      deviceId: _deviceId,
      sequence: sequence,
      kind: SyncOperationKind.stateSnapshot,
      createdAtUtc: updatedAtUtc,
      payload: {
        'snapshotPath': snapshotPath,
        'paperCount': state.papers.length,
      },
    );
    await _putOperationLog(operation);
  }

  Future<void> _putOperationLog(SyncOperation operation) async {
    await _client.putBytes(
      _paths.operationLogPath(operation.deviceId, operation.sequence),
      utf8.encode('${jsonEncode(operation.toJson())}\n'),
    );
  }

  SyncOperation? _normalizeOperationForUpload(SyncOperation operation) {
    if (operation.sequence <= 0 || operation.deviceId.trim().isEmpty) {
      return null;
    }
    final normalizedDeviceId = _normalizeDeviceId(operation.deviceId);
    return SyncOperation(
      id: '$normalizedDeviceId-${operation.sequence}',
      deviceId: normalizedDeviceId,
      sequence: operation.sequence,
      kind: operation.kind,
      createdAtUtc: operation.createdAtUtc,
      payload: Map<String, Object?>.from(operation.payload),
    );
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

class _OperationLogIdentity {
  const _OperationLogIdentity({
    required this.deviceId,
    required this.sequence,
  });

  final String deviceId;
  final int sequence;
}

_OperationLogIdentity? _operationLogIdentityFromPath(String path) {
  final fileName = path.split('/').last;
  final match = RegExp(r'^(.+)-(\d{12})\.jsonl$').firstMatch(fileName);
  if (match == null) {
    return null;
  }
  final sequence = int.tryParse(match.group(2)!);
  if (sequence == null) {
    return null;
  }
  final deviceId = normalizeSyncDeviceId(match.group(1)!, fallback: '');
  if (deviceId.isEmpty) {
    return null;
  }
  return _OperationLogIdentity(deviceId: deviceId, sequence: sequence);
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
  final normalized = normalizeSyncDeviceId(value, fallback: '');
  return normalized.isEmpty ? 'local-device' : normalized;
}

String _normalizeDeviceId(String value) {
  return normalizeSyncDeviceId(value);
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
