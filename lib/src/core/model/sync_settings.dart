import 'json_helpers.dart';

abstract final class SyncProviderIds {
  static const none = 'none';
  static const webDav = 'webDav';

  static String normalize(String? value) {
    return value == webDav ? webDav : none;
  }
}

abstract final class WebDavPresetIds {
  static const custom = 'custom';
  static const jianguoyun = 'jianguoyun';

  static String normalize(String? value) {
    return value == jianguoyun ? jianguoyun : custom;
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
        operationDeviceSequences = operationDeviceSequences ?? <String, int>{},
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
      operationDeviceSequences: intMap(json['operationDeviceSequences']),
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
    operationDeviceSequences = _normalizeDeviceSequences(
      operationDeviceSequences,
    );
    deletedPaperTombstones = _normalizeTombstoneMap(deletedPaperTombstones);
    deletedTodoItemTombstones =
        _normalizeNestedTombstoneMap(deletedTodoItemTombstones);
    if (enabled && provider == SyncProviderIds.none) {
      provider = SyncProviderIds.webDav;
    }
  }

  bool isPaperDeleted(String paperId) {
    return deletedPaperTombstones.containsKey(paperId.trim());
  }

  DateTime? paperDeletedAtUtc(String paperId) {
    return DateTime.tryParse(deletedPaperTombstones[paperId.trim()] ?? '')
        ?.toUtc();
  }

  void markPaperDeleted(String paperId, DateTime deletedAtUtc) {
    final id = paperId.trim();
    if (id.isEmpty) {
      return;
    }
    deletedPaperTombstones[id] = _tombstoneTimestamp(deletedAtUtc);
    deletedTodoItemTombstones.remove(id);
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
    return DateTime.tryParse(
      deletedTodoItemTombstones[paperId.trim()]?[itemId.trim()] ?? '',
    )?.toUtc();
  }

  void markTodoItemDeleted(
    String paperId,
    String itemId,
    DateTime deletedAtUtc,
  ) {
    final normalizedPaperId = paperId.trim();
    final normalizedItemId = itemId.trim();
    if (normalizedPaperId.isEmpty || normalizedItemId.isEmpty) {
      return;
    }
    deletedTodoItemTombstones.putIfAbsent(
            normalizedPaperId, () => <String, String>{})[normalizedItemId] =
        _tombstoneTimestamp(deletedAtUtc);
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
    this.rootPath = 'repapertodo',
    this.autoSyncOnStart = false,
    this.autoSyncIntervalMinutes = 15,
    JsonMap? extra,
  }) : extra = extra ?? <String, Object?>{};

  static const _knownKeys = {
    'presetId',
    'endpoint',
    'username',
    'password',
    'rootPath',
    'autoSyncOnStart',
    'autoSyncIntervalMinutes',
  };

  String presetId;
  String endpoint;
  String username;
  String password;
  String rootPath;
  bool autoSyncOnStart;
  int autoSyncIntervalMinutes;
  JsonMap extra;

  factory WebDavSyncSettings.jianguoyun({
    String username = '',
    String password = '',
  }) {
    return WebDavSyncSettings(
      presetId: WebDavPresetIds.jianguoyun,
      endpoint: 'https://dav.jianguoyun.com/dav/',
      username: username,
      password: password,
      rootPath: 'RePaperTodo',
    );
  }

  factory WebDavSyncSettings.fromJson(JsonMap json) {
    return WebDavSyncSettings(
      presetId: stringValue(json['presetId'], WebDavPresetIds.custom),
      endpoint: stringValue(json['endpoint'], ''),
      username: stringValue(json['username'], ''),
      password: stringValue(json['password'], ''),
      rootPath: stringValue(json['rootPath'], 'repapertodo'),
      autoSyncOnStart: boolValue(json['autoSyncOnStart'], false),
      autoSyncIntervalMinutes: intValue(json['autoSyncIntervalMinutes'], 15),
      extra: preserveUnknown(json, _knownKeys),
    )..normalize();
  }

  bool get isConfigured {
    return endpointUri != null &&
        username.isNotEmpty &&
        password.isNotEmpty &&
        rootPath.isNotEmpty;
  }

  Uri? get endpointUri {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  void normalize() {
    presetId = WebDavPresetIds.normalize(presetId);
    endpoint = endpoint.trim();
    username = username.trim();
    rootPath = _normalizeRootPath(rootPath);
    autoSyncIntervalMinutes = autoSyncIntervalMinutes.clamp(1, 1440).toInt();
    if (presetId == WebDavPresetIds.jianguoyun && endpoint.isEmpty) {
      endpoint = 'https://dav.jianguoyun.com/dav/';
    }
  }

  WebDavSyncSettings copy() {
    return WebDavSyncSettings(
      presetId: presetId,
      endpoint: endpoint,
      username: username,
      password: password,
      rootPath: rootPath,
      autoSyncOnStart: autoSyncOnStart,
      autoSyncIntervalMinutes: autoSyncIntervalMinutes,
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
      'rootPath': rootPath,
      'autoSyncOnStart': autoSyncOnStart,
      'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
    };
  }
}

String _normalizeRootPath(String value) {
  final normalized = value
      .trim()
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .join('/');
  return normalized.isEmpty ? 'repapertodo' : normalized;
}

Map<String, int> _normalizeDeviceSequences(Map<String, int> source) {
  final normalized = <String, int>{};
  for (final entry in source.entries) {
    final key = entry.key.trim();
    if (key.isEmpty || entry.value <= 0) {
      continue;
    }
    normalized[key] = entry.value;
  }
  return normalized;
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
    normalized[id] = timestamp;
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
    normalized[paperId] = itemTombstones;
  }
  return normalized;
}

String _tombstoneTimestamp(DateTime value) {
  return value.toUtc().toIso8601String();
}

String _normalizeTombstoneTimestamp(String value) {
  final parsed = DateTime.tryParse(value.trim());
  if (parsed == null) {
    return '';
  }
  return _tombstoneTimestamp(parsed);
}
