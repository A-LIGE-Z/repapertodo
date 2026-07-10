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

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$smokeRoot = Join-Path $tempRoot "repapertodo-windows-smoke-$([Guid]::NewGuid().ToString("N"))"
$smokeReleaseDirectory = Join-Path $smokeRoot "Release"
$smokeExe = Join-Path $smokeReleaseDirectory "repapertodo.exe"
$smokeStateFile = Join-Path $smokeReleaseDirectory "data.json"
$primaryProcess = $null
$smokeFailure = $null
$secondaryStartupCommands = @("--new-note", "--new-todo", "--exit")
$initialPaperCount = 0
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

  Invoke-SecondaryStartupCommand `
    -Executable $smokeExe `
    -WorkingDirectory $smokeReleaseDirectory `
    -Command $secondaryStartupCommands[0]
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
    $resultPath = [IO.Path]::GetFullPath($ResultJson)
    $resultDirectory = Split-Path -Parent $resultPath
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
      secondaryStartupCommands = $secondaryStartupCommands
      startupTimeoutSeconds = $StartupTimeoutSeconds
      exitTimeoutSeconds = $ExitTimeoutSeconds
    } |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath $resultPath -Encoding ascii
  }
  Write-Host "Windows release smoke passed with $paperCount persisted papers."
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
