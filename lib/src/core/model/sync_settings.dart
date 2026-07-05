import 'json_helpers.dart';
import 'sync_device_id.dart';
import 'sync_wire_datetime.dart';
import 'webdav_presets.dart';

abstract final class SyncProviderIds {
  static const none = 'none';
  static const webDav = 'webDav';

  static String normalize(String? value) {
    return value?.trim().toLowerCase() == webDav.toLowerCase() ? webDav : none;
  }
}

class SyncSettings {
  SyncSettings({
    this.enabled = false,
    this.provider = SyncProviderIds.none,
    WebDavSyncSettings? webDav,
    Map<String, int>? operationDeviceSequences,
    Map<String, String>? deletedPaperTombstones,
    Map<String, Map<String, String>>? deletedTodoItemTombstones,
    JsonMap? extra,
  })  : webDav = webDav ?? WebDavSyncSettings(),
        operationDeviceSequences =
            normalizeSyncDeviceSequences(operationDeviceSequences),
        deletedPaperTombstones = deletedPaperTombstones ?? <String, String>{},
        deletedTodoItemTombstones =
            deletedTodoItemTombstones ?? <String, Map<String, String>>{},
        extra = extra ?? <String, Object?>{};

  static const _knownKeys = {
    'enabled',
    'provider',
    'webDav',
    'operationDeviceSequences',
    'deletedPaperTombstones',
    'deletedTodoItemTombstones',
  };

  bool enabled;
  String provider;
  WebDavSyncSettings webDav;
  Map<String, int> operationDeviceSequences;
  Map<String, String> deletedPaperTombstones;
  Map<String, Map<String, String>> deletedTodoItemTombstones;
  JsonMap extra;

  factory SyncSettings.fromJson(JsonMap json) {
    final webDavJson = json['webDav'];
    return SyncSettings(
      enabled: boolValue(json['enabled'], false),
      provider: stringValue(json['provider'], SyncProviderIds.none),
      webDav: webDavJson is Map
          ? WebDavSyncSettings.fromJson(Map<String, Object?>.from(webDavJson))
          : null,
      operationDeviceSequences:
          _syncDeviceSequencesFromWire(json['operationDeviceSequences']),
      deletedPaperTombstones:
          _normalizeTombstoneMap(json['deletedPaperTombstones']),
      deletedTodoItemTombstones:
          _normalizeNestedTombstoneMap(json['deletedTodoItemTombstones']),
      extra: preserveUnknown(json, _knownKeys),
    )..normalize();
  }

  void normalize() {
    provider = SyncProviderIds.normalize(provider);
    webDav.normalize();
    operationDeviceSequences = normalizeSyncDeviceSequences(
      operationDeviceSequences,
    );
    deletedPaperTombstones = _normalizeTombstoneMap(deletedPaperTombstones);
    deletedTodoItemTombstones =
        _normalizeNestedTombstoneMap(deletedTodoItemTombstones);
    _removeTodoItemTombstonesCoveredByPaperTombstones();
    if (enabled && provider == SyncProviderIds.none) {
      provider = SyncProviderIds.webDav;
    }
  }

  bool isPaperDeleted(String paperId) {
    return deletedPaperTombstones.containsKey(paperId.trim());
  }

  DateTime? paperDeletedAtUtc(String paperId) {
    return tryParseStrictSyncWireDateTimeUtc(
      deletedPaperTombstones[paperId.trim()] ?? '',
    );
  }

  bool markPaperDeleted(String paperId, DateTime deletedAtUtc) {
    final id = paperId.trim();
    if (id.isEmpty) {
      return false;
    }
    final tombstoneChanged = _putLatestTombstone(
      deletedPaperTombstones,
      id,
      _tombstoneTimestamp(deletedAtUtc),
    );
    final effectiveDeletedAtUtc = paperDeletedAtUtc(id);
    final itemTombstonesChanged = effectiveDeletedAtUtc != null &&
        _removeCoveredTodoItemTombstones(id, effectiveDeletedAtUtc);
    return tombstoneChanged || itemTombstonesChanged;
  }

  bool _removeCoveredTodoItemTombstones(
    String paperId,
    DateTime paperDeletedAtUtc,
  ) {
    final itemTombstones = deletedTodoItemTombstones[paperId];
    if (itemTombstones == null) {
      return false;
    }
    final beforeCount = itemTombstones.length;
    final paperDeletedAt = paperDeletedAtUtc.toUtc();
    itemTombstones.removeWhere((_, timestamp) {
      final itemDeletedAt = tryParseStrictSyncWireDateTimeUtc(timestamp);
      return itemDeletedAt == null || !itemDeletedAt.isAfter(paperDeletedAt);
    });
    if (itemTombstones.isEmpty) {
      deletedTodoItemTombstones.remove(paperId);
    }
    return itemTombstones.length != beforeCount;
  }

  bool _removeTodoItemTombstonesCoveredByPaperTombstones() {
    var changed = false;
    for (final entry in deletedPaperTombstones.entries) {
      final deletedAtUtc = tryParseStrictSyncWireDateTimeUtc(entry.value);
      if (deletedAtUtc == null) {
        continue;
      }
      changed =
          _removeCoveredTodoItemTombstones(entry.key, deletedAtUtc) || changed;
    }
    return changed;
  }

  void clearPaperDeleted(String paperId) {
    final id = paperId.trim();
    if (id.isEmpty) {
      return;
    }
    deletedPaperTombstones.remove(id);
  }

  bool isTodoItemDeleted(String paperId, String itemId) {
    return deletedTodoItemTombstones[paperId.trim()]?.containsKey(
          itemId.trim(),
        ) ??
        false;
  }

  DateTime? todoItemDeletedAtUtc(String paperId, String itemId) {
    return tryParseStrictSyncWireDateTimeUtc(
      deletedTodoItemTombstones[paperId.trim()]?[itemId.trim()] ?? '',
    );
  }

  bool markTodoItemDeleted(
    String paperId,
    String itemId,
    DateTime deletedAtUtc,
  ) {
    final normalizedPaperId = paperId.trim();
    final normalizedItemId = itemId.trim();
    if (normalizedPaperId.isEmpty || normalizedItemId.isEmpty) {
      return false;
    }
    final paperDeletedAt = paperDeletedAtUtc(normalizedPaperId);
    if (paperDeletedAt != null &&
        !deletedAtUtc.toUtc().isAfter(paperDeletedAt)) {
      return _removeCoveredTodoItemTombstones(
        normalizedPaperId,
        paperDeletedAt,
      );
    }
    return _putLatestTombstone(
      deletedTodoItemTombstones.putIfAbsent(
        normalizedPaperId,
        () => <String, String>{},
      ),
      normalizedItemId,
      _tombstoneTimestamp(deletedAtUtc),
    );
  }

  void clearTodoItemDeleted(String paperId, String itemId) {
    final normalizedPaperId = paperId.trim();
    final normalizedItemId = itemId.trim();
    final paperTombstones = deletedTodoItemTombstones[normalizedPaperId];
    if (paperTombstones == null || normalizedItemId.isEmpty) {
      return;
    }
    paperTombstones.remove(normalizedItemId);
    if (paperTombstones.isEmpty) {
      deletedTodoItemTombstones.remove(normalizedPaperId);
    }
  }

  SyncSettings copy() {
    return SyncSettings(
      enabled: enabled,
      provider: provider,
      webDav: webDav.copy(),
      operationDeviceSequences: Map<String, int>.from(operationDeviceSequences),
      deletedPaperTombstones: Map<String, String>.from(
        deletedPaperTombstones,
      ),
      deletedTodoItemTombstones: {
        for (final entry in deletedTodoItemTombstones.entries)
          entry.key: Map<String, String>.from(entry.value),
      },
      extra: Map<String, Object?>.from(extra),
    );
  }

  JsonMap toJson() {
    return {
      ...extra,
      'enabled': enabled,
      'provider': provider,
      'webDav': webDav.toJson(),
      'operationDeviceSequences': operationDeviceSequences,
      'deletedPaperTombstones': deletedPaperTombstones,
      'deletedTodoItemTombstones': deletedTodoItemTombstones,
    };
  }
}

class WebDavSyncSettings {
  WebDavSyncSettings({
    this.presetId = WebDavPresetIds.custom,
    this.endpoint = '',
    this.username = '',
    this.password = '',
    this.encryptionPassphrase = '',
    this.rootPath = 'repapertodo',
    this.autoSyncOnStart = false,
    this.autoSyncIntervalMinutes = 15,
    this.requestTimeoutSeconds = 30,
    JsonMap? extra,
  }) : extra = extra ?? <String, Object?>{};

  static const _knownKeys = {
    'presetId',
    'endpoint',
    'username',
    'password',
    'encryptionPassphrase',
    'rootPath',
    'autoSyncOnStart',
    'autoSyncIntervalMinutes',
    'requestTimeoutSeconds',
  };

  String presetId;
  String endpoint;
  String username;
  String password;
  String encryptionPassphrase;
  String rootPath;
  bool autoSyncOnStart;
  int autoSyncIntervalMinutes;
  int requestTimeoutSeconds;
  JsonMap extra;

  factory WebDavSyncSettings.jianguoyun({
    String username = '',
    String password = '',
    String encryptionPassphrase = '',
  }) {
    final preset = WebDavPresets.jianguoyun;
    return WebDavSyncSettings(
      presetId: preset.id,
      endpoint: preset.endpointText,
      username: username,
      password: password,
      encryptionPassphrase: encryptionPassphrase,
      rootPath: preset.defaultRootPath,
    );
  }

  factory WebDavSyncSettings.fromJson(JsonMap json) {
    return WebDavSyncSettings(
      presetId: stringValue(json['presetId'], WebDavPresetIds.custom),
      endpoint: stringValue(json['endpoint'], ''),
      username: stringValue(json['username'], ''),
      password: stringValue(json['password'], ''),
      encryptionPassphrase: stringValue(json['encryptionPassphrase'], ''),
      rootPath: stringValue(json['rootPath'], 'repapertodo'),
      autoSyncOnStart: boolValue(json['autoSyncOnStart'], false),
      autoSyncIntervalMinutes: intValue(json['autoSyncIntervalMinutes'], 15),
      requestTimeoutSeconds: intValue(json['requestTimeoutSeconds'], 30),
      extra: preserveUnknown(json, _knownKeys),
    )..normalize();
  }

  bool get isConfigured => configurationIssues.isEmpty;

  bool get isSecurelyConfigured => secureConfigurationIssues.isEmpty;

  Set<WebDavSyncConfigurationIssue> get configurationIssues {
    return {
      if (endpointUri == null) WebDavSyncConfigurationIssue.endpoint,
      if (!_isValidBasicAuthUsername(username))
        WebDavSyncConfigurationIssue.username,
      if (!_isValidBasicAuthPassword(password))
        WebDavSyncConfigurationIssue.password,
      if (rootPath.isEmpty) WebDavSyncConfigurationIssue.rootPath,
    };
  }

  Set<WebDavSyncConfigurationIssue> get secureConfigurationIssues {
    return {
      ...configurationIssues,
      if (!_isValidEncryptionPassphrase(encryptionPassphrase))
        WebDavSyncConfigurationIssue.encryptionPassphrase,
    };
  }

  Uri? get endpointUri {
    final trimmedEndpoint = endpoint.trim();
    if (_hasUnsafeEndpointPath(trimmedEndpoint)) {
      return null;
    }
    final uri = Uri.tryParse(trimmedEndpoint);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        (scheme != 'http' && scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        _hasUnsafeEndpointAuthority(uri) ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri;
  }

  bool get usesEncryptedPayloads {
    return _isValidEncryptionPassphrase(encryptionPassphrase);
  }

  void normalize() {
    presetId = WebDavPresetIds.normalize(presetId);
    endpoint = _normalizeEndpoint(endpoint);
    username = username.trim();
    encryptionPassphrase = encryptionPassphrase.trim();
    rootPath = _normalizeRootPath(rootPath);
    autoSyncIntervalMinutes = autoSyncIntervalMinutes.clamp(1, 1440).toInt();
    requestTimeoutSeconds = requestTimeoutSeconds.clamp(1, 300).toInt();
    final preset = WebDavPresets.byId(presetId);
    if (preset != null && endpoint.isEmpty) {
      endpoint = preset.endpointText;
    }
  }

  WebDavSyncSettings copy() {
    return WebDavSyncSettings(
      presetId: presetId,
      endpoint: endpoint,
      username: username,
      password: password,
      encryptionPassphrase: encryptionPassphrase,
      rootPath: rootPath,
      autoSyncOnStart: autoSyncOnStart,
      autoSyncIntervalMinutes: autoSyncIntervalMinutes,
      requestTimeoutSeconds: requestTimeoutSeconds,
      extra: Map<String, Object?>.from(extra),
    );
  }

  JsonMap toJson() {
    return {
      ...extra,
      'presetId': presetId,
      'endpoint': endpoint,
      'username': username,
      'password': password,
      'encryptionPassphrase': encryptionPassphrase,
      'rootPath': rootPath,
      'autoSyncOnStart': autoSyncOnStart,
      'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
      'requestTimeoutSeconds': requestTimeoutSeconds,
    };
  }
}

enum WebDavSyncConfigurationIssue {
  endpoint,
  username,
  password,
  rootPath,
  encryptionPassphrase,
}

String _normalizeEndpoint(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || _hasUnsafeEndpointPath(trimmed)) {
    return trimmed;
  }
  final uri = Uri.tryParse(trimmed);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null ||
      (scheme != 'http' && scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      _hasUnsafeEndpointAuthority(uri) ||
      uri.hasQuery ||
      uri.hasFragment) {
    return trimmed;
  }
  final pathSegments = [
    ...uri.pathSegments,
    if (!uri.path.endsWith('/')) '',
  ];
  final normalized = uri
      .replace(
        scheme: scheme,
        host: uri.host.toLowerCase(),
        pathSegments: pathSegments,
      )
      .toString();
  return normalized.endsWith('/') ? normalized : '$normalized/';
}

bool _hasUnsafeEndpointAuthority(Uri uri) {
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

String _normalizeRootPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return value.isEmpty ? '' : 'repapertodo';
  }
  late final String decoded;
  try {
    decoded = Uri.decodeComponent(trimmed);
  } on ArgumentError {
    return '';
  } on FormatException {
    return '';
  }
  final segments = <String>[];
  final rawSegments = decoded.replaceAll('\\', '/').split('/');
  for (var index = 0; index < rawSegments.length; index += 1) {
    final segment = rawSegments[index];
    if (segment.isEmpty &&
        _hasNonEmptyPathSegmentBefore(rawSegments, index) &&
        _hasNonEmptyPathSegmentAfter(rawSegments, index)) {
      return '';
    }
    if (_hasControlCharacter(segment)) {
      return '';
    }
    final trimmedSegment = segment.trim();
    if (segment.isNotEmpty && trimmedSegment.isEmpty) {
      return '';
    }
    if (trimmedSegment.isEmpty || trimmedSegment == '.') {
      continue;
    }
    if (trimmedSegment == '..') {
      return '';
    }
    segments.add(trimmedSegment);
  }
  final normalized = segments.join('/');
  return normalized.isEmpty ? 'repapertodo' : normalized;
}

bool _hasNonEmptyPathSegmentBefore(List<String> segments, int index) {
  return segments.take(index).any((segment) => segment.isNotEmpty);
}

bool _hasNonEmptyPathSegmentAfter(List<String> segments, int index) {
  return segments.skip(index + 1).any((segment) => segment.isNotEmpty);
}

bool _hasUnsafeEndpointPath(String endpoint) {
  if (endpoint.contains('\\')) {
    return true;
  }
  final schemeSeparator = endpoint.indexOf('://');
  if (schemeSeparator < 0) {
    return false;
  }
  final pathStart = endpoint.indexOf('/', schemeSeparator + 3);
  if (pathStart < 0) {
    return false;
  }
  var pathEnd = endpoint.length;
  for (final terminator in const ['?', '#']) {
    final index = endpoint.indexOf(terminator, pathStart);
    if (index >= 0 && index < pathEnd) {
      pathEnd = index;
    }
  }
  final path = endpoint.substring(pathStart, pathEnd);
  final rawSegments = path.split('/');
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

bool _isValidBasicAuthUsername(String value) {
  return value.trim().isNotEmpty &&
      !value.contains(':') &&
      !_hasControlCharacter(value);
}

bool _isValidBasicAuthPassword(String value) {
  return value.trim().isNotEmpty && !_hasControlCharacter(value);
}

bool _isValidEncryptionPassphrase(String value) {
  return value.trim().isNotEmpty && !_hasControlCharacter(value);
}

bool _hasControlCharacter(String value) {
  return value.codeUnits.any((unit) => unit <= 0x1F || unit == 0x7F);
}

Map<String, String> _normalizeTombstoneMap(Object? value) {
  if (value is! Map) {
    return <String, String>{};
  }
  final normalized = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      continue;
    }
    final id = (entry.key as String).trim();
    final timestamp = _normalizeTombstoneTimestamp(entry.value as String);
    if (id.isEmpty || timestamp.isEmpty) {
      continue;
    }
    _putLatestTombstone(normalized, id, timestamp);
  }
  return normalized;
}

Map<String, Map<String, String>> _normalizeNestedTombstoneMap(Object? value) {
  if (value is! Map) {
    return <String, Map<String, String>>{};
  }
  final normalized = <String, Map<String, String>>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      continue;
    }
    final paperId = (entry.key as String).trim();
    final itemTombstones = _normalizeTombstoneMap(entry.value);
    if (paperId.isEmpty || itemTombstones.isEmpty) {
      continue;
    }
    final existing = normalized.putIfAbsent(paperId, () => <String, String>{});
    for (final itemEntry in itemTombstones.entries) {
      _putLatestTombstone(existing, itemEntry.key, itemEntry.value);
    }
  }
  return normalized;
}

Map<String, int> _syncDeviceSequencesFromWire(Object? value) {
  if (value is! Map) {
    return const <String, int>{};
  }
  final normalized = <String, int>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      continue;
    }
    final sequence = _syncDeviceSequenceFromWire(entry.value);
    if (sequence == null) {
      continue;
    }
    final deviceId = normalizeSyncDeviceId(key, fallback: '');
    if (deviceId.isEmpty) {
      continue;
    }
    final previous = normalized[deviceId] ?? 0;
    if (sequence > previous) {
      normalized[deviceId] = sequence;
    }
  }
  return normalized;
}

int? _syncDeviceSequenceFromWire(Object? value) {
  if (value is int) {
    return isSyncDeviceSequenceInRange(value) ? value : null;
  }
  if (value is num && value.isFinite && value % 1 == 0) {
    final sequence = value.toInt();
    return isSyncDeviceSequenceInRange(sequence) ? sequence : null;
  }
  if (value is String && value.trim() == value) {
    final sequence = int.tryParse(value);
    if (sequence != null && isSyncDeviceSequenceInRange(sequence)) {
      return sequence;
    }
  }
  return null;
}

bool _putLatestTombstone(
  Map<String, String> target,
  String id,
  String timestamp,
) {
  final previous = target[id];
  final previousTime =
      previous == null ? null : tryParseStrictSyncWireDateTimeUtc(previous);
  final timestampTime = tryParseStrictSyncWireDateTimeUtc(timestamp);
  if (timestampTime == null) {
    return false;
  }
  if (previous == null ||
      previousTime == null ||
      timestampTime.isAfter(previousTime)) {
    target[id] = timestamp;
    return true;
  }
  return false;
}

String _tombstoneTimestamp(DateTime value) {
  return value.toUtc().toIso8601String();
}

String _normalizeTombstoneTimestamp(String value) {
  final parsed = tryParseStrictSyncWireDateTimeUtc(value);
  if (parsed == null) {
    return '';
  }
  return _tombstoneTimestamp(parsed);
}
