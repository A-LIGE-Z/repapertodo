class WebDavPreset {
  const WebDavPreset({
    required this.id,
    required this.name,
    required this.label,
    this.endpoint,
    this.defaultRemotePath = '',
  });

  final String id;
  final String name;
  final String label;
  final Uri? endpoint;
  final String defaultRemotePath;

  bool get isCustom => id == WebDavPresetIds.custom;

  String get endpointText => endpoint?.toString() ?? '';

  String get defaultRootPath => _normalizePresetRootPath(defaultRemotePath);
}

abstract final class WebDavPresetIds {
  static const custom = 'custom';
  static const jianguoyun = 'jianguoyun';

  static String normalize(String? value) {
    return WebDavPresets.byId(value).id;
  }
}

abstract final class WebDavPresets {
  static const custom = WebDavPreset(
    id: WebDavPresetIds.custom,
    name: 'Generic WebDAV',
    label: 'Generic',
  );

  static final jianguoyun = WebDavPreset(
    id: WebDavPresetIds.jianguoyun,
    name: 'Jianguoyun WebDAV',
    label: 'Jianguoyun',
    endpoint: Uri.parse('https://dav.jianguoyun.com/dav/'),
    defaultRemotePath: '/RePaperTodo/',
  );

  static final recommended = List<WebDavPreset>.unmodifiable([
    jianguoyun,
  ]);

  static final all = List<WebDavPreset>.unmodifiable([
    ...recommended,
    custom,
  ]);

  static const customId = WebDavPresetIds.custom;

  static WebDavPreset byId(String? id) {
    final normalizedId = _normalizePresetId(id);
    if (normalizedId == null || normalizedId.isEmpty) {
      return custom;
    }
    for (final preset in all) {
      if (preset.id == normalizedId) {
        return preset;
      }
    }
    return custom;
  }

  static WebDavPreset? configuredById(String? id) {
    final preset = byId(id);
    return preset.isCustom ? null : preset;
  }
}

String? _normalizePresetId(String? id) {
  final value = id?.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-');
  return switch (value) {
    null || '' => null,
    '坚果云' ||
    '坚果云-webdav' ||
    'jianguoyun' ||
    'jianguo-yun' ||
    'jian-guoyun' ||
    'jian-guo-yun' ||
    'jianguoyun-webdav' ||
    'jianguo-yun-webdav' ||
    'jian-guoyun-webdav' ||
    'jian-guo-yun-webdav' ||
    'nutstore' ||
    'nut-store' ||
    'nutstore-webdav' ||
    'nut-store-webdav' =>
      WebDavPresetIds.jianguoyun,
    'custom' ||
    'generic' ||
    'custom-webdav' ||
    'generic-webdav' =>
      WebDavPresetIds.custom,
    _ => value,
  };
}

String _normalizePresetRootPath(String value) {
  return value
      .trim()
      .replaceAll('\\', '/')
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty && segment != '.')
      .join('/');
}
