param(
  [string]$Dart = "",
  [string]$ResultJson = ""
)

$ErrorActionPreference = "Stop"

function Find-DartTool {
  param([string]$ConfiguredPath = "")

  if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
    if (-not (Test-Path -LiteralPath $ConfiguredPath -PathType Leaf)) {
      throw "Configured Dart tool was not found: $ConfiguredPath"
    }
    return $ConfiguredPath
  }

  $command = Get-Command dart -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $puroDart = Join-Path $env:USERPROFILE ".puro\envs\stable\flutter\bin\dart.bat"
  if (Test-Path -LiteralPath $puroDart -PathType Leaf) {
    return $puroDart
  }

  throw "Dart was not found. Pass -Dart or install the Flutter/Dart toolchain."
}

function Resolve-ResultJsonPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Live WebDAV smoke result JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "Live WebDAV smoke result JSON path must not contain wildcard characters."
  }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path)
  } catch {
    throw "Live WebDAV smoke result JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($fullPath))) {
    throw "Live WebDAV smoke result JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -ne ".json") {
    throw "Live WebDAV smoke result JSON path must use the .json extension."
  }
  return $fullPath
}

function Assert-RequiredEnvironment {
  param([string]$Name)

  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Missing required environment variable $Name for live WebDAV smoke."
  }
  if ($value -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Environment variable $Name must not contain control characters."
  }
}

function Assert-LiveSmokeDeviceSequences {
  param([object]$Record)

  $deviceSequences = $Record.PSObject.Properties["deviceSequences"].Value
  if ($null -eq $deviceSequences) {
    throw "Live WebDAV smoke result must include deviceSequences."
  }
  foreach ($deviceId in @("windows-live-smoke", "android-live-smoke")) {
    $sequenceProperty = $deviceSequences.PSObject.Properties[$deviceId]
    if ($null -eq $sequenceProperty -or
        -not ($sequenceProperty.Value -is [byte] -or
          $sequenceProperty.Value -is [sbyte] -or
          $sequenceProperty.Value -is [int16] -or
          $sequenceProperty.Value -is [uint16] -or
          $sequenceProperty.Value -is [int32] -or
          $sequenceProperty.Value -is [uint32] -or
          $sequenceProperty.Value -is [int64]) -or
        [int64]$sequenceProperty.Value -le 0) {
      throw "Live WebDAV smoke result must include a positive $deviceId device sequence."
    }
  }
}

function Test-LiveSmokeRootPathSafe {
  param([string]$RootPath)

  if ([string]::IsNullOrWhiteSpace($RootPath)) {
    return $false
  }
  if ($RootPath -match "[\x00-\x1F\x7F-\x9F]") {
    return $false
  }
  $normalized = $RootPath -replace "\\", "/"
  if ($normalized.StartsWith("/") -or $normalized -match "^[A-Za-z]:") {
    return $false
  }
  foreach ($segment in ($normalized -split "/")) {
    if ([string]::IsNullOrWhiteSpace($segment) -or
        $segment -ne $segment.Trim() -or
        $segment -eq "." -or
        $segment -eq "..") {
      return $false
    }
  }
  return $normalized.Contains("/run-")
}

function Assert-LiveSmokeRecord {
  param([object]$Record)

  if ([string]$Record.status -ne "passed") {
    throw "Live WebDAV smoke did not report a passed status."
  }
  foreach ($timestampProperty in @("checkedAtUtc", "startedAtUtc")) {
    $timestampValue = [string]$Record.$timestampProperty
    if ([string]::IsNullOrWhiteSpace($timestampValue)) {
      throw "Live WebDAV smoke result must include $timestampProperty."
    }
    try {
      $timestamp = [DateTimeOffset]::Parse($timestampValue)
      if ($timestamp.Offset -ne [TimeSpan]::Zero) {
        throw "not UTC"
      }
    } catch {
      throw "Live WebDAV smoke result $timestampProperty must be a UTC timestamp."
    }
  }
  foreach ($property in @("endpointHost", "providerId", "rootPath")) {
    if ([string]::IsNullOrWhiteSpace([string]$Record.$property)) {
      throw "Live WebDAV smoke result must include $property."
    }
  }
  if (-not (Test-LiveSmokeRootPathSafe -RootPath ([string]$Record.rootPath))) {
    throw "Live WebDAV smoke result rootPath must be a relative run-scoped path."
  }
  if ([string]$Record.windowsUploadStatus -ne "uploaded") {
    throw "Live WebDAV smoke result must confirm Windows upload."
  }
  if ([string]$Record.androidDownloadStatus -ne "downloaded") {
    throw "Live WebDAV smoke result must confirm Android download."
  }
  if ([int]$Record.androidOperationUploadedCount -lt 1) {
    throw "Live WebDAV smoke result must include at least one Android operation upload."
  }
  if ([int]$Record.windowsOperationAppliedCount -lt 1) {
    throw "Live WebDAV smoke result must include at least one Windows operation merge."
  }
  $cleanup = [string]$Record.remoteCleanup
  if ($cleanup -ne "attempted" -and $cleanup -ne "skipped") {
    throw "Live WebDAV smoke result remoteCleanup must be attempted or skipped."
  }
  Assert-LiveSmokeDeviceSequences -Record $Record
}

$resultJsonFullPath = Resolve-ResultJsonPath -Path $ResultJson
foreach ($name in @(
  "REPAPERTODO_WEBDAV_ENDPOINT",
  "REPAPERTODO_WEBDAV_USERNAME",
  "REPAPERTODO_WEBDAV_PASSWORD",
  "REPAPERTODO_WEBDAV_PASSPHRASE"
)) {
  Assert-RequiredEnvironment -Name $name
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$dartTool = Find-DartTool -ConfiguredPath $Dart
$smokeScript = Join-Path $repoRoot "tool\webdav_live_smoke.dart"
if (-not (Test-Path -LiteralPath $smokeScript -PathType Leaf)) {
  throw "Live WebDAV smoke Dart entrypoint was not found: $smokeScript"
}

$output = & $dartTool run $smokeScript
if ($LASTEXITCODE -ne 0) {
  throw "Live WebDAV smoke failed with exit code $LASTEXITCODE."
}
$jsonText = ($output -join "`n").Trim()
if ([string]::IsNullOrWhiteSpace($jsonText)) {
  throw "Live WebDAV smoke did not produce JSON output."
}
$record = $jsonText | ConvertFrom-Json
Assert-LiveSmokeRecord -Record $record

if (-not [string]::IsNullOrWhiteSpace($ResultJson)) {
  $resultDirectory = Split-Path -Parent $resultJsonFullPath
  if (-not [string]::IsNullOrWhiteSpace($resultDirectory)) {
    New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
  }
  $jsonText | Set-Content -LiteralPath $resultJsonFullPath -Encoding ascii
}

Write-Host "Live WebDAV smoke passed for $($record.endpointHost) with root $($record.rootPath)."
