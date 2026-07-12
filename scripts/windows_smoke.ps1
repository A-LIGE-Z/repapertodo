param(
  [string]$ReleaseDirectory = "",
  [int]$StartupTimeoutSeconds = 30,
  [int]$ExitTimeoutSeconds = 30,
  [string]$ResultJson = ""
)

$ErrorActionPreference = "Stop"

function Assert-WindowsHost {
  if (-not ($IsWindows -or $env:OS -eq "Windows_NT")) {
    throw "Windows release smoke tests can only run on Windows."
  }
}

function Assert-NoExistingRePaperTodoProcess {
  $processes = @(Get-Process -Name "repapertodo" -ErrorAction SilentlyContinue)
  if ($processes.Count -gt 0) {
    $processIds = ($processes | ForEach-Object { $_.Id }) -join ", "
    throw "Close existing RePaperTodo processes before running the Windows smoke test. Running process IDs: $processIds"
  }
}

function Assert-PathInside {
  param(
    [string]$Path,
    [string]$ParentPath,
    [string]$Message
  )

  $resolvedPath = [IO.Path]::GetFullPath($Path)
  $resolvedParent = [IO.Path]::GetFullPath($ParentPath)
  if (-not $resolvedParent.EndsWith([IO.Path]::DirectorySeparatorChar)) {
    $resolvedParent = "$resolvedParent$([IO.Path]::DirectorySeparatorChar)"
  }
  if ($resolvedPath -eq $resolvedParent.TrimEnd([IO.Path]::DirectorySeparatorChar) -or
      -not $resolvedPath.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw $Message
  }
}

function Wait-ForCondition {
  param(
    [scriptblock]$Condition,
    [int]$TimeoutSeconds,
    [string]$TimeoutMessage
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Condition) {
      return
    }
    Start-Sleep -Milliseconds 250
  }
  throw $TimeoutMessage
}

function Get-PaperCount {
  param([string]$StateFile)

  $counts = Get-PaperTypeCounts -StateFile $StateFile
  return [int]$counts.total
}

function Get-VisiblePaperCount {
  param([string]$StateFile)

  if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    return 0
  }
  try {
    $state = Get-Content -Raw -LiteralPath $StateFile | ConvertFrom-Json
    $visibleCount = 0
    foreach ($paper in @($state.papers)) {
      if ([bool]$paper.isVisible) {
        $visibleCount += 1
      }
    }
    return $visibleCount
  } catch {
    return 0
  }
}

function Initialize-WindowEnumerator {
  if ("RePaperTodoSmokeWindowEnumerator" -as [type]) {
    return
  }
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class RePaperTodoSmokeWindowEnumerator {
  public delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

  [DllImport("user32.dll")]
  private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

  [DllImport("user32.dll")]
  private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

  [DllImport("user32.dll")]
  private static extern bool IsWindowVisible(IntPtr window);

  [DllImport("user32.dll")]
  private static extern bool GetWindowRect(IntPtr window, out RECT bounds);

  [DllImport("user32.dll")]
  private static extern bool PostMessage(IntPtr window, uint message,
                                         IntPtr wParam, IntPtr lParam);

  private struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  public static int CountVisibleTopLevelWindows(uint expectedProcessId) {
    var count = 0;
    EnumWindows((window, parameter) => {
      uint processId;
      GetWindowThreadProcessId(window, out processId);
      if (processId == expectedProcessId && IsWindowVisible(window)) {
        count += 1;
      }
      return true;
    }, IntPtr.Zero);
    return count;
  }

  public static long FindVisibleCoordinatorWindow(uint expectedProcessId) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      uint processId;
      GetWindowThreadProcessId(window, out processId);
      if (processId != expectedProcessId || !IsWindowVisible(window)) {
        return true;
      }
      RECT bounds;
      if (GetWindowRect(window, out bounds) &&
          bounds.Right - bounds.Left >= 800 &&
          bounds.Bottom - bounds.Top >= 500) {
        result = window;
        return false;
      }
      return true;
    }, IntPtr.Zero);
    return result.ToInt64();
  }

  public static bool CloseWindow(long window) {
    return window != 0 && PostMessage(new IntPtr(window), 0x0010,
                                      IntPtr.Zero, IntPtr.Zero);
  }
}
"@ | Out-Null
}

function Get-VisibleTopLevelWindowCount {
  param([int]$ProcessId)

  Initialize-WindowEnumerator
  return [RePaperTodoSmokeWindowEnumerator]::CountVisibleTopLevelWindows(
    [uint32]$ProcessId)
}

function Get-VisibleCoordinatorWindow {
  param([int]$ProcessId)

  Initialize-WindowEnumerator
  return [RePaperTodoSmokeWindowEnumerator]::FindVisibleCoordinatorWindow(
    [uint32]$ProcessId)
}

function Close-CoordinatorWindow {
  param([long]$WindowHandle)

  Initialize-WindowEnumerator
  if (-not [RePaperTodoSmokeWindowEnumerator]::CloseWindow($WindowHandle)) {
    throw "Windows release smoke could not close the settings coordinator window."
  }
}

function Get-PaperTypeCounts {
  param([string]$StateFile)

  $counts = [ordered]@{
    total = 0
    todo = 0
    note = 0
    other = 0
  }
  if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    return $counts
  }
  try {
    $state = Get-Content -Raw -LiteralPath $StateFile | ConvertFrom-Json
    if ($null -eq $state.papers) {
      return $counts
    }
    foreach ($paper in @($state.papers)) {
      $counts.total += 1
      $type = ([string]$paper.type).Trim().ToLowerInvariant()
      if ($type -eq "todo") {
        $counts.todo += 1
      } elseif ($type -eq "note") {
        $counts.note += 1
      } else {
        $counts.other += 1
      }
    }
  } catch {
    return [ordered]@{
      total = 0
      todo = 0
      note = 0
      other = 0
    }
  }
  return $counts
}

function Invoke-SecondaryStartupCommand {
  param(
    [string]$Executable,
    [string]$WorkingDirectory,
    [string]$Command
  )

  $process = Start-Process `
    -FilePath $Executable `
    -ArgumentList $Command `
    -WorkingDirectory $WorkingDirectory `
    -WindowStyle Hidden `
    -PassThru
  if (-not $process.WaitForExit(10000)) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw "Secondary startup command '$Command' did not exit promptly."
  }
  if ($process.ExitCode -ne 0) {
    throw "Secondary startup command '$Command' failed with exit code $($process.ExitCode)."
  }
}

function Remove-SmokeRoot {
  param(
    [string]$SmokeRoot,
    [string]$TempRoot
  )

  if ([string]::IsNullOrWhiteSpace($SmokeRoot) -or
      -not (Test-Path -LiteralPath $SmokeRoot)) {
    return
  }
  Assert-PathInside `
    -Path $SmokeRoot `
    -ParentPath $TempRoot `
    -Message "Refusing to remove a smoke-test directory outside the system temp path."
  $lastError = $null
  for ($attempt = 1; $attempt -le 10; $attempt += 1) {
    try {
      Remove-Item -LiteralPath $SmokeRoot -Recurse -Force
      return
    } catch {
      $lastError = $_
      Start-Sleep -Milliseconds 300
    }
  }
  throw $lastError
}

function Resolve-ResultJsonPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Windows release smoke result JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "Windows release smoke result JSON path must not contain wildcard characters."
  }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path)
  } catch {
    throw "Windows release smoke result JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($fullPath))) {
    throw "Windows release smoke result JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -ne ".json") {
    throw "Windows release smoke result JSON path must use the .json extension."
  }
  return $fullPath
}

$resultJsonFullPath = Resolve-ResultJsonPath -Path $ResultJson
Assert-WindowsHost
Assert-NoExistingRePaperTodoProcess

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
  $ReleaseDirectory = Join-Path $repoRoot "build\windows\x64\runner\Release"
}
$releaseDirectoryFullPath = [IO.Path]::GetFullPath($ReleaseDirectory)
$sourceExe = Join-Path $releaseDirectoryFullPath "repapertodo.exe"
$sourceFlutterDll = Join-Path $releaseDirectoryFullPath "flutter_windows.dll"
$sourceDataDirectory = Join-Path $releaseDirectoryFullPath "data"

foreach ($requiredPath in @($sourceExe, $sourceFlutterDll, $sourceDataDirectory)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "Windows release smoke input was not found: $requiredPath"
  }
}

$tempRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot ".tmp"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$smokeRoot = Join-Path $tempRoot "repapertodo-windows-smoke-$([Guid]::NewGuid().ToString("N"))"
$smokeReleaseDirectory = Join-Path $smokeRoot "Release"
$smokeExe = Join-Path $smokeReleaseDirectory "repapertodo.exe"
$smokeStateFile = Join-Path $smokeReleaseDirectory "data.json"
$primaryProcess = $null
$smokeFailure = $null
$hiddenStartupCommands = @("--hide")
$ignoredSecondaryStartupCommands = @("--unknown-startup-command")
$secondaryStartupCommands = @("--new-note", "--new-todo", "--exit")
$settingsStartupCommands = @("--settings")
$initialPaperCount = 0
$initialVisibleWindowCount = 0
$finalVisibleWindowCount = 0
$visiblePaperCountAfterIgnoredCommand = 0
$visiblePaperCountBeforeSettings = 0
$visibleTopLevelWindowCountWhileSettingsOpen = 0
$visibleTopLevelWindowCountAfterSettingsClose = 0
$initialPaperTypeCounts = [ordered]@{
  total = 0
  todo = 0
  note = 0
  other = 0
}

try {
  New-Item -ItemType Directory -Force -Path $smokeReleaseDirectory | Out-Null
  Copy-Item `
    -Path (Join-Path $releaseDirectoryFullPath "*") `
    -Destination $smokeReleaseDirectory `
    -Recurse `
    -Force

  $primaryProcess = Start-Process `
    -FilePath $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -WindowStyle Hidden `
    -PassThru

  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke app did not create an initial data.json in time." `
    -Condition {
      -not $primaryProcess.HasExited -and
        (Test-Path -LiteralPath $smokeStateFile -PathType Leaf) -and
        (Get-PaperCount -StateFile $smokeStateFile) -ge 1
    }

  $initialPaperTypeCounts = Get-PaperTypeCounts -StateFile $smokeStateFile
  $initialPaperCount = [int]$initialPaperTypeCounts.total
  Start-Sleep -Milliseconds 1000
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke did not create one visible top-level window per initial paper." `
    -Condition {
      $visibleWindowCount = Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id
      $visibleWindowCount -ge $initialPaperCount
    }
  $initialVisibleWindowCount =
    Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id

  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $hiddenStartupCommands[0]

  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke app did not persist secondary --hide command in time." `
    -Condition {
      -not $primaryProcess.HasExited -and
        (Get-VisiblePaperCount -StateFile $smokeStateFile) -eq 0
    }
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke did not hide every independent paper window." `
    -Condition {
      (Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id) -eq 0
    }

  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $ignoredSecondaryStartupCommands[0]

  Start-Sleep -Milliseconds 750
  $visiblePaperCountAfterIgnoredCommand =
    Get-VisiblePaperCount -StateFile $smokeStateFile
  if ($visiblePaperCountAfterIgnoredCommand -ne 0) {
    throw "Windows release smoke unknown secondary startup command unexpectedly changed paper visibility."
  }

  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $secondaryStartupCommands[0]
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke app did not persist the secondary --new-note paper in time." `
    -Condition {
      -not $primaryProcess.HasExited -and
        (Get-PaperCount -StateFile $smokeStateFile) -ge ($initialPaperCount + 1)
    }
  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $secondaryStartupCommands[1]

  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke app did not persist secondary startup command papers in time." `
    -Condition {
      -not $primaryProcess.HasExited -and
        (Get-PaperCount -StateFile $smokeStateFile) -ge 3
    }
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke did not create one visible top-level HWND per visible paper." `
    -Condition {
      $visiblePapers = Get-VisiblePaperCount -StateFile $smokeStateFile
      $visibleWindows = Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id
      $visiblePapers -ge 2 -and $visibleWindows -ge $visiblePapers
    }
  $finalVisibleWindowCount =
    Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id

  $visiblePaperCountBeforeSettings =
    Get-VisiblePaperCount -StateFile $smokeStateFile
  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $settingsStartupCommands[0]
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke forwarded --settings command did not reveal the coordinator window." `
    -Condition {
      (Get-VisibleCoordinatorWindow -ProcessId $primaryProcess.Id) -ne 0 -and
        (Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id) -ge
          ($visiblePaperCountBeforeSettings + 1)
    }
  $visibleTopLevelWindowCountWhileSettingsOpen =
    Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id
  $coordinatorWindow =
    Get-VisibleCoordinatorWindow -ProcessId $primaryProcess.Id
  Close-CoordinatorWindow -WindowHandle $coordinatorWindow
  Wait-ForCondition `
    -TimeoutSeconds $StartupTimeoutSeconds `
    -TimeoutMessage "Windows release smoke settings coordinator did not close without changing independent papers." `
    -Condition {
      (Get-VisibleCoordinatorWindow -ProcessId $primaryProcess.Id) -eq 0 -and
        (Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id) -eq
          $visiblePaperCountBeforeSettings -and
        (Get-VisiblePaperCount -StateFile $smokeStateFile) -eq
          $visiblePaperCountBeforeSettings
    }
  $visibleTopLevelWindowCountAfterSettingsClose =
    Get-VisibleTopLevelWindowCount -ProcessId $primaryProcess.Id

  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $secondaryStartupCommands[2]

  if (-not $primaryProcess.WaitForExit($ExitTimeoutSeconds * 1000)) {
    throw "Windows release smoke app did not exit after --exit forwarding."
  }
  if ($primaryProcess.ExitCode -ne 0) {
    throw "Windows release smoke app exited with code $($primaryProcess.ExitCode)."
  }

  $finalPaperTypeCounts = Get-PaperTypeCounts -StateFile $smokeStateFile
  $paperCount = [int]$finalPaperTypeCounts.total
  if ([int]$finalPaperTypeCounts.note -le [int]$initialPaperTypeCounts.note) {
    throw "Windows release smoke --new-note did not increase the persisted note paper count."
  }
  if ([int]$finalPaperTypeCounts.todo -le [int]$initialPaperTypeCounts.todo) {
    throw "Windows release smoke --new-todo did not increase the persisted todo paper count."
  }
  if (-not [string]::IsNullOrWhiteSpace($ResultJson)) {
    $resultDirectory = Split-Path -Parent $resultJsonFullPath
    if (-not [string]::IsNullOrWhiteSpace($resultDirectory)) {
      New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
    }
    [ordered]@{
      status = "passed"
      checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
      releaseDirectory = $releaseDirectoryFullPath
      exeFileName = "repapertodo.exe"
      initialPaperCount = $initialPaperCount
      finalPaperCount = $paperCount
      initialTodoPaperCount = [int]$initialPaperTypeCounts.todo
      finalTodoPaperCount = [int]$finalPaperTypeCounts.todo
      initialNotePaperCount = [int]$initialPaperTypeCounts.note
      finalNotePaperCount = [int]$finalPaperTypeCounts.note
      initialVisibleTopLevelWindowCount = $initialVisibleWindowCount
      finalVisibleTopLevelWindowCount = $finalVisibleWindowCount
      independentPaperSurfaces = $true
      settingsCoordinatorLifecycle = $true
      settingsStartupCommands = $settingsStartupCommands
      visiblePaperCountBeforeSettings = $visiblePaperCountBeforeSettings
      visibleTopLevelWindowCountWhileSettingsOpen =
        $visibleTopLevelWindowCountWhileSettingsOpen
      visibleTopLevelWindowCountAfterSettingsClose =
        $visibleTopLevelWindowCountAfterSettingsClose
      hiddenStartupCommands = $hiddenStartupCommands
      ignoredSecondaryStartupCommands = $ignoredSecondaryStartupCommands
      visiblePaperCountAfterIgnoredCommand = $visiblePaperCountAfterIgnoredCommand
      secondaryStartupCommands = $secondaryStartupCommands
      startupTimeoutSeconds = $StartupTimeoutSeconds
      exitTimeoutSeconds = $ExitTimeoutSeconds
    } |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath $resultJsonFullPath -Encoding ascii
  }
  Write-Host "Windows release smoke passed with $paperCount persisted papers and $finalVisibleWindowCount independent visible HWNDs."
} catch {
  $smokeFailure = $_
  throw
} finally {
  if ($null -ne $primaryProcess -and -not $primaryProcess.HasExited) {
    Stop-Process -Id $primaryProcess.Id -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $primaryProcess.Id -Timeout 5 -ErrorAction SilentlyContinue
  }
  try {
    Remove-SmokeRoot -SmokeRoot $smokeRoot -TempRoot $tempRoot
  } catch {
    if ($null -eq $smokeFailure) {
      throw
    }
    Write-Warning "Unable to remove Windows smoke temp directory '$smokeRoot': $($_.Exception.Message)"
  }
}
