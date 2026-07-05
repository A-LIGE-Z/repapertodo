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
    final gitignore = File('.gitignore').readAsStringSync();
    final readme = File('README.md').readAsStringSync();
    final mainActivity = File(
            'android/app/src/main/kotlin/com/aligez/repapertodo/MainActivity.kt')
        .readAsStringSync();

    expect(gradle, contains('compileSdk = 37'));
    expect(gradle, contains('minSdk = 34'));
    expect(gradle, contains('targetSdk = 37'));
    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, contains('hasReleaseSigningConfig'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, contains('signingConfigs.getByName("debug")'));
    expect(gradle, contains('enableV2Signing = true'));
    expect(gradle, contains('enableV3Signing = true'));
    expect(gitignore, contains('android/key.properties'));
    expect(gitignore, contains('*.jks'));
    expect(readme, contains('Android release signing'));
    expect(readme, contains('debug fallback'));
    expect(readme, contains('android/key.properties'));
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
    expect(mainActivity, contains('val parsedUri = try'));
    expect(mainActivity, contains('The URI is not valid.'));
    expect(mainActivity, contains('val trimmedPath = path.trim()'));
    expect(mainActivity, contains('!file.isFile'));
    expect(mainActivity, contains('parsedUri.scheme'));
    expect(mainActivity, contains('uri.userInfo.isNullOrBlank()'));
    expect(mainActivity, contains('uri.encodedAuthority'));
    expect(mainActivity, contains('hasEncodedExternalUriAuthoritySeparator'));
    expect(mainActivity, contains('hasUnsafeExternalUriCharacter'));
    expect(mainActivity, contains('hasEncodedUnsafeExternalUriCharacter'));
    expect(mainActivity, contains('hasUnsafeExternalFilePathCharacter'));
    expect(mainActivity, contains('isAllowedExternalUri'));
    expect(mainActivity, contains('"mailto"'));
    expect(mainActivity, contains('Intent.CATEGORY_BROWSABLE'));
    expect(mainActivity, contains('file_provider_failed'));
    expect(mainActivity, contains('SecurityException'));
  });

  test('platform launch hosts reject blank native channel arguments', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();
    final android = File('lib/src/platform/android_platform_services.dart')
        .readAsStringSync();
    final windows = File('lib/src/platform/windows_platform_services.dart')
        .readAsStringSync();

    expect(design, contains('reject blank launch\narguments'));
    expect(design, contains('percent-encoded control characters'));
    expect(design, contains('encoded authority separators'));
    expect(design, contains('external-file paths must reject raw control'));
    expect(design, contains('Generated external Markdown export filenames'));
    expect(design, contains('External Markdown extension settings'));
    expect(design, contains('including DEL'));
    expect(app, contains(r'[<>:"/\\|?*\x00-\x1F\x7F]'));
    expect(app, contains('_hasEncodedUnsafeExternalUriCharacter'));
    expect(app, contains('_hasEncodedExternalUriAuthoritySeparator'));
    expect(android, contains('Android URI must not be blank.'));
    expect(
        android, contains('Android URI must not contain control characters.'));
    expect(android,
        contains('Android URI must not contain encoded control characters.'));
    expect(android,
        contains('Android URI must not contain encoded authority separators.'));
    expect(android, contains('_hasEncodedExternalUriAuthoritySeparator'));
    expect(android, contains('Android external file path must not be blank.'));
    expect(
        android,
        contains(
            'Android external file path must not contain control characters.'));
    expect(windows, contains('Windows URI must not be blank.'));
    expect(
        windows, contains('Windows URI must not contain control characters.'));
    expect(windows,
        contains('Windows URI must not contain encoded control characters.'));
    expect(windows,
        contains('Windows URI must not contain encoded authority separators.'));
    expect(windows, contains('_hasEncodedExternalUriAuthoritySeparator'));
    expect(windows, contains('Windows external file path must not be blank.'));
    expect(
        windows,
        contains(
            'Windows external file path must not contain control characters.'));
    final appState =
        File('lib/src/core/model/app_state.dart').readAsStringSync();
    final settingsDialog =
        File('lib/src/ui/sync_settings_dialog.dart').readAsStringSync();
    expect(appState, contains('rune < 0x20 || rune == 0x7F'));
    expect(settingsDialog, contains('rune < 0x20 || rune == 0x7F'));
  });

  test('sync design preserves merge safety rules', () {
    final syncDesign = File('docs/SYNC.md').readAsStringSync();

    expect(syncDesign, contains('earliest `createdAtUtc` first'));
    expect(syncDesign, contains('Tombstone timestamps only move forward'));
    expect(
        syncDesign, contains('Settings operations are intentionally limited'));
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
        File('lib/src/core/model/sync_settings.dart').readAsStringSync();
    final webDavClient =
        File('lib/src/sync/webdav/webdav_client.dart').readAsStringSync();
    expect(syncSettings, contains('_hasUnsafeEndpointAuthority'));
    expect(syncSettings, contains('value.trim().isNotEmpty'));
    expect(syncSettings, contains("'%40'"));
    expect(webDavClient, contains('_hasUnsafeBaseUriAuthority'));
    expect(webDavClient, contains('_hrefRawPathHasDotSegments'));
    expect(webDavClient, contains('_rawHrefPath'));
    expect(webDavClient, contains('value.trim().isNotEmpty'));
    expect(webDavClient, contains("'%40'"));
    expect(webDavClient, contains('segment != trimmed'));
    expect(
      webDavClient,
      contains(
        'WebDAV path segments must not contain leading or trailing whitespace.',
      ),
    );
    final syncDeviceId =
        File('lib/src/core/model/sync_device_id.dart').readAsStringSync();
    final webDavStateSync =
        File('lib/src/sync/webdav/webdav_state_sync_service.dart')
            .readAsStringSync();
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
        File('lib/src/core/model/sync_wire_datetime.dart').readAsStringSync();
    final syncManifest =
        File('lib/src/sync/sync_manifest.dart').readAsStringSync();
    final syncOperation =
        File('lib/src/sync/sync_operation.dart').readAsStringSync();
    final syncOperationApplier =
        File('lib/src/sync/sync_operation_applier.dart').readAsStringSync();
    final appSyncService =
        File('lib/src/sync/app_sync_service.dart').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();
    final webDavPayloadCodec =
        File('lib/src/sync/webdav/webdav_payload_codec.dart')
            .readAsStringSync();
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
    final runner = File('windows/runner/main.cpp').readAsStringSync();
    final dartParser =
        File('lib/src/core/startup/startup_command.dart').readAsStringSync();

    expect(runner, contains('find_first_of("=:", segment_start)'));
    expect(runner, contains('CreatedPaperStartupCommand'));
    expect(dartParser, contains("RegExp(r'[=:]+')"));
    expect(dartParser, contains('_createdPaperKind'));
  });

  test('Windows runner forwards secondary instance startup commands', () {
    final entrypoint = File('windows/runner/main.cpp').readAsStringSync();
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(entrypoint, contains('kSingleInstanceMutexName'));
    expect(entrypoint, contains('kSingleInstancePipeName'));
    expect(entrypoint, contains('CreateMutexW'));
    expect(entrypoint, contains('ERROR_ALREADY_EXISTS'));
    expect(entrypoint, contains('StartupCommandFromArgs'));
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

  test('hotkey settings keep forgiving aliases without control characters', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final appState =
        File('lib/src/core/model/app_state.dart').readAsStringSync();
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(design, contains('Hotkey settings should strip control characters'));
    expect(design, contains('preserving ordinary spaces used by aliases'));
    expect(design, contains('must include at least one real modifier'));
    expect(design, contains('single-key global shortcuts are ignored'));
    expect(appState, contains('_normalizeHotKeyForSettings'));
    expect(appState, contains('unit <= 0x1F || unit == 0x7F'));
    expect(runner, contains('bool has_modifier = false'));
    expect(runner, contains('has_modifier = true'));
    expect(runner, contains('return has_modifier && *key != 0'));
  });

  test('Windows fullscreen avoidance uses PaperTodo defensive detection', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

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
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final controller = File('lib/src/app_controller.dart').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();
    final constants =
        File('lib/src/core/model/paper_constants.dart').readAsStringSync();
    final platform =
        File('lib/src/platform/platform_services.dart').readAsStringSync();
    final windowsPlatform =
        File('lib/src/platform/windows_platform_services.dart')
            .readAsStringSync();
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(design, contains('open away from the deep capsule edge strip'));
    expect(design, contains('created from an existing paper'));
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
    expect(controller, contains('_initializeNewPaperCapsuleQueue'));
    expect(controller, contains('!_canPaperDisplayAsCapsule(paper)'));
    expect(controller, contains('_rescuePapersIntoWorkAreas'));
    expect(controller, contains('_rescuePaperIntoWorkArea'));
    expect(controller, contains('_clampNewPaperAwayFromDeepCapsuleStrip'));
    expect(controller, contains('_newPaperInitialPosition'));
    expect(controller, contains('workAreaForPaper'));
    expect(app, contains("'Paper surfaces'"));
    expect(windowsPlatform, contains("'getWorkArea'"));
    expect(runner, contains('getWorkArea'));
    expect(runner, contains('EnumDisplayMonitors'));
    expect(runner, contains('MONITORINFOEXW'));
  });

  test('PaperTodo paper hide and last-delete rules are preserved', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final controller = File('lib/src/app_controller.dart').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(design,
        contains("Hiding a paper should follow PaperTodo's single-paper"));
    expect(design, contains('Deleting the last remaining paper'));
    expect(controller, contains('..isPinnedToDesktop = false'));
    expect(controller, contains('..isVisible = false'));
    expect(controller, contains('..isCollapsed = false'));
    expect(app,
        contains('defaultPaper = controller.tryCreatePaper(PaperTypes.todo)'));
    expect(app, contains('await controller.showPaper(createdDefaultPaper)'));
    expect(app, contains('_undoDeletePaper'));
  });

  test('PaperTodo runtime custom font convention is preserved', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();
    final settingsDialog =
        File('lib/src/ui/sync_settings_dialog.dart').readAsStringSync();
    final runtimeFont =
        File('lib/src/ui/runtime_custom_font.dart').readAsStringSync();

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
    final model =
        File('lib/src/core/model/paper_constants.dart').readAsStringSync();
    final item = File('lib/src/core/model/paper_item.dart').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(model, contains('static const maxCount = 4'));
    expect(model, contains('static const maxWidth = 10000.0'));
    expect(item, contains('TodoColumnLimits.maxCount'));
    expect(item, contains('TodoColumnLimits.maxWidth'));
    expect(item, isNot(contains('clamp(1, 8)')));
    expect(app, contains('TodoColumnLimits.maxCount'));
    expect(app, isNot(contains('todoColumnCount < 8')));
  });

  test('PaperTodo todo reminder timing is preserved', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

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
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(design, contains('Todo keyboard editing should follow PaperTodo'));
    expect(design, contains('Enter with no modifiers inserts'));
    expect(design, contains('Backspace'));
    expect(design, contains('suppresses repeated'));
    expect(app, contains('_handleTodoItemKeyEvent'));
    expect(app, contains('_insertItemAfter'));
    expect(app, contains('_deleteBlankTodoItemFromKeyboard'));
    expect(app, contains('_allTodoTextColumnsBlank'));
    expect(app, contains('_suppressTodoBackspaceUntilKeyUp'));
  });

  test('PaperTodo per-column todo editing is preserved', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(design, contains('Todo column editing should preserve PaperTodo'));
    expect(design, contains('before column 1 moves'));
    expect(design, contains('deleting column 1 promotes'));
    expect(app, contains('_columnActionInsertBeforePrefix'));
    expect(app, contains('_columnActionDeletePrefix'));
    expect(app, contains('_insertTodoColumnBefore'));
    expect(app, contains('_deleteTodoColumn'));
    expect(app, contains('item.todoExtraColumns.insert(0, item.text)'));
    expect(app, contains('item.text = item.todoExtraColumns.first'));
  });

  test('PaperTodo todo due date time precision is preserved', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(design, contains('Todo due editing should preserve PaperTodo'));
    expect(design, contains('00-23 hour'));
    expect(design, contains('00-59 minute'));
    expect(design, contains('yyyy-MM-ddTHH:mm:ss'));
    expect(design, contains('today is `HH:mm`'));
    expect(design, contains('Tomorrow HH:mm'));
    expect(design, contains('round the absolute distance up'));
    expect(design, contains('`2h5m`'));
    expect(design, contains('{duration} overdue'));
    expect(app, contains('_TodoDueSelectionDialog'));
    expect(app, contains("ValueKey('todo-due-hour')"));
    expect(app, contains("ValueKey('todo-due-minute')"));
    expect(app, contains('_formatDueAtLocalValue'));
    expect(app, contains("return 'Tomorrow \$time'"));
    expect(app, contains('Duration.microsecondsPerMinute'));
    expect(app, contains("return '\$text overdue'"));
    expect(app, contains("return 'in \$text'"));
    expect(app, contains('now.add(const Duration(hours: 1))'));
  });

  test('PaperTodo todo reorder data semantics are preserved', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

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
    expect(app, contains('Move item up'));
    expect(app, contains('Move item down'));
    expect(app, contains('Drag to reorder'));
    expect(app, contains('_requestTodoItemFocus(item.id)'));
  });

  test('PaperTodo markdown note link interaction is preserved', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();
    final markdownLinks =
        File('lib/src/core/model/markdown_links.dart').readAsStringSync();

    expect(design, contains('Markdown note link interaction should preserve'));
    expect(design, contains('preview-mode links open directly'));
    expect(design, contains('edit-mode source links open'));
    expect(design, contains('Ctrl+click'));
    expect(design, contains('single-line inline HTML `a href` links'));
    expect(design, contains('focus-driven reading flow'));
    expect(design, contains('open in preview mode by default'));
    expect(design, contains('clicking the preview body enters'));
    expect(design, contains('losing editor focus returns'));
    expect(app, contains('_handleEditorTap'));
    expect(app, contains('_enterEditorFromPreview'));
    expect(app, contains('_handleEditorFocusChange'));
    expect(app, contains('HardwareKeyboard.instance.isControlPressed'));
    expect(app, contains('MarkdownLinks.hrefAt'));
    expect(markdownLinks, contains('class MarkdownLinkSpan'));
    expect(markdownLinks, contains('_htmlAnchorLinks'));
  });

  test('PaperTodo note canvas geometry gestures are preserved', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(design, contains('Note canvas element geometry should preserve'));
    expect(design, contains('dragging the element header moves the block'));
    expect(design, contains('bottom-right grip'));
    expect(design, contains('72x48'));
    expect(app, contains('note-canvas-drag-handle-'));
    expect(app, contains('note-canvas-resize-handle-'));
    expect(app, contains('_moveElement'));
    expect(app, contains('_resizeElement'));
    expect(app, contains('clamp(72, maxWidth)'));
    expect(app, contains('clamp(48, maxHeight)'));
  });

  test('Windows runner preserves external URI safety checks', () {
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();

    expect(app, contains('_hasUnsafeExternalUriCharacter'));
    expect(app, contains('_hasEncodedUnsafeExternalUriCharacter'));
    expect(app, contains('uri.userInfo.isNotEmpty'));
    expect(app, contains('_hasEncodedExternalUriAuthoritySeparator'));
    expect(runner, contains('IsAllowedExternalUri'));
    expect(runner, contains('HasEncodedUnsafeExternalUriCharacter'));
    expect(runner, contains('HasEncodedExternalUriAuthoritySeparator'));
    expect(runner, contains('ascii <= 0x20'));
    expect(runner, contains("authority.find('@')"));
    expect(runner, contains('authority_host'));
    expect(runner, contains("authority.front() == '['"));
    expect(runner, contains('scheme == "mailto"'));
    expect(runner, contains('scheme != "http" && scheme != "https"'));
    expect(runner, contains('ShellExecuteW'));
  });

  test('Windows tray settings command shows the app window', () {
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final settingsCaseStart = runner.indexOf('case kTraySettingsCommand:');
    final settingsCaseEnd = runner.indexOf('break;', settingsCaseStart);

    expect(settingsCaseStart, isNonNegative);
    expect(settingsCaseEnd, greaterThan(settingsCaseStart));
    final settingsCase = runner.substring(settingsCaseStart, settingsCaseEnd);
    expect(settingsCase, contains('SendStartupCommandRequested("settings");'));
    expect(settingsCase, contains('ShowWindow(window, SW_SHOWNORMAL);'));
    expect(settingsCase, contains('SetForegroundWindow(window);'));
  });

  test('Windows tray paper command shows the selected paper window', () {
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final paperCommandStart = runner.indexOf(
      'command >= kTrayPaperCommandBase',
    );
    final paperCommandEnd = runner.indexOf('break;', paperCommandStart);

    expect(paperCommandStart, isNonNegative);
    expect(paperCommandEnd, greaterThan(paperCommandStart));
    final paperCommand = runner.substring(paperCommandStart, paperCommandEnd);
    expect(paperCommand, contains('SendPaperRequested('));
    expect(paperCommand, contains('ShowWindow(window, SW_SHOWNORMAL);'));
    expect(paperCommand, contains('SetForegroundWindow(window);'));
  });

  test('Windows tray marks script capsule notes distinctly', () {
    final dartHost = File('lib/src/platform/windows_platform_services.dart')
        .readAsStringSync();
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(dartHost, contains("'isScriptCapsule'"));
    expect(dartHost, contains('ScriptCapsuleSpec.isScriptCapsuleContent'));
    expect(runner, contains('is_script_capsule'));
    expect(runner, contains('L"Script - "'));
    expect(runner, contains('GetBoolArgument(map, "isScriptCapsule"'));
  });

  test('Windows runner validates external files before opening them', () {
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(runner, contains('path = TrimAscii(path)'));
    expect(runner, contains('HasUnsafeExternalFilePathCharacter'));
    expect(runner, contains('FileExists'));
    expect(runner, contains('FILE_ATTRIBUTE_DIRECTORY'));
    expect(runner, contains('file_not_found'));
    expect(runner, contains('ShellExecuteW'));
  });

  test('Windows script capsule hosts validate launch requests', () {
    final design = File('docs/DESIGN_SYSTEM.md').readAsStringSync();
    final app = File('lib/src/app.dart').readAsStringSync();
    final dartHost = File('lib/src/platform/windows_platform_services.dart')
        .readAsStringSync();
    final runner = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(design, contains('Script capsule hosts must reject blank scripts'));
    expect(design, contains('Collapsed note papers whose content starts'));
    expect(design, contains('primary click runs the script'));
    expect(design, contains('secondary click opens the note for editing'));
    expect(app, contains('-script-capsule'));
    expect(app, contains('_collapsedScriptCapsule'));
    expect(app, contains('_openCollapsedScriptCapsuleForEditing'));
    expect(dartHost, contains('Windows script capsule must not be blank.'));
    expect(dartHost, contains('Unsupported Windows script capsule engine.'));
    expect(runner, contains('IsAllowedScriptCapsuleEngine'));
    expect(runner, contains('invalid_script_capsule_engine'));
  });

  test('release script packages Windows and Android artifacts', () {
    final script = File('scripts/release.ps1').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(script, contains(r'$env:HTTPS_PROXY = ""'));
    expect(script, contains('flutter.bat'));
    expect(script, contains(r'[switch]$OfflinePubGet'));
    expect(script, contains('function Invoke-Native'));
    expect(script, contains(r'failed with exit code $LASTEXITCODE'));
    expect(script, contains(r'& $flutter pub get --offline'));
    expect(script, contains(r'& $flutter test --no-pub'));
    expect(script, contains(r'& $flutter analyze --no-pub'));
    expect(script, contains(r'& $flutter build windows --release --no-pub'));
    expect(script, contains(r'& $flutter build apk --release --no-pub'));
    expect(script, contains('Get-AndroidSigningMode'));
    expect(script, contains(r'Android signing mode: $androidSigningMode'));
    expect(script, contains(r'Android signing: $androidSigningMode.'));
    expect(script, contains('Compress-Archive'));
    expect(script, contains('Get-FileHash -Algorithm SHA256'));
    expect(script, contains(r'Set-Content -LiteralPath $checksumsFile'));
    expect(script, contains(r'repapertodo-windows-x64-$artifactVersion.zip'));
    expect(script, contains(r'repapertodo-android-$artifactVersion.apk'));
    expect(script, contains(r'repapertodo-$artifactVersion-sha256.txt'));
    expect(script, contains('gh release create'));
    expect(script, contains('gh release upload'));
    expect(script, contains(r'$releaseViewExitCode'));
    expect(script, contains(r'$checksumsFile --clobber'));
    expect(script, contains('SHA-256 checksums for release artifacts.'));
    expect(script, contains('Android release APK for Android 14+'));
    expect(readme, contains(r'.\scripts\release.ps1'));
    expect(readme, contains('-PublishGitHubRelease'));
    expect(readme, contains('-OfflinePubGet'));
    expect(readme, contains('SHA-256 checksum file'));
  });
}
