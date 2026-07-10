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
  test('GitHub Release authentication reports token-specific failures',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for release auth testing.');
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
    $node.Name -eq 'Assert-GitHubAuthentication'
}, $true)
if ($null -eq $function) {
  throw "Assert-GitHubAuthentication was not found."
}
Invoke-Expression $function.Extent.Text
function gh {
  param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Args)
  $script:lastGhArgs = $Args
  $global:LASTEXITCODE = 1
}

$oldGhToken = $env:GH_TOKEN
$oldGitHubToken = $env:GITHUB_TOKEN
try {
  $env:GH_TOKEN = $null
  $env:GITHUB_TOKEN = $null
  try {
    Assert-GitHubAuthentication
    throw 'Expected missing GitHub CLI authentication to fail.'
  } catch {
    if ($_.Exception.Message -notlike '*authenticated GitHub CLI session*') {
      throw
    }
    if ($_.Exception.Message -like '*valid GH_TOKEN or GITHUB_TOKEN*') {
      throw 'Missing CLI login should not report an environment token failure.'
    }
  }

  $env:GH_TOKEN = 'expired-token'
  $env:GITHUB_TOKEN = $null
  try {
    Assert-GitHubAuthentication
    throw 'Expected invalid GH_TOKEN authentication to fail.'
  } catch {
    if ($_.Exception.Message -notlike '*valid GH_TOKEN or GITHUB_TOKEN*') {
      throw
    }
  }

  if (($script:lastGhArgs -join ' ') -ne 'auth status') {
    throw "Assert-GitHubAuthentication must call 'gh auth status'."
  }
} finally {
  $env:GH_TOKEN = $oldGhToken
  $env:GITHUB_TOKEN = $oldGitHubToken
}
''',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'Release publishing auth must distinguish invalid environment tokens from missing GitHub CLI login.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('GitHub Release git state gate rejects stale or wrong branches',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for release git testing.');
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
    $node.Name -eq 'Assert-GitHubReleaseGitState'
}, $true)
if ($null -eq $function) {
  throw "Assert-GitHubReleaseGitState was not found."
}
Invoke-Expression $function.Extent.Text
function Invoke-Native {
  param([string]$Name, [scriptblock]$Action)
  $script:fetchCalled = $true
}
function Invoke-NativeText {
  param([string]$Name, [scriptblock]$Action)
  if ($Name -eq 'git rev-parse --abbrev-ref HEAD') {
    return $script:branch
  }
  if ($Name -eq 'git rev-parse HEAD') {
    return $script:headCommit
  }
  if ($Name -eq 'git rev-parse --verify origin/main') {
    return $script:originMainCommit
  }
  throw "Unexpected native text command: $Name"
}

$script:fetchCalled = $false
$script:branch = 'feature'
$script:headCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$script:originMainCommit = $script:headCommit
try {
  Assert-GitHubReleaseGitState
  throw 'Expected non-main branch to fail.'
} catch {
  if ($_.Exception.Message -notlike '*main branch*') {
    throw
  }
}
if (-not $script:fetchCalled) {
  throw 'GitHub Release git state gate must fetch origin/main before checking refs.'
}

$script:branch = 'main'
$script:headCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$script:originMainCommit = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
try {
  Assert-GitHubReleaseGitState
  throw 'Expected stale origin/main to fail.'
} catch {
  if ($_.Exception.Message -notlike '*local HEAD to match origin/main*') {
    throw
  }
}

$oldGitHubActions = $env:GITHUB_ACTIONS
$oldGitHubRefName = $env:GITHUB_REF_NAME
try {
  $env:GITHUB_ACTIONS = 'true'
  $env:GITHUB_REF_NAME = 'main'
  $script:branch = 'HEAD'
  $script:headCommit = 'cccccccccccccccccccccccccccccccccccccccc'
  $script:originMainCommit = $script:headCommit
  Assert-GitHubReleaseGitState

  $env:GITHUB_REF_NAME = 'feature'
  try {
    Assert-GitHubReleaseGitState
    throw 'Expected detached non-main GitHub Actions ref to fail.'
  } catch {
    if ($_.Exception.Message -notlike '*main ref*') {
      throw
    }
  }
} finally {
  $env:GITHUB_ACTIONS = $oldGitHubActions
  $env:GITHUB_REF_NAME = $oldGitHubRefName
}
''',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'Release publishing must reject non-main branches and commits that differ from origin/main.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

  test('GitHub Release tag gate rejects mismatched remote tags', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for release tag testing.');
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
    $node.Name -eq 'Assert-GitHubReleaseTagState'
}, $true)
if ($null -eq $function) {
  throw "Assert-GitHubReleaseTagState was not found."
}
Invoke-Expression $function.Extent.Text
function git {
  param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Args)
  $script:lastGitArgs = $Args
  $global:LASTEXITCODE = 0
  return $script:tagLines
}

$matchingCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$differentCommit = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$script:tagLines = @()
Assert-GitHubReleaseTagState -TagName 'v1.0.0' -GitCommit $matchingCommit

$script:tagLines = @(
  "$matchingCommit`trefs/tags/v1.0.0",
  "$differentCommit`trefs/tags/v1.0.0^{}"
)
try {
  Assert-GitHubReleaseTagState -TagName 'v1.0.0' -GitCommit $matchingCommit
  throw 'Expected annotated tag peeled commit mismatch to fail.'
} catch {
  if ($_.Exception.Message -notlike '*already points to*') {
    throw
  }
}

$script:tagLines = @("$matchingCommit`trefs/tags/v1.0.0^{}")
Assert-GitHubReleaseTagState -TagName 'v1.0.0' -GitCommit $matchingCommit

if (($script:lastGitArgs -join ' ') -ne 'ls-remote --tags origin refs/tags/v1.0.0 refs/tags/v1.0.0^{}') {
  throw "Assert-GitHubReleaseTagState must query the exact remote tag and peeled tag refs."
}
''',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: [
        'Release publishing must reject existing GitHub tags that point to another commit.',
        if (result.stdout.toString().trim().isNotEmpty)
          'stdout: ${result.stdout}',
        if (result.stderr.toString().trim().isNotEmpty)
          'stderr: ${result.stderr}',
      ].join('\n'),
    );
  });

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
