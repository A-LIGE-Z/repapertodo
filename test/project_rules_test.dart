import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readProjectText(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

String _extractConstMapBody(String source, String mapName) {
  final marker = 'const $mapName = {';
  final start = source.indexOf(marker);
  if (start < 0) {
    throw StateError('$mapName was not found.');
  }
  final bodyStart = start + marker.length;
  final end = source.indexOf('\n};', bodyStart);
  if (end < 0) {
    throw StateError('$mapName terminator was not found.');
  }
  return source.substring(bodyStart, end);
}

String _sliceBetween(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  if (start < 0) {
    throw StateError('$startMarker was not found.');
  }
  final end = source.indexOf(endMarker, start + startMarker.length);
  if (end < 0) {
    throw StateError('$endMarker was not found after $startMarker.');
  }
  return source.substring(start, end);
}

Set<String> _declaredStringKeys(String source) {
  final keysClassStart =
      source.indexOf('abstract final class PaperTodoStringKeys');
  final keysClassEnd = source.indexOf('\n}', keysClassStart);
  if (keysClassStart < 0 || keysClassEnd < 0) {
    throw StateError('PaperTodoStringKeys class was not found.');
  }
  final keysClass = source.substring(keysClassStart, keysClassEnd);
  return RegExp(
    r"static const ([A-Za-z0-9_]+)\s*=\s*'[^']+';",
  ).allMatches(keysClass).map((match) => match.group(1)!).toSet();
}

Set<String> _localizedStringKeys(String source, String mapName) {
  final body = _extractConstMapBody(source, mapName);
  return RegExp(
    r'PaperTodoStringKeys\.([A-Za-z0-9_]+)\s*:',
  ).allMatches(body).map((match) => match.group(1)!).toSet();
}

String? _findPowerShellExecutable() {
  final candidates = Platform.isWindows
      ? const ['pwsh.exe', 'powershell.exe']
      : const ['pwsh'];
  final lookupCommand = Platform.isWindows ? 'where' : 'which';
  for (final candidate in candidates) {
    final result = Process.runSync(
      lookupCommand,
      [candidate],
      runInShell: true,
    );
    if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
      return candidate;
    }
  }
  return null;
}

void main() {
  test('project rules preserve the requested direction', () {
    final rules = _readProjectText('AGENTS.md');

    expect(rules, contains('Flutter-first reimplementation'));
    expect(rules, contains('Windows exe first'));
    expect(rules, contains('Generic WebDAV must remain supported'));
    expect(rules, contains('no fixed budget ceiling'));
  });

  test('roadmap keeps completion audit boundaries explicit', () {
    final roadmap = _readProjectText('docs/ROADMAP.md');

    expect(
      roadmap,
      contains('does not by itself prove full Windows feature parity'),
    );
    expect(roadmap, contains('Status: In progress.'));
    expect(roadmap, contains('one top-level HWND and one Flutter engine'));
    expect(roadmap, contains('one visible HWND per visible\n  paper'));
    expect(roadmap, contains('Remaining native-window parity work'));
    expect(roadmap, contains('generic WebDAV protocol coverage'));
    expect(roadmap, contains('credentialed Jianguoyun'));
    expect(roadmap, contains('unquoted opaque ETag conditional-write'));
    expect(roadmap, contains('Android 15/API 35 AOSP ATD emulator'));
    expect(roadmap, contains('real WorkManager background Dart'));
    expect(roadmap, contains('signed release APK'));
    expect(roadmap, contains('worker returned `SUCCESS`'));
    expect(roadmap, contains('signed Android release configuration'));
    expect(roadmap, contains('manual Windows parity QA'));
    expect(
      roadmap,
      isNot(contains('Status: Done for full PaperTodo replacement')),
    );
  });

  test('PowerShell ResultJson outputs are validated before writing', () {
    final resultJsonScripts = Directory('scripts')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.ps1'))
        .where((file) =>
            _readProjectText(file.path).contains(r'[string]$ResultJson'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final resultJsonScriptPaths = resultJsonScripts
        .map((file) => file.path.replaceAll(r'\', '/'))
        .toList();

    expect(
      resultJsonScriptPaths,
      containsAll(<String>[
        'scripts/android_device_smoke.ps1',
        'scripts/android_smoke.ps1',
        'scripts/release_readiness_audit.ps1',
        'scripts/webdav_live_smoke.ps1',
        'scripts/webdav_smoke.ps1',
        'scripts/windows_manual_qa.ps1',
        'scripts/windows_policy_smoke.ps1',
        'scripts/windows_smoke.ps1',
      ]),
    );

    for (final script in resultJsonScripts) {
      final source = _readProjectText(script.path);
      expect(
        source,
        contains('function Resolve-ResultJsonPath'),
        reason: '${script.path} must validate ResultJson before writing.',
      );
      expect(
        source,
        contains('result JSON path must not contain control characters.'),
        reason: '${script.path} must reject unsafe ResultJson characters.',
      );
      expect(
        source,
        contains('result JSON path must not contain wildcard characters.'),
        reason: '${script.path} must reject wildcard ResultJson paths.',
      );
      expect(
        source,
        contains('result JSON path must include a file name.'),
        reason: '${script.path} must reject directory-only ResultJson paths.',
      );
      expect(
        source,
        contains('result JSON path must use the .json extension.'),
        reason: '${script.path} must keep reusable evidence as JSON.',
      );
    }
  });

  test('runtime localization is scoped to Chinese and English', () {
    final rules = _readProjectText('AGENTS.md');
    final readme = _readProjectText('README.md');
    final changelog = _readProjectText('CHANGELOG.md');
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final development = _readProjectText('docs/DEVELOPMENT.md');
    final app = _readProjectText('lib/src/app.dart');
    final gradle = _readProjectText('android/app/build.gradle.kts');
    final manifest =
        _readProjectText('android/app/src/main/AndroidManifest.xml');
    final localeConfig =
        _readProjectText('android/app/src/main/res/xml/locales_config.xml');
    final androidSmokeScript = _readProjectText('scripts/android_smoke.ps1');
    final syncSettingsDialog =
        _readProjectText('lib/src/ui/sync_settings_dialog.dart');
    final strings = _readProjectText('lib/src/ui/papertodo_strings.dart');
    final stringsTest = _readProjectText('test/papertodo_strings_test.dart');

    expect(rules, contains('Chinese and English'));
    expect(rules, contains('unsupported\nsystem languages should fall back'));
    expect(readme, contains('Chinese and English'));
    expect(changelog, contains('## Unreleased'));
    expect(
      changelog,
      contains('optional Windows manual QA and live WebDAV QA result inputs'),
    );
    expect(design, contains('Chinese and English'));
    expect(design, contains('unsupported system\n  languages fall back'));
    expect(strings, contains('static const supportedLocales = ['));
    expect(strings, contains("Locale('zh')"));
    expect(strings, contains("Locale('en')"));
    expect(strings, contains("'zh' => 'zh'"));
    expect(strings, contains("'en' => 'en'"));
    expect(strings, isNot(contains("Locale('ja')")));
    expect(strings, isNot(contains("Locale('ko')")));
    expect(strings, isNot(contains("Locale('fr')")));
    final releaseScript = _readProjectText('scripts/release.ps1');
    expect(releaseScript, contains('function Get-RuntimeSupportedLanguages'));
    expect(
      releaseScript,
      contains('PaperTodoStrings.supportedLocales'),
    );
    expect(
      releaseScript,
      contains('function Assert-RuntimeSupportedLanguages'),
    );
    expect(
      releaseScript,
      contains(r'$validatedRuntimeLanguages'),
    );
    expect(
      readme,
      contains('reads\n`PaperTodoStrings.supportedLocales`'),
    );
    expect(
      development,
      contains('reads `PaperTodoStrings.supportedLocales`'),
    );
    expect(
        app, contains('supportedLocales: PaperTodoStrings.supportedLocales'));
    expect(app, contains('PaperTodoStrings.resolveLocale'));
    expect(app, isNot(contains("Locale('ja')")));
    expect(app, isNot(contains("Locale('ko')")));
    expect(app, isNot(contains("Locale('fr')")));
    expect(stringsTest, contains("const Locale('zz', 'TEST')"));
    expect(stringsTest, contains("const Locale('zz')"));
    expect(stringsTest, isNot(contains("Locale('ja')")));
    expect(stringsTest, isNot(contains("Locale('ko')")));
    expect(stringsTest, isNot(contains("Locale('fr')")));
    expect(stringsTest, contains("const Locale('en')"));
    expect(gradle, contains('resourceConfigurations += listOf("zh", "en")'));
    expect(manifest, contains('android:localeConfig="@xml/locales_config"'));
    expect(localeConfig, contains('<locale android:name="zh" />'));
    expect(localeConfig, contains('<locale android:name="en" />'));
    expect(localeConfig, isNot(contains('android:name="ja"')));
    expect(localeConfig, isNot(contains('android:name="ko"')));
    expect(localeConfig, isNot(contains('android:name="fr"')));
    expect(
      androidSmokeScript,
      contains(r'[string[]]$ExpectedResourceLanguages = @("zh", "en")'),
    );
    final forbiddenAndroidResourceLocales = Directory(
      'android/app/src/main/res',
    ).listSync().whereType<Directory>().expand((directory) {
      final name = directory.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      );
      if (!name.startsWith('values-')) {
        return const <String>[];
      }
      return name.substring('values-'.length).split('-').where((qualifier) {
        final languageParts = qualifier.split('+');
        final language = qualifier.startsWith('b+') && languageParts.length > 1
            ? languageParts[1]
            : qualifier;
        return RegExp(r'^[a-z]{2,3}$').hasMatch(language) &&
            language != 'zh' &&
            language != 'en';
      }).map((language) => name);
    }).toList();
    expect(forbiddenAndroidResourceLocales, isEmpty);
    expect(design, contains('Tooltips setting only controls'));
    expect(strings, contains('tipEnableToolTips'));
    expect(syncSettingsDialog, contains('class _SettingsHelpIcon'));
    expect(syncSettingsDialog, contains('tipEnableToolTips'));
  });

  test('PaperTodo settings toggle and close chrome are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final settings = _readProjectText('lib/src/ui/sync_settings_dialog.dart');
    final widgetTest = _readProjectText('test/widget_test.dart');

    expect(design, contains('Windows settings toggles follow PaperTodo'));
    expect(design, contains('M 4,8.1 L 7,11 L 12,5'));
    expect(design, contains('0.55 disabled option opacity'));
    expect(settings, contains('class _SettingsCheckboxTile'));
    expect(settings, contains('class _SettingsCheckMarkPainter'));
    expect(settings, contains('dimension: 16'));
    expect(settings, contains('static const double borderWidth = 1.5'));
    expect(settings, contains('..moveTo(4, 8.1)'));
    expect(settings, contains('..lineTo(7, 11)'));
    expect(settings, contains('..lineTo(12, 5)'));
    expect(settings, contains('opacity: enabled ? 1 : 0.55'));
    expect(settings, isNot(contains('CheckboxListTile(')));
    expect(settings, contains('class _SettingsCloseButton'));
    expect(settings, contains("ValueKey('settings-close-button-surface')"));
    expect(settings, contains("'\\u00D7'"));
    expect(widgetTest,
        contains('settings toggles and close button match PaperTodo chrome'));
  });

  test('PaperTodo settings hints preserve source coverage and chrome', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final strings = _readProjectText('lib/src/ui/papertodo_strings.dart');
    final settings = _readProjectText('lib/src/ui/sync_settings_dialog.dart');
    final widgetTest = _readProjectText('test/widget_test.dart');
    const tipKeys = <String>{
      'tipAllowLongLinkedNoteTitles',
      'tipCapsuleCollapseAll',
      'tipCapsuleMode',
      'tipCollapseExpandedDeepCapsuleOnClick',
      'tipCustomThemeColor',
      'tipDeepCapsuleMode',
      'tipEnableAnimations',
      'tipEnableTodoNoteLinks',
      'tipEnableToolTips',
      'tipExternalExtension',
      'tipExternalOpenButton',
      'tipFullscreenTopmostMode',
      'tipHideDeepCapsulesWhenCovered',
      'tipHideLinkedNotesFromCapsules',
      'tipHidePapersFromWindowSwitcher',
      'tipHideScriptRunWindow',
      'tipMarkdownRender',
      'tipMaxTitleLength',
      'tipNewNoteButton',
      'tipNewTodoButton',
      'tipNoteLineSpacing',
      'tipPersistentPowerShellProcess',
      'tipPinnedNoteHotKey',
      'tipPinnedTodoHotKey',
      'tipPreferPowerShell7',
      'tipRunLinkedScriptCapsulesOnClick',
      'tipShowDeepCapsuleWhileExpanded',
      'tipShowLinkedNoteName',
      'tipShowTodoDueRelativeTime',
      'tipStartup',
      'tipSystemFont',
      'tipThemeMode',
      'tipTodoDueYearDisplay',
      'tipTodoLineSpacing',
      'tipTodoReminderBubbleDuration',
      'tipTodoReminderInterval',
      'tipTodoReminderIntervalUnit',
      'tipTodoReminderScope',
      'tipTodoVisualSize',
      'tipUseTodoReminderInterval',
    };

    for (final tipKey in tipKeys) {
      expect(
        strings,
        matches(
          RegExp("static const $tipKey\\s*=\\s*'$tipKey';"),
        ),
        reason: '$tipKey must remain declared and localized.',
      );
      expect(
        settings,
        matches(RegExp('PaperTodoStringKeys\\s*\\.\\s*$tipKey')),
        reason: '$tipKey must remain connected to its settings option.',
      );
    }
    expect(design, contains('40 source `WrapWithHint` options'));
    expect(settings, contains("'\\u24D8'"));
    expect(settings, contains('dimension: 18'));
    expect(settings, contains('Duration(milliseconds: 200)'));
    expect(settings, contains('Duration(seconds: 20)'));
    expect(settings, contains('SystemMouseCursors.help'));
    expect(widgetTest, contains('expect(tester.getSize(capsuleHelp),'));
  });

  test('PaperTodo settings groups and 28px controls preserve source chrome',
      () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final strings = _readProjectText('lib/src/ui/papertodo_strings.dart');
    final settings = _readProjectText('lib/src/ui/sync_settings_dialog.dart');
    final widgetTest = _readProjectText('test/widget_test.dart');
    final adaptiveSelector = _sliceBetween(
      settings,
      'Widget _adaptiveChoiceSelector',
      'Widget _adaptiveFieldPair',
    );
    final sourceStepper = _sliceBetween(
      settings,
      'class _SettingsStepper extends',
      'class _SettingsWindowDialog extends',
    );

    expect(strings, contains("PaperTodoStringKeys.appearance: 'Display'"));
    expect(
      strings,
      contains("PaperTodoStringKeys.themeColorDefault: "
          "'Use default palette'"),
    );
    expect(
      strings,
      contains("PaperTodoStringKeys.themeColorClear: 'Default color'"),
    );
    expect(
      strings,
      contains("PaperTodoStringKeys.settingsTodoAndNotes: 'Todo / Notes'"),
    );
    expect(
      strings,
      contains("PaperTodoStringKeys.settingsGeneralAdvanced: "
          "'General / Advanced'"),
    );
    expect(
        strings, contains("settingsSectionTopBarButtons: 'Top-bar buttons'"));
    expect(settings, contains('Widget _settingsGroupLabel'));
    expect(settings, contains('EdgeInsets.only(top: 12, bottom: 3)'));
    expect(settings, contains('class _SettingsSegmentSelector'));
    expect(settings, contains('class _SettingsSegmentButton'));
    expect(adaptiveSelector, contains('_SettingsSegmentSelector('));
    expect(adaptiveSelector, isNot(contains('SegmentedButton<String>(')));
    expect(settings, contains('padding: const EdgeInsets.all(1)'));
    expect(settings, contains('fontSize: 12'));
    expect(settings, contains('FontWeight.w600'));
    expect(settings, contains('FontWeight.w400'));
    expect(sourceStepper, contains('height: 28'));
    expect(sourceStepper, contains('width: 34'));
    expect(sourceStepper, contains("fontFamily: 'Segoe UI Symbol'"));
    expect(sourceStepper, contains('onTapDown: (_) => widget.onPressed()'));
    expect(sourceStepper, isNot(contains('Tooltip(')));
    expect(settings, contains('BoxConstraints.tightFor(height: height)'));
    expect(settings, contains("'settings-reminder-interval'"));
    expect(settings, contains("'settings-reminder-duration'"));
    expect(settings, contains("'settings-pinned-todo-hotkey'"));
    expect(settings, contains('BoxConstraints(minWidth: 76)'));
    expect(settings, contains('BoxConstraints(minWidth: 82)'));
    expect(settings, contains('height: 27'));
    expect(settings, contains('class _SettingsAuthorLink'));
    expect(settings, contains('https://github.com/snownico0722'));
    expect(settings, contains('Duration(milliseconds: 300)'));
    expect(settings, contains('Duration(seconds: 12)'));
    expect(app, contains("openAuthorLink: () => _openUri("));
    expect(
      widgetTest,
      contains('inactive reminder mode keeps timing editors available'),
    );
    expect(widgetTest, contains('expect(tester.getSize(swatch),'));
    expect(design, contains('28px source segment selectors'));
  });

  test('runtime localization maps cover every declared string key', () {
    final strings = _readProjectText('lib/src/ui/papertodo_strings.dart');
    final declaredKeys = _declaredStringKeys(strings);
    final englishKeys = _localizedStringKeys(strings, '_enStrings');
    final chineseKeys = _localizedStringKeys(strings, '_zhStrings');

    expect(declaredKeys, isNotEmpty);
    expect(
      englishKeys.difference(declaredKeys),
      isEmpty,
      reason: 'English strings must not contain undeclared keys.',
    );
    expect(
      chineseKeys.difference(declaredKeys),
      isEmpty,
      reason: 'Chinese strings must not contain undeclared keys.',
    );
    expect(
      declaredKeys.difference(englishKeys),
      isEmpty,
      reason: 'Every declared key needs an English string.',
    );
    expect(
      declaredKeys.difference(chineseKeys),
      isEmpty,
      reason: 'Every declared key needs a Chinese string.',
    );
  });

  test('local model IDs strip raw control characters before persistence', () {
    final constants =
        _readProjectText('lib/src/core/model/paper_constants.dart');
    final appState = _readProjectText('lib/src/core/model/app_state.dart');
    final paperData = _readProjectText('lib/src/core/model/paper_data.dart');
    final paperItem = _readProjectText('lib/src/core/model/paper_item.dart');
    final canvasElement =
        _readProjectText('lib/src/core/model/note_canvas_element.dart');
    final syncDocs = _readProjectText('docs/SYNC.md');

    expect(constants, contains('String normalizeLocalModelId(String? value)'));
    expect(constants, contains('!_isRawControlCharacter(rune)'));
    expect(appState, contains('paper.id = normalizeLocalModelId(paper.id);'));
    expect(paperData, contains('id = normalizeLocalModelId(id);'));
    expect(paperData, contains('item.id = normalizeLocalModelId(item.id);'));
    expect(
      paperData,
      contains('element.id = normalizeLocalModelId(element.id);'),
    );
    expect(paperItem, contains('id = normalizeLocalModelId(id);'));
    expect(
      paperItem,
      contains('final normalizedLinkedNoteId = normalizeLocalModelId('),
    );
    expect(canvasElement, contains('id = normalizeLocalModelId(id);'));
    expect(syncDocs, contains('Local model normalization strips raw control'));
  });

  test('Android build targets Android 14 through 17', () {
    final gradle = _readProjectText('android/app/build.gradle.kts');
    final gradleProperties = _readProjectText('android/gradle.properties');
    final manifest =
        _readProjectText('android/app/src/main/AndroidManifest.xml');
    final localeConfig =
        _readProjectText('android/app/src/main/res/xml/locales_config.xml');
    final filePaths =
        _readProjectText('android/app/src/main/res/xml/file_paths.xml');
    final gitignore = _readProjectText('.gitignore');
    final readme = _readProjectText('README.md');
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final development = _readProjectText('docs/DEVELOPMENT.md');
    final app = _readProjectText('lib/src/app.dart');
    final appBootstrap =
        _readProjectText('lib/src/bootstrap/app_bootstrap.dart');
    final androidPlatform =
        _readProjectText('lib/src/platform/android_platform_services.dart');
    final mainActivity = _readProjectText(
        'android/app/src/main/kotlin/com/aligez/repapertodo/MainActivity.kt');

    expect(gradle, contains('compileSdk = 37'));
    expect(gradle, contains('minSdk = 34'));
    expect(gradle, contains('targetSdk = 37'));
    expect(gradle, contains('"proguard-rules.pro"'));
    final proguard = _readProjectText('android/app/proguard-rules.pro');
    expect(proguard, contains('androidx.work.impl.WorkDatabase_Impl'));
    expect(proguard, contains('<init>();'));
    expect(gradle, contains('resourceConfigurations += listOf("zh", "en")'));
    expect(manifest, contains('android:localeConfig="@xml/locales_config"'));
    expect(localeConfig, contains('<locale android:name="zh" />'));
    expect(localeConfig, contains('<locale android:name="en" />'));
    expect(localeConfig, isNot(contains('android:name="ja"')));
    expect(localeConfig, isNot(contains('android:name="ko"')));
    expect(localeConfig, isNot(contains('android:name="fr"')));
    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, contains('FileInputStream(keystorePropertiesFile).use'));
    expect(gradle, contains('hasAndroidSigningControlCharacter'));
    expect(gradle, contains('requireAndroidSigningPropertyValue'));
    expect(gradle, contains('requireAndroidStoreFileValue'));
    expect(gradle, contains('Android signing property'));
    expect(gradle, contains('must not contain control characters'));
    expect(gradle, contains('must not contain wildcard characters'));
    expect(gradle, contains('must not contain dot-segments'));
    expect(gradle, contains("storeFile.contains('*')"));
    expect(gradle, contains("storeFile.contains('?')"));
    expect(gradle, contains("storeFile.split('/', '\\\\')"));
    expect(gradle, contains('val releaseStoreFile'));
    expect(gradle, contains('val androidSigningKeys'));
    expect(gradle, contains('val androidSigningValues'));
    expect(gradle, contains('androidSigningKeys.associateWith'));
    expect(gradle, contains('value?.trim()'));
    expect(gradle, contains('androidSigningValues["storeFile"]'));
    expect(gradle, contains('androidSigningValues[key]?.isNotBlank()'));
    expect(gradle,
        contains('storePassword = androidSigningValues["storePassword"]'));
    expect(gradle, contains('keyAlias = androidSigningValues["keyAlias"]'));
    expect(
        gradle, contains('keyPassword = androidSigningValues["keyPassword"]'));
    expect(gradle, contains('hasReleaseSigningConfig'));
    expect(gradle, contains('releaseStoreFile?.isFile == true'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, contains('signingConfigs.getByName("debug")'));
    expect(gradle, contains('enableV2Signing = true'));
    expect(gradle, contains('enableV3Signing = true'));
    expect(gradleProperties, contains('android.newDsl=false'));
    expect(gradleProperties, contains('android.builtInKotlin=false'));
    expect(gradleProperties, contains('kotlin.incremental=false'));
    expect(gradleProperties, contains('cross-drive'));
    expect(development, contains('Push-Location android'));
    expect(development, contains('.\\gradlew.bat tasks --no-daemon'));
    expect(development, contains('Pop-Location'));
    expect(development, contains('quick configuration-phase check'));
    expect(development, contains('audit copies is best-effort only'));
    expect(development, contains('must not block loading'));
    expect(development, contains('Retired PaperTodo fields'));
    expect(development, contains('`TopBarHeight`'));
    expect(development, contains('preserved\nin `AppState.extra`'));
    expect(
      gradleProperties,
      contains('Flutter\n# Gradle plugin configures cleanly'),
    );
    expect(gitignore, contains('android/key.properties'));
    expect(gitignore, contains('*.jks'));
    expect(readme, contains('Android release signing'));
    expect(readme, contains('debug fallback'));
    expect(readme, contains('android/key.properties'));
    expect(readme, contains('`storeFile` points to an existing'));
    expect(readme, contains('same validation also runs'));
    expect(readme, contains('same trimmed signing\nvalues'));
    expect(readme, contains('direct APK builds'));
    expect(design, contains('System back from an opened paper surface'));
    expect(design, contains('return to the board'));
    expect(app, contains('PopScope<Object?>'));
    expect(app, contains('canPop: surfacePaper == null'));
    expect(app, contains('onPopInvokedWithResult'));
    expect(appBootstrap, contains('Desktop executable path contains'));
    expect(appBootstrap, contains('Mobile documents directory contains'));
    expect(appBootstrap, contains('_hasControlCharacter'));
    expect(androidPlatform, contains("trimmedPath.startsWith('/')"));
    expect(
      androidPlatform,
      contains('Android external file path must be absolute.'),
    );
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android:usesCleartextTraffic="true"'));
    expect(manifest, contains('androidx.core.content.FileProvider'));
    expect(manifest, contains('android:grantUriPermissions="true"'));
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android:scheme="http"'));
    expect(manifest, contains('android:scheme="https"'));
    expect(manifest, contains('android:scheme="mailto"'));
    expect(manifest, contains('android:mimeType="text/markdown"'));
    expect(manifest, contains('android:mimeType="text/plain"'));
    expect(manifest, contains('android:mimeType="*/*"'));
    expect(design, contains('Android package visibility queries'));
    expect(design, contains('generic file fallback'));
    expect(design, contains('Android app files'));
    expect(design, contains('external-file channel paths'));
    expect(design, contains('absolute `/...` paths'));
    expect(design, contains('must not\nexpose the external storage root'));
    expect(design, contains('RePaperTodo-scoped external directories'));
    expect(design, contains('canonicalize file paths'));
    expect(filePaths, contains('<files-path'));
    expect(filePaths, contains('<cache-path'));
    expect(filePaths, contains('<external-files-path'));
    expect(filePaths, contains('<external-path'));
    expect(filePaths, contains('name="external_repapertodo"'));
    expect(filePaths, contains('path="RePaperTodo/"'));
    expect(filePaths, contains('name="external_documents_repapertodo"'));
    expect(filePaths, contains('path="Documents/RePaperTodo/"'));
    expect(filePaths, contains('name="external_download_repapertodo"'));
    expect(filePaths, contains('path="Download/RePaperTodo/"'));
    expect(filePaths, isNot(contains('name="external_storage"')));
    expect(mainActivity, contains('FileProvider.getUriForFile'));
    expect(mainActivity, contains('val canonicalFile = try'));
    expect(mainActivity, contains('!isAllowedExternalFile(canonicalFile)'));
    expect(mainActivity, contains('externalFileShareRoots'));
    expect(mainActivity, contains('Environment.getExternalStorageDirectory()'));
    expect(mainActivity, contains('File(storageRoot, "RePaperTodo")'));
    expect(
      mainActivity,
      contains('File(storageRoot, "Documents/RePaperTodo")'),
    );
    expect(
      mainActivity,
      contains('File(storageRoot, "Download/RePaperTodo")'),
    );
    expect(mainActivity, contains('MimeTypeMap'));
    expect(mainActivity, contains('getMimeTypeFromExtension'));
    expect(mainActivity, contains('distinct()'));
    expect(mainActivity, contains('ClipData.newUri'));
    expect(mainActivity, contains('val trimmedUri = uri.trim()'));
    expect(mainActivity, contains('val parsedUri = try'));
    expect(mainActivity, contains('The URI is not valid.'));
    expect(mainActivity, contains('val trimmedPath = path.trim()'));
    expect(mainActivity, contains('!file.isAbsolute'));
    expect(mainActivity, contains('The file path must be absolute.'));
    expect(mainActivity, contains('!canonicalFile.isFile'));
    expect(mainActivity, contains('parsedUri.scheme'));
    expect(mainActivity, contains('uri.userInfo.isNullOrBlank()'));
    expect(mainActivity, contains('uri.encodedAuthority'));
    expect(mainActivity, contains('hasEncodedExternalUriAuthoritySeparator'));
    expect(mainActivity, contains('hasUnsafeExternalUriCharacter'));
    expect(mainActivity, contains('hasMalformedExternalUriPercentEscape'));
    expect(mainActivity, contains('The URI contains malformed escapes.'));
    expect(mainActivity, contains('hasEncodedUnsafeExternalUriCharacter'));
    expect(mainActivity, contains('hasRawExternalUriControlCharacter'));
    expect(mainActivity, contains('hasUnsafeExternalFilePathCharacter'));
    expect(mainActivity, contains('isAllowedExternalUri'));
    expect(mainActivity, contains('"mailto"'));
    expect(mainActivity, contains('val recipient = uri.schemeSpecificPart'));
    expect(
      mainActivity,
      contains('uri.authority.isNullOrBlank() && recipient.isNotBlank()'),
    );
    expect(mainActivity, contains('!recipient.startsWith("?")'));
    expect(mainActivity, contains('!recipient.startsWith("//")'));
    expect(mainActivity, contains('Intent.CATEGORY_BROWSABLE'));
    expect(mainActivity, contains('file_provider_failed'));
    expect(mainActivity, contains('SecurityException'));
    final androidOpenUriStart = mainActivity.indexOf('"openUri" ->');
    final androidTrimStart = mainActivity.indexOf(
        'val trimmedUri = uri.trim()', androidOpenUriStart);
    final androidRawCheckStart = mainActivity.indexOf(
      'hasRawExternalUriControlCharacter(uri)',
      androidOpenUriStart,
    );
    expect(androidOpenUriStart, isNonNegative);
    expect(androidRawCheckStart, greaterThan(androidOpenUriStart));
    expect(androidTrimStart, greaterThan(androidOpenUriStart));
    expect(androidRawCheckStart, lessThan(androidTrimStart));
  });

  test('platform launch hosts reject blank native channel arguments', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final externalUriTargets =
        _readProjectText('lib/src/core/model/external_uri_targets.dart');
    final android =
        _readProjectText('lib/src/platform/android_platform_services.dart');
    final windows =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final strings = _readProjectText('lib/src/ui/papertodo_strings.dart');

    expect(design, contains('reject blank launch\narguments'));
    expect(design, contains('percent-encoded control characters'));
    expect(design, contains('malformed percent escapes'));
    expect(design, contains('encoded authority separators'));
    expect(design, contains('external-file paths must reject raw control'));
    expect(design, contains('Generated external Markdown export filenames'));
    expect(design, contains('External Markdown extension settings'));
    expect(design, contains('including DEL and C1 controls'));
    expect(design, contains('not be constrained to a hardcoded Markdown'));
    expect(design, contains('reject repeated dots by preference'));
    expect(design, contains('External Markdown export writes must flush'));
    expect(app, contains(r'[<>:"/\\|?*\x00-\x1F\x7F-\x9F]'));
    expect(app, contains('writeAsStringSync(paper.content, flush: true)'));
    expect(app, contains('normalizeExternalUriTarget'));
    expect(app, contains('_platformFailureMessageKey'));
    expect(app, contains('_isGenericPlatformFailureMessage'));
    expect(app, contains('PaperTodoStringKeys.platformOpenUriFailed'));
    expect(strings, contains('platformOpenUriFailed'));
    expect(strings, contains('platformOpenExternalFileFailed'));
    expect(strings, contains('Unable to open the URI.'));
    expect(strings, contains('无法打开链接。'));
    expect(
        externalUriTargets, contains('hasEncodedUnsafeExternalUriCharacter'));
    expect(
        externalUriTargets, contains('hasMalformedExternalUriPercentEscape'));
    expect(externalUriTargets, contains('hasRawExternalUriControlCharacter'));
    expect(
      externalUriTargets,
      contains('hasEncodedExternalUriAuthoritySeparator'),
    );
    expect(android, contains('Android URI must not be blank.'));
    expect(
        android, contains('Android URI must not contain control characters.'));
    expect(android,
        contains('Android URI must not contain malformed percent escapes.'));
    expect(android,
        contains('Android URI must not contain encoded control characters.'));
    expect(android,
        contains('Android URI must not contain encoded authority separators.'));
    expect(android, contains('hasRawExternalUriControlCharacter(uri)'));
    expect(android, contains('hasEncodedExternalUriAuthoritySeparator'));
    expect(android, contains('isAllowedExternalUriTarget'));
    expect(android, contains('Android external file path must not be blank.'));
    expect(
        android,
        contains(
            'Android external file path must not contain control characters.'));
    expect(windows, contains('Windows URI must not be blank.'));
    expect(
        windows, contains('Windows URI must not contain control characters.'));
    expect(windows,
        contains('Windows URI must not contain malformed percent escapes.'));
    expect(windows,
        contains('Windows URI must not contain encoded control characters.'));
    expect(windows,
        contains('Windows URI must not contain encoded authority separators.'));
    expect(windows, contains('hasRawExternalUriControlCharacter(uri)'));
    expect(windows, contains('hasEncodedExternalUriAuthoritySeparator'));
    expect(windows, contains('isAllowedExternalUriTarget'));
    expect(windows, contains('Windows external file path must not be blank.'));
    expect(
        windows,
        contains(
            'Windows external file path must not contain control characters.'));
    final appState = _readProjectText('lib/src/core/model/app_state.dart');
    final paperConstants =
        _readProjectText('lib/src/core/model/paper_constants.dart');
    final settingsDialog =
        _readProjectText('lib/src/ui/sync_settings_dialog.dart');
    expect(appState, contains('rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)'));
    expect(appState, contains('normalizeCapsuleMonitorDeviceName'));
    expect(appState, contains('hasRawControlCharacter(key)'));
    expect(paperConstants, contains('normalizeCapsuleMonitorDeviceName'));
    expect(paperConstants, contains('hasRawControlCharacter'));
    expect(
      settingsDialog,
      contains('rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)'),
    );
  });

  test('sync design preserves merge safety rules', () {
    final syncDesign = _readProjectText('docs/SYNC.md');
    final webDavPresets =
        _readProjectText('lib/src/core/model/webdav_presets.dart');
    final syncSettingsSource =
        _readProjectText('lib/src/core/model/sync_settings.dart');
    final appStateCodec =
        _readProjectText('lib/src/core/state/app_state_codec.dart');
    final jsonHelpers =
        _readProjectText('lib/src/core/model/json_helpers.dart');
    final appSyncServiceSource =
        _readProjectText('lib/src/sync/app_sync_service.dart');
    final webDavStateSyncService =
        _readProjectText('lib/src/sync/webdav/webdav_state_sync_service.dart');
    final webDavPayloadCodec =
        _readProjectText('lib/src/sync/webdav/webdav_payload_codec.dart');
    final syncManifestSource =
        _readProjectText('lib/src/sync/sync_manifest.dart');
    final syncOperationSource =
        _readProjectText('lib/src/sync/sync_operation.dart');
    final syncOperationPayload =
        _readProjectText('lib/src/sync/sync_operation_payload.dart');
    final syncOperationDiff =
        _readProjectText('lib/src/sync/sync_operation_diff.dart');
    final development = _readProjectText('docs/DEVELOPMENT.md');
    final stateStore =
        _readProjectText('lib/src/core/storage/state_store.dart');
    final syncDeviceIdStore =
        _readProjectText('lib/src/sync/sync_device_id_store.dart');
    final crashRecovery =
        _readProjectText('lib/src/bootstrap/crash_recovery.dart');
    final app = _readProjectText('lib/src/app.dart');
    final mainDart = _readProjectText('lib/main.dart');
    final appBootstrap =
        _readProjectText('lib/src/bootstrap/app_bootstrap.dart');
    final androidBackgroundSync =
        _readProjectText('lib/src/sync/android_background_sync.dart');
    final pubspec = _readProjectText('pubspec.yaml');
    final strings = _readProjectText('lib/src/ui/papertodo_strings.dart');
    final paperConstants =
        _readProjectText('lib/src/core/model/paper_constants.dart');
    final noteCanvasElement =
        _readProjectText('lib/src/core/model/note_canvas_element.dart');

    expect(syncDesign, contains('earliest `createdAtUtc` first'));
    expect(syncDesign, contains('Durable Local Outbox'));
    expect(syncDesign, contains('same operation IDs and timestamps'));
    expect(syncDesign, contains('never included in remote snapshots'));
    expect(syncDesign, contains('cleared only after'));
    expect(syncDesign, contains('replayed over it'));
    expect(syncDesign, contains('Android WorkManager'));
    expect(syncSettingsSource, contains('pendingOperationBatch'));
    expect(appSyncServiceSource, contains('_uploadPendingSyncBatch'));
    expect(appSyncServiceSource, contains('_replayPendingSyncBatch'));
    expect(appSyncServiceSource, contains('_completePendingSyncBatch'));
    expect(syncDesign, contains('Tombstone timestamps only move forward'));
    expect(
        syncDesign, contains('Settings operations are intentionally limited'));
    expect(syncDesign, contains('startup-at-login state'));
    expect(syncDesign, contains('explicit app-preference whitelist'));
    expect(syncDesign, contains('root setting fields'));
    expect(syncDesign, contains('unknown local `AppState.extra` fields'));
    expect(syncDesign, contains('Local operation diff generation'));
    expect(syncDesign, contains('same\nwhitelist'));
    expect(syncDesign, contains('canonical settings payloads'));
    expect(syncDesign, contains('Invalid local setting values'));
    expect(syncDesign, contains('semantically equivalent setting formats'));
    expect(syncDesign, contains('Integer app-preference settings'));
    expect(syncDesign, contains('unsigned integer strings'));
    expect(syncDesign, contains('Double app-preference settings'));
    expect(syncDesign, contains('unsigned decimal'));
    expect(syncDesign, contains('whitespace-padded'));
    expect(syncDesign, contains('dropped instead of rounded'));
    expect(syncDesign, contains('Capsule-mode dependency settings'));
    expect(syncDesign, contains('deep-capsule\nmargin resets'));
    expect(syncDesign, contains('Boolean queue-map settings'));
    expect(syncDesign, contains('exact canonical'));
    expect(syncDesign, contains('canonical `false` values'));
    expect(syncDesign, contains('Double queue-map settings'));
    expect(syncDesign, contains('deep-capsule start margins'));
    expect(syncDesign, contains('model-normalized paper and todo-item'));
    expect(syncDesign, contains('uploading new upsert logs'));
    expect(
      syncOperationDiff,
      contains('canonicalSyncOperationSettingsPayload(state.toJson())'),
    );
    expect(
        syncOperationDiff, contains('JsonMap _settingsJson(AppState state)'));
    expect(
      syncOperationDiff,
      contains('canonicalSyncOperationPaperPayload(\n'
          '      PaperData.fromJson(paper.toJson()).toJson(),\n'
          '    )'),
    );
    expect(
      syncOperationDiff,
      contains('canonicalSyncOperationTodoItemPayload(\n'
          '      PaperItem.fromJson(item.toJson()).toJson(),\n'
          '    )'),
    );
    expect(syncOperationDiff, contains('normalizeLocalModelId(paper.id)'));
    expect(syncOperationDiff, contains('normalizeLocalModelId(item.id)'));
    expect(syncOperationDiff, isNot(contains("'papers',\n      'sync'")));
    expect(appStateCodec, contains("json.remove('startAtLogin')"));
    expect(appStateCodec, contains('_decodePaperTodoStateJson'));
    expect(appStateCodec, contains('_stripPaperTodoJsonComments'));
    expect(appStateCodec, contains('_removePaperTodoJsonTrailingCommas'));
    expect(appSyncServiceSource, contains('remoteState.startAtLogin'));
    expect(syncDesign,
        contains('Local device sequence progress must never move backward'));
    expect(syncDesign, contains('Upload result sequence maps'));
    expect(syncDesign,
        contains('Persisted or restored operation device sequence maps'));
    expect(syncDesign, contains('unsigned decimal integer strings'));
    expect(syncDesign, contains('signed strings'));
    expect(syncDesign, contains('exponent numeric forms'));
    expect(syncDesign, contains('discarded instead of rounded, coerced'));
    expect(syncSettingsSource, contains('_unsignedIntegerStringPattern'));
    expect(syncManifestSource, contains('_unsignedIntegerStringPattern'));
    expect(syncOperationSource, contains('_unsignedIntegerStringPattern'));
    expect(syncDesign, contains('cannot pollute local sync progress'));
    expect(syncDesign, contains('Downloaded or restored snapshot'));
    expect(syncDesign, contains('cannot drop known device progress'));
    expect(syncDesign, contains('save invalid device IDs'));
    expect(syncDesign, contains('locally'));
    expect(syncDesign, contains('must not return applied state as accepted'));
    expect(syncDesign, contains('unsaved remote operation progress'));
    expect(syncDesign, contains('Local delete operation uploads'));
    expect(syncDesign, contains('tombstone save failures'));
    expect(
        syncDesign, contains('Recovery snapshot restores must also surface'));
    expect(syncDesign, contains('preserving the previous local state on disk'));
    expect(syncDesign, contains('Restoring a legacy plain recovery snapshot'));
    expect(syncDesign, contains('must report the legacy plain source'));
    expect(syncDesign, contains('must not upload a migration snapshot'));
    expect(syncDesign, contains('next normal successful upload writes'));
    expect(appSyncServiceSource,
        contains('Snapshot restored from legacy plain WebDAV data'));
    expect(
        appSyncServiceSource,
        contains(
            'Future<AppSyncLocalOperationUploadResult> uploadLocalOperations'));
    expect(appSyncServiceSource, contains('_operationDiffBuilder.build'));
    expect(appSyncServiceSource,
        contains('Future<AppSyncOperationMergeResult> mergeRemoteOperations'));
    expect(appSyncServiceSource, contains('_operationApplier.apply'));
    expect(appSyncServiceSource, contains('result.state.normalize()'));
    expect(app, contains('syncSnapshotRestoredLegacyPlainNextUpload'));
    expect(strings, contains('syncSnapshotRestoredLegacyPlainNextUpload'));
    expect(
        syncDesign,
        contains(
            'Require a sync encryption passphrase before user-facing WebDAV sync runs'));
    expect(syncDesign,
        contains('Sync encryption passphrases must be trimmed, non-empty'));
    expect(syncDesign,
        contains('Malformed, unsupported, or\ncorrupted encrypted envelopes'));
    expect(syncDesign, contains('Legacy\nsnapshot migration failures'));
    expect(syncDesign, contains('manifest has a strong ETag'));
    expect(syncDesign, contains('no strong ETag is available'));
    expect(syncDesign, contains('preserving the downloaded state'));
    expect(syncDesign, contains('migration metadata save'));
    expect(syncDesign, contains('failures must not advance'));
    expect(syncDesign, contains('durably saved'));
    expect(syncDesign, contains('fields must be present and non-empty'));
    expect(syncDesign, contains('nonce, and MAC field sizes'));
    expect(syncDesign, contains('unpadded base64url text'));
    expect(syncDesign, contains('padded, non-URL-safe'));
    expect(syncDesign, contains('impossible-length values'));
    expect(syncDesign, contains('non-JSON or non-UTF-8 plain bytes'));
    expect(syncDesign,
        contains('unknown instead of treating arbitrary remote bytes'));
    expect(syncDesign, contains('defaults to 30 seconds'));
    expect(syncDesign, contains('default to 15\nminutes'));
    expect(syncDesign, contains('normalized to 1 through 1440 minutes'));
    expect(syncDesign, contains('normalized to 1 through'));
    expect(jsonHelpers, contains('JsonMap? jsonMapOrNull'));
    expect(jsonHelpers, contains('key is! String'));
    expect(development,
        contains('Temporary state\nand device-ID files are flushed'));
    expect(
      development,
      contains('tolerates UTF-8 BOMs, comments, and trailing commas'),
    );
    expect(development, contains('representative PaperTodo fixture path'));
    expect(development, contains('loads through the real `data.json` store'));
    expect(development, contains('preserving unknown future fields'));
    expect(development, contains('device-ID creation is serialized'));
    expect(development, contains('first successful save must skip backup'));
    expect(development, contains('flushed `RePaperTodo.crash.log`'));
    expect(development, contains('previous log exceeds 100 KB'));
    expect(development, contains('preserve the last 80 KB'));
    expect(stateStore, contains('_skipNextBackupRotationAfterRecovery = true'));
    expect(stateStore, contains('!skipBackupRotation'));
    expect(stateStore, contains('writeAsString(encodedState, flush: true)'));
    expect(syncDeviceIdStore,
        contains('static final Map<String, Future<void>> _fileQueues'));
    expect(syncDeviceIdStore, contains('p.canonicalize(filePath)'));
    expect(syncDeviceIdStore, contains('writeAsString(value, flush: true)'));
    expect(crashRecovery, contains('writeAsStringSync('));
    expect(crashRecovery, contains('FileMode.append'));
    expect(crashRecovery, contains('_maxCrashLogBytes = 100 * 1024'));
    expect(crashRecovery, contains('_keptCrashLogBytes = 80 * 1024'));
    expect(crashRecovery, contains('allowMalformed: true'));
    expect(crashRecovery, contains('flush: true'));
    expect(syncDesign, contains('Endpoint authority values'));
    expect(syncDesign, contains('endpoint paths\nwith dot-segments'));
    expect(syncDesign, contains('percent-encoded separators'));
    expect(syncDesign, contains('percent-encoded control characters'));
    expect(syncDesign, contains('usernames are trimmed before storage'));
    expect(syncDesign, contains('must\ncontain a non-whitespace character'));
    expect(syncDesign, contains('Passwords are preserved as entered'));
    expect(syncDesign, contains('may contain\ncolons'));
    expect(syncDesign, contains('percent-encoded\npath separators'));
    expect(syncDesign, contains('leading or trailing'));
    expect(syncDesign, contains('whitespace inside\ndecoded segments'));
    expect(syncDesign, contains('blank path segments'));
    expect(syncDesign, contains('non-empty segments that collapse to blank'));
    expect(syncDesign, contains('empty root folder'));
    expect(syncDesign, contains('values remain incomplete'));
    expect(syncDesign, contains('unsafe base URI paths including control'));
    expect(syncDesign, contains('unsafe base URI authorities'));
    expect(syncDesign, contains('request path'));
    expect(syncDesign, contains('request paths with backslashes'));
    expect(syncDesign, contains('segments that decode to path\nseparators'));
    expect(
        syncDesign, contains('Request path segments that collapse to blank'));
    expect(syncDesign,
        contains('decoded segments must not contain leading or trailing'));
    expect(syncDesign,
        contains('whitespace, so low-level callers cannot silently'));
    expect(syncDesign, contains('resolves all accepted paths'));
    expect(syncDesign, contains('metadata must be taken'));
    expect(syncDesign, contains('entry matching the requested'));
    expect(syncDesign, contains('same-time snapshot appears first'));
    expect(syncDesign, contains('requested resource path'));
    expect(syncDesign, contains('before direct snapshot'));
    expect(syncDesign, contains('filename-safe lowercase tokens'));
    expect(syncDesign, contains('8 through 64 characters'));
    expect(syncDesign, contains('invalid for remote path generation'));
    expect(syncDesign,
        contains('Manifest-referenced\nsnapshot file names must contain'));
    expect(
        syncDesign, contains('remains non-empty after\ndisplay normalization'));
    expect(syncDesign, contains('same filename-safe cleanup'));
    expect(syncDesign, contains('maximum length cap'));
    expect(syncDesign, contains('does not apply the minimum device-ID'));
    expect(
      syncDesign,
      contains('Manifest-referenced snapshot timestamps must parse\nstrictly'),
    );
    expect(
        syncDesign, contains('Manifest-referenced snapshot sequence suffixes'));
    expect(syncDesign, contains('inside the supported remote sequence range'));
    expect(syncDesign,
        contains('Generated snapshot and operation-log paths must reject'));
    expect(syncDesign, contains('device IDs that normalize\nto blank'));
    expect(syncDesign, contains('12-digit remote sequence range'));
    expect(syncDesign, contains('Next device sequences must stay inside'));
    expect(
        syncDesign, contains('Operation upload queues must skip operations'));
    expect(syncDesign, contains('whose device ID normalizes to\nblank'));
    expect(syncDesign, contains('whose targeted payload is structurally'));
    expect(syncDesign, contains('create a remote gap'));
    expect(syncDesign, contains('local persistence of accepted'));
    expect(syncDesign, contains('pending local edits can retry'));
    expect(
        syncDesign, contains('Manifest device sequences must reject values'));
    expect(syncDesign, contains('coerced into an integer'));
    expect(syncDesign, contains('Manifest `updatedAtUtc` wire timestamps'));
    expect(syncDesign,
        contains('Local operation diff generation and merge application'));
    expect(syncDesign,
        contains('Merge application must apply matching duplicate'));
    expect(syncDesign, contains('conflicting duplicate operations must block'));
    expect(syncDesign, contains('structurally incomplete'));
    expect(syncDesign, contains('missing paper, item, settings'));
    expect(syncDesign, contains('blank\n`linkedNoteId` strings'));
    expect(syncDesign, contains('only protected local fields'));
    expect(syncDesign, contains('startup-at-login, or paper lists'));
    expect(syncDesign, contains('containing only unknown fields'));
    expect(syncDesign, contains('JSON objects with string keys'));
    expect(syncDesign, contains('instead of throwing during merge'));
    expect(syncDesign, contains('Upsert-paper top-level fields'));
    expect(syncDesign, contains('Paper `type` is required'));
    expect(syncDesign, contains('missing types are structurally incomplete'));
    expect(syncDesign, contains('fallback bounds'));
    expect(syncDesign, contains('hard stored-title'));
    expect(syncDesign, contains('silently stripped or truncated'));
    expect(syncDesign, contains('shared Markdown editor storage limit'));
    expect(syncDesign, contains('must not carry non-empty note `content`'));
    expect(syncDesign, contains('Oversized note\ncontent'));
    expect(syncDesign, contains('Paper window dimensions'));
    expect(syncDesign, contains('`textZoom` must be positive'));
    expect(syncDesign, contains('Paper capsule identity fields'));
    expect(syncDesign, contains('`capsuleSide` must be blank'));
    expect(
        syncDesign, contains('capsule payloads are structurally incomplete'));
    expect(syncDesign, contains('non-empty collections on the matching'));
    expect(syncDesign, contains('wrong-type collections are structurally'));
    expect(syncDesign, contains('`todoExtraColumns`'));
    expect(syncDesign, contains('`todoColumnWidths`'));
    expect(syncDesign, contains('Negative column widths'));
    expect(syncDesign, contains('must\nalso include `todoColumnCount`'));
    expect(syncDesign, contains('must not exceed the declared\ncolumn shape'));
    expect(syncDesign, contains('Todo column counts'));
    expect(syncDesign, contains('silently normalized to one column'));
    expect(syncDesign, contains('`reminderIntervalValue`'));
    expect(syncDesign, contains('Todo due-date payloads'));
    expect(syncDesign, contains('PaperTodo-compatible parseable date strings'));
    expect(syncDesign, contains('clearing a due date is represented'));
    expect(syncDesign, contains('positive JSON\nintegers'));
    expect(syncDesign, contains('`minutes` or `hours`'));
    expect(syncDesign, contains('defaulting the unit to minutes'));
    expect(syncDesign, contains('malformed todo-item payloads'));
    expect(syncDesign, contains('shared Todo text-entry line limit'));
    expect(syncDesign, contains('bypass the local editor limit'));
    expect(syncDesign, contains('`zIndex`'));
    expect(syncDesign, contains('malformed canvas payloads'));
    expect(syncDesign, contains('Canvas element text payloads'));
    expect(syncDesign, contains('shared Markdown text limit'));
    expect(syncDesign, contains('Canvas `type` payloads'));
    expect(syncDesign, contains('`code`, `text`, or `sticky`'));
    expect(syncDesign, contains('silently normalized to code blocks'));
    expect(syncDesign, contains('Canvas geometry values'));
    expect(syncDesign, contains('note-canvas coordinate and size bounds'));
    expect(syncDesign, contains('Canvas `zIndex` values'));
    expect(syncDesign, contains('negative layers are structurally incomplete'));
    expect(syncDesign, contains('Accepted operation upload candidates'));
    expect(syncDesign, contains('canonical operation payloads'));
    expect(syncDesign, contains('physical line number'));
    expect(syncDesign, contains('standalone CR as\nphysical line delimiters'));
    expect(webDavPayloadCodec, contains('_looksLikePlainJsonPayload(bytes)'));
    expect(webDavPayloadCodec, contains('_splitPhysicalLines'));
    expect(webDavPayloadCodec, contains('exactly one operation'));
    expect(webDavStateSyncService, contains('_canonicalOperationForUpload'));
    expect(
      webDavStateSyncService,
      contains('final canonicalOperation = _canonicalOperationForUpload'),
    );
    expect(
      webDavStateSyncService,
      contains('canonicalSyncOperationPayload(operation)'),
    );
    expect(
      webDavStateSyncService,
      contains('encodeOperationLog(canonicalOperation)'),
    );
    expect(syncOperationPayload, contains('_payloadMarkdownTextFieldIsSafe'));
    expect(
        syncOperationPayload, contains('SyncTextLimits.maxMarkdownTextLength'));
    expect(
      syncOperationPayload,
      isNot(contains("import '../core/model/markdown_paste.dart'")),
    );
    expect(syncOperationPayload, contains('_payloadTodoTextFieldIsSafe'));
    expect(syncOperationPayload, contains('TodoPasteItems.maxLineLength'));
    expect(syncDesign, contains('Well-formed operations'));
    expect(syncDesign, contains('are still consumed'));
    expect(syncDesign, contains('Operation `createdAtUtc` wire timestamps'));
    expect(syncDesign,
        contains('Operation sequence numbers accept unsigned decimal integer'));
    expect(syncOperationSource, contains('_unsignedIntegerStringPattern'));
    expect(syncDesign, contains('exponent numeric forms'));
    expect(syncDesign, contains('Operation kind values are matched'));
    expect(syncDesign, contains('different valid operation kind'));
    expect(syncDesign, contains('snapshot-marker\noperation logs'));
    expect(syncDesign, contains('`snapshotPath` only'));
    expect(syncDesign, contains('Paper and todo-item upsert payloads'));
    expect(syncDesign, contains('same model\nnormalization'));
    expect(syncDesign, contains('equivalent\nduplicate logs into conflicts'));
    expect(syncDesign, contains('overflow dates or times'));
    expect(syncDesign, contains('invalid time-zone offsets'));
    expect(syncDesign, contains('leading or\ntrailing whitespace'));
    expect(syncDesign, contains('operation-log'));
    expect(syncDesign, contains('does not match their\noperation-log path'));
    expect(syncDesign, contains('downloaded result path does not match'));
    expect(syncDesign, contains('not legacy plain JSON'));
    expect(syncDesign, contains('exactly one operation'));
    expect(syncDesign, contains('Structurally incomplete operation payloads'));
    expect(syncDesign, contains('before legacy plain operation logs'));
    expect(syncDesign, contains('operation-log migration'));
    expect(syncDesign, contains('failures must be counted'));
    expect(syncDesign, contains('applying the downloaded'));
    expect(syncDesign, contains('Merge candidate selection must skip'));
    expect(syncDesign, contains('already\ncovered sequences'));
    expect(syncDesign, contains('before downloading\noperation log payloads'));
    expect(syncDesign, contains('previous device sequence\nmaps'));
    expect(syncDesign, contains('cannot hide valid remote sequence `1`'));
    expect(syncDesign, contains('provider listing order cannot decide'));
    expect(syncDesign, contains('Downloaded, decoded, or restored tombstone'));
    expect(syncDesign, contains('are discarded instead of'));
    expect(syncDesign, contains('normalized to a different instant'));
    expect(syncDesign, contains('Foreground/background transitions'));
    expect(syncDesign, contains('flush any pending local-edit operation'));
    expect(syncDesign, contains('before running the snapshot sync'));
    expect(syncDesign, contains('instead of waiting for the debounce timer'));
    expect(syncDesign, contains('lifecycle request must be queued'));
    expect(syncDesign, contains('after the active sync finishes'));
    expect(syncDesign, contains('Android backgrounding does not drop'));
    expect(syncDesign, contains('Exit commands must wait'));
    expect(syncDesign, contains('active manual or automatic sync attempt'));
    expect(syncDesign, contains('platform cleanup does not race'));
    expect(syncDesign, contains('Duplicate exit commands must share'));
    expect(syncDesign, contains('in-flight exit save/sync future'));
    expect(syncDesign, contains('While that exit future is active'));
    expect(syncDesign, contains('late startup commands, tray open/delete'));
    expect(syncDesign, contains('mutate paper visibility or tombstones'));
    expect(syncDesign, contains('If the active sync fails'));
    expect(syncDesign, contains('platform cleanup instead of leaving'));
    expect(syncDesign, contains('WorkManager periodic task'));
    expect(syncDesign, contains('headless Dart\n  background dispatcher'));
    expect(syncDesign, contains('receives only the local `data.json` path'));
    expect(syncDesign, contains('AppSyncService.syncAndMergeNow'));
    expect(syncDesign, contains('Incomplete or disabled WebDAV'));
    expect(syncDesign, contains('Registration and task execution'));
    expect(syncDesign, contains('unsafe, relative, or non-`data.json`'));
    expect(syncDesign, contains('scheduling'));
    expect(syncDesign, contains('doomed background work'));
    expect(syncDesign, contains('require network connectivity'));
    expect(syncDesign, contains('Disabled sync,\n  incomplete configuration'));
    expect(syncDesign, contains('remote write conflicts remain retryable'));
    expect(
        syncDesign, contains('Saving sync settings while the app is running'));
    expect(syncDesign, contains('after the new StateStore contents'));
    expect(syncDesign, contains('does not wait for the next app launch'));
    expect(pubspec, contains('workmanager:'));
    expect(
      _readProjectText('tool/local_webdav_server.dart'),
      contains("case 'PROPFIND':"),
    );
    expect(mainDart, contains('initializeRePaperTodoAndroidBackgroundSync'));
    expect(mainDart, contains('configureRePaperTodoAndroidBackgroundSync'));
    expect(app, contains('AndroidBackgroundSyncConfigurator'));
    expect(app, contains('configureAndroidBackgroundSync'));
    expect(
      app,
      contains('await _configureAndroidBackgroundSyncAfterSettingsSave()'),
    );
    expect(androidBackgroundSync, contains('@pragma(\'vm:entry-point\')'));
    expect(
      androidBackgroundSync,
      contains(
          'abstract interface class RePaperTodoAndroidBackgroundScheduler'),
    );
    expect(
      androidBackgroundSync,
      contains('class WorkmanagerRePaperTodoAndroidBackgroundScheduler'),
    );
    expect(
      androidBackgroundSync,
      contains('WorkmanagerRePaperTodoAndroidBackgroundScheduler(workmanager)'),
    );
    expect(androidBackgroundSync, contains('Workmanager().executeTask'));
    expect(androidBackgroundSync, contains('registerPeriodicTask'));
    expect(androidBackgroundSync,
        contains('Constraints(networkType: NetworkType.connected)'));
    expect(
        androidBackgroundSync, contains('ExistingPeriodicWorkPolicy.update'));
    expect(androidBackgroundSync, contains('BackoffPolicy.exponential'));
    expect(androidBackgroundSync, contains('cancelByUniqueName'));
    expect(androidBackgroundSync,
        contains('androidBackgroundSyncStateFilePathKey'));
    expect(
        androidBackgroundSync, contains('StateStore(filePath: stateFilePath)'));
    expect(
        androidBackgroundSync, contains('AppSyncService()).syncAndMergeNow'));
    expect(androidBackgroundSync,
        contains('_backgroundSyncCompletedWithoutRetry'));
    expect(androidBackgroundSync, contains('AppSyncStatus.payloadUnreadable'));
    expect(androidBackgroundSync, contains('AppSyncStatus.conflict => false'));
    expect(
        androidBackgroundSync, contains('_normalizeBackgroundStateFilePath'));
    expect(
        androidBackgroundSync, contains('_isAbsoluteBackgroundStateFilePath'));
    expect(androidBackgroundSync, contains('_backgroundStateFileName'));
    expect(androidBackgroundSync, contains("!= 'data.json'"));
    expect(androidBackgroundSync, contains('_hasControlCharacter'));
    expect(syncDesign, contains('Primary startup `exit` commands'));
    expect(syncDesign, contains('startup auto-sync is disabled'));
    expect(appBootstrap, contains('_shouldSyncOnExit'));
    expect(appBootstrap,
        contains('startupCommand.kind == StartupCommandKind.exit'));
    expect(appBootstrap,
        contains('controller.executeStartupCommand(startupCommand)'));
    expect(app, contains('Future<void>? _activeSyncFuture'));
    expect(app, contains('bool _queuedSilentSync = false'));
    expect(app, contains('_queuedSilentSync = true'));
    expect(app, contains('await _activeSyncFuture'));
    expect(app, contains('_runSyncNow(showMessage: showMessage)'));
    expect(syncDesign, contains('Silent local-edit upload failures'));
    expect(syncDesign, contains('automatic, lifecycle, or manual sync'));
    expect(syncDesign, contains('without\n  requiring another user edit'));
    expect(syncDesign, contains('Opening settings must pause pending'));
    expect(syncDesign, contains('canceling settings or saving settings'));
    expect(
        syncDesign, contains('without changing sync configuration restores'));
    expect(syncDesign, contains('platform setting application reports errors'));
    expect(syncDesign, contains('must clear the durable pending batch'));
    expect(syncDesign, contains('scheduling-only changes preserve both'));
    expect(syncDesign, contains('Settings save failures must surface'));
    expect(syncDesign, contains('later local edits blocked'));
    expect(syncDesign, contains('accepted idempotently'));
    expect(syncDesign, contains('creates no new remote log'));
    expect(
        syncDesign, contains('canonicalized state affect later sync inputs'));
    expect(syncDesign, contains('downloads can reach the network'));
    expect(syncDesign, contains('direct child files'));
    expect(syncDesign, contains('Direct remote path segments'));
    expect(syncDesign, contains('decode to path separators'));
    expect(syncDesign, contains('Listing `href` path segments'));
    expect(syncDesign, contains('must keep their decoded edge characters'));
    expect(syncDesign, contains('false `404` for\n`HEAD`'));
    expect(syncDesign, contains('matching safe `href`'));
    expect(syncDesign, contains('Remote layout components'));
    expect(syncDesign, contains('must not normalize to blank paths'));
    expect(syncDesign, contains('single path segments'));
    expect(syncDesign, contains('extra nested remote folders'));
    expect(syncDesign, contains('Direct state sync root paths'));
    expect(syncDesign, contains('must not normalize to blank'));
    expect(syncDesign, contains('recovery listings'));
    expect(syncDesign, contains('direct recovery downloads'));
    expect(syncDesign, contains('uploads can reach WebDAV'));
    expect(syncDesign, contains('Downloaded migration results'));
    expect(syncDesign, contains('Absolute and scheme-relative metadata'));
    expect(syncDesign, contains('same WebDAV origin'));
    expect(syncDesign, contains('Metadata `href` matches with query'));
    expect(syncDesign, contains('silently dropping non-path URI parts'));
    expect(syncDesign,
        contains('paths can be compared with the requested resource'));
    expect(syncDesign, contains('percent-encoded dot-segments'));
    expect(syncDesign, contains('different resource path'));
    expect(syncDesign, contains('Safe percent-encoded metadata `href` paths'));
    expect(syncDesign, contains('compared by decoded path segment'));
    expect(syncDesign, contains('Relative metadata `href` matches'));
    expect(syncDesign, contains('not an arbitrary suffix'));
    expect(syncDesign, contains('404 Not Found'));
    expect(syncDesign, contains('410 Gone'));
    expect(syncDesign, contains('direct payload downloads must still fail'));
    expect(syncDesign, contains('If `manifest.json` disappears'));
    expect(syncDesign, contains('`If-None-Match: *`'));
    expect(syncDesign, contains('explicit `Accept` headers'));
    expect(syncDesign, contains('stable `User-Agent`'));
    expect(syncDesign, contains('`Content-Length` and `getcontentlength`'));
    expect(syncDesign, contains('unsigned decimal digits'));
    expect(syncDesign, contains('padded, or malformed size values'));
    expect(syncDesign, contains('`Last-Modified` and `getlastmodified`'));
    expect(syncDesign, contains('exact HTTP\ndate values'));
    expect(syncDesign, contains('Malformed date metadata is ignored'));
    expect(syncDesign, contains('`PROPFIND` prefers XML responses'));
    expect(syncDesign, contains('Collection listings use `PROPFIND`'));
    expect(syncDesign,
        contains('same normalized path once with a trailing slash'));
    expect(syncDesign, contains('must not follow\nan arbitrary `Location`'));
    expect(syncDesign, contains('file-level metadata'));
    expect(syncDesign, contains('Provider `Retry-After` hints'));
    expect(syncDesign, contains('failure response bodies'));
    expect(syncDesign, contains('declared HTTP charsets'));
    expect(syncDesign, contains('shown in user-facing retryable\nsync errors'));
    expect(syncDesign, contains('including DEL and C1\ncontrols'));
    expect(syncDesign, contains('bounded truncation'));
    expect(app, contains(r'\x7F-\x9F'));
    expect(syncDesign, contains('Closing a WebDAV client wrapper'));
    expect(syncDesign, contains('underlying HTTP client was injected'));
    expect(syncDesign, contains('zero-second retry hint is valid'));
    expect(syncDesign, contains('signed or decimal delay values'));
    expect(syncDesign, contains('negative or malformed values are ignored'));
    expect(syncDesign, contains('Missing or weak ETags must not be used for'));
    expect(syncDesign, contains('malformed quote structure'));
    expect(syncDesign, contains('standards-compliant quoted'));
    expect(syncDesign, contains('exact original unquoted opaque ETag'));
    expect(syncDesign, contains('never degrade into an unconditional PUT'));
    expect(
      syncDesign,
      contains(
          'Weak,\ncontrol-character, wildcard-only, or malformed values are rejected'),
    );
    expect(syncDesign, contains('Provider `409` or `412` create-only'));
    expect(syncDesign, contains('original create-only conflict is preserved'));
    expect(syncDesign, contains('localized already-exists wording'));
    expect(syncDesign, contains('does not exist'));
    expect(syncDesign, contains('retryable WebDAV error messages'));
    expect(syncDesign, contains('Preset default root paths'));
    expect(syncDesign, contains('`坚果云` spellings'));
    expect(syncDesign, contains('omit\nthe root path field'));
    expect(syncDesign, contains('explicit custom or blank root path values'));
    expect(syncDesign, contains('New programmatic WebDAV settings'));
    expect(syncDesign, contains('unsafe explicit root paths'));
    expect(syncDesign, contains('parent-directory\nsegments'));
    expect(syncDesign, contains('blank middle path segments'));
    expect(webDavPresets, contains('String _normalizePresetRootPath'));
    expect(webDavPresets, contains("label: '坚果云'"));
    expect(webDavPresets, contains("trimmedSegment == '..'"));
    expect(webDavPresets, contains('_hasControlCharacter(segment)'));
    expect(webDavPresets, contains('_hasNonEmptySegmentBefore'));
    expect(syncSettingsSource, contains('json.containsKey(\'rootPath\')'));
    expect(syncSettingsSource, contains('preserveExplicitRootPath'));
    expect(syncSettingsSource, contains('rootPathWasBlank'));
    expect(syncSettingsSource, contains('String _defaultRootPathForPreset'));
    expect(syncDesign, contains('Absolute `href` values are accepted only'));
    expect(syncDesign, contains('cross-origin or'));
    expect(syncDesign, contains('base-path-escaping listing entries'));
    expect(syncDesign, contains('decode to path separators or dot-segments'));
    expect(syncDesign, contains('relative and server-absolute'));
    expect(syncDesign, contains('collapse to blank'));
    expect(syncDesign, contains('percent-encoded control characters'));
    expect(syncDesign, contains('local\nsnapshot or operation-log records'));
    expect(syncDesign, contains('Network-path `href` values'));
    expect(syncDesign, contains('configured endpoint scheme'));
    expect(syncDesign, contains('userinfo-bearing network-path'));
    expect(syncDesign, contains('decode into network-path or'));
    expect(syncDesign, contains('Plain relative'));
    expect(syncDesign, contains('must already start at the sync root'));
    expect(syncDesign, contains('bare\nchild file names'));
    expect(syncDesign, contains('requested collection'));
    expect(syncDesign, contains('query components, or fragments'));
    expect(
        syncDesign, contains('must not follow HTTP redirects automatically'));
    expect(syncDesign, contains('configured endpoint'));
    final syncSettings =
        _readProjectText('lib/src/core/model/sync_settings.dart');
    final webDavClient =
        _readProjectText('lib/src/sync/webdav/webdav_client.dart');
    expect(syncSettings, contains('_hasUnsafeEndpointAuthority'));
    expect(syncSettings, contains('value.trim().isNotEmpty'));
    expect(
      syncSettings,
      contains('rune <= 0x1F || (rune >= 0x7F && rune <= 0x9F)'),
    );
    expect(syncSettings, contains("'%40'"));
    expect(webDavClient, contains('_hasUnsafeBaseUriAuthority'));
    expect(webDavClient, contains('_safeDecodedHrefPathSegments'));
    expect(webDavClient, contains('_relativeRequestPathSegments'));
    expect(webDavClient, contains('_requestParentRelativePathSegments'));
    expect(webDavClient, contains('_pathSegmentsEqual'));
    expect(webDavClient, contains('_rawHrefPath'));
    expect(webDavClient, contains('_effectiveHrefPort'));
    expect(webDavClient, contains('!hrefUri.hasScheme'));
    expect(webDavClient, contains('_decodedResponseBody'));
    expect(webDavClient, contains('_encodingFromContentTypeOrNull'));
    expect(webDavClient,
        contains('_shouldRetryCollectionPropFindWithTrailingSlash'));
    expect(webDavClient, contains('_withTrailingSlash(path)'));
    expect(webDavClient, contains('statusCode == 301'));
    expect(webDavClient, contains('statusCode == 308'));
    expect(webDavClient, contains("depth == '0'"));
    expect(webDavClient, contains("body.contains('already exist')"));
    expect(webDavClient, isNot(contains("body.contains('exist')")));
    expect(webDavClient, contains('if (_closed)'));
    expect(webDavClient, contains('_closed = true'));
    expect(webDavClient, contains('if (_ownsHttpClient)'));
    expect(webDavClient, contains("RegExp(r'^\\d+\$')"));
    expect(webDavClient, contains('_normalizedHeaderEtagValue'));
    expect(webDavClient, contains('_normalizedPropEtagValue'));
    expect(webDavClient, contains('_normalizedIfMatchHeaderValue'));
    expect(webDavClient, contains('_hasValidRemoteEtagShape'));
    expect(webDavStateSyncService, contains('_hasValidRemoteEtagShape'));
    expect(appSyncServiceSource, contains('_hasValidRemoteEtagShape'));
    expect(webDavClient, contains('value.trim().isNotEmpty'));
    expect(
      webDavClient,
      contains('rune <= 0x1F || (rune >= 0x7F && rune <= 0x9F)'),
    );
    expect(webDavClient, contains("'%40'"));
    expect(webDavClient, contains('segment != trimmed'));
    expect(
      webDavClient,
      contains(
        'WebDAV path segments must not contain leading or trailing whitespace.',
      ),
    );
    expect(
      webDavClient,
      contains('WebDAV path must not contain backslashes.'),
    );
    final syncDeviceId =
        _readProjectText('lib/src/core/model/sync_device_id.dart');
    final webDavStateSync =
        _readProjectText('lib/src/sync/webdav/webdav_state_sync_service.dart');
    expect(syncDeviceId, contains('syncDeviceSequenceWireWidth'));
    expect(syncDeviceId, contains('maxSyncDeviceSequence'));
    expect(syncDeviceId, contains('minSyncDeviceIdLength'));
    expect(syncDeviceId, contains('maxSyncDeviceIdLength'));
    expect(syncDeviceId, contains('normalizeSyncDeviceIdForDisplay'));
    expect(syncDeviceId, isNot(contains('length < 8')));
    expect(syncDeviceId, isNot(contains('substring(0, 64')));
    expect(webDavStateSync, contains('syncDeviceSequenceWireWidth'));
    expect(webDavStateSync, contains('normalizeSyncDeviceIdForDisplay'));
    expect(webDavStateSync, contains('trimmed != decoded'));
    expect(webDavStateSync, contains('_compareSnapshotRecordOrder'));
    expect(webDavStateSync, isNot(contains('padLeft(12')));
    expect(webDavStateSync, isNot(contains(r'\d{12}')));
    expect(webDavStateSync, isNot(contains('length <= 64')));
    expect(webDavStateSync, isNot(contains('substring(0, 64')));
    expect(webDavStateSync, isNot(contains(r"RegExp(r'[^a-z0-9_-]+')")));
    final wireDateTime =
        _readProjectText('lib/src/core/model/sync_wire_datetime.dart');
    final syncManifest = _readProjectText('lib/src/sync/sync_manifest.dart');
    final syncOperation = _readProjectText('lib/src/sync/sync_operation.dart');
    final syncOperationApplier =
        _readProjectText('lib/src/sync/sync_operation_applier.dart');
    final publicExports = _readProjectText('lib/repapertodo.dart');
    final appSyncService =
        _readProjectText('lib/src/sync/app_sync_service.dart');
    expect(wireDateTime, contains('parseStrictSyncWireDateTimeUtc'));
    expect(wireDateTime, contains('tryParseStrictSyncWireDateTimeUtc'));
    expect(syncSettings, contains('tryParseStrictSyncWireDateTimeUtc'));
    expect(syncSettings, isNot(contains('DateTime.tryParse')));
    expect(syncSettings, contains('_syncDeviceSequencesFromWire'));
    expect(syncSettings, contains('_normalizeTombstoneId'));
    expect(syncSettings, isNot(contains('operationDeviceSequences: intMap')));
    expect(syncSettings, isNot(contains('value is num')));
    expect(syncSettings, isNot(contains('int.tryParse(value.trim())')));
    expect(syncManifest, contains('parseStrictSyncWireDateTimeUtc'));
    expect(syncManifest, isNot(contains('DateTime.tryParse')));
    expect(syncManifest, isNot(contains('value is num')));
    expect(syncManifest, isNot(contains('int.tryParse(value.trim())')));
    expect(syncOperation, contains('parseStrictSyncWireDateTimeUtc'));
    expect(syncOperation, contains('jsonMapOrNull(value)'));
    expect(syncOperation, isNot(contains('DateTime.tryParse')));
    expect(syncOperation, isNot(contains('value is num')));
    expect(syncOperation, isNot(contains('int.tryParse(value.trim())')));
    expect(syncOperationApplier, contains('_hasConflictingDuplicateAt'));
    expect(syncOperationApplier, contains('_operationsMatch'));
    expect(
      syncOperationApplier,
      contains('isSyncOperationPayloadWellFormed'),
    );
    expect(syncOperationPayload, contains('isSyncOperationPayloadWellFormed'));
    expect(syncOperationPayload, contains('_isSafeSnapshotPathPayload'));
    expect(syncOperationPayload, contains('_hasSafePaperPayloadIds'));
    expect(syncOperationPayload, contains('_hasSafePaperTopLevelPayloadShape'));
    expect(syncOperationPayload, contains('_payloadPaperTitleFieldIsSafe'));
    expect(syncOperationPayload, contains('PaperTitles.cleanCustomTitle'));
    expect(syncOperationPayload, contains("'isVisible'"));
    expect(syncOperationPayload, contains("'textZoom'"));
    expect(syncOperationPayload, contains('_payloadPaperDimensionFieldIsSafe'));
    expect(syncOperationPayload, contains('_payloadPositiveNumberFieldIsSafe'));
    expect(
        syncOperationPayload, contains('_payloadPaperCapsuleSideFieldIsSafe'));
    expect(syncOperationPayload, contains('_payloadMonitorNameFieldIsSafe'));
    expect(syncOperationPayload, contains("'capsuleSide'"));
    expect(syncOperationPayload, contains("'capsuleMonitorDeviceName'"));
    expect(syncOperationPayload, contains('_hasSafeTodoItemPayloadIds'));
    expect(syncOperationPayload, contains('_hasSafeTodoItemPayloadShape'));
    expect(syncOperationPayload,
        contains('_hasSafeNoteCanvasElementPayloadShape'));
    expect(syncOperationPayload, contains('_payloadStringFieldIsSafe'));
    expect(syncOperationPayload, contains('_payloadIntFieldIsSafe'));
    expect(syncOperationPayload, contains('_payloadPositiveIntFieldIsSafe'));
    expect(syncOperationPayload, contains('_payloadBoolFieldIsSafe'));
    expect(
        syncOperationPayload, contains("!_payloadContainsKey(paper, 'type')"));
    expect(syncOperationPayload, contains('elements.isNotEmpty'));
    expect(syncOperationPayload, contains('items.isNotEmpty'));
    expect(syncOperationPayload,
        contains('_payloadNoteCanvasElementTypeFieldIsSafe'));
    expect(syncOperationPayload,
        contains('_supportedNoteCanvasElementTypePayloadValues'));
    expect(syncOperationPayload, contains("'sticky'"));
    expect(syncOperationPayload, contains("'dueAtLocal'"));
    expect(syncOperationPayload, contains('_payloadTodoDueAtLocalFieldIsSafe'));
    expect(syncOperationPayload, contains('parsePaperTodoDueAtLocal(value)'));
    expect(syncOperationPayload, contains("'reminderIntervalValue'"));
    expect(syncOperationPayload, contains('_payloadTodoReminderFieldsAreSafe'));
    expect(syncOperationPayload, contains('value <= 0'));
    expect(syncOperationPayload, contains('value.trim().isNotEmpty'));
    expect(syncOperationPayload, contains("'todoExtraColumns'"));
    expect(syncOperationPayload, contains("'todoColumnWidths'"));
    expect(syncOperationPayload, contains('_payloadTodoColumnListsAreSafe'));
    expect(
        syncOperationPayload, contains('!hasExtraColumns && !hasColumnWidths'));
    expect(syncOperationPayload,
        contains('extraColumns.length > columnCount - 1'));
    expect(syncOperationPayload, contains('columnWidths.length > columnCount'));
    expect(syncOperationPayload, contains('value < 0'));
    expect(syncOperationPayload, contains("'zIndex'"));
    expect(syncOperationPayload, contains('zIndex < 0'));
    expect(syncOperationPayload, contains('_payloadNumberFieldInRangeIsSafe'));
    expect(syncOperationPayload, contains('NoteCanvasElementLimits.minWidth'));
    expect(paperConstants,
        contains('abstract final class NoteCanvasElementLimits'));
    expect(
        noteCanvasElement, contains('NoteCanvasElementLimits.maxCoordinate'));
    expect(syncOperationPayload, contains('_optionalPayloadIdIsSafe'));
    expect(syncOperationPayload, contains('_jsonMapListPayloadOrNull'));
    expect(syncOperationPayload, contains("Uri.decodeComponent(value)"));
    expect(syncOperationPayload, contains("decoded.startsWith('/')"));
    expect(syncOperationPayload, contains("trimmed == '..'"));
    expect(syncOperationPayload, contains('_hasApplicableSettingsPayload'));
    expect(syncOperationPayload, isNot(contains('return value.round();')));
    expect(syncOperationPayload, isNot(contains('int.tryParse(value.trim())')));
    expect(syncOperationPayload,
        contains('applicableSyncOperationSettingsPayload'));
    expect(syncOperationPayload, contains('_syncOperationAppPreferenceKeys'));
    expect(syncOperationPayload, contains('_canonicalBooleanQueueMapSetting'));
    expect(syncOperationPayload, contains('entry.key == queueKey'));
    expect(syncOperationPayload, contains('canonical.remove(entry.key)'));
    expect(syncOperationPayload, contains('_canonicalDoubleQueueMapSetting'));
    expect(syncOperationPayload, contains('margin.clamp(8, 10000).toDouble()'));
    expect(
      syncOperationPayload,
      contains('_canonicalMonitorDeviceNameSettingValue'),
    );
    expect(syncOperationPayload, contains('_hasControlCharacter(value)'));
    expect(syncOperationPayload, contains("'enableToolTips'"));
    expect(syncOperationPayload, contains("'hideDeepCapsulesWhenCovered'"));
    expect(
      syncOperationPayload,
      contains("'hideDeepCapsulesWhenFullscreen'"),
    );
    expect(
      syncOperationPayload,
      isNot(contains("canonical['hideDeepCapsulesWhenCovered'] =\n"
          "        retiredFullscreen")),
    );
    expect(syncOperationPayload, isNot(contains("..remove('sync')")));
    expect(syncOperationPayload, isNot(contains("..remove('startAtLogin')")));
    expect(syncOperationPayload, isNot(contains("..remove('papers')")));
    expect(syncOperationApplier,
        contains('canonicalSyncOperationSettingsPayload(settings)'));
    expect(syncOperationApplier, contains('AppState.fromJson(merged)'));
    expect(syncOperationApplier, isNot(contains('..extra = updated.extra')));
    expect(
      publicExports,
      contains("export 'src/sync/sync_operation_payload.dart';"),
    );
    expect(syncOperationPayload, contains('_payloadMarkdownTextFieldIsSafe'));
    expect(syncOperationPayload, contains('jsonMapOrNull(value)'));
    expect(syncOperationApplier, contains('jsonMapOrNull(value)'));
    expect(webDavStateSync, contains('isSyncOperationPayloadWellFormed'));
    expect(
      webDavStateSync,
      contains('!isSyncOperationPayloadWellFormed(result.operations.single)'),
    );
    expect(appSyncService, contains('tryParseStrictSyncWireDateTimeUtc'));
    expect(appSyncService, isNot(contains('DateTime.tryParse')));
    expect(
      syncDesign,
      contains('Delete operation payload keys must remain case-insensitive'),
    );
    expect(
      syncDesign,
      contains('queue-map keys with raw control characters are'),
    );
    expect(
      syncDesign,
      contains('Target paper IDs, todo-item IDs, linked-note IDs'),
    );
    expect(
      syncDesign,
      contains('Malformed ID payloads block that device'),
    );
    expect(
      syncDesign,
      contains('Duplicate nested IDs are structurally'),
    );
    expect(
      syncDesign,
      contains('nested collection fields such as `items`'),
    );
    expect(
      syncDesign,
      contains('silently dropped'),
    );
    expect(
      syncDesign,
      contains('tombstone paper IDs and todo-item IDs'),
    );
    expect(
      syncDesign,
      contains('leading or trailing control characters'),
    );
    expect(appSyncService,
        contains("_payloadString(operation.payload, 'paperId')"));
    expect(appSyncService,
        contains("_payloadString(operation.payload, 'itemId')"));
    expect(
        appSyncService, contains('_payloadValue(Map<String, Object?> payload'));
    expect(
      appSyncService,
      contains('isSyncDeviceSequenceInRange(record.sequence)'),
    );
    expect(appSyncService, contains('normalizeSyncDeviceSequences('));
    expect(appSyncService, contains('path.compareTo'));
    expect(appSyncService, contains("record.etag ?? ''"));
    expect(
      appSyncService,
      contains('deviceSequences ?? localState.sync.operationDeviceSequences'),
    );
    expect(app, contains('_isSettingsOpen'));
    expect(app, contains('_deferredSettingsSync'));
    expect(app, contains('_clearPendingLocalEditSync'));
    expect(app, contains('_localEditSyncGeneration'));
    expect(webDavPayloadCodec, contains('_saltLength'));
    expect(webDavPayloadCodec, contains('_nonceLength'));
    expect(webDavPayloadCodec, contains('_macLength'));
    expect(webDavPayloadCodec, contains('invalid envelope field sizes'));
    expect(webDavPayloadCodec, contains('_stringField'));
    expect(webDavPayloadCodec, contains('_base64UrlField'));
    expect(webDavPayloadCodec, contains('_base64UrlNoPaddingPattern'));
    expect(webDavPayloadCodec, contains("value.contains('=')"));
  });

  test('PaperTodo compatibility keeps retired fields non-destructive', () {
    final migration =
        _readProjectText('lib/src/core/state/papertodo_legacy_migration.dart');
    final appState = _readProjectText('lib/src/core/model/app_state.dart');
    final codecTest = _readProjectText('test/app_state_codec_test.dart');
    final development = _readProjectText('docs/DEVELOPMENT.md');

    expect(migration, contains("'TopBarHeight': 'topBarHeight'"));
    expect(appState, isNot(contains("'topBarHeight',")));
    expect(appState, contains('extra: preserveUnknown(json, _knownKeys)'));
    expect(appState, contains('...extra'));
    expect(codecTest, contains("'topBarHeight': 18.5"));
    expect(codecTest, contains('"TopBarHeight": 19'));
    expect(codecTest, contains("encoded['topBarHeight'], 18.5"));
    expect(codecTest, contains("encoded['topBarHeight'], 19"));
    expect(development, contains('Retired PaperTodo fields'));
  });

  test('Windows runner preserves startup command parsing parity', () {
    final runner = _readProjectText('windows/runner/main.cpp');
    final utils = _readProjectText('windows/runner/utils.cpp');
    final utilsHeader = _readProjectText('windows/runner/utils.h');
    final dartParser =
        _readProjectText('lib/src/core/startup/startup_command.dart');
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');

    expect(utils, contains('find_first_of("=:", segment_start)'));
    expect(utils, contains('CreatedPaperStartupCommand'));
    expect(utilsHeader, contains('StartupCommandFromArgs'));
    expect(runner, contains('class ScopedComInitializer'));
    expect(runner, contains('class ScopedHandle'));
    expect(runner, contains('~ScopedComInitializer()'));
    expect(runner, contains('~ScopedHandle()'));
    expect(runner, contains('IsExplicitExitStartupCommand'));
    expect(runner, contains('OpenMutexW(SYNCHRONIZE'));
    expect(runner, contains('existing_instance.is_valid()'));
    expect(utils, contains('if (normalized_args.empty())'));
    expect(utils, contains('return "show";'));
    expect(utils, contains('return std::string();'));
    expect(utils, contains('if (command.empty())'));
    expect(runner, isNot(contains('CreatedPaperStartupCommand')));
    expect(design, contains('return before creating the'));
    expect(design, contains('only unknown arguments'));
    expect(
      runner.indexOf('if (IsExplicitExitStartupCommand'),
      lessThan(runner.indexOf('flutter::DartProject project')),
    );
    expect(
      runner.indexOf('ScopedComInitializer com_initializer'),
      lessThan(runner.indexOf('return EXIT_FAILURE')),
    );
    expect(dartParser, contains("RegExp(r'[=:]+')"));
    expect(dartParser, contains('_createdPaperKind'));
  });

  test('Windows runner forwards secondary instance startup commands', () {
    final entrypoint = _readProjectText('windows/runner/main.cpp');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final utils = _readProjectText('windows/runner/utils.cpp');
    final utilsHeader = _readProjectText('windows/runner/utils.h');
    final windowsPlatform =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final dartParser =
        _readProjectText('lib/src/core/startup/startup_command.dart');
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');

    expect(entrypoint, contains('kSingleInstanceMutexName'));
    expect(entrypoint, contains('kSingleInstancePipeName'));
    expect(entrypoint, contains('CreateMutexW'));
    expect(entrypoint, contains('ERROR_ALREADY_EXISTS'));
    expect(entrypoint, contains('StartupCommandFromArgs'));
    expect(utilsHeader, contains('SignalStartupCommandPipe'));
    expect(utilsHeader, contains('SignalPipeWake'));
    expect(utils, contains('WriteStartupCommandToPipe'));
    expect(utils, contains('WritePipeWake'));
    expect(utils, contains('bytes_written != static_cast<DWORD>'));
    expect(utils, contains('ScopedHandle pipe(CreateFileW'));
    expect(utils, contains('pipe.is_valid()'));
    expect(runner, contains('class ScopedWinHandle'));
    expect(runner, contains('~ScopedWinHandle()'));
    expect(utils, contains('reveal-pinned-todo'));
    expect(utils, contains('reveal-pinned-note'));
    expect(dartParser, contains('reveal-pinned-todo'));
    expect(dartParser, contains('reveal-pinned-note'));
    expect(
        entrypoint, contains('SignalPrimaryInstance(command_line_arguments)'));
    expect(
      entrypoint,
      contains('SignalStartupCommandPipe(kSingleInstancePipeName'),
    );
    expect(runner, contains('SignalPrimaryInstanceFromChannel'));
    expect(runner, contains('GetStringListArgumentValue(call.arguments())'));
    expect(
      runner,
      contains('SignalStartupCommandPipe(kSingleInstancePipeName'),
    );
    expect(runner, contains('forward_to_primary_failed'));
    expect(
      runner,
      isNot(contains(
          'if (method == "forwardToPrimary") {\n          result->Success();')),
    );
    expect(utils, contains('WaitNamedPipeW(pipe_name'));
    expect(runner, contains('StartSingleInstanceListener();'));
    expect(runner, contains('ScopedWinHandle pipe(CreateNamedPipeW'));
    expect(runner, contains('ConnectNamedPipe(pipe.get(), nullptr)'));
    expect(runner, contains('ReadFile(pipe.get(), buffer'));
    expect(runner, contains('DisconnectNamedPipe(pipe.get())'));
    expect(runner, contains('kMaxSingleInstanceCommandBytes = 4096'));
    expect(runner, contains('FirstStartupCommandLine'));
    expect(runner, contains('CanonicalStartupCommandLine'));
    expect(runner, contains("const size_t newline = command.find('\\n')"));
    expect(runner, contains('command = command.substr(0, newline)'));
    expect(runner, contains('command = FirstStartupCommandLine(command)'));
    expect(
      runner,
      contains('command.empty() || HasAsciiControlCharacter(command)'),
    );
    expect(
      runner,
      contains('StartupCommandFromArgs(std::vector<std::string>{command})'),
    );
    expect(runner, contains('command = CanonicalStartupCommandLine(command)'));
    expect(runner, contains('bytes_to_append < bytes_read'));
    expect(
        runner, contains('command.size() >= kMaxSingleInstanceCommandBytes'));
    expect(
        runner, contains('PostMessageW(window, kSingleInstanceCommandMessage'));
    expect(runner, contains('auto command_message = std::make_unique'));
    expect(runner, contains('command_message.get()'));
    expect(runner, contains('command_message.release()'));
    expect(runner, isNot(contains('new std::string(command)')));
    expect(runner, contains('case kSingleInstanceCommandMessage'));
    expect(runner, contains('SendStartupCommandRequested(*command)'));
    expect(runner, contains('const std::string canonical_command'));
    expect(
      runner,
      contains('StartupCommandFromArgs(std::vector<std::string>{command})'),
    );
    expect(runner, contains('HasAsciiControlCharacter(canonical_command)'));
    expect(runner, contains('flutter::EncodableValue>(canonical_command)'));
    expect(runner, contains('StopSingleInstanceListener();'));
    expect(runner, contains('SignalPipeWake(kSingleInstancePipeName'));
    expect(
      runner,
      isNot(contains('CreateFileW(kSingleInstancePipeName, GENERIC_WRITE')),
    );
    expect(runner, isNot(contains('CloseHandle(pipe)')));
    expect(runner, contains('single_instance_listener_thread_.join()'));
    expect(windowsPlatform, contains('_pendingCommands'));
    expect(windowsPlatform, contains('onListen: _flushPendingCommands'));
    expect(windowsPlatform, contains('scheduleMicrotask'));
    expect(design, contains('buffer early\ncommands'));
    expect(design, contains('PostMessageW` succeeds'));
    expect(design, contains('failed posts during\nteardown'));
    expect(design, contains('Startup-at-login registration'));
    expect(design, contains('dynamically sized module path buffer'));
    expect(runner, contains('std::wstring CurrentExecutablePath()'));
    expect(runner, contains('std::vector<wchar_t> buffer(MAX_PATH)'));
    expect(runner, contains('buffer.resize(buffer.size() * 2)'));
    expect(runner,
        contains('const std::wstring module_path = CurrentExecutablePath();'));
    expect(runner, isNot(contains('wchar_t module_path[MAX_PATH]')));
  });

  test('Windows tray icon keeps PaperTodo external icon behavior', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final header = _readProjectText('windows/runner/flutter_window.h');

    expect(design, contains('TaskbarCreated'));
    expect(design, contains('re-adding the notification icon'));
    expect(design, contains('PaperTodo.ico'));
    expect(design, contains('RePaperTodo.ico'));
    expect(design, contains('Windows executable should override'));
    expect(design, contains('long install'));
    expect(design, contains('runtime icon overrides'));
    expect(design, contains('RePaperTodo v<version>'));
    expect(design, contains("metadata after `+` hidden"));
    expect(runner, contains('RegisterWindowMessageW(L"TaskbarCreated")'));
    expect(runner, contains('message == taskbar_created_message_'));
    expect(runner, contains('tray_icon_added_ = false'));
    expect(runner, contains('AddTrayIcon();'));
    expect(runner, contains('std::wstring AppDisplayName()'));
    expect(runner, contains('FLUTTER_VERSION'));
    expect(runner, contains("version.find('+')"));
    expect(runner, contains('RePaperTodo v'));
    expect(
        runner, contains('append_owner_draw(menu.get(), 0, AppDisplayName()'));
    expect(runner, contains('ExecutableDirectory()'));
    expect(
        runner,
        contains(
            'const std::wstring executable_path = CurrentExecutablePath();'));
    expect(runner,
        isNot(contains('std::array<wchar_t, MAX_PATH> executable_path')));
    expect(runner, contains('LoadCustomTrayIcon'));
    expect(runner, contains('LoadImageW('));
    expect(runner, contains('LR_LOADFROMFILE'));
    expect(runner, contains('L"PaperTodo.ico"'));
    expect(runner, contains('L"RePaperTodo.ico"'));
    expect(runner, contains('LoadIcon(GetModuleHandle(nullptr)'));
    expect(runner, contains('Shell_NotifyIcon(NIM_ADD'));
    expect(runner, contains('Shell_NotifyIcon(NIM_SETVERSION'));
    expect(runner, contains('Shell_NotifyIcon(NIM_DELETE'));
    expect(runner, contains('DestroyIcon(tray_icon_handle_)'));
    expect(header, contains('HICON tray_icon_handle_'));
    expect(header, contains('tray_icon_handle_is_custom_'));
    expect(header, contains('taskbar_created_message_'));
  });

  test('Windows native messages tolerate late teardown delivery', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    final fontChangeStart = runner.indexOf('case WM_FONTCHANGE:');
    final fontChangeEnd = runner.indexOf('break;', fontChangeStart);
    expect(fontChangeStart, isNonNegative);
    expect(fontChangeEnd, greaterThan(fontChangeStart));
    final fontChangeBlock = runner.substring(fontChangeStart, fontChangeEnd);

    expect(
      fontChangeBlock,
      contains('if (flutter_controller_ && flutter_controller_->engine())'),
    );
    expect(fontChangeBlock, contains('ReloadSystemFonts();'));
  });

  test('hotkey settings keep forgiving aliases without control characters', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final controller = _readProjectText('lib/src/app_controller.dart');
    final platform =
        _readProjectText('lib/src/platform/platform_services.dart');
    final windowsPlatform =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final appState = _readProjectText('lib/src/core/model/app_state.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(design, contains('Hotkey settings should strip control characters'));
    expect(design, contains('preserving ordinary spaces used by aliases'));
    expect(design, contains('PaperTodo-style capture fields'));
    expect(design, contains('modifier-only'));
    expect(design, contains('Esc`, `Backspace`, and\n`Delete` clear'));
    expect(design, contains('must include at least one real modifier'));
    expect(design, contains('single-key global shortcuts are ignored'));
    expect(design, contains('undo any partial hotkey registration'));
    expect(design, contains("PaperTodo's reveal model"));
    expect(design, contains('do not create new papers'));
    expect(design, contains('dedicated platform path'));
    expect(appState, contains('_normalizeHotKeyForSettings'));
    expect(
      _readProjectText('lib/src/ui/sync_settings_dialog.dart'),
      contains('_handleHotKeyCapture'),
    );
    expect(windowsPlatform, contains('_normalizeHotKeyForPlatform'));
    expect(platform, contains('revealPinnedPaper'));
    expect(windowsPlatform, contains("'revealPinnedPaper'"));
    expect(controller, contains('_platform.paperWindows.revealPinnedPaper'));
    expect(
      appState,
      contains('unit <= 0x1F || (unit >= 0x7F && unit <= 0x9F)'),
    );
    expect(
      windowsPlatform,
      contains('unit <= 0x1F || (unit >= 0x7F && unit <= 0x9F)'),
    );
    expect(runner, contains('bool has_modifier = false'));
    expect(runner, contains('has_modifier = true'));
    expect(runner, contains('return has_modifier && *key != 0'));
    expect(runner, contains('ParsePositiveAsciiInteger'));
    expect(runner, contains('int max_value'));
    expect(runner, contains('(max_value - digit) / 10'));
    expect(
        runner, contains('ParsePositiveAsciiInteger(compact.substr(1), 24)'));
    expect(runner, isNot(contains('std::atoi')));
    expect(runner, contains('"NUMBERPAD"'));
    expect(runner, contains('hotkey_registration_failed'));
    expect(
        runner, contains('todo_hotkey_requested && !todo_hotkey_registered_'));
    expect(runner, contains('reveal-pinned-todo'));
    expect(runner, contains('reveal-pinned-note'));
    expect(runner, contains('method == "revealPinnedPaper"'));
    expect(runner, contains('HWND_TOP'));
    final revealStart = runner.indexOf('if (method == "revealPinnedPaper")');
    final revealEnd = runner.indexOf('if (method == "hide")', revealStart);
    expect(revealStart, isNonNegative);
    expect(revealEnd, greaterThan(revealStart));
    final revealBlock = runner.substring(revealStart, revealEnd);
    expect(revealBlock, contains('HWND_TOP'));
    expect(revealBlock, contains('z_order_state_initialized_ = false'));
    expect(revealBlock, isNot(contains('z_order_state_initialized_ = true')));
    final trayRequestStart =
        runner.indexOf('void FlutterWindow::SendPaperRequested');
    final trayRequestEnd = runner.indexOf(
      'void FlutterWindow::SendPaperDeleteRequested',
      trayRequestStart,
    );
    expect(trayRequestStart, isNonNegative);
    expect(trayRequestEnd, greaterThan(trayRequestStart));
    final trayRequestBlock = runner.substring(trayRequestStart, trayRequestEnd);
    expect(trayRequestBlock, contains('"paperRequested"'));
    expect(trayRequestBlock, contains('flutter::EncodableValue("paperId")'));
    expect(trayRequestBlock, isNot(contains('active_paper_id_ = paper_id')));
    expect(trayRequestBlock, isNot(contains('RememberPaperVisibility')));
  });

  test('Windows fullscreen avoidance uses PaperTodo defensive detection', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final cmake = _readProjectText('windows/runner/CMakeLists.txt');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(design, contains('Task-switcher visibility changes'));
    expect(design, contains('style reads, style writes'));
    expect(runner, contains('bool SetHideFromWindowSwitcher'));
    expect(runner, contains('SetLastError(ERROR_SUCCESS)'));
    expect(runner, contains('GetLastError() != ERROR_SUCCESS'));
    expect(runner, contains('window_switcher_visibility_failed'));
    expect(design, contains('prefer DWM extended frame bounds'));
    expect(design, contains('ignore'));
    expect(design, contains('tool, cloaked, shell, hidden, minimized'));
    expect(design, contains('power-resume broadcasts'));
    expect(design, contains('clear the native z-order cache'));
    expect(
      design,
      contains('foreground-process top-level windows'),
    );
    expect(cmake, contains('dwmapi.lib'));
    expect(runner, contains('#include <dwmapi.h>'));
    expect(runner, contains('g_last_external_foreground_window'));
    expect(runner, contains('kFullscreenTolerance'));
    expect(runner, contains('kFullscreenMinCandidateSize'));
    expect(runner, contains('TryGetDwmWindowBounds'));
    expect(runner, contains('DWMWA_EXTENDED_FRAME_BOUNDS'));
    expect(runner, contains('TryGetRawWindowBounds'));
    expect(runner, contains('DwmGetWindowAttribute(window, DWMWA_CLOAKED'));
    expect(runner, contains('IsToolWindow'));
    expect(runner, contains('WS_EX_TOOLWINDOW'));
    expect(runner, contains('IsShellClassWindow'));
    expect(runner, contains('Shell_TrayWnd'));
    expect(runner, contains('GetShellWindow()'));
    expect(runner, contains('IsCurrentProcessWindow'));
    expect(runner, contains('IsCandidateExternalWindow'));
    expect(
      runner,
      contains('EnumWindows(FindForegroundRelatedFullscreenWindow'),
    );
    expect(runner, contains('ProcessIdForWindow(window)'));
    expect(runner, contains('case WM_DISPLAYCHANGE:'));
    expect(runner, contains('case WM_SETTINGCHANGE:'));
    expect(runner, contains('case WM_POWERBROADCAST:'));
    expect(runner, contains('PBT_APMRESUMEAUTOMATIC'));
    expect(runner, contains('PBT_APMRESUMESUSPEND'));
    expect(runner, contains('PBT_APMRESUMECRITICAL'));
    final powerBroadcastStart = runner.indexOf('case WM_POWERBROADCAST:');
    final powerBroadcastEnd =
        runner.indexOf('case WM_CLOSE:', powerBroadcastStart);
    expect(powerBroadcastStart, isNonNegative);
    expect(powerBroadcastEnd, greaterThan(powerBroadcastStart));
    final powerBroadcastBlock =
        runner.substring(powerBroadcastStart, powerBroadcastEnd);
    expect(
      powerBroadcastBlock,
      contains('z_order_state_initialized_ = false'),
    );
    expect(powerBroadcastBlock, contains('RefreshActivePaperZOrder(hwnd)'));
    expect(powerBroadcastBlock, contains('return TRUE'));
  });

  test('new Windows papers avoid the deep capsule edge strip', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final controller = _readProjectText('lib/src/app_controller.dart');
    final app = _readProjectText('lib/src/app.dart');
    final constants =
        _readProjectText('lib/src/core/model/paper_constants.dart');
    final platform =
        _readProjectText('lib/src/platform/platform_services.dart');
    final windowsPlatform =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(design, contains('open away from the deep capsule edge strip'));
    expect(design, contains('created from an existing paper'));
    expect(design, contains('first-unused-number rule'));
    expect(design, contains('lowest missing positive number'));
    expect(design, contains("100-paper limit"));
    expect(design, contains('collapse-all queue maps'));
    expect(design, contains('canonical `(monitor|side)` entries'));
    expect(design, contains('canonical `false` values'));
    expect(design, contains('fullscreen-app hiding'));
    expect(design, contains('external-window covered-area hiding'));
    expect(design, contains('hideDeepCapsulesWhenFullscreen'));
    expect(design, contains('hideDeepCapsulesWhenCovered'));
    expect(design, contains('Disabling capsule mode'));
    expect(design, contains('can no longer display as a capsule'));
    expect(design, contains('Pinning a paper to the desktop'));
    expect(constants, contains('capsuleWidth = 92.0'));
    expect(constants, contains('deepCapsuleExpandedEdgeInset = 36.0'));
    expect(constants, contains('deepCapsuleGap = 4.0'));
    expect(constants, contains('newPaperBaseLeft = 140.0'));
    expect(constants, contains('newPaperCascadeOffset = 24.0'));
    expect(constants, contains('newPaperSourceOffset = 30.0'));
    expect(constants, contains('newPaperCollisionNudge = 30.0'));
    expect(constants, contains('newPaperWorkAreaResizeInset = 80.0'));
    expect(constants, contains('maxPapers = 100'));
    expect(platform, contains('workAreaForPaper'));
    expect(controller, contains('canCreatePaper'));
    expect(controller, contains('tryCreatePaper'));
    expect(controller, contains('hideDeepCapsulesWhenFullscreen'));
    expect(app, contains('initialHideDeepCapsulesWhenFullscreen'));
    expect(controller, contains('applyCapsuleSettings'));
    expect(controller, contains('_clearDeepCapsuleCollapseAllState'));
    expect(controller, contains('setPaperPinnedToDesktop'));
    expect(controller, contains('setPaperAlwaysOnTop'));
    expect(controller, contains('sourcePaper'));
    expect(controller, contains('_nextTitleNumber'));
    expect(controller, contains('usedNumbers.contains(next)'));
    expect(controller, contains('_initializeNewPaperCapsuleQueue'));
    expect(controller, contains('!_canPaperDisplayAsCapsule(paper)'));
    expect(controller, contains('_rescuePapersIntoWorkAreas'));
    expect(controller, contains('_rescuePaperIntoWorkArea'));
    expect(controller, contains('_clampNewPaperAwayFromDeepCapsuleStrip'));
    expect(controller, contains('_newPaperInitialPosition'));
    expect(controller, contains('workAreaForPaper'));
    expect(app, contains('PaperTodoStringKeys.platformSettingPaperSurfaces'));
    expect(app, contains('controller.applyCurrentStateToPlatform'));
    expect(windowsPlatform, contains("'getWorkArea'"));
    expect(runner, contains('getWorkArea'));
    expect(runner, contains('EnumDisplayMonitors'));
    expect(runner, contains('MONITORINFOEXW'));
    expect(design, contains('Normal startup should restore every'));
    expect(design, contains('Explicit startup exit commands'));
    expect(
        design, contains('Once the Dart controller has started exit cleanup'));
    expect(design, contains('later exit startup commands\nmust be ignored'));
    expect(design, contains('same Dart save/sync-before-exit future'));
    expect(
      design,
      contains('late startup commands, tray paper open/delete\nrequests'),
    );
    expect(
      design,
      contains('cannot hide, delete, or create papers'),
    );
    expect(design, contains('Windows session-ending messages'));
    expect(design, contains('save/sync-before-exit flow'));
    expect(design, contains('guard\nshould be set only after'));
    expect(runner, contains('SendSessionEndingExitRequested'));
    expect(runner, contains('session_ending_exit_requested_'));
    expect(
      runner,
      contains('if (session_ending_exit_requested_ || !window_channel_)'),
    );
    expect(runner, contains('case WM_QUERYENDSESSION:'));
    expect(runner, contains('case WM_ENDSESSION:'));
    expect(runner, contains('SendStartupCommandRequested("exit")'));
    expect(app, contains('Future<void>? _exitCommandFuture;'));
    expect(
      app,
      contains('_exitCommandFuture ??= _runExitStartupCommand(command)'),
    );
    expect(app, contains('Future<void> _runExitStartupCommand'));
    expect(app, contains('if (_exitCommandFuture != null) {\n      return;'));
    expect(
      app,
      contains('if (_exitCommandFuture != null && !paper.isVisible)'),
    );
    expect(controller, contains('bool _isExiting = false;'));
    expect(controller, contains('if (_isExiting)'));
    expect(controller, contains('_isExiting = true;'));
    expect(controller, contains('_restorePapersForStartupSession'));
    final state = _readProjectText('lib/src/core/model/app_state.dart');
    expect(state, contains('_normalizeCollapseAllActiveQueues'));
    expect(state, contains('entry.key == normalizedKey'));
    expect(state, contains('normalized.remove(entry.key)'));
  });

  test('PaperTodo paper hide and last-delete rules are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final controller = _readProjectText('lib/src/app_controller.dart');
    final app = _readProjectText('lib/src/app.dart');

    expect(design,
        contains("Hiding a paper should follow PaperTodo's single-paper"));
    expect(design, contains('Deleting the last remaining paper'));
    expect(design, contains('Surface mode controls'));
    expect(design, contains('rebuild the tray menu'));
    expect(design, contains('Paper deletion should remain available'));
    expect(design, contains('route through Dart deletion'));
    expect(design, contains('interaction-locked like'));
    expect(design, contains('desktop unpin'));
    expect(design, contains('control remains reachable'));
    expect(design, contains('collapsed desktop-pinned paper'));
    expect(design, contains('clearing desktop pinning'));
    expect(controller, contains('..isPinnedToDesktop = false'));
    expect(controller, contains('..isVisible = false'));
    expect(controller, contains('..isCollapsed = false'));
    expect(app, contains('Future<void> _setPaperAlwaysOnTop'));
    expect(app, contains('Future<void> _setPaperPinnedToDesktop'));
    expect(app, contains('desktopInteractionLocked'));
    expect(app, contains('AbsorbPointer'));
    expect(app, contains('_pinnedDesktopUnlockButton'));
    expect(app, contains('paper.isPinnedToDesktop && paper.isCollapsed'));
    expect(app,
        contains('defaultPaper = controller.tryCreatePaper(PaperTypes.todo)'));
    expect(app, contains('await controller.showPaper(createdDefaultPaper)'));
    expect(app, contains('await controller.updatePaperSurface(paper)'));
    expect(app, contains('_handlePaperDeleteRequest'));
    expect(app, contains('_undoDeletePaper'));
  });

  test('PaperTodo runtime custom font convention is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final platform =
        _readProjectText('lib/src/platform/platform_services.dart');
    final windowsPlatform =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final settingsDialog =
        _readProjectText('lib/src/ui/sync_settings_dialog.dart');
    final windowsRunner = _readProjectText('windows/runner/flutter_window.cpp');
    final runtimeFont = _readProjectText('lib/src/ui/runtime_custom_font.dart');

    expect(design, contains('papertodo.ttf'));
    expect(design, contains('papertodo.otf'));
    expect(design, contains('Windows executable directory'));
    expect(design, contains('must not block startup'));
    expect(design, contains('yahei'));
    expect(design, contains('dengxian'));
    expect(design, contains('HKLM\\SOFTWARE\\Microsoft\\Windows NT'));
    expect(design, contains('HKCU\\SOFTWARE\\Microsoft\\Windows NT'));
    expect(design, contains('installed for me'));
    expect(app, contains('PaperTodoRuntimeCustomFontLoader'));
    expect(app, contains('resolveAppFontFamily'));
    expect(app, contains('resolveAppFontFamilyFallback'));
    expect(app, contains('Microsoft YaHei UI'));
    expect(app, contains('DengXian'));
    expect(app, contains('const _paperTodoDengXianAdvanceScale = 12.5 / 13'));
    expect(app, contains('height: widget.lineSpacing / textMetricScale'));
    expect(platform, contains('normalizeInstalledFontFamilies'));
    expect(windowsPlatform, contains('listInstalledFontFamilies'));
    expect(settingsDialog, isNot(contains('value: UiFontPresets.yaHei')));
    expect(settingsDialog, isNot(contains('value: UiFontPresets.dengXian')));
    expect(settingsDialog,
        contains('_uiFontPreset = UiFontPresets.defaultPreset'));
    expect(settingsDialog, contains('RawAutocomplete<String>'));
    expect(settingsDialog, contains('loadInstalledFontFamilies'));
    expect(windowsRunner, contains('InstalledFontFamilies'));
    expect(windowsRunner, contains('AddRegistryFontFamilies'));
    expect(windowsRunner, contains('HKEY_CURRENT_USER'));
    expect(runtimeFont, contains('paperTodoRuntimeCustomFontCandidates'));
    expect(runtimeFont, contains("'papertodo.ttf'"));
    expect(runtimeFont, contains("'papertodo.otf'"));
    expect(runtimeFont, contains('FontLoader(family)'));
    expect(runtimeFont, contains('Invalid or unsupported custom fonts'));
  });

  test('PaperTodo todo column limits are preserved', () {
    final model = _readProjectText('lib/src/core/model/paper_constants.dart');
    final item = _readProjectText('lib/src/core/model/paper_item.dart');
    final app = _readProjectText('lib/src/app.dart');

    expect(model, contains('static const maxCount = 4'));
    expect(model, contains('static const maxWidth = 8.0'));
    expect(item, contains('TodoColumnLimits.maxCount'));
    expect(item, contains('TodoColumnLimits.maxWidth'));
    expect(app, contains('_maxTodoColumnWidth = TodoColumnLimits.maxWidth'));
    expect(app, contains('TodoColumnLimits.maxCount'));
    expect(app, isNot(contains('todoColumnCount < 8')));
  });

  test('PaperTodo todo reminder timing is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final controller = _readProjectText('lib/src/app_controller.dart');

    expect(design, contains('10 minutes before due time'));
    expect(design, contains('2 minutes after due time'));
    expect(design, contains('closest to the current time'));
    expect(design, contains('Deleting a Todo paper should clear active'));
    expect(design, contains('Changing or clearing a todo due date'));
    expect(design, contains('pause their automatic close countdown'));
    expect(design, contains('Opening a Todo reminder should follow'));
    expect(design, contains('desktop-pinned reminder paper'));
    expect(app, contains('_todoReminderLeadTime = Duration(minutes: 10)'));
    expect(app, contains('_todoReminderGraceTime = Duration(minutes: 2)'));
    expect(app, contains('candidate.dueAt.subtract(_todoReminderLeadTime)'));
    expect(app, contains('candidate.dueAt.add(_todoReminderGraceTime)'));
    expect(app, contains('_distanceFromNow'));
    expect(app, contains('_activeTodoReminderItemIds'));
    expect(app, contains('_pauseTodoReminderSnackBarDismissTimer'));
    expect(app, contains('_resumeTodoReminderSnackBarDismissTimer'));
    expect(app, contains('_clearTodoReminderStateForItems'));
    expect(app, contains('_openTodoReminderPaper'));
    expect(app, contains('controller.openReminderPaper'));
    expect(app, contains('onTodoReminderReset'));
    expect(app, contains('widget.onReminderReset(item)'));
    expect(
      app,
      contains(r"String get key => '${item.id}|${item.dueAtLocal ?? ''}'"),
    );
    expect(controller, contains('Future<void> openReminderPaper'));
    expect(controller, contains('paper.isPinnedToDesktop'));
    expect(controller, contains('paperWindows.revealPinnedPaper'));
  });

  test('PaperTodo todo keyboard editing is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('Todo keyboard editing should follow PaperTodo'));
    expect(design, contains('Enter with no modifiers inserts'));
    expect(design, contains("PaperTodo's `AddItemAfter` semantics"));
    expect(design, contains('default single-column'));
    expect(design, contains('every Todo text column'));
    expect(design, contains('first cleaned line replaces'));
    expect(design, contains("last-row\nrebuild focus"));
    expect(design, contains("PaperTodo's `ReplaceSelection`"));
    expect(design, contains('surrounding text remains intact'));
    expect(design, contains('MaxLength = 5000'));
    expect(design, contains('main and extra columns'));
    expect(design, contains('Backspace'));
    expect(design, contains('suppresses repeated'));
    expect(design, contains("previous Todo item's text end"));
    expect(design, contains("next Todo item's text start"));
    expect(app, contains('_handleTodoItemKeyEvent'));
    expect(app, contains('_insertItemAfter'));
    expect(app, contains('extraColumnIndex'));
    expect(app, contains('_TodoPasteTextInputFormatter'));
    expect(app, contains('_TodoTextEdit.betweenValues'));
    expect(app, contains('newItems.last.id'));
    expect(app, contains('LengthLimitingTextInputFormatter'));
    expect(app, contains('TodoPasteItems.maxLineLength'));
    expect(app, contains('PaperItem _newTodoItem({String text = \'\'}'));
    expect(app, contains('_deleteBlankTodoItemFromKeyboard'));
    expect(app, contains('_allTodoTextColumnsBlank'));
    expect(app, contains('_suppressTodoBackspaceUntilKeyUp'));
    expect(app, contains('enum _TodoFocusPlacement { start, end }'));
    expect(app, contains('_placeTodoCaret'));
    expect(app, contains('previousItem == null'));
  });

  test('PaperTodo todo text undo snapshot timing is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains("Todo text editing should follow PaperTodo's"));
    expect(design, contains('focusing a'));
    expect(design, contains('main or extra todo text field records'));
    expect(design, contains('original column text'));
    expect(design, contains('losing focus'));
    expect(design, contains('after a change pushes'));
    expect(design, contains('structural edits first'));
    expect(design, contains('commit any focused text edit'));
    expect(design, contains('text undo or redo history'));
    expect(design, contains('before falling back to structural todo undo'));
    expect(design, contains('uncommitted text edit should keep Ctrl+Z'));
    expect(design, contains('should not\nblock Ctrl+Y'));
    expect(design, contains('Todo snapshot'));
    expect(design, contains('clear active text tracking'));
    expect(design, contains('PaperTodo\nrebuilds the row text boxes'));
    expect(app, contains('_activeOriginalTodoItemId'));
    expect(app, contains('_activeOriginalTodoText'));
    expect(app, contains('_focusedTodoTextUndoStack'));
    expect(app, contains('_focusedTodoTextRedoStack'));
    expect(app, contains('_clearActiveTodoTextTracking'));
    expect(app, contains('_handleFocusedTodoTextShortcut'));
    expect(app, contains('_recordTodoTextInput'));
    expect(app, contains('_handleMainTodoFieldFocusChange'));
    expect(app, contains('_commitFocusedTodoTextIfNeeded'));
    expect(app, contains('_markTodoTextEditCommitted'));
    expect(app, contains('_shouldDeferToTodoTextUndo'));
    expect(app, contains('_focusedTodoTextHasUncommittedEdit'));
    expect(app, contains('return _focusedTodoTextRedoStack.isNotEmpty;'));
    expect(app, contains('_commitFocusedTodoTextIfNeeded();'));
  });

  test('PaperTodo per-column todo editing is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final item = _readProjectText('lib/src/core/model/paper_item.dart');

    expect(design, contains('Todo column editing should preserve PaperTodo'));
    expect(design, contains('before column 1 moves'));
    expect(design, contains('deleting column 1 promotes'));
    expect(design, contains('clicked Todo text column should be focused'));
    expect(design, contains('previously focused column are committed'));
    expect(design, contains('focus should return to that clicked column'));
    expect(app, contains('_columnActionInsertBeforePrefix'));
    expect(app, contains('_columnActionDeletePrefix'));
    expect(app, contains('_focusTodoColumn(item, columnIndex)'));
    expect(app, contains('void _focusTodoColumn'));
    expect(app, contains('requestFocus: false'));
    expect(app, contains('applyFocusChangesIfNeeded'));
    expect(app, contains('_insertTodoColumnBefore'));
    expect(app, contains('_deleteTodoColumn'));
    expect(app, contains('item.todoExtraColumns.insert(0, item.text)'));
    expect(app, contains('item.text = item.todoExtraColumns.first'));
    expect(item, contains("'todoExtraColumns': [...todoExtraColumns]"));
    expect(item, contains("'todoColumnWidths': [...todoColumnWidths]"));
  });

  test('PaperTodo todo column splitter resizing is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('Todo column width resizing should preserve'));
    expect(design, contains('8px drag target'));
    expect(design, contains('resizes only that column pair'));
    expect(design, contains('clamped to at least 0.2'));
    expect(design, contains('at most 8'));
    expect(design, contains('without creating a todo undo snapshot'));
    expect(app, contains('_todoColumnSplitterWidth = 8.0'));
    expect(app, contains('_minTodoColumnWidth = 0.2'));
    expect(app, contains('_maxTodoColumnWidth = TodoColumnLimits.maxWidth'));
    expect(app, contains('_todoColumnSplitter'));
    expect(app, contains('_resizeTodoColumnPair'));
    expect(app, contains('column-splitter-'));
    expect(app, contains('SystemMouseCursors.resizeLeftRight'));
    expect(app, contains('class _TodoColumnSeparatorPainter'));
    expect(app, contains('paperBorder.withValues(alpha: 0.9)'));
    expect(app, contains('Rect.fromLTWH(left, 4, 1, size.height - 8)'));
    expect(app, contains('..isAntiAlias = false'));
    expect(app, contains("fontFamily: 'Segoe UI Symbol'"));
    expect(app, contains('unawaited(widget.onChanged())'));
  });

  test('PaperTodo todo due date time precision is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final paperWindow =
        _readProjectText('windows/runner/paper_flutter_window.cpp');
    final runnerCmake = _readProjectText('windows/runner/CMakeLists.txt');
    final runnerResources = _readProjectText('windows/runner/Runner.rc');
    final resourceHeader = _readProjectText('windows/runner/resource.h');
    final dueDateHelper =
        _readProjectText('lib/src/core/model/todo_due_date.dart');

    expect(design, contains('Todo due editing should preserve PaperTodo'));
    expect(design, contains('PaperTodo-compatible due dates'));
    expect(design, contains('existing Todo due value'));
    expect(design, contains("PaperTodo's due badge"));
    expect(design, contains('existing Todo reminder chip'));
    expect(design, contains('Todo overflow actions should mirror PaperTodo'));
    expect(design, contains('change plus clear actions'));
    expect(design, contains('global reminder interval value and unit'));
    expect(design, contains("PaperTodo's forgiving input"));
    expect(design, contains('values above 240 are clamped to 240'));
    expect(design, contains('00-23 hour'));
    expect(design, contains('00-59 minute'));
    expect(design, contains('yyyy-MM-ddTHH:mm:ss'));
    expect(design, contains('seconds reset to `00`'));
    expect(design, contains('Enter saves through the same OK path'));
    expect(design, contains('Escape cancels'));
    expect(design, contains('focus the interval value field on open'));
    expect(design, contains('select the full value'));
    expect(design, contains('seven-digit fractional-second'));
    expect(design, contains('today is `HH:mm`'));
    expect(design, contains('Tomorrow HH:mm'));
    expect(design, contains('`M/d HH:mm`'));
    expect(design, contains('`yyyy年M/d HH:mm`'));
    expect(design, contains('round the absolute distance up'));
    expect(design, contains('`2h5m`'));
    expect(design, contains('localized future/overdue wrapper'));
    expect(design, contains('`2小时5分`'));
    expect(design, contains('visible countdown text does not go stale'));
    expect(app, contains('_TodoDueSelectionDialog'));
    expect(app, contains("'pickDateTime'"));
    expect(app, contains("'pickReminderInterval'"));
    expect(app, contains('_pickNativeWindowsReminderInterval'));
    expect(app, contains('PaperTodoStringKeys.dialogDueDateMessage'));
    expect(app, contains('PaperTodoStringKeys.reminderIntervalMessage'));
    expect(app, contains('PaperTodoStringKeys.reminderIntervalGlobal'));
    expect(app, contains("'openCalendar': openCalendar"));
    expect(app, contains("'backgroundColor': colorScheme.surface.toARGB32()"));
    expect(paperWindow, contains('DATETIMEPICK_CLASSW'));
    expect(paperWindow, contains('ShowNativeDateTimePicker'));
    expect(paperWindow, contains('ShowNativeReminderIntervalPicker'));
    expect(paperWindow, contains('MulDiv(354'));
    expect(paperWindow, contains('MulDiv(242'));
    expect(paperWindow, contains('MulDiv(326'));
    expect(paperWindow, contains('MulDiv(216'));
    expect(paperWindow, contains('WS_POPUP | WS_CLIPCHILDREN'));
    expect(paperWindow, isNot(contains('WS_POPUP | WS_CAPTION')));
    expect(paperWindow, contains('CreateRoundRectRgn'));
    expect(paperWindow, contains('WC_COMBOBOXW'));
    expect(paperWindow, contains('CBS_DROPDOWNLIST'));
    expect(paperWindow, contains('BS_OWNERDRAW'));
    expect(paperWindow, contains('kDatePickerDateSurfaceId'));
    expect(paperWindow, contains('kDatePickerHourSurfaceId'));
    expect(paperWindow, contains('kDatePickerMinuteSurfaceId'));
    expect(paperWindow, contains('DrawDateTimePickerCalendarIcon'));
    expect(paperWindow, contains('IDB_DATE_PICKER_CALENDAR_LIGHT'));
    expect(paperWindow, contains('LR_CREATEDIBSECTION'));
    expect(
      runnerResources,
      contains('date_picker_calendar_light.bmp'),
    );
    expect(resourceHeader, contains('IDB_DATE_PICKER_CALENDAR_LIGHT'));
    expect(
      File('windows/runner/resources/date_picker_calendar_light.bmp')
          .existsSync(),
      isTrue,
    );
    expect(paperWindow, contains('POINT chevron_points[]'));
    expect(paperWindow, contains('Polygon(draw->hDC, chevron_points'));
    expect(
      paperWindow,
      contains('OffsetRect(&text_bounds, 0, -ScaleForDpi(state->dialog, 3))'),
    );
    expect(paperWindow, contains('old_numeric_character_extra'));
    expect(paperWindow, contains('const int second_line_top'));
    expect(paperWindow, contains('const int first_line_dc = SaveDC(context)'));
    expect(
      paperWindow,
      contains('OffsetRect(&message_bounds, 0, -ScaleForDpi(window, 1))'),
    );
    expect(
      paperWindow,
      contains('OffsetRect(&text_bounds, ScaleForDpi(state->dialog, 1), 0)'),
    );
    expect(
      RegExp(
        r'state->control_font = CreateFontW\([\s\S]*?ANTIALIASED_QUALITY',
      ).hasMatch(paperWindow),
      isTrue,
    );
    expect(paperWindow, contains('RGB(153, 201, 238)'));
    expect(paperWindow, contains('RGB(213, 200, 176)'));
    expect(paperWindow, contains('RECT editor_surface'));
    expect(
      RegExp(
        r'state->button_font = CreateFontW\([\s\S]*?ANTIALIASED_QUALITY',
      ).allMatches(paperWindow).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      RegExp(
        r'OffsetRect\(&text_bounds, 0, ScaleForDpi\(state->dialog, 1\)\)',
      ).allMatches(paperWindow).length,
      greaterThanOrEqualTo(2),
    );
    expect(paperWindow, contains('kReminderIntervalUnitSurfaceId'));
    expect(paperWindow, contains('ReminderIntervalValueSubclassProc'));
    expect(paperWindow, contains('RGB(86, 157, 229)'));
    expect(paperWindow, contains('RGB(149, 193, 220)'));
    expect(paperWindow, contains('scaled(170), scaled(21)'));
    expect(paperWindow, contains('scaled(112), scaled(27)'));
    expect(
      RegExp(r'const int shade = 240').allMatches(paperWindow).length,
      greaterThanOrEqualTo(2),
    );
    expect(paperWindow, contains('value_focused'));
    expect(paperWindow, contains('IsDialogMessageW'));
    expect(paperWindow, contains('kReminderIntervalGlobalId'));
    expect(paperWindow, contains('EM_SETSEL'));
    expect(runnerCmake, contains('comctl32.lib'));
    expect(app, contains('CallbackShortcuts'));
    expect(app, contains('SingleActivator(LogicalKeyboardKey.enter)'));
    expect(app, contains('SingleActivator(LogicalKeyboardKey.escape)'));
    expect(app, contains("debugLabel: 'todo-reminder-interval'"));
    expect(app, contains('_intervalFocusNode.requestFocus()'));
    expect(app, contains('extentOffset: _intervalController.text.length'));
    expect(
      app,
      contains('onPressed: () => unawaited(_pickDueDate(context, item))'),
    );
    expect(app, contains('_pickReminderInterval(context, item)'));
    expect(app, contains("ValueKey('todo-due-hour')"));
    expect(app, contains("ValueKey('todo-due-minute')"));
    expect(app, contains('parsePaperTodoDueAtLocal'));
    expect(app, contains('formatPaperTodoDueAtLocal'));
    expect(app, contains('_formatDueAtLocalValue'));
    expect(app, contains('PaperTodoStringKeys.dueTomorrow'));
    expect(app, contains('Duration.microsecondsPerMinute'));
    expect(app, contains('PaperTodoStringKeys.relativeDueOverdue'));
    expect(app, contains('PaperTodoStringKeys.relativeDueFuture'));
    expect(app, contains('class _HorizontalOverflowClip'));
    expect(app, contains('class _RenderHorizontalOverflowClip'));
    expect(design, contains('clip its right edge at the paper viewport'));
    expect(design, contains('wrapping individual letters vertically'));
    expect(app, contains('now.add(const Duration(hours: 1))'));
    expect(app, contains('_compactTodoActionClearDueDate'));
    expect(app, contains('_compactTodoActionClearReminder'));
    expect(app, contains('_hasDueDate'));
    expect(app, contains('_hasReminderInterval'));
    expect(app, contains('defaultReminderIntervalValue'));
    expect(app, contains('defaultReminderIntervalUnit'));
    expect(app, contains('fallbackValue'));
    expect(app, contains('rawValue <= 0 ? 1 : rawValue'));
    expect(app, contains('shouldRefreshRelativeDueLabels'));
    expect(dueDateHelper, contains('parsePaperTodoDueAtLocal'));
    expect(dueDateHelper, contains('formatPaperTodoDueAtLocal'));
    expect(dueDateHelper, contains(r'\d{1,7}'));
    expect(dueDateHelper, contains('_normalizeIsoFractionForDart'));
    expect(dueDateHelper, contains(r"replaceAll('\u5e74', '-')"));
  });

  test('Windows reminder bubble keeps PaperTodo paper and icon layers', () {
    final app = _readProjectText('lib/src/app.dart');
    final paperWindow =
        _readProjectText('windows/runner/paper_flutter_window.cpp');
    final header = _readProjectText('windows/runner/paper_flutter_window.h');

    expect(app, contains("'borderColor': reminderTint.toARGB32()"));
    expect(app, contains("'borderAlpha': 150"));
    expect(app, contains("'iconBackgroundColor': Color.alphaBlend("));
    expect(app, contains('(isDark ? 48 : 32) / 255'));
    expect(header, contains('reminder_icon_background_color_'));
    expect(header, contains('int reminder_border_alpha_ = 150'));
    expect(paperWindow, contains('CS_DROPSHADOW'));
    expect(paperWindow, contains('WS_EX_LAYERED'));
    expect(paperWindow, contains('ScaleForDpi(reminder_bubble_, 260)'));
    expect(paperWindow, contains('ScaleForDpi(reminder_bubble_, 104)'));
    expect(paperWindow, contains('RoundedRectPixelCoverage'));
    expect(paperWindow, contains('CirclePixelCoverage'));
    expect(paperWindow, contains('const double outer_radius = 15.0'));
    expect(
      paperWindow,
      contains('GetBValue(reminder_icon_background_color_)'),
    );
    expect(
      paperWindow,
      contains('SetTextColor(buffer, reminder_accent_color_)'),
    );
    expect(paperWindow, contains('UpdateLayeredWindow'));
  });

  test('PaperTodo todo reorder data semantics are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('Todo ordering should preserve PaperTodo'));
    expect(design, contains('push a todo undo snapshot'));
    expect(design, contains('orders after every move'));
    expect(design, contains('visible drag handle'));
    expect(design, contains('upper or lower half'));
    expect(design, contains('boundary-based drag placement'));
    expect(app, contains('_moveTodoItem'));
    expect(app, contains('_reorderTodoItemToTarget'));
    expect(app, contains('_todoReorderDropTarget'));
    expect(app, contains('_dropAfterTodoTarget'));
    expect(app, contains('globalToLocal'));
    expect(app, contains('Draggable<PaperItem>'));
    expect(app, contains('DragTarget<PaperItem>'));
    expect(app, contains('_canAcceptTodoItemDrop'));
    expect(app, isNot(contains('ReorderableListView.builder')));
    expect(app, isNot(contains('ReorderableDragStartListener')));
    expect(app, contains('_compactTodoActionMoveUp'));
    expect(app, contains('_compactTodoActionMoveDown'));
    expect(app, contains('PaperTodoStringKeys.actionMoveItemUp'));
    expect(app, contains('PaperTodoStringKeys.actionMoveItemDown'));
    expect(app, contains('PaperTodoStringKeys.actionDragToReorder'));
    expect(app, contains('_requestTodoItemFocus(item.id)'));
  });

  test('PaperTodo drag-to-delete todo item path is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final widgetTest = _readProjectText('test/widget_test.dart');

    expect(design, contains('Dragging a Todo row handle'));
    expect(design, contains('bottom delete area'));
    expect(design, contains('PaperTodo tombstones'));
    expect(app, contains('_todoDeleteDropTarget'));
    expect(app,
        contains("ValueKey('\${widget.paper.id}-todo-delete-drop-target')"));
    expect(app, contains("ValueKey('\${widget.paper.id}-todo-trash-area')"));
    expect(app, contains('paperColors.danger.withValues'));
    expect(app, contains('width: highlighted ? 1.5 : 1'));
    expect(app, contains('opacity: highlighted ? 1 : 0.65'));
    expect(app, contains('_setTodoItemDragging(false);'));
    expect(app, contains('_deleteItem(context, details.data)'));
    expect(widgetTest,
        contains('drags todo items to the bottom delete area like PaperTodo'));
    expect(widgetTest, contains('trashColors.danger.withValues'));
  });

  test('PaperTodo todo completion and due visual metrics are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final widgetTest = _readProjectText('test/widget_test.dart');

    expect(design, contains('Completed rows animate to 0.75'));
    expect(design, contains('1.35px BrightWeakText rule'));
    expect(design, contains('due urgency begins ten minutes'));
    expect(app, contains('opacity: dragging ? 0.25 : (item.done ? 0.75 : 1)'));
    expect(app, contains('class _TodoCompletionLinePainter'));
    expect(app, contains('final double strokeWidth = 1.35'));
    expect(app, contains('difference <= const Duration(minutes: 10)'));
    expect(app, contains('padding: const EdgeInsets.only(left: 1)'));
    expect(app, contains('class _PaperTodoTodoCheckBox'));
    expect(app, contains('dimension: 16'));
    expect(app, contains('static const double borderWidth = 1.5'));
    expect(app, contains('static const double radius = 4'));
    expect(app, contains('moveTo(3 * scaleX, 7.5 * scaleY)'));
    expect(app, contains('lineTo(6.5 * scaleX, 11 * scaleY)'));
    expect(app, contains('lineTo(13 * scaleX, 4 * scaleY)'));
    expect(app, contains(r"'\u2261'"));
    expect(app, contains('opacity: dragging ? 0.9 : (hovered ? 0.78 : 0.48)'));
    expect(app, contains('opacity: dragging ? 0.25'));
    expect(app, contains('SizeChangedLayoutNotifier'));
    expect(app, contains('firstLine.end < item.text.length'));
    expect(widgetTest,
        contains('todo due badges match PaperTodo timing and visual metrics'));
    expect(
        widgetTest, contains('all Todo visual size metrics match PaperTodo'));
    expect(
        widgetTest,
        contains(
            'linked note button matches PaperTodo metrics and pointer states'));
    expect(
        widgetTest,
        contains(
            'auto-wrapped todo text switches linked note multiline metrics'));
  });

  test('PaperTodo individual todo delete semantics are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(
        design, contains('Deleting an individual Todo item should preserve'));
    expect(design, contains("PaperTodo's `RemoveItem`"));
    expect(design, contains('last remaining row'));
    expect(design, contains('creates a blank fallback row'));
    expect(design, contains('snackbar undo'));
    expect(app, contains('_deleteItem'));
    expect(app, contains('final replacement = _newTodoItem()'));
    expect(app, contains('fallbackItemId = replacement.id'));
    expect(app, contains('candidate.id == fallbackItemId'));
    expect(app, contains('_requestTodoItemFocus(focusTargetId)'));
    expect(app, contains('onPressed: () => _deleteItem(context, item)'));
    expect(app, isNot(contains('enabled: widget.paper.items.length > 1')));
  });

  test('PaperTodo clear completed todo items is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('Clearing completed Todo items should preserve'));
    expect(design, contains('push one todo undo snapshot'));
    expect(design, contains('create a blank fallback row'));
    expect(design, contains('deleted-item tombstones'));
    expect(design, contains('first'));
    expect(design, contains('nonblank remaining row'));
    expect(app, contains('_compactTodoActionClearDone'));
    expect(app, contains('PaperTodoStringKeys.actionClearCompleted'));
    expect(app, contains('PaperTodoStringKeys.actionClearCompletedItems'));
    expect(app, contains('_clearDoneItems'));
    expect(app, contains('completedItems.isEmpty'));
    expect(app, contains('remainingItems.add(_newTodoItem())'));
    expect(app, contains('widget.onItemDeleted(widget.paper, item)'));
    expect(app, contains('_requestTodoItemFocus(focusTargetId)'));
  });

  test('PaperTodo context menu section headers are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final strings = _readProjectText('lib/src/ui/papertodo_strings.dart');

    expect(design, contains('disabled section headers'));
    expect(design, contains('New, Todo, Canvas, Desktop pin, Format, Text'));
    expect(design, contains("PaperTodo's capsule wording"));
    expect(design, contains('Collapse to capsule'));
    expect(design, contains('Restore\nwindow'));
    expect(design, contains("PaperTodo's precise wording"));
    expect(design, contains('Hide this paper'));
    expect(design, contains('Open in default `{extension}` editor'));
    expect(design, contains('top-bar external-open setting'));
    expect(design, contains('only shows on Note paper surfaces'));
    expect(design, contains('first two uppercase characters'));
    expect(design, contains('current Note\neditor text'));
    expect(design, contains('persistence debounce'));
    expect(app, contains('_paperTodoMenuHeader'));
    expect(app, contains('_CompactAppBarActions.openMarkdown'));
    expect(app, contains('_externalMarkdownButtonLabel'));
    expect(app, contains('currentSurfacePaper.isNote'));
    expect(app, contains('_openNoteMarkdownExternally(currentSurfacePaper)'));
    expect(app, contains('PaperTodoStringKeys.menuNew'));
    expect(app, contains('PaperTodoStringKeys.menuTodo'));
    expect(app, contains('PaperTodoStringKeys.menuCanvas'));
    expect(app, contains('PaperTodoStringKeys.menuDesktopPin'));
    expect(app, contains('PaperTodoStringKeys.menuFormat'));
    expect(app, contains('PaperTodoStringKeys.menuText'));
    expect(app, contains('PaperTodoStringKeys.menuTodoItem'));
    expect(app, contains('PaperTodoStringKeys.actionCollapseToCapsule'));
    expect(app, contains('PaperTodoStringKeys.actionRestoreWindow'));
    expect(app, contains('PaperTodoStringKeys.actionHideThisPaper'));
    expect(
      app,
      contains('PaperTodoStringKeys.actionOpenMarkdownInDefaultEditor'),
    );
    expect(
      app,
      contains('externalMarkdownExtension: '
          'controller.state.externalMarkdownExtension'),
    );
    expect(strings, contains("PaperTodoStringKeys.menuNew: 'New'"));
    expect(strings, contains("PaperTodoStringKeys.menuNew: '新建'"));
    expect(strings,
        contains("PaperTodoStringKeys.actionCollapseToCapsule: '折叠为胶囊'"));
    expect(
        strings, contains("PaperTodoStringKeys.actionRestoreWindow: '恢复窗口'"));
    expect(
        strings, contains("PaperTodoStringKeys.actionHideThisPaper: '隐藏这张纸'"));
    expect(strings,
        contains("PaperTodoStringKeys.actionHideThisPaper: 'Hide this paper'"));
    expect(
      strings,
      contains(
        "PaperTodoStringKeys.actionOpenMarkdownInDefaultEditor:\n"
        "      'Open in default {0} editor'",
      ),
    );
    expect(
      strings,
      contains(
        "PaperTodoStringKeys.actionOpenMarkdownInDefaultEditor: "
        "'用默认 {0} 编辑器打开'",
      ),
    );
    expect(
        strings,
        contains(
            "PaperTodoStringKeys.topBarOpenSurface: 'Show external open button'"));
    expect(
        strings, contains("PaperTodoStringKeys.topBarOpenSurface: '显示外部打开按钮'"));
  });

  test('Todo compact item actions use phone form factor and paper width', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('Todo compact item actions should switch'));
    expect(design, contains('current paper/editor width'));
    expect(app, contains('final availableWidth = constraints.hasBoundedWidth'));
    expect(app, contains('final useCompactItemActions ='));
    expect(app, contains('MediaQuery.sizeOf(context).shortestSide < 600 ||'));
    expect(app, contains('availableWidth < 600'));
    expect(app, contains('PaperTodoStringKeys.actionTodoItemActions'));
  });

  test('PaperTodo todo note link semantics are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final controller = _readProjectText('lib/src/app_controller.dart');

    expect(design, contains('Todo-note linking should preserve'));
    expect(design, contains('source Todo paper as an anchor'));
    expect(design, contains('fall back to the left side'));
    expect(design, contains('Note-to-Todo drag linking should preserve'));
    expect(design, contains('linking the same note'));
    expect(design, contains('unlinking is a no-op'));
    expect(design, contains('remain available from Todo item menus'));
    expect(design, contains('dedicated link drag handle'));
    expect(design, contains('candidate rows highlight'));
    expect(app, contains('_compactTodoActionOpenLinkedNote'));
    expect(app, contains('_compactTodoActionUnlinkNote'));
    expect(app, contains('_todoLinkActionUnlink'));
    expect(app, contains('_noteLinkDragHandle'));
    expect(app, contains("ValueKey('\${paper.id}-note-link-drag-handle')"));
    expect(app, contains('DragTarget<String>'));
    expect(app, contains('_noteLinkDropTarget'));
    expect(app, contains('_canAcceptNoteLinkDrop'));
    expect(app, contains('_openLinkedNote'));
    expect(app, contains('controller.openLinkedNote'));
    expect(app, contains('onOpenLinkedNote'));
    expect(app, contains('_notePaperById'));
    expect(app, contains('item.linkedNoteId == noteId'));
    expect(app, contains('_requestTodoItemFocus(focusTargetId)'));
    expect(controller, contains('Future<void> openLinkedNote'));
    expect(controller, contains('_placeLinkedNoteBesideAnchor'));
    expect(controller, contains('rightX <= maxX'));
    expect(controller, contains('leftX >= minX'));
  });

  test('PaperTodo markdown note link interaction is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final inlineHtml =
        _readProjectText('lib/src/core/model/markdown_inline_html.dart');
    final markdownLinkTargets =
        _readProjectText('lib/src/core/model/markdown_link_targets.dart');
    final externalUriTargets =
        _readProjectText('lib/src/core/model/external_uri_targets.dart');
    final markdownLinks =
        _readProjectText('lib/src/core/model/markdown_links.dart');
    final markdownSource =
        _readProjectText('lib/src/ui/papertodo_markdown_source.dart');

    expect(design, contains('Markdown note link interaction should preserve'));
    expect(design, contains('preview-mode links open directly'));
    expect(design, contains('edit-mode source links open'));
    expect(design, contains('Ctrl+click'));
    expect(design, contains('single-line inline HTML `a href` links'));
    expect(design, contains('Inline HTML anchor parsing should follow'));
    expect(design, contains('well-formed `name=value` pairs'));
    expect(design, contains('quoted attribute values may contain `>`'));
    expect(design, contains('empty anchor bodies'));
    expect(design, contains('Inline HTML preview rendering should preserve'));
    expect(design, contains('`b`, `strong`, `i`, `em`, `s`, `del`, `u`'));
    expect(design, contains('arbitrary tags'));
    expect(design, contains("bare-host convenience"));
    expect(design, contains('links beginning with `www.`'));
    expect(design, contains('Markdown local path links should preserve'));
    expect(design, contains('drive/UNC paths'));
    expect(design, contains('Android POSIX absolute paths'));
    expect(design, contains('and `file:` targets'));
    expect(design, contains('query or fragment components'));
    expect(design, contains('device paths'));
    expect(design, contains('control characters after URI decoding'));
    expect(design, contains('percent-encoded newlines or C1 controls'));
    expect(markdownLinkTargets, contains('uri.toFilePath'));
    expect(
      markdownLinkTargets,
      contains('if (trimmed.isEmpty || _hasControlCharacter(trimmed))'),
    );
    expect(design, contains('closed inline code spans'));
    expect(design, contains('CRLF/LF/standalone CR line boundaries'));
    expect(design, contains('Markdown image syntax should follow'));
    expect(design, contains('treated as a source'));
    expect(design, contains('link hit target'));
    expect(design, contains('PaperTodo-scoped source renderer'));
    expect(design, contains('Basic mode keeps source'));
    expect(design, contains('Enhanced preview fades syntax'));
    expect(design, contains('redraws list bullets/numbers'));
    expect(design, contains('source-like images/tables'));
    expect(design, contains('active IME composing ranges'));
    expect(design, contains('track its scroll offset'));
    expect(design, contains('Markdown source link scanning'));
    expect(design, contains('first literal `](`'));
    expect(design, contains('backslash'));
    expect(design, contains('CommonMark angle destinations'));
    expect(design, contains('only `http`, `https`, `mailto`, `www.`'));
    expect(design, contains('Markdown line classification'));
    expect(design, contains('PaperTodo-compatible model'));
    expect(design, contains('fenced code block detection'));
    expect(design, contains('standalone CR'));
    expect(design, contains("PaperTodo's English fallback label"));
    expect(design, contains('`Link`'));
    expect(design, contains('focus-driven reading flow'));
    expect(design, contains('open in preview mode by default'));
    expect(design, contains('clicking the preview body enters'));
    expect(design, contains('losing editor focus returns'));
    expect(design, contains('Markdown editors should accept Tab'));
    expect(design, contains('Shift+Tab outdents'));
    expect(design, contains('editor context menu must not trigger'));
    expect(design, contains('remain in source-edit mode'));
    expect(design, contains('Ctrl+mouse-wheel'));
    expect(design, contains('0.1 steps between 0.5 and 1.5'));
    expect(design, contains('visible note zoom status'));
    expect(design, contains('clicking the status resets'));
    expect(app, contains('_handleEditorTap'));
    expect(app, contains('_enterEditorFromPreview'));
    expect(app, contains('_handleEditorFocusChange'));
    expect(app, contains('_toolbarInteractionActive'));
    expect(app, contains('_beginToolbarInteraction'));
    expect(app, contains('_endToolbarInteraction'));
    expect(app, contains('HardwareKeyboard.instance.isControlPressed'));
    expect(app, contains('LogicalKeyboardKey.tab'));
    expect(app, contains('MarkdownFormatting.handleTab'));
    expect(app, contains('PointerScrollEvent'));
    expect(app, contains('pointerSignalResolver'));
    expect(app, contains('_textZoomAfterWheel'));
    expect(app, contains('_noteZoomStatus'));
    expect(app, contains('_resetTextZoom'));
    expect(app, contains('PaperTodoStringKeys.actionResetTextZoom'));
    expect(app, contains('widget.onTextZoomChanged(1)'));
    expect(app, contains('PaperTodoMarkdownSourcePreview'));
    expect(app, contains('PaperTodoMarkdownTextEditingController'));
    expect(app, contains('PaperTodoMarkdownEditorBackgroundPainter'));
    expect(app, contains("'markdown-editor-block-background'"));
    expect(markdownSource, contains('class PaperTodoMarkdownSourcePreview'));
    expect(markdownSource,
        contains('class PaperTodoMarkdownTextEditingController'));
    expect(markdownSource,
        contains('class PaperTodoMarkdownEditorBackgroundPainter'));
    expect(markdownSource, contains('hasActiveComposing'));
    expect(markdownSource, contains('Colors.transparent'));
    expect(
        markdownSource, contains("'papertodo-markdown-list-marker-\$index'"));
    expect(markdownSource,
        contains('const _paperTodoHiddenListMarkerFontSize = 12.0'));
    expect(
        markdownSource, contains('final centerY = markerPainter.height / 2'));
    expect(markdownSource, contains('scrollController.offset'));
    expect(externalUriTargets, contains("startsWith('www.')"));
    expect(app, contains('_normalizeMarkdownLocalPath'));
    expect(app, contains('controller.openExternalFile(localPath)'));
    expect(app, contains('normalizeMarkdownLocalPathTarget'));
    expect(app, contains('MarkdownLinks.hrefAt'));
    expect(markdownLinkTargets, contains('normalizeMarkdownLocalPathTarget'));
    expect(markdownLinkTargets, contains('p.Style.windows'));
    expect(markdownLinkTargets, contains('p.Style.posix'));
    expect(markdownLinkTargets, contains('uri.hasQuery || uri.hasFragment'));
    expect(markdownLinkTargets, contains('_isUnsafeDevicePath'));
    expect(markdownLinkTargets, contains('_isPosixAbsolutePath'));
    expect(markdownLinks, contains('class MarkdownLinkSpan'));
    expect(markdownLinks, contains('_htmlAnchorLinks'));
    expect(markdownLinks, contains('_tryParseHtmlOpeningAnchor'));
    expect(markdownLinks, contains('_tryGetHtmlHrefAttribute'));
    expect(markdownLinks, contains('normalizeExternalUriTarget'));
    expect(markdownLinks, contains('allowBareWww: true'));
    expect(markdownLinks, contains('_closedInlineCodeSpans'));
    expect(markdownLinks, contains("indexOf(']('"));
    expect(markdownLinks, contains('normalizeMarkdownLocalPathTarget'));
    expect(inlineHtml, contains('class PaperTodoMarkdownInlineHtmlSyntax'));
    expect(inlineHtml, contains("'b' || 'strong'"));
    expect(inlineHtml, contains("'i' || 'em'"));
    expect(inlineHtml, contains("'s' || 'del'"));
    expect(inlineHtml, contains("'u' => md.Element.text('u'"));
    expect(inlineHtml, contains("'strong',"));
    expect(inlineHtml, contains("'em',"));
    expect(inlineHtml, contains("'del',"));
    expect(inlineHtml, contains("md.Element.text('code'"));
    expect(inlineHtml, contains("md.Element('a'"));
    expect(
      _readProjectText('lib/src/core/model/markdown_line_analysis.dart'),
      contains('enum MarkdownLineKind'),
    );
    expect(
      _readProjectText('lib/src/core/model/markdown_list_continuation.dart'),
      contains('MarkdownLineAnalysis.analyzeLine'),
    );
    expect(
      _readProjectText('lib/src/core/model/markdown_formatting.dart'),
      contains("defaultLinkLabel = 'Link'"),
    );
    expect(
      _readProjectText('lib/src/core/model/markdown_formatting.dart'),
      contains("tabIndent = '\\t'"),
    );
  });

  test('PaperTodo markdown note paste safety is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final markdownPaste =
        _readProjectText('lib/src/core/model/markdown_paste.dart');

    expect(design, contains('Markdown note paste safety should preserve'));
    expect(design, contains('100000 characters'));
    expect(design, contains('30000 characters'));
    expect(design, contains('CR/LF line endings are preserved'));
    expect(design, contains('longer than 6000 characters'));
    expect(app, contains('MarkdownPasteText.formatEditUpdate'));
    expect(markdownPaste, contains('maxTextLength = 100000'));
    expect(markdownPaste, contains('formatEditUpdate'));
    expect(markdownPaste, contains('_TextEditDiff.between'));
    expect(markdownPaste, contains('_clipPasteText'));
    expect(markdownPaste, contains('_containsLineLongerThan'));
  });

  test('PaperTodo markdown ordered list continuation is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final listContinuation =
        _readProjectText('lib/src/core/model/markdown_list_continuation.dart');

    expect(design, contains('Markdown list continuation should preserve'));
    expect(design, contains('leading zero markers'));
    expect(design, contains('long.MaxValue - 1'));
    expect(design, contains('ordinary Enter behavior'));
    expect(design, contains('existing CRLF/LF document line delimiters'));
    expect(
      listContinuation,
      contains('_maxContinuableOrderedListNumber = 9223372036854775806'),
    );
    expect(listContinuation, contains('markerEnd'));
    expect(listContinuation, contains('_firstLineDelimiter'));
  });

  test('PaperTodo note canvas geometry gestures are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('Note canvas element geometry should preserve'));
    expect(design, contains('dragging the element header moves the block'));
    expect(design, contains('bottom-right grip'));
    expect(design, contains('72x48'));
    expect(design, contains('Pinned'));
    expect(design, contains('ignore canvas move, resize, and add-block'));
    expect(design, contains('edit, duplicate, layer, delete, and text-edit'));
    expect(app, contains('note-canvas-drag-handle-'));
    expect(app, contains('note-canvas-resize-handle-'));
    expect(app, contains('geometryGesturesEnabled'));
    expect(app, contains('!widget.paper.isPinnedToDesktop'));
    expect(app, contains('if (widget.paper.isPinnedToDesktop)'));
    expect(app, contains('_moveElement'));
    expect(app, contains('_resizeElement'));
    expect(app, contains('clamp(72, maxWidth)'));
    expect(app, contains('clamp(48, maxHeight)'));
  });

  test('PaperTodo note status and canvas chrome metrics are preserved', () {
    final app = _readProjectText('lib/src/app.dart');

    expect(app, contains("ValueKey('note-canvas-toolbar')"));
    expect(app, contains('constraints: const BoxConstraints(minHeight: 31)'));
    expect(app, contains("ValueKey('note-add-canvas-block')"));
    expect(app, contains("ValueKey('note-add-canvas-block-surface')"));
    expect(app, contains('width: 28'));
    expect(app, contains('height: 24'));
    expect(app, contains('fontSize: 13'));
    expect(
        app,
        contains(
            'opacity: enabled ? (_canvasAddButtonPressed ? 0.7 : 1) : 0.72'));
    expect(app, contains('maxLines: 1'));
    expect(app, contains('fit: BoxFit.scaleDown'));
    expect(app, contains("ValueKey('note-status-mode-pill')"));
    expect(app, contains('constraints: const BoxConstraints(minWidth: 42)'));
    expect(app, contains("ValueKey('note-status-zoom')"));
    expect(app, contains('width: 38'));
    expect(app, contains("ValueKey('note-text-zoom-overlay')"));
    expect(app, contains("(widget.textZoom - 1).abs() < 0.001"));
    expect(app, contains('right: 12'));
    expect(app, contains('bottom: 7'));
    expect(app, contains('opacity: _zoomOverlayHovered ? 1 : 0.55'));
    expect(app, contains('fontSize: 10.5'));
    expect(app, contains('EdgeInsets.fromLTRB(26, 12, 14, 12)'));
    expect(app, contains('alpha: isDark ? 88 / 255 : 104 / 255'));
    expect(app, contains('alpha: isDark ? 34 / 255 : 28 / 255'));
    expect(app, contains("ValueKey('note-preview-scroll')"));
    expect(app, contains('padding: EdgeInsets.zero'));
    expect(app, isNot(contains('final compactContent =')));
    expect(app, isNot(contains('final compactHeader =')));
    expect(app, contains('fontSize: (isCode ? 13 : 14) * widget.scale'));
    expect(app, contains('fontFamily: _paperTodoCodeFontFamily'));
    expect(app, contains('PaperTodoTypography.of(context).contentStyle'));
    expect(app, contains("const _paperTodoCodeFontFamily = 'Cascadia Mono'"));
    expect(app, contains("'Consolas'"));
    expect(app, contains('final emphasized = widget.isSelected || isTopLayer'));
    expect(app, contains(': const []'));
    expect(app, contains('alpha: isDark ? 0.22 : 0.13'));
    expect(app, contains('blurRadius: 6'));
    expect(app, contains('final shadowAxis = 2 / math.sqrt(2)'));
    expect(app, contains('offset: Offset(shadowAxis, shadowAxis)'));
    expect(app,
        contains('final origin = embedded ? const Offset(2, 1) : Offset.zero'));
    expect(app,
        contains("String _noteCanvasElementTypeLabel(String type) => 'CODE';"));
    expect(app, contains("return '顶层 \$layerRank';"));
    expect(app, contains("return '层 \$layerRank';"));
  });

  test('PaperTodo note canvas placement and layer rules are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final constants =
        _readProjectText('lib/src/core/model/paper_constants.dart');

    expect(design, contains('New note canvas blocks should follow'));
    expect(design, contains('only code blocks can be created'));
    expect(design, contains('legacy text or sticky block types'));
    expect(design, contains('230x116'));
    expect(design, contains('28px origin'));
    expect(design, contains('12px cascade'));
    expect(design, contains('top z-index plus 10'));
    expect(design, contains('duplicates offset by 18px'));
    expect(design, contains('one-step layer moves swap z-indexes'));
    expect(design, contains('duplicate z-indexes'));
    expect(design, contains('current render rank'));
    expect(design, contains('Note canvas code block editors'));
    expect(design, contains('Shift+Tab outdents'));
    expect(constants, contains('static const code = \'code\''));
    expect(constants, isNot(contains('static const text')));
    expect(app, isNot(contains('actionAddTextBlock')));
    expect(app, contains('_nextNoteCanvasElementPoint'));
    expect(app, contains('math.min(80.0, existingCount * 12.0)'));
    expect(app, contains('math.max(220.0, widget.paper.width - 40)'));
    expect(app, contains('_maxCanvasElementLayer(elements)'));
    expect(app, contains('_minCanvasElementLayer(elements)'));
    expect(app, contains('_renumberDuplicateCanvasLayers'));
    expect(app, contains('element.zIndex = maxLayer + 10'));
    expect(app, contains('element.zIndex = minLayer - 10'));
    expect(app, contains('_handleCanvasTextKeyEvent'));
    expect(app, contains('_commitCanvasText'));
  });

  test('Windows runner preserves external URI safety checks', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final app = _readProjectText('lib/src/app.dart');
    final externalUriTargets =
        _readProjectText('lib/src/core/model/external_uri_targets.dart');

    expect(app, contains('normalizeExternalUriTarget'));
    expect(externalUriTargets, contains('hasUnsafeExternalUriCharacter'));
    expect(
        externalUriTargets, contains('hasEncodedUnsafeExternalUriCharacter'));
    expect(
        externalUriTargets, contains('hasMalformedExternalUriPercentEscape'));
    expect(externalUriTargets, contains('uri.userInfo.isEmpty'));
    expect(
      externalUriTargets,
      contains('hasEncodedExternalUriAuthoritySeparator'),
    );
    expect(
      _readProjectText('docs/DESIGN_SYSTEM.md'),
      contains('malformed UTF-8'),
    );
    expect(runner, contains('IsAllowedExternalUri'));
    expect(runner, contains('Utf8ToWideStrict(path)'));
    expect(runner, contains('Utf8ToWideStrict(uri)'));
    expect(runner, contains('not valid UTF-8'));
    expect(runner, contains('HasRawExternalUriControlCharacter'));
    expect(runner, contains('HasEncodedUnsafeExternalUriCharacter'));
    expect(runner, contains('HasMalformedExternalUriPercentEscape'));
    expect(runner, contains('HasEncodedExternalUriAuthoritySeparator'));
    expect(runner, contains('ascii <= 0x20'));
    expect(runner, contains("authority.find('@')"));
    expect(runner, contains('authority_host'));
    expect(runner, contains("authority.front() == '['"));
    expect(runner, contains('scheme == "mailto"'));
    expect(runner, contains('const std::string recipient = TrimAscii'));
    expect(runner, contains('StartsWith(recipient, "?")'));
    expect(runner, contains('StartsWith(recipient, "//")'));
    expect(runner, contains('scheme != "http" && scheme != "https"'));
    expect(runner, contains('ShellExecuteW'));
    final windowsOpenUriStart = runner.indexOf('if (method == "openUri")');
    final windowsTrimStart =
        runner.indexOf('uri = TrimAscii(uri);', windowsOpenUriStart);
    final windowsRawCheckStart = runner.indexOf(
      'HasRawExternalUriControlCharacter(uri)',
      windowsOpenUriStart,
    );
    expect(windowsOpenUriStart, isNonNegative);
    expect(windowsRawCheckStart, greaterThan(windowsOpenUriStart));
    expect(windowsTrimStart, greaterThan(windowsOpenUriStart));
    expect(windowsRawCheckStart, lessThan(windowsTrimStart));
  });

  test('Windows tray menu keeps PaperTodo action labels', () {
    final app = _readProjectText('lib/src/app.dart');
    final platform =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final header = _readProjectText('windows/runner/flutter_window.h');

    expect(header, contains('std::wstring new_todo = L"+ New todo paper"'));
    expect(header, contains('std::wstring new_note = L"+ New note paper"'));
    expect(header, contains('std::wstring show_all = L"Show all papers"'));
    expect(header, contains('std::wstring hide_all = L"Hide all papers"'));
    expect(header, contains('std::wstring toggle_all = L"Toggle all papers"'));
    expect(
        runner, contains('append_owner_draw(menu.get(), 0, AppDisplayName()'));
    expect(runner, contains('TrayMenuLabelsFromMap'));
    expect(runner, contains('kTrayNewTodoCommand, tray_labels_.new_todo'));
    expect(runner, contains('kTrayNewNoteCommand, tray_labels_.new_note'));
    expect(runner, contains('kTrayShowCommand, tray_labels_.show_all'));
    expect(runner, contains('kTrayHideCommand, tray_labels_.hide_all'));
    expect(runner, contains('kTrayToggleCommand, tray_labels_.toggle_all'));
    expect(runner, contains('tray_labels_.inline_confirm_delete'));
    expect(runner, contains('tray_labels_.inline_confirm_action,'));
    expect(runner, contains('tray_labels_.cancel,'));
    expect(platform, contains("'labels': labels.toJson()"));
    expect(platform,
        contains("'trayLabel': _trayPaperLabel(paper, title, labels)"));
    expect(app, contains('PaperTodoStringKeys.trayNewTodo'));
    expect(app, contains('PaperTodoStringKeys.trayInlineConfirmDelete'));
    expect(app, contains('PaperTodoStringKeys.trayInlineConfirmAction'));
    expect(app, contains('_trayMenuLabelsFor'));
    expect(runner, contains('SendStartupCommandRequested("new-todo");'));
    expect(runner, contains('SendStartupCommandRequested("new-note");'));
    expect(runner, contains('SendStartupCommandRequested("show");'));
    expect(runner, contains('SendStartupCommandRequested("hide");'));
    expect(runner, contains('SendStartupCommandRequested("toggle");'));
  });

  test('Windows tray menu follows PaperTodo owner-drawn metrics and theme', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final header = _readProjectText('windows/runner/flutter_window.h');

    expect(header, contains('enum class TrayOwnerDrawKind'));
    expect(header, contains('std::vector<std::unique_ptr<TrayOwnerDrawItem>>'));
    expect(runner, contains('MFT_OWNERDRAW'));
    expect(runner, contains('case WM_MEASUREITEM:'));
    expect(runner, contains('case WM_DRAWITEM:'));
    expect(runner, contains('constexpr int kTrayMenuMinimumWidth = 190'));
    expect(runner, contains('kTrayMenuNativeWidthCompensation = 21'));
    expect(runner, contains('constexpr int kTrayMenuItemHeight = 24'));
    expect(runner, contains('constexpr int kTrayMenuHeaderHeight = 22'));
    expect(runner, contains('constexpr int kTrayMenuItemRadius = 8'));
    expect(runner, contains('constexpr int kTrayMenuShellRadius = 10'));
    expect(runner, contains('constexpr int kTrayMenuCheckboxSize = 13'));
    expect(runner, contains('header ? 11 : 12'));
    expect(runner, contains('MixTrayColor(palette.paper, palette.weak, 0.72)'));
    expect(runner, contains('L"\\u270E"'));
    expect(runner, contains('L"\\u26A1"'));
    expect(runner, contains('item->paper_type == "script" ? 15 : 14'));
    expect(runner, contains('ANTIALIASED_QUALITY'));
    expect(
        runner, contains('MixTrayColor(palette.paper, palette.active, 0.92)'));
    expect(runner, contains('GetWindowRgn(window, current_region)'));
    expect(runner, contains('!IsWindowVisible(window)'));
    expect(runner, contains('std::atomic_bool keep_styling_menu'));
    expect(runner, contains('chrome_thread.join()'));
    expect(runner, contains('GetStringArgument(*state, "theme", theme)'));
    expect(
        runner, contains('GetStringArgument(*state, "colorScheme", scheme)'));
    expect(
      runner,
      contains('GetStringArgument(*state, "customThemeColorHex", "")'),
    );
    expect(runner, contains('ApplyTrayMenuWindowChrome'));
    expect(runner, contains('CreateRoundRectRgn'));
    expect(runner, contains('L"#32768"'));
  });

  test('Windows custom theme color uses the native PaperTodo picker', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final cmake = _readProjectText('windows/runner/CMakeLists.txt');
    final settings = _readProjectText('lib/src/ui/sync_settings_dialog.dart');

    expect(runner, contains('if (method == "chooseCustomColor")'));
    expect(runner, contains('CHOOSECOLORW chooser = {}'));
    expect(runner, contains('CC_ANYCOLOR | CC_FULLOPEN | CC_RGBINIT'));
    expect(cmake, contains('"comdlg32.lib"'));
    expect(settings, contains('widget.pickCustomThemeColor'));
  });

  test('Paper menus use the original hover tint strengths', () {
    final app = _readProjectText('lib/src/app.dart');

    expect(app, contains('elevation: 0'));
    expect(
      app,
      contains('shadowColor: const WidgetStatePropertyAll(Colors.transparent)'),
    );
    expect(app, contains('alpha: isDark ? 48 / 255 : 32 / 255'));
    expect(app, contains('hoverColor: hoverTint'));
    expect(app, contains('focusColor: hoverTint'));
    expect(app, contains('highlightColor: hoverTint'));
    expect(app, contains('class _PaperTodoPopupMenuItem<T>'));
    expect(app, contains('borderRadius: BorderRadius.circular(8)'));
    expect(app, contains('highlightColor: Colors.transparent'));
    expect(app, contains('class _PaperTodoPopupMenuHeaderLabel'));
    expect(app, contains('colors.weakText.withValues(alpha: 0.72)'));
    expect(app, contains('colors.onSurface.withValues(alpha: 0.72)'));
    expect(app, contains('? _PaperTodoPopupMenuItem<String>('));
    expect(app, contains('height: 21'));
    expect(app, contains('widget.standaloneSurface ? 7 : 16'));
  });

  test('Todo removals preserve PaperTodo fade and stagger timing', () {
    final app = _readProjectText('lib/src/app.dart');

    expect(app, contains('class _TodoDepartureAnimation'));
    expect(app, contains('duration: const Duration(milliseconds: 200)'));
    expect(app, contains('slideDistance: 30'));
    expect(app, contains('delay: Duration(milliseconds: index * 30)'));
    expect(app, contains('duration: const Duration(milliseconds: 180)'));
    expect(app, contains('slideDistance: 20'));
    expect(app, contains('Curves.easeOutQuad.transform(fadeProgress)'));
  });

  test('Todo entrances preserve PaperTodo new and paste timing', () {
    final app = _readProjectText('lib/src/app.dart');

    expect(app, contains('class _TodoEntranceAnimation'));
    expect(app, contains('opacityDuration: const Duration(milliseconds: 250)'));
    expect(app, contains('slideDuration: const Duration(milliseconds: 250)'));
    expect(app, contains('slideDistance: 20'));
    expect(app, contains('delay: Duration(milliseconds: index * 40)'));
    expect(app, contains('opacityDuration: const Duration(milliseconds: 200)'));
    expect(app, contains('slideDuration: const Duration(milliseconds: 220)'));
    expect(app, contains('slideDistance: 15'));
  });

  test('Flutter secondary surfaces keep PaperTodo paper dialog chrome', () {
    final app = _readProjectText('lib/src/app.dart');
    final settings = _readProjectText('lib/src/ui/sync_settings_dialog.dart');

    expect(app, isNot(contains('AlertDialog(')));
    expect(settings, isNot(contains('AlertDialog(')));
    expect(settings, contains('_SettingsWindowDialog('));
    expect(settings, contains("'settings-max-title-length'"));
    expect(settings, contains('_SettingsStepper('));
    expect(settings, isNot(contains('_SettingsSlider(')));
    expect(settings, isNot(contains("'settings-color-scheme-selector'")));
  });

  test('Windows paper HWNDs preserve PaperTodo transparent shadow chrome', () {
    final app = _readProjectText('lib/src/app.dart');

    expect(app, contains('const _paperWindowChromeMargin = 8.0'));
    expect(app, contains('EdgeInsets.all(_paperWindowChromeMargin)'));
    expect(app, contains('standaloneSurface'));
    expect(app, contains('const <BoxShadow>[]'));
    expect(app, contains('_paperWindowTransparencyGuards()'));
    expect(app, contains('paper-window-transparency-guard-left'));
    expect(app, contains('clipBehavior: standaloneSurface ? Clip.hardEdge'));
    expect(app, contains('paper-window-capsule-surface'));
    expect(app, contains('scaleX: paper.isNote ? 0.93 : 0.94'));
    expect(app, contains('offset: const Offset(-1, -1)'));
    expect(app, contains('paper.isNote ? -1 : -1.25'));
  });

  test('Windows paper HWND geometry stays logical across monitor DPI', () {
    final paperWindow =
        _readProjectText('windows/runner/paper_flutter_window.cpp');
    final coordinator = _readProjectText('windows/runner/flutter_window.cpp');

    expect(paperWindow, contains('DpiForPhysicalPoint'));
    expect(paperWindow, contains('ScaleLogicalValue'));
    expect(paperWindow, contains('UnscalePhysicalValue'));
    expect(paperWindow, contains('ScaleForDpi(window, 220)'));
    expect(paperWindow, contains('FlutterDesktopGetDpiForMonitor(monitor)'));
    expect(
      coordinator,
      contains('GetWindowRect(paper_window->GetHandle(), &native_bounds)'),
    );
  });

  test('Windows native capsules scale their paper metrics per monitor', () {
    final capsule =
        _readProjectText('windows/runner/native_capsule_window.cpp');
    final header = _readProjectText('windows/runner/native_capsule_window.h');

    expect(capsule, contains('FlutterDesktopGetDpiForMonitor'));
    expect(capsule, contains('ScaleMetric(kCapsuleChromeMargin)'));
    expect(capsule, contains('ScaleMetric(kCapsuleBodyHeight)'));
    expect(capsule, contains('height_ = ScaleMetric(46)'));
    expect(capsule, contains('ScaleMetric(13)'));
    expect(capsule, contains('ScaleMetric(15)'));
    expect(capsule, contains('L"\\u270E"'));
    expect(capsule, contains('L"\\u26A1"'));
    expect(capsule, contains('script_capsule_ = BoolValue('));
    expect(capsule, contains('constexpr int kCapsuleCloseWidth = 30'));
    expect(capsule, contains('bool NativeCapsuleWindow::IsClosePoint('));
    expect(capsule, contains('DrawTextW(buffer, L"\\u00D7"'));
    expect(capsule, contains('SendHide();'));
    expect(capsule, contains('"hideRequested"'));
    expect(capsule, contains('struct CapsulePalette'));
    expect(capsule, contains('RelativeLuminance(COLORREF color)'));
    expect(capsule, contains('BlendAlpha(background, palette.tint'));
    expect(capsule, contains('dark ? 48 : 32'));
    expect(capsule, contains('Mix(custom, RGB(0, 0, 0), 82)'));
    expect(capsule, contains('Mix(custom, RGB(255, 255, 255), 90)'));
    expect(capsule,
        contains('palette.weak = Mix(palette.text, palette.paper, 46)'));
    expect(
        capsule, contains('font_family_ = StringValue(surface, "fontFamily"'));
    expect(capsule, contains('GetTextExtentPoint32W('));
    expect(capsule, contains('std::ceil(UnscaleMetric(measured.cx))'));
    expect(capsule, contains('int NativeCapsuleWindow::MeasureTextWidth('));
    expect(capsule, contains('62 + glyph_width + label_width'));
    expect(capsule, contains('wpf_metric_correction'));
    expect(capsule, contains('label_width - 3'));
    expect(capsule, contains('const int title_clip_width ='));
    expect(capsule, contains('IntersectClipRect(buffer, title_clip.left'));
    expect(capsule, contains('SetTextColor(buffer, master_ ? text : weak)'));
    expect(capsule, contains('ANTIALIASED_QUALITY'));
    expect(capsule, contains('22 + glyph_width +'));
    expect(capsule, contains('logical_full_width -'));
    expect(capsule, contains('std::min(54, logical_full_width)'));
    expect(capsule, contains('? ScaleMetric(12)'));
    expect(capsule, contains('measured_glyph_width'));
    expect(capsule, contains('glyph_rect.right + glyph_gap'));
    expect(header, contains('UINT dpi_ = 96'));
    expect(header, contains('EffectiveFontFamily() const'));
    expect(header, contains('int MeasureTextWidth('));
    expect(header, contains('bool script_capsule_ = false'));
    expect(header, contains('bool close_hovered_ = false'));
    expect(header, contains('bool close_pressed_ = false'));
  });

  test('Windows tray icon primary click follows PaperTodo double-click model',
      () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final trayMessageStart = runner.indexOf('case kTrayIconMessage:');
    final trayMessageEnd = runner.indexOf('break;', trayMessageStart);

    expect(design, contains('double-click restores'));
    expect(design, contains('single left'));
    expect(trayMessageStart, isNonNegative);
    expect(trayMessageEnd, greaterThan(trayMessageStart));
    final trayMessage = runner.substring(trayMessageStart, trayMessageEnd);
    expect(trayMessage, contains('case WM_LBUTTONDBLCLK:'));
    expect(trayMessage, isNot(contains('case WM_LBUTTONUP:')));
    expect(trayMessage, contains('SendStartupCommandRequested("show");'));
    expect(trayMessage, contains('case WM_RBUTTONUP:'));
    expect(trayMessage, contains('ShowTrayMenu();'));
  });

  test('Windows tray settings command shows the app window', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final settingsCaseStart = runner.indexOf('case kTraySettingsCommand:');
    final settingsCaseEnd = runner.indexOf('break;', settingsCaseStart);

    expect(settingsCaseStart, isNonNegative);
    expect(settingsCaseEnd, greaterThan(settingsCaseStart));
    final settingsCase = runner.substring(settingsCaseStart, settingsCaseEnd);
    expect(settingsCase, contains('SendStartupCommandRequested("settings");'));
    expect(settingsCase, contains('ShowSettingsCoordinatorWindow(window);'));
  });

  test('Windows settings coordinator is a DPI-aware borderless paper window',
      () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final app = _readProjectText('lib/src/app.dart');
    final settings = _readProjectText('lib/src/ui/sync_settings_dialog.dart');

    expect(
        runner, contains('ApplySettingsCoordinatorWindowStyle(GetHandle())'));
    expect(runner, contains('ApplySettingsCoordinatorWindowStyle(window)'));
    expect(runner, contains('SetWindowTextW(window, L"")'));
    expect(runner, contains('WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN'));
    expect(runner, contains('WS_EX_LAYERED | WS_EX_TOOLWINDOW'));
    expect(runner, contains('SetLayeredWindowAttributes(window, RGB(1, 2, 3)'));
    expect(runner, contains('DWMNCRP_DISABLED'));
    expect(runner, contains('MARGINS margins = {0, 0, 0, 0}'));
    expect(runner, contains('PaintSettingsCoordinatorBackground('));
    expect(runner, contains('g_settings_coordinator_background'));
    expect(runner, contains('method == "setCoordinatorBackgroundColor"'));
    expect(runner, contains('RDW_INVALIDATE | RDW_ERASE | RDW_FRAME'));
    expect(runner, contains('logical_work_height * 0.72'));
    expect(runner, contains('kSettingsWindowMinDefaultWidth = 672'));
    expect(runner, contains('kSettingsWindowMaxDefaultWidth = 792'));
    expect(runner, contains('kSettingsWindowMinDefaultHeight = 520'));
    expect(runner, contains('kSettingsWindowMaxDefaultHeight = 720'));
    expect(runner, isNot(contains('case WM_NCCALCSIZE:')));
    expect(runner, contains('message == WM_NCCALCSIZE && wparam == TRUE'));
    expect(runner, contains('message == WM_NCPAINT'));
    expect(runner, contains('message == WM_NCACTIVATE'));
    expect(
      runner.indexOf('message == WM_NCCALCSIZE && wparam == TRUE'),
      lessThan(runner.indexOf('HandleTopLevelWindowProc(hwnd, message')),
    );
    expect(runner, contains('case WM_NCHITTEST:'));
    expect(runner, contains('return SettingsCoordinatorHitTest(hwnd, lparam)'));
    expect(
        runner, contains('ScaleSettingsMetric(dpi, kSettingsWindowMinWidth)'));
    expect(app, contains('backgroundColor: _windowsPaperTransparencyKey'));
    expect(app, contains("ValueKey('windows-settings-paper-underlay')"));
    expect(app, contains('controller.setCoordinatorBackgroundColor('));
    expect(settings, contains('barrierColor: Colors.transparent'));
    expect(settings, contains('barrierDismissible: false'));
    expect(settings, contains('useSafeArea: false'));
    expect(settings, contains("ValueKey('windows-settings-paper-dialog')"));
    expect(settings, contains('insetPadding: EdgeInsets.zero'));
    expect(settings, contains("ValueKey('windows-settings-paper-fill')"));
    expect(settings, contains('child: SizedBox.expand('));
  });

  test('Windows forwarded settings command reveals the coordinator window', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final forwardedCommandStart =
        runner.indexOf('case kSingleInstanceCommandMessage:');
    final forwardedCommandEnd =
        runner.indexOf('case kTrayIconMessage:', forwardedCommandStart);

    expect(forwardedCommandStart, isNonNegative);
    expect(forwardedCommandEnd, greaterThan(forwardedCommandStart));
    final forwardedCommand =
        runner.substring(forwardedCommandStart, forwardedCommandEnd);
    expect(
        forwardedCommand, contains('SendStartupCommandRequested(*command);'));
    expect(forwardedCommand, contains('if (*command == "settings")'));
    expect(forwardedCommand, contains('ShowSettingsCoordinatorWindow(hwnd);'));
  });

  test('Windows coordinator closes without becoming a duplicate paper window',
      () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final closeStart = runner.indexOf('case WM_CLOSE:');
    final closeEnd = runner.indexOf('case WM_HOTKEY:', closeStart);

    expect(closeStart, isNonNegative);
    expect(closeEnd, greaterThan(closeStart));
    final closeCase = runner.substring(closeStart, closeEnd);
    expect(closeCase, contains('if (!paper_windows_.empty())'));
    expect(closeCase, contains('SendWindowEvent("coordinatorCloseRequested")'));
    expect(closeCase, contains('ShowWindow(hwnd, SW_HIDE);'));
    expect(closeCase.indexOf('if (!paper_windows_.empty())'),
        lessThan(closeCase.indexOf('RetargetActivePaperToVisibleSurface')));
    expect(runner, contains('if (method == "hideCoordinator")'));
  });

  test('Windows tray paper command lets Dart toggle the selected paper', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final app = _readProjectText('lib/src/app.dart');
    final nativeCapsule =
        _readProjectText('windows/runner/native_capsule_window.cpp');
    final paperCommandStart = runner.indexOf(
      'command >= kTrayPaperCommandBase',
    );
    final paperCommandEnd = runner.indexOf('break;', paperCommandStart);

    expect(paperCommandStart, isNonNegative);
    expect(paperCommandEnd, greaterThan(paperCommandStart));
    final paperCommand = runner.substring(paperCommandStart, paperCommandEnd);
    expect(paperCommand, contains('SendPaperRequested('));
    expect(paperCommand, isNot(contains('ShowWindow(window, SW_SHOWNORMAL);')));
    expect(paperCommand, isNot(contains('SetForegroundWindow(window);')));
    expect(app, contains('Future<void> _handlePaperOpenRequest'));
    expect(app, contains('await _hidePaper(paper);'));
    expect(app, contains('await _openPaper(paper);'));
    expect(
        app,
        contains(
            'final isCollapsed = Platform.isWindows && paper.isCollapsed;'));
    expect(app, isNot(contains('collapseAllActive || paper.isCollapsed')));
    expect(app, contains('_applyDueSelection(item, result, initialDate)'));
    expect(app, contains("'stale-collapse-rerouted'"));
    expect(
        app, contains('Platform.isWindows && controller.state.useCapsuleMode'));
    expect(app, contains('final isCollapsed = Platform.isWindows &&'));
    expect(nativeCapsule, contains('const int corner_ellipse'));
    expect(nativeCapsule, contains('bounds.bottom - bounds.top'));
  });

  test('Windows tray visibility state is refreshed without bounds noise', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final controller = _readProjectText('lib/src/app_controller.dart');
    final showStart = controller.indexOf('Future<void> _showPaper(');
    final showEnd = controller.indexOf('Future<void> openLinkedNote');
    final hideStart = controller.indexOf('Future<void> _hidePaper(');
    final hideEnd = controller.indexOf('Future<void> executeStartupCommand');
    final updateStart = controller.indexOf('Future<void> updatePaperSurface(');
    final updateEnd =
        controller.indexOf('Future<void> capturePaperSurfaceBounds(');
    final captureEnd =
        controller.indexOf('void setPaperAlwaysOnTop(', updateEnd);
    final startupStart =
        controller.indexOf('Future<void> _executeStartupCommand(');
    final startupEnd =
        controller.indexOf('Future<bool> _hasVisibleSurfacesForToggle');

    expect(design, contains('close/show/hide events'));
    expect(design, contains('should refresh the tray menu promptly'));
    expect(
      design,
      contains('plain move/resize bounds updates should not trigger extra'),
    );
    expect(showStart, isNonNegative);
    expect(showEnd, greaterThan(showStart));
    expect(hideStart, isNonNegative);
    expect(hideEnd, greaterThan(hideStart));
    expect(updateStart, isNonNegative);
    expect(updateEnd, greaterThan(updateStart));
    expect(captureEnd, greaterThan(updateEnd));
    expect(startupStart, isNonNegative);
    expect(startupEnd, greaterThan(startupStart));

    final showBlock = controller.substring(showStart, showEnd);
    final hideBlock = controller.substring(hideStart, hideEnd);
    final surfaceOnlyBlock = controller.substring(updateStart, captureEnd);
    final startupBlock = controller.substring(startupStart, startupEnd);

    expect(showBlock, contains('_platform.tray.rebuildMenu(state)'));
    expect(hideBlock, contains('_platform.tray.rebuildMenu(state)'));
    expect(surfaceOnlyBlock, isNot(contains('rebuildMenu')));
    expect(startupBlock, contains('trayMenuNeedsRefresh'));
    expect(startupBlock, contains('rebuildTrayMenu: false'));
  });

  test('Windows tray paper delete command confirms in the menu', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final platform =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final trayCommandStart = runner.indexOf('switch (command) {');
    final trayCommandEnd = runner.indexOf(
      'void FlutterWindow::SendBoundsChanged()',
      trayCommandStart,
    );

    expect(design, contains('Native Windows tray menus'));
    expect(design, contains('do not leak confirmation or delete submenus'));
    expect(runner, contains('kTrayPaperDeleteCommandBase'));
    expect(runner, contains('tray_labels_.delete_paper,'));
    expect(runner, contains('class ScopedMenu'));
    expect(runner, contains('DestroyMenu(menu_);'));
    expect(runner, contains('ScopedMenu confirm_menu(CreatePopupMenu());'));
    expect(runner, contains('ScopedMenu delete_menu(CreatePopupMenu());'));
    expect(runner, contains('has_delete_confirmation'));
    expect(runner, contains('append_owner_draw(delete_menu.get()'));
    expect(runner,
        contains('append_owner_draw(menu.get(), 0, tray_labels_.delete_paper'));
    expect(runner, contains('confirm_menu.release();'));
    expect(runner, contains('delete_menu.release();'));
    expect(runner, contains('tray_labels_.inline_confirm_action,'));
    expect(runner, contains('tray_labels_.cancel,'));
    expect(trayCommandStart, isNonNegative);
    expect(trayCommandEnd, greaterThan(trayCommandStart));
    expect(
      runner.substring(trayCommandStart, trayCommandEnd),
      isNot(contains('MessageBoxW')),
    );
    expect(runner, contains('SendPaperDeleteRequested'));
    expect(runner, contains('"paperDeleteRequested"'));
    expect(platform, contains('_paperDeleteRequests'));
    expect(platform, contains("case 'paperDeleteRequested':"));
  });

  test('Windows platform ignores unknown explicit paper IDs', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final platform =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final lookupStart = platform.indexOf('PaperData? _paperFromEventArguments');
    final lookupEnd = platform.indexOf('String? _paperIdFromArguments');
    final surfaceArgsStart =
        platform.indexOf('Map<String, Object?> _paperSurfaceArguments');
    final surfaceArgsEnd =
        platform.indexOf('Map<String, Object?> _paperTitleArguments');
    final registryStart =
        runner.indexOf('void FlutterWindow::ApplyPaperSurfaceRegistry');
    final registryEnd =
        runner.indexOf('std::string FlutterWindow::CachedMonitorDeviceName');

    expect(design, contains('explicitly name an unknown `paperId`'));
    expect(design, contains('must already be normalized'));
    expect(
      design,
      contains(
          'Native direct paper surface operations must follow the same rule'),
    );
    expect(
      design,
      contains('ignored rather than falling back to the active paper'),
    );
    expect(design, contains('Dedicated registry refreshes from restore'));
    expect(design, contains('capsule side and monitor device name'));
    expect(design, contains('primary monitor device name to an empty queue'));
    expect(design, contains('direct paper surface operations'));
    expect(platform, contains('WindowsTrayHost(channel, paperWindowHost)'));
    expect(platform, contains('void _syncKnownPapers(AppState state)'));
    expect(platform, contains('_knownPapers.clear();'));
    expect(platform, contains('_paperWindows._syncKnownPapers(state);'));
    expect(platform, contains('if (activePaper.isVisible)'));
    expect(surfaceArgsStart, isNonNegative);
    expect(surfaceArgsEnd, greaterThan(surfaceArgsStart));
    final surfaceArgsBlock =
        platform.substring(surfaceArgsStart, surfaceArgsEnd);
    expect(surfaceArgsBlock, contains("'capsuleSide': paper.capsuleSide"));
    expect(
      surfaceArgsBlock,
      contains("'capsuleMonitorDeviceName': paper.capsuleMonitorDeviceName"),
    );
    expect(platform, contains('_normalizeStateForPlatform'));
    expect(platform, contains('_normalizePaperForPlatform'));
    expect(platform, contains('paper.id = normalizeLocalModelId(paper.id);'));
    expect(platform, contains('normalizeLocalModelId(_activePaper?.id)'));
    expect(platform, contains('_normalizePaperQueueMonitorDeviceName'));
    expect(platform, contains("'setPaperSurfaces'"));
    expect(platform, contains("'normalizeQueueMonitorDeviceName'"));
    expect(runner, contains('RememberPaperCapsuleState'));
    expect(runner, contains('if (method == "setPaperSurfaces")'));
    expect(runner, contains('ApplyPaperSurfaceRegistry(*papers, false)'));
    expect(runner, contains('ApplyPaperSurfaceRegistry(*papers, true)'));
    expect(runner, contains('struct PaperIdArgument'));
    expect(runner, contains('ValidatePaperIdArgumentValue'));
    expect(runner, contains('TrimAscii(value) != value'));
    expect(runner, contains('HasAsciiControlCharacter(value)'));
    expect(runner, contains('HasControlCodePoint(value)'));
    expect(
      runner,
      contains('paper_id_argument.provided && !paper_id_argument.valid'),
    );
    expect(runner, contains('NormalizeQueueMonitorDeviceName'));
    expect(runner, contains('PrimaryMonitorDeviceName'));
    expect(runner, contains('"normalizeQueueMonitorDeviceName"'));
    expect(runner, contains('GetStringArgument(*paper_map, "capsuleSide"'));
    expect(runner, contains('GetStringArgumentValue(call.arguments()'));
    expect(runner, contains('"capsuleMonitorDeviceName"'));
    expect(runner, contains('CachedMonitorDeviceNameForPaper'));
    expect(
      runner,
      contains('monitor_device_name = cached_monitor_device_name;'),
    );
    expect(
      runner,
      contains('CachedMonitorDeviceNameForPaper(requested_paper_id)'),
    );
    expect(
      _readProjectText('windows/runner/flutter_window.h'),
      contains('std::string capsule_side;'),
    );
    expect(platform, contains('_validatedEventPaperId'));
    expect(platform, contains('value.trim() != value'));
    expect(
      platform,
      contains('_hasUnsafeExternalFilePathCharacter(value)'),
    );
    expect(lookupStart, isNonNegative);
    expect(lookupEnd, greaterThan(lookupStart));
    final lookupBlock = platform.substring(lookupStart, lookupEnd);
    expect(lookupBlock, contains('return _activePaper;'));
    expect(lookupBlock, contains('return _knownPapers[paperId];'));
    expect(lookupBlock, isNot(contains('?? _activePaper')));
    expect(platform, contains('_nextVisibleKnownPaperAfter'));
    expect(platform, contains('_retargetActivePaperAfterLocalHide'));
    expect(platform, contains('candidate.isVisible'));
    expect(platform, contains('_activePaper = _nextVisibleKnownPaperAfter'));
    expect(platform, contains('_retargetActivePaperAfterLocalHide(paper);'));
    final updateSurfaceStart =
        platform.indexOf('Future<void> updatePaperSurface(PaperData paper)');
    final updateSurfaceEnd =
        platform.indexOf('Map<String, Object?> _paperSurfaceArguments');
    expect(updateSurfaceStart, isNonNegative);
    expect(updateSurfaceEnd, greaterThan(updateSurfaceStart));
    final updateSurfaceBlock =
        platform.substring(updateSurfaceStart, updateSurfaceEnd);
    expect(updateSurfaceBlock, contains('if (!paper.isVisible)'));
    expect(
      updateSurfaceBlock,
      contains('_retargetActivePaperAfterLocalHide(paper);'),
    );
    expect(registryStart, isNonNegative);
    expect(registryEnd, greaterThan(registryStart));
    final registryBlock = runner.substring(registryStart, registryEnd);
    expect(registryBlock, contains('current_paper_ids'));
    expect(registryBlock, contains('ValidatePaperIdArgumentValue'));
    expect(registryBlock, contains('if (paper_id_argument.valid)'));
    expect(registryBlock,
        contains('const std::string id = paper_id_argument.value'));
    expect(registryBlock, contains('paper_surface_order_ = current_paper_ids'));
    expect(registryBlock, contains('paper_surfaces_.erase(iterator)'));
    expect(registryBlock, contains('active_paper_id_.clear()'));
    expect(registryBlock, contains('if (rebuild_tray_items)'));
  });

  test('Windows runner hides only the active native paper surface', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final header = _readProjectText('windows/runner/flutter_window.h');
    final hideStart = runner.indexOf('if (method == "hide")');
    final hideEnd = runner.indexOf('if (method == "setAlwaysOnTop")');

    expect(design, contains('specific non-active paper'));
    expect(design, contains('next visible surface after the hidden\npaper'));
    expect(design, contains('latest Dart registry order'));
    expect(header, contains('std::vector<std::string> paper_surface_order_'));
    expect(header, contains('void RememberPaperSurfaceOrder'));
    expect(hideStart, isNonNegative);
    expect(hideEnd, greaterThan(hideStart));
    final hideBlock = runner.substring(hideStart, hideEnd);
    expect(hideBlock, contains('GetPaperIdArgument'));
    expect(
      hideBlock,
      contains('RememberPaperVisibility(requested_paper_id, false)'),
    );
    expect(hideBlock, contains('requested_paper_id == active_paper_id_'));
    expect(hideBlock, contains('RetargetActivePaperToVisibleSurface'));
    expect(hideBlock, isNot(contains('RememberActivePaperId')));
    expect(runner,
        contains('bool FlutterWindow::RetargetActivePaperToVisibleSurface'));
    expect(runner, contains('const auto retarget_to_surface'));
    expect(runner, contains('size_t start_index = 0'));
    expect(runner, contains('std::distance(paper_surface_order_.begin()'));
    expect(runner, contains('(start_index + offset) %'));
    expect(runner, contains('RememberPaperSurfaceOrder(paper_id)'));
    expect(runner, contains('entry.second.is_visible'));
    expect(runner, contains('paper_surface_order_.end()'));
    expect(runner, contains('ApplyActivePaperBounds(window)'));
    expect(runner, contains('SetWindowTextW(window, state.title.c_str())'));
    expect(runner, contains('RefreshActivePaperZOrder(window)'));
    final closeStart = runner.indexOf('case WM_CLOSE:');
    final closeEnd = runner.indexOf('case WM_HOTKEY:', closeStart);
    expect(closeStart, isNonNegative);
    expect(closeEnd, greaterThan(closeStart));
    final closeBlock = runner.substring(closeStart, closeEnd);
    expect(closeBlock, contains('SendCloseRequested()'));
    expect(closeBlock,
        contains('RememberPaperVisibility(closed_paper_id, false)'));
    expect(closeBlock, contains('RetargetActivePaperToVisibleSurface'));
  });

  test('Windows runner owns one Flutter engine and HWND per visible paper', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final roadmap = _readProjectText('docs/ROADMAP.md');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final runnerHeader = _readProjectText('windows/runner/flutter_window.h');
    final paperWindow =
        _readProjectText('windows/runner/paper_flutter_window.cpp');
    final paperWindowHeader =
        _readProjectText('windows/runner/paper_flutter_window.h');
    final nativeCapsule =
        _readProjectText('windows/runner/native_capsule_window.cpp');
    final nativeCapsuleHeader =
        _readProjectText('windows/runner/native_capsule_window.h');
    final cmake = _readProjectText('windows/runner/CMakeLists.txt');
    final mainDart = _readProjectText('lib/main.dart');
    final paperWindowApp =
        _readProjectText('lib/src/windows/paper_window_app.dart');
    final windowsPlatform =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final windowsSmoke = _readProjectText('scripts/windows_smoke.ps1');
    final paperNativeStyle = _sliceBetween(
      paperWindow,
      'void PaperFlutterWindow::ApplyNativeStyle()',
      'int PaperFlutterWindow::ResizeBorderHitTest',
    );

    expect(design, contains('one child Flutter engine and one top-level HWND'));
    expect(design, contains('return only their own'));
    expect(roadmap, contains('one visible HWND per visible'));
    expect(runnerHeader,
        contains('std::map<std::string, std::unique_ptr<PaperFlutterWindow>>'));
    expect(runner, contains('ReconcilePaperWindows(*papers)'));
    expect(runner, contains('ReconcileNativeCapsuleWindows(*surfaces)'));
    expect(runner, contains('child_project.set_dart_entrypoint_arguments'));
    expect(runner, contains('ShowWindow(GetHandle(), SW_HIDE)'));
    expect(paperWindowHeader, contains('class PaperFlutterWindow'));
    expect(nativeCapsuleHeader, contains('class NativeCapsuleWindow'));
    expect(nativeCapsuleHeader, contains('public Win32Window'));
    expect(nativeCapsule, isNot(contains('FlutterViewController')));
    expect(nativeCapsule, contains('WS_EX_NOACTIVATE'));
    expect(nativeCapsule, contains('"toggleCollapseAll"'));
    expect(nativeCapsule, contains('"capsuleDropped"'));
    expect(nativeCapsule, contains('"capsuleMasterDragUpdated"'));
    expect(nativeCapsule, contains('kCapsuleBodyHeight = 30'));
    expect(nativeCapsule, contains('kCapsuleChromeMargin = 8'));
    expect(nativeCapsule, contains('kCapsuleCornerRadius = 12'));
    expect(nativeCapsule, contains('kCapsuleSlideOutMilliseconds = 220'));
    expect(nativeCapsule, contains('kCapsuleSlideInMilliseconds = 180'));
    expect(nativeCapsule, contains('UpdateDockAnimation'));
    expect(
      windowsPlatform,
      contains("'enableAnimations': state.enableAnimations"),
    );
    expect(runner, contains('ApplyQueueDragOffset(delta_y)'));
    expect(paperWindow,
        contains('std::make_unique<flutter::FlutterViewController>'));
    expect(paperWindow, contains('"repapertodo/paper_window"'));
    expect(paperWindow, contains('MeasureCapsuleTextWidth('));
    expect(paperWindow, contains('GetTextExtentPoint32W('));
    expect(paperWindow, contains('CapsuleFontFamily(font_family)'));
    expect(paperWindow, contains('script_capsule ? 15 : 13'));
    expect(paperWindow, contains('CapsuleWpfMetricCorrection('));
    expect(
      paperWindow,
      contains('paper_type == "note" || script_capsule ? -2.0 : -3.0'),
    );
    expect(paperWindowHeader, contains('std::string paper_type_ = "todo"'));
    expect(paperWindowHeader, contains('bool script_capsule_ = false'));
    expect(paperWindow, contains('collapsed_ ? 46.0'));
    expect(paperWindow, isNot(contains('FindDesktopWorkerWindow')));
    expect(paperWindow, isNot(contains('SetParent(window, desktop_parent_)')));
    expect(paperWindow, contains('SetWindowPos(window, HWND_BOTTOM'));
    expect(paperWindow, contains('(current_style & WS_VISIBLE)'));
    expect(paperNativeStyle, isNot(contains('WS_EX_TRANSPARENT')));
    expect(paperWindow, contains('taskbar->DeleteTab(window)'));
    expect(paperWindow, contains('WS_EX_NOACTIVATE'));
    expect(paperWindow, contains('case WM_MOUSEACTIVATE:'));
    expect(paperWindow, contains('return MA_NOACTIVATE;'));
    expect(paperWindow, isNot(contains('case WM_WINDOWPOSCHANGING:')));
    expect(paperWindow, contains('SetHideFromWindowSwitcher'));
    expect(paperWindow, contains('IsExternalFullscreenWindow'));
    expect(paperWindow, contains('DWMWA_EXTENDED_FRAME_BOUNDS'));
    expect(paperWindow,
        contains('bounds.left <= info.rcMonitor.left + tolerance'));
    expect(paperWindow, contains('IsCoveredByAnotherWindow'));
    expect(paperWindow, contains('SetWindowPos(window, HWND_NOTOPMOST'));
    expect(paperWindow,
        contains('wcscmp(class_name, kPaperShadowWindowClass) == 0'));
    expect(paperWindow, contains('case WM_ENTERSIZEMOVE:'));
    expect(paperWindow, contains('case WM_EXITSIZEMOVE:'));
    expect(paperWindow, contains('case WM_GETMINMAXINFO:'));
    expect(paperWindow, contains('GetDpiForWindow(window)'));
    expect(paperWindow, contains('WS_EX_LAYERED'));
    expect(paperWindow,
        contains('SetLayeredWindowAttributes(window, RGB(1, 2, 3)'));
    expect(paperWindow, contains('DWMNCRP_DISABLED'));
    expect(paperWindow, contains('MARGINS margins = {0, 0, 0, 0}'));
    expect(paperWindow, contains('case WM_NCPAINT:'));
    expect(paperWindow, contains('case WM_NCACTIVATE:'));
    expect(paperWindow, contains('case WM_WINDOWPOSCHANGED:'));
    expect(paperWindow,
        contains('const int drag_width = ScaleForDpi(window, 26)'));
    expect(paperWindow, contains('return HTCAPTION;'));
    expect(paperWindow, contains('kPaperShadowWindowClass'));
    expect(paperWindow, contains('RoundedRectSignedDistance'));
    expect(paperWindow,
        contains('edge_opacity = paper_shadow_dark_ ? 0.17 : 0.09'));
    expect(paperWindow,
        contains('UpdateLayeredWindow(paper_shadow_window_, screen'));
    expect(paperWindow, contains('SetWindowPos(paper_shadow_window_, window'));
    expect(paperWindow, contains('WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW'));
    expect(paperWindowHeader, contains('void SetAlwaysOnTop(bool enabled);'));
    expect(
        paperWindowHeader, contains('void SetPinnedToDesktop(bool pinned);'));
    expect(paperWindowHeader,
        contains('void SetPaperTitle(const std::string& title);'));
    expect(runner, contains('paper_window->SetAlwaysOnTop(enabled)'));
    expect(runner, contains('paper_window->SetPinnedToDesktop(enabled)'));
    expect(runner, contains('paper_window->SetPaperTitle(title)'));
    expect(
      runner,
      contains(
        'Native expanded-paper proxies must activate their paper synchronously',
      ),
    );
    expect(runner, contains('kind == "openPaper" && target.valid'));
    expect(
        runner, contains('RememberPaperPinnedToDesktop(target.value, false)'));
    expect(runner, contains('paper_window->SetPinnedToDesktop(false)'));
    expect(runner, contains('paper_window->ShowPaper(true)'));
    expect(runner, contains('existing_window->BoundsValue()'));
    expect(runner, contains('flutter::EncodableMap resolved_surface'));
    expect(
      paperWindow,
      contains('WorkAreaForWindow(window, capsule_monitor_device_name_)'),
    );
    expect(paperWindow, contains('capsuleTopIsWorkAreaRelative'));
    expect(paperWindow, contains('ScaleLogicalValue(y, target_dpi)'));
    expect(paperWindow, contains('DpiForPhysicalPoint(window, x, y)'));
    expect(paperWindow, contains('UnscalePhysicalValue('));
    expect(paperWindow, contains('capsule_side_ == "left"'));
    expect(paperWindow, contains('CapsuleRestingVisibleWidth'));
    expect(paperWindow, contains('CapsuleHoverVisibleWidth'));
    expect(paperWindow, contains('SetCapsuleHovered(*hovered)'));
    expect(paperWindow, contains('StartCapsuleDockAnimation'));
    expect(paperWindow, contains('UpdateCapsuleDockAnimation'));
    expect(paperWindow, contains('kCapsuleSlideOutMilliseconds = 220'));
    expect(paperWindow, contains('kCapsuleSlideInMilliseconds = 180'));
    expect(paperWindow, contains('capsule_animation_active_'));
    expect(paperWindowHeader,
        contains('bool capsule_animations_enabled_ = true;'));
    expect(nativeCapsule, contains('!hovered_ && !pointer_down_'));
    expect(paperWindow, contains('collapsed_ && !capsule_hovered_'));
    expect(runner, contains('kFullscreenTopmostRefreshIntervalMs = 250'));
    expect(paperWindowApp, contains("'capsuleHoverChanged'"));
    expect(paperWindowHeader, contains('bool in_size_move_ = false;'));
    expect(cmake, contains('"paper_flutter_window.cpp"'));
    expect(cmake, contains('"native_capsule_window.cpp"'));
    expect(mainDart, contains('PaperWindowArguments.tryParse(args)'));
    expect(paperWindowApp, contains("'paperChanged'"));
    expect(paperWindowApp, contains('paperWindowMode: true'));
    expect(windowsSmoke, contains('CountVisibleTopLevelWindows'));
    expect(windowsSmoke, contains('CountVisiblePaperWindows'));
    expect(windowsSmoke, contains('CountVisibleNativeCapsuleWindows'));
    expect(windowsSmoke, contains('IsIndependentPaperWindow'));
    expect(windowsSmoke, contains('WS_THICKFRAME'));
    expect(windowsSmoke, contains('MoveResizeWindow'));
    expect(windowsSmoke, contains('Test-PersistedPaperBounds'));
    expect(windowsSmoke, contains('Test-PersistedPaperContentMarker'));
    expect(windowsSmoke, contains('Test-PaperWindowBounds'));
    expect(windowsSmoke, contains('EditTodoText'));
    expect(windowsSmoke, contains(r'geometryPersistenceVerified = $true'));
    expect(
      windowsSmoke,
      contains(r'contentEditGeometryStabilityVerified = $true'),
    );
    expect(windowsSmoke, contains('independentPaperSurfaces = \$true'));
    expect(windowsSmoke, contains('settingsCoordinatorLifecycle = \$true'));
    expect(windowsSmoke, contains('settingsStartupCommands'));
    expect(windowsSmoke, contains('Close-CoordinatorWindow'));
    expect(
      _readProjectText('scripts/release_readiness_audit.ps1'),
      allOf(
        contains('must prove independent visible paper HWNDs'),
        contains('content-edit geometry stability'),
      ),
    );
  });

  test('independent paper windows expose a visible native drag affordance', () {
    final app = _readProjectText('lib/src/app.dart');
    final strings = _readProjectText('lib/src/ui/papertodo_strings.dart');
    final policySmoke = _readProjectText('scripts/windows_policy_smoke.ps1');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(app, contains('final Future<void> Function()? onWindowDragStart;'));
    expect(app, contains('!desktopInteractionLocked &&'));
    expect(app, contains('unawaited(onWindowDragStart!())'));
    expect(app, isNot(contains('_paperWindowDragStrip')));
    expect(app, contains('_paperWindowResizeHandles()'));
    expect(app, contains('onPointerDown: (_) =>'));
    expect(app, contains('unawaited(resizeStarter(direction))'));
    expect(app, contains("ValueKey('paper-window-resize-\$direction')"));
    expect(app, contains('actionMovePaperWindow'));
    expect(app, contains('actionResizePaperWindow'));
    expect(app, contains('standaloneSurface: widget.paperWindowMode'));
    expect(app, contains('PaperWindowActionKinds.expandPaper'));
    expect(app, contains('onPointerDown: widget.paperWindowDragStarter'));
    expect(strings, contains("'Drag to move paper'"));
    expect(strings, contains("'Drag an edge to resize paper'"));
    expect(strings, contains("'拖动以移动纸张'"));
    expect(strings, contains("'拖动边缘以调整纸张大小'"));
    expect(
      _readProjectText('lib/src/windows/paper_window_app.dart'),
      contains("invokeMethod<void>('startResize', direction)"),
    );
    expect(
      _readProjectText('windows/runner/paper_flutter_window.cpp'),
      contains('call.method_name() == "startResize"'),
    );
    expect(
      _readProjectText('windows/runner/paper_flutter_window.cpp'),
      contains('WM_SYSCOMMAND, SC_MOVE | HTCAPTION'),
    );
    expect(policySmoke, contains(r'DragPaperBy($paper, 140, 90)'));
    expect(policySmoke, contains('contentEditGeometryStable'));
    expect(
      policySmoke,
      contains('content edit replayed stale paper geometry'),
    );
    final eventStart = runner.indexOf(
      'void FlutterWindow::SendPaperWindowEvent(',
    );
    final eventEnd = runner.indexOf(
      'void FlutterWindow::DestroyPaperWindows()',
      eventStart,
    );
    expect(eventStart, isNonNegative);
    expect(eventEnd, greaterThan(eventStart));
    final eventBlock = runner.substring(eventStart, eventEnd);
    expect(eventBlock, contains('method == "boundsChanged"'));
    expect(
        eventBlock, contains('RememberPaperBounds(paper_id, native_bounds)'));
    expect(eventBlock, contains('paper_window_surfaces_[paper_id]'));
    expect(eventBlock.indexOf('RememberPaperBounds(paper_id, native_bounds)'),
        lessThan(eventBlock.indexOf('window_channel_->InvokeMethod')));
  });

  test('Windows data directory uses a native folder picker and relocation', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final storage = _readProjectText('lib/src/core/storage/state_store.dart');
    final settings = _readProjectText('lib/src/ui/sync_settings_dialog.dart');

    expect(runner, contains('FOS_PICKFOLDERS'));
    expect(runner, contains('storage-path.txt'));
    expect(runner, contains('EnsureLogDirectory'));
    expect(runner, contains('directory / L"LOG"'));
    expect(runner, contains('method == "getDataDirectory"'));
    expect(runner, contains('method == "commitDataDirectory"'));
    expect(storage, contains('Future<void> relocate('));
    expect(settings, contains("'settings-data-directory'"));
  });

  test('Windows release deploys app-local runtime dependencies', () {
    final cmake = _readProjectText('windows/CMakeLists.txt');
    final release = _readProjectText('scripts/release.ps1');
    final package = _readProjectText('scripts/package_windows_zip.ps1');
    final launcher = _readProjectText('windows/runner/launcher_main.cpp');
    final readme = _readProjectText('README.md');

    expect(cmake, contains('include(InstallRequiredSystemLibraries)'));
    expect(cmake, contains('CMAKE_INSTALL_UCRT_LIBRARIES TRUE'));
    expect(release, contains('msvcp140.dll'));
    expect(release, contains('vcruntime140.dll'));
    expect(release, contains('vcruntime140_1.dll'));
    expect(release, contains('ucrtbase.dll'));
    expect(release, contains('Assert-WindowsZipRootLayout'));
    expect(release, contains('runtime/repapertodo.runtime.exe'));
    expect(package,
        contains('Windows ZIP root must contain only repapertodo.exe'));
    expect(package, contains('runtime/repapertodo.runtime.exe'));
    expect(package, contains('[IO.Compression.ZipArchiveMode]::Create'));
    expect(package, contains(').Replace("\\", "/")'));
    expect(package, contains('Windows ZIP entries must use forward-slash'));
    expect(package, isNot(contains('Compress-Archive')));
    expect(launcher, contains('CreateProcessW'));
    expect(launcher, contains('repapertodo.runtime.exe'));
    expect(readme, contains('app-local MSVC/Universal CRT DLLs'));
  });

  test('Windows startup toggle checks the actual native surface visibility',
      () {
    final controller = _readProjectText('lib/src/app_controller.dart');
    final platformHost =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(controller, contains('hasVisibleSurfacesForToggle'));
    expect(platformHost, contains("'hasVisibleSurfaces'"));
    expect(runner, contains('if (method == "hasVisibleSurfaces")'));
    expect(runner, contains('HasAnyVisibleSurface(window)'));
    expect(runner, contains('bool FlutterWindow::HasAnyVisibleSurface'));
    expect(runner, contains('entry.second.is_visible'));
    expect(runner, contains('entry.first != active_paper_id_'));
    expect(
      _readProjectText('windows/runner/flutter_window.h'),
      contains('bool HasAnyVisibleSurface(HWND window) const;'),
    );
  });

  test('Windows settings apply restores missing visible paper surfaces', () {
    final controller = _readProjectText('lib/src/app_controller.dart');
    final platformHost =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final header = _readProjectText('windows/runner/flutter_window.h');

    expect(controller, contains('_restoreMissingVisiblePaperSurfaces'));
    expect(controller, contains('paperWindows.hasVisibleSurface(paper)'));
    expect(controller, contains('await showPaper(paper)'));
    expect(platformHost, contains("'hasVisibleSurface'"));
    expect(runner, contains('if (method == "hasVisibleSurface")'));
    expect(runner, contains('HasVisibleSurfaceForPaper'));
    expect(header, contains('bool HasVisibleSurfaceForPaper'));
  });

  test('Windows runner keeps non-active surface refreshes cached', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final header = _readProjectText('windows/runner/flutter_window.h');
    final showStart = runner.indexOf('if (method == "show")');
    final showEnd = runner.indexOf('if (method == "hide")');
    final alwaysOnTopStart = runner.indexOf('if (method == "setAlwaysOnTop")');
    final alwaysOnTopEnd =
        runner.indexOf('if (method == "setPinnedToDesktop")');
    final pinnedStart = alwaysOnTopEnd;
    final pinnedEnd = runner.indexOf('if (method == "setTitle")');
    final titleStart = pinnedEnd;
    final titleEnd = runner.indexOf('if (method == "setPaperSurfaces")');
    final boundsStart = runner.indexOf('if (method == "setBounds")');
    final boundsEnd = runner.indexOf('if (method == "getBounds")');

    expect(design, contains('Structured surface refreshes for a non-active'));
    expect(design, contains('without stealing the active paper'));
    expect(design, contains('moving the'));
    expect(design, contains('current host window'));
    expect(design, contains('changing the current host title'));
    expect(header, contains('void ApplyActivePaperBounds(HWND window);'));
    expect(showStart, isNonNegative);
    expect(showEnd, greaterThan(showStart));
    final showBlock = runner.substring(showStart, showEnd);
    expect(showBlock, contains('RememberActivePaperId(call.arguments())'));
    expect(showBlock, contains('ApplyActivePaperBounds(window)'));
    expect(alwaysOnTopStart, isNonNegative);
    expect(alwaysOnTopEnd, greaterThan(alwaysOnTopStart));
    final alwaysOnTopBlock = runner.substring(alwaysOnTopStart, alwaysOnTopEnd);
    expect(alwaysOnTopBlock, contains('target_paper_id'));
    expect(alwaysOnTopBlock, contains('RememberPaperAlwaysOnTop'));
    expect(alwaysOnTopBlock, contains('target_paper_id == active_paper_id_'));
    expect(alwaysOnTopBlock, isNot(contains('RememberActivePaperId')));
    expect(pinnedStart, isNonNegative);
    expect(pinnedEnd, greaterThan(pinnedStart));
    final pinnedBlock = runner.substring(pinnedStart, pinnedEnd);
    expect(pinnedBlock, contains('target_paper_id'));
    expect(pinnedBlock, contains('RememberPaperPinnedToDesktop'));
    expect(pinnedBlock, contains('target_paper_id == active_paper_id_'));
    expect(pinnedBlock, isNot(contains('RememberActivePaperId')));
    expect(titleStart, isNonNegative);
    expect(titleEnd, greaterThan(titleStart));
    final titleBlock = runner.substring(titleStart, titleEnd);
    expect(titleBlock, contains('structured_title'));
    expect(titleBlock, contains('requested_paper_id == active_paper_id_'));
    expect(titleBlock, contains('SetWindowTextW'));
    expect(titleBlock, contains('RememberPaperTitle'));
    expect(titleBlock, isNot(contains('RememberActivePaperId')));
    expect(boundsStart, isNonNegative);
    expect(boundsEnd, greaterThan(boundsStart));
    final boundsBlock = runner.substring(boundsStart, boundsEnd);
    expect(boundsBlock, contains('target_paper_id'));
    expect(boundsBlock, contains('RememberPaperBounds(target_paper_id'));
    expect(boundsBlock, contains('target_paper_id == active_paper_id_'));
    expect(boundsBlock, contains('SetWindowPos'));
    expect(boundsBlock, isNot(contains('RememberActivePaperId')));
  });

  test('Windows tray marks script capsule notes distinctly', () {
    final dartHost =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(dartHost, contains("'isScriptCapsule'"));
    expect(dartHost, contains('ScriptCapsuleSpec.isScriptCapsuleContent'));
    expect(dartHost,
        contains("'trayLabel': _trayPaperLabel(paper, title, labels)"));
    expect(runner, contains('? "script"'));
    expect(runner, contains('L"\\u26A1"'));
    expect(runner, contains('GetBoolArgument(*paper_map, "isScriptCapsule"'));
  });

  test('Windows runner validates external files before opening them', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(runner, contains('path = TrimAscii(path)'));
    expect(runner, contains('HasUnsafeExternalFilePathCharacter'));
    expect(runner, contains('FileExists'));
    expect(runner, contains('FILE_ATTRIBUTE_DIRECTORY'));
    expect(runner, contains('file_not_found'));
    expect(runner, contains('ShellExecuteW'));
  });

  test('Windows script capsule hosts validate launch requests', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final dartHost =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(design, contains('Script capsule hosts must reject blank scripts'));
    expect(design, contains('written completely'));
    expect(design, contains('Persistent PowerShell hosts'));
    expect(design, contains('Collapsed note papers whose content starts'));
    expect(design, contains('primary click runs the script'));
    expect(design, contains('secondary click opens the note for editing'));
    expect(design, contains('platform line terminator'));
    expect(app, contains('-script-capsule'));
    expect(app, contains('_collapsedScriptCapsule'));
    expect(app, contains('_openCollapsedScriptCapsuleForEditing'));
    expect(
      _readProjectText('lib/src/core/script/script_capsule.dart'),
      contains('Platform.lineTerminator'),
    );
    expect(dartHost, contains('Windows script capsule must not be blank.'));
    expect(dartHost, contains('Unsupported Windows script capsule engine.'));
    expect(runner, contains('IsAllowedScriptCapsuleEngine'));
    expect(runner, contains('invalid_script_capsule_engine'));
    expect(runner, contains('WriteAllToFile'));
    expect(runner, contains('MoveFileExW'));
    expect(runner, contains('DeleteFileW(script_path.c_str())'));
    expect(runner, contains('-NonInteractive'));
  });

  test('PaperTodo paper title editing rules are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final paperData = _readProjectText('lib/src/core/model/paper_data.dart');
    final windows =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final pubspec = _readProjectText('pubspec.yaml');

    expect(design, contains('Paper title editing should preserve PaperTodo'));
    expect(design, contains('40 text elements'));
    expect(design, contains('control characters are removed'));
    expect(design, contains('show as plain title\ntext by default'));
    expect(design, contains('Click to edit title'));
    expect(design, contains('restore the pre-edit title\non Escape'));
    expect(design, contains('23x24 leading control'));
    expect(design, contains('generic Material icon'));
    expect(design, contains('0.58 opacity'));
    expect(design, contains('38 and 86 pixels wide'));
    expect(design, contains('permanent\nbottom divider'));
    expect(design, contains('default 280px Todo and 320px Note'));
    expect(design, contains('structured window title updates'));
    expect(app, contains('class _PaperTitleEditor'));
    expect(app, contains('readOnly: !_isEditingTitle'));
    expect(app, contains('LogicalKeyboardKey.escape'));
    expect(app, contains('_titleBeforeEdit'));
    expect(app, contains('_PaperTitleTextInputFormatter'));
    expect(app, contains('class _PaperWindowTopmostGlyph'));
    expect(app, contains('widget.active || _hovered ? 1 : 0.58'));
    expect(app, contains("glyph: paper.isTodo ? '\\u2611' : '\\u270E'"));
    expect(app, contains("ValueKey('\${widget.paper.id}-title-host')"));
    expect(app, contains('minWidth: standaloneSurface ? 38 : 0'));
    expect(
        app,
        contains(
            'final showBaseActions = width >= (paper.isNote ? 230 : 180)'));
    expect(app, contains('final showUtility = width >= 210'));
    expect(app, contains('final showSync = width >= 400'));
    expect(app, contains('_paperTodoDesktopPinGlyph'));
    expect(app, contains("'assets/icons/pin.png'"));
    expect(app, contains("'assets/icons/unpin.png'"));
    expect(app, contains('opacity: pinned ? 1 : 0.72'));
    expect(pubspec, contains('assets/icons/pin.png'));
    expect(pubspec, contains('assets/icons/unpin.png'));
    expect(app, contains('PaperTitles.cleanCustomTitle(value)'));
    expect(app, contains('controller.paperTitleText(paper)'));
    expect(paperData, contains('PaperTitles.maxTitleLength'));
    expect(windows, contains('PaperTitles.effectiveTitle'));
    expect(windows, contains("'title': _windowTitle(paper)"));
    final titleStart = runner.indexOf('if (method == "setTitle")');
    final titleEnd = runner.indexOf('if (method == "setPaperSurfaces")');
    expect(titleStart, isNonNegative);
    expect(titleEnd, greaterThan(titleStart));
    final titleBlock = runner.substring(titleStart, titleEnd);
    final legacyStringRead = titleBlock.indexOf('std::get_if<std::string>');
    final mapRead = titleBlock.indexOf('std::get_if<flutter::EncodableMap>');
    expect(legacyStringRead, isNonNegative);
    expect(mapRead, greaterThan(legacyStringRead));
    expect(titleBlock, contains('GetStringArgument(*map, "title", title)'));
    expect(titleBlock, contains('requested_paper_id == active_paper_id_'));
    expect(titleBlock, isNot(contains('RememberActivePaperId')));
  });

  test('release script packages Windows and Android artifacts', () {
    final script = _readProjectText('scripts/release.ps1');
    final gradle = _readProjectText('android/app/build.gradle.kts');
    final releaseReadinessAudit =
        _readProjectText('scripts/release_readiness_audit.ps1');
    final signingScript =
        _readProjectText('scripts/configure_android_signing.ps1');
    final signingScriptTest =
        _readProjectText('test/configure_android_signing_test.dart');
    final androidSmokeScript = _readProjectText('scripts/android_smoke.ps1');
    final androidDeviceSmokeScript =
        _readProjectText('scripts/android_device_smoke.ps1');
    final windowsSmokeScript = _readProjectText('scripts/windows_smoke.ps1');
    final windowsPolicySmokeScript =
        _readProjectText('scripts/windows_policy_smoke.ps1');
    final windowsManualQaScript =
        _readProjectText('scripts/windows_manual_qa.ps1');
    final webDavSmokeScript = _readProjectText('scripts/webdav_smoke.ps1');
    final webDavLiveSmokeScript =
        _readProjectText('scripts/webdav_live_smoke.ps1');
    final webDavLiveSmokeDart = _readProjectText('tool/webdav_live_smoke.dart');
    final workflow = _readProjectText('.github/workflows/release.yml');
    final qaEvidenceWorkflow =
        _readProjectText('.github/workflows/qa-evidence.yml');
    final releaseAssetVerificationTest =
        _readProjectText('test/release_asset_verification_test.dart');
    final readme = _readProjectText('README.md');
    final development = _readProjectText('docs/DEVELOPMENT.md');
    final readinessReadJsonRecord = _sliceBetween(
      releaseReadinessAudit,
      'function Read-JsonRecord',
      'function Test-UtcTimestamp',
    );
    final releaseReadQaRecord = _sliceBetween(
      script,
      'function Read-ReleaseQaRecord',
      'function Assert-WindowsSmokeReleaseDirectory',
    );

    expect(
      releaseReadinessAudit,
      contains(
          'Release readiness audit result JSON path must use the .json extension.'),
    );
    expect(
      releaseReadinessAudit,
      contains(
        'Release readiness audit result JSON path must not contain wildcard characters.',
      ),
    );
    expect(releaseReadinessAudit, contains('function Resolve-InputJsonPath'));
    expect(
      releaseReadinessAudit,
      contains(r'$Context JSON path must use the .json extension.'),
    );
    expect(
      readinessReadJsonRecord,
      contains(r'Resolve-InputJsonPath -Path $Path -Context $Context'),
    );
    expect(
      readinessReadJsonRecord,
      isNot(contains(r'[IO.Path]::GetFullPath($Path)')),
    );
    expect(script, contains('function Resolve-ReleaseQaJsonPath'));
    expect(
      script,
      contains(r'$Context result JSON path must use the .json extension.'),
    );
    expect(
      releaseReadQaRecord,
      contains(r'Resolve-ReleaseQaJsonPath -Path $Path -Context $Context'),
    );
    expect(
      releaseReadQaRecord,
      isNot(contains(r'Get-Content -Raw -LiteralPath $Path')),
    );
    expect(
      releaseAssetVerificationTest,
      contains(
        'release packaging rejects unsafe QA result JSON paths before reading',
      ),
    );
    expect(script, contains('function Clear-ProxyEnvironment'));
    expect(script, contains(r'Remove-Item -LiteralPath "Env:\$name"'));
    expect(script, contains('Android SDK tools parse empty proxy variables'));
    expect(script, contains('Clear-ProxyEnvironment'));
    expect(script, isNot(contains(r'$env:HTTPS_PROXY = ""')));
    expect(script, isNot(contains(r'$env:HTTP_PROXY = ""')));
    expect(script, isNot(contains(r'$env:ALL_PROXY = ""')));
    expect(script, contains('flutter.bat'));
    expect(script, contains(r'[switch]$OfflinePubGet'));
    expect(script, contains(r'[switch]$AllowDirty'));
    expect(script, contains(r'[switch]$RunAndroidDeviceSmoke'));
    expect(script, contains(r'[string]$AndroidDeviceSerial = ""'));
    expect(script, contains(r'[string]$AndroidDeviceSmokeResultJson = ""'));
    expect(script, contains(r'[string]$WindowsManualQaResultJson = ""'));
    expect(script, contains(r'[string]$WebDavLiveSmokeResultJson = ""'));
    expect(
      script,
      contains(r'[string]$WebDavDomesticLiveSmokeResultJson = ""'),
    );
    expect(script, contains('function Invoke-Native'));
    expect(script, contains('function Assert-CleanGitTree'));
    expect(script, contains('function Assert-GitDiffCheck'));
    expect(script, contains('function Assert-PathExists'));
    expect(script, contains('function Assert-FileExists'));
    expect(script, contains('function Assert-FileExtension'));
    expect(script, contains('function Find-AndroidSdkTool'));
    expect(script, contains('function Get-ApkManifestInteger'));
    expect(script, contains('function Assert-AndroidApkSdkCompatibility'));
    expect(script, contains('function Assert-ReleaseChecksumFile'));
    expect(script, contains('function Assert-ReleaseMetadataFile'));
    expect(script, contains('function Assert-ReleaseMetadataRecord'));
    expect(script, contains('function Assert-ReleaseMetadataRecords'));
    expect(script, contains('function Assert-ReleaseMetadataStringSequence'));
    expect(script, contains('function Assert-WindowsManualQaArtifact'));
    expect(script, contains('function Get-AndroidKeyProperty'));
    expect(script, contains('function Assert-AndroidKeyPropertyValue'));
    expect(script, contains('function Assert-AndroidStoreFileValue'));
    expect(script, contains('function Resolve-AndroidKeystorePath'));
    expect(script, contains('function Get-GradleIntegerAssignment'));
    expect(script, contains('function Get-AndroidSdkConfig'));
    expect(script, contains('function Assert-AndroidSdkCompatibility'));
    expect(script, contains('function Assert-PublishableReleaseOptions'));
    expect(script, contains('function Assert-PublishableReleaseQaOptions'));
    expect(script, contains('function Assert-PublishableReleaseQaRecords'));
    expect(
      script,
      contains(
        'GitHub Release publishing requires Android release signing from android/key.properties',
      ),
    );
    expect(
      script,
      contains(
        'GitHub Release publishing requires Windows manual QA evidence.',
      ),
    );
    expect(
      script,
      contains(
        'GitHub Release publishing requires generic WebDAV live smoke evidence.',
      ),
    );
    expect(
      script,
      contains(
        'GitHub Release publishing requires domestic WebDAV live smoke evidence.',
      ),
    );
    expect(
      script,
      contains(
        'GitHub Release publishing requires Android runtime smoke evidence.',
      ),
    );
    expect(
      script,
      contains(
        'Use either -RunAndroidDeviceSmoke or -AndroidDeviceSmokeResultJson, not both.',
      ),
    );
    expect(
      script,
      contains(
        'GitHub Release publishing requires a passed Windows manual QA record.',
      ),
    );
    expect(
      script,
      contains(
        'GitHub Release publishing requires a passed generic WebDAV live smoke record.',
      ),
    );
    expect(
      script,
      contains(
        'GitHub Release publishing requires a passed domestic WebDAV live smoke record.',
      ),
    );
    expect(
      script,
      contains(
        'GitHub Release publishing requires a passed Android device smoke record.',
      ),
    );
    expect(script, contains(r'-AndroidSigningMode $androidSigningMode'));
    expect(script, contains('Assert-PublishableReleaseQaOptions `'));
    expect(script, contains('Assert-PublishableReleaseQaRecords `'));
    expect(
        script,
        contains(
            r'-AndroidDeviceSmokeResultJson $AndroidDeviceSmokeResultJson'));
    expect(script, contains('function Assert-GitHubAuthentication'));
    expect(script, contains('function Assert-GitHubReleaseGitState'));
    expect(script, contains('function Assert-GitHubReleaseTagState'));
    expect(script, contains('function Assert-GitHubReleaseAssets'));
    expect(script, contains('function Assert-GitHubReleaseDownloadedAssets'));
    expect(script, contains(r'gh release view $TagName --json assets'));
    expect(script, contains(r'gh release download $TagName'));
    expect(script, contains('GitHub Release asset metadata'));
    expect(
      script,
      contains('Downloaded GitHub Release asset'),
    );
    expect(
      script,
      contains('SHA-256 does not match the packaged file.'),
    );
    expect(script, contains('did not return an asset list'));
    expect(script, contains(r'$expectedAssetNames'));
    expect(script, contains(r'$unexpectedAssets'));
    expect(script, contains('contains unexpected asset(s)'));
    expect(script, contains('Remove stale release assets'));
    expect(script, contains('expected exactly one'));
    expect(script, contains(r"asset '$($item.Name)' is missing its size"));
    expect(script, contains('size does not match the packaged file'));
    expect(script, contains('is missing its upload state'));
    expect(script, contains('is not fully uploaded'));
    expect(script, contains('function Invoke-NativeText'));
    expect(script, contains(r'$env:GITHUB_ACTIONS -eq "true"'));
    expect(script, contains(r'$env:GITHUB_REF_NAME -eq "main"'));
    expect(
      script,
      contains('GitHub Release publishing from GitHub Actions must run'),
    );
    expect(script, contains('git update-index --refresh'));
    expect(script, contains('stat-only status noise'));
    expect(script, contains('git diff --quiet --'));
    expect(script, contains('git diff --cached --quiet --'));
    expect(script, contains('git ls-files --others --exclude-standard'));
    expect(script, contains('Dirty git status:'));
    expect(script, contains('git status --porcelain --untracked-files=all'));
    expect(script, contains('Verify release inputs stayed clean'));
    expect(script, contains('git diff --check'));
    expect(script, contains('git diff --cached --check'));
    expect(script, contains('git fetch origin main'));
    expect(script, contains('git rev-parse --abbrev-ref HEAD'));
    expect(script, contains('git rev-parse --verify origin/main'));
    expect(script, contains('git ls-remote --tags origin'));
    expect(script, contains('Working tree has uncommitted changes'));
    expect(script, contains('local-only test package'));
    expect(script, contains('GitHub Release publishing requires a clean'));
    expect(script, contains('fully validated build'));
    expect(script, contains('GitHub Release publishing must run from'));
    expect(script, contains('local HEAD to match origin/main'));
    expect(script, contains('already points to'));
    expect(script, contains('Bump the version or retarget the tag'));
    expect(script, contains(r"Remove $($blockedOptions -join ', ')"));
    expect(
      development,
      contains(r'.\scripts\release.ps1 -AllowDirty -SkipTests'),
    );
    expect(development, contains('local verification only'));
    expect(
      development,
      contains('verifies the copied APK manifest with `apkanalyzer`'),
    );
    expect(
      development,
      contains('same resolved Android SDK `aapt2` binary'),
    );
    expect(readme, contains('resolves both `apkanalyzer` and `aapt2`'));
    expect(
      readme,
      contains('passes\nthose exact tools into Android smoke validation'),
    );
    expect(
      development,
      contains('Do not use `-AllowDirty` or `-SkipTests`'),
    );
    expect(script, contains(r'failed with exit code $LASTEXITCODE'));
    expect(script, contains('function Get-PackageResolutionMode'));
    expect(script, contains('function Get-FlutterToolchainInfo'));
    expect(script, contains('function Format-ReleaseNotesCommandList'));
    expect(script, contains('function Assert-FlutterVersion'));
    expect(script, contains('function Get-ReleaseArtifactVersion'));
    expect(script, contains('function Assert-ReleaseTagName'));
    expect(script, contains('function Assert-ReleaseTitle'));
    expect(script, contains('function Assert-PublishTagMatchesVersion'));
    expect(script, contains('flutter --version --machine'));
    expect(script, contains('Flutter toolchain metadata is missing'));
    expect(
      script,
      contains('safe for release metadata, tags, and artifact names'),
    );
    expect(script, contains('Release artifact version'));
    expect(script, contains('safe for artifact file names'));
    expect(script, contains('git check-ref-format'));
    expect(
      script,
      contains('GitHub Release tag must not contain whitespace'),
    );
    expect(
      script,
      contains('GitHub Release title must not contain control characters'),
    );
    expect(
      script,
      contains(
        'GitHub Release title must not contain leading or trailing whitespace',
      ),
    );
    expect(
      script,
      contains('GitHub Release tag must match pubspec.yaml version'),
    );
    expect(
      script,
      contains(
          r'$artifactVersion = Get-ReleaseArtifactVersion -Version $version'),
    );
    expect(script, contains(r'return "skipped (both -SkipTests'));
    expect(script, contains(r'return "flutter pub get"'));
    expect(
      script,
      contains(r'return "flutter pub get --offline"'),
    );
    expect(script, contains('Dirty working tree allowed:'));
    expect(script, contains('Package resolution:'));
    expect(script, contains('Flutter toolchain: Flutter'));
    expect(script, contains('Android APK analyzer:'));
    expect(script, contains(r'$aapt2ToolName = if ($IsWindows'));
    expect(script, contains(r'$aapt2 = Find-AndroidSdkTool'));
    expect(script, contains(r'$androidSdkTools = [ordered]@{'));
    expect(script, contains(r'apkAnalyzer = $apkAnalyzer'));
    expect(script, contains(r'aapt2 = $aapt2'));
    expect(script, contains(r'$androidStaticSmokeResultFile ='));
    expect(script, contains(r'$androidStaticSmokeRecord = [ordered]@{}'));
    expect(script, contains(r'$androidDeviceSmokeRecord = [ordered]@{'));
    expect(script, contains(r'$windowsManualQaRecord = [ordered]@{'));
    expect(script, contains(r'$webDavLiveSmokeRecord = [ordered]@{'));
    expect(script, contains(r'$webDavDomesticLiveSmokeRecord = [ordered]@{'));
    expect(
      script,
      contains(r'checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")'),
    );
    expect(script, contains('optional; pass -RunAndroidDeviceSmoke'));
    expect(script, contains('optional; pass -WindowsManualQaResultJson'));
    expect(script, contains('optional; pass -WebDavLiveSmokeResultJson'));
    expect(
      script,
      contains('optional; pass -WebDavDomesticLiveSmokeResultJson'),
    );
    expect(script, contains('Android AAPT2:'));
    expect(script, contains('Validation executed:'));
    expect(script, contains('Validation skipped:'));
    expect(script, contains(r'& $flutter pub get --offline'));
    expect(script, contains(r'& $flutter test --no-pub'));
    expect(script, contains(r'& $flutter analyze --no-pub'));
    expect(script, contains(r'& $flutter build windows --release --no-pub'));
    expect(script, contains(r'& $flutter build apk --release --no-pub'));
    expect(script, contains('Get-AndroidSigningMode'));
    expect(
      script,
      contains(
        'debug fallback (android/key.properties storeFile not found)',
      ),
    );
    expect(
      script,
      contains(
        'Android signing property',
      ),
    );
    expect(script, contains('must not contain control characters'));
    expect(
      script,
      contains('Android signing storeFile must not contain wildcard'),
    );
    expect(
      script,
      contains('Android signing storeFile must not contain dot-segments'),
    );
    expect(script, contains('[IO.Path]::GetFullPath'));
    expect(
      script,
      contains('Android signing storeFile path is invalid'),
    );
    expect(
      script,
      contains(r'Test-Path -LiteralPath $keystorePath -PathType Leaf'),
    );
    expect(script, contains(r'Android signing mode: $androidSigningMode'));
    expect(script, contains(r'Android signing: $androidSigningMode.'));
    expect(script, contains('Android SDK config: compileSdk='));
    expect(script, contains('Android 14-17 / API 34-37'));
    expect(
      script,
      contains(
        'Android SDK compatibility must remain Android 14-17 / API 34-37',
      ),
    );
    expect(script, contains('apkanalyzer manifest'));
    expect(script, contains('min-sdk'));
    expect(script, contains('target-sdk'));
    expect(script, contains('scripts/windows_smoke.ps1'));
    expect(script, contains('windows_smoke.ps1'));
    expect(script, contains('Run Windows release smoke'));
    expect(script, contains('scripts/windows_policy_smoke.ps1'));
    expect(script, contains('Run Windows policy smoke'));
    expect(script, contains(r'$windowsPolicySmokeRecord = [ordered]@{}'));
    expect(script, contains('windowsPolicySmokeRecord'));
    expect(script, contains(r'policySmoke = $windowsPolicySmokeRecord'));
    expect(
      windowsPolicySmokeScript,
      contains('trayIconRecoveredAfterTaskbarCreated'),
    );
    expect(windowsPolicySmokeScript, contains('fullscreenAvoidance'));
    expect(windowsPolicySmokeScript, contains('fullscreenTopmostRestored'));
    expect(windowsPolicySmokeScript, contains('RePaperTodo.PaperShadow'));
    expect(windowsPolicySmokeScript, contains('longRunningScriptCapsule'));
    expect(windowsPolicySmokeScript, contains('borderlessResizableWindow'));
    expect(windowsPolicySmokeScript, contains('taskSwitcherVisibility'));
    expect(windowsPolicySmokeScript, contains('capsuleEdgeDocking'));
    expect(windowsPolicySmokeScript, contains('capsuleWindowWidth'));
    expect(windowsPolicySmokeScript, contains('capsuleRestingVisibleWidth'));
    expect(windowsPolicySmokeScript, contains('capsuleHoverVisibleWidth'));
    expect(
      windowsPolicySmokeScript,
      contains(
        r'FindWindowByTitle([uint32]$primary.Id, "Policy")',
      ),
    );
    expect(
      windowsPolicySmokeScript,
      contains("Selecting by size made this assertion depend on"),
    );
    expect(windowsPolicySmokeScript, contains('BroadcastTaskbarCreated'));
    expect(windowsPolicySmokeScript, contains('Start-FullscreenProbe'));
    expect(
      releaseReadinessAudit,
      contains(
        'Release metadata must prove Windows window styles, task-switcher visibility, capsule docking, tray recovery, fullscreen policy, and long-running scripts.',
      ),
    );
    expect(
      script,
      contains(
          r'-ReleaseDirectory (Join-Path $repoRoot "build\windows\x64\runner\Release")'),
    );
    expect(script, contains('scripts/webdav_smoke.ps1'));
    expect(script, contains('webdav_smoke.ps1'));
    expect(script, contains('Run WebDAV static smoke'));
    expect(script, contains(r'$webDavSmokeResultFile ='));
    expect(script, contains(r'$webDavSmokeRecord = [ordered]@{}'));
    expect(script, contains(r'-ResultJson $webDavSmokeResultFile'));
    expect(script,
        contains('WebDAV static smoke result JSON could not be parsed'));
    expect(script, contains(r'$webDavSmokeRecord[$property.Name]'));
    expect(
        script, contains(r'Remove-Item -LiteralPath $webDavSmokeResultFile'));
    expect(script, contains('scripts/android_smoke.ps1'));
    expect(script, contains('android_smoke.ps1'));
    expect(script, contains('scripts/android_device_smoke.ps1'));
    expect(script, contains('-RunAndroidDeviceSmoke'));
    expect(
      script,
      contains(
        'scripts/android_device_smoke.ps1 (optional; pass -RunAndroidDeviceSmoke)',
      ),
    );
    expect(
      script,
      contains(
        r'scripts/android_device_smoke.ps1 result: $AndroidDeviceSmokeResultJson',
      ),
    );
    expect(script, contains('-Context "Android device smoke"'));
    expect(
      script,
      contains(r'-ExpectedApkFileName ([IO.Path]::GetFileName($androidApk))'),
    );
    expect(script, contains(r'$androidDeviceSmokeArgs = @{'));
    expect(script, contains(r'ApkPath = $androidApk'));
    expect(script, contains(r'-ResultJson $androidStaticSmokeResultFile'));
    expect(script, contains(r'$androidStaticSmokeResult ='));
    expect(script,
        contains('Android static smoke result JSON could not be parsed'));
    expect(script, contains(r'$androidStaticSmokeRecord[$property.Name]'));
    expect(script,
        contains(r'Remove-Item -LiteralPath $androidStaticSmokeResultFile'));
    expect(script, contains(r'ResultJson = $androidDeviceSmokeResultFile'));
    expect(
      script,
      contains(
          r'$androidDeviceSmokeArgs["DeviceSerial"] = $AndroidDeviceSerial'),
    );
    expect(script, contains(r'@androidDeviceSmokeArgs'));
    expect(script, contains(r'$androidDeviceSmokeResult ='));
    expect(script,
        contains('Android device smoke result JSON could not be parsed'));
    expect(script, contains(r'$androidDeviceSmokeRecord[$property.Name]'));
    expect(script,
        contains(r'Remove-Item -LiteralPath $androidDeviceSmokeResultFile'));
    expect(script, contains(r'$AndroidDeviceSerial'));
    expect(script, contains('scripts/windows_manual_qa.ps1 result:'));
    expect(
      script,
      contains(
        'scripts/windows_manual_qa.ps1 (optional; pass -WindowsManualQaResultJson <path>)',
      ),
    );
    expect(script, contains('scripts/webdav_live_smoke.ps1 result:'));
    expect(
      script,
      contains(
        'scripts/webdav_live_smoke.ps1 (optional; pass -WebDavLiveSmokeResultJson <path>)',
      ),
    );
    expect(script, contains('scripts/webdav_live_smoke.ps1 domestic result:'));
    expect(
      script,
      contains(
        'scripts/webdav_live_smoke.ps1 domestic (optional; pass -WebDavDomesticLiveSmokeResultJson <path>)',
      ),
    );
    expect(
      script,
      contains(r'$Context result JSON could not be parsed'),
    );
    expect(script, contains('-Context "Windows manual QA"'));
    expect(script, contains('-Context "generic WebDAV live smoke"'));
    expect(script, contains('-Context "domestic WebDAV live smoke"'));
    expect(script, contains(r'-Aapt2 $aapt2'));
    expect(script, contains(r'-ExpectedMinSdk $androidSdkConfig["minSdk"]'));
    expect(
      script,
      contains(r'-ExpectedTargetSdk $androidSdkConfig["targetSdk"]'),
    );
    expect(
      script,
      contains(r'-ExpectedCompileSdk $androidSdkConfig["compileSdk"]'),
    );
    expect(
      script,
      contains('Android release APK manifest must match Android 14-17'),
    );
    expect(script, contains('compileSdk = Get-GradleIntegerAssignment'));
    expect(script, contains('compatibility = "Android 14-17 / API 34-37"'));
    expect(script, contains('function New-ZipFromDirectory'));
    expect(script, contains('ZipArchiveMode]::Create'));
    expect(script, contains('CreateEntryFromFile'));
    expect(script, contains(r'$entryName = $relativePath.Replace("\", "/")'));
    expect(script, contains('Get-FileHash -Algorithm SHA256'));
    expect(script, contains(r'Set-Content -LiteralPath $checksumsFile'));
    expect(script, contains(r'repapertodo-windows-x64-$artifactVersion.zip'));
    expect(script, contains(r'repapertodo-android-$artifactVersion.apk'));
    expect(script, contains(r'repapertodo-$artifactVersion-sha256.txt'));
    expect(script, contains(r'repapertodo-$artifactVersion-release.json'));
    expect(script, contains(r'repapertodo-$artifactVersion-release-notes.md'));
    expect(
        script,
        contains(
            r'$windowsReleaseExe = Join-Path $windowsReleaseDir "repapertodo.exe"'));
    expect(script, contains('Windows release build output was not found'));
    expect(script, contains('Windows release executable was not found'));
    expect(script, contains('Android release APK was not found'));
    expect(script, contains('Android release artifact must be an .apk file'));
    expect(script, contains('-ExpectedExtension ".apk"'));
    expect(script, contains('function Assert-ZipContainsFile'));
    expect(script, contains('function Assert-ZipContainsFilePattern'));
    expect(script, contains('function Assert-ZipDoesNotContainFile'));
    expect(script, contains('function Assert-ZipDoesNotContainFilePattern'));
    expect(script, contains('function Remove-WindowsRuntimeStateFiles'));
    expect(script, contains('function Assert-ZipEntriesSafe'));
    expect(script, contains('function Assert-ReleaseArtifactFileName'));
    expect(script, contains('function Assert-ReleaseSha256'));
    expect(script, contains('function Assert-ReleaseByteCount'));
    expect(script, contains('function Assert-ReleaseRecordFields'));
    expect(script, contains('function Get-RecordPropertyValue'));
    expect(script, contains('function Assert-RecordUtcTimestamp'));
    expect(script, contains('function Assert-WindowsManualQaRecord'));
    expect(script, contains('Windows manual QA repapertodo.exe'));
    expect(script, contains('Windows manual QA data/app.so'));
    expect(
      script,
      contains('SHA-256 does not match the current Windows release build.'),
    );
    expect(
      script,
      contains('byte count does not match the current Windows release build.'),
    );
    expect(script, contains(r'-ExpectedExePath $windowsReleaseExe'));
    expect(
      script,
      contains(
          r'-ExpectedAppSoPath (Join-Path $windowsReleaseDir "data\app.so")'),
    );
    expect(
      script,
      contains(
        'Windows manual QA record releaseDirectory must match the Windows release build output.',
      ),
    );
    expect(script, contains('function Assert-WebDavLiveSmokeRecord'));
    expect(script, contains('function Read-ReleaseQaRecord'));
    expect(script, contains('function Assert-AndroidStaticSmokeRecord'));
    expect(
      script,
      contains(
          'artifact file name must not contain leading or trailing whitespace'),
    );
    expect(script, contains('must be a safe single file name'));
    expect(
      script,
      contains('SHA-256 hash must be 64 lowercase hexadecimal characters'),
    );
    expect(script, contains('byte count must be a positive integer'));
    expect(script, contains('[IO.Compression.ZipFile]::OpenRead'));
    expect(script, contains('Windows release zip does not contain'));
    expect(script, contains('Windows release zip contains unsafe entry paths'));
    expect(script, contains('Android release APK contains unsafe entry paths'));
    expect(script, contains('contains control characters'));
    expect(script, contains(r'$trimmedSegment = $segment.Trim()'));
    expect(script, contains(r'$segment -ne $trimmedSegment'));
    expect(
      script,
      contains('contains blank, whitespace-padded, or unsafe path segments'),
    );
    expect(script, contains(r'$windowsStagingDir'));
    expect(script, contains('Remove-WindowsRuntimeStateFiles'));
    expect(script, contains('data.backup.json'));
    expect(script, contains('data.crash_recovery.json'));
    expect(script, contains('RePaperTodo.crash.log'));
    expect(script, contains('fullscreen-debug.log'));
    expect(script, contains('*.failed_load.*'));
    expect(script, contains('*.used_for_recovery.*'));
    expect(script, contains('Windows release zip must not contain runtime'));
    expect(script, contains('flutter_windows.dll'));
    expect(script, contains('data/app.so'));
    expect(script, contains('data/icudtl.dat'));
    expect(script, contains('data/flutter_assets/FontManifest.json'));
    expect(script, contains('Android release APK does not contain'));
    expect(script, contains('AndroidManifest.xml'));
    expect(script, contains('assets/flutter_assets/AssetManifest.bin'));
    expect(script, contains('assets/flutter_assets/FontManifest.json'));
    expect(script, contains('lib/*/libapp.so'));
    expect(script, contains('lib/*/libflutter.so'));
    expect(script, contains('ConvertTo-Json -Depth 5'));
    expect(script, contains('git rev-parse HEAD'));
    expect(script, contains('dirtyWorkingTreeAllowed'));
    expect(script, contains(r'dirtyWorkingTreeAllowed = [bool]$AllowDirty'));
    expect(script, contains(r'$supportedRuntimeLanguages = @("zh", "en")'));
    expect(script, contains('Get-RuntimeSupportedLanguages -RepoRoot'));
    expect(script, contains('Assert-RuntimeSupportedLanguages'));
    expect(
      script,
      contains(
          r'Write-Host "Runtime UI languages: $($validatedRuntimeLanguages -join '),
    );
    expect(script, contains(r'packageResolution = $packageResolution'));
    expect(script, contains(r'toolchain = $toolchainInfo'));
    expect(script, contains(r'tools = $androidSdkTools'));
    expect(script, contains(r'webDav = [ordered]@{'));
    expect(script, contains(r'staticSmoke = $webDavSmokeRecord'));
    expect(script, contains(r'liveSmoke = $webDavLiveSmokeRecord'));
    expect(script, contains(r'staticSmoke = $androidStaticSmokeRecord'));
    expect(script, contains(r'deviceSmoke = $androidDeviceSmokeRecord'));
    expect(script, contains('runtime = [ordered]@{'));
    expect(
      script,
      contains(r'supportedLanguages = $validatedRuntimeLanguages'),
    );
    expect(script, contains(r'-AndroidSdkTools $androidSdkTools'));
    expect(
      script,
      contains(r'-AndroidStaticSmokeRecord $androidStaticSmokeRecord'),
    );
    expect(
      script,
      contains(r'-AndroidDeviceSmokeRecord $androidDeviceSmokeRecord'),
    );
    expect(
      script,
      contains(r'-WindowsSmokeRecord $windowsSmokeRecord'),
    );
    expect(
      script,
      contains(r'-WindowsManualQaRecord $windowsManualQaRecord'),
    );
    expect(
      script,
      contains(r'-WebDavSmokeRecord $webDavSmokeRecord'),
    );
    expect(
      script,
      contains(r'-WebDavLiveSmokeRecord $webDavLiveSmokeRecord'),
    );
    expect(
      script,
      contains(r'-SupportedRuntimeLanguages $validatedRuntimeLanguages'),
    );
    expect(script,
        contains(r'$pubspecLockPath = Join-Path $repoRoot "pubspec.lock"'));
    expect(script, contains('pubspec.lock was not found'));
    expect(script, contains(r'$pubspecLockHash = Get-FileHash'));
    expect(script, contains('dependencyLock'));
    expect(script, contains(r'$dependencyLockRecord = [ordered]@{'));
    expect(script, contains('builtAtUtc'));
    expect(script, contains(r'$builtAtUtc.Offset'));
    expect(
      script,
      contains('Release metadata JSON builtAtUtc must be a UTC timestamp.'),
    );
    expect(script, contains('windows = [ordered]'));
    expect(script, contains(r'smoke = $windowsSmokeRecord'));
    expect(script, contains(r'manualQa = $windowsManualQaRecord'));
    expect(script, contains('function Assert-WindowsSmokeReleaseDirectory'));
    expect(script, contains('function Assert-WindowsSmokeRecord'));
    expect(script, contains('function Assert-RepositoryEvidenceFile'));
    expect(
      script,
      contains('WebDAV static smoke evidence file'),
    );
    expect(
      script,
      contains('must be repository-relative'),
    );
    expect(
      script,
      contains('must not contain dot-segments'),
    );
    expect(
      script,
      contains('must stay inside the repository'),
    );
    expect(
      script,
      contains('was not found'),
    );
    expect(script, contains('Release metadata JSON windows is missing'));
    expect(script, contains('Release metadata JSON windows.smoke is missing'));
    expect(
      script,
      contains('Release metadata JSON windows.manualQa is missing'),
    );
    expect(
      script,
      contains('Windows smoke record must have status \'passed\'.'),
    );
    expect(
      script,
      contains('Windows smoke record checkedAtUtc must be a UTC timestamp.'),
    );
    expect(
      script,
      contains('Windows smoke record exeFileName must be repapertodo.exe.'),
    );
    expect(
      script,
      contains(
        'Windows smoke record releaseDirectory must match the Windows release build output.',
      ),
    );
    expect(
      script,
      contains(
        'Windows smoke record releaseDirectory is missing a required release file',
      ),
    );
    expect(
      script,
      contains(
        'Windows smoke record releaseDirectory is missing the Flutter data directory',
      ),
    );
    expect(
      script,
      contains('Windows smoke record initialPaperCount must be at least 1.'),
    );
    expect(
      script,
      contains('Windows smoke record finalPaperCount must be at least 3.'),
    );
    expect(
      script,
      contains(
          'Windows smoke record finalNotePaperCount must be greater than initialNotePaperCount after --new-note.'),
    );
    expect(
      script,
      contains(
          'Windows smoke record finalTodoPaperCount must be greater than initialTodoPaperCount after --new-todo.'),
    );
    expect(
      script,
      contains('windows.smoke.secondaryStartupCommands'),
    );
    expect(script, contains('windows.smoke.hiddenStartupCommands'));
    expect(script, contains('windows.smoke.ignoredSecondaryStartupCommands'));
    expect(
      script,
      contains(
          'Windows smoke record visiblePaperCountAfterIgnoredCommand must remain 0 after an unknown secondary startup command.'),
    );
    expect(
      script,
      contains(
        r'Release metadata JSON windows.smoke.$property does not match',
      ),
    );
    expect(
      script,
      contains(
        r'Assert-WindowsSmokeRecord -Record $metadata.windows.smoke -RepoRoot $RepoRoot',
      ),
    );
    expect(
      script,
      contains(
        r'Assert-WindowsManualQaRecord -Record $metadata.windows.manualQa',
      ),
    );
    expect(
      script,
      contains(
        r'Release metadata JSON windows.manualQa.$property does not match',
      ),
    );
    expect(
      script,
      contains(
          "Windows manual QA record must have status 'passed', 'passedWithDeferredMultiMonitor', or 'skipped'."),
    );
    expect(
      script,
      contains('Skipped Windows manual QA record must include a reason.'),
    );
    expect(
      script,
      contains('Windows manual QA record tester must not be blank.'),
    );
    expect(
      script,
      contains('Windows manual QA record windowsVersion must not be blank.'),
    );
    expect(
      script,
      contains('Windows manual QA record exeFileName must be repapertodo.exe.'),
    );
    expect(script, contains('function Assert-WebDavSmokeRecord'));
    expect(script, contains('Release metadata JSON webDav is missing'));
    expect(
      script,
      contains('Release metadata JSON webDav.staticSmoke is missing'),
    );
    expect(
      script,
      contains('Release metadata JSON webDav.liveSmoke is missing'),
    );
    expect(
      script,
      contains('Release metadata JSON webDav.domesticLiveSmoke is missing'),
    );
    expect(
      script,
      contains('WebDAV static smoke record must have status \'passed\'.'),
    );
    expect(
      script,
      contains(
        'WebDAV static smoke record checkedAtUtc must be a UTC timestamp.',
      ),
    );
    expect(script, contains('genericWebDavSupported'));
    expect(script, contains('jianguoyunPresetSupported'));
    expect(script, contains('encryptedPayloadsRequired'));
    expect(script, contains('operationLogsSupported'));
    expect(script, contains('crossDeviceOperationRoundTripCovered'));
    expect(script, contains('localHttpWebDavRoundTripCovered'));
    expect(script, contains('sharedWindowsAndroidSettings'));
    expect(script, contains('androidBackgroundSyncSharedDartPath'));
    expect(script, contains('androidBackgroundSyncRegistrationCovered'));
    expect(
      script,
      contains('androidBackgroundSyncAbsoluteStatePathCovered'),
    );
    expect(
      script,
      contains('androidBackgroundSyncDataJsonStatePathCovered'),
    );
    expect(script, contains('webDav.staticSmoke.evidenceFiles'));
    expect(script, contains('lib/src/sync/android_background_sync.dart'));
    expect(script, contains('test/android_background_sync_test.dart'));
    expect(
      script,
      contains('Assert-RepositoryEvidenceFile `'),
    );
    expect(
      script,
      contains('-Context "WebDAV static smoke evidence file"'),
    );
    expect(
      script,
      contains(
        r'Release metadata JSON webDav.staticSmoke.$property does not match',
      ),
    );
    expect(
      script,
      contains(r'-ExpectedProviderId "custom"'),
    );
    expect(script, contains(r'-ExpectedProviderId "jianguoyun"'));
    expect(
      script,
      contains(
        r'Release metadata JSON webDav.liveSmoke.$property does not match',
      ),
    );
    expect(
      script,
      contains(
        r'Release metadata JSON webDav.domesticLiveSmoke.$property does not match',
      ),
    );
    expect(
      script,
      contains(
          "WebDAV live smoke record must have status 'passed' or 'skipped'."),
    );
    expect(
      script,
      contains('Skipped WebDAV live smoke record must include a reason.'),
    );
    expect(
      script,
      contains('WebDAV live smoke record must confirm Windows upload.'),
    );
    expect(
      script,
      contains('WebDAV live smoke record must include deviceSequences.'),
    );
    expect(
      script,
      contains(
        r'WebDAV live smoke record must include a positive $deviceId device sequence.',
      ),
    );
    expect(script, contains('Assert-ReleaseMetadataFile'));
    expect(script, contains(r'-RepoRoot $repoRoot'));
    expect(script, contains(r'-DependencyLockRecord $dependencyLockRecord'));
    expect(script, contains(r'-ReleaseNotesRecord $releaseNotesRecord'));
    expect(script, contains(r'-ValidationExecuted $validationExecuted'));
    expect(script, contains(r'-ValidationSkipped $validationSkipped'));
    expect(script, contains(r'-ArtifactRecords $artifactRecords'));
    expect(script, contains(r'Set-Content -LiteralPath $releaseNotesFile'));
    expect(script, contains('- Windows manual QA:'));
    expect(script, contains('- WebDAV generic live smoke:'));
    expect(script, contains('- WebDAV domestic live smoke:'));
    expect(script, contains(r'$windowsManualQaSummary'));
    expect(script, contains(r'$webDavLiveSmokeSummary'));
    expect(script, contains('Release notes file was not created'));
    expect(script, contains('Release notes file must not be empty'));
    expect(script, contains(r'$metadataHash = Get-FileHash'));
    expect(script, contains(r'$releaseNotesHash ='));
    expect(script, contains(r'$releaseNotesRecord = [ordered]@{'));
    expect(script, contains(r'releaseNotes = $releaseNotesRecord'));
    expect(script, contains('-Name "releaseNotes"'));
    expect(script, contains(r'$releasePackageRecords = $artifactRecords'));
    expect(script, contains(r'fileName = $releaseNotesItem.Name'));
    expect(script, contains(r'$releasePackageRecords |'));
    expect(script, contains('Assert-ReleaseChecksumFile'));
    expect(
      script,
      contains('-Context "Release checksum"'),
    );
    expect(
      script,
      contains('-Context "Release metadata JSON'),
    );
    expect(script, contains(r'-ArtifactDirectory $dist'));
    expect(script, contains("references missing artifact"));
    expect(script, contains('size changed after checksum generation'));
    expect(script, contains('hash changed after checksum generation'));
    expect(script, contains('does not match the packaged artifact hash'));
    expect(
      script,
      contains('Release metadata JSON version does not match pubspec.yaml'),
    );
    expect(script, contains('releaseNotes'));
    expect(
      script,
      contains('Release metadata JSON Android settings do not match'),
    );
    expect(script, contains('Release metadata JSON android.tools is missing'));
    expect(
      script,
      contains('Release metadata JSON android.staticSmoke is missing'),
    );
    expect(script, contains('function Assert-AndroidStaticSmokeApkPath'));
    expect(
      script,
      contains(
        'Android static smoke record must have status \'passed\'.',
      ),
    );
    expect(
      androidSmokeScript,
      contains('apkanalyzer manifest application-id'),
    );
    expect(androidSmokeScript, contains(r'apkApplicationId = $applicationId'));
    expect(
      androidSmokeScript,
      contains(
        r'Android APK applicationId must be $ExpectedApplicationId; found $applicationId.',
      ),
    );
    expect(
      script,
      contains(
        'Android static smoke record APK applicationId must match the manifest package.',
      ),
    );
    expect(
      script,
      contains(
        'Android static smoke record launcherActivity must match RePaperTodo MainActivity.',
      ),
    );
    expect(script, contains('launcherIntentPresent'));
    expect(script, contains('singleTopLaunchMode'));
    expect(script, contains('emptyTaskAffinity'));
    expect(script, contains('adjustResizeWindow'));
    expect(script, contains('hardwareAcceleratedActivity'));
    expect(script, contains('backgroundWorkManagerInitializer'));
    expect(script, contains('backgroundWorkManagerSystemJobService'));
    expect(script, contains('backgroundWorkManagerRescheduleReceiver'));
    expect(script, contains('backgroundSyncNetworkPermission'));
    expect(script, contains('backgroundSyncWakeLockPermission'));
    expect(script, contains('backgroundSyncBootReschedulePermission'));
    expect(
      script,
      contains(
        'Android static smoke record checkedAtUtc must be a UTC timestamp.',
      ),
    );
    expect(
      script,
      contains(
        'Android static smoke record SDK values do not match the validated Android build configuration.',
      ),
    );
    expect(
      script,
      contains(
        'Android static smoke record must describe a non-debuggable APK.',
      ),
    );
    expect(
      script,
      contains(
        'Android static smoke record must confirm generic HTTP WebDAV cleartext support.',
      ),
    );
    expect(
      script,
      contains(
        'Android static smoke record must confirm broad external storage permissions are absent.',
      ),
    );
    expect(
      script,
      contains(
        'Android static smoke record must include the FileProvider paths resource.',
      ),
    );
    expect(
      script,
      contains('Android static smoke record must reference an APK file name.'),
    );
    expect(
      script,
      contains('Android static smoke record apkPath must not be blank.'),
    );
    expect(
      script,
      contains(
        'Android static smoke record apkPath must match the packaged Android APK.',
      ),
    );
    expect(
      script,
      contains(
          'Android static smoke record apkPath must reference an APK file.'),
    );
    expect(
      script,
      contains('Android static smoke record apkPath was not found'),
    );
    expect(script, contains('Assert-AndroidStaticSmokeRecord'));
    expect(script, contains(r'-AndroidApkPath $androidApk'));
    expect(script, contains(r'-ExpectedApkPath $AndroidApkPath'));
    expect(script, contains('cleartextWebDavAllowed'));
    expect(script, contains('WorkManager background sync'));
    expect(script, contains('broadExternalStoragePermissionsAbsent'));
    expect(
      script,
      contains('forbiddenLocalizedResourceConfigurationsAbsent'),
    );
    expect(script, contains('androidLocaleConfigPresent'));
    expect(
      script,
      contains('android.staticSmoke.expectedResourceLanguages'),
    );
    expect(
      script,
      contains('android.staticSmoke.localeConfigLanguages'),
    );
    expect(script, contains('fileProviderPathsResource'));
    expect(script, contains('localeConfigResource'));
    expect(script, contains('apkFileName'));
    expect(
      script,
      contains(
        r'Release metadata JSON android.staticSmoke.$property does not match',
      ),
    );
    expect(
      script,
      contains('Release metadata JSON android.deviceSmoke is missing'),
    );
    expect(
      script,
      contains('Android device smoke record checkedAtUtc must not be blank.'),
    );
    expect(
      script,
      contains(
        'Android device smoke record checkedAtUtc must be a UTC timestamp.',
      ),
    );
    expect(
      script,
      contains(
        r'Release metadata JSON android.deviceSmoke.$property does not match',
      ),
    );
    expect(script, contains('Android device smoke APK'));
    expect(
      script,
      contains(
        'Android device smoke APK byte count must match the packaged Android APK.',
      ),
    );
    expect(
      script,
      contains(
        'Android device smoke APK SHA-256 must match the packaged Android APK.',
      ),
    );
    expect(
      script,
      contains(
        r'Release metadata JSON android.tools.$property does not match',
      ),
    );
    expect(script, contains('Release metadata JSON runtime is missing'));
    expect(script, contains('runtime.supportedLanguages'));
    expect(script, contains('Release metadata JSON toolchain.'));
    expect(
      script,
      contains('does not match the packaged release record'),
    );
    expect(script, contains(r'compileSdk = $androidSdkConfig["compileSdk"]'));
    expect(script, contains(r'targetSdk = $androidSdkConfig["targetSdk"]'));
    expect(script, contains(r'$validationExecuted'));
    expect(script, contains(r'$validationSkipped'));
    expect(script, contains('skippedValidation'));
    expect(script, contains('function New-ReleaseNotes'));
    expect(script, contains('Verification summary:'));
    expect(script, contains('Windows smoke:'));
    expect(script, contains('initialTodoPaperCount'));
    expect(script, contains('finalTodoPaperCount'));
    expect(script, contains('initialNotePaperCount'));
    expect(script, contains('finalNotePaperCount'));
    expect(script, contains('WebDAV static smoke:'));
    expect(
      script,
      contains('Android background absolute state path gate'),
    );
    expect(script, contains('Android background data.json state path gate'));
    expect(script, contains('Android static smoke:'));
    expect(script, contains('launcherActivity'));
    expect(script, contains('singleTopLaunchMode'));
    expect(script, contains('emptyTaskAffinity'));
    expect(script, contains('APK application ID'));
    expect(script, contains('Android device smoke:'));
    expect(script, contains(r'$androidDeviceSmokeCheckedAtUtc'));
    expect(script, contains(r'passed at $androidDeviceSmokeCheckedAtUtc'));
    expect(script, contains(r'skipped at $androidDeviceSmokeCheckedAtUtc'));
    expect(script, contains(r'-WindowsSmokeRecord $windowsSmokeRecord'));
    expect(script, contains(r'-WebDavSmokeRecord $webDavSmokeRecord'));
    expect(
      script,
      contains(r'-AndroidStaticSmokeRecord $androidStaticSmokeRecord'),
    );
    expect(
      script,
      contains(r'-AndroidDeviceSmokeRecord $androidDeviceSmokeRecord'),
    );
    expect(script, contains('function Get-ChangelogUnreleasedNotes'));
    expect(script, contains('User-facing changes:'));
    expect(script, contains('CHANGELOG.md'));
    expect(script, contains('-UserFacingChanges'));
    expect(script, contains(r'-ValidationExecuted $validationExecuted'));
    expect(script, contains(r'-ValidationSkipped $validationSkipped'));
    expect(script, contains(r'-DirtyWorkingTreeAllowed $AllowDirty'));
    expect(script, contains(r'-PackageResolution $packageResolution'));
    expect(script, contains(r'-FlutterFrameworkVersion $toolchainInfo'));
    expect(
      script,
      contains(r'-SupportedRuntimeLanguages $validatedRuntimeLanguages'),
    );
    expect(script, contains('gh release create'));
    expect(script, contains('gh release edit'));
    expect(script, contains('gh release upload'));
    expect(script, contains('gh auth status'));
    expect(script, contains(r'$env:GH_TOKEN'));
    expect(script, contains(r'$env:GITHUB_TOKEN'));
    expect(script, contains('valid GH_TOKEN or GITHUB_TOKEN'));
    expect(script, contains('authenticated GitHub CLI session'));
    expect(script, contains('gh auth refresh -h github.com'));
    expect(script, contains('gh auth login -h github.com'));
    expect(script, contains(r'--target $gitCommit'));
    expect(script, contains(r'$releaseViewExitCode'));
    expect(script, contains(r'--notes-file $releaseNotesFile'));
    expect(
      script,
      contains(r'$checksumsFile $metadataFile $releaseNotesFile --clobber'),
    );
    expect(script, contains('Assert-GitHubReleaseAssets'));
    expect(script, contains('Assert-GitHubReleaseDownloadedAssets'));
    expect(script, contains(r'-ArtifactPaths @('));
    expect(script, contains(r'$windowsZip,'));
    expect(script, contains(r'$androidApk,'));
    expect(script, contains(r'$checksumsFile,'));
    expect(script, contains(r'$metadataFile,'));
    expect(script, contains(r'$releaseNotesFile'));
    expect(script, contains('SHA-256 checksums for release artifacts.'));
    expect(
      script,
      contains('Release notes markdown used by GitHub Release publishing.'),
    );
    expect(
      script,
      contains('Android smoke, runtime language, validation'),
    );
    expect(
      script,
      contains('WebDAV smoke, Android SDK/signing, Android smoke'),
    );
    expect(script, contains('Runtime UI languages:'));
    expect(script, contains('Release metadata JSON with version'));
    expect(readme, contains('package\nresolution mode'));
    expect(readme, contains('Android SDK tool paths'));
    expect(readme, contains('WebDAV static smoke result'));
    expect(readme, contains('Android static smoke result'));
    expect(readme, contains('Flutter/Dart toolchain versions'));
    expect(readme, contains('runtime supported languages (`zh` and `en`)'));
    expect(readme, contains('expected application ID'));
    expect(readme, contains('APK application ID'));
    expect(readme, contains('`pubspec.lock` hash'));
    expect(readme, contains('release notes file hash'));
    expect(
      development,
      contains('runtime supported\nlanguage set (`zh` and `en`)'),
    );
    expect(development, contains('APK application ID'));
    expect(development, contains('release notes file record'));
    expect(readme, contains('release notes markdown file'));
    expect(readme, contains('CHANGELOG.md` Unreleased entries'));
    expect(readme, contains('`assets/flutter_assets/AssetManifest.bin`'));
    expect(readme, contains('`lib/*/libapp.so`'));
    expect(readme, contains('`lib/*/libflutter.so`'));
    expect(readme, contains('inspected with `apkanalyzer`'));
    expect(
      development,
      contains('build/app/outputs/flutter-apk/app-release.apk'),
    );
    expect(
      development,
      contains('dist/repapertodo-windows-x64-<version>.zip'),
    );
    expect(
      development,
      contains('dist/repapertodo-android-<version>.apk'),
    );
    expect(
      development,
      contains('dist/repapertodo-<version>-release.json'),
    );
    expect(readme, contains('actual manifest\n`min-sdk` and `target-sdk`'));
    expect(readme, contains('UTC build timestamp'));
    expect(readme, contains('WebDAV static smoke pass status'));
    expect(readme, contains('relative or non-`data.json` state-file paths'));
    expect(readme, contains('generic WebDAV support'));
    expect(readme, contains('Jianguoyun preset support'));
    expect(readme, contains('operation-log evidence'));
    expect(readme, contains('local HTTP WebDAV protocol round-trip'));
    expect(readme, contains('Windows/Android operation-log round-trip'));
    expect(readme, contains('skipped validation commands'));
    expect(readme, contains('record those skipped validation'));
    expect(readme, contains('validates\nthe `pubspec.yaml` version as SemVer'));
    expect(readme, contains('filename-safe artifact\nversion token'));
    expect(readme, contains('rejects unsafe GitHub Release tags'));
    expect(readme, contains('leading/trailing whitespace'));
    expect(readme, contains('control characters'));
    expect(
      script,
      contains('Android release APK targeting Android 14-17 / API 34-37.'),
    );
    expect(workflow, contains('name: Build and Release'));
    expect(workflow, contains('workflow_dispatch'));
    expect(workflow, contains('publishRelease'));
    expect(workflow, contains('windows-latest'));
    expect(workflow, contains('permissions:'));
    expect(workflow, contains('contents: read'));
    expect(workflow, contains('contents: write'));
    expect(
      workflow,
      contains(
        r"if: ${{ github.event_name != 'workflow_dispatch' || inputs.publishRelease != true }}",
      ),
    );
    expect(workflow, contains('name: Validate, package, and publish'));
    expect(
      workflow,
      contains(
        r"if: ${{ github.event_name == 'workflow_dispatch' && inputs.publishRelease == true }}",
      ),
    );
    expect(workflow, contains('actions/checkout@v4'));
    expect(workflow, contains('fetch-depth: 0'));
    expect(workflow, contains('actions/setup-java@v4'));
    expect(workflow, contains('subosito/flutter-action@v2'));
    expect(workflow, contains('channel: stable'));
    expect(workflow, contains('function Invoke-Native'));
    expect(workflow, contains('"sdkmanager --licenses"'));
    expect(workflow, contains('"sdkmanager install Android API 37"'));
    expect(workflow, contains(r'failed with exit code $LASTEXITCODE'));
    expect(workflow, contains('platforms;android-37.0'));
    expect(workflow, isNot(contains('"platforms;android-37"')));
    expect(workflow, contains('build-tools;37.0.0'));
    expect(workflow, contains('Configure Android release signing'));
    expect(workflow, contains('ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains('ANDROID_STORE_PASSWORD'));
    expect(workflow, contains('ANDROID_KEY_ALIAS'));
    expect(workflow, contains('ANDROID_KEY_PASSWORD'));
    expect(
      RegExp(r'run: \.\\scripts\\configure_android_signing\.ps1')
          .allMatches(workflow),
      hasLength(2),
    );
    expect(workflow, isNot(contains('function Assert-AndroidSigningSecret')));
    expect(workflow, isNot(contains('function Convert-AndroidKeystoreSecret')));
    expect(signingScript, contains('function Assert-AndroidSigningSecret'));
    expect(signingScript, contains('function Assert-AndroidStoreFile'));
    expect(signingScript, contains('function Convert-AndroidKeystoreSecret'));
    expect(
      signingScript,
      contains('function Resolve-AndroidSigningOutputPath'),
    );
    expect(
      signingScript,
      contains("Android release signing secret '\$Name'"),
    );
    expect(signingScript, contains('must not contain control characters'));
    expect(
      signingScript,
      contains(
          'Android signing storeFile must not contain wildcard characters'),
    );
    expect(
      signingScript,
      contains('Android signing storeFile must not contain dot-segments'),
    );
    expect(
      signingScript,
      contains('Android signing storeFile must be relative'),
    );
    expect(signingScript, contains(r'[IO.Path]::IsPathRooted($Value)'));
    expect(script, contains('Android signing storeFile must be relative'));
    expect(script, contains(r'[IO.Path]::IsPathRooted($StoreFile)'));
    expect(
      releaseReadinessAudit,
      contains(r'[IO.Path]::IsPathRooted($StoreFile)'),
    );
    expect(gradle, contains('File(storeFile).isAbsolute'));
    expect(gradle, contains('Android signing storeFile must be relative'));
    expect(signingScript, contains('must be valid base64'));
    expect(
      signingScript,
      contains(r'Android signing $Description path must not be blank.'),
    );
    expect(
      signingScript,
      contains(
          r'Android signing $Description path must not contain wildcard characters.'),
    );
    expect(
      signingScript,
      contains(
        r'Android signing $Description path must include a file name.',
      ),
    );
    expect(
      signingScript,
      contains(r'$resolvedKeystorePath = Resolve-AndroidSigningOutputPath `'),
    );
    expect(
      signingScript,
      contains(
          r'$resolvedKeyPropertiesPath = Resolve-AndroidSigningOutputPath `'),
    );
    expect(
      signingScript,
      contains('Assert-AndroidSigningSecret -Name "ANDROID_KEYSTORE_BASE64"'),
    );
    expect(
      signingScript,
      contains(
        r'Assert-AndroidSigningSecret `',
      ),
    );
    expect(signingScript, contains(r'-Name $name `'));
    expect(
      signingScript,
      contains(r'$androidSigningSecrets[$name] = Get-AndroidSigningSecret'),
    );
    expect(signingScript, contains(r'$configuredSecrets = @('));
    expect(
      signingScript,
      contains(
          r'$configuredSecrets.Count -ne $androidSigningSecretNames.Count'),
    );
    expect(
      signingScript,
      contains(r'-Value $androidSigningSecrets[$name]'),
    );
    expect(
      signingScript,
      contains(
        r'$keystoreBytes = Convert-AndroidKeystoreSecret -Value $keystoreSecret',
      ),
    );
    expect(
      signingScript,
      contains(r'Assert-AndroidStoreFile -Value $StoreFile'),
    );
    expect(signingScript, contains('repapertodo-release.jks'));
    expect(signingScript, contains('android\\key.properties'));
    expect(signingScript, contains(r'$androidSigningSecretNames = @('));
    expect(signingScript, contains('ANDROID_KEYSTORE_BASE64'));
    expect(signingScript, contains('ANDROID_STORE_PASSWORD'));
    expect(signingScript, contains('ANDROID_KEY_ALIAS'));
    expect(signingScript, contains('ANDROID_KEY_PASSWORD'));
    expect(
      signingScript,
      contains(r'foreach ($name in $androidSigningSecretNames)'),
    );
    expect(
      signingScriptTest,
      contains('Android signing script rejects partial signing secrets'),
    );
    expect(
      signingScriptTest,
      contains('Android signing script writes complete signing secrets'),
    );
    expect(
      signingScriptTest,
      contains('Android signing script rejects unsafe storeFile values'),
    );
    expect(
      signingScriptTest,
      contains('Android signing script rejects absolute storeFile values'),
    );
    expect(
      signingScriptTest,
      contains('Android signing script rejects unsafe output paths'),
    );
    expect(signingScript, contains('} finally {'));
    expect(
      readme,
      contains('clears those signing secret environment variables'),
    );
    expect(readme, contains('unsafe `storeFile` override'));
    expect(readme, contains('absolute paths'));
    expect(readme, contains('`finally` block'));
    expect(
      signingScript,
      contains('Android release signing secrets are not configured'),
    );
    expect(
      signingScript,
      contains('Android release signing secrets are incomplete'),
    );
    expect(signingScript, contains(r'Remove-Item -LiteralPath "Env:\$name"'));
    expect(workflow, isNot(contains('HTTP_PROXY: ""')));
    expect(workflow, isNot(contains('HTTPS_PROXY: ""')));
    expect(workflow, isNot(contains('ALL_PROXY: ""')));
    expect(
      RegExp(
        RegExp.escape(
          r'& $sdkManager.FullName --channel=3 "platform-tools" "platforms;android-37.0" "build-tools;37.0.0"',
        ),
      ).allMatches(workflow).length,
      2,
    );
    expect(workflow, contains(r'.\scripts\release.ps1 @releaseArgs'));
    expect(workflow, contains('-PublishGitHubRelease'));
    expect(workflow, contains('qaEvidenceRunId'));
    expect(workflow, contains('actions/download-artifact@v4'));
    expect(workflow, contains(r'run-id: ${{ inputs.qaEvidenceRunId }}'));
    expect(workflow, contains('name: repapertodo-qa-evidence'));
    expect(
        qaEvidenceWorkflow, contains('runs-on: [self-hosted, Windows, X64]'));
    expect(qaEvidenceWorkflow, contains('candidateRunId'));
    expect(qaEvidenceWorkflow, contains('actions/download-artifact@v4'));
    expect(qaEvidenceWorkflow, contains('scripts\\windows_manual_qa.ps1'));
    expect(qaEvidenceWorkflow, contains('scripts\\webdav_live_smoke.ps1'));
    expect(qaEvidenceWorkflow,
        contains('REPAPERTODO_WEBDAV_PROVIDER: jianguoyun'));
    expect(qaEvidenceWorkflow, contains('scripts\\android_device_smoke.ps1'));
    expect(qaEvidenceWorkflow, contains('name: repapertodo-qa-evidence'));
    expect(
      workflow,
      contains(
        r'$releaseArgs += @("-WindowsManualQaResultJson", "dist\qa\windows-manual-qa.json")',
      ),
    );
    expect(
      workflow,
      contains(
        r'$releaseArgs += @("-WebDavLiveSmokeResultJson", "dist\qa\webdav-live-smoke.json")',
      ),
    );
    expect(
      workflow,
      contains(
        r'$releaseArgs += @("-WebDavDomesticLiveSmokeResultJson", "dist\qa\webdav-domestic-live-smoke.json")',
      ),
    );
    expect(
      workflow,
      contains(
        r'$releaseArgs += @("-AndroidDeviceSmokeResultJson", "dist\qa\android-device-smoke.json")',
      ),
    );
    expect(workflow, contains('actions/upload-artifact@v4'));
    expect(workflow, contains('Upload published artifacts'));
    expect(workflow, contains('path: dist/*'));
    expect(readme, contains('wired into GitHub Actions'));
    expect(readme, contains('keystore base64, password, and alias secrets'));
    expect(readme, contains('Pushes and pull requests'));
    expect(readme, contains('read-only `contents`'));
    expect(readme, contains('separate write-permission job'));
    expect(readme, contains('GitHub Release publish path'));
    expect(readme, contains('workflow_dispatch'));
    expect(readme, contains('publishRelease'));
    expect(readme, contains(r'.\scripts\release.ps1'));
    expect(readme, contains('-PublishGitHubRelease'));
    expect(readme, contains('Publishing checks `gh auth status`'));
    expect(readme, contains('accepts `GH_TOKEN` or `GITHUB_TOKEN`'));
    expect(readme, contains('missing or expired GitHub credentials'));
    expect(readme, contains('`gh auth refresh -h github.com`'));
    expect(readme, contains('`gh auth login -h github.com`'));
    expect(readme, contains('fetches `origin/main`'));
    expect(readme, contains('local `main` HEAD'));
    expect(readme, contains('validated commit SHA'));
    expect(readme, contains('tag to match the `pubspec.yaml`'));
    expect(readme, contains('version exactly as `v<version>`'));
    expect(readme, contains('target tag already exists'));
    expect(readme, contains('reused version cannot'));
    expect(readme, contains('reads the\nrelease asset list back'));
    expect(readme, contains('exists exactly once'));
    expect(readme, contains('same byte count'));
    expect(readme, contains('-AllowDirty'));
    expect(readme, contains('dirty git working tree'));
    expect(readme, contains('dirtyWorkingTreeAllowed: true'));
    expect(readme, contains('flutter pub get --offline'));
    expect(readme, contains('which package resolution mode'));
    expect(readme, contains('was used'));
    expect(readme, contains('runtime UI'));
    expect(readme, contains('language set (`zh` and `en`)'));
    expect(readme, contains('Flutter and Dart'));
    expect(readme, contains('toolchain versions'));
    expect(readme, contains('validation commands'));
    expect(readme, contains('were executed or skipped'));
    expect(readme, contains('verification summary'));
    expect(readme, contains('Android APK application ID and SDK values'));
    expect(readme, contains('runs again immediately before packaging'));
    expect(readme, contains('drift away from the metadata'));
    expect(readme, contains('commit unnoticed'));
    expect(readme, contains("refreshing Git's index"));
    expect(readme, contains('normalized content'));
    expect(readme, contains('is unchanged'));
    expect(readme, contains('GitHub Release publishing always requires'));
    expect(readme, contains('combined with `-SkipTests`'));
    expect(readme, contains('`-SkipBuild`, or `-AllowDirty`'));
    expect(readme, contains('-OfflinePubGet'));
    expect(readme, contains('When using `-SkipBuild`'));
    expect(readme, contains('rerun without `-SkipBuild`'));
    expect(readme, contains('must include `repapertodo.exe`'));
    expect(readme, contains('Flutter Windows runtime files'));
    expect(readme, contains('must point to an APK file'));
    expect(readme, contains('Validation includes `git diff --check`'));
    expect(readme, contains('SHA-256 checksum file'));
    expect(readme, contains('covers the Windows zip, Android APK'));
    expect(
      readme,
      contains('verifies that checksum file against the packaged files'),
    );
    expect(readme, contains('release metadata JSON file'));
    expect(readme, contains('reads that metadata JSON back'));
    expect(readme, contains('runtime language fields'));
    expect(readme, contains('artifact records match'));
    expect(readme, contains('safe single file names rather than paths'));
    expect(readme, contains('byte counts must be positive integers'));
    expect(readme, contains('64-character\nlowercase SHA-256 values'));
    expect(readme, contains('packages must actually contain'));
    expect(readme, contains('local runtime state'));
    expect(readme, contains('backup/recovery JSON files'));
    expect(readme, contains('rejects package entries'));
    expect(readme, contains('absolute paths'));
    expect(readme, contains('parent-directory\nsegments'));
    expect(readme, contains('blank or whitespace-padded path segments'));
    expect(readme, contains('`repapertodo.exe`'));
    expect(readme, contains('`flutter_windows.dll`'));
    expect(readme, contains('`data/app.so`'));
    expect(readme, contains('`data/icudtl.dat`'));
    expect(readme, contains('`data/flutter_assets/FontManifest.json`'));
    expect(readme, contains('`AndroidManifest.xml`'));
    expect(readme, contains('refuses to'));
    expect(readme, contains('keystore file'));
    expect(readme, contains('Signing property values'));
    expect(readme, contains('wildcard'));
    expect(readme, contains('dot-segments'));
    expect(readme, contains('keystore base64, password, and alias secrets'));
    expect(readme, contains('clear signing-secret error'));
    expect(readme, contains('ANDROID_KEYSTORE_BASE64'));
    expect(readme, contains('ANDROID_STORE_PASSWORD'));
    expect(readme, contains('ANDROID_KEY_ALIAS'));
    expect(readme, contains('ANDROID_KEY_PASSWORD'));
    expect(readme, contains('Android 14-17/API 34-37 compatibility'));
    expect(readme, contains('reads the Android Gradle SDK settings'));
    expect(readme, contains('stops if they drift'));
    expect(androidSmokeScript, contains('apkanalyzer manifest print'));
    expect(androidSmokeScript, contains('apkanalyzer manifest debuggable'));
    expect(androidSmokeScript, contains(r'[string]$Aapt2 = ""'));
    expect(androidSmokeScript, contains(r'[string]$ResultJson = ""'));
    expect(androidSmokeScript, contains('function Resolve-ResultJsonPath'));
    expect(
      androidSmokeScript,
      contains(
          'Android APK smoke result JSON path must use the .json extension.'),
    );
    expect(
      androidSmokeScript,
      contains(
        'Android APK smoke result JSON path must not contain wildcard characters.',
      ),
    );
    expect(androidSmokeScript, contains('checkedAtUtc'));
    expect(androidSmokeScript, contains('apkFileName'));
    expect(androidSmokeScript, contains('applicationId'));
    expect(androidSmokeScript, contains('launcherActivity'));
    expect(androidSmokeScript, contains('launcherIntentPresent'));
    expect(androidSmokeScript, contains('singleTopLaunchMode'));
    expect(androidSmokeScript, contains('emptyTaskAffinity'));
    expect(androidSmokeScript, contains('adjustResizeWindow'));
    expect(androidSmokeScript, contains('hardwareAcceleratedActivity'));
    expect(androidSmokeScript, contains('cleartextWebDavAllowed'));
    expect(androidSmokeScript, contains('backgroundWorkManagerInitializer'));
    expect(
        androidSmokeScript, contains('backgroundWorkManagerSystemJobService'));
    expect(
      androidSmokeScript,
      contains('backgroundWorkManagerRescheduleReceiver'),
    );
    expect(androidSmokeScript, contains('backgroundSyncNetworkPermission'));
    expect(androidSmokeScript, contains('backgroundSyncWakeLockPermission'));
    expect(
      androidSmokeScript,
      contains('backgroundSyncBootReschedulePermission'),
    );
    expect(
        androidSmokeScript, contains('broadExternalStoragePermissionsAbsent'));
    expect(androidSmokeScript, contains(r'$ExpectedResourceLanguages'));
    expect(androidSmokeScript, contains('aapt2 dump configurations'));
    expect(
      androidSmokeScript,
      contains('function Assert-AndroidResourceLanguages'),
    );
    expect(
      androidSmokeScript,
      contains('forbiddenLocalizedResourceConfigurationsAbsent'),
    );
    expect(androidSmokeScript, contains('function Assert-LocaleConfig'));
    expect(androidSmokeScript, contains('androidLocaleConfigPresent'));
    expect(androidSmokeScript, contains('localeConfigLanguages'));
    expect(androidSmokeScript, contains('localeConfigResource'));
    expect(androidSmokeScript, contains('ConvertTo-Json -Depth 4'));
    expect(androidSmokeScript, contains('aapt2 dump resources'));
    expect(androidSmokeScript, contains('aapt2 dump xmltree'));
    expect(androidSmokeScript, contains('function Get-AndroidXmlResourceFile'));
    expect(androidSmokeScript, contains('function Assert-FileProviderPaths'));
    expect(androidSmokeScript, contains('xml/file_paths'));
    expect(androidSmokeScript, contains('xml/locales_config'));
    expect(androidSmokeScript, contains('E: root-path'));
    expect(
      androidSmokeScript,
      contains('must not expose device root paths'),
    );
    expect(androidSmokeScript, contains('cache-path'));
    expect(androidSmokeScript, contains('files-path'));
    expect(androidSmokeScript, contains('external-cache-path'));
    expect(androidSmokeScript, contains('external-files-path'));
    expect(androidSmokeScript, contains('external_repapertodo'));
    expect(androidSmokeScript, contains('RePaperTodo/'));
    expect(androidSmokeScript, contains('external_documents_repapertodo'));
    expect(androidSmokeScript, contains('Documents/RePaperTodo/'));
    expect(androidSmokeScript, contains('external_download_repapertodo'));
    expect(androidSmokeScript, contains('Download/RePaperTodo/'));
    expect(
      androidSmokeScript,
      contains('must stay scoped to RePaperTodo directories'),
    );
    expect(androidSmokeScript, contains('ExpectedMinSdk = 34'));
    expect(androidSmokeScript, contains('ExpectedTargetSdk = 37'));
    expect(androidSmokeScript, contains('ExpectedCompileSdk = 37'));
    expect(androidSmokeScript, contains('com.aligez.repapertodo'));
    expect(androidSmokeScript, contains('android.permission.INTERNET'));
    expect(androidSmokeScript,
        contains('android.permission.ACCESS_NETWORK_STATE'));
    expect(androidSmokeScript, contains('android.permission.WAKE_LOCK'));
    expect(androidSmokeScript,
        contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(
        androidSmokeScript, contains('androidx.work.WorkManagerInitializer'));
    expect(androidSmokeScript,
        contains('androidx.work.impl.background.systemjob.SystemJobService'));
    expect(
        androidSmokeScript,
        contains(
            'androidx.work.impl.background.systemalarm.RescheduleReceiver'));
    expect(androidSmokeScript,
        contains('android.permission.MANAGE_EXTERNAL_STORAGE'));
    expect(androidSmokeScript,
        contains('android.permission.READ_EXTERNAL_STORAGE'));
    expect(androidSmokeScript,
        contains('android.permission.WRITE_EXTERNAL_STORAGE'));
    expect(androidSmokeScript, contains('android:usesCleartextTraffic'));
    expect(androidSmokeScript, contains('generic HTTP WebDAV endpoints'));
    expect(androidSmokeScript, contains('androidx.core.content.FileProvider'));
    expect(androidSmokeScript, contains('android:taskAffinity=""'));
    expect(androidSmokeScript, contains('android:launchMode="1"'));
    expect(androidSmokeScript, contains('android:windowSoftInputMode="0x10"'));
    expect(androidSmokeScript, contains('android:hardwareAccelerated="true"'));
    expect(
      androidSmokeScript,
      contains('android:name="android.intent.action.MAIN"'),
    );
    expect(
      androidSmokeScript,
      contains('android:name="android.intent.category.LAUNCHER"'),
    );
    expect(androidSmokeScript, contains('android:grantUriPermissions'));
    expect(androidSmokeScript, contains('android.support.FILE_PROVIDER_PATHS'));
    expect(androidSmokeScript, contains('android:scheme="http"'));
    expect(androidSmokeScript, contains('android:scheme="https"'));
    expect(androidSmokeScript, contains('android:scheme="mailto"'));
    expect(androidSmokeScript, contains('android:mimeType="text/markdown"'));
    expect(androidSmokeScript, contains('android:mimeType="text/plain"'));
    expect(androidSmokeScript, contains('android:mimeType="*/*"'));
    expect(androidDeviceSmokeScript, contains('adb.exe'));
    expect(androidDeviceSmokeScript, contains(r'[string]$ResultJson = ""'));
    expect(
      androidDeviceSmokeScript,
      contains('function Resolve-ResultJsonPath'),
    );
    expect(
      androidDeviceSmokeScript,
      contains(
        'Android device smoke result JSON path must use the .json extension.',
      ),
    );
    expect(
      androidDeviceSmokeScript,
      contains(
        'Android device smoke result JSON path must not contain wildcard characters.',
      ),
    );
    expect(
        androidDeviceSmokeScript, contains('function Get-AndroidDeviceSerial'));
    expect(androidDeviceSmokeScript, contains('No online Android device'));
    expect(androidDeviceSmokeScript, contains('Multiple Android devices'));
    expect(androidDeviceSmokeScript, contains('ro.build.version.sdk'));
    expect(androidDeviceSmokeScript, contains('Android 14-17/API'));
    expect(androidDeviceSmokeScript, contains('adb install'));
    expect(androidDeviceSmokeScript, contains('am start'));
    expect(androidDeviceSmokeScript, contains('android.intent.action.MAIN'));
    expect(
        androidDeviceSmokeScript, contains('android.intent.category.LAUNCHER'));
    expect(androidDeviceSmokeScript, contains(r'[string]$ApkAnalyzer = ""'));
    expect(androidDeviceSmokeScript, contains('function Get-ApkApplicationId'));
    expect(
      androidDeviceSmokeScript,
      contains('apkanalyzer manifest application-id'),
    );
    expect(androidDeviceSmokeScript, contains('apkApplicationId'));
    expect(
      androidDeviceSmokeScript,
      contains(
        "Android device smoke APK applicationId '\$apkApplicationId' does not match expected package '\$ExpectedApplicationId'.",
      ),
    );
    expect(androidDeviceSmokeScript, contains('pidof'));
    expect(androidDeviceSmokeScript, contains('am force-stop'));
    expect(
      androidDeviceSmokeScript,
      contains('function Stop-AndroidPackageQuietly'),
    );
    expect(androidDeviceSmokeScript, contains('} finally {'));
    expect(
      androidDeviceSmokeScript,
      contains(
          r'Stop-AndroidPackageQuietly -PackageName $ExpectedApplicationId'),
    );
    expect(androidDeviceSmokeScript, contains('checkedAtUtc'));
    expect(androidDeviceSmokeScript, contains('deviceSerial'));
    expect(androidDeviceSmokeScript, contains('apiLevel'));
    expect(androidDeviceSmokeScript, contains('apkFileName'));
    expect(androidDeviceSmokeScript, contains('apkBytes'));
    expect(androidDeviceSmokeScript, contains('apkSha256'));
    expect(
        androidDeviceSmokeScript, contains('Get-FileHash -Algorithm SHA256'));
    expect(androidDeviceSmokeScript, contains('processId'));
    expect(
      androidDeviceSmokeScript,
      contains('function Get-AndroidForegroundPackage'),
    );
    expect(
      androidDeviceSmokeScript,
      contains('function Get-ForegroundPackageFromDump'),
    );
    expect(androidDeviceSmokeScript, contains('dumpsys'));
    expect(androidDeviceSmokeScript, contains('mCurrentFocus'));
    expect(androidDeviceSmokeScript, contains('topResumedActivity'));
    expect(androidDeviceSmokeScript, contains('dumpsys activity activities'));
    expect(androidDeviceSmokeScript, contains('mResumedActivity'));
    expect(
        androidDeviceSmokeScript, isNot(contains(r'$ExpectedPackageName)/')));
    expect(androidDeviceSmokeScript, contains('foregroundPackage'));
    expect(
      androidDeviceSmokeScript,
      contains(
        'Android device smoke observed process ID must be a positive integer',
      ),
    );
    expect(
      androidDeviceSmokeScript,
      contains(
        "Android device smoke expected '\$ExpectedApplicationId' to be foreground after launch, but found '\$foregroundPackage'.",
      ),
    );
    expect(androidDeviceSmokeScript, contains('ConvertTo-Json -Depth 4'));
    expect(androidDeviceSmokeScript, contains('com.aligez.repapertodo'));
    expect(script, contains('function Assert-AndroidDeviceSmokeRecord'));
    expect(
      script,
      contains(
        'Android device smoke record APK applicationId must match the launched package.',
      ),
    );
    expect(
      script,
      contains(
        'Android device smoke record foregroundPackage must match the launched package.',
      ),
    );
    expect(
      script,
      contains(
        'Android device smoke record processId must be a positive integer.',
      ),
    );
    expect(
      script,
      contains(
        'Android device smoke record API level must be inside Android 14-17/API 34-37.',
      ),
    );
    expect(
      script,
      contains(
        'Android device smoke record APK file name must match the packaged Android APK.',
      ),
    );
    expect(script, contains('Android device smoke APK byte count'));
    expect(script, contains('Android device smoke APK SHA-256'));
    expect(
      script,
      contains(
          r'-ExpectedApkFileName ([IO.Path]::GetFileName($AndroidApkPath))'),
    );
    expect(script, contains(r'-ExpectedApkPath $AndroidApkPath'));
    expect(script, contains(r'-ExpectedApkPath $androidApk'));
    expect(script, contains('Assert-AndroidDeviceSmokeRecord'));
    expect(readme, contains('Android smoke\nvalidation'));
    expect(readme, contains('scripts/android_device_smoke.ps1'));
    expect(readme, contains('-RunAndroidDeviceSmoke'));
    expect(readme, contains('-AndroidDeviceSerial'));
    expect(readme, contains('optional Android device smoke result'));
    expect(readme, contains('APK byte count, APK SHA-256'));
    expect(readme, contains('verify the APK application ID'));
    expect(readme, contains('adb and apkanalyzer'));
    expect(readme, contains('APK application ID'));
    expect(readme, contains('observed process ID'));
    expect(readme, contains('without uninstalling existing app data'));
    expect(development, contains('APK byte count, APK SHA-256'));
    expect(
      development,
      contains('same APK file name and hash'),
    );
    expect(readme, contains('generic HTTP WebDAV cleartext support'));
    expect(readme, contains('structured metadata'));
    expect(readme, contains('broad-storage\npermission absence'));
    expect(readme, contains('APK localized resource configurations'));
    expect(readme, contains('runtime language set (`zh` and `en`)'));
    expect(readme, contains('avoids broad external-storage\npermissions'));
    expect(readme, contains('dumps the compiled\n`@xml/file_paths`'));
    expect(readme, contains('external sharing stays scoped'));
    expect(readme, contains('Windows release output is smoke-tested'));
    expect(readme, contains('Windows smoke result'));
    expect(readme, contains('initial/final paper and note/todo type counts'));
    expect(
      readme,
      contains('forwarding secondary `--new-note`, `--new-todo`, and'),
    );
    expect(readme, contains('Windows/WebDAV/Android smoke scripts'));
    expect(readme, contains('generic WebDAV remains present'));
    expect(readme, contains('encrypted payloads are required'));
    expect(readme, contains('Windows/Android two-store round trip'));
    expect(readme, contains('shared settings'));
    expect(readme, contains('UI exposes the same sync model'));
    expect(development, contains(r'.\scripts\android_smoke.ps1'));
    expect(development, contains(r'.\scripts\android_device_smoke.ps1'));
    expect(development, contains(r'.\scripts\webdav_smoke.ps1'));
    expect(
      development,
      contains(
        r'.\scripts\release.ps1 -AllowDirty -SkipTests -SkipBuild -RunAndroidDeviceSmoke',
      ),
    );
    expect(development, contains('-AndroidDeviceSerial <adb-serial>'));
    expect(development, contains('-ResultJson'));
    expect(development, contains('structured smoke result'));
    expect(development, contains('resolves `apkanalyzer` and `adb`'));
    expect(development, contains('verifies the APK\napplication ID'));
    expect(development, contains('APK application ID'));
    expect(development,
        contains('Release packaging records this static smoke result'));
    expect(development,
        contains('Release packaging records this Windows smoke result'));
    expect(development, contains('repository-relative evidence file paths'));
    expect(development, contains('evidence paths must stay inside'));
    expect(development, contains('point at real files'));
    expect(development, contains('result in metadata by\ndefault'));
    expect(development, contains('does not need real WebDAV credentials'));
    expect(development, contains('generic HTTP/HTTPS WebDAV support'));
    expect(development, contains('Jianguoyun WebDAV preset support'));
    expect(development, contains('operation-log sync support'));
    expect(development, contains('two-store operation-log round trip'));
    expect(
      development,
      contains('Android background sync absolute `data.json` state-path gate'),
    );
    expect(development, contains('For real-provider WebDAV QA'));
    expect(development, contains('REPAPERTODO_WEBDAV_ENDPOINT'));
    expect(development, contains('REPAPERTODO_WEBDAV_KEEP_REMOTE=true'));
    expect(webDavSmokeScript, contains(r'[string]$ResultJson = ""'));
    expect(webDavSmokeScript, contains('function Resolve-ResultJsonPath'));
    expect(
      webDavSmokeScript,
      contains(
          'WebDAV static smoke result JSON path must use the .json extension.'),
    );
    expect(
      webDavSmokeScript,
      contains(
        'WebDAV static smoke result JSON path must not contain wildcard characters.',
      ),
    );
    expect(webDavSmokeScript, contains('function Assert-RepoEvidenceFile'));
    expect(
      webDavSmokeScript,
      contains('WebDAV smoke evidence file path must be relative'),
    );
    expect(
      webDavSmokeScript,
      contains('WebDAV smoke evidence file path must not contain dot-segments'),
    );
    expect(
      webDavSmokeScript,
      contains(
          'WebDAV smoke evidence file path must stay inside the repository'),
    );
    expect(
      webDavSmokeScript,
      contains('WebDAV smoke evidence file was not found'),
    );
    expect(webDavSmokeScript, contains('Generic WebDAV'));
    expect(webDavSmokeScript, contains('Jianguoyun WebDAV'));
    expect(webDavSmokeScript, contains('RePaperTodo-Encrypted-Payload-v1'));
    expect(
      webDavSmokeScript,
      contains(
        'round trips snapshots and operation logs through a local HTTP WebDAV server',
      ),
    );
    expect(webDavSmokeScript, contains('uploadOperationLogs'));
    expect(webDavSmokeScript, contains('migrateLegacyPlainOperationLog'));
    expect(webDavSmokeScript, contains('syncEncryptionPassphrase'));
    expect(webDavSmokeScript, contains('webDavProvider'));
    expect(webDavSmokeScript, contains('Workmanager().executeTask'));
    expect(
      webDavSmokeScript,
      contains('runRePaperTodoBackgroundSync(inputData)'),
    );
    expect(webDavSmokeScript, contains('StateStore(filePath: stateFilePath)'));
    expect(webDavSmokeScript, contains('AppSyncService()).syncAndMergeNow'));
    expect(webDavSmokeScript, contains('ExistingPeriodicWorkPolicy.update'));
    expect(webDavSmokeScript, contains('_backgroundSyncCompletedWithoutRetry'));
    expect(webDavSmokeScript, contains('_isAbsoluteBackgroundStateFilePath'));
    expect(webDavSmokeScript, contains('_backgroundStateFileName'));
    expect(webDavSmokeScript, contains("!= 'data.json'"));
    expect(
      webDavSmokeScript,
      contains('Android background sync accepts POSIX absolute state paths'),
    );
    expect(webDavSmokeScript, contains('relative/data.json'));
    expect(webDavSmokeScript, contains('state.json'));
    expect(webDavSmokeScript, contains('genericWebDavSupported'));
    expect(webDavSmokeScript, contains('jianguoyunPresetSupported'));
    expect(webDavSmokeScript, contains('encryptedPayloadsRequired'));
    expect(webDavSmokeScript, contains('operationLogsSupported'));
    expect(webDavSmokeScript, contains('crossDeviceOperationRoundTripCovered'));
    expect(webDavSmokeScript, contains('localHttpWebDavRoundTripCovered'));
    expect(webDavSmokeScript, contains('sharedWindowsAndroidSettings'));
    expect(webDavSmokeScript, contains('androidBackgroundSyncSharedDartPath'));
    expect(
      webDavSmokeScript,
      contains('androidBackgroundSyncRegistrationCovered'),
    );
    expect(
      webDavSmokeScript,
      contains('androidBackgroundSyncAbsoluteStatePathCovered'),
    );
    expect(
      webDavSmokeScript,
      contains('androidBackgroundSyncDataJsonStatePathCovered'),
    );
    expect(webDavSmokeScript, contains(r'$evidenceFiles = @('));
    expect(
      webDavSmokeScript,
      contains(r'Assert-RepoEvidenceFile -RelativePath $evidenceFile'),
    );
    expect(
      webDavSmokeScript,
      contains(
        'round trips Windows and Android edits through shared WebDAV operation logs',
      ),
    );
    expect(
      webDavSmokeScript,
      contains('lib/src/sync/android_background_sync.dart'),
    );
    expect(
      webDavSmokeScript,
      contains('test/android_background_sync_test.dart'),
    );
    expect(webDavSmokeScript, contains('evidenceFiles'));
    expect(webDavSmokeScript, contains('ConvertTo-Json -Depth 4'));
    expect(webDavLiveSmokeScript, contains('REPAPERTODO_WEBDAV_ENDPOINT'));
    expect(webDavLiveSmokeScript, contains('REPAPERTODO_WEBDAV_USERNAME'));
    expect(webDavLiveSmokeScript, contains('REPAPERTODO_WEBDAV_PASSWORD'));
    expect(webDavLiveSmokeScript, contains('REPAPERTODO_WEBDAV_PASSPHRASE'));
    expect(webDavLiveSmokeScript, contains('tool\\webdav_live_smoke.dart'));
    expect(webDavLiveSmokeScript, contains('ConvertFrom-Json'));
    expect(webDavLiveSmokeScript, contains(r'[string]$ResultJson = ""'));
    expect(webDavLiveSmokeScript, contains('function Resolve-ResultJsonPath'));
    expect(
      webDavLiveSmokeScript,
      contains(
          'Live WebDAV smoke result JSON path must use the .json extension.'),
    );
    expect(
      webDavLiveSmokeScript,
      contains(
        'Live WebDAV smoke result JSON path must not contain wildcard characters.',
      ),
    );
    expect(
      webDavLiveSmokeScript,
      contains('function Assert-LiveSmokeDeviceSequences'),
    );
    expect(
      webDavLiveSmokeScript,
      contains('Live WebDAV smoke result must include deviceSequences.'),
    );
    expect(
      webDavLiveSmokeScript,
      contains(
        r'Live WebDAV smoke result must include a positive $deviceId device sequence.',
      ),
    );
    expect(webDavLiveSmokeDart, contains('REPAPERTODO_WEBDAV_ROOT'));
    expect(webDavLiveSmokeDart, contains('REPAPERTODO_WEBDAV_KEEP_REMOTE'));
    expect(webDavLiveSmokeDart, contains('windows-live-smoke'));
    expect(webDavLiveSmokeDart, contains('android-live-smoke'));
    expect(webDavLiveSmokeDart, contains('syncAndMergeNow'));
    expect(webDavLiveSmokeDart, contains('uploadLocalOperations'));
    expect(webDavLiveSmokeDart, contains('mergeRemoteOperations'));
    expect(webDavLiveSmokeDart, contains('androidOperationUploadedCount'));
    expect(webDavLiveSmokeDart, contains('windowsOperationAppliedCount'));
    expect(webDavLiveSmokeDart, contains('deviceSequences'));
    expect(webDavLiveSmokeDart, contains('client.delete(rootPath)'));
    expect(readme, contains('scripts/webdav_live_smoke.ps1'));
    expect(readme, contains('REPAPERTODO_WEBDAV_*'));
    expect(readme, contains('optional Windows manual QA result'));
    expect(readme,
        contains('optional generic and domestic WebDAV live smoke results'));
    expect(readme, contains('-WindowsManualQaResultJson'));
    expect(readme, contains('-WebDavLiveSmokeResultJson'));
    expect(readme, contains('-WebDavDomesticLiveSmokeResultJson'));
    final webDavLiveSmokeTest =
        _readProjectText('test/webdav_live_smoke_script_test.dart');
    expect(
      webDavLiveSmokeTest,
      contains('live WebDAV wrapper writes complete two-device evidence'),
    );
    expect(
      webDavLiveSmokeTest,
      contains('live WebDAV wrapper rejects missing Android device sequence'),
    );
    expect(development, contains('observed process ID'));
    expect(development, contains('one Android 14-17/API 34-37 device'));
    expect(development, contains('selects the only online device'));
    expect(development, contains('without uninstalling existing app data'));
    expect(development, contains('preferred runtime proof before publishing'));
    expect(development, contains('actual APK manifest'));
    expect(development, contains('compiled'));
    expect(development, contains('`@xml/file_paths` resource'));
    expect(development, contains('intentional'));
    expect(development, contains('cleartext flag'));
    expect(development, contains('localized APK'));
    expect(development, contains('resource configurations'));
    expect(development, contains('runtime language\nset (`zh` and `en`)'));
    final androidDeviceSmokeTest =
        _readProjectText('test/android_device_smoke_script_test.dart');
    final androidSmokeTest =
        _readProjectText('test/android_smoke_script_test.dart');
    final releaseResultJsonPathTest =
        _readProjectText('test/release_result_json_path_script_test.dart');
    expect(
      androidSmokeTest,
      contains(
          'Android APK smoke rejects unsafe result paths before reading APK'),
    );
    expect(
      releaseResultJsonPathTest,
      contains(
        'release evidence scripts reject unsafe result paths before side effects',
      ),
    );
    expect(releaseResultJsonPathTest, contains('scripts/windows_smoke.ps1'));
    expect(
      releaseResultJsonPathTest,
      contains('scripts/windows_policy_smoke.ps1'),
    );
    expect(releaseResultJsonPathTest, contains('scripts/webdav_smoke.ps1'));
    expect(
      releaseResultJsonPathTest,
      contains('scripts/webdav_live_smoke.ps1'),
    );
    expect(
      androidDeviceSmokeTest,
      contains(
        'Android device smoke wrapper writes APK-matched launch evidence',
      ),
    );
    expect(
      androidDeviceSmokeTest,
      contains('Android device smoke wrapper rejects invalid process evidence'),
    );
    expect(
      androidDeviceSmokeTest,
      contains(
        'Android device smoke wrapper rejects non-json result evidence paths',
      ),
    );
    expect(
      androidDeviceSmokeTest,
      contains(
        'Android device smoke wrapper rejects wildcard result evidence paths',
      ),
    );
    expect(androidDeviceSmokeTest, contains('fake-adb'));
    expect(androidDeviceSmokeTest, contains('fake-apkanalyzer'));
    expect(windowsSmokeScript, contains('repapertodo.exe'));
    expect(windowsSmokeScript, contains(r'[string]$ResultJson = ""'));
    expect(windowsSmokeScript, contains('function Resolve-ResultJsonPath'));
    expect(
      windowsSmokeScript,
      contains(
          'Windows release smoke result JSON path must use the .json extension.'),
    );
    expect(
      windowsSmokeScript,
      contains(
        'Windows release smoke result JSON path must not contain wildcard characters.',
      ),
    );
    expect(windowsSmokeScript, contains('checkedAtUtc'));
    expect(windowsSmokeScript, contains('initialPaperCount'));
    expect(windowsSmokeScript, contains('finalPaperCount'));
    expect(windowsSmokeScript, contains('Get-PaperTypeCounts'));
    expect(windowsSmokeScript, contains('initialTodoPaperCount'));
    expect(windowsSmokeScript, contains('finalTodoPaperCount'));
    expect(windowsSmokeScript, contains('initialNotePaperCount'));
    expect(windowsSmokeScript, contains('finalNotePaperCount'));
    expect(windowsSmokeScript, contains('Get-VisiblePaperCount'));
    expect(windowsSmokeScript, contains('hiddenStartupCommands'));
    expect(windowsSmokeScript, contains('ignoredSecondaryStartupCommands'));
    expect(
      windowsSmokeScript,
      contains(
          'unknown secondary startup command unexpectedly changed paper visibility'),
    );
    expect(
      windowsSmokeScript,
      contains('--new-note did not increase the persisted note paper count'),
    );
    expect(
      windowsSmokeScript,
      contains('--new-todo did not increase the persisted todo paper count'),
    );
    expect(windowsSmokeScript, contains('secondaryStartupCommands'));
    expect(windowsSmokeScript, contains('ConvertTo-Json -Depth 4'));
    expect(windowsSmokeScript, contains('Assert-NoExistingRePaperTodoProcess'));
    expect(windowsSmokeScript, contains('Get-Process -Name "repapertodo"'));
    expect(windowsSmokeScript, contains('WindowStyle Hidden'));
    expect(windowsSmokeScript, contains('repapertodo-windows-smoke-'));
    expect(windowsSmokeScript, contains('Copy-Item'));
    expect(windowsSmokeScript, contains('Start-Process'));
    expect(windowsSmokeScript, contains('data.json'));
    expect(windowsSmokeScript, contains('ConvertFrom-Json'));
    expect(windowsSmokeScript, contains('--hide'));
    expect(windowsSmokeScript, contains('--unknown-startup-command'));
    expect(windowsSmokeScript, contains('--new-note'));
    expect(windowsSmokeScript, contains('--new-todo'));
    expect(windowsSmokeScript, contains('--exit'));
    expect(windowsSmokeScript, contains('Remove-SmokeRoot'));
    expect(windowsSmokeScript, contains('Assert-PathInside'));
    expect(development, contains('runs the Windows release smoke test'));
    expect(
      development,
      contains('Windows release smoke and Android smoke validation run inside'),
    );
    expect(development, contains(r'.\scripts\windows_smoke.ps1'));
    expect(development, contains('isolated `repapertodo.exe`'));
    expect(development, contains('unknown-only arguments do not restore'));
    expect(development, contains('secondary `--new-note` and'));
    expect(development, contains('state out of the build output'));
    expect(windowsManualQaScript, contains('TransparentBorderlessFeel'));
    expect(windowsManualQaScript, contains('TaskSwitcherVisibility'));
    expect(windowsManualQaScript, contains('MultiMonitorEdgeDocking'));
    expect(windowsManualQaScript, contains('FullscreenAvoidance'));
    expect(windowsManualQaScript, contains('TrayAfterExplorerRestart'));
    expect(windowsManualQaScript, contains('LongRunningScriptCapsule'));
    expect(windowsManualQaScript, contains('IndependentPaperSurfaces'));
    expect(windowsManualQaScript, contains('AllowSkipped'));
    expect(windowsManualQaScript, contains('DeferMultiMonitor'));
    expect(windowsManualQaScript, contains('passedWithDeferredMultiMonitor'));
    expect(
        windowsManualQaScript,
        contains(
            "Windows manual QA item '\$Name' must be pass, fail, or skip."));
    expect(
      windowsManualQaScript,
      contains('function Resolve-ResultJsonPath'),
    );
    expect(
      windowsManualQaScript,
      contains(
          'Windows manual QA result JSON path must use the .json extension.'),
    );
    expect(
      windowsManualQaScript,
      contains(
        'Windows manual QA result JSON path must not contain wildcard characters.',
      ),
    );
    expect(windowsManualQaScript,
        contains('Windows manual QA contains skipped items.'));
    expect(
      windowsManualQaScript,
      contains('Windows manual QA passed records require -Tester'),
    );
    expect(windowsManualQaScript, contains('ConvertTo-Json -Depth 5'));
    expect(windowsManualQaScript, contains('Get-FileHash -Algorithm SHA256'));
    expect(windowsManualQaScript, contains('exeBytes'));
    expect(windowsManualQaScript, contains('exeSha256'));
    expect(windowsManualQaScript, contains('appSoRelativePath'));
    expect(windowsManualQaScript, contains('appSoBytes'));
    expect(windowsManualQaScript, contains('appSoSha256'));
    expect(windowsManualQaScript, contains('data/app.so'));
    expect(windowsManualQaScript, contains('transparentBorderlessFeel'));
    expect(windowsManualQaScript, contains('taskSwitcherVisibility'));
    expect(windowsManualQaScript, contains('multiMonitorEdgeDocking'));
    expect(windowsManualQaScript, contains('fullscreenAvoidance'));
    expect(windowsManualQaScript, contains('trayAfterExplorerRestart'));
    expect(windowsManualQaScript, contains('longRunningScriptCapsule'));
    expect(windowsManualQaScript, contains('independentPaperSurfaces'));
    expect(readme, contains('scripts/windows_manual_qa.ps1'));
    expect(readme, contains('transparent borderless feel'));
    expect(readme, contains('skipped items fail'));
    expect(readme, contains('byte counts and SHA-256 hashes'));
    expect(readme, contains('a non-empty tester name'));
    expect(readme, contains('Windows version string'));
    expect(readme, contains('exactly the expected seven checked parity items'));
    expect(readme, contains('current Windows release build'));
    expect(development, contains(r'.\scripts\windows_manual_qa.ps1'));
    expect(development, contains('-TransparentBorderlessFeel pass'));
    expect(development, contains('real desktop session'));
    expect(development, contains('byte counts and SHA-256 hashes'));
    expect(development, contains('non-empty tester name'));
    expect(development, contains('current Windows release output'));
    final windowsManualQaTest =
        _readProjectText('test/windows_manual_qa_script_test.dart');
    expect(
      windowsManualQaTest,
      contains('Windows manual QA script writes build-bound pass evidence'),
    );
    expect(
      windowsManualQaTest,
      contains('Windows manual QA script rejects skipped items by default'),
    );
    expect(
      windowsManualQaTest,
      contains(
          'Windows manual QA script records only multi-monitor as deferred'),
    );
    expect(
      windowsManualQaTest,
      contains('Windows manual QA script rejects unsafe result evidence paths'),
    );
    expect(windowsManualQaTest, contains('fake repapertodo exe bytes'));
    expect(windowsManualQaTest, contains('appSoSha256'));
    expect(development, contains('-WindowsManualQaResultJson'));
    expect(development, contains('-WebDavLiveSmokeResultJson'));
    expect(development, contains('explicit skipped Windows manual QA record'));
    expect(
        development, contains('explicit skipped WebDAV\nlive smoke records'));
  });

  test('release script parses before packaging starts', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for release script parsing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference = 'Stop'; [scriptblock]::Create((Get-Content -Raw -LiteralPath 'scripts/release.ps1')) | Out-Null",
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'scripts/release.ps1 must remain parseable before release packaging.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('release publish options reject incomplete validation gates', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for release option testing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
$ErrorActionPreference = 'Stop'
$content = Get-Content -Raw -LiteralPath 'scripts/release.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput(
  $content,
  [ref]$tokens,
  [ref]$errors
)
if ($errors.Count -gt 0) {
  throw "scripts/release.ps1 could not be parsed."
}
$function = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Assert-PublishableReleaseOptions'
}, $true)
if ($null -eq $function) {
  throw "Assert-PublishableReleaseOptions was not found."
}
Invoke-Expression $function.Extent.Text
$qaOptionsFunction = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Assert-PublishableReleaseQaOptions'
}, $true)
if ($null -eq $qaOptionsFunction) {
  throw "Assert-PublishableReleaseQaOptions was not found."
}
Invoke-Expression $qaOptionsFunction.Extent.Text

$localSmokeParams = @{
  PublishGitHubRelease = $false
  SkipTests = $true
  SkipBuild = $true
  AllowDirty = $true
  AndroidSigningMode = 'debug fallback (android/key.properties not found)'
}
Assert-PublishableReleaseOptions @localSmokeParams
Assert-PublishableReleaseQaOptions `
  -PublishGitHubRelease $false `
  -RunAndroidDeviceSmoke $false `
  -AndroidDeviceSmokeResultJson '' `
  -WindowsManualQaResultJson '' `
  -WebDavLiveSmokeResultJson '' `
  -WebDavDomesticLiveSmokeResultJson ''

$publishableParams = @{
  PublishGitHubRelease = $true
  SkipTests = $false
  SkipBuild = $false
  AllowDirty = $false
  AndroidSigningMode = 'release keystore from android/key.properties'
}
Assert-PublishableReleaseOptions @publishableParams
Assert-PublishableReleaseQaOptions `
  -PublishGitHubRelease $true `
  -RunAndroidDeviceSmoke $false `
  -AndroidDeviceSmokeResultJson 'dist/android-device-smoke.json' `
  -WindowsManualQaResultJson 'dist/windows-manual-qa.json' `
  -WebDavLiveSmokeResultJson 'dist/webdav-live-smoke.json' `
  -WebDavDomesticLiveSmokeResultJson 'dist/webdav-domestic-live-smoke.json'
Assert-PublishableReleaseQaOptions `
  -PublishGitHubRelease $true `
  -RunAndroidDeviceSmoke $true `
  -AndroidDeviceSmokeResultJson '' `
  -WindowsManualQaResultJson 'dist/windows-manual-qa.json' `
  -WebDavLiveSmokeResultJson 'dist/webdav-live-smoke.json' `
  -WebDavDomesticLiveSmokeResultJson 'dist/webdav-domestic-live-smoke.json'

foreach ($case in @(
  @{
    SkipTests = $true
    SkipBuild = $false
    AllowDirty = $false
    Signing = 'release keystore from android/key.properties'
    Expected = '*-SkipTests*'
  },
  @{
    SkipTests = $false
    SkipBuild = $true
    AllowDirty = $false
    Signing = 'release keystore from android/key.properties'
    Expected = '*-SkipBuild*'
  },
  @{
    SkipTests = $false
    SkipBuild = $false
    AllowDirty = $true
    Signing = 'release keystore from android/key.properties'
    Expected = '*-AllowDirty*'
  },
  @{
    SkipTests = $false
    SkipBuild = $false
    AllowDirty = $false
    Signing = 'debug fallback (android/key.properties not found)'
    Expected = '*requires Android release signing*'
  }
)) {
  try {
    $caseParams = @{
      PublishGitHubRelease = $true
      SkipTests = $case.SkipTests
      SkipBuild = $case.SkipBuild
      AllowDirty = $case.AllowDirty
      AndroidSigningMode = $case.Signing
    }
    Assert-PublishableReleaseOptions @caseParams
    throw 'Expected publish option gate to reject the case.'
  } catch {
    if ($_.Exception.Message -notlike $case.Expected) {
      throw
    }
  }
}
Write-Host 'publish option gates passed'

foreach ($case in @(
  @{
    RunAndroidDeviceSmoke = $true
    AndroidDeviceSmokeResultJson = ''
    WindowsManualQaResultJson = ''
    WebDavLiveSmokeResultJson = 'dist/webdav-live-smoke.json'
    WebDavDomesticLiveSmokeResultJson = 'dist/webdav-domestic-live-smoke.json'
    Expected = '*Windows manual QA evidence*'
  },
  @{
    RunAndroidDeviceSmoke = $true
    AndroidDeviceSmokeResultJson = ''
    WindowsManualQaResultJson = 'dist/windows-manual-qa.json'
    WebDavLiveSmokeResultJson = ''
    WebDavDomesticLiveSmokeResultJson = 'dist/webdav-domestic-live-smoke.json'
    Expected = '*generic WebDAV live smoke evidence*'
  },
  @{
    RunAndroidDeviceSmoke = $true
    AndroidDeviceSmokeResultJson = ''
    WindowsManualQaResultJson = 'dist/windows-manual-qa.json'
    WebDavLiveSmokeResultJson = 'dist/webdav-live-smoke.json'
    WebDavDomesticLiveSmokeResultJson = ''
    Expected = '*domestic WebDAV live smoke evidence*'
  },
  @{
    RunAndroidDeviceSmoke = $false
    AndroidDeviceSmokeResultJson = ''
    WindowsManualQaResultJson = 'dist/windows-manual-qa.json'
    WebDavLiveSmokeResultJson = 'dist/webdav-live-smoke.json'
    WebDavDomesticLiveSmokeResultJson = 'dist/webdav-domestic-live-smoke.json'
    Expected = '*Android runtime smoke evidence*'
  },
  @{
    RunAndroidDeviceSmoke = $true
    AndroidDeviceSmokeResultJson = 'dist/android-device-smoke.json'
    WindowsManualQaResultJson = 'dist/windows-manual-qa.json'
    WebDavLiveSmokeResultJson = 'dist/webdav-live-smoke.json'
    WebDavDomesticLiveSmokeResultJson = 'dist/webdav-domestic-live-smoke.json'
    Expected = '*either -RunAndroidDeviceSmoke or -AndroidDeviceSmokeResultJson*'
  }
)) {
  try {
    Assert-PublishableReleaseQaOptions `
      -PublishGitHubRelease $true `
      -RunAndroidDeviceSmoke $case.RunAndroidDeviceSmoke `
      -AndroidDeviceSmokeResultJson $case.AndroidDeviceSmokeResultJson `
      -WindowsManualQaResultJson $case.WindowsManualQaResultJson `
      -WebDavLiveSmokeResultJson $case.WebDavLiveSmokeResultJson `
      -WebDavDomesticLiveSmokeResultJson $case.WebDavDomesticLiveSmokeResultJson
    throw 'Expected publish QA option gate to reject the case.'
  } catch {
    if ($_.Exception.Message -notlike $case.Expected) {
      throw
    }
  }
}
Write-Host 'publish QA option gates passed'
''',
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'GitHub Release publishing must reject skipped tests, skipped builds, dirty local packages, debug signing, and missing QA evidence.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('release asset verification rejects stale GitHub assets', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for release asset testing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
$ErrorActionPreference = 'Stop'
$content = Get-Content -Raw -LiteralPath 'scripts/release.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput(
  $content,
  [ref]$tokens,
  [ref]$errors
)
if ($errors.Count -gt 0) {
  throw "scripts/release.ps1 could not be parsed."
}
$function = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Assert-GitHubReleaseAssets'
}, $true)
if ($null -eq $function) {
  throw "Assert-GitHubReleaseAssets was not found."
}
Invoke-Expression $function.Extent.Text
function Invoke-NativeText {
  param([string]$Name, [scriptblock]$Action)
  return '{"assets":[{"name":"expected.txt","size":1,"state":"uploaded"},{"name":"old.zip","size":3,"state":"uploaded"}]}'
}
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "repapertodo-release-asset-test-$([Guid]::NewGuid().ToString('N'))"
try {
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
  $expected = Join-Path $tempRoot 'expected.txt'
  [IO.File]::WriteAllText($expected, 'x', [Text.Encoding]::ASCII)
  try {
    Assert-GitHubReleaseAssets -TagName 'v-test' -ArtifactPaths @($expected)
    throw 'Expected stale GitHub Release assets to fail verification.'
  } catch {
    if ($_.Exception.Message -notlike '*unexpected asset*') {
      throw
    }
  }
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
''',
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'Release publishing must reject stale extra GitHub Release assets.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('release asset verification requires uploaded GitHub asset state',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for release asset testing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
$ErrorActionPreference = 'Stop'
$content = Get-Content -Raw -LiteralPath 'scripts/release.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput(
  $content,
  [ref]$tokens,
  [ref]$errors
)
if ($errors.Count -gt 0) {
  throw "scripts/release.ps1 could not be parsed."
}
$function = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Assert-GitHubReleaseAssets'
}, $true)
if ($null -eq $function) {
  throw "Assert-GitHubReleaseAssets was not found."
}
Invoke-Expression $function.Extent.Text
$script:releaseAssetJson = ''
function Invoke-NativeText {
  param([string]$Name, [scriptblock]$Action)
  return $script:releaseAssetJson
}
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "repapertodo-release-asset-state-test-$([Guid]::NewGuid().ToString('N'))"
try {
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
  $expected = Join-Path $tempRoot 'expected.txt'
  [IO.File]::WriteAllText($expected, 'x', [Text.Encoding]::ASCII)

  foreach ($case in @(
    @{
      Json = '{"assets":[{"name":"expected.txt","size":1}]}'
      Expected = '*missing its upload state*'
    },
    @{
      Json = '{"assets":[{"name":"expected.txt","size":1,"state":"starter"}]}'
      Expected = '*not fully uploaded*'
    }
  )) {
    $script:releaseAssetJson = $case.Json
    try {
      Assert-GitHubReleaseAssets -TagName 'v-test' -ArtifactPaths @($expected)
      throw 'Expected incomplete GitHub Release asset state to fail verification.'
    } catch {
      if ($_.Exception.Message -notlike $case.Expected) {
        throw
      }
    }
  }
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
''',
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'Release publishing must require GitHub Release assets to be fully uploaded.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('Android APK smoke script parses before it runs', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for smoke script parsing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference = 'Stop'; [scriptblock]::Create((Get-Content -Raw -LiteralPath 'scripts/android_smoke.ps1')) | Out-Null",
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'scripts/android_smoke.ps1 must remain parseable before Android smoke.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('Android device smoke script parses before it runs', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for smoke script parsing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference = 'Stop'; [scriptblock]::Create((Get-Content -Raw -LiteralPath 'scripts/android_device_smoke.ps1')) | Out-Null",
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'scripts/android_device_smoke.ps1 must remain parseable before Android device smoke.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('Windows release smoke script parses before it runs', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for smoke script parsing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference = 'Stop'; [scriptblock]::Create((Get-Content -Raw -LiteralPath 'scripts/windows_smoke.ps1')) | Out-Null",
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'scripts/windows_smoke.ps1 must remain parseable before Windows smoke.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('Windows policy smoke script parses before it runs', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for smoke script parsing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference = 'Stop'; [scriptblock]::Create((Get-Content -Raw -LiteralPath 'scripts/windows_policy_smoke.ps1')) | Out-Null",
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'scripts/windows_policy_smoke.ps1 must remain parseable before Windows policy smoke.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('Windows manual QA script parses before it runs', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for smoke script parsing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference = 'Stop'; [scriptblock]::Create((Get-Content -Raw -LiteralPath 'scripts/windows_manual_qa.ps1')) | Out-Null",
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'scripts/windows_manual_qa.ps1 must remain parseable before Windows manual QA.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('WebDAV static smoke script parses before it runs', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for smoke script parsing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference = 'Stop'; [scriptblock]::Create((Get-Content -Raw -LiteralPath 'scripts/webdav_smoke.ps1')) | Out-Null",
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'scripts/webdav_smoke.ps1 must remain parseable before WebDAV smoke.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('WebDAV live smoke script parses before it runs', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for smoke script parsing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference = 'Stop'; [scriptblock]::Create((Get-Content -Raw -LiteralPath 'scripts/webdav_live_smoke.ps1')) | Out-Null",
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'scripts/webdav_live_smoke.ps1 must remain parseable before live WebDAV smoke.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('WebDAV live CLI avoids Flutter-only umbrella imports', () {
    final tool = _readProjectText('tool/webdav_live_smoke.dart');
    expect(
        tool,
        contains(
            "import 'package:repapertodo/src/sync/app_sync_service.dart';"));
    expect(tool,
        isNot(contains("import 'package:repapertodo/repapertodo.dart';")));
    expect(
      _readProjectText('lib/src/sync/sync_text_limits.dart'),
      contains('maxMarkdownTextLength'),
    );
  });

  test('release readiness audit keeps publish blockers explicit', () {
    final script = _readProjectText('scripts/release_readiness_audit.ps1');
    final readme = _readProjectText('README.md');
    final development = _readProjectText('docs/DEVELOPMENT.md');
    final auditTest =
        _readProjectText('test/release_readiness_audit_test.dart');

    expect(script, contains('readyForGitHubRelease'));
    expect(script, contains('readyForLocalRelease'));
    expect(script, contains('localBlockers'));
    expect(script, contains('webDav.liveSmoke'));
    expect(script, contains('releaseMetadataRecord.webDav.liveSmoke'));
    expect(script, contains('releaseMetadataRecord.android.deviceSmoke'));
    expect(script, contains('runtimeLanguages'));
    expect(script, contains('cleanGitTree'));
    expect(script, contains('androidSigning'));
    expect(script, contains('windowsManualQa'));
    expect(script, contains('webDavLiveSmoke'));
    expect(script, contains('webDavDomesticLiveSmoke'));
    expect(script, contains('androidDeviceSmoke'));
    expect(script, contains('ExpectedWindowsReleaseDirectory'));
    expect(script, contains('ExpectedAndroidApkFileName'));
    expect(script, contains('ExpectedAndroidApkPath'));
    expect(script, contains('ReleaseMetadataJson'));
    expect(script, contains('ReleaseChecksumsFile'));
    expect(script, contains('ReleaseChecksumsPath'));
    expect(script, contains('releaseMetadata'));
    expect(script, contains('releaseChecksums'));
    expect(script, contains('FailOnBlocked'));
    expect(
      script,
      contains('Runtime UI languages are limited to zh and en.'),
    );
    expect(
      script,
      contains('Android release publishing requires a release keystore'),
    );
    expect(
      script,
      contains('GitHub Release publishing requires a clean working tree.'),
    );
    expect(
      script,
      contains(
          'Windows manual QA evidence must have status passed or passedWithDeferredMultiMonitor.'),
    );
    expect(
      script,
      contains('Windows manual QA evidence must include a tester.'),
    );
    expect(
      script,
      contains('Windows manual QA evidence must include windowsVersion.'),
    );
    expect(
      script,
      contains(r'Windows manual QA evidence must include positive $property.'),
    );
    expect(
      script,
      contains(
        r'Windows manual QA evidence must include lowercase SHA-256 $property.',
      ),
    );
    expect(
      script,
      contains('Windows manual QA evidence must reference data/app.so.'),
    );
    expect(
      script,
      contains(
        'Windows manual QA evidence exe byte count must match the expected release build.',
      ),
    );
    expect(
      script,
      contains(
        'Windows manual QA evidence data/app.so SHA-256 must match the expected release build.',
      ),
    );
    expect(
      script,
      contains(
        r'Windows manual QA evidence must include exactly $($expectedIds.Count) checked items.',
      ),
    );
    expect(
      script,
      contains('WebDAV live smoke evidence must have status passed.'),
    );
    expect(
      script,
      contains('WebDAV live smoke evidence must include deviceSequences.'),
    );
    expect(
      script,
      contains(
        r'WebDAV live smoke evidence must include a positive $deviceId device sequence.',
      ),
    );
    expect(
      script,
      contains('WebDAV live smoke evidence must use providerId'),
    );
    expect(
      script,
      contains('Android device smoke evidence must be from Android 14-17'),
    );
    expect(
      script,
      contains(
        'Android device smoke evidence must include a positive integer processId.',
      ),
    );
    expect(
      script,
      contains('Android device smoke evidence must include positive apkBytes.'),
    );
    expect(
      script,
      contains(
        'Android device smoke evidence must include lowercase SHA-256 apkSha256.',
      ),
    );
    expect(
      script,
      contains(
        'Android device smoke evidence APK byte count must match the expected APK.',
      ),
    );
    expect(
      script,
      contains(
        'Android device smoke evidence APK SHA-256 must match the expected APK.',
      ),
    );
    expect(
      script,
      contains(
        'Android device smoke expected APK file name must match pubspec.yaml version.',
      ),
    );
    expect(
      script,
      contains(
        'Android device smoke expected APK path must match pubspec.yaml version.',
      ),
    );
    expect(
      script,
      contains(
        'Release metadata runtime.supportedLanguages must be exactly zh,en.',
      ),
    );
    expect(
      script,
      contains('Release metadata version must match pubspec.yaml.'),
    );
    expect(
      script,
      contains('Release metadata tagName must match pubspec.yaml version.'),
    );
    expect(
      script,
      contains(
        'Release metadata JSON file name must match pubspec.yaml version.',
      ),
    );
    expect(
      script,
      contains('Release metadata must include Flutter toolchain information.'),
    );
    expect(
      script,
      contains(
        r'Release metadata toolchain.$property must match the current Flutter toolchain.',
      ),
    );
    expect(
      script,
      contains(
        'Release metadata artifacts must include exactly one',
      ),
    );
    expect(
      script,
      contains('Release metadata dependencyLock must reference pubspec.lock.'),
    );
    expect(
      script,
      contains(
        'Release metadata dependencyLock SHA-256 must match pubspec.lock.',
      ),
    );
    expect(
      script,
      contains(
        r'Release metadata $Context file name must match pubspec.yaml version.',
      ),
    );
    expect(
      script,
      contains(r'Release metadata $Context SHA-256 must match the file.'),
    );
    expect(
      script,
      contains(
        'Release metadata Windows smoke must prove unknown secondary startup commands do not restore hidden papers.',
      ),
    );
    expect(
      script,
      contains('Release metadata WebDAV static smoke must confirm'),
    );
    expect(
      script,
      contains('Release metadata Android SDK fields must target Android 14-17'),
    );
    expect(script, contains('androidLocaleConfigPresent'));
    expect(script, contains('localeConfigLanguages'));
    expect(
      script,
      contains(
        'Release metadata Android static smoke must pass with only zh,en localized resources and localeConfig.',
      ),
    );
    expect(
      script,
      contains('Release metadata artifact file was not found'),
    );
    expect(
      script,
      contains(
        r"Release metadata artifact '$fileName' byte count must match the file.",
      ),
    );
    expect(
      script,
      contains(
        r"Release metadata artifact '$fileName' SHA-256 must match the file.",
      ),
    );
    expect(
      script,
      contains('Release checksum audit requires -ReleaseMetadataJson.'),
    );
    expect(
      script,
      contains(
          'Release checksum file name must match release metadata version.'),
    );
    expect(
      script,
      contains('Release checksum file matches metadata and packaged files.'),
    );
    expect(
      script,
      contains(r'Release checksum file line $($index + 1) must match'),
    );
    expect(
      script,
      contains(
        r"Release checksum artifact '$fileName' SHA-256 must match the file.",
      ),
    );
    expect(readme, contains('scripts\\release_readiness_audit.ps1'));
    expect(readme, contains('-ExpectedWindowsReleaseDirectory'));
    expect(readme, contains('-ExpectedAndroidApkPath'));
    expect(
      readme,
      contains('Android device smoke expected APK file name\nand path'),
    );
    expect(readme, contains('-ReleaseMetadataJson'));
    expect(readme, contains('-ReleaseChecksumsFile'));
    expect(readme, contains('readyForGitHubRelease'));
    expect(readme, contains('metadata JSON/checksum file names'));
    expect(readme, contains('metadata `version`/`tagName`'));
    expect(readme, contains('artifact\nfile names matching `pubspec.yaml`'));
    expect(readme, contains('metadata artifact file name'));
    expect(readme, contains('neighboring Windows zip and Android APK files'));
    expect(readme, contains('checksum-file line matching'));
    expect(readme, contains('metadata JSON, and'));
    expect(readme, contains('release notes markdown'));
    expect(
      readme,
      contains('metadata release notes file name/byte/hash'),
    );
    expect(readme, contains('metadata Flutter/Dart toolchain fields'));
    expect(readme, contains('current `flutter --version --machine` output'));
    expect(readme, contains('`pubspec.lock` byte/hash'));
    expect(readme, contains('runtime language set (`zh` and `en`)'));
    expect(
      development,
      contains('scripts/release_readiness_audit.ps1'),
    );
    expect(development, contains('-ExpectedWindowsReleaseDirectory'));
    expect(development, contains('expected Windows\nexe and `data/app.so`'));
    expect(development, contains('-ExpectedAndroidApkPath'));
    expect(
      development,
      contains('Android device smoke expected APK file name\nand path'),
    );
    expect(development, contains('-ReleaseMetadataJson'));
    expect(development, contains('-ReleaseChecksumsFile'));
    expect(development, contains('expected APK byte/hash matching'));
    expect(development, contains('release metadata\nJSON/checksum file names'));
    expect(development, contains('`version`/`tagName`'));
    expect(development, contains('artifact file names matching'));
    expect(development, contains('metadata artifact file'));
    expect(development, contains('neighboring Windows zip and\nAndroid APK'));
    expect(development, contains('checksum-file line matching'));
    expect(development, contains('metadata JSON,\nand release notes markdown'));
    expect(
      development,
      contains('metadata release notes file name/byte/hash'),
    );
    expect(development, contains('metadata Flutter/Dart toolchain fields'));
    expect(
      development,
      contains('current `flutter --version --machine` output'),
    );
    expect(development, contains('`pubspec.lock` byte/hash'));
    expect(development, contains('Android 14-17/API 34-37 device smoke'));
    expect(
      auditTest,
      contains(
          'readiness audit rejects unsafe result JSON paths before writing'),
    );
    expect(
      auditTest,
      contains('readiness audit rejects unsafe input JSON evidence paths'),
    );
    expect(
      auditTest,
      contains(
        'readiness audit accepts artifact-matched Windows and Android evidence',
      ),
    );
    expect(
      auditTest,
      contains(
        'readiness audit writes result JSON before failing blocked CI gate',
      ),
    );
    expect(
      auditTest,
      contains('readiness audit accepts release metadata pinned to zh and en'),
    );
    expect(
      auditTest,
      contains(
        'readiness audit rejects release metadata with extra runtime language',
      ),
    );
    expect(
      auditTest,
      contains(
        'readiness audit rejects release metadata from another pubspec version',
      ),
    );
    expect(
      auditTest,
      contains('readiness audit rejects release metadata with wrong file name'),
    );
    expect(
      auditTest,
      contains('readiness audit rejects release metadata with stale toolchain'),
    );
    expect(
      auditTest,
      contains(
          'readiness audit rejects release metadata with stale artifact hash'),
    );
    expect(
      auditTest,
      contains(
        'readiness audit rejects release metadata with stale dependency lock',
      ),
    );
    expect(
      auditTest,
      contains(
        'readiness audit rejects release metadata with stale release notes hash',
      ),
    );
    expect(
      auditTest,
      contains(
        'readiness audit accepts release checksum file matched to metadata',
      ),
    );
    expect(
      auditTest,
      contains('readiness audit accepts ReleaseChecksumsPath alias'),
    );
    expect(
      auditTest,
      contains(
        'readiness audit rejects release checksum file with wrong file name',
      ),
    );
    expect(
      auditTest,
      contains('readiness audit rejects release checksum file with stale line'),
    );
    expect(
      auditTest,
      contains('readiness audit rejects Windows manual QA from another build'),
    );
    expect(
      auditTest,
      contains(
        'readiness audit rejects unattributed Windows manual QA evidence',
      ),
    );
    expect(
      auditTest,
      contains('readiness audit rejects Windows manual QA without OS evidence'),
    );
    expect(
      auditTest,
      contains('readiness audit rejects Windows manual QA with extra items'),
    );
    expect(
      auditTest,
      contains('readiness audit rejects Android device smoke from another APK'),
    );
    expect(
      auditTest,
      contains(
        'readiness audit rejects Android device smoke with wrong expected APK name',
      ),
    );
    expect(
      auditTest,
      contains(
        'readiness audit rejects Android device smoke with wrong expected APK path',
      ),
    );
    expect(
      auditTest,
      contains(
        'readiness audit accepts generic and domestic WebDAV live evidence',
      ),
    );
    expect(
      auditTest,
      contains(
        'readiness audit rejects domestic WebDAV live smoke from generic provider',
      ),
    );
    expect(auditTest, contains("providerId: 'jianguoyun'"));
    expect(
      auditTest,
      contains(
        'readiness audit rejects WebDAV live smoke without Android sequence',
      ),
    );
    expect(auditTest, contains('ExpectedWindowsReleaseDirectory'));
    expect(auditTest, contains('ExpectedAndroidApkPath'));
    expect(
      auditTest,
      contains('Windows manual QA evidence exe SHA-256 must match'),
    );
    expect(
      auditTest,
      contains('Android device smoke evidence APK SHA-256 must match'),
    );
  });

  test('release readiness audit script parses before it runs', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped(
          'PowerShell is unavailable for readiness script parsing.');
      return;
    }

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference = 'Stop'; [scriptblock]::Create((Get-Content -Raw -LiteralPath 'scripts/release_readiness_audit.ps1')) | Out-Null",
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'scripts/release_readiness_audit.ps1 must remain parseable before release readiness audit.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });
}
