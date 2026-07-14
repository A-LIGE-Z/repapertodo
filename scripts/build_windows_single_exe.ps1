param(
  [string]$ReleaseDirectory = "",
  [string]$OutputExe = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
  $ReleaseDirectory = Join-Path $repoRoot "build\windows\x64\runner\Release"
}
$releaseFull = [IO.Path]::GetFullPath($ReleaseDirectory)
$sourceExe = Join-Path $releaseFull "repapertodo.exe"
if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) {
  throw "Windows release executable was not found: $sourceExe"
}
if ([string]::IsNullOrWhiteSpace($OutputExe)) {
  $OutputExe = Join-Path (Split-Path -Parent $releaseFull) "repapertodo-single.exe"
}
$outputFull = [IO.Path]::GetFullPath($OutputExe)
$repoFull = [IO.Path]::GetFullPath($repoRoot)
$repoPrefix = $repoFull.TrimEnd([IO.Path]::DirectorySeparatorChar) +
  [IO.Path]::DirectorySeparatorChar
if (-not $outputFull.StartsWith(
    $repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Single executable output must stay inside the repository."
}
$tempRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot ".tmp"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$workRoot = Join-Path $tempRoot "windows-single-exe-$([Guid]::NewGuid().ToString('N'))"
$payloadZip = Join-Path $workRoot "payload.zip"
$launcher = Join-Path $workRoot "launch.cmd"
$sedPath = Join-Path $workRoot "package.sed"
$packageSucceeded = $false

try {
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  $payloadFiles = Get-ChildItem -LiteralPath $releaseFull -Force |
    Where-Object {
      $_.FullName -ne $outputFull -and
      $_.Name -notin @('data.json', 'data.backup.json', 'data.json.tmp')
    }
  Compress-Archive -Path $payloadFiles.FullName -DestinationPath $payloadZip `
    -CompressionLevel Optimal -Force
  $runtimeId = (Get-FileHash -LiteralPath $payloadZip -Algorithm SHA256).Hash
  $runtimeId = $runtimeId.Substring(0, 16).ToLowerInvariant()
  @"
@echo off
setlocal
set "RUNTIME_DIR=%LOCALAPPDATA%\RePaperTodo\Runtime\$runtimeId"
if not exist "%RUNTIME_DIR%\repapertodo.exe" (
  if not exist "%RUNTIME_DIR%" mkdir "%RUNTIME_DIR%"
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%~dp0payload.zip' -DestinationPath '%RUNTIME_DIR%' -Force"
  if errorlevel 1 exit /b 1
)
start "" "%RUNTIME_DIR%\repapertodo.exe" %*
"@ | Set-Content -LiteralPath $launcher -Encoding ascii

  $escapedWorkRoot = $workRoot.TrimEnd('\') + '\'
  @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$outputFull
FriendlyName=RePaperTodo single executable
AppLaunched=launch.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[SourceFiles]
SourceFiles0=$escapedWorkRoot
[SourceFiles0]
%FILE0%=
%FILE1%=
[Strings]
FILE0="launch.cmd"
FILE1="payload.zip"
"@ | Set-Content -LiteralPath $sedPath -Encoding ascii

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFull) |
    Out-Null
  if (Test-Path -LiteralPath $outputFull) {
    Remove-Item -LiteralPath $outputFull -Force
  }
  Start-Process -FilePath "$env:SystemRoot\System32\iexpress.exe" `
    -ArgumentList @('/N', '/Q', $sedPath) -WindowStyle Hidden -Wait | Out-Null
  if (-not (Test-Path -LiteralPath $outputFull -PathType Leaf)) {
    throw "IExpress failed to create the single executable. Inspect $workRoot"
  }
  $packageSucceeded = $true
  Get-Item -LiteralPath $outputFull
} finally {
  if ($packageSucceeded -and (Test-Path -LiteralPath $workRoot)) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
