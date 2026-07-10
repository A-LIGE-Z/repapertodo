import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('keeps Jianguoyun as the recommended domestic WebDAV preset', () {
    final preset = WebDavPresets.jianguoyun;

    expect(WebDavPresets.recommended, contains(preset));
    expect(WebDavPresets.all, containsAll([preset, WebDavPresets.custom]));
    expect(WebDavPresets.byId(' jianguoyun '), same(preset));
    expect(WebDavPresets.byId('坚果云'), same(preset));
    expect(WebDavPresets.byId('坚果云 WebDAV'), same(preset));
    expect(WebDavPresets.byId('坚 果 云'), same(preset));
    expect(WebDavPresets.byId('坚_果_云'), same(preset));
    expect(WebDavPresets.byId('坚-果-云 WebDAV'), same(preset));
    expect(WebDavPresets.byId('jian guo yun'), same(preset));
    expect(WebDavPresets.byId('jian_guo_yun'), same(preset));
    expect(WebDavPresets.byId('Jian-Guo-Yun'), same(preset));
    expect(WebDavPresets.byId('nutstore'), same(preset));
    expect(WebDavPresets.byId('nut-store'), same(preset));
    expect(WebDavPresets.byId('nutstore-webdav'), same(preset));
    expect(WebDavPresets.byId('nut store webdav'), same(preset));
    expect(WebDavPresetIds.normalize('jianguoyun'), WebDavPresetIds.jianguoyun);
    expect(WebDavPresetIds.normalize('坚果云'), WebDavPresetIds.jianguoyun);
    expect(WebDavPresetIds.normalize('坚果云 WebDAV'), WebDavPresetIds.jianguoyun);
    expect(WebDavPresetIds.normalize('NUTSTORE'), WebDavPresetIds.jianguoyun);
    expect(preset.label, '坚果云');
    expect(preset.name, 'Jianguoyun WebDAV');
    expect(preset.endpointText, 'https://dav.jianguoyun.com/dav/');
    expect(preset.defaultRootPath, 'RePaperTodo');
  });

  test('keeps generic WebDAV as an explicit fallback preset', () {
    final preset = WebDavPresets.custom;

    expect(WebDavPresets.recommended, isNot(contains(preset)));
    expect(WebDavPresets.byId(WebDavPresetIds.custom), same(preset));
    expect(WebDavPresets.byId(' generic '), same(preset));
    expect(WebDavPresets.byId('generic-webdav'), same(preset));
    expect(WebDavPresets.byId('custom-webdav'), same(preset));
    expect(WebDavPresets.byId('future-provider'), same(preset));
    expect(WebDavPresets.configuredById(WebDavPresetIds.custom), isNull);
    expect(WebDavPresets.configuredById('future-provider'), isNull);
    expect(WebDavPresetIds.normalize('GENERIC'), WebDavPresetIds.custom);
    expect(
        WebDavPresetIds.normalize('future-provider'), WebDavPresetIds.custom);
    expect(WebDavPresetIds.normalize(null), WebDavPresetIds.custom);
    expect(preset.isCustom, true);
    expect(preset.label, 'Generic');
    expect(preset.name, 'Generic WebDAV');
    expect(preset.endpointText, isEmpty);
    expect(preset.defaultRootPath, isEmpty);
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

  test('normalizes preset default root paths before applying them', () {
    expect(
      const WebDavPreset(
        id: 'nested',
        name: 'Nested WebDAV',
        label: 'Nested',
        defaultRemotePath: r' /Team/RePaperTodo/ ',
      ).defaultRootPath,
      'Team/RePaperTodo',
    );
    expect(
      const WebDavPreset(
        id: 'parent',
        name: 'Parent WebDAV',
        label: 'Parent',
        defaultRemotePath: '../RePaperTodo',
      ).defaultRootPath,
      isEmpty,
    );
    expect(
      const WebDavPreset(
        id: 'blank-segment',
        name: 'Blank Segment WebDAV',
        label: 'Blank',
        defaultRemotePath: 'Team//RePaperTodo',
      ).defaultRootPath,
      isEmpty,
    );
    expect(
      const WebDavPreset(
        id: 'control',
        name: 'Control WebDAV',
        label: 'Control',
        defaultRemotePath: 'Team/RePaperTodo\u0001',
      ).defaultRootPath,
      isEmpty,
    );
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
