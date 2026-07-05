param(
  [switch]$SkipTests,
  [switch]$SkipBuild,
  [switch]$OfflinePubGet,
  [switch]$PublishGitHubRelease,
  [string]$TagName = "",
  [string]$ReleaseTitle = ""
)

$ErrorActionPreference = "Stop"

function Invoke-Step {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  Write-Host ""
  Write-Host "==> $Name"
  & $Action
}

function Assert-Command {
  param([string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found."
  }
}

function Get-FlutterVersion {
  $pubspec = Get-Content -LiteralPath "pubspec.yaml"
  $versionLine = $pubspec | Where-Object { $_ -match "^version:\s*(.+)$" } | Select-Object -First 1
  if (-not $versionLine) {
    throw "pubspec.yaml does not contain a version line."
  }
  return ($versionLine -replace "^version:\s*", "").Trim()
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

# Some local shells may carry malformed proxy values. Release commands should
# prefer direct network access unless the caller deliberately sets a proxy here.
$env:HTTP_PROXY = ""
$env:HTTPS_PROXY = ""
$env:ALL_PROXY = ""

$flutter = "C:\Users\28415\.puro\envs\stable\flutter\bin\flutter.bat"
if (-not (Test-Path -LiteralPath $flutter)) {
  $flutter = "flutter"
}

Assert-Command "git"
if ($PublishGitHubRelease) {
  Assert-Command "gh"
}

$version = Get-FlutterVersion
$artifactVersion = $version -replace "\+", "-"
if ([string]::IsNullOrWhiteSpace($TagName)) {
  $TagName = "v$version"
}
if ([string]::IsNullOrWhiteSpace($ReleaseTitle)) {
  $ReleaseTitle = "RePaperTodo $version"
}

if (-not $SkipTests -or -not $SkipBuild) {
  Invoke-Step "Resolve Flutter packages" {
    if ($OfflinePubGet) {
      & $flutter pub get --offline
    } else {
      & $flutter pub get
    }
  }
}

if (-not $SkipTests) {
  Invoke-Step "Run Flutter tests" {
    & $flutter test --no-pub
  }
  Invoke-Step "Run Flutter analyze" {
    & $flutter analyze --no-pub
  }
}

if (-not $SkipBuild) {
  Invoke-Step "Build Windows release" {
    & $flutter build windows --release --no-pub
  }
  Invoke-Step "Build Android release APK" {
    & $flutter build apk --release --no-pub
  }
}

$dist = Join-Path $repoRoot "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$windowsZip = Join-Path $dist "repapertodo-windows-x64-$artifactVersion.zip"
$androidApk = Join-Path $dist "repapertodo-android-$artifactVersion.apk"
$checksumsFile = Join-Path $dist "repapertodo-$artifactVersion-sha256.txt"

Invoke-Step "Package release artifacts" {
  if (Test-Path -LiteralPath $windowsZip) {
    Remove-Item -LiteralPath $windowsZip -Force
  }
  if (Test-Path -LiteralPath $androidApk) {
    Remove-Item -LiteralPath $androidApk -Force
  }
  if (Test-Path -LiteralPath $checksumsFile) {
    Remove-Item -LiteralPath $checksumsFile -Force
  }
  Compress-Archive `
    -Path "build\windows\x64\runner\Release\*" `
    -DestinationPath $windowsZip `
    -CompressionLevel Optimal
  Copy-Item `
    -LiteralPath "build\app\outputs\flutter-apk\app-release.apk" `
    -Destination $androidApk

  @($windowsZip, $androidApk) |
    ForEach-Object {
      $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $_
      "$($hash.Hash.ToLowerInvariant())  $(Split-Path -Leaf $_)"
    } |
    Set-Content -LiteralPath $checksumsFile -Encoding ascii
}

Get-Item -LiteralPath $windowsZip, $androidApk, $checksumsFile |
  Select-Object FullName, Length, LastWriteTime |
  Format-Table -AutoSize

if ($PublishGitHubRelease) {
  Invoke-Step "Publish GitHub release $TagName" {
    $existingRelease = & gh release view $TagName --json tagName 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingRelease)) {
      & gh release upload $TagName $windowsZip $androidApk $checksumsFile --clobber
    } else {
      & gh release create $TagName $windowsZip $androidApk $checksumsFile `
        --target main `
        --title $ReleaseTitle `
        --notes "Release build for RePaperTodo $version.`n`nArtifacts:`n- Windows x64 release zip containing repapertodo.exe and runtime files.`n- Android release APK for Android 14+ target SDK 37.`n- SHA-256 checksums for release artifacts.`n`nValidation:`n- flutter test`n- flutter analyze`n- flutter build windows --release`n- flutter build apk --release"
    }
  }
}
