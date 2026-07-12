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
  test(
      'release evidence scripts reject unsafe result paths before side effects',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped(
        'PowerShell is unavailable for release evidence script tests.',
      );
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_release_result_path_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final unsafeResultPath = p.join(temp.path, 'release-evidence.txt');

    final cases = <({String script, String message, String laterMessage})>[
      (
        script: 'scripts/windows_smoke.ps1',
        message:
            'Windows release smoke result JSON path must use the .json extension.',
        laterMessage: 'Windows release smoke input was not found',
      ),
      (
        script: 'scripts/windows_policy_smoke.ps1',
        message:
            'Windows policy smoke result JSON path must use the .json extension.',
        laterMessage: 'Windows policy smoke release exe was not found',
      ),
      (
        script: 'scripts/webdav_smoke.ps1',
        message:
            'WebDAV static smoke result JSON path must use the .json extension.',
        laterMessage: 'Required WebDAV smoke input was not found',
      ),
      (
        script: 'scripts/webdav_live_smoke.ps1',
        message:
            'Live WebDAV smoke result JSON path must use the .json extension.',
        laterMessage:
            'Missing required environment variable REPAPERTODO_WEBDAV_ENDPOINT',
      ),
    ];

    for (final testCase in cases) {
      final result = await Process.run(
        powerShell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          testCase.script,
          '-ResultJson',
          unsafeResultPath,
        ],
        workingDirectory: Directory.current.path,
      );
      final output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, isNot(0), reason: output);
      expect(File(unsafeResultPath).existsSync(), false);
      expect(output, contains(testCase.message));
      expect(output, isNot(contains(testCase.laterMessage)));
    }
  });
}
