import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  test('GitHub Release asset verification rejects duplicate asset names',
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
function Invoke-NativeText {
  param([string]$Name, [scriptblock]$Action)
  return '{"assets":[{"name":"expected.txt","size":1,"state":"uploaded"},{"name":"expected.txt","size":1,"state":"uploaded"}]}'
}
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "repapertodo-release-asset-duplicate-test-$([Guid]::NewGuid().ToString('N'))"
try {
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
  $expected = Join-Path $tempRoot 'expected.txt'
  [IO.File]::WriteAllText($expected, 'x', [Text.Encoding]::ASCII)
  try {
    Assert-GitHubReleaseAssets -TagName 'v-test' -ArtifactPaths @($expected)
    throw 'Expected duplicate GitHub Release assets to fail verification.'
  } catch {
    if ($_.Exception.Message -notlike "*contains 2 asset(s) named 'expected.txt', expected exactly one*") {
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
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'Release publishing must reject duplicate GitHub Release asset names.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('GitHub Release downloaded asset verification rejects SHA mismatch',
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
foreach ($functionName in @(
  'Assert-GitHubReleaseDownloadedAssets',
  'Assert-FileExists'
)) {
  $function = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
      $node.Name -eq $functionName
  }, $true)
  if ($null -eq $function) {
    throw "$functionName was not found."
  }
  Invoke-Expression $function.Extent.Text
}
function Invoke-Native {
  param([string]$Name, [scriptblock]$Action)
  [IO.File]::WriteAllText(
    (Join-Path $downloadRoot 'expected.txt'),
    'y',
    [Text.Encoding]::ASCII
  )
}
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "repapertodo-release-download-hash-test-$([Guid]::NewGuid().ToString('N'))"
try {
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
  $expected = Join-Path $tempRoot 'expected.txt'
  [IO.File]::WriteAllText($expected, 'x', [Text.Encoding]::ASCII)
  try {
    Assert-GitHubReleaseDownloadedAssets `
      -TagName 'v-test' `
      -ArtifactPaths @($expected)
    throw 'Expected downloaded GitHub Release asset hash mismatch to fail verification.'
  } catch {
    if ($_.Exception.Message -notlike "*SHA-256 does not match the packaged file*") {
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
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'Release publishing must reject downloaded GitHub Release assets whose bytes do not match the packaged file.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('release packaging rejects Windows QA from another release directory',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for release QA testing.');
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
foreach ($functionName in @(
  'Get-RecordPropertyValue',
  'Assert-RecordUtcTimestamp',
  'Assert-WindowsManualQaArtifact',
  'Assert-WindowsManualQaRecord'
)) {
  $function = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
      $node.Name -eq $functionName
  }, $true)
  if ($null -eq $function) {
    throw "$functionName was not found."
  }
  Invoke-Expression $function.Extent.Text
}
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "repapertodo-release-windows-qa-dir-test-$([Guid]::NewGuid().ToString('N'))"
try {
  $releaseDir = Join-Path $tempRoot 'Release'
  $dataDir = Join-Path $releaseDir 'data'
  New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
  $exe = Join-Path $releaseDir 'repapertodo.exe'
  $appSo = Join-Path $dataDir 'app.so'
  [IO.File]::WriteAllText($exe, 'fake exe', [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText($appSo, 'fake app so', [Text.Encoding]::ASCII)
  $exeItem = Get-Item -LiteralPath $exe
  $appSoItem = Get-Item -LiteralPath $appSo
  $exeHash = Get-FileHash -Algorithm SHA256 -LiteralPath $exe
  $appSoHash = Get-FileHash -Algorithm SHA256 -LiteralPath $appSo
  $items = @(
    'transparentBorderlessFeel',
    'taskSwitcherVisibility',
    'multiMonitorEdgeDocking',
    'fullscreenAvoidance',
    'trayAfterExplorerRestart',
    'longRunningScriptCapsule',
    'independentPaperSurfaces'
  ) | ForEach-Object {
    [pscustomobject]@{
      id = $_
      title = $_
      status = 'pass'
    }
  }
  $record = [pscustomobject]@{
    status = 'passed'
    checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    allowSkipped = $false
    tester = 'release-test'
    exeFileName = 'repapertodo.exe'
    releaseDirectory = $tempRoot
    exeBytes = $exeItem.Length
    exeSha256 = $exeHash.Hash.ToLowerInvariant()
    appSoRelativePath = 'data/app.so'
    appSoBytes = $appSoItem.Length
    appSoSha256 = $appSoHash.Hash.ToLowerInvariant()
    items = $items
  }
  try {
    Assert-WindowsManualQaRecord `
      -Record $record `
      -ExpectedExePath $exe `
      -ExpectedAppSoPath $appSo
    throw 'Expected stale Windows manual QA releaseDirectory to fail.'
  } catch {
    if ($_.Exception.Message -notlike '*releaseDirectory must match the Windows release build output*') {
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
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'Release packaging must reject Windows QA evidence recorded against another release directory.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });
}
