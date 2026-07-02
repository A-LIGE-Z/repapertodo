import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('keeps Jianguoyun as the recommended domestic WebDAV preset', () {
    final preset = WebDavPresets.jianguoyun;

    expect(WebDavPresets.recommended, contains(preset));
    expect(WebDavPresets.byId(' jianguoyun '), same(preset));
    expect(WebDavPresets.byId('Jian-Guo-Yun'), same(preset));
    expect(WebDavPresets.byId('nutstore'), same(preset));
    expect(WebDavPresets.byId('nutstore-webdav'), same(preset));
    expect(WebDavPresetIds.normalize('jianguoyun'), WebDavPresetIds.jianguoyun);
    expect(WebDavPresetIds.normalize('NUTSTORE'), WebDavPresetIds.jianguoyun);
    expect(preset.label, 'Jianguoyun');
    expect(preset.name, 'Jianguoyun WebDAV');
    expect(preset.endpointText, 'https://dav.jianguoyun.com/dav/');
    expect(preset.defaultRootPath, 'RePaperTodo');
  });

  test('keeps custom WebDAV as the fallback preset id', () {
    expect(WebDavPresets.byId(WebDavPresetIds.custom), isNull);
    expect(
        WebDavPresetIds.normalize('future-provider'), WebDavPresetIds.custom);
    expect(WebDavPresetIds.normalize(null), WebDavPresetIds.custom);
  });

  test('uses preset defaults for Jianguoyun sync settings', () {
    final settings = WebDavSyncSettings.jianguoyun(
      username: 'user@example.com',
      password: 'app-password',
      encryptionPassphrase: 'shared sync secret',
    )..normalize();

    expect(settings.presetId, WebDavPresetIds.jianguoyun);
    expect(settings.endpoint, WebDavPresets.jianguoyun.endpointText);
    expect(settings.rootPath, WebDavPresets.jianguoyun.defaultRootPath);
    expect(settings.isConfigured, true);
    expect(settings.isSecurelyConfigured, true);
  });

  test('distinguishes WebDAV connection settings from secure sync settings',
      () {
    final settings = WebDavSyncSettings.jianguoyun(
      username: 'user@example.com',
      password: 'app-password',
    )..normalize();

    expect(settings.isConfigured, true);
    expect(settings.usesEncryptedPayloads, false);
    expect(settings.isSecurelyConfigured, false);
  });
}
