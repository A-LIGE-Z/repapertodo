param(
  [string]$ReleaseDirectory = "",
  [string]$OutputZip = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
  $ReleaseDirectory = Join-Path $repoRoot "build\windows\x64\runner\Release"
}
if ([string]::IsNullOrWhiteSpace($OutputZip)) {
  $OutputZip = Join-Path $repoRoot "build\windows\x64\runner\repapertodo-windows-x64.zip"
}
$releaseFull = [IO.Path]::GetFullPath($ReleaseDirectory)
$outputFull = [IO.Path]::GetFullPath($OutputZip)
$appExe = Join-Path $releaseFull "repapertodo.exe"
$launcherExe = Join-Path $releaseFull "repapertodo_launcher.exe"
foreach ($required in @(
  $appExe,
  $launcherExe,
  (Join-Path $releaseFull "flutter_windows.dll"),
  (Join-Path $releaseFull "msvcp140.dll"),
  (Join-Path $releaseFull "vcruntime140.dll"),
  (Join-Path $releaseFull "vcruntime140_1.dll"),
  (Join-Path $releaseFull "ucrtbase.dll"),
  (Join-Path $releaseFull "data\app.so"),
  (Join-Path $releaseFull "data\icudtl.dat")
)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Windows package dependency was not found: $required"
  }
}

$workRoot = Join-Path $repoRoot ".tmp\windows-layered-package-$([Guid]::NewGuid().ToString('N'))"
$runtimeRoot = Join-Path $workRoot "runtime"
$runtimeStateNames = @(
  "data.json",
  "data.backup.json",
  "data.crash_recovery.json",
  "data.json.tmp",
  "RePaperTodo.crash.log",
  "fullscreen-debug.log"
)
try {
  New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
  Copy-Item -LiteralPath $launcherExe `
    -Destination (Join-Path $workRoot "repapertodo.exe") -Force
  Get-ChildItem -LiteralPath $releaseFull -Force | Where-Object {
    $_.Name -ne "repapertodo_launcher.exe" -and
    $_.Name -ne "LOG" -and
    $_.Name -notin $runtimeStateNames -and
    $_.Name -notlike "*.tmp" -and
    $_.Name -notlike "*.failed_load.*" -and
    $_.Name -notlike "*.used_for_recovery.*"
  } | Copy-Item -Destination $runtimeRoot -Recurse -Force
  Move-Item -LiteralPath (Join-Path $runtimeRoot "repapertodo.exe") `
    -Destination (Join-Path $runtimeRoot "repapertodo.runtime.exe") -Force

  $outputDirectory = Split-Path -Parent $outputFull
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
  if (Test-Path -LiteralPath $outputFull) {
    Remove-Item -LiteralPath $outputFull -Force
  }
  Compress-Archive -Path (Join-Path $workRoot "*") `
    -DestinationPath $outputFull -CompressionLevel Optimal

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($outputFull)
  try {
    $entries = @($archive.Entries | ForEach-Object {
      $_.FullName.Replace("\", "/")
    })
    $rootFiles = @($entries | Where-Object { -not $_.Contains("/") })
    if ($rootFiles.Count -ne 1 -or $rootFiles[0] -ne "repapertodo.exe") {
      throw "Windows ZIP root must contain only repapertodo.exe."
    }
    foreach ($requiredEntry in @(
      "runtime/repapertodo.runtime.exe",
      "runtime/flutter_windows.dll",
      "runtime/msvcp140.dll",
      "runtime/vcruntime140.dll",
      "runtime/vcruntime140_1.dll",
      "runtime/ucrtbase.dll",
      "runtime/data/app.so",
      "runtime/data/icudtl.dat"
    )) {
      if ($requiredEntry -notin $entries) {
        throw "Windows ZIP is missing $requiredEntry."
      }
    }
  } finally {
    $archive.Dispose()
  }
  Get-Item -LiteralPath $outputFull
} finally {
  if (Test-Path -LiteralPath $workRoot) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
