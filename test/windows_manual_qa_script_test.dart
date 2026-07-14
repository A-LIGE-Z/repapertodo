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

String _canonicalDirectoryPath(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return Directory(path).absolute.path;
  }
}

Future<({File exe, File appSo})> _writeReleaseFiles(Directory directory) async {
  final release = Directory(p.join(directory.path, 'Release'));
  final data = Directory(p.join(release.path, 'data'));
  await data.create(recursive: true);
  final exe = File(p.join(release.path, 'repapertodo.exe'));
  final appSo = File(p.join(data.path, 'app.so'));
  await exe.writeAsString('fake repapertodo exe bytes for QA evidence');
  await appSo.writeAsString('fake Flutter AOT app.so bytes for QA evidence');
  return (exe: exe, appSo: appSo);
}

Future<ProcessResult> _runManualQa({
  required String powerShell,
  required File exe,
  required File resultJson,
  required String fullscreenAvoidance,
  String multiMonitorEdgeDocking = 'pass',
  String tester = ' qa-tester ',
  String notes = '',
  bool allowSkipped = false,
  bool deferMultiMonitor = false,
  String? resultJsonPath,
}) {
  final arguments = [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    'scripts/windows_manual_qa.ps1',
    '-TransparentBorderlessFeel',
    'pass',
    '-TaskSwitcherVisibility',
    'pass',
    '-MultiMonitorEdgeDocking',
    multiMonitorEdgeDocking,
    '-FullscreenAvoidance',
    fullscreenAvoidance,
    '-TrayAfterExplorerRestart',
    'pass',
    '-LongRunningScriptCapsule',
    'pass',
    '-IndependentPaperSurfaces',
    'pass',
    '-Tester',
    tester,
    '-Notes',
    notes,
    '-ExePath',
    exe.path,
    '-ResultJson',
    resultJsonPath ?? resultJson.path,
  ];
  if (allowSkipped) {
    arguments.add('-AllowSkipped');
  }
  if (deferMultiMonitor) {
    arguments.add('-DeferMultiMonitor');
  }
  return Process.run(
    powerShell,
    arguments,
    workingDirectory: Directory.current.path,
  );
}

void main() {
  test('Windows manual QA script writes build-bound pass evidence', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for Windows manual QA tests.');
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_windows_manual_qa_pass_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final (:exe, :appSo) = await _writeReleaseFiles(temp);
    final resultJson = File(p.join(temp.path, 'windows-manual-qa.json'));

    final result = await _runManualQa(
      powerShell: powerShell,
      exe: exe,
      resultJson: resultJson,
      fullscreenAvoidance: 'pass',
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final record =
        jsonDecode(resultJson.readAsStringSync()) as Map<String, Object?>;
    expect(record['status'], 'passed');
    expect(record['tester'], 'qa-tester');
    expect(record['windowsVersion'], isA<String>());
    expect((record['windowsVersion'] as String).trim(), isNotEmpty);
    expect(
      p.equals(
        _canonicalDirectoryPath(record['releaseDirectory'] as String),
        _canonicalDirectoryPath(exe.parent.path),
      ),
      true,
    );
    expect(record['exeFileName'], 'repapertodo.exe');
    expect(record['exeBytes'], exe.lengthSync());
    expect(record['exeSha256'], _sha256File(exe));
    expect(record['appSoRelativePath'], 'data/app.so');
    expect(record['appSoBytes'], appSo.lengthSync());
    expect(record['appSoSha256'], _sha256File(appSo));
    expect(record['allowSkipped'], false);
    expect(record['deferMultiMonitor'], false);
    expect(record['deferredItemIds'], isEmpty);
    final items = (record['items'] as List).cast<Map<String, Object?>>();
    expect(items, hasLength(7));
    expect(items.every((item) => item['status'] == 'pass'), true);
  });

  test('Windows manual QA script records only multi-monitor as deferred',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for Windows manual QA tests.');
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_windows_manual_qa_deferred_monitor_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final (:exe, :appSo) = await _writeReleaseFiles(temp);
    final resultJson = File(p.join(temp.path, 'windows-manual-qa.json'));

    final result = await _runManualQa(
      powerShell: powerShell,
      exe: exe,
      resultJson: resultJson,
      fullscreenAvoidance: 'pass',
      multiMonitorEdgeDocking: 'skip',
      notes: 'Single-monitor workstation; cross-screen behavior deferred.',
      deferMultiMonitor: true,
    );

    expect(appSo.existsSync(), true);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final record =
        jsonDecode(resultJson.readAsStringSync()) as Map<String, Object?>;
    expect(record['status'], 'passedWithDeferredMultiMonitor');
    expect(record['deferMultiMonitor'], true);
    expect(record['deferredItemIds'], ['multiMonitorEdgeDocking']);
    expect((record['notes'] as String).trim(), isNotEmpty);
    final items = (record['items'] as List).cast<Map<String, Object?>>();
    expect(
      items.singleWhere(
          (item) => item['id'] == 'multiMonitorEdgeDocking')['status'],
      'skip',
    );
    expect(
      items
          .where((item) => item['id'] != 'multiMonitorEdgeDocking')
          .every((item) => item['status'] == 'pass'),
      true,
    );
  });

  test('Windows manual QA script rejects deferring another item', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for Windows manual QA tests.');
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_windows_manual_qa_wrong_deferred_item_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final (:exe, :appSo) = await _writeReleaseFiles(temp);
    final resultJson = File(p.join(temp.path, 'windows-manual-qa.json'));

    final result = await _runManualQa(
      powerShell: powerShell,
      exe: exe,
      resultJson: resultJson,
      fullscreenAvoidance: 'skip',
      notes: 'Attempted wrong deferral.',
      deferMultiMonitor: true,
    );

    expect(appSo.existsSync(), true);
    expect(result.exitCode, isNot(0));
    expect(resultJson.existsSync(), false);
    expect(
      result.stderr.toString(),
      contains('requires multiMonitorEdgeDocking to be the only skipped'),
    );
  });

  test('Windows manual QA script rejects skipped items by default', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for Windows manual QA tests.');
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_windows_manual_qa_skip_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final (:exe, :appSo) = await _writeReleaseFiles(temp);
    final resultJson = File(p.join(temp.path, 'windows-manual-qa.json'));

    final result = await _runManualQa(
      powerShell: powerShell,
      exe: exe,
      resultJson: resultJson,
      fullscreenAvoidance: 'skip',
    );

    expect(appSo.existsSync(), true);
    expect(result.exitCode, isNot(0));
    expect(resultJson.existsSync(), false);
    expect(
      result.stderr.toString(),
      contains('Windows manual QA contains skipped items.'),
    );
  });

  test('Windows manual QA script rejects unsafe result evidence paths',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for Windows manual QA tests.');
      return;
    }
    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_windows_manual_qa_result_path_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final (:exe, :appSo) = await _writeReleaseFiles(temp);
    final resultJson = File(p.join(temp.path, 'windows-manual-qa.json'));
    final unsafeResultPath = p.join(temp.path, 'windows-manual-qa.txt');

    final result = await _runManualQa(
      powerShell: powerShell,
      exe: exe,
      resultJson: resultJson,
      fullscreenAvoidance: 'pass',
      resultJsonPath: unsafeResultPath,
    );

    expect(appSo.existsSync(), true);
    expect(result.exitCode, isNot(0));
    expect(resultJson.existsSync(), false);
    expect(File(unsafeResultPath).existsSync(), false);
    expect(
      result.stderr.toString(),
      contains(
          'Windows manual QA result JSON path must use the .json extension.'),
    );
  });
}
