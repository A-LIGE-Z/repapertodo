import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readProjectText(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

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

  test('Android build targets Android 14 through 17', () {
    final gradle = _readProjectText('android/app/build.gradle.kts');
    final manifest =
        _readProjectText('android/app/src/main/AndroidManifest.xml');
    final filePaths =
        _readProjectText('android/app/src/main/res/xml/file_paths.xml');
    final gitignore = _readProjectText('.gitignore');
    final readme = _readProjectText('README.md');
    final mainActivity = _readProjectText(
        'android/app/src/main/kotlin/com/aligez/repapertodo/MainActivity.kt');

    expect(gradle, contains('compileSdk = 37'));
    expect(gradle, contains('minSdk = 34'));
    expect(gradle, contains('targetSdk = 37'));
    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, contains('val releaseStoreFile'));
    expect(gradle, contains('hasReleaseSigningConfig'));
    expect(gradle, contains('releaseStoreFile?.isFile == true'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, contains('signingConfigs.getByName("debug")'));
    expect(gradle, contains('enableV2Signing = true'));
    expect(gradle, contains('enableV3Signing = true'));
    expect(gitignore, contains('android/key.properties'));
    expect(gitignore, contains('*.jks'));
    expect(readme, contains('Android release signing'));
    expect(readme, contains('debug fallback'));
    expect(readme, contains('android/key.properties'));
    expect(readme, contains('storeFile` points to an existing keystore file'));
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android:usesCleartextTraffic="true"'));
    expect(manifest, contains('androidx.core.content.FileProvider'));
    expect(manifest, contains('android:grantUriPermissions="true"'));
    expect(filePaths, contains('<files-path'));
    expect(filePaths, contains('<cache-path'));
    expect(filePaths, contains('<external-files-path'));
    expect(filePaths, contains('<external-path'));
    expect(mainActivity, contains('FileProvider.getUriForFile'));
    expect(mainActivity, contains('MimeTypeMap'));
    expect(mainActivity, contains('getMimeTypeFromExtension'));
    expect(mainActivity, contains('distinct()'));
    expect(mainActivity, contains('ClipData.newUri'));
    expect(mainActivity, contains('val trimmedUri = uri.trim()'));
    expect(mainActivity, contains('val parsedUri = try'));
    expect(mainActivity, contains('The URI is not valid.'));
    expect(mainActivity, contains('val trimmedPath = path.trim()'));
    expect(mainActivity, contains('!file.isFile'));
    expect(mainActivity, contains('parsedUri.scheme'));
    expect(mainActivity, contains('uri.userInfo.isNullOrBlank()'));
    expect(mainActivity, contains('uri.encodedAuthority'));
    expect(mainActivity, contains('hasEncodedExternalUriAuthoritySeparator'));
    expect(mainActivity, contains('hasUnsafeExternalUriCharacter'));
    expect(mainActivity, contains('hasMalformedExternalUriPercentEscape'));
    expect(mainActivity, contains('The URI contains malformed escapes.'));
    expect(mainActivity, contains('hasEncodedUnsafeExternalUriCharacter'));
    expect(mainActivity, contains('hasUnsafeExternalFilePathCharacter'));
    expect(mainActivity, contains('isAllowedExternalUri'));
    expect(mainActivity, contains('"mailto"'));
    expect(mainActivity, contains('val recipient = uri.schemeSpecificPart'));
    expect(
      mainActivity,
      contains('uri.authority.isNullOrBlank() && recipient.isNotBlank()'),
    );
    expect(mainActivity, contains('Intent.CATEGORY_BROWSABLE'));
    expect(mainActivity, contains('file_provider_failed'));
    expect(mainActivity, contains('SecurityException'));
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

    expect(design, contains('reject blank launch\narguments'));
    expect(design, contains('percent-encoded control characters'));
    expect(design, contains('malformed percent escapes'));
    expect(design, contains('encoded authority separators'));
    expect(design, contains('external-file paths must reject raw control'));
    expect(design, contains('Generated external Markdown export filenames'));
    expect(design, contains('External Markdown extension settings'));
    expect(design, contains('including DEL and C1 controls'));
    expect(app, contains(r'[<>:"/\\|?*\x00-\x1F\x7F-\x9F]'));
    expect(app, contains('normalizeExternalUriTarget'));
    expect(
        externalUriTargets, contains('hasEncodedUnsafeExternalUriCharacter'));
    expect(
        externalUriTargets, contains('hasMalformedExternalUriPercentEscape'));
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
    expect(windows, contains('hasEncodedExternalUriAuthoritySeparator'));
    expect(windows, contains('isAllowedExternalUriTarget'));
    expect(windows, contains('Windows external file path must not be blank.'));
    expect(
        windows,
        contains(
            'Windows external file path must not contain control characters.'));
    final appState = _readProjectText('lib/src/core/model/app_state.dart');
    final settingsDialog =
        _readProjectText('lib/src/ui/sync_settings_dialog.dart');
    expect(appState, contains('rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)'));
    expect(
      settingsDialog,
      contains('rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)'),
    );
  });

  test('sync design preserves merge safety rules', () {
    final syncDesign = _readProjectText('docs/SYNC.md');
    final appStateCodec =
        _readProjectText('lib/src/core/state/app_state_codec.dart');
    final appSyncServiceSource =
        _readProjectText('lib/src/sync/app_sync_service.dart');

    expect(syncDesign, contains('earliest `createdAtUtc` first'));
    expect(syncDesign, contains('Tombstone timestamps only move forward'));
    expect(
        syncDesign, contains('Settings operations are intentionally limited'));
    expect(syncDesign, contains('startup-at-login state'));
    expect(appStateCodec, contains("json.remove('startAtLogin')"));
    expect(appSyncServiceSource, contains('remoteState.startAtLogin'));
    expect(syncDesign,
        contains('Local device sequence progress must never move backward'));
    expect(syncDesign, contains('Upload result sequence maps'));
    expect(syncDesign, contains('fractional numbers and leading/trailing'));
    expect(syncDesign, contains('instead of rounded or trimmed'));
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
    expect(syncDesign, contains('defaults to 30 seconds'));
    expect(syncDesign, contains('default to 15\nminutes'));
    expect(syncDesign, contains('normalized to 1 through 1440 minutes'));
    expect(syncDesign, contains('normalized to 1 through'));
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
    expect(syncDesign, contains('metadata must be taken from the entry'));
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
    expect(syncDesign, contains('whose device ID normalizes to blank'));
    expect(syncDesign, contains('local persistence of accepted'));
    expect(syncDesign, contains('pending local edits can retry'));
    expect(
        syncDesign, contains('Manifest device sequences must reject values'));
    expect(syncDesign, contains('Manifest `updatedAtUtc` wire timestamps'));
    expect(syncDesign,
        contains('Local operation diff generation and merge application'));
    expect(syncDesign,
        contains('Merge application must apply matching duplicate'));
    expect(syncDesign, contains('conflicting duplicate operations must block'));
    expect(syncDesign, contains('Operation `createdAtUtc` wire timestamps'));
    expect(syncDesign,
        contains('Operation sequence numbers accept positive integer'));
    expect(syncDesign, contains('overflow dates or times'));
    expect(syncDesign, contains('invalid time-zone offsets'));
    expect(syncDesign, contains('leading or\ntrailing whitespace'));
    expect(syncDesign, contains('operation-log'));
    expect(syncDesign, contains('does not match their\noperation-log path'));
    expect(syncDesign, contains('downloaded result path does not match'));
    expect(syncDesign, contains('not legacy plain JSON'));
    expect(syncDesign, contains('exactly one operation'));
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
    expect(syncDesign, contains('Opening settings must pause pending'));
    expect(syncDesign, contains('canceling settings or saving settings'));
    expect(
        syncDesign, contains('without changing sync configuration restores'));
    expect(syncDesign, contains('platform setting application reports errors'));
    expect(syncDesign, contains('saving sync setting changes clears'));
    expect(syncDesign, contains('Settings save failures must surface'));
    expect(syncDesign, contains('later local edits blocked'));
    expect(syncDesign, contains('downloads can reach the network'));
    expect(syncDesign, contains('direct child files'));
    expect(syncDesign, contains('Direct remote path segments'));
    expect(syncDesign, contains('decode to path separators'));
    expect(syncDesign, contains('Listing `href` path segments'));
    expect(syncDesign, contains('must keep their decoded edge characters'));
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
    expect(syncDesign, contains('Absolute metadata `href` matches'));
    expect(syncDesign, contains('same WebDAV origin'));
    expect(syncDesign, contains('Metadata `href` matches with query'));
    expect(syncDesign, contains('silently dropping non-path URI parts'));
    expect(syncDesign,
        contains('paths can be compared with the requested resource'));
    expect(syncDesign, contains('percent-encoded dot-segments'));
    expect(syncDesign, contains('different resource path'));
    expect(syncDesign, contains('Relative metadata `href` matches'));
    expect(syncDesign, contains('not an arbitrary suffix'));
    expect(syncDesign, contains('404 Not Found'));
    expect(syncDesign, contains('410 Gone'));
    expect(syncDesign, contains('direct payload downloads must still fail'));
    expect(syncDesign, contains('If `manifest.json` disappears'));
    expect(syncDesign, contains('`If-None-Match: *`'));
    expect(syncDesign, contains('explicit `Accept` headers'));
    expect(syncDesign, contains('stable `User-Agent`'));
    expect(syncDesign, contains('`PROPFIND` prefers XML responses'));
    expect(syncDesign, contains('Provider `Retry-After` hints'));
    expect(syncDesign, contains('Missing or weak ETags must not be used for'));
    expect(syncDesign, contains('Provider `409` or `412` create-only'));
    expect(syncDesign, contains('original create-only conflict is preserved'));
    expect(syncDesign, contains('localized already-exists wording'));
    expect(syncDesign, contains('retryable WebDAV error messages'));
    expect(syncDesign, contains('Absolute `href` values are accepted only'));
    expect(syncDesign, contains('cross-origin or'));
    expect(syncDesign, contains('base-path-escaping listing entries'));
    expect(syncDesign, contains('decode to path separators or dot-segments'));
    expect(syncDesign, contains('relative and server-absolute'));
    expect(syncDesign, contains('collapse to blank'));
    expect(syncDesign, contains('percent-encoded control characters'));
    expect(syncDesign, contains('local\nsnapshot or operation-log records'));
    expect(syncDesign, contains('Network-path `href` values'));
    expect(syncDesign, contains('decode into network-path or'));
    expect(syncDesign, contains('Plain relative'));
    expect(syncDesign, contains('must already start at the sync root'));
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
    expect(webDavClient, contains('_hrefRawPathHasDotSegments'));
    expect(webDavClient, contains('_rawHrefPath'));
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
    final appSyncService =
        _readProjectText('lib/src/sync/app_sync_service.dart');
    final app = _readProjectText('lib/src/app.dart');
    final webDavPayloadCodec =
        _readProjectText('lib/src/sync/webdav/webdav_payload_codec.dart');
    expect(wireDateTime, contains('parseStrictSyncWireDateTimeUtc'));
    expect(wireDateTime, contains('tryParseStrictSyncWireDateTimeUtc'));
    expect(syncSettings, contains('tryParseStrictSyncWireDateTimeUtc'));
    expect(syncSettings, isNot(contains('DateTime.tryParse')));
    expect(syncSettings, contains('_syncDeviceSequencesFromWire'));
    expect(syncSettings, isNot(contains('operationDeviceSequences: intMap')));
    expect(syncSettings, isNot(contains('int.tryParse(value.trim())')));
    expect(syncManifest, contains('parseStrictSyncWireDateTimeUtc'));
    expect(syncManifest, isNot(contains('DateTime.tryParse')));
    expect(syncManifest, isNot(contains('int.tryParse(value.trim())')));
    expect(syncOperation, contains('parseStrictSyncWireDateTimeUtc'));
    expect(syncOperation, isNot(contains('DateTime.tryParse')));
    expect(syncOperation, isNot(contains('int.tryParse(value.trim())')));
    expect(syncOperationApplier, contains('_hasConflictingDuplicateAt'));
    expect(syncOperationApplier, contains('_operationsMatch'));
    expect(appSyncService, contains('tryParseStrictSyncWireDateTimeUtc'));
    expect(appSyncService, isNot(contains('DateTime.tryParse')));
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
    expect(app, contains('_clearPendingLocalEditSync'));
    expect(app, contains('_localEditSyncGeneration'));
    expect(webDavPayloadCodec, contains('_saltLength'));
    expect(webDavPayloadCodec, contains('_nonceLength'));
    expect(webDavPayloadCodec, contains('_macLength'));
    expect(webDavPayloadCodec, contains('invalid envelope field sizes'));
    expect(webDavPayloadCodec, contains('_stringField'));
  });

  test('Windows runner preserves startup command parsing parity', () {
    final runner = _readProjectText('windows/runner/main.cpp');
    final dartParser =
        _readProjectText('lib/src/core/startup/startup_command.dart');
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');

    expect(runner, contains('find_first_of("=:", segment_start)'));
    expect(runner, contains('CreatedPaperStartupCommand'));
    expect(runner, contains('IsExplicitExitStartupCommand'));
    expect(runner, contains('OpenMutexW(SYNCHRONIZE'));
    expect(design, contains('return before creating the'));
    expect(
      runner.indexOf('if (IsExplicitExitStartupCommand'),
      lessThan(runner.indexOf('flutter::DartProject project')),
    );
    expect(dartParser, contains("RegExp(r'[=:]+')"));
    expect(dartParser, contains('_createdPaperKind'));
  });

  test('Windows runner forwards secondary instance startup commands', () {
    final entrypoint = _readProjectText('windows/runner/main.cpp');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final dartParser =
        _readProjectText('lib/src/core/startup/startup_command.dart');

    expect(entrypoint, contains('kSingleInstanceMutexName'));
    expect(entrypoint, contains('kSingleInstancePipeName'));
    expect(entrypoint, contains('CreateMutexW'));
    expect(entrypoint, contains('ERROR_ALREADY_EXISTS'));
    expect(entrypoint, contains('StartupCommandFromArgs'));
    expect(entrypoint, contains('reveal-pinned-todo'));
    expect(entrypoint, contains('reveal-pinned-note'));
    expect(dartParser, contains('reveal-pinned-todo'));
    expect(dartParser, contains('reveal-pinned-note'));
    expect(
        entrypoint, contains('SignalPrimaryInstance(command_line_arguments)'));
    expect(entrypoint, contains('CreateFileW(kSingleInstancePipeName'));
    expect(entrypoint, contains('WriteFile(pipe, command.data()'));
    expect(entrypoint, contains('WaitNamedPipeW(kSingleInstancePipeName'));
    expect(runner, contains('StartSingleInstanceListener();'));
    expect(runner, contains('CreateNamedPipeW'));
    expect(
        runner, contains('PostMessageW(window, kSingleInstanceCommandMessage'));
    expect(runner, contains('case kSingleInstanceCommandMessage'));
    expect(runner, contains('SendStartupCommandRequested(*command)'));
    expect(runner, contains('StopSingleInstanceListener();'));
    expect(runner, contains('single_instance_listener_thread_.join()'));
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
    expect(runner, contains('RegisterWindowMessageW(L"TaskbarCreated")'));
    expect(runner, contains('message == taskbar_created_message_'));
    expect(runner, contains('tray_icon_added_ = false'));
    expect(runner, contains('AddTrayIcon();'));
    expect(runner, contains('ExecutableDirectory()'));
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
    expect(design, contains('must include at least one real modifier'));
    expect(design, contains('single-key global shortcuts are ignored'));
    expect(design, contains('undo any partial hotkey registration'));
    expect(design, contains("PaperTodo's reveal model"));
    expect(design, contains('do not create new papers'));
    expect(design, contains('dedicated platform path'));
    expect(appState, contains('_normalizeHotKeyForSettings'));
    expect(platform, contains('revealPinnedPaper'));
    expect(windowsPlatform, contains("'revealPinnedPaper'"));
    expect(controller, contains('_platform.paperWindows.revealPinnedPaper'));
    expect(
      appState,
      contains('unit <= 0x1F || (unit >= 0x7F && unit <= 0x9F)'),
    );
    expect(runner, contains('bool has_modifier = false'));
    expect(runner, contains('has_modifier = true'));
    expect(runner, contains('return has_modifier && *key != 0'));
    expect(runner, contains('hotkey_registration_failed'));
    expect(
        runner, contains('todo_hotkey_requested && !todo_hotkey_registered_'));
    expect(runner, contains('reveal-pinned-todo'));
    expect(runner, contains('reveal-pinned-note'));
    expect(runner, contains('method == "revealPinnedPaper"'));
    expect(runner, contains('HWND_TOP'));
    expect(runner, contains('z_order_state_initialized_ = true'));
  });

  test('Windows fullscreen avoidance uses PaperTodo defensive detection', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final cmake = _readProjectText('windows/runner/CMakeLists.txt');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(design, contains('prefer DWM extended frame bounds'));
    expect(design, contains('ignore'));
    expect(design, contains('tool, cloaked, shell, hidden, minimized'));
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
    expect(controller, contains('_restorePapersForStartupSession'));
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
    final settingsDialog =
        _readProjectText('lib/src/ui/sync_settings_dialog.dart');
    final runtimeFont = _readProjectText('lib/src/ui/runtime_custom_font.dart');

    expect(design, contains('papertodo.ttf'));
    expect(design, contains('papertodo.otf'));
    expect(design, contains('Windows executable directory'));
    expect(design, contains('must not block startup'));
    expect(design, contains('yahei'));
    expect(design, contains('dengxian'));
    expect(app, contains('PaperTodoRuntimeCustomFontLoader'));
    expect(app, contains('resolveAppFontFamily'));
    expect(app, contains('resolveAppFontFamilyFallback'));
    expect(app, contains('Microsoft YaHei UI'));
    expect(app, contains('DengXian'));
    expect(settingsDialog, contains('value: UiFontPresets.yaHei'));
    expect(settingsDialog, contains('value: UiFontPresets.dengXian'));
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

    expect(design, contains('10 minutes before due time'));
    expect(design, contains('2 minutes after due time'));
    expect(design, contains('closest to the current time'));
    expect(design, contains('Deleting a Todo paper should clear active'));
    expect(design, contains('Changing or clearing a todo due date'));
    expect(app, contains('_todoReminderLeadTime = Duration(minutes: 10)'));
    expect(app, contains('_todoReminderGraceTime = Duration(minutes: 2)'));
    expect(app, contains('candidate.dueAt.subtract(_todoReminderLeadTime)'));
    expect(app, contains('candidate.dueAt.add(_todoReminderGraceTime)'));
    expect(app, contains('_distanceFromNow'));
    expect(app, contains('_activeTodoReminderItemIds'));
    expect(app, contains('_clearTodoReminderStateForItems'));
    expect(app, contains('onTodoReminderReset'));
    expect(app, contains('widget.onReminderReset(item)'));
    expect(
      app,
      contains(r"String get key => '${item.id}|${item.dueAtLocal ?? ''}'"),
    );
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
    expect(design, contains('main todo text field records'));
    expect(design, contains('losing focus after a change'));
    expect(design, contains('structural edits first commit'));
    expect(design, contains('left to the text editor'));
    expect(app, contains('_activeOriginalTodoItemId'));
    expect(app, contains('_activeOriginalTodoText'));
    expect(app, contains('_handleMainTodoFieldFocusChange'));
    expect(app, contains('_commitFocusedTodoTextIfNeeded'));
    expect(app, contains('_markTodoTextEditCommitted'));
    expect(app, contains('_shouldDeferToTodoTextUndo'));
    expect(app, contains('_focusedTodoTextHasUncommittedEdit'));
    expect(app, contains('_commitFocusedTodoTextIfNeeded();'));
  });

  test('PaperTodo per-column todo editing is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final item = _readProjectText('lib/src/core/model/paper_item.dart');

    expect(design, contains('Todo column editing should preserve PaperTodo'));
    expect(design, contains('before column 1 moves'));
    expect(design, contains('deleting column 1 promotes'));
    expect(app, contains('_columnActionInsertBeforePrefix'));
    expect(app, contains('_columnActionDeletePrefix'));
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
    expect(app, contains('unawaited(widget.onChanged())'));
  });

  test('PaperTodo todo due date time precision is preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final dueDateHelper =
        _readProjectText('lib/src/core/model/todo_due_date.dart');

    expect(design, contains('Todo due editing should preserve PaperTodo'));
    expect(design, contains('PaperTodo-compatible due dates'));
    expect(design, contains('existing Todo due chip'));
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
    expect(design, contains('today is `HH:mm`'));
    expect(design, contains('Tomorrow HH:mm'));
    expect(design, contains('round the absolute distance up'));
    expect(design, contains('`2h5m`'));
    expect(design, contains('{duration} overdue'));
    expect(design, contains('visible countdown text does not go stale'));
    expect(app, contains('_TodoDueSelectionDialog'));
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
    expect(dueDateHelper, contains(r"replaceAll('\u5e74', '-')"));
  });

  test('PaperTodo todo reorder data semantics are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('Todo ordering should preserve PaperTodo'));
    expect(design, contains('push a todo undo snapshot'));
    expect(design, contains('orders after every move'));
    expect(design, contains('visible drag handle'));
    expect(app, contains('_moveTodoItem'));
    expect(app, contains('_reorderTodoItem'));
    expect(app, contains('ReorderableListView.builder'));
    expect(app, contains('ReorderableDragStartListener'));
    expect(app, contains('onReorderItem: _reorderTodoItem'));
    expect(app, isNot(contains('onReorder: _reorderTodoItem')));
    expect(app, contains('_compactTodoActionMoveUp'));
    expect(app, contains('_compactTodoActionMoveDown'));
    expect(app, contains('PaperTodoStringKeys.actionMoveItemUp'));
    expect(app, contains('PaperTodoStringKeys.actionMoveItemDown'));
    expect(app, contains('PaperTodoStringKeys.actionDragToReorder'));
    expect(app, contains('_requestTodoItemFocus(item.id)'));
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

  test('Todo compact item actions use paper width', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('Todo compact item actions should switch'));
    expect(design, contains('current paper/editor width'));
    expect(app, contains('final availableWidth = constraints.hasBoundedWidth'));
    expect(app, contains('final useCompactItemActions = availableWidth < 600'));
    expect(app, contains('PaperTodoStringKeys.actionTodoItemActions'));
  });

  test('PaperTodo todo note link semantics are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('Todo-note linking should preserve'));
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
    expect(app, contains('_notePaperById'));
    expect(app, contains('item.linkedNoteId == noteId'));
    expect(app, contains('_requestTodoItemFocus(focusTargetId)'));
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

    expect(design, contains('Markdown note link interaction should preserve'));
    expect(design, contains('preview-mode links open directly'));
    expect(design, contains('edit-mode source links open'));
    expect(design, contains('Ctrl+click'));
    expect(design, contains('single-line inline HTML `a href` links'));
    expect(design, contains('Inline HTML anchor parsing should follow'));
    expect(design, contains('well-formed `name=value` pairs'));
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
    expect(design, contains('device paths'));
    expect(design, contains('closed inline code spans'));
    expect(design, contains('Markdown image syntax should follow'));
    expect(design, contains('treated as a source'));
    expect(design, contains('link hit target'));
    expect(design, contains('PaperTodo-scoped extension set'));
    expect(design, contains('no GitHub'));
    expect(design, contains('table or task-checkbox expansion'));
    expect(design, contains('Markdown source link scanning'));
    expect(design, contains('first literal `](`'));
    expect(design, contains('backslash'));
    expect(design, contains('CommonMark angle destinations'));
    expect(design, contains('only `http`, `https`, `mailto`, `www.`'));
    expect(design, contains('Markdown line classification'));
    expect(design, contains('PaperTodo-compatible model'));
    expect(design, contains('fenced code block detection'));
    expect(design, contains("PaperTodo's English fallback label"));
    expect(design, contains('`Link`'));
    expect(design, contains('focus-driven reading flow'));
    expect(design, contains('open in preview mode by default'));
    expect(design, contains('clicking the preview body enters'));
    expect(design, contains('losing editor focus returns'));
    expect(design, contains('Markdown editors should accept Tab'));
    expect(design, contains('Shift+Tab outdents'));
    expect(design, contains('Ctrl+mouse-wheel'));
    expect(design, contains('0.1 steps between 0.5 and 1.5'));
    expect(app, contains('_handleEditorTap'));
    expect(app, contains('_enterEditorFromPreview'));
    expect(app, contains('_handleEditorFocusChange'));
    expect(app, contains('HardwareKeyboard.instance.isControlPressed'));
    expect(app, contains('LogicalKeyboardKey.tab'));
    expect(app, contains('MarkdownFormatting.handleTab'));
    expect(app, contains('PointerScrollEvent'));
    expect(app, contains('pointerSignalResolver'));
    expect(app, contains('_textZoomAfterWheel'));
    expect(app, contains('paperTodoMarkdownInlineHtmlSyntaxes'));
    expect(app, contains('_paperTodoMarkdownExtensionSet'));
    expect(app, contains('md.ExtensionSet.commonMark'));
    expect(app, contains('md.StrikethroughSyntax'));
    expect(app, contains('_paperTodoMarkdownImageBuilder'));
    expect(app, contains('_paperTodoMarkdownBuilders'));
    expect(app, contains('class _UnderlineMarkdownElementBuilder'));
    expect(app, contains("_previewMarkdownStyleSheet"));
    expect(externalUriTargets, contains("startsWith('www.')"));
    expect(app, contains('_normalizeMarkdownLocalPath'));
    expect(app, contains('controller.openExternalFile(localPath)'));
    expect(app, contains('normalizeMarkdownLocalPathTarget'));
    expect(app, contains('MarkdownLinks.hrefAt'));
    expect(markdownLinkTargets, contains('normalizeMarkdownLocalPathTarget'));
    expect(markdownLinkTargets, contains('p.Style.windows'));
    expect(markdownLinkTargets, contains('p.Style.posix'));
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
    expect(
      listContinuation,
      contains('_maxContinuableOrderedListNumber = 9223372036854775806'),
    );
    expect(listContinuation, contains('markerEnd'));
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

  test('PaperTodo note canvas placement and layer rules are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');

    expect(design, contains('New note canvas blocks should follow'));
    expect(design, contains('230x116'));
    expect(design, contains('28px origin'));
    expect(design, contains('12px cascade'));
    expect(design, contains('top z-index plus 10'));
    expect(design, contains('duplicates offset by 18px'));
    expect(design, contains('one-step layer moves swap z-indexes'));
    expect(design, contains('Note canvas text and code block editors'));
    expect(design, contains('Shift+Tab outdents without moving focus'));
    expect(app, contains('_nextNoteCanvasElementPoint'));
    expect(app, contains('math.min(80.0, existingCount * 12.0)'));
    expect(app, contains('math.max(220.0, widget.paper.width - 40)'));
    expect(app, contains('_maxCanvasElementLayer(elements)'));
    expect(app, contains('_minCanvasElementLayer(elements)'));
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
    expect(runner, contains('IsAllowedExternalUri'));
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
    expect(runner, contains('MF_STRING | MF_DISABLED, 0, L"RePaperTodo"'));
    expect(runner, contains('TrayMenuLabelsFromMap'));
    expect(runner, contains('tray_labels_.new_todo.c_str()'));
    expect(runner, contains('tray_labels_.new_note.c_str()'));
    expect(runner, contains('tray_labels_.show_all.c_str()'));
    expect(runner, contains('tray_labels_.hide_all.c_str()'));
    expect(runner, contains('tray_labels_.toggle_all.c_str()'));
    expect(runner, contains('tray_labels_.inline_confirm_delete'));
    expect(runner, contains('tray_labels_.inline_confirm_action.c_str()'));
    expect(runner, contains('tray_labels_.cancel.c_str()'));
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

  test('Windows tray settings command shows the app window', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final settingsCaseStart = runner.indexOf('case kTraySettingsCommand:');
    final settingsCaseEnd = runner.indexOf('break;', settingsCaseStart);

    expect(settingsCaseStart, isNonNegative);
    expect(settingsCaseEnd, greaterThan(settingsCaseStart));
    final settingsCase = runner.substring(settingsCaseStart, settingsCaseEnd);
    expect(settingsCase, contains('SendStartupCommandRequested("settings");'));
    expect(settingsCase, contains('ShowWindow(window, SW_SHOWNORMAL);'));
    expect(settingsCase, contains('SetForegroundWindow(window);'));
  });

  test('Windows tray paper command lets Dart toggle the selected paper', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final app = _readProjectText('lib/src/app.dart');
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
  });

  test('Windows tray paper delete command confirms in the menu', () {
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final platform =
        _readProjectText('lib/src/platform/windows_platform_services.dart');

    expect(runner, contains('kTrayPaperDeleteCommandBase'));
    expect(runner, contains('tray_labels_.delete_paper.c_str()'));
    expect(runner, contains('HMENU confirm_menu = CreatePopupMenu();'));
    expect(runner, contains('tray_labels_.inline_confirm_action.c_str()'));
    expect(runner, contains('tray_labels_.cancel.c_str()'));
    expect(runner, isNot(contains('MessageBoxW')));
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
    final trayMenuStart = runner.indexOf('if (method == "setTrayMenu")');
    final trayMenuEnd =
        runner.indexOf('if (method == "acquireSingleInstance")');

    expect(design, contains('explicitly name an unknown `paperId`'));
    expect(design, contains('Registry refreshes from restore or tray rebuild'));
    expect(platform, contains('WindowsTrayHost(channel, paperWindowHost)'));
    expect(platform, contains('void _syncKnownPapers(AppState state)'));
    expect(platform, contains('_knownPapers.clear();'));
    expect(platform, contains('_paperWindows._syncKnownPapers(state);'));
    expect(lookupStart, isNonNegative);
    expect(lookupEnd, greaterThan(lookupStart));
    final lookupBlock = platform.substring(lookupStart, lookupEnd);
    expect(lookupBlock, contains('return _activePaper;'));
    expect(lookupBlock, contains('return _knownPapers[paperId];'));
    expect(lookupBlock, isNot(contains('?? _activePaper')));
    expect(trayMenuStart, isNonNegative);
    expect(trayMenuEnd, greaterThan(trayMenuStart));
    final trayMenuBlock = runner.substring(trayMenuStart, trayMenuEnd);
    expect(trayMenuBlock, contains('current_paper_ids'));
    expect(trayMenuBlock, contains('paper_surfaces_.erase(iterator)'));
    expect(trayMenuBlock, contains('active_paper_id_.clear()'));
  });

  test('Windows runner hides only the active native paper surface', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');
    final hideStart = runner.indexOf('if (method == "hide")');
    final hideEnd = runner.indexOf('if (method == "setAlwaysOnTop")');

    expect(design, contains('specific non-active paper'));
    expect(hideStart, isNonNegative);
    expect(hideEnd, greaterThan(hideStart));
    final hideBlock = runner.substring(hideStart, hideEnd);
    expect(hideBlock, contains('GetPaperIdArgument'));
    expect(
      hideBlock,
      contains('RememberPaperVisibility(requested_paper_id, false)'),
    );
    expect(hideBlock, contains('requested_paper_id == active_paper_id_'));
    expect(hideBlock, isNot(contains('RememberActivePaperId')));
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
    expect(runner, contains('IsWindowVisible(window) != 0'));
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
    final titleEnd = runner.indexOf('if (method == "setTrayMenu")');
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
    expect(runner, contains('is_script_capsule'));
    expect(runner, contains('labels.script_paper + L" - "'));
    expect(runner, contains('GetBoolArgument(map, "isScriptCapsule"'));
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
  });

  test('PaperTodo paper title editing rules are preserved', () {
    final design = _readProjectText('docs/DESIGN_SYSTEM.md');
    final app = _readProjectText('lib/src/app.dart');
    final paperData = _readProjectText('lib/src/core/model/paper_data.dart');
    final windows =
        _readProjectText('lib/src/platform/windows_platform_services.dart');
    final runner = _readProjectText('windows/runner/flutter_window.cpp');

    expect(design, contains('Paper title editing should preserve PaperTodo'));
    expect(design, contains('40 text elements'));
    expect(design, contains('control characters are removed'));
    expect(design, contains('structured window title updates'));
    expect(app, contains('_PaperTitleTextInputFormatter'));
    expect(app, contains('PaperTitles.cleanCustomTitle(value)'));
    expect(app, contains('controller.paperTitleText(paper)'));
    expect(paperData, contains('PaperTitles.maxTitleLength'));
    expect(windows, contains('PaperTitles.effectiveTitle'));
    expect(windows, contains("'title': _windowTitle(paper)"));
    final titleStart = runner.indexOf('if (method == "setTitle")');
    final titleEnd = runner.indexOf('if (method == "setTrayMenu")');
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
    final workflow = _readProjectText('.github/workflows/release.yml');
    final readme = _readProjectText('README.md');

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
    expect(script, contains('function Invoke-Native'));
    expect(script, contains('function Assert-CleanGitTree'));
    expect(script, contains('function Assert-GitDiffCheck'));
    expect(script, contains('function Assert-PathExists'));
    expect(script, contains('function Get-AndroidKeyProperty'));
    expect(script, contains('function Resolve-AndroidKeystorePath'));
    expect(script, contains('function Get-GradleIntegerAssignment'));
    expect(script, contains('function Get-AndroidSdkConfig'));
    expect(script, contains('function Assert-AndroidSdkCompatibility'));
    expect(script, contains('function Assert-PublishableReleaseOptions'));
    expect(
      script,
      contains(
        'GitHub Release publishing requires Android release signing from android/key.properties',
      ),
    );
    expect(script, contains(r'-AndroidSigningMode $androidSigningMode'));
    expect(script, contains('function Assert-GitHubAuthentication'));
    expect(script, contains('function Assert-GitHubReleaseGitState'));
    expect(script, contains('function Assert-GitHubReleaseTagState'));
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
    expect(script, contains(r'failed with exit code $LASTEXITCODE'));
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
    expect(script, contains('compileSdk = Get-GradleIntegerAssignment'));
    expect(script, contains('compatibility = "Android 14-17 / API 34-37"'));
    expect(script, contains('Compress-Archive'));
    expect(script, contains('Get-FileHash -Algorithm SHA256'));
    expect(script, contains(r'Set-Content -LiteralPath $checksumsFile'));
    expect(script, contains(r'repapertodo-windows-x64-$artifactVersion.zip'));
    expect(script, contains(r'repapertodo-android-$artifactVersion.apk'));
    expect(script, contains(r'repapertodo-$artifactVersion-sha256.txt'));
    expect(script, contains(r'repapertodo-$artifactVersion-release.json'));
    expect(script, contains('Windows release build output was not found'));
    expect(script, contains('Android release APK was not found'));
    expect(script, contains('ConvertTo-Json -Depth 5'));
    expect(script, contains('git rev-parse HEAD'));
    expect(script, contains('builtAtUtc'));
    expect(script, contains(r'compileSdk = $androidSdkConfig["compileSdk"]'));
    expect(script, contains(r'targetSdk = $androidSdkConfig["targetSdk"]'));
    expect(script, contains(r'$validationExecuted'));
    expect(script, contains(r'$validationSkipped'));
    expect(script, contains('skippedValidation'));
    expect(script, contains('function New-ReleaseNotes'));
    expect(script, contains('gh release create'));
    expect(script, contains('gh release edit'));
    expect(script, contains('gh release upload'));
    expect(script, contains('gh auth status'));
    expect(script, contains('authenticated GitHub CLI session'));
    expect(script, contains('gh auth refresh -h github.com'));
    expect(script, contains('gh auth login -h github.com'));
    expect(script, contains(r'--target $gitCommit'));
    expect(script, contains(r'$releaseViewExitCode'));
    expect(script, contains(r'--notes $releaseNotes'));
    expect(script, contains(r'$checksumsFile $metadataFile --clobber'));
    expect(script, contains('SHA-256 checksums for release artifacts.'));
    expect(script, contains('Release metadata JSON with version'));
    expect(readme, contains('skipped validation commands'));
    expect(readme, contains('record those skipped validation'));
    expect(
      script,
      contains('Android release APK targeting Android 14-17 / API 34-37.'),
    );
    expect(workflow, contains('name: Build and Release'));
    expect(workflow, contains('workflow_dispatch'));
    expect(workflow, contains('publishRelease'));
    expect(workflow, contains('windows-latest'));
    expect(workflow, contains('permissions:'));
    expect(workflow, contains('contents: write'));
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
    expect(workflow, contains('repapertodo-release.jks'));
    expect(workflow, contains('android\\key.properties'));
    expect(
      workflow,
      contains('Android release signing secrets are not configured'),
    );
    expect(
      workflow,
      contains('Android release signing secrets are incomplete'),
    );
    expect(workflow, contains(r'Remove-Item -LiteralPath "Env:\$name"'));
    expect(workflow, isNot(contains('HTTP_PROXY: ""')));
    expect(workflow, isNot(contains('HTTPS_PROXY: ""')));
    expect(workflow, isNot(contains('ALL_PROXY: ""')));
    expect(workflow, contains(r'.\scripts\release.ps1 @releaseArgs'));
    expect(workflow, contains('-PublishGitHubRelease'));
    expect(workflow, contains('actions/upload-artifact@v4'));
    expect(workflow, contains('path: dist/*'));
    expect(readme, contains('wired into GitHub Actions'));
    expect(readme, contains('Pushes and pull requests'));
    expect(readme, contains('workflow_dispatch'));
    expect(readme, contains('publishRelease'));
    expect(readme, contains(r'.\scripts\release.ps1'));
    expect(readme, contains('-PublishGitHubRelease'));
    expect(readme, contains('Publishing checks `gh auth status`'));
    expect(readme, contains('missing or expired GitHub credentials'));
    expect(readme, contains('`gh auth refresh -h github.com`'));
    expect(readme, contains('`gh auth login -h github.com`'));
    expect(readme, contains('fetches `origin/main`'));
    expect(readme, contains('local `main` HEAD'));
    expect(readme, contains('validated commit SHA'));
    expect(readme, contains('target tag already exists'));
    expect(readme, contains('reused version cannot'));
    expect(readme, contains('-AllowDirty'));
    expect(readme, contains('dirty git working tree'));
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
    expect(readme, contains('Validation includes `git diff --check`'));
    expect(readme, contains('SHA-256 checksum file'));
    expect(readme, contains('release metadata JSON file'));
    expect(readme, contains('refuses to'));
    expect(readme, contains('storeFile` points to an existing keystore file'));
    expect(readme, contains('ANDROID_KEYSTORE_BASE64'));
    expect(readme, contains('ANDROID_STORE_PASSWORD'));
    expect(readme, contains('ANDROID_KEY_ALIAS'));
    expect(readme, contains('ANDROID_KEY_PASSWORD'));
    expect(readme, contains('Android 14-17/API 34-37 compatibility'));
    expect(readme, contains('reads the Android Gradle SDK settings'));
    expect(readme, contains('stops if they drift'));
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
}
