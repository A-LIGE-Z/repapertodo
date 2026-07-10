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

Future<File> _writeFakeApkAnalyzer(Directory directory) async {
  if (Platform.isWindows) {
    final file = File(p.join(directory.path, 'fake-apkanalyzer.cmd'));
    await file.writeAsString(
      '@echo off\r\n'
      'if "%1"=="manifest" if "%2"=="application-id" (\r\n'
      '  echo com.aligez.repapertodo\r\n'
      '  exit /b 0\r\n'
      ')\r\n'
      'echo unexpected apkanalyzer args %* 1>&2\r\n'
      'exit /b 1\r\n',
    );
    return file;
  }

  final file = File(p.join(directory.path, 'fake-apkanalyzer.sh'));
  await file.writeAsString(
    '#!/bin/sh\n'
    'if [ "\$1" = "manifest" ] && [ "\$2" = "application-id" ]; then\n'
    '  printf "%s\\n" "com.aligez.repapertodo"\n'
    '  exit 0\n'
    'fi\n'
    'printf "%s\\n" "unexpected apkanalyzer args \$*" >&2\n'
    'exit 1\n',
  );
  await Process.run('chmod', ['755', file.path]);
  return file;
}

Future<File> _writeFakeAdb(
  Directory directory, {
  String apiLevel = '34',
  String processId = '12345',
  String foregroundPackage = 'com.aligez.repapertodo',
}) async {
  if (Platform.isWindows) {
    final file = File(p.join(directory.path, 'fake-adb.cmd'));
    await file.writeAsString(
      '@echo off\r\n'
      'if "%1"=="-s" (\r\n'
      '  shift\r\n'
      '  shift\r\n'
      ')\r\n'
      'if "%1"=="devices" (\r\n'
      '  echo List of devices attached\r\n'
      '  echo emulator-5554\tdevice\r\n'
      '  exit /b 0\r\n'
      ')\r\n'
      'if "%1"=="install" (\r\n'
      '  echo Success\r\n'
      '  exit /b 0\r\n'
      ')\r\n'
      'if "%1"=="shell" (\r\n'
      '  if "%2"=="getprop" (\r\n'
      '    echo $apiLevel\r\n'
      '    exit /b 0\r\n'
      '  )\r\n'
      '  if "%2"=="pidof" (\r\n'
      '    echo $processId\r\n'
      '    exit /b 0\r\n'
      '  )\r\n'
      '  if "%2"=="ps" (\r\n'
      '    echo USER PID NAME\r\n'
      '    echo u0_a1 $processId com.aligez.repapertodo\r\n'
      '    exit /b 0\r\n'
      '  )\r\n'
      '  if "%2"=="dumpsys" if "%3"=="window" (\r\n'
      '    echo mCurrentFocus=Window{123 u0 $foregroundPackage/.MainActivity}\r\n'
      '    exit /b 0\r\n'
      '  )\r\n'
      '  if "%2"=="dumpsys" if "%3"=="activity" (\r\n'
      '    echo mResumedActivity: ActivityRecord{ $foregroundPackage/.MainActivity }\r\n'
      '    exit /b 0\r\n'
      '  )\r\n'
      '  if "%2"=="am" (\r\n'
      '    echo OK\r\n'
      '    exit /b 0\r\n'
      '  )\r\n'
      ')\r\n'
      'echo unexpected adb args %* 1>&2\r\n'
      'exit /b 1\r\n',
    );
    return file;
  }

  final file = File(p.join(directory.path, 'fake-adb.sh'));
  await file.writeAsString(
    '#!/bin/sh\n'
    'if [ "\$1" = "-s" ]; then shift; shift; fi\n'
    'if [ "\$1" = "devices" ]; then\n'
    '  printf "%s\\n" "List of devices attached"\n'
    '  printf "%s\\n" "emulator-5554\tdevice"\n'
    '  exit 0\n'
    'fi\n'
    'if [ "\$1" = "install" ]; then printf "%s\\n" "Success"; exit 0; fi\n'
    'if [ "\$1" = "shell" ]; then\n'
    '  if [ "\$2" = "getprop" ]; then printf "%s\\n" "$apiLevel"; exit 0; fi\n'
    '  if [ "\$2" = "pidof" ]; then printf "%s\\n" "$processId"; exit 0; fi\n'
    '  if [ "\$2" = "ps" ]; then\n'
    '    printf "%s\\n" "USER PID NAME"\n'
    '    printf "%s\\n" "u0_a1 $processId com.aligez.repapertodo"\n'
    '    exit 0\n'
    '  fi\n'
    '  if [ "\$2" = "dumpsys" ] && [ "\$3" = "window" ]; then\n'
    '    printf "%s\\n" "mCurrentFocus=Window{123 u0 $foregroundPackage/.MainActivity}"\n'
    '    exit 0\n'
    '  fi\n'
    '  if [ "\$2" = "dumpsys" ] && [ "\$3" = "activity" ]; then\n'
    '    printf "%s\\n" "mResumedActivity: ActivityRecord{ $foregroundPackage/.MainActivity }"\n'
    '    exit 0\n'
    '  fi\n'
    '  if [ "\$2" = "am" ]; then printf "%s\\n" "OK"; exit 0; fi\n'
    'fi\n'
    'printf "%s\\n" "unexpected adb args \$*" >&2\n'
    'exit 1\n',
  );
  await Process.run('chmod', ['755', file.path]);
  return file;
}

Future<ProcessResult> _runDeviceSmoke({
  required String powerShell,
  required File apk,
  required File adb,
  required File apkAnalyzer,
  required File resultJson,
}) {
  return Process.run(
    powerShell,
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      'scripts/android_device_smoke.ps1',
      '-ApkPath',
      apk.path,
      '-Adb',
      adb.path,
      '-ApkAnalyzer',
      apkAnalyzer.path,
      '-DeviceSerial',
      'emulator-5554',
      '-LaunchWaitSeconds',
      '1',
      '-ResultJson',
      resultJson.path,
    ],
    workingDirectory: Directory.current.path,
  );
}

void main() {
  test('Android device smoke wrapper writes APK-matched launch evidence',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped(
        'PowerShell is unavailable for Android device smoke script tests.',
      );
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_android_device_smoke_pass_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final apk = File(p.join(temp.path, 'repapertodo-test.apk'));
    await apk.writeAsString('fake APK bytes for smoke wrapper test');
    final adb = await _writeFakeAdb(temp);
    final apkAnalyzer = await _writeFakeApkAnalyzer(temp);
    final resultJson = File(p.join(temp.path, 'android-device-smoke.json'));

    final result = await _runDeviceSmoke(
      powerShell: powerShell,
      apk: apk,
      adb: adb,
      apkAnalyzer: apkAnalyzer,
      resultJson: resultJson,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final record =
        jsonDecode(resultJson.readAsStringSync()) as Map<String, Object?>;
    expect(record['status'], 'passed');
    expect(record['apiLevel'], 34);
    expect(record['packageName'], 'com.aligez.repapertodo');
    expect(record['apkFileName'], 'repapertodo-test.apk');
    expect(record['apkBytes'], apk.lengthSync());
    expect(record['apkSha256'], _sha256File(apk));
    expect(record['processId'], '12345');
    expect(record['foregroundPackage'], 'com.aligez.repapertodo');
  });

  test('Android device smoke wrapper rejects invalid process evidence',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped(
        'PowerShell is unavailable for Android device smoke script tests.',
      );
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_android_device_smoke_process_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final apk = File(p.join(temp.path, 'repapertodo-test.apk'));
    await apk.writeAsString('fake APK bytes for process validation');
    final adb = await _writeFakeAdb(temp, processId: 'not-a-pid');
    final apkAnalyzer = await _writeFakeApkAnalyzer(temp);
    final resultJson = File(p.join(temp.path, 'android-device-smoke.json'));

    final result = await _runDeviceSmoke(
      powerShell: powerShell,
      apk: apk,
      adb: adb,
      apkAnalyzer: apkAnalyzer,
      resultJson: resultJson,
    );

    expect(result.exitCode, isNot(0));
    expect(resultJson.existsSync(), false);
    expect(
      result.stderr.toString(),
      contains('Android device smoke observed process ID must be a positive'),
    );
  });
}
