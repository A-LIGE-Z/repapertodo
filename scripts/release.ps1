param(
  [switch]$SkipTests,
  [switch]$SkipBuild,
  [switch]$OfflinePubGet,
  [switch]$PublishGitHubRelease,
  [switch]$AllowDirty,
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

function Clear-ProxyEnvironment {
  foreach ($name in @(
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "http_proxy",
    "https_proxy",
    "all_proxy"
  )) {
    Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
  }
}

function Invoke-Native {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
}

function Invoke-NativeText {
  param(
    [string]$Name,
    [scriptblock]$Action
  )

  $output = & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
  return (($output -join "`n").Trim())
}

function Get-FlutterVersion {
  $pubspec = Get-Content -LiteralPath "pubspec.yaml"
  $versionLine = $pubspec | Where-Object { $_ -match "^version:\s*(.+)$" } | Select-Object -First 1
  if (-not $versionLine) {
    throw "pubspec.yaml does not contain a version line."
  }
  return ($versionLine -replace "^version:\s*", "").Trim()
}

function Get-AndroidSigningMode {
  param([string]$RepoRoot)

  $keyProperties = Join-Path $RepoRoot "android\key.properties"
  if (-not (Test-Path -LiteralPath $keyProperties)) {
    return "debug fallback (android/key.properties not found)"
  }

  $requiredKeys = @("storeFile", "storePassword", "keyAlias", "keyPassword")
  $content = Get-Content -LiteralPath $keyProperties
  foreach ($key in $requiredKeys) {
    $match = $content | Where-Object { $_ -match "^\s*$([regex]::Escape($key))\s*=\s*\S+" } | Select-Object -First 1
    if (-not $match) {
      return "debug fallback (android/key.properties is incomplete)"
    }
  }

  return "release keystore from android/key.properties"
}

function Assert-CleanGitTree {
  if ($AllowDirty) {
    Write-Host "Working tree clean check skipped because -AllowDirty was provided."
    return
  }

  # Flutter's Windows build can rewrite generated plugin files without changing
  # their normalized content. Refresh the index, then check real content/staged
  # diffs plus untracked files instead of blocking on stat-only status noise.
  & git update-index --refresh 2>$null
  if ($LASTEXITCODE -gt 1) {
    throw "git update-index --refresh failed with exit code $LASTEXITCODE."
  }

  & git diff --quiet --
  $workingTreeDiffExitCode = $LASTEXITCODE
  if ($workingTreeDiffExitCode -gt 1) {
    throw "git diff --quiet failed with exit code $workingTreeDiffExitCode."
  }

  & git diff --cached --quiet --
  $stagedDiffExitCode = $LASTEXITCODE
  if ($stagedDiffExitCode -gt 1) {
    throw "git diff --cached --quiet failed with exit code $stagedDiffExitCode."
  }

  $untrackedFiles = & git ls-files --others --exclude-standard
  if ($LASTEXITCODE -ne 0) {
    throw "git ls-files --others --exclude-standard failed with exit code $LASTEXITCODE."
  }

  if ($workingTreeDiffExitCode -ne 0 -or
      $stagedDiffExitCode -ne 0 -or
      $untrackedFiles) {
    Write-Host "Dirty git status:"
    $status = & git status --porcelain --untracked-files=all
    if ($LASTEXITCODE -ne 0) {
      throw "git status --porcelain --untracked-files=all failed with exit code $LASTEXITCODE."
    }
    $status | ForEach-Object { Write-Host "  $_" }
    throw "Working tree has uncommitted changes. Commit or stash them before release, or rerun with -AllowDirty for a local-only test package."
  }
}

function Assert-GitDiffCheck {
  Invoke-Step "Check git diff whitespace" {
    Invoke-Native "git diff --check" {
      & git diff --check
    }
    Invoke-Native "git diff --cached --check" {
      & git diff --cached --check
    }
  }
}

function Assert-PathExists {
  param(
    [string]$Path,
    [string]$Message
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw $Message
  }
}

function Get-GradleIntegerAssignment {
  param(
    [string]$Content,
    [string]$Name,
    [string]$SourcePath
  )

  $pattern = "(?m)^\s*$([regex]::Escape($Name))\s*=\s*(\d+)\s*$"
  $match = [regex]::Match($Content, $pattern)
  if (-not $match.Success) {
    throw "$SourcePath does not declare $Name as an integer assignment."
  }
  return [int]$match.Groups[1].Value
}

function Get-AndroidSdkConfig {
  param([string]$RepoRoot)

  $gradleFile = Join-Path $RepoRoot "android\app\build.gradle.kts"
  Assert-PathExists `
    -Path $gradleFile `
    -Message "Android Gradle build file was not found."
  $content = Get-Content -Raw -LiteralPath $gradleFile
  return [ordered]@{
    compileSdk = Get-GradleIntegerAssignment `
      -Content $content `
      -Name "compileSdk" `
      -SourcePath $gradleFile
    minSdk = Get-GradleIntegerAssignment `
      -Content $content `
      -Name "minSdk" `
      -SourcePath $gradleFile
    targetSdk = Get-GradleIntegerAssignment `
      -Content $content `
      -Name "targetSdk" `
      -SourcePath $gradleFile
    compatibility = "Android 14-17 / API 34-37"
  }
}

function Assert-AndroidSdkCompatibility {
  param($SdkConfig)

  if ($SdkConfig["compileSdk"] -ne 37 -or
      $SdkConfig["minSdk"] -ne 34 -or
      $SdkConfig["targetSdk"] -ne 37) {
    throw "Android SDK compatibility must remain Android 14-17 / API 34-37 (compileSdk 37, minSdk 34, targetSdk 37)."
  }
}

function Assert-PublishableReleaseOptions {
  param(
    [bool]$PublishGitHubRelease,
    [bool]$SkipTests,
    [bool]$SkipBuild,
    [bool]$AllowDirty,
    [string]$AndroidSigningMode
  )

  if (-not $PublishGitHubRelease) {
    return
  }

  $blockedOptions = @()
  if ($SkipTests) {
    $blockedOptions += "-SkipTests"
  }
  if ($SkipBuild) {
    $blockedOptions += "-SkipBuild"
  }
  if ($AllowDirty) {
    $blockedOptions += "-AllowDirty"
  }

  if ($blockedOptions.Count -gt 0) {
    throw "GitHub Release publishing requires a clean, fully validated build. Remove $($blockedOptions -join ', ') before publishing."
  }
  if ($AndroidSigningMode -ne "release keystore from android/key.properties") {
    throw "GitHub Release publishing requires Android release signing from android/key.properties. Configure android/key.properties locally or provide Android signing secrets in GitHub Actions before publishing."
  }
}

function Assert-GitHubAuthentication {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & gh auth status
  $authExitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorActionPreference
  if ($authExitCode -ne 0) {
    throw 'GitHub Release publishing requires an authenticated GitHub CLI session. Run `gh auth refresh -h github.com` or `gh auth login -h github.com`, then rerun the release script.'
  }
}

function Assert-GitHubReleaseGitState {
  Invoke-Native "git fetch origin main" {
    & git fetch origin main
  }

  $branch = Invoke-NativeText "git rev-parse --abbrev-ref HEAD" {
    & git rev-parse --abbrev-ref HEAD
  }
  $isGitHubActionsDetachedMain = (
    $env:GITHUB_ACTIONS -eq "true" -and
    $branch -eq "HEAD" -and
    $env:GITHUB_REF_NAME -eq "main"
  )
  if ($branch -ne "main" -and -not $isGitHubActionsDetachedMain) {
    if ($env:GITHUB_ACTIONS -eq "true" -and $branch -eq "HEAD") {
      throw "GitHub Release publishing from GitHub Actions must run from the main ref."
    }
    throw "GitHub Release publishing must run from the main branch."
  }

  $headCommit = Invoke-NativeText "git rev-parse HEAD" {
    & git rev-parse HEAD
  }
  $originMainCommit = Invoke-NativeText "git rev-parse --verify origin/main" {
    & git rev-parse --verify origin/main
  }
  if ($headCommit -ne $originMainCommit) {
    throw "GitHub Release publishing requires local HEAD to match origin/main. Push or pull main before publishing."
  }
}

function Assert-GitHubReleaseTagState {
  param(
    [string]$TagName,
    [string]$GitCommit
  )

  $tagRef = "refs/tags/$TagName"
  $tagLines = & git ls-remote --tags origin $tagRef "$tagRef^{}"
  if ($LASTEXITCODE -ne 0) {
    throw "git ls-remote --tags origin $TagName failed with exit code $LASTEXITCODE."
  }
  if (-not $tagLines) {
    return
  }

  $tagCommit = ""
  foreach ($line in $tagLines) {
    $parts = $line -split "\s+"
    if ($parts.Count -lt 2) {
      continue
    }
    if ($parts[1] -eq "$tagRef^{}") {
      $tagCommit = $parts[0]
      break
    }
    if ($parts[1] -eq $tagRef) {
      $tagCommit = $parts[0]
    }
  }

  if ([string]::IsNullOrWhiteSpace($tagCommit)) {
    throw "Unable to determine the remote commit for GitHub Release tag '$TagName'."
  }
  if ($tagCommit -ne $GitCommit) {
    throw "GitHub Release tag '$TagName' already points to $tagCommit, but the release artifacts were built from $GitCommit. Bump the version or retarget the tag before publishing."
  }
}

function New-ReleaseNotes {
  param(
    [string]$version,
    [string]$androidSigningMode
  )

  return @"
Release build for RePaperTodo $version.

Artifacts:
- Windows x64 release zip containing repapertodo.exe and runtime files.
- Android release APK targeting Android 14-17 / API 34-37.
- SHA-256 checksums for release artifacts.
- Release metadata JSON with version, commit, Android SDK/signing, validation, and artifact hashes.

Android signing: $androidSigningMode.

Validation:
- git diff --check
- git diff --cached --check
- flutter test --no-pub
- flutter analyze --no-pub
- flutter build windows --release --no-pub
- flutter build apk --release --no-pub
"@
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

# Some local shells may carry malformed proxy values. Release commands should
# prefer direct network access. Remove the variables entirely because Java and
# Android SDK tools parse empty proxy variables as malformed URLs.
Clear-ProxyEnvironment

$flutter = "C:\Users\28415\.puro\envs\stable\flutter\bin\flutter.bat"
if (-not (Test-Path -LiteralPath $flutter)) {
  $flutter = "flutter"
}

Assert-Command "git"
$androidSigningMode = Get-AndroidSigningMode -RepoRoot $repoRoot
$androidSdkConfig = Get-AndroidSdkConfig -RepoRoot $repoRoot
Assert-AndroidSdkCompatibility -SdkConfig $androidSdkConfig
Assert-PublishableReleaseOptions `
  -PublishGitHubRelease $PublishGitHubRelease `
  -SkipTests $SkipTests `
  -SkipBuild $SkipBuild `
  -AllowDirty $AllowDirty `
  -AndroidSigningMode $androidSigningMode
if ($PublishGitHubRelease) {
  Assert-Command "gh"
  Assert-GitHubAuthentication
}

$version = Get-FlutterVersion
$artifactVersion = $version -replace "\+", "-"
if ([string]::IsNullOrWhiteSpace($TagName)) {
  $TagName = "v$version"
}
if ([string]::IsNullOrWhiteSpace($ReleaseTitle)) {
  $ReleaseTitle = "RePaperTodo $version"
}
$releaseNotes = New-ReleaseNotes -Version $version -AndroidSigningMode $androidSigningMode
Write-Host "Android signing mode: $androidSigningMode"
Write-Host "Android SDK config: compileSdk=$($androidSdkConfig["compileSdk"]), minSdk=$($androidSdkConfig["minSdk"]), targetSdk=$($androidSdkConfig["targetSdk"])"

$gitCommit = ""
Invoke-Native "git rev-parse HEAD" {
  $script:gitCommit = (& git rev-parse HEAD).Trim()
}
Assert-CleanGitTree
Assert-GitDiffCheck
if ($PublishGitHubRelease) {
  Assert-GitHubReleaseGitState
  Assert-GitHubReleaseTagState -TagName $TagName -GitCommit $gitCommit
}

$validationExecuted = @(
  "git diff --check",
  "git diff --cached --check"
)
$validationSkipped = @()

if (-not $SkipTests -or -not $SkipBuild) {
  Invoke-Step "Resolve Flutter packages" {
    if ($OfflinePubGet) {
      Invoke-Native "flutter pub get --offline" {
        & $flutter pub get --offline
      }
    } else {
      Invoke-Native "flutter pub get" {
        & $flutter pub get
      }
    }
  }
}

if (-not $SkipTests) {
  $validationExecuted += "flutter test --no-pub"
  $validationExecuted += "flutter analyze --no-pub"
  Invoke-Step "Run Flutter tests" {
    Invoke-Native "flutter test" {
      & $flutter test --no-pub
    }
  }
  Invoke-Step "Run Flutter analyze" {
    Invoke-Native "flutter analyze" {
      & $flutter analyze --no-pub
    }
  }
} else {
  $validationSkipped += "flutter test --no-pub"
  $validationSkipped += "flutter analyze --no-pub"
}

if (-not $SkipBuild) {
  $validationExecuted += "flutter build windows --release --no-pub"
  $validationExecuted += "flutter build apk --release --no-pub"
  Invoke-Step "Build Windows release" {
    Invoke-Native "flutter build windows" {
      & $flutter build windows --release --no-pub
    }
  }
  Invoke-Step "Build Android release APK" {
    Invoke-Native "flutter build apk" {
      & $flutter build apk --release --no-pub
    }
  }
} else {
  $validationSkipped += "flutter build windows --release --no-pub"
  $validationSkipped += "flutter build apk --release --no-pub"
}

Invoke-Step "Verify release inputs stayed clean" {
  Assert-CleanGitTree
}

$dist = Join-Path $repoRoot "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$windowsReleaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$androidReleaseApkSource = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"
$windowsZip = Join-Path $dist "repapertodo-windows-x64-$artifactVersion.zip"
$androidApk = Join-Path $dist "repapertodo-android-$artifactVersion.apk"
$checksumsFile = Join-Path $dist "repapertodo-$artifactVersion-sha256.txt"
$metadataFile = Join-Path $dist "repapertodo-$artifactVersion-release.json"

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
  if (Test-Path -LiteralPath $metadataFile) {
    Remove-Item -LiteralPath $metadataFile -Force
  }
  Assert-PathExists `
    -Path $windowsReleaseDir `
    -Message "Windows release build output was not found. Run without -SkipBuild to create it."
  Assert-PathExists `
    -Path $androidReleaseApkSource `
    -Message "Android release APK was not found. Run without -SkipBuild to create it."
  Compress-Archive `
    -Path (Join-Path $windowsReleaseDir "*") `
    -DestinationPath $windowsZip `
    -CompressionLevel Optimal
  Copy-Item `
    -LiteralPath $androidReleaseApkSource `
    -Destination $androidApk

  $artifactRecords = @($windowsZip, $androidApk) |
    ForEach-Object {
      $item = Get-Item -LiteralPath $_
      $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $_
      [ordered]@{
        fileName = $item.Name
        bytes = $item.Length
        sha256 = $hash.Hash.ToLowerInvariant()
      }
    }

  $artifactRecords |
    ForEach-Object { "$($_.sha256)  $($_.fileName)" } |
    Set-Content -LiteralPath $checksumsFile -Encoding ascii

  [ordered]@{
    version = $version
    tagName = $TagName
    gitCommit = $gitCommit
    builtAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    android = [ordered]@{
      compileSdk = $androidSdkConfig["compileSdk"]
      minSdk = $androidSdkConfig["minSdk"]
      targetSdk = $androidSdkConfig["targetSdk"]
      compatibility = $androidSdkConfig["compatibility"]
      signing = $androidSigningMode
    }
    validation = $validationExecuted
    skippedValidation = $validationSkipped
    artifacts = $artifactRecords
  } |
    ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $metadataFile -Encoding ascii
}

Get-Item -LiteralPath $windowsZip, $androidApk, $checksumsFile, $metadataFile |
  Select-Object FullName, Length, LastWriteTime |
  Format-Table -AutoSize

if ($PublishGitHubRelease) {
  Invoke-Step "Publish GitHub release $TagName" {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $existingRelease = & gh release view $TagName --json tagName 2>$null
    $releaseViewExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($releaseViewExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingRelease)) {
      Invoke-Native "gh release edit $TagName" {
        & gh release edit $TagName `
          --title $ReleaseTitle `
          --notes $releaseNotes
      }
      Invoke-Native "gh release upload $TagName" {
        & gh release upload $TagName $windowsZip $androidApk $checksumsFile $metadataFile --clobber
      }
    } else {
      Invoke-Native "gh release create $TagName" {
        & gh release create $TagName $windowsZip $androidApk $checksumsFile $metadataFile `
          --target $gitCommit `
          --title $ReleaseTitle `
          --notes $releaseNotes
      }
    }
  }
}
