param(
  [ValidateSet("", "pass", "fail", "skip")]
  [string]$TransparentBorderlessFeel = "",
  [ValidateSet("", "pass", "fail", "skip")]
  [string]$TaskSwitcherVisibility = "",
  [ValidateSet("", "pass", "fail", "skip")]
  [string]$MultiMonitorEdgeDocking = "",
  [ValidateSet("", "pass", "fail", "skip")]
  [string]$FullscreenAvoidance = "",
  [ValidateSet("", "pass", "fail", "skip")]
  [string]$TrayAfterExplorerRestart = "",
  [ValidateSet("", "pass", "fail", "skip")]
  [string]$LongRunningScriptCapsule = "",
  [ValidateSet("", "pass", "fail", "skip")]
  [string]$IndependentPaperSurfaces = "",
  [switch]$AllowSkipped,
  [string]$Tester = "",
  [string]$Notes = "",
  [string]$ExePath = "build\windows\x64\runner\Release\repapertodo.exe",
  [string]$ResultJson = ""
)

$ErrorActionPreference = "Stop"

function Assert-StatusProvided {
  param(
    [string]$Name,
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "Windows manual QA item '$Name' must be pass, fail, or skip."
  }
}

function New-QaItem {
  param(
    [string]$Id,
    [string]$Title,
    [string]$Status
  )

  Assert-StatusProvided -Name $Id -Value $Status
  [ordered]@{
    id = $Id
    title = $Title
    status = $Status
  }
}

function Get-WindowsVersionText {
  try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    return "$($os.Caption) $($os.Version) build $($os.BuildNumber)"
  } catch {
    return [Environment]::OSVersion.VersionString
  }
}

function Resolve-ResultJsonPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Windows manual QA result JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "Windows manual QA result JSON path must not contain wildcard characters."
  }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path)
  } catch {
    throw "Windows manual QA result JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($fullPath))) {
    throw "Windows manual QA result JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -ne ".json") {
    throw "Windows manual QA result JSON path must use the .json extension."
  }
  return $fullPath
}

$resultJsonFullPath = Resolve-ResultJsonPath -Path $ResultJson
$exeFullPath = [IO.Path]::GetFullPath($ExePath)
if (-not (Test-Path -LiteralPath $exeFullPath -PathType Leaf)) {
  throw "Windows manual QA exe was not found: $exeFullPath"
}
if ([IO.Path]::GetFileName($exeFullPath) -ine "repapertodo.exe") {
  throw "Windows manual QA exe path must point to repapertodo.exe."
}
$exeItem = Get-Item -LiteralPath $exeFullPath
$exeHash = Get-FileHash -Algorithm SHA256 -LiteralPath $exeFullPath
$releaseDirectory = Split-Path -Parent $exeFullPath
$appSoRelativePath = "data/app.so"
$appSoFullPath = Join-Path $releaseDirectory $appSoRelativePath
if (-not (Test-Path -LiteralPath $appSoFullPath -PathType Leaf)) {
  throw "Windows manual QA Dart AOT library was not found: $appSoFullPath"
}
$appSoItem = Get-Item -LiteralPath $appSoFullPath
$appSoHash = Get-FileHash -Algorithm SHA256 -LiteralPath $appSoFullPath

$items = @(
  New-QaItem `
    -Id "transparentBorderlessFeel" `
    -Title "Transparent borderless paper feel matches PaperTodo" `
    -Status $TransparentBorderlessFeel
  New-QaItem `
    -Id "taskSwitcherVisibility" `
    -Title "Task-switcher visibility follows the configured setting" `
    -Status $TaskSwitcherVisibility
  New-QaItem `
    -Id "multiMonitorEdgeDocking" `
    -Title "Capsule and paper edge docking behave across monitors" `
    -Status $MultiMonitorEdgeDocking
  New-QaItem `
    -Id "fullscreenAvoidance" `
    -Title "Fullscreen foreground apps hide or lower PaperTodo surfaces as configured" `
    -Status $FullscreenAvoidance
  New-QaItem `
    -Id "trayAfterExplorerRestart" `
    -Title "Tray icon and menu recover after Explorer restarts" `
    -Status $TrayAfterExplorerRestart
  New-QaItem `
    -Id "longRunningScriptCapsule" `
    -Title "Long-running script capsules stay controllable and do not block the UI" `
    -Status $LongRunningScriptCapsule
  New-QaItem `
    -Id "independentPaperSurfaces" `
    -Title "Multiple visible papers behave as independent desktop surfaces" `
    -Status $IndependentPaperSurfaces
)

$failed = @($items | Where-Object { $_.status -eq "fail" })
$skipped = @($items | Where-Object { $_.status -eq "skip" })
if ($skipped.Count -gt 0 -and -not $AllowSkipped) {
  throw "Windows manual QA contains skipped items. Pass -AllowSkipped only for non-publishable exploratory records."
}

$recordStatus = if ($failed.Count -gt 0) {
  "failed"
} elseif ($skipped.Count -gt 0) {
  "skipped"
} else {
  "passed"
}
if ($recordStatus -eq "passed" -and [string]::IsNullOrWhiteSpace($Tester)) {
  throw "Windows manual QA passed records require -Tester so release evidence is attributable."
}
$recordReason = if ($recordStatus -eq "skipped") {
  "one or more Windows manual QA items were skipped; non-publishable exploratory record"
} else {
  ""
}

$record = [ordered]@{
  status = $recordStatus
  checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  reason = $recordReason
  tester = $Tester.Trim()
  windowsVersion = Get-WindowsVersionText
  exePath = $exeFullPath
  releaseDirectory = $releaseDirectory
  exeFileName = [IO.Path]::GetFileName($exeFullPath)
  exeBytes = $exeItem.Length
  exeSha256 = $exeHash.Hash.ToLowerInvariant()
  appSoRelativePath = $appSoRelativePath
  appSoBytes = $appSoItem.Length
  appSoSha256 = $appSoHash.Hash.ToLowerInvariant()
  allowSkipped = [bool]$AllowSkipped
  notes = $Notes.Trim()
  items = $items
}

if (-not [string]::IsNullOrWhiteSpace($ResultJson)) {
  $resultDirectory = Split-Path -Parent $resultJsonFullPath
  if (-not [string]::IsNullOrWhiteSpace($resultDirectory)) {
    New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
  }
  $record |
    ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $resultJsonFullPath -Encoding ascii
}

if ($recordStatus -eq "failed") {
  throw "Windows manual QA failed: $($failed.id -join ', ')"
}

Write-Host "Windows manual QA $recordStatus with $($items.Count) checked item(s)."
