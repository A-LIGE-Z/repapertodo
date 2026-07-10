import 'dart:convert';
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

Future<File> _writeFakeDartTool(
  Directory directory,
  Map<String, Object?> record,
) async {
  final jsonText = jsonEncode(record);
  if (Platform.isWindows) {
    final file = File(p.join(directory.path, 'fake-dart.cmd'));
    await file.writeAsString('@echo off\r\necho $jsonText\r\n');
    return file;
  }

  final file = File(p.join(directory.path, 'fake-dart.sh'));
  await file.writeAsString('#!/bin/sh\nprintf %s\\n \'$jsonText\'\n');
  await Process.run('chmod', ['755', file.path]);
  return file;
}

Map<String, Object?> _liveSmokeRecord({
  Map<String, int>? deviceSequences,
  String rootPath = 'repapertodo-live-smoke/run-20260709000000',
}) {
  return {
    'status': 'passed',
    'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'endpointHost': 'dav.example.test',
    'providerId': 'custom',
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

Future<ProcessResult> _runLiveSmokeScript({
  required String powerShell,
  required File dartTool,
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
      'scripts/webdav_live_smoke.ps1',
      '-Dart',
      dartTool.path,
      '-ResultJson',
      resultJson.path,
    ],
    workingDirectory: Directory.current.path,
    environment: const {
      'REPAPERTODO_WEBDAV_ENDPOINT': 'https://dav.example.test/dav/',
      'REPAPERTODO_WEBDAV_USERNAME': 'webdav-smoke-test',
      'REPAPERTODO_WEBDAV_PASSWORD': 'webdav-smoke-password',
      'REPAPERTODO_WEBDAV_PASSPHRASE': 'webdav-smoke-passphrase',
    },
  );
}

void main() {
  test('live WebDAV wrapper writes complete two-device evidence', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped(
          'PowerShell is unavailable for live smoke wrapper tests.');
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_webdav_live_wrapper_pass_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final dartTool = await _writeFakeDartTool(temp, _liveSmokeRecord());
    final resultJson = File(p.join(temp.path, 'webdav-live-smoke.json'));

    final result = await _runLiveSmokeScript(
      powerShell: powerShell,
      dartTool: dartTool,
      resultJson: resultJson,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(resultJson.existsSync(), true);
    final record =
        jsonDecode(resultJson.readAsStringSync()) as Map<String, Object?>;
    expect(record['status'], 'passed');
    expect(
      record['deviceSequences'],
      containsPair('android-live-smoke', 1),
    );
  });

  test('live WebDAV wrapper rejects missing Android device sequence', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped(
          'PowerShell is unavailable for live smoke wrapper tests.');
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_webdav_live_wrapper_sequence_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final dartTool = await _writeFakeDartTool(
      temp,
      _liveSmokeRecord(deviceSequences: {'windows-live-smoke': 1}),
    );
    final resultJson = File(p.join(temp.path, 'webdav-live-smoke.json'));

    final result = await _runLiveSmokeScript(
      powerShell: powerShell,
      dartTool: dartTool,
      resultJson: resultJson,
    );

    expect(result.exitCode, isNot(0));
    expect(resultJson.existsSync(), false);
    expect(
      result.stderr.toString(),
      contains(
        'Live WebDAV smoke result must include a positive android-live-smoke device sequence.',
      ),
    );
  });

  test('live WebDAV wrapper rejects unsafe remote root paths', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped(
          'PowerShell is unavailable for live smoke wrapper tests.');
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_webdav_live_wrapper_root_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final dartTool = await _writeFakeDartTool(
      temp,
      _liveSmokeRecord(rootPath: '../repapertodo-live-smoke/run-20260709'),
    );
    final resultJson = File(p.join(temp.path, 'webdav-live-smoke.json'));

    final result = await _runLiveSmokeScript(
      powerShell: powerShell,
      dartTool: dartTool,
      resultJson: resultJson,
    );

    expect(result.exitCode, isNot(0));
    expect(resultJson.existsSync(), false);
    expect(
      result.stderr.toString(),
      contains(
        'Live WebDAV smoke result rootPath must be a relative run-scoped path.',
      ),
    );
  });
}
