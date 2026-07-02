import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project rules preserve the requested direction', () {
    final rules = File('AGENTS.md').readAsStringSync();

    expect(rules, contains('Flutter-first reimplementation'));
    expect(rules, contains('Windows exe first'));
    expect(rules, contains('Generic WebDAV must remain supported'));
    expect(rules, contains('no fixed budget ceiling'));
  });

  test('Android build targets Android 14 through 17', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final filePaths =
        File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync();
    final mainActivity = File(
            'android/app/src/main/kotlin/com/aligez/repapertodo/MainActivity.kt')
        .readAsStringSync();

    expect(gradle, contains('compileSdk = 37'));
    expect(gradle, contains('minSdk = 34'));
    expect(gradle, contains('targetSdk = 37'));
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android:usesCleartextTraffic="true"'));
    expect(manifest, contains('androidx.core.content.FileProvider'));
    expect(manifest, contains('android:grantUriPermissions="true"'));
    expect(filePaths, contains('<files-path'));
    expect(filePaths, contains('<cache-path'));
    expect(filePaths, contains('<external-files-path'));
    expect(mainActivity, contains('FileProvider.getUriForFile'));
    expect(mainActivity, contains('ClipData.newUri'));
    expect(mainActivity, contains('val trimmedUri = uri.trim()'));
    expect(mainActivity, contains('val trimmedPath = path.trim()'));
    expect(mainActivity, contains('!file.isFile'));
    expect(mainActivity, contains('parsedUri.scheme'));
    expect(mainActivity, contains('hasUnsafeExternalUriCharacter'));
    expect(mainActivity, contains('isAllowedExternalUri'));
    expect(mainActivity, contains('"mailto"'));
    expect(mainActivity, contains('Intent.CATEGORY_BROWSABLE'));
    expect(mainActivity, contains('file_provider_failed'));
    expect(mainActivity, contains('SecurityException'));
  });

  test('sync design preserves merge safety rules', () {
    final syncDesign = File('docs/SYNC.md').readAsStringSync();

    expect(syncDesign, contains('earliest `createdAtUtc` first'));
    expect(syncDesign, contains('Tombstone timestamps only move forward'));
    expect(
        syncDesign, contains('Settings operations are intentionally limited'));
    expect(syncDesign,
        contains('Local device sequence progress must never move backward'));
    expect(syncDesign, contains('sparse or stale manifest cannot drop'));
    expect(
        syncDesign,
        contains(
            'Require a sync encryption passphrase before user-facing WebDAV sync runs'));
    expect(syncDesign, contains('defaults to 30 seconds'));
    expect(syncDesign, contains('normalized to 1 through'));
    expect(syncDesign,
        contains('Endpoint paths with dot-segments, raw or percent-encoded'));
    expect(syncDesign, contains('percent-encoded control characters'));
    expect(syncDesign, contains('empty root folder values remain incomplete'));
    expect(syncDesign, contains('unsafe base URI paths including control'));
    expect(syncDesign, contains('characters, and resolves all accepted paths'));
  });

  test('Windows runner preserves startup command parsing parity', () {
    final runner = File('windows/runner/main.cpp').readAsStringSync();
    final dartParser =
        File('lib/src/core/startup/startup_command.dart').readAsStringSync();

    expect(runner, contains('find_first_of("=:", segment_start)'));
    expect(runner, contains('CreatedPaperStartupCommand'));
    expect(dartParser, contains("RegExp(r'[=:]+')"));
    expect(dartParser, contains('_createdPaperKind'));
  });

  test('Windows runner preserves external URI safety checks', () {
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(app, contains('_hasUnsafeExternalUriCharacter'));
    expect(runner, contains('IsAllowedExternalUri'));
    expect(runner, contains('ascii <= 0x20'));
    expect(runner, contains('scheme == "mailto"'));
    expect(runner, contains('scheme != "http" && scheme != "https"'));
    expect(runner, contains('ShellExecuteW'));
  });

  test('Windows runner validates external files before opening them', () {
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(runner, contains('path = TrimAscii(path)'));
    expect(runner, contains('FileExists'));
    expect(runner, contains('FILE_ATTRIBUTE_DIRECTORY'));
    expect(runner, contains('file_not_found'));
    expect(runner, contains('ShellExecuteW'));
  });
}
