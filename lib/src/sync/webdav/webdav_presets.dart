class WebDavPreset {
  const WebDavPreset({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.defaultRemotePath,
  });

  final String id;
  final String name;
  final Uri endpoint;
  final String defaultRemotePath;
}

abstract final class WebDavPresets {
  static final jianguoyun = WebDavPreset(
    id: 'jianguoyun',
    name: 'Jianguoyun WebDAV',
    endpoint: Uri.parse('https://dav.jianguoyun.com/dav/'),
    defaultRemotePath: '/RePaperTodo/',
  );

  static const customId = 'custom';
}

