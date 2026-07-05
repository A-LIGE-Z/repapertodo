import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

import '../../core/model/app_state.dart';
import '../../core/model/sync_settings.dart';
import '../../core/state/app_state_codec.dart';
import '../sync_device_id.dart';
import '../sync_manifest.dart';
import '../sync_operation.dart';
import 'webdav_client.dart';
import 'webdav_payload_codec.dart';

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

  String snapshotPath(
    DateTime updatedAtUtc,
    String deviceId, {
    int? sequence,
  }) {
    if (sequence != null) {
      _validateRemoteSequence(sequence, 'Snapshot path sequence');
    }
    final stamp = _formatSnapshotStamp(updatedAtUtc);
    final safeDeviceId = _normalizeRemotePathSegment(deviceId);
    final safeSequence =
        sequence == null ? '' : '-seq-${_formatRemoteSequence(sequence)}';
    return _joinRemotePath(
      snapshotCollectionPath,
      'snapshot-$stamp-$safeDeviceId$safeSequence.json',
    );
  }

  String operationLogPath(String deviceId, int sequence) {
    _validateRemoteSequence(sequence, 'Operation log sequence');
    final safeDeviceId = _normalizeRemotePathSegment(deviceId);
    return _joinRemotePath(
      operationCollectionPath,
      '$safeDeviceId-${_formatRemoteSequence(sequence)}.jsonl',
    );
  }
}

void _validateRemoteSequence(int sequence, String label) {
  if (!_isRemoteSequenceInRange(sequence)) {
    throw WebDavSyncConfigurationException(
      '$label must be a 1 through $maxSyncDeviceSequence integer.',
    );
  }
}

bool _isRemoteSequenceInRange(int sequence) {
  return isSyncDeviceSequenceInRange(sequence);
}

String _formatRemoteSequence(int sequence) {
  return sequence.toString().padLeft(syncDeviceSequenceWireWidth, '0');
}

class WebDavStateSyncResult {
  const WebDavStateSyncResult({
    required this.status,
    this.state,
    this.manifest,
    this.manifestEtag,
    this.snapshotPath = '',
    this.snapshotPayloadFormat = WebDavPayloadFormat.unknown,
  });

  final WebDavStateSyncStatus status;
  final AppState? state;
  final SyncManifest? manifest;
  final String? manifestEtag;
  final String snapshotPath;
  final WebDavPayloadFormat snapshotPayloadFormat;
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

class WebDavOperationLogDownloadResult {
  const WebDavOperationLogDownloadResult({
    required this.path,
    required this.operations,
    this.payloadFormat = WebDavPayloadFormat.unknown,
  });

  final String path;
  final List<SyncOperation> operations;
  final WebDavPayloadFormat payloadFormat;
}

class WebDavOperationLogUploadResult {
  const WebDavOperationLogUploadResult({
    required this.deviceSequences,
    required this.uploadedCount,
    this.acceptedDeviceSequences = const <String, int>{},
  });

  final Map<String, int> deviceSequences;
  final int uploadedCount;
  final Map<String, int> acceptedDeviceSequences;
}

class WebDavStateSyncService {
  WebDavStateSyncService({
    required WebDavClient client,
    AppStateCodec codec = const AppStateCodec(),
    WebDavPayloadCodec payloadCodec = const PlainWebDavPayloadCodec(),
    WebDavStateSyncPaths paths = const WebDavStateSyncPaths(),
    String deviceId = 'local-device',
  })  : _client = client,
        _codec = codec,
        _payloadCodec = payloadCodec,
        _paths = paths,
        _deviceId = _normalizeDeviceId(deviceId);

  factory WebDavStateSyncService.fromSettings(
    WebDavSyncSettings settings, {
    AppStateCodec codec = const AppStateCodec(),
    WebDavPayloadCodec? payloadCodec,
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
        requestTimeout: Duration(seconds: settings.requestTimeoutSeconds),
      ),
      codec: codec,
      payloadCodec: payloadCodec ??
          (settings.usesEncryptedPayloads
              ? EncryptedWebDavPayloadCodec(
                  passphrase: settings.encryptionPassphrase,
                )
              : const PlainWebDavPayloadCodec()),
      paths: WebDavStateSyncPaths(rootPath: settings.rootPath),
      deviceId: deviceId ?? 'local-device',
    );
  }

  final WebDavClient _client;
  final AppStateCodec _codec;
  final WebDavPayloadCodec _payloadCodec;
  final WebDavStateSyncPaths _paths;
  final String _deviceId;

  void close() {
    _client.close();
  }

  Future<WebDavStateSyncResult> push(
    AppState state, {
    DateTime? updatedAtUtc,
    String? expectedManifestEtag,
    bool manifestKnownMissing = false,
    Map<String, int>? previousDeviceSequences,
    bool requireManifestCondition = false,
  }) async {
    _validateLocalDeviceId();
    _validatePaths();
    final deviceSequences =
        normalizeSyncDeviceSequences(previousDeviceSequences);
    final nextSequence = (deviceSequences[_deviceId] ?? 0) + 1;
    _validateRemoteSequence(nextSequence, 'Next device sequence');
    deviceSequences[_deviceId] = nextSequence;
    final stamp = (updatedAtUtc ?? DateTime.now().toUtc()).toUtc();
    await _ensureCollections();
    final snapshotPath = _paths.snapshotPath(
      stamp,
      _deviceId,
      sequence: nextSequence,
    );
    final snapshotBytes = await _payloadCodec.encodeSnapshot(state, _codec);
    await _putSnapshot(snapshotPath, snapshotBytes, state);
    final operationLogPath = _paths.operationLogPath(_deviceId, nextSequence);
    final snapshotOperationUploaded = await _putSnapshotOperation(
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
      requireCondition: requireManifestCondition,
    );
    if (!manifestUploaded) {
      if (snapshotOperationUploaded) {
        await _deleteOperationLogQuietly(operationLogPath);
      }
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
    final remoteManifest = await _loadManifestWithMetadata();
    final manifest = remoteManifest?.manifest;
    if (manifest == null || manifest.latestSnapshotPath.isEmpty) {
      return const WebDavStateSyncResult(
          status: WebDavStateSyncStatus.remoteMissing);
    }
    return _downloadSnapshot(manifest, manifestEtag: remoteManifest?.etag);
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
      return _downloadSnapshot(manifest, manifestEtag: remoteManifest?.etag);
    }

    return push(
      localState,
      updatedAtUtc: localStamp,
      expectedManifestEtag: remoteManifest?.etag,
      previousDeviceSequences: manifest.deviceSequences,
      requireManifestCondition: true,
    );
  }

  Future<List<WebDavSnapshotRecord>> listSnapshots() async {
    _validatePaths();
    try {
      final entries = await _client.list(_paths.snapshotCollectionPath);
      final snapshots = _deduplicateSnapshotRecords(
        entries
            .where((entry) => !entry.isCollection)
            .map(_snapshotRecordFromEntry)
            .whereType<WebDavSnapshotRecord>(),
      );
      snapshots.sort(_compareSnapshotRecordOrder);
      return snapshots;
    } on WebDavException catch (error) {
      if (_isMissingRemoteCollectionStatus(error.statusCode)) {
        return const [];
      }
      rethrow;
    }
  }

  List<WebDavSnapshotRecord> _deduplicateSnapshotRecords(
    Iterable<WebDavSnapshotRecord> records,
  ) {
    final recordsByPath = <String, WebDavSnapshotRecord>{};
    for (final record in records) {
      final existing = recordsByPath[record.path];
      if (existing == null ||
          _compareSnapshotRecordPreference(record, existing) < 0) {
        recordsByPath[record.path] = record;
      }
    }
    return recordsByPath.values.toList();
  }

  int _compareSnapshotRecordPreference(
    WebDavSnapshotRecord left,
    WebDavSnapshotRecord right,
  ) {
    final metadataComparison =
        _snapshotMetadataScore(right).compareTo(_snapshotMetadataScore(left));
    if (metadataComparison != 0) {
      return metadataComparison;
    }
    final etagComparison = (left.etag ?? '').compareTo(right.etag ?? '');
    if (etagComparison != 0) {
      return etagComparison;
    }
    final contentLengthComparison =
        (left.contentLength ?? -1).compareTo(right.contentLength ?? -1);
    if (contentLengthComparison != 0) {
      return contentLengthComparison;
    }
    return (left.lastModifiedUtc?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .compareTo(
      right.lastModifiedUtc?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  int _compareSnapshotRecordOrder(
    WebDavSnapshotRecord left,
    WebDavSnapshotRecord right,
  ) {
    final updatedComparison = right.updatedAtUtc.compareTo(left.updatedAtUtc);
    if (updatedComparison != 0) {
      return updatedComparison;
    }
    final pathComparison = left.path.compareTo(right.path);
    if (pathComparison != 0) {
      return pathComparison;
    }
    final etagComparison = (left.etag ?? '').compareTo(right.etag ?? '');
    if (etagComparison != 0) {
      return etagComparison;
    }
    final contentLengthComparison =
        (left.contentLength ?? -1).compareTo(right.contentLength ?? -1);
    if (contentLengthComparison != 0) {
      return contentLengthComparison;
    }
    return (left.lastModifiedUtc?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .compareTo(
      right.lastModifiedUtc?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Future<List<WebDavOperationLogRecord>> listOperationLogs() async {
    _validatePaths();
    try {
      final entries = await _client.list(_paths.operationCollectionPath);
      final logs = _deduplicateOperationLogRecords(
        entries
            .where((entry) => !entry.isCollection)
            .map(_operationLogRecordFromEntry)
            .whereType<WebDavOperationLogRecord>(),
      );
      logs.sort((a, b) {
        final deviceComparison = a.deviceId.compareTo(b.deviceId);
        if (deviceComparison != 0) {
          return deviceComparison;
        }
        return a.sequence.compareTo(b.sequence);
      });
      return logs;
    } on WebDavException catch (error) {
      if (_isMissingRemoteCollectionStatus(error.statusCode)) {
        return const [];
      }
      rethrow;
    }
  }

  List<WebDavOperationLogRecord> _deduplicateOperationLogRecords(
    Iterable<WebDavOperationLogRecord> records,
  ) {
    final recordsByIdentity = <String, WebDavOperationLogRecord>{};
    for (final record in records) {
      final key = '${record.deviceId}\u0000${record.sequence}';
      final existing = recordsByIdentity[key];
      if (existing == null ||
          _compareOperationLogRecordPreference(record, existing) < 0) {
        recordsByIdentity[key] = record;
      }
    }
    return recordsByIdentity.values.toList();
  }

  int _compareOperationLogRecordPreference(
    WebDavOperationLogRecord left,
    WebDavOperationLogRecord right,
  ) {
    final leftIsCanonical =
        left.path == _paths.operationLogPath(left.deviceId, left.sequence);
    final rightIsCanonical =
        right.path == _paths.operationLogPath(right.deviceId, right.sequence);
    if (leftIsCanonical != rightIsCanonical) {
      return leftIsCanonical ? -1 : 1;
    }

    final metadataComparison = _operationLogMetadataScore(right)
        .compareTo(_operationLogMetadataScore(left));
    if (metadataComparison != 0) {
      return metadataComparison;
    }

    final pathComparison = left.path.compareTo(right.path);
    if (pathComparison != 0) {
      return pathComparison;
    }
    final etagComparison = (left.etag ?? '').compareTo(right.etag ?? '');
    if (etagComparison != 0) {
      return etagComparison;
    }
    final contentLengthComparison =
        (left.contentLength ?? -1).compareTo(right.contentLength ?? -1);
    if (contentLengthComparison != 0) {
      return contentLengthComparison;
    }
    return (left.lastModifiedUtc?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .compareTo(
      right.lastModifiedUtc?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Future<WebDavStateSyncResult> downloadSnapshot(String snapshotPath) async {
    _validateRootPath();
    final normalizedPath = _normalizeSnapshotPath(snapshotPath);
    final bytes = await _client.getBytes(normalizedPath);
    return WebDavStateSyncResult(
      status: WebDavStateSyncStatus.downloaded,
      state: await _payloadCodec.decodeSnapshot(bytes, _codec),
      snapshotPath: normalizedPath,
      snapshotPayloadFormat: _payloadCodec.inspectPayloadFormat(bytes),
    );
  }

  Future<List<SyncOperation>> downloadOperationLog(
      String operationLogPath) async {
    final result = await downloadOperationLogWithMetadata(operationLogPath);
    return result.operations;
  }

  Future<WebDavOperationLogDownloadResult> downloadOperationLogWithMetadata(
      String operationLogPath) async {
    _validateRootPath();
    final normalizedPath = _normalizeOperationLogPath(operationLogPath);
    final identity = _operationLogIdentityFromPath(normalizedPath);
    if (identity == null) {
      throw const WebDavSyncConfigurationException(
        'Operation log path must contain a valid device and sequence.',
      );
    }
    final bytes = await _client.getBytes(normalizedPath);
    final operations = await _payloadCodec.decodeOperationLog(bytes);
    if (operations.length != 1) {
      throw const FormatException(
        'Operation log must contain exactly one operation.',
      );
    }
    return WebDavOperationLogDownloadResult(
      path: normalizedPath,
      payloadFormat: _payloadCodec.inspectPayloadFormat(bytes),
      operations: [
        _normalizeDownloadedOperation(
          operations.single,
          identity,
        ),
      ],
    );
  }

  Future<bool> migrateLegacyPlainOperationLog(
    WebDavOperationLogRecord record, {
    WebDavOperationLogDownloadResult? downloadedResult,
  }) async {
    _validateRootPath();
    final etag = _nonBlankRemoteValue(record.etag);
    if (etag == null) {
      return false;
    }
    final ifMatch = _ifMatchHeaderValue(etag);
    if (ifMatch == null) {
      return false;
    }
    final normalizedPath = _normalizeOperationLogPath(record.path);
    final identity = _operationLogIdentityFromPath(normalizedPath);
    final normalizedRecordDeviceId = normalizeSyncDeviceId(
      record.deviceId,
      fallback: '',
    );
    if (identity == null ||
        normalizedRecordDeviceId != identity.deviceId ||
        record.sequence != identity.sequence) {
      return false;
    }
    final result =
        downloadedResult ?? await downloadOperationLogWithMetadata(record.path);
    if (result.path != normalizedPath ||
        result.payloadFormat != WebDavPayloadFormat.plainJson ||
        result.operations.length != 1) {
      return false;
    }
    final encryptedBytes =
        await _payloadCodec.encodeOperationLog(result.operations.single);
    if (_payloadCodec.inspectPayloadFormat(encryptedBytes) !=
        WebDavPayloadFormat.encrypted) {
      return false;
    }
    try {
      await _client.putBytes(
        normalizedPath,
        encryptedBytes,
        ifMatch: ifMatch,
      );
      return true;
    } on WebDavException catch (error) {
      if (error.statusCode == 412) {
        return false;
      }
      rethrow;
    }
  }

  Future<WebDavOperationLogUploadResult> uploadOperationLogs(
    Iterable<SyncOperation> operations, {
    Map<String, int>? previousDeviceSequences,
  }) async {
    _validateRootPath();
    final deviceSequences =
        normalizeSyncDeviceSequences(previousDeviceSequences);
    final candidates = operations
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
    final pendingOperations = _contiguousOperationsForUpload(
      candidates,
      deviceSequences,
    );
    if (pendingOperations.isEmpty) {
      return WebDavOperationLogUploadResult(
        deviceSequences: deviceSequences,
        uploadedCount: 0,
      );
    }

    await _ensureCollections();
    var uploadedCount = 0;
    for (final operation in pendingOperations) {
      final uploaded = await _putOperationLog(operation);
      if (uploaded) {
        uploadedCount += 1;
      }
      deviceSequences[operation.deviceId] = operation.sequence;
    }
    return WebDavOperationLogUploadResult(
      deviceSequences: deviceSequences,
      uploadedCount: uploadedCount,
      acceptedDeviceSequences: _operationDeviceSequences(pendingOperations),
    );
  }

  Future<_RemoteManifest?> _loadManifestWithMetadata() async {
    _validatePaths();
    final metadata = await _client.metadata(_paths.manifestPath);
    if (metadata == null) {
      return null;
    }
    late final List<int> bytes;
    try {
      bytes = await _client.getBytes(_paths.manifestPath);
    } on WebDavException catch (error) {
      if (_isMissingRemoteCollectionStatus(error.statusCode)) {
        return null;
      }
      rethrow;
    }
    return _RemoteManifest(
      manifest: SyncManifest.fromJson(
        decodeJsonObject(_decodeManifestText(bytes)),
      ),
      etag: metadata.etag,
    );
  }

  WebDavSnapshotRecord? _snapshotRecordFromEntry(WebDavEntry entry) {
    final path = _tryNormalizeEntryPath(entry.href, _normalizeSnapshotPath);
    if (path == null) {
      return null;
    }
    final fileName = path.split('/').last;
    final match = _snapshotFileNamePattern.firstMatch(fileName);
    if (match == null) {
      return null;
    }
    final updatedAtUtc = _tryParseSnapshotStamp(match.group(1)!);
    if (updatedAtUtc == null) {
      return null;
    }
    final deviceId = _normalizeSnapshotRecordDeviceId(match.group(2)!);
    if (deviceId.isEmpty) {
      return null;
    }
    return WebDavSnapshotRecord(
      path: path,
      deviceId: deviceId,
      updatedAtUtc: updatedAtUtc,
      etag: entry.etag,
      contentLength: entry.contentLength,
      lastModifiedUtc: entry.lastModified?.toUtc(),
    );
  }

  WebDavOperationLogRecord? _operationLogRecordFromEntry(WebDavEntry entry) {
    final path = _tryNormalizeEntryPath(entry.href, _normalizeOperationLogPath);
    if (path == null) {
      return null;
    }
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
    final absolutePath = _absoluteHrefPath(href);
    var path = absolutePath ?? href.trim();
    if (!_hasUnambiguousEncodedPathSegments(path) ||
        !_hasStableDecodedPathSegments(path)) {
      throw const WebDavSyncConfigurationException(
        'WebDAV entry href must stay on the configured endpoint origin and path.',
      );
    }
    path = _decodeRemotePath(path).replaceAll('\\', '/');
    final isServerAbsolutePath = absolutePath != null || path.startsWith('/');
    if (absolutePath == null && _looksLikeAbsoluteHrefPath(path)) {
      throw const WebDavSyncConfigurationException(
        'WebDAV entry href must stay on the configured endpoint origin and path.',
      );
    }
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final root = _paths.rootCollectionPath;
    if (root.isNotEmpty) {
      final marker = '/$root/';
      final markerIndex = path.lastIndexOf(marker);
      if (isServerAbsolutePath && markerIndex >= 0) {
        return _normalizeDecodedRemotePath(path.substring(markerIndex + 1));
      }
      if (path == root || path.startsWith('$root/')) {
        return _normalizeDecodedRemotePath(path);
      }
    }
    return _normalizeDecodedRemotePath(path);
  }

  String? _absoluteHrefPath(String href) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null) {
      return null;
    }
    if (!uri.hasScheme) {
      if (uri.hasAuthority) {
        throw const WebDavSyncConfigurationException(
          'WebDAV entry href must stay on the configured endpoint origin and path.',
        );
      }
      return null;
    }
    if (!_hasSameOrigin(uri, _client.baseUri) ||
        !_hasUnambiguousEncodedPathSegments(uri.path) ||
        !_absoluteHrefStaysBelowBasePath(uri) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const WebDavSyncConfigurationException(
        'WebDAV entry href must stay on the configured endpoint origin and path.',
      );
    }
    return uri.path;
  }

  bool _absoluteHrefStaysBelowBasePath(Uri uri) {
    final baseSegments = _absolutePathSegments(_client.baseUri.path);
    if (baseSegments.isEmpty) {
      return true;
    }
    final entrySegments = _absolutePathSegments(uri.path);
    if (entrySegments.length < baseSegments.length) {
      return false;
    }
    for (var index = 0; index < baseSegments.length; index += 1) {
      if (entrySegments[index] != baseSegments[index]) {
        return false;
      }
    }
    return true;
  }

  String? _tryNormalizeEntryPath(
    String href,
    String Function(String path) normalize,
  ) {
    try {
      return normalize(_entryRemotePath(href));
    } on WebDavSyncConfigurationException {
      return null;
    }
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
    final fileName = normalizedPath.substring(expectedPrefix.length);
    if (fileName.contains('/')) {
      throw const WebDavSyncConfigurationException(
        'Snapshot path must reference a direct snapshot file.',
      );
    }
    final match = _snapshotFileNamePattern.firstMatch(fileName);
    if (match == null) {
      throw const WebDavSyncConfigurationException(
        'Snapshot path must reference a RePaperTodo snapshot file.',
      );
    }
    if (match.group(3) == null &&
        RegExp(r'-seq-\d+\.json$').hasMatch(fileName)) {
      throw const WebDavSyncConfigurationException(
        'Snapshot path sequence must be a positive integer within the supported range.',
      );
    }
    if (_tryParseSnapshotStamp(match.group(1)!) == null) {
      throw const WebDavSyncConfigurationException(
        'Snapshot path must contain a valid timestamp.',
      );
    }
    if (_normalizeSnapshotRecordDeviceId(match.group(2)!).isEmpty) {
      throw const WebDavSyncConfigurationException(
        'Snapshot path must contain a valid device id.',
      );
    }
    final sequence = match.group(3);
    final parsedSequence = sequence == null ? null : int.tryParse(sequence);
    if (sequence != null && !_isRemoteSequenceInRange(parsedSequence ?? 0)) {
      throw const WebDavSyncConfigurationException(
        'Snapshot path sequence must be a positive integer within the supported range.',
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
    final fileName = normalizedPath.substring(expectedPrefix.length);
    if (fileName.contains('/')) {
      throw const WebDavSyncConfigurationException(
        'Operation log path must reference a direct operation log file.',
      );
    }
    if (!_operationLogFileNamePattern.hasMatch(fileName)) {
      throw const WebDavSyncConfigurationException(
        'Operation log path must reference a RePaperTodo operation log file.',
      );
    }
    return normalizedPath;
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

  Future<WebDavStateSyncResult> _downloadSnapshot(
    SyncManifest manifest, {
    String? manifestEtag,
  }) async {
    final snapshotPath = _normalizeSnapshotPath(manifest.latestSnapshotPath);
    final bytes = await _client.getBytes(snapshotPath);
    return WebDavStateSyncResult(
      status: WebDavStateSyncStatus.downloaded,
      state: await _payloadCodec.decodeSnapshot(bytes, _codec),
      manifest: manifest,
      manifestEtag: manifestEtag,
      snapshotPath: snapshotPath,
      snapshotPayloadFormat: _payloadCodec.inspectPayloadFormat(bytes),
    );
  }

  Future<void> _ensureCollections() async {
    final ensured = <String>{};
    Future<void> ensurePath(String path) async {
      final normalizedPath = _normalizeRemotePath(path);
      if (normalizedPath.isEmpty) {
        return;
      }
      final segments = normalizedPath.split('/');
      for (var index = 1; index <= segments.length; index += 1) {
        final collectionPath = segments.take(index).join('/');
        if (ensured.add(collectionPath)) {
          await _client.makeCollection(collectionPath);
        }
      }
    }

    await ensurePath(_paths.rootCollectionPath);
    await ensurePath(_paths.snapshotCollectionPath);
    await ensurePath(_paths.operationCollectionPath);
  }

  Future<bool> _putSnapshot(
    String snapshotPath,
    List<int> bytes,
    AppState state,
  ) async {
    try {
      await _client.putBytes(
        snapshotPath,
        bytes,
        createOnly: true,
      );
      return true;
    } on WebDavException catch (error) {
      if (!_isCreateOnlyConflictStatus(error.statusCode)) {
        rethrow;
      }
      final existingBytes = await _getBytesOrRethrowOriginal(
        snapshotPath,
        originalError: error,
      );
      if (!await _snapshotBytesMatchOrRethrowOriginal(
        existingBytes,
        bytes,
        state,
        originalError: error,
      )) {
        _throwWebDavException(error);
      }
      return false;
    }
  }

  Future<bool> _snapshotsMatch(List<int> existingBytes, AppState state) async {
    final existingState = await _payloadCodec.decodeSnapshot(
      existingBytes,
      _codec,
    );
    return _canonicalRemoteSnapshot(existingState) ==
        _canonicalRemoteSnapshot(state);
  }

  Future<bool> _snapshotBytesMatchOrRethrowOriginal(
    List<int> existingBytes,
    List<int> uploadedBytes,
    AppState state, {
    required WebDavException originalError,
  }) async {
    if (const ListEquality<int>().equals(existingBytes, uploadedBytes)) {
      return true;
    }
    try {
      return await _snapshotsMatch(existingBytes, state);
    } on FormatException {
      _throwWebDavException(originalError);
    } on WebDavPayloadDecryptionException {
      _throwWebDavException(originalError);
    }
  }

  String _canonicalRemoteSnapshot(AppState state) {
    return _codec.encodeRemoteSnapshot(AppState.fromJson(state.toJson()));
  }

  Future<bool> _putSnapshotOperation({
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
    return _putOperationLog(operation);
  }

  Future<bool> _putOperationLog(SyncOperation operation) async {
    final operationLogPath = _paths.operationLogPath(
      operation.deviceId,
      operation.sequence,
    );
    try {
      await _client.putBytes(
        operationLogPath,
        await _payloadCodec.encodeOperationLog(operation),
        createOnly: true,
      );
      return true;
    } on WebDavException catch (error) {
      if (!_isCreateOnlyConflictStatus(error.statusCode)) {
        rethrow;
      }
      final existingOperations = await _downloadOperationLogOrRethrowOriginal(
        operationLogPath,
        originalError: error,
      );
      if (existingOperations.length != 1 ||
          !_operationsMatch(existingOperations.single, operation)) {
        _throwWebDavException(error);
      }
      return false;
    }
  }

  Future<List<int>> _getBytesOrRethrowOriginal(
    String path, {
    required WebDavException originalError,
  }) async {
    try {
      return await _client.getBytes(path);
    } on WebDavException {
      throw originalError;
    }
  }

  Future<List<SyncOperation>> _downloadOperationLogOrRethrowOriginal(
    String path, {
    required WebDavException originalError,
  }) async {
    try {
      return await downloadOperationLog(path);
    } on WebDavException {
      _throwWebDavException(originalError);
    } on FormatException {
      _throwWebDavException(originalError);
    } on WebDavPayloadDecryptionException {
      _throwWebDavException(originalError);
    }
  }

  Future<void> _deleteOperationLogQuietly(String operationLogPath) async {
    try {
      await _client.delete(operationLogPath);
    } on Object {
      // Preserve the original sync conflict result even if cleanup fails.
    }
  }

  SyncOperation? _normalizeOperationForUpload(SyncOperation operation) {
    if (!_isRemoteSequenceInRange(operation.sequence)) {
      return null;
    }
    final normalizedDeviceId = normalizeSyncDeviceId(
      operation.deviceId,
      fallback: '',
    );
    if (normalizedDeviceId.isEmpty) {
      return null;
    }
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
    bool requireCondition = false,
  }) async {
    final ifMatch = expectedManifestEtag == null
        ? null
        : _ifMatchHeaderValue(expectedManifestEtag);
    if (!createOnly &&
        (ifMatch == null &&
            (requireCondition || expectedManifestEtag != null))) {
      return false;
    }
    try {
      await _client.putBytes(
        _paths.manifestPath,
        utf8.encode(jsonEncode(manifest.toJson())),
        ifMatch: ifMatch,
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

  void _validatePaths() {
    _validateRootPath();
    _paths.manifestPath;
    _paths.snapshotCollectionPath;
    _paths.operationCollectionPath;
  }

  void _validateLocalDeviceId() {
    if (_deviceId.isEmpty) {
      throw const WebDavSyncConfigurationException(
        'Remote path device id must not be blank.',
      );
    }
  }

  void _validateRootPath() {
    if (_paths.rootCollectionPath.isEmpty) {
      throw const WebDavSyncConfigurationException(
        'Remote root path must not be blank.',
      );
    }
  }
}

bool _operationsMatch(SyncOperation left, SyncOperation right) {
  return left.id == right.id &&
      left.deviceId == right.deviceId &&
      left.sequence == right.sequence &&
      left.kind == right.kind &&
      left.createdAtUtc.toUtc().isAtSameMomentAs(right.createdAtUtc.toUtc()) &&
      const DeepCollectionEquality().equals(left.payload, right.payload);
}

List<SyncOperation> _contiguousOperationsForUpload(
  Iterable<SyncOperation> operations,
  Map<String, int> previousSequences,
) {
  final selected = <SyncOperation>[];
  final operationsByDevice = <String, List<SyncOperation>>{};
  for (final operation in operations) {
    operationsByDevice
        .putIfAbsent(operation.deviceId, () => <SyncOperation>[])
        .add(operation);
  }

  final deviceIds = operationsByDevice.keys.toList()..sort();
  for (final deviceId in deviceIds) {
    final deviceOperations = operationsByDevice[deviceId]!
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    var expectedSequence = (previousSequences[deviceId] ?? 0) + 1;
    var cursor = 0;
    while (cursor < deviceOperations.length) {
      final sequence = deviceOperations[cursor].sequence;
      final groupStart = cursor;
      while (cursor < deviceOperations.length &&
          deviceOperations[cursor].sequence == sequence) {
        cursor += 1;
      }
      if (sequence < expectedSequence) {
        continue;
      }
      if (sequence > expectedSequence) {
        break;
      }
      final operation = deviceOperations[groupStart];
      var hasConflictingDuplicate = false;
      for (var index = groupStart + 1; index < cursor; index += 1) {
        if (!_operationsMatch(operation, deviceOperations[index])) {
          hasConflictingDuplicate = true;
          break;
        }
      }
      if (hasConflictingDuplicate) {
        break;
      }
      selected.add(operation);
      expectedSequence += 1;
    }
  }
  return selected;
}

Map<String, int> _operationDeviceSequences(Iterable<SyncOperation> operations) {
  final sequences = <String, int>{};
  for (final operation in operations) {
    final previous = sequences[operation.deviceId] ?? 0;
    if (operation.sequence > previous) {
      sequences[operation.deviceId] = operation.sequence;
    }
  }
  return normalizeSyncDeviceSequences(sequences);
}

int _snapshotMetadataScore(WebDavSnapshotRecord record) {
  return (record.etag == null ? 0 : 4) +
      (record.contentLength == null ? 0 : 2) +
      (record.lastModifiedUtc == null ? 0 : 1);
}

int _operationLogMetadataScore(WebDavOperationLogRecord record) {
  return (record.etag == null ? 0 : 4) +
      (record.contentLength == null ? 0 : 2) +
      (record.lastModifiedUtc == null ? 0 : 1);
}

bool _isCreateOnlyConflictStatus(int statusCode) {
  return statusCode == 409 || statusCode == 412;
}

Never _throwWebDavException(WebDavException error) {
  throw error;
}

String? _nonBlankRemoteValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

String? _ifMatchHeaderValue(String etag) {
  final trimmed = etag.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('w/')) {
    return null;
  }
  if (trimmed.startsWith('"') || trimmed.contains('"')) {
    return trimmed;
  }
  return '"$trimmed"';
}

String _decodeManifestText(List<int> bytes) {
  final text = utf8.decode(bytes);
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
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
  final match = _operationLogIdentityPattern.firstMatch(fileName);
  if (match == null) {
    return null;
  }
  final sequence = int.tryParse(match.group(2)!);
  if (sequence == null || !_isRemoteSequenceInRange(sequence)) {
    return null;
  }
  final deviceId = normalizeSyncDeviceId(match.group(1)!, fallback: '');
  if (deviceId.isEmpty) {
    return null;
  }
  return _OperationLogIdentity(deviceId: deviceId, sequence: sequence);
}

final _operationLogFileNamePattern = RegExp(
  '^.+-\\d{$syncDeviceSequenceWireWidth}\\.jsonl\$',
);

final _operationLogIdentityPattern = RegExp(
  '^(.+)-(\\d{$syncDeviceSequenceWireWidth})\\.jsonl\$',
);

final _snapshotFileNamePattern = RegExp(
  '^snapshot-(\\d{8}T\\d{9}Z)-(.+?)(?:-seq-'
  '(\\d{$syncDeviceSequenceWireWidth}))?\\.json\$',
);

String _joinRemotePath(String base, String child) {
  final normalizedChild = _normalizeRemotePath(child);
  if (normalizedChild.isEmpty) {
    throw const WebDavSyncConfigurationException(
      'Remote path component must not be blank.',
    );
  }
  if (normalizedChild.contains('/')) {
    throw const WebDavSyncConfigurationException(
      'Remote path component must not contain path separators.',
    );
  }
  if (base.isEmpty) {
    return normalizedChild;
  }
  return '$base/$normalizedChild';
}

String _normalizeRemotePath(String path) {
  if (!_hasUnambiguousEncodedPathSegments(path)) {
    throw const WebDavSyncConfigurationException(
      'Remote path segments must not decode to path separators.',
    );
  }
  return _normalizeDecodedRemotePath(_decodeRemotePath(path));
}

bool _looksLikeAbsoluteHrefPath(String path) {
  return path.startsWith('//') || (Uri.tryParse(path)?.hasScheme ?? false);
}

bool _hasUnambiguousEncodedPathSegments(String path) {
  final segments = path.split('/');
  for (var index = 0; index < segments.length; index += 1) {
    final segment = segments[index];
    if (segment.isEmpty && index > 0 && index < segments.length - 1) {
      return false;
    }
    final decoded = _decodeRemotePath(segment);
    if (decoded.contains('/') || decoded.contains('\\')) {
      return false;
    }
    final trimmed = decoded.trim();
    if (segment.isNotEmpty && trimmed.isEmpty) {
      return false;
    }
    if (segment.isNotEmpty && trimmed != decoded) {
      return false;
    }
    if (trimmed == '.' || trimmed == '..') {
      return false;
    }
  }
  return true;
}

bool _hasStableDecodedPathSegments(String path) {
  for (final segment in path.split('/')) {
    if (segment.isEmpty) {
      continue;
    }
    late final String decoded;
    try {
      decoded = Uri.decodeComponent(segment);
    } on ArgumentError {
      return false;
    } on FormatException {
      return false;
    }
    if (decoded.trim() != decoded) {
      return false;
    }
  }
  return true;
}

String _decodeRemotePath(String path) {
  try {
    return Uri.decodeComponent(path.trim());
  } on ArgumentError {
    throw const WebDavSyncConfigurationException(
      'Remote path contains invalid percent encoding.',
    );
  } on FormatException {
    throw const WebDavSyncConfigurationException(
      'Remote path contains invalid percent encoding.',
    );
  }
}

String _normalizeDecodedRemotePath(String path) {
  final segments = <String>[];
  final rawSegments = path.trim().replaceAll('\\', '/').split('/');
  for (var index = 0; index < rawSegments.length; index += 1) {
    final segment = rawSegments[index];
    if (segment.isEmpty && index > 0 && index < rawSegments.length - 1) {
      throw const WebDavSyncConfigurationException(
        'Remote path must not contain blank path segments.',
      );
    }
    if (_hasControlCharacter(segment)) {
      throw const WebDavSyncConfigurationException(
        'Remote path must not contain control characters.',
      );
    }
    final trimmed = segment.trim();
    if (segment.isNotEmpty && trimmed.isEmpty) {
      throw const WebDavSyncConfigurationException(
        'Remote path segments must not collapse to blank.',
      );
    }
    if (trimmed.isEmpty || trimmed == '.') {
      continue;
    }
    if (trimmed == '..') {
      throw const WebDavSyncConfigurationException(
        'Remote path must not contain parent-directory segments.',
      );
    }
    segments.add(trimmed);
  }
  return segments.join('/');
}

bool _hasControlCharacter(String value) {
  return value.codeUnits.any((unit) => unit <= 0x1F || unit == 0x7F);
}

bool _isMissingRemoteCollectionStatus(int statusCode) {
  return statusCode == 404 || statusCode == 410;
}

List<String> _absolutePathSegments(String path) {
  return _decodeRemotePath(path)
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
}

bool _hasSameOrigin(Uri left, Uri right) {
  return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      _effectivePort(left) == _effectivePort(right);
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

String _normalizeRemotePathSegment(String value) {
  final normalized = normalizeSyncDeviceId(value, fallback: '');
  if (normalized.isEmpty) {
    throw const WebDavSyncConfigurationException(
      'Remote path device id must not be blank.',
    );
  }
  return normalized;
}

String _normalizeSnapshotRecordDeviceId(String value) {
  return normalizeSyncDeviceIdForDisplay(value);
}

String _normalizeDeviceId(String value) {
  return normalizeSyncDeviceId(value, fallback: '');
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
    final parsed = DateTime.utc(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
      int.parse(value.substring(9, 11)),
      int.parse(value.substring(11, 13)),
      int.parse(value.substring(13, 15)),
      int.parse(value.substring(15, 18)),
    );
    return _formatSnapshotStamp(parsed) == value ? parsed : null;
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
