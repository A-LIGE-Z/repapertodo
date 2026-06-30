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
    JsonMap? extra,
  })  : webDav = webDav ?? WebDavSyncSettings(),
        extra = extra ?? <String, Object?>{};

  static const _knownKeys = {
    'enabled',
    'provider',
    'webDav',
  };

  bool enabled;
  String provider;
  WebDavSyncSettings webDav;
  JsonMap extra;

  factory SyncSettings.fromJson(JsonMap json) {
    final webDavJson = json['webDav'];
    return SyncSettings(
      enabled: boolValue(json['enabled'], false),
      provider: stringValue(json['provider'], SyncProviderIds.none),
      webDav: webDavJson is Map
          ? WebDavSyncSettings.fromJson(Map<String, Object?>.from(webDavJson))
          : null,
      extra: preserveUnknown(json, _knownKeys),
    )..normalize();
  }

  void normalize() {
    provider = SyncProviderIds.normalize(provider);
    webDav.normalize();
    if (enabled && provider == SyncProviderIds.none) {
      provider = SyncProviderIds.webDav;
    }
  }

  JsonMap toJson() {
    return {
      ...extra,
      'enabled': enabled,
      'provider': provider,
      'webDav': webDav.toJson(),
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
