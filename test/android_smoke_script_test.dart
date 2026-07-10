import 'dart:io';

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

void main() {
  test('Android APK smoke rejects unsafe result paths before reading APK',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for Android smoke tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_android_smoke_result_path_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final unsafeResultPath = p.join(temp.path, 'android-smoke.txt');

    final result = await Process.run(
      powerShell,
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'scripts/android_smoke.ps1',
        '-ApkPath',
        p.join(temp.path, 'missing.apk'),
        '-ResultJson',
        unsafeResultPath,
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, isNot(0));
    expect(File(unsafeResultPath).existsSync(), false);
    expect(
      result.stderr.toString(),
      contains(
          'Android APK smoke result JSON path must use the .json extension.'),
    );
    expect(
      result.stderr.toString(),
      isNot(contains('Android release APK was not found')),
    );
  });
}
