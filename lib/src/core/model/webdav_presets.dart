class WebDavPreset {
  const WebDavPreset({
    required this.id,
    required this.name,
    required this.label,
    required this.endpoint,
    required this.defaultRemotePath,
  });

  final String id;
  final String name;
  final String label;
  final Uri endpoint;
  final String defaultRemotePath;

  String get endpointText => endpoint.toString();

  String get defaultRootPath => _normalizePresetRootPath(defaultRemotePath);
}

abstract final class WebDavPresetIds {
  static const custom = 'custom';
  static const jianguoyun = 'jianguoyun';

  static String normalize(String? value) {
    return WebDavPresets.byId(value)?.id ?? custom;
  }
}

abstract final class WebDavPresets {
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
  ]);

  static const customId = WebDavPresetIds.custom;

  static WebDavPreset? byId(String? id) {
    final normalizedId = _normalizePresetId(id);
    if (normalizedId == null || normalizedId.isEmpty) {
      return null;
    }
    for (final preset in all) {
      if (preset.id == normalizedId) {
        return preset;
      }
    }
    return null;
  }
}

String? _normalizePresetId(String? id) {
  final value = id?.trim().toLowerCase();
  return switch (value) {
    null || '' => null,
    'jianguoyun' ||
    'jian-guo-yun' ||
    'jianguoyun-webdav' ||
    'nutstore' ||
    'nutstore-webdav' =>
      WebDavPresetIds.jianguoyun,
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
