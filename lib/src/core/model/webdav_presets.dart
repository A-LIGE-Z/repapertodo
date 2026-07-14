class WebDavPreset {
  const WebDavPreset({
    required this.id,
    required this.name,
    required this.label,
    this.endpoint,
    this.defaultRemotePath = '',
    this.maxRootPathFirstSegmentLength,
  });

  final String id;
  final String name;
  final String label;
  final Uri? endpoint;
  final String defaultRemotePath;
  final int? maxRootPathFirstSegmentLength;

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
    label: '坚果云',
    endpoint: Uri.parse('https://dav.jianguoyun.com/dav/'),
    defaultRemotePath: '/RePaperTodo/',
    maxRootPathFirstSegmentLength: 30,
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
  final rawValue = id?.trim().toLowerCase();
  if (rawValue == null || rawValue.isEmpty) {
    return null;
  }
  final value = rawValue.replaceAll(RegExp(r'[\s_]+'), '-');
  final compactValue = rawValue.replaceAll(RegExp(r'[\s_-]+'), '');
  if (switch (compactValue) {
    '坚果云' ||
    '坚果云webdav' ||
    'jianguoyun' ||
    'jianguoyunwebdav' ||
    'nutstore' ||
    'nutstorewebdav' =>
      true,
    _ => false,
  }) {
    return WebDavPresetIds.jianguoyun;
  }
  return switch (value) {
    'jianguo-yun' ||
    'jian-guoyun' ||
    'jian-guo-yun' ||
    'jianguo-yun-webdav' ||
    'jian-guoyun-webdav' ||
    'jian-guo-yun-webdav' ||
    'nut-store' ||
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
  final normalizedSegments = <String>[];
  final rawSegments = value.trim().replaceAll('\\', '/').split('/');
  for (var index = 0; index < rawSegments.length; index += 1) {
    final segment = rawSegments[index];
    if (segment.isEmpty &&
        _hasNonEmptySegmentBefore(rawSegments, index) &&
        _hasNonEmptySegmentAfter(rawSegments, index)) {
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
    normalizedSegments.add(trimmedSegment);
  }
  return normalizedSegments.join('/');
}

bool _hasNonEmptySegmentBefore(List<String> segments, int index) {
  return segments.take(index).any((segment) => segment.isNotEmpty);
}

bool _hasNonEmptySegmentAfter(List<String> segments, int index) {
  return segments.skip(index + 1).any((segment) => segment.isNotEmpty);
}

bool _hasControlCharacter(String value) {
  return value.runes.any(
    (rune) => rune <= 0x1F || (rune >= 0x7F && rune <= 0x9F),
  );
}
