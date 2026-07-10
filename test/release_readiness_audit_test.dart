import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

String _sha256File(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();

Map<String, dynamic>? _cachedFlutterToolchain;

String? _findFlutterExecutable() {
  final dartExecutable = File(Platform.resolvedExecutable);
  final dartSdkBin = dartExecutable.parent;
  final dartSdk = dartSdkBin.parent;
  final cache = dartSdk.parent;
  final flutterRoot = cache.parent;
  final bundledFlutter = File(
    p.join(
      flutterRoot.path,
      'bin',
      Platform.isWindows ? 'flutter.bat' : 'flutter',
    ),
  );
  if (bundledFlutter.existsSync()) {
    return bundledFlutter.path;
  }

  final lookupCommand = Platform.isWindows ? 'where' : 'which';
  final result = Process.runSync(
    lookupCommand,
    ['flutter'],
    runInShell: true,
  );
  if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
    for (final line
        in result.stdout.toString().trim().split(RegExp(r'\r?\n'))) {
      final candidate = File(line.trim());
      if (Platform.isWindows) {
        final batchCandidate = candidate.path.toLowerCase().endsWith('.bat')
            ? candidate
            : File('${candidate.path}.bat');
        if (batchCandidate.existsSync()) {
          return batchCandidate.path;
        }
      }
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
  }
  return null;
}

Map<String, dynamic> _currentFlutterToolchain() {
  final cached = _cachedFlutterToolchain;
  if (cached != null) {
    return Map<String, dynamic>.from(cached);
  }
  final flutter = _findFlutterExecutable();
  if (flutter == null) {
    fail(
        'Flutter executable is unavailable for readiness audit test metadata.');
  }
  final result = Process.runSync(flutter, ['--version', '--machine']);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  final raw = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
  final toolchain = {
    'flutterFrameworkVersion': raw['frameworkVersion'] as String,
    'flutterChannel': raw['channel'] as String,
    'flutterFrameworkRevision': raw['frameworkRevision'] as String,
    'flutterEngineRevision': raw['engineRevision'] as String,
    'dartSdkVersion': raw['dartSdkVersion'] as String,
  };
  _cachedFlutterToolchain = toolchain;
  return Map<String, dynamic>.from(toolchain);
}

Future<ProcessResult> _runReadinessAudit({
  required String powerShell,
  required String windowsManualQaJson,
  required String androidDeviceSmokeJson,
  required String windowsReleaseDirectory,
  required String androidApkPath,
  String? webDavLiveSmokeJson,
  String? webDavDomesticLiveSmokeJson,
  String? releaseMetadataJson,
  String? releaseChecksumsFile,
}) {
  final arguments = [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    'scripts/release_readiness_audit.ps1',
    '-WindowsManualQaResultJson',
    windowsManualQaJson,
    '-ExpectedWindowsReleaseDirectory',
    windowsReleaseDirectory,
    '-AndroidDeviceSmokeResultJson',
    androidDeviceSmokeJson,
    '-ExpectedAndroidApkFileName',
    p.basename(androidApkPath),
    '-ExpectedAndroidApkPath',
    androidApkPath,
  ];
  if (webDavLiveSmokeJson != null) {
    arguments.addAll(['-WebDavLiveSmokeResultJson', webDavLiveSmokeJson]);
  }
  if (webDavDomesticLiveSmokeJson != null) {
    arguments.addAll([
      '-WebDavDomesticLiveSmokeResultJson',
      webDavDomesticLiveSmokeJson,
    ]);
  }
  if (releaseMetadataJson != null) {
    arguments.addAll(['-ReleaseMetadataJson', releaseMetadataJson]);
  }
  if (releaseChecksumsFile != null) {
    arguments.addAll(['-ReleaseChecksumsFile', releaseChecksumsFile]);
  }
  return Process.run(
    powerShell,
    arguments,
    workingDirectory: Directory.current.path,
  );
}

Map<String, dynamic> _decodeAudit(ProcessResult result) {
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
}

Map<String, dynamic> _checkById(Map<String, dynamic> audit, String id) {
  final checks = (audit['checks'] as List).cast<Map<String, dynamic>>();
  return checks.singleWhere((check) => check['id'] == id);
}

Map<String, dynamic> _windowsManualQaRecord({
  required File exe,
  required File appSo,
  String? exeSha256Override,
  String? releaseDirectoryOverride,
  String tester = 'readiness-audit-test',
  String windowsVersion = 'Windows readiness audit test',
  bool includeExtraItem = false,
}) {
  Map<String, String> item(String id) => {
        'id': id,
        'title': id,
        'status': 'pass',
      };
  final items = [
    item('transparentBorderlessFeel'),
    item('taskSwitcherVisibility'),
    item('multiMonitorEdgeDocking'),
    item('fullscreenAvoidance'),
    item('trayAfterExplorerRestart'),
    item('longRunningScriptCapsule'),
    item('independentPaperSurfaces'),
    if (includeExtraItem) item('unreviewedExtraWindowsBehavior'),
  ];
  return {
    'status': 'passed',
    'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'reason': '',
    'tester': tester,
    'windowsVersion': windowsVersion,
    'exePath': exe.path,
    'releaseDirectory': releaseDirectoryOverride ?? exe.parent.path,
    'exeFileName': 'repapertodo.exe',
    'exeBytes': exe.lengthSync(),
    'exeSha256': exeSha256Override ?? _sha256File(exe),
    'appSoRelativePath': 'data/app.so',
    'appSoBytes': appSo.lengthSync(),
    'appSoSha256': _sha256File(appSo),
    'allowSkipped': false,
    'notes': 'Synthetic readiness audit test record.',
    'items': items,
  };
}

Map<String, dynamic> _androidDeviceSmokeRecord({
  required File apk,
  String? apkSha256Override,
}) {
  return {
    'status': 'passed',
    'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'adb': r'D:\Android\Sdk\platform-tools\adb.exe',
    'apkAnalyzer': r'D:\Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat',
    'deviceSerial': 'readiness-audit-test',
    'apiLevel': 34,
    'minSupportedApi': 34,
    'maxSupportedApi': 37,
    'packageName': 'com.aligez.repapertodo',
    'apkApplicationId': 'com.aligez.repapertodo',
    'apkPath': apk.path,
    'apkFileName': p.basename(apk.path),
    'apkBytes': apk.lengthSync(),
    'apkSha256': apkSha256Override ?? _sha256File(apk),
    'launchWaitSeconds': 8,
    'processId': '12345',
    'foregroundPackage': 'com.aligez.repapertodo',
  };
}

Map<String, dynamic> _webDavLiveSmokeRecord({
  String providerId = 'custom',
  Map<String, int>? deviceSequences,
  String rootPath = 'repapertodo-live-smoke/run-20260709000000',
}) {
  return {
    'status': 'passed',
    'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'endpointHost': 'dav.example.test',
    'providerId': providerId,
    'rootPath': rootPath,
    'windowsUploadStatus': 'uploaded',
    'androidDownloadStatus': 'downloaded',
    'androidOperationUploadedCount': 1,
    'windowsOperationAppliedCount': 1,
    'deviceSequences': deviceSequences ??
        const {
          'windows-live-smoke': 1,
          'android-live-smoke': 1,
        },
    'remoteCleanup': 'attempted',
  };
}

Map<String, dynamic> _releaseMetadataRecord({
  required File windowsZip,
  required File androidApk,
  File? releaseNotes,
  String version = '0.1.1+2',
  String tagName = 'v0.1.1+2',
  List<String> supportedLanguages = const ['zh', 'en'],
  List<String> expectedResourceLanguages = const ['zh', 'en'],
  String? androidApkSha256Override,
  String? dependencyLockSha256Override,
  Map<String, dynamic>? toolchainOverride,
}) {
  final dependencyLock = File('pubspec.lock');
  final releaseNotesFile = releaseNotes ??
      (File(p.join(
        windowsZip.parent.path,
        'repapertodo-0.1.1-2-release-notes.md',
      ))
        ..writeAsStringSync('Release notes'));
  return {
    'version': version,
    'tagName': tagName,
    'gitCommit': '0' * 40,
    'dirtyWorkingTreeAllowed': true,
    'builtAtUtc': DateTime.now().toUtc().toIso8601String(),
    'windows': {
      'smoke': {
        'status': 'passed',
        'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'releaseDirectory':
            r'D:\AI\repapertodo\build\windows\x64\runner\Release',
        'exeFileName': 'repapertodo.exe',
        'initialPaperCount': 1,
        'finalPaperCount': 3,
        'initialTodoPaperCount': 1,
        'finalTodoPaperCount': 2,
        'initialNotePaperCount': 0,
        'finalNotePaperCount': 1,
        'secondaryStartupCommands': ['--new-note', '--new-todo', '--exit'],
        'startupTimeoutSeconds': 30,
        'exitTimeoutSeconds': 30,
      },
      'manualQa': {
        'status': 'skipped',
        'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'reason': 'optional',
      },
    },
    'webDav': {
      'staticSmoke': {
        'status': 'passed',
        'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'genericWebDavSupported': true,
        'jianguoyunPresetSupported': true,
        'encryptedPayloadsRequired': true,
        'operationLogsSupported': true,
        'crossDeviceOperationRoundTripCovered': true,
        'localHttpWebDavRoundTripCovered': true,
        'sharedWindowsAndroidSettings': true,
        'androidBackgroundSyncSharedDartPath': true,
        'androidBackgroundSyncRegistrationCovered': true,
        'androidBackgroundSyncAbsoluteStatePathCovered': true,
        'androidBackgroundSyncDataJsonStatePathCovered': true,
        'evidenceFiles': [
          'lib/src/sync/webdav/webdav_client.dart',
          'lib/src/sync/android_background_sync.dart',
        ],
      },
      'liveSmoke': {
        'status': 'skipped',
        'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'reason': 'optional',
      },
      'domesticLiveSmoke': {
        'status': 'skipped',
        'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'reason': 'optional',
      },
    },
    'android': {
      'compileSdk': 37,
      'minSdk': 34,
      'targetSdk': 37,
      'compatibility': 'Android 14-17 / API 34-37',
      'signing': 'debug fallback (android/key.properties not found)',
      'tools': {
        'apkAnalyzer':
            r'D:\Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat',
        'aapt2': r'D:\Android\Sdk\build-tools\37.0.0\aapt2.exe',
      },
      'staticSmoke': {
        'status': 'passed',
        'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'applicationId': 'com.aligez.repapertodo',
        'apkApplicationId': 'com.aligez.repapertodo',
        'minSdk': 34,
        'targetSdk': 37,
        'compileSdk': 37,
        'expectedResourceLanguages': expectedResourceLanguages,
        'localeConfigLanguages': expectedResourceLanguages,
        'localizedResourceConfigurations': <String>[],
        'forbiddenLocalizedResourceConfigurationsAbsent': true,
        'androidLocaleConfigPresent': true,
      },
      'deviceSmoke': {
        'status': 'skipped',
        'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'reason': 'optional',
      },
    },
    'runtime': {
      'supportedLanguages': supportedLanguages,
    },
    'packageResolution': 'skipped',
    'toolchain': toolchainOverride ?? _currentFlutterToolchain(),
    'dependencyLock': {
      'fileName': 'pubspec.lock',
      'bytes': dependencyLock.lengthSync(),
      'sha256': dependencyLockSha256Override ?? _sha256File(dependencyLock),
    },
    'releaseNotes': {
      'fileName': p.basename(releaseNotesFile.path),
      'bytes': releaseNotesFile.lengthSync(),
      'sha256': _sha256File(releaseNotesFile),
    },
    'validation': ['scripts/windows_smoke.ps1'],
    'skippedValidation': ['flutter test --no-pub'],
    'artifacts': [
      {
        'fileName': p.basename(windowsZip.path),
        'bytes': windowsZip.lengthSync(),
        'sha256': _sha256File(windowsZip),
      },
      {
        'fileName': p.basename(androidApk.path),
        'bytes': androidApk.lengthSync(),
        'sha256': androidApkSha256Override ?? _sha256File(androidApk),
      },
    ],
  };
}

void _writeJson(File file, Object value) {
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(value));
}

void _writeReleaseChecksums({
  required File file,
  required File windowsZip,
  required File androidApk,
  required File releaseMetadata,
  required File releaseNotes,
  String? androidApkSha256Override,
}) {
  final lines = [
    '${_sha256File(windowsZip)}  ${p.basename(windowsZip.path)}',
    '${androidApkSha256Override ?? _sha256File(androidApk)}  ${p.basename(androidApk.path)}',
    '${_sha256File(releaseMetadata)}  ${p.basename(releaseMetadata.path)}',
    '${_sha256File(releaseNotes)}  ${p.basename(releaseNotes.path)}',
  ];
  file.writeAsStringSync(lines.join('\n'));
}

void main() {
  test('readiness audit rejects unsafe result JSON paths before writing',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_result_path_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final resultJson = File(p.join(temp.path, 'release-readiness-audit.json'));
    final unsafeResultPath = p.join(temp.path, 'release-readiness-audit.txt');

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'scripts/release_readiness_audit.ps1',
        '-ResultJson',
        unsafeResultPath,
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, isNot(0));
    expect(resultJson.existsSync(), false);
    expect(File(unsafeResultPath).existsSync(), false);
    expect(
      result.stderr.toString(),
      contains(
        'Release readiness audit result JSON path must use the .json extension.',
      ),
    );
  });

  test('readiness audit rejects unsafe input JSON evidence paths', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_input_path_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final unsafeInputPath = p.join(temp.path, 'windows-manual-qa.txt');

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'scripts/release_readiness_audit.ps1',
        '-WindowsManualQaResultJson',
        unsafeInputPath,
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout.toString(),
      contains('Windows manual QA JSON path must use the .json extension.'),
    );
    expect(
      result.stdout.toString(),
      isNot(contains('Windows manual QA JSON was not found')),
    );
  });

  test('readiness audit writes result JSON before failing blocked CI gate',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_fail_on_blocked_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final resultJson = File(p.join(temp.path, 'release-readiness-audit.json'));

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'scripts/release_readiness_audit.ps1',
        '-ResultJson',
        resultJson.path,
        '-FailOnBlocked',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, isNot(0));
    expect(resultJson.existsSync(), true);
    final audit =
        jsonDecode(resultJson.readAsStringSync()) as Map<String, dynamic>;
    expect(audit['status'], 'blocked');
    expect(audit['readyForGitHubRelease'], false);
    expect((audit['blockers'] as List), isNotEmpty);
    expect(
      result.stderr.toString(),
      contains('Release readiness audit is blocked:'),
    );
  });

  test('readiness audit accepts artifact-matched Windows and Android evidence',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_audit_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    _writeJson(windowsQaJson, _windowsManualQaRecord(exe: exe, appSo: appSo));
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
      ),
    );

    expect(_checkById(audit, 'windowsManualQa')['status'], 'passed');
    expect(_checkById(audit, 'androidDeviceSmoke')['status'], 'passed');
  });

  test('readiness audit accepts release metadata pinned to zh and en',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_metadata_pass_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(windowsZip: windowsZip, androidApk: androidApk),
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    expect(_checkById(audit, 'releaseMetadata')['status'], 'passed');
  });

  test('readiness audit rejects release metadata with extra runtime language',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_metadata_language_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        supportedLanguages: const ['zh', 'en', 'ja'],
      ),
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    final metadataCheck = _checkById(audit, 'releaseMetadata');
    expect(metadataCheck['status'], 'blocked');
    expect(
      metadataCheck['summary'],
      contains(
        'Release metadata runtime.supportedLanguages must be exactly zh,en.',
      ),
    );
  });

  test('readiness audit rejects release metadata from another pubspec version',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_metadata_version_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        version: '0.1.1+1',
        tagName: 'v0.1.1+1',
      ),
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    final metadataCheck = _checkById(audit, 'releaseMetadata');
    expect(metadataCheck['status'], 'blocked');
    expect(
      metadataCheck['summary'],
      contains('Release metadata version must match pubspec.yaml.'),
    );
  });

  test('readiness audit rejects release metadata with wrong file name',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_metadata_file_name_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-wrong-release.json'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(windowsZip: windowsZip, androidApk: androidApk),
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    final metadataCheck = _checkById(audit, 'releaseMetadata');
    expect(metadataCheck['status'], 'blocked');
    expect(
      metadataCheck['summary'],
      contains(
        'Release metadata JSON file name must match pubspec.yaml version.',
      ),
    );
  });

  test('readiness audit rejects release metadata with stale toolchain',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_metadata_toolchain_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    final staleToolchain = _currentFlutterToolchain()
      ..['dartSdkVersion'] = '0.0.0-stale';
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        toolchainOverride: staleToolchain,
      ),
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    final metadataCheck = _checkById(audit, 'releaseMetadata');
    expect(metadataCheck['status'], 'blocked');
    expect(
      metadataCheck['summary'],
      contains(
        'Release metadata toolchain.dartSdkVersion must match the current Flutter toolchain.',
      ),
    );
  });

  test('readiness audit rejects release metadata with stale artifact hash',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_metadata_artifact_hash_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        androidApkSha256Override: '0' * 64,
      ),
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    final metadataCheck = _checkById(audit, 'releaseMetadata');
    expect(metadataCheck['status'], 'blocked');
    expect(
      metadataCheck['summary'],
      contains(
        "Release metadata artifact 'repapertodo-android-0.1.1-2.apk' SHA-256 must match the file.",
      ),
    );
  });

  test('readiness audit rejects release metadata with stale dependency lock',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_metadata_dependency_lock_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        dependencyLockSha256Override: '0' * 64,
      ),
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    final metadataCheck = _checkById(audit, 'releaseMetadata');
    expect(metadataCheck['status'], 'blocked');
    expect(
      metadataCheck['summary'],
      contains(
        'Release metadata dependencyLock SHA-256 must match pubspec.lock.',
      ),
    );
  });

  test('readiness audit rejects release metadata with stale release notes hash',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_metadata_release_notes_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseNotes =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release-notes.md'))
          ..writeAsStringSync('Release notes');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        releaseNotes: releaseNotes,
      ),
    );
    releaseNotes.writeAsStringSync('Changed notes');

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    final metadataCheck = _checkById(audit, 'releaseMetadata');
    expect(metadataCheck['status'], 'blocked');
    expect(
      metadataCheck['summary'],
      contains('Release metadata releaseNotes SHA-256 must match the file.'),
    );
  });

  test('readiness audit accepts release checksum file matched to metadata',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_checksum_pass_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseNotes =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release-notes.md'))
          ..writeAsStringSync('Release notes');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    final releaseChecksumsFile =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-sha256.txt'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        releaseNotes: releaseNotes,
      ),
    );
    _writeReleaseChecksums(
      file: releaseChecksumsFile,
      windowsZip: windowsZip,
      androidApk: androidApk,
      releaseMetadata: releaseMetadataJson,
      releaseNotes: releaseNotes,
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
          '-ReleaseChecksumsFile',
          releaseChecksumsFile.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    expect(_checkById(audit, 'releaseMetadata')['status'], 'passed');
    expect(_checkById(audit, 'releaseChecksums')['status'], 'passed');
  });

  test('readiness audit accepts ReleaseChecksumsPath alias', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_checksum_alias_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseNotes =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release-notes.md'))
          ..writeAsStringSync('Release notes');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    final releaseChecksumsFile =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-sha256.txt'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        releaseNotes: releaseNotes,
      ),
    );
    _writeReleaseChecksums(
      file: releaseChecksumsFile,
      windowsZip: windowsZip,
      androidApk: androidApk,
      releaseMetadata: releaseMetadataJson,
      releaseNotes: releaseNotes,
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
          '-ReleaseChecksumsPath',
          releaseChecksumsFile.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    expect(_checkById(audit, 'releaseMetadata')['status'], 'passed');
    expect(_checkById(audit, 'releaseChecksums')['status'], 'passed');
  });

  test('readiness audit rejects release checksum file with wrong file name',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_checksum_file_name_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseNotes =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release-notes.md'))
          ..writeAsStringSync('Release notes');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    final releaseChecksumsFile =
        File(p.join(temp.path, 'repapertodo-wrong-sha256.txt'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        releaseNotes: releaseNotes,
      ),
    );
    _writeReleaseChecksums(
      file: releaseChecksumsFile,
      windowsZip: windowsZip,
      androidApk: androidApk,
      releaseMetadata: releaseMetadataJson,
      releaseNotes: releaseNotes,
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
          '-ReleaseChecksumsFile',
          releaseChecksumsFile.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    final checksumCheck = _checkById(audit, 'releaseChecksums');
    expect(checksumCheck['status'], 'blocked');
    expect(
      checksumCheck['summary'],
      contains(
        'Release checksum file name must match release metadata version.',
      ),
    );
  });

  test('readiness audit rejects release checksum file with stale line',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_checksum_stale_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsZip =
        File(p.join(temp.path, 'repapertodo-windows-x64-0.1.1-2.zip'))
          ..writeAsStringSync('windows package');
    final androidApk =
        File(p.join(temp.path, 'repapertodo-android-0.1.1-2.apk'))
          ..writeAsStringSync('android package');
    final releaseNotes =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release-notes.md'))
          ..writeAsStringSync('Release notes');
    final releaseMetadataJson =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-release.json'));
    final releaseChecksumsFile =
        File(p.join(temp.path, 'repapertodo-0.1.1-2-sha256.txt'));
    _writeJson(
      releaseMetadataJson,
      _releaseMetadataRecord(
        windowsZip: windowsZip,
        androidApk: androidApk,
        releaseNotes: releaseNotes,
      ),
    );
    _writeReleaseChecksums(
      file: releaseChecksumsFile,
      windowsZip: windowsZip,
      androidApk: androidApk,
      releaseMetadata: releaseMetadataJson,
      releaseNotes: releaseNotes,
      androidApkSha256Override: '0' * 64,
    );

    final audit = _decodeAudit(
      await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          'scripts/release_readiness_audit.ps1',
          '-ReleaseMetadataJson',
          releaseMetadataJson.path,
          '-ReleaseChecksumsFile',
          releaseChecksumsFile.path,
        ],
        workingDirectory: Directory.current.path,
      ),
    );

    final checksumCheck = _checkById(audit, 'releaseChecksums');
    expect(checksumCheck['status'], 'blocked');
    expect(
      checksumCheck['summary'],
      contains('Release checksum file line 2 must match'),
    );
  });

  test('readiness audit rejects Windows manual QA from another build',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_windows_mismatch_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    _writeJson(
      windowsQaJson,
      _windowsManualQaRecord(
        exe: exe,
        appSo: appSo,
        exeSha256Override: '0' * 64,
      ),
    );
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
      ),
    );

    final windowsCheck = _checkById(audit, 'windowsManualQa');
    expect(windowsCheck['status'], 'blocked');
    expect(
      windowsCheck['summary'],
      contains(
        'Windows manual QA evidence exe SHA-256 must match the expected release build.',
      ),
    );
  });

  test(
      'readiness audit rejects Windows manual QA from another release directory',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_windows_directory_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    _writeJson(
      windowsQaJson,
      _windowsManualQaRecord(
        exe: exe,
        appSo: appSo,
        releaseDirectoryOverride: temp.path,
      ),
    );
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
      ),
    );

    final windowsCheck = _checkById(audit, 'windowsManualQa');
    expect(windowsCheck['status'], 'blocked');
    expect(
      windowsCheck['summary'],
      contains(
        'Windows manual QA evidence releaseDirectory must match the expected release directory.',
      ),
    );
  });

  test('readiness audit rejects unattributed Windows manual QA evidence',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_windows_unattributed_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    _writeJson(
      windowsQaJson,
      _windowsManualQaRecord(exe: exe, appSo: appSo, tester: '   '),
    );
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
      ),
    );

    final windowsCheck = _checkById(audit, 'windowsManualQa');
    expect(windowsCheck['status'], 'blocked');
    expect(
      windowsCheck['summary'],
      contains('Windows manual QA evidence must include a tester.'),
    );
  });

  test('readiness audit rejects Windows manual QA without OS evidence',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_windows_os_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    _writeJson(
      windowsQaJson,
      _windowsManualQaRecord(
        exe: exe,
        appSo: appSo,
        windowsVersion: '   ',
      ),
    );
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
      ),
    );

    final windowsCheck = _checkById(audit, 'windowsManualQa');
    expect(windowsCheck['status'], 'blocked');
    expect(
      windowsCheck['summary'],
      contains('Windows manual QA evidence must include windowsVersion.'),
    );
  });

  test('readiness audit rejects Windows manual QA with extra items', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_windows_extra_item_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    _writeJson(
      windowsQaJson,
      _windowsManualQaRecord(
        exe: exe,
        appSo: appSo,
        includeExtraItem: true,
      ),
    );
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
      ),
    );

    final windowsCheck = _checkById(audit, 'windowsManualQa');
    expect(windowsCheck['status'], 'blocked');
    expect(
      windowsCheck['summary'],
      contains(
          'Windows manual QA evidence must include exactly 7 checked items.'),
    );
  });

  test('readiness audit rejects Android device smoke from another APK',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_android_mismatch_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    _writeJson(windowsQaJson, _windowsManualQaRecord(exe: exe, appSo: appSo));
    _writeJson(
      androidSmokeJson,
      _androidDeviceSmokeRecord(
        apk: apk,
        apkSha256Override: '0' * 64,
      ),
    );

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
      ),
    );

    final androidCheck = _checkById(audit, 'androidDeviceSmoke');
    expect(androidCheck['status'], 'blocked');
    expect(
      androidCheck['summary'],
      contains(
        'Android device smoke evidence APK SHA-256 must match the expected APK.',
      ),
    );
  });

  test(
      'readiness audit rejects Android device smoke with wrong expected APK name',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_android_expected_name_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    _writeJson(windowsQaJson, _windowsManualQaRecord(exe: exe, appSo: appSo));
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'scripts/release_readiness_audit.ps1',
        '-WindowsManualQaResultJson',
        windowsQaJson.path,
        '-ExpectedWindowsReleaseDirectory',
        windowsRelease.path,
        '-AndroidDeviceSmokeResultJson',
        androidSmokeJson.path,
        '-ExpectedAndroidApkFileName',
        'repapertodo-android-0.1.1-1.apk',
        '-ExpectedAndroidApkPath',
        apk.path,
      ],
      workingDirectory: Directory.current.path,
    );
    final audit = _decodeAudit(result);

    final androidCheck = _checkById(audit, 'androidDeviceSmoke');
    expect(androidCheck['status'], 'blocked');
    expect(
      androidCheck['summary'],
      contains(
        'Android device smoke evidence must match the expected APK file name.',
      ),
    );
  });

  test(
      'readiness audit rejects Android device smoke with wrong expected APK path',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_android_expected_path_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final wrongNamedApk = File(p.join(temp.path, 'repapertodo-android-old.apk'))
      ..writeAsBytesSync(apk.readAsBytesSync());
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    _writeJson(windowsQaJson, _windowsManualQaRecord(exe: exe, appSo: appSo));
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: wrongNamedApk));

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'scripts/release_readiness_audit.ps1',
        '-WindowsManualQaResultJson',
        windowsQaJson.path,
        '-ExpectedWindowsReleaseDirectory',
        windowsRelease.path,
        '-AndroidDeviceSmokeResultJson',
        androidSmokeJson.path,
        '-ExpectedAndroidApkFileName',
        p.basename(wrongNamedApk.path),
        '-ExpectedAndroidApkPath',
        wrongNamedApk.path,
      ],
      workingDirectory: Directory.current.path,
    );
    final audit = _decodeAudit(result);

    final androidCheck = _checkById(audit, 'androidDeviceSmoke');
    expect(androidCheck['status'], 'blocked');
    expect(
      androidCheck['summary'],
      contains(
        'Android device smoke expected APK file name must match pubspec.yaml version.',
      ),
    );
  });

  test('readiness audit accepts generic and domestic WebDAV live evidence',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_webdav_pass_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    final genericWebDavJson = File(p.join(temp.path, 'webdav-live-smoke.json'));
    final domesticWebDavJson =
        File(p.join(temp.path, 'webdav-domestic-live-smoke.json'));
    _writeJson(windowsQaJson, _windowsManualQaRecord(exe: exe, appSo: appSo));
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));
    _writeJson(genericWebDavJson, _webDavLiveSmokeRecord(providerId: 'custom'));
    _writeJson(
      domesticWebDavJson,
      _webDavLiveSmokeRecord(providerId: 'jianguoyun'),
    );

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
        webDavLiveSmokeJson: genericWebDavJson.path,
        webDavDomesticLiveSmokeJson: domesticWebDavJson.path,
      ),
    );

    expect(_checkById(audit, 'webDavLiveSmoke')['status'], 'passed');
    expect(_checkById(audit, 'webDavDomesticLiveSmoke')['status'], 'passed');
  });

  test(
      'readiness audit rejects domestic WebDAV live smoke from generic provider',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_webdav_provider_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    final genericWebDavJson = File(p.join(temp.path, 'webdav-live-smoke.json'));
    final domesticWebDavJson =
        File(p.join(temp.path, 'webdav-domestic-live-smoke.json'));
    _writeJson(windowsQaJson, _windowsManualQaRecord(exe: exe, appSo: appSo));
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));
    _writeJson(genericWebDavJson, _webDavLiveSmokeRecord(providerId: 'custom'));
    _writeJson(
        domesticWebDavJson, _webDavLiveSmokeRecord(providerId: 'custom'));

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
        webDavLiveSmokeJson: genericWebDavJson.path,
        webDavDomesticLiveSmokeJson: domesticWebDavJson.path,
      ),
    );

    final domesticCheck = _checkById(audit, 'webDavDomesticLiveSmoke');
    expect(domesticCheck['status'], 'blocked');
    expect(
      domesticCheck['summary'],
      contains('WebDAV live smoke evidence must use providerId jianguoyun.'),
    );
  });

  test('readiness audit rejects WebDAV live smoke without Android sequence',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_webdav_sequence_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    final webDavSmokeJson = File(p.join(temp.path, 'webdav-live-smoke.json'));
    _writeJson(windowsQaJson, _windowsManualQaRecord(exe: exe, appSo: appSo));
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));
    _writeJson(
      webDavSmokeJson,
      _webDavLiveSmokeRecord(deviceSequences: {'windows-live-smoke': 1}),
    );

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
        webDavLiveSmokeJson: webDavSmokeJson.path,
      ),
    );

    final webDavCheck = _checkById(audit, 'webDavLiveSmoke');
    expect(webDavCheck['status'], 'blocked');
    expect(
      webDavCheck['summary'],
      contains(
        'WebDAV live smoke evidence must include a positive android-live-smoke device sequence.',
      ),
    );
  });

  test('readiness audit rejects WebDAV live smoke with unsafe root path',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for readiness audit tests.');
      return;
    }
    final windowsRelease = Directory(
      p.join('build', 'windows', 'x64', 'runner', 'Release'),
    );
    final exe = File(p.join(windowsRelease.path, 'repapertodo.exe'));
    final appSo = File(p.join(windowsRelease.path, 'data', 'app.so'));
    final apk = File(p.join('dist', 'repapertodo-android-0.1.1-2.apk'));
    if (!exe.existsSync() || !appSo.existsSync() || !apk.existsSync()) {
      markTestSkipped('Release artifacts are unavailable for hash matching.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_readiness_webdav_root_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final windowsQaJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final androidSmokeJson =
        File(p.join(temp.path, 'android-device-smoke.json'));
    final webDavSmokeJson = File(p.join(temp.path, 'webdav-live-smoke.json'));
    _writeJson(windowsQaJson, _windowsManualQaRecord(exe: exe, appSo: appSo));
    _writeJson(androidSmokeJson, _androidDeviceSmokeRecord(apk: apk));
    _writeJson(
      webDavSmokeJson,
      _webDavLiveSmokeRecord(rootPath: '../repapertodo-live-smoke/run-1'),
    );

    final audit = _decodeAudit(
      await _runReadinessAudit(
        powerShell: powerShell,
        windowsManualQaJson: windowsQaJson.path,
        androidDeviceSmokeJson: androidSmokeJson.path,
        windowsReleaseDirectory: windowsRelease.path,
        androidApkPath: apk.path,
        webDavLiveSmokeJson: webDavSmokeJson.path,
      ),
    );

    final webDavCheck = _checkById(audit, 'webDavLiveSmoke');
    expect(webDavCheck['status'], 'blocked');
    expect(
      webDavCheck['summary'],
      contains(
        'WebDAV live smoke evidence rootPath must be a relative run-scoped path.',
      ),
    );
  });
}
