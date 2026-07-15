param(
  [switch]$SkipTests,
  [switch]$SkipBuild,
  [switch]$OfflinePubGet,
  [switch]$PublishGitHubRelease,
  [switch]$AllowDirty,
  [switch]$RunAndroidDeviceSmoke,
  [string]$AndroidDeviceSerial = "",
  [string]$AndroidDeviceSmokeResultJson = "",
  [string]$WindowsManualQaResultJson = "",
  [string]$WebDavLiveSmokeResultJson = "",
  [string]$WebDavDomesticLiveSmokeResultJson = "",
  [string]$TagName = "",
  [string]$ReleaseTitle = ""
)

$ErrorActionPreference = "Stop"
$supportedRuntimeLanguages = @("zh", "en")

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

function Assert-FlutterVersion {
  param([string]$Version)

  if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "pubspec.yaml version must not be blank."
  }

  $semverPattern = "^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$"
  if ($Version -notmatch $semverPattern) {
    throw "pubspec.yaml version '$Version' must be a SemVer value safe for release metadata, tags, and artifact names."
  }
}

function Get-ReleaseArtifactVersion {
  param([string]$Version)

  Assert-FlutterVersion -Version $Version
  $artifactVersion = $Version -replace "\+", "-"
  if ($artifactVersion -notmatch "^[0-9A-Za-z][0-9A-Za-z.-]*$" -or
      $artifactVersion.Contains("..") -or
      $artifactVersion.EndsWith(".")) {
    throw "Release artifact version '$artifactVersion' is not safe for artifact file names."
  }
  return $artifactVersion
}

function Assert-ReleaseTagName {
  param([string]$TagName)

  if ([string]::IsNullOrWhiteSpace($TagName)) {
    throw "GitHub Release tag must not be blank."
  }
  if ($TagName.StartsWith("-")) {
    throw "GitHub Release tag must not start with '-'."
  }
  if ($TagName -match "[\x00-\x20\x7F-\x9F]") {
    throw "GitHub Release tag must not contain whitespace or control characters."
  }

  Invoke-Native "git check-ref-format refs/tags/$TagName" {
    & git check-ref-format "refs/tags/$TagName"
  }
}

function Assert-ReleaseTitle {
  param([string]$ReleaseTitle)

  if ([string]::IsNullOrWhiteSpace($ReleaseTitle)) {
    throw "GitHub Release title must not be blank."
  }
  $trimmedReleaseTitle = $ReleaseTitle.Trim()
  if ($ReleaseTitle -cne $trimmedReleaseTitle) {
    throw "GitHub Release title must not contain leading or trailing whitespace."
  }
  if ($ReleaseTitle -match "[\x00-\x1F\x7F-\x9F]") {
    throw "GitHub Release title must not contain control characters."
  }
}

function Assert-PublishTagMatchesVersion {
  param(
    [bool]$PublishGitHubRelease,
    [string]$TagName,
    [string]$Version
  )

  if (-not $PublishGitHubRelease) {
    return
  }

  $expectedTagName = "v$Version"
  if ($TagName -cne $expectedTagName) {
    throw "GitHub Release tag must match pubspec.yaml version as '$expectedTagName'."
  }
}

function Get-FlutterToolchainInfo {
  param([string]$Flutter)

  $json = Invoke-NativeText "flutter --version --machine" {
    & $Flutter --version --machine
  }
  try {
    $raw = $json | ConvertFrom-Json
  } catch {
    throw "Unable to parse Flutter toolchain metadata from 'flutter --version --machine': $($_.Exception.Message)"
  }

  foreach ($property in @(
    "frameworkVersion",
    "channel",
    "frameworkRevision",
    "engineRevision",
    "dartSdkVersion"
  )) {
    if ([string]::IsNullOrWhiteSpace([string]$raw.$property)) {
      throw "Flutter toolchain metadata is missing '$property'."
    }
  }

  return [ordered]@{
    flutterFrameworkVersion = [string]$raw.frameworkVersion
    flutterChannel = [string]$raw.channel
    flutterFrameworkRevision = [string]$raw.frameworkRevision
    flutterEngineRevision = [string]$raw.engineRevision
    dartSdkVersion = [string]$raw.dartSdkVersion
  }
}

function Get-RuntimeSupportedLanguages {
  param([string]$RepoRoot)

  $stringsFile = Join-Path $RepoRoot "lib\src\ui\papertodo_strings.dart"
  Assert-PathExists `
    -Path $stringsFile `
    -Message "Runtime localization file was not found."
  $content = Get-Content -Raw -LiteralPath $stringsFile
  $match = [regex]::Match(
    $content,
    "static\s+const\s+supportedLocales\s*=\s*\[(?<body>.*?)\];",
    [Text.RegularExpressions.RegexOptions]::Singleline
  )
  if (-not $match.Success) {
    throw "Runtime localization file does not declare PaperTodoStrings.supportedLocales."
  }

  $localeMatches = [regex]::Matches(
    $match.Groups["body"].Value,
    "Locale\(\s*'(?<language>[a-z]{2})'\s*\)"
  )
  $languages = @($localeMatches | ForEach-Object {
      $_.Groups["language"].Value
    })
  if ($languages.Count -eq 0) {
    throw "Runtime localization file does not list any supported locales."
  }
  return [string[]]$languages
}

function Assert-RuntimeSupportedLanguages {
  param(
    [string[]]$Actual,
    [string[]]$Expected
  )

  if ($Actual.Count -ne $Expected.Count) {
    throw "Runtime supported languages must match release metadata languages: expected $($Expected -join ', '), found $($Actual -join ', ')."
  }
  for ($index = 0; $index -lt $Expected.Count; $index++) {
    if ($Actual[$index] -ne $Expected[$index]) {
      throw "Runtime supported languages must match release metadata languages: expected $($Expected -join ', '), found $($Actual -join ', ')."
    }
  }
}

function Get-AndroidKeyProperty {
  param(
    [string[]]$Content,
    [string]$Key
  )

  foreach ($line in $Content) {
    $match = [regex]::Match(
      $line,
      "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$"
    )
    if ($match.Success) {
      return $match.Groups[1].Value.Trim()
    }
  }
  return ""
}

function Assert-AndroidKeyPropertyValue {
  param(
    [string]$Key,
    [string]$Value
  )

  if ($Value -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Android signing property '$Key' must not contain control characters."
  }
}

function Assert-AndroidStoreFileValue {
  param([string]$StoreFile)

  Assert-AndroidKeyPropertyValue -Key "storeFile" -Value $StoreFile
  if ([IO.Path]::IsPathRooted($StoreFile)) {
    throw "Android signing storeFile must be relative to the Android project."
  }
  if ($StoreFile -match "[*?]") {
    throw "Android signing storeFile must not contain wildcard characters."
  }

  $segments = $StoreFile -split "[\\/]+"
  foreach ($segment in $segments) {
    if ($segment -eq "." -or $segment -eq "..") {
      throw "Android signing storeFile must not contain dot-segments."
    }
  }
}

function Resolve-AndroidKeystorePath {
  param(
    [string]$RepoRoot,
    [string]$StoreFile
  )

  Assert-AndroidStoreFileValue -StoreFile $StoreFile
  try {
    return [IO.Path]::GetFullPath(
      (Join-Path (Join-Path $RepoRoot "android") $StoreFile)
    )
  } catch {
    throw "Android signing storeFile path is invalid: $($_.Exception.Message)"
  }
}

function Get-AndroidSigningMode {
  param([string]$RepoRoot)

  $keyProperties = Join-Path $RepoRoot "android\key.properties"
  if (-not (Test-Path -LiteralPath $keyProperties)) {
    return "debug fallback (android/key.properties not found)"
  }

  $requiredKeys = @("storeFile", "storePassword", "keyAlias", "keyPassword")
  $content = Get-Content -LiteralPath $keyProperties
  $values = @{}
  foreach ($key in $requiredKeys) {
    $values[$key] = Get-AndroidKeyProperty -Content $content -Key $key
    if ([string]::IsNullOrWhiteSpace($values[$key])) {
      return "debug fallback (android/key.properties is incomplete)"
    }
    Assert-AndroidKeyPropertyValue -Key $key -Value $values[$key]
  }

  $keystorePath = Resolve-AndroidKeystorePath `
    -RepoRoot $RepoRoot `
    -StoreFile $values["storeFile"]
  if (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
    return "debug fallback (android/key.properties storeFile not found)"
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

function Assert-FileExists {
  param(
    [string]$Path,
    [string]$Message
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw $Message
  }
}

function Assert-FileExtension {
  param(
    [string]$Path,
    [string]$ExpectedExtension,
    [string]$Message
  )

  $extension = [IO.Path]::GetExtension($Path)
  if ($extension -ine $ExpectedExtension) {
    throw $Message
  }
}

function Find-AndroidSdkTool {
  param([string]$ToolName)

  $command = Get-Command $ToolName -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $sdkRoots = @(
    $env:ANDROID_HOME,
    $env:ANDROID_SDK_ROOT
  ) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Unique

  foreach ($sdkRoot in $sdkRoots) {
    if (-not (Test-Path -LiteralPath $sdkRoot)) {
      continue
    }
    $tool = Get-ChildItem `
      -LiteralPath $sdkRoot `
      -Recurse `
      -Filter $ToolName `
      -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($tool) {
      return $tool.FullName
    }
  }

  throw "Android SDK tool '$ToolName' was not found. Install Android command-line tools so the APK manifest can be verified."
}

function Get-ApkManifestInteger {
  param(
    [string]$ApkAnalyzer,
    [string]$ApkPath,
    [string]$Field
  )

  $value = Invoke-NativeText "apkanalyzer manifest $Field" {
    & $ApkAnalyzer manifest $Field $ApkPath
  }
  if ($value -notmatch "^\d+$") {
    throw "Android release APK manifest $Field value '$value' is not an integer."
  }
  return [int]$value
}

function Assert-AndroidApkSdkCompatibility {
  param(
    [string]$ApkPath,
    [object]$SdkConfig,
    [string]$ApkAnalyzer
  )

  $manifestMinSdk = Get-ApkManifestInteger `
    -ApkAnalyzer $ApkAnalyzer `
    -ApkPath $ApkPath `
    -Field "min-sdk"
  $manifestTargetSdk = Get-ApkManifestInteger `
    -ApkAnalyzer $ApkAnalyzer `
    -ApkPath $ApkPath `
    -Field "target-sdk"

  if ($manifestMinSdk -ne [int]$SdkConfig["minSdk"] -or
      $manifestTargetSdk -ne [int]$SdkConfig["targetSdk"]) {
    throw "Android release APK manifest must match Android 14-17 / API 34-37 (minSdk $($SdkConfig["minSdk"]), targetSdk $($SdkConfig["targetSdk"])); found minSdk $manifestMinSdk, targetSdk $manifestTargetSdk."
  }
}

function Assert-ZipContainsFile {
  param(
    [string]$ZipPath,
    [string]$FileName,
    [string]$Message
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    foreach ($entry in $archive.Entries) {
      $entryName = $entry.FullName -replace "\\", "/"
      if (($entryName -eq $FileName -or $entryName.EndsWith("/$FileName")) -and
          $entry.Length -gt 0) {
        return
      }
    }
  } finally {
    $archive.Dispose()
  }

  throw $Message
}

function Assert-ZipContainsExactFile {
  param(
    [string]$ZipPath,
    [string]$FileName,
    [string]$Message
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    foreach ($entry in $archive.Entries) {
      $entryName = $entry.FullName -replace "\\", "/"
      if ($entryName -eq $FileName -and $entry.Length -gt 0) {
        return
      }
    }
  } finally {
    $archive.Dispose()
  }

  throw $Message
}

function Assert-WindowsZipRootLayout {
  param([string]$ZipPath)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $rootFiles = @($archive.Entries | Where-Object {
      $entryName = $_.FullName -replace "\\", "/"
      -not $entryName.Contains("/") -and $_.Length -gt 0
    })
    if ($rootFiles.Count -ne 1 -or
        ($rootFiles[0].FullName -replace "\\", "/") -ne "repapertodo.exe") {
      throw "Windows release zip root must contain only repapertodo.exe."
    }
  } finally {
    $archive.Dispose()
  }
}

function Assert-ZipContainsFilePattern {
  param(
    [string]$ZipPath,
    [string]$Pattern,
    [string]$Message
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    foreach ($entry in $archive.Entries) {
      $entryName = $entry.FullName -replace "\\", "/"
      if ($entryName -like $Pattern -and $entry.Length -gt 0) {
        return
      }
    }
  } finally {
    $archive.Dispose()
  }

  throw $Message
}

function Assert-ZipDoesNotContainFile {
  param(
    [string]$ZipPath,
    [string]$FileName,
    [string]$Message
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    foreach ($entry in $archive.Entries) {
      $entryName = $entry.FullName -replace "\\", "/"
      if ($entryName -eq $FileName -or $entryName.EndsWith("/$FileName")) {
        throw $Message
      }
    }
  } finally {
    $archive.Dispose()
  }
}

function Assert-ZipDoesNotContainFilePattern {
  param(
    [string]$ZipPath,
    [string]$Pattern,
    [string]$Message
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    foreach ($entry in $archive.Entries) {
      $entryName = ($entry.FullName -replace "\\", "/").TrimEnd("/")
      $leafName = [IO.Path]::GetFileName($entryName)
      if ($leafName -like $Pattern) {
        throw $Message
      }
    }
  } finally {
    $archive.Dispose()
  }
}

function Assert-ZipEntriesSafe {
  param(
    [string]$ZipPath,
    [string]$Message
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    foreach ($entry in $archive.Entries) {
      $entryName = $entry.FullName -replace "\\", "/"
      if ([string]::IsNullOrWhiteSpace($entryName)) {
        throw "$Message Empty zip entry path."
      }
      foreach ($character in $entryName.ToCharArray()) {
        $code = [int][char]$character
        if ($code -le 0x1F -or ($code -ge 0x7F -and $code -le 0x9F)) {
          throw "$Message Zip entry '$entryName' contains control characters."
        }
      }
      if ($entryName.StartsWith("/") -or $entryName -match "^[A-Za-z]:") {
        throw "$Message Zip entry '$entryName' is absolute."
      }
      $relativeName = $entryName.TrimEnd("/")
      if ([string]::IsNullOrWhiteSpace($relativeName)) {
        throw "$Message Zip entry '$entryName' is not a relative file path."
      }
      foreach ($segment in $relativeName.Split("/")) {
        $trimmedSegment = $segment.Trim()
        if ([string]::IsNullOrEmpty($segment) -or
            [string]::IsNullOrEmpty($trimmedSegment) -or
            $segment -ne $trimmedSegment -or
            $trimmedSegment -eq "." -or
            $trimmedSegment -eq "..") {
          throw "$Message Zip entry '$entryName' contains blank, whitespace-padded, or unsafe path segments."
        }
      }
    }
  } finally {
    $archive.Dispose()
  }
}

function Assert-ReleaseArtifactFileName {
  param(
    [string]$FileName,
    [string]$Context
  )

  if ([string]::IsNullOrWhiteSpace($FileName)) {
    throw "$Context artifact file name must not be blank."
  }
  $trimmedFileName = $FileName.Trim()
  if ($FileName -cne $trimmedFileName) {
    throw "$Context artifact file name must not contain leading or trailing whitespace."
  }
  if ([IO.Path]::IsPathRooted($trimmedFileName) -or
      $trimmedFileName -ne [IO.Path]::GetFileName($trimmedFileName) -or
      $trimmedFileName -match '[<>:"/\\|?*\x00-\x1F\x7F-\x9F]' -or
      $trimmedFileName -eq "." -or
      $trimmedFileName -eq "..") {
    throw "$Context artifact file name '$trimmedFileName' must be a safe single file name."
  }
}

function Assert-ReleaseSha256 {
  param(
    [object]$Sha256,
    [string]$Context
  )

  $hash = [string]$Sha256
  if ($hash -cnotmatch '^[0-9a-f]{64}$') {
    throw "$Context SHA-256 hash must be 64 lowercase hexadecimal characters."
  }
}

function Assert-ReleaseByteCount {
  param(
    [object]$Bytes,
    [string]$Context
  )

  $isInteger =
    $Bytes -is [byte] -or
    $Bytes -is [sbyte] -or
    $Bytes -is [int16] -or
    $Bytes -is [uint16] -or
    $Bytes -is [int32] -or
    $Bytes -is [uint32] -or
    $Bytes -is [int64]

  if (-not $isInteger) {
    throw "$Context byte count must be a positive integer."
  }

  $byteCount = [int64]$Bytes
  if ($byteCount -le 0) {
    throw "$Context byte count must be a positive integer."
  }
}

function Assert-ReleaseRecordFields {
  param(
    [object]$Record,
    [string]$Context
  )

  if ($null -eq $Record) {
    throw "$Context release record must not be missing."
  }
  Assert-ReleaseArtifactFileName `
    -FileName ([string]$Record.fileName) `
    -Context $Context
  Assert-ReleaseByteCount `
    -Bytes $Record.bytes `
    -Context $Context
  Assert-ReleaseSha256 `
    -Sha256 $Record.sha256 `
    -Context $Context
}

function New-ZipFromDirectory {
  param(
    [string]$SourceDirectory,
    [string]$DestinationPath
  )

  Assert-PathExists `
    -Path $SourceDirectory `
    -Message "Zip source directory '$SourceDirectory' was not found."

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $sourceRoot = [IO.Path]::GetFullPath($SourceDirectory)
  $sourceRoot = $sourceRoot.TrimEnd(
    [char[]]@(
      [IO.Path]::DirectorySeparatorChar,
      [IO.Path]::AltDirectorySeparatorChar
    )
  )
  $sourceBase = "$sourceRoot$([IO.Path]::DirectorySeparatorChar)"
  $archive = [IO.Compression.ZipFile]::Open(
    $DestinationPath,
    [IO.Compression.ZipArchiveMode]::Create
  )
  try {
    Get-ChildItem -LiteralPath $sourceRoot -Recurse -File |
      Sort-Object FullName |
      ForEach-Object {
        $relativePath = $_.FullName.Substring($sourceBase.Length)
        $entryName = $relativePath.Replace("\", "/")
        if ([string]::IsNullOrWhiteSpace($entryName)) {
          throw "Zip source directory '$SourceDirectory' contained an empty file path."
        }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
          $archive,
          $_.FullName,
          $entryName,
          [IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
      }
  } finally {
    $archive.Dispose()
  }
}

function Remove-WindowsRuntimeStateFiles {
  param([string]$StagingDirectory)

  $runtimeStateNames = @(
    "data.json",
    "data.backup.json",
    "data.crash_recovery.json",
    "data.json.tmp",
    "RePaperTodo.crash.log",
    "fullscreen-debug.log"
  )

  Get-ChildItem -LiteralPath $StagingDirectory -Recurse -Directory |
    Where-Object { $_.Name -eq "LOG" } |
    Sort-Object FullName -Descending |
    Remove-Item -Recurse -Force

  Get-ChildItem -LiteralPath $StagingDirectory -Recurse -File |
    Where-Object {
      $name = $_.Name
      $runtimeStateNames -contains $name -or
        $name -like "*.tmp" -or
        $name -like "*.failed_load.*" -or
        $name -like "*.used_for_recovery.*"
    } |
    Remove-Item -Force
}

function Assert-ReleaseChecksumFile {
  param(
    [string]$ChecksumsFile,
    [string]$ArtifactDirectory,
    [object[]]$Records
  )

  foreach ($record in $Records) {
    Assert-ReleaseRecordFields `
      -Record $record `
      -Context "Release checksum"
  }

  $expectedLines = @(
    $Records | ForEach-Object { "$($_.sha256)  $($_.fileName)" }
  )
  $actualLines = @(Get-Content -LiteralPath $ChecksumsFile)

  if ($actualLines.Count -ne $expectedLines.Count) {
    throw "Release checksum file '$ChecksumsFile' contains $($actualLines.Count) line(s), expected $($expectedLines.Count)."
  }

  for ($index = 0; $index -lt $expectedLines.Count; $index++) {
    if ($actualLines[$index] -ne $expectedLines[$index]) {
      throw "Release checksum file '$ChecksumsFile' line $($index + 1) does not match the packaged artifact hash."
    }
  }

  foreach ($record in $Records) {
    $artifactPath = Join-Path $ArtifactDirectory $record.fileName
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
      throw "Release checksum file '$ChecksumsFile' references missing artifact '$($record.fileName)'."
    }
    $artifactItem = Get-Item -LiteralPath $artifactPath
    if ($artifactItem.Length -ne [int64]$record.bytes) {
      throw "Release artifact '$($record.fileName)' size changed after checksum generation."
    }
    $artifactHash = Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath
    if ($artifactHash.Hash.ToLowerInvariant() -ne [string]$record.sha256) {
      throw "Release artifact '$($record.fileName)' hash changed after checksum generation."
    }
  }
}

function Assert-ReleaseMetadataStringSequence {
  param(
    [string]$Name,
    [object]$Actual,
    [string[]]$Expected
  )

  $actualValues = @()
  if ($null -ne $Actual) {
    $actualValues = @($Actual | ForEach-Object { [string]$_ })
  }

  if ($actualValues.Count -ne $Expected.Count) {
    throw "Release metadata JSON '$Name' contains $($actualValues.Count) value(s), expected $($Expected.Count)."
  }

  for ($index = 0; $index -lt $Expected.Count; $index++) {
    if ($actualValues[$index] -ne $Expected[$index]) {
      throw "Release metadata JSON '$Name' value $($index + 1) does not match the validated release command list."
    }
  }
}

function Assert-ReleaseMetadataRecord {
  param(
    [string]$Name,
    [object]$Actual,
    [object]$Expected
  )

  if ($null -eq $Actual) {
    throw "Release metadata JSON is missing '$Name'."
  }
  Assert-ReleaseRecordFields `
    -Record $Actual `
    -Context "Release metadata JSON '$Name'"
  Assert-ReleaseRecordFields `
    -Record $Expected `
    -Context "Packaged release '$Name'"
  if ([string]$Actual.fileName -ne [string]$Expected.fileName -or
      [int64]$Actual.bytes -ne [int64]$Expected.bytes -or
      [string]$Actual.sha256 -ne [string]$Expected.sha256) {
    throw "Release metadata JSON '$Name' does not match the packaged release record."
  }
}

function Assert-ReleaseMetadataRecords {
  param(
    [string]$Name,
    [object]$Actual,
    [object[]]$Expected
  )

  $actualRecords = @()
  if ($null -ne $Actual) {
    $actualRecords = @($Actual)
  }

  if ($actualRecords.Count -ne $Expected.Count) {
    throw "Release metadata JSON '$Name' contains $($actualRecords.Count) record(s), expected $($Expected.Count)."
  }

  for ($index = 0; $index -lt $Expected.Count; $index++) {
    Assert-ReleaseMetadataRecord `
      -Name "$Name[$index]" `
      -Actual $actualRecords[$index] `
      -Expected $Expected[$index]
  }
}

function Get-RecordPropertyValue {
  param(
    [object]$Record,
    [string]$Name
  )

  if ($null -eq $Record) {
    return $null
  }
  if ($Record -is [System.Collections.IDictionary]) {
    if ($Record.Contains($Name)) {
      return $Record[$Name]
    }
    return $null
  }
  $property = $Record.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Assert-AndroidStaticSmokeApkPath {
  param(
    [string]$ApkPath,
    [string]$ExpectedApkPath
  )

  if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    throw "Android static smoke record apkPath must not be blank."
  }

  $resolvedApkPath = [IO.Path]::GetFullPath($ApkPath)
  $resolvedExpectedApkPath = [IO.Path]::GetFullPath($ExpectedApkPath)
  if ($resolvedApkPath -ine $resolvedExpectedApkPath) {
    throw "Android static smoke record apkPath must match the packaged Android APK."
  }
  if ([IO.Path]::GetExtension($resolvedApkPath) -ine ".apk") {
    throw "Android static smoke record apkPath must reference an APK file."
  }
  if (-not (Test-Path -LiteralPath $resolvedApkPath -PathType Leaf)) {
    throw "Android static smoke record apkPath was not found: $resolvedApkPath"
  }
}

function Assert-AndroidStaticSmokeRecord {
  param(
    [object]$Record,
    [object]$AndroidSdkConfig,
    [string]$ExpectedApkPath
  )

  if ($null -eq $Record) {
    throw "Android static smoke record is missing."
  }

  $status = [string](Get-RecordPropertyValue -Record $Record -Name "status")
  if ($status -ne "passed") {
    throw "Android static smoke record must have status 'passed'."
  }

  $checkedAtUtcText =
    [string](Get-RecordPropertyValue -Record $Record -Name "checkedAtUtc")
  if ([string]::IsNullOrWhiteSpace($checkedAtUtcText)) {
    throw "Android static smoke record checkedAtUtc must not be blank."
  }
  try {
    $checkedAtUtc = [DateTimeOffset]::Parse($checkedAtUtcText)
  } catch {
    throw "Android static smoke record checkedAtUtc is not a valid timestamp."
  }
  if ($checkedAtUtc.Offset -ne [TimeSpan]::Zero) {
    throw "Android static smoke record checkedAtUtc must be a UTC timestamp."
  }

  if ([string](Get-RecordPropertyValue -Record $Record -Name "applicationId") -ne
      "com.aligez.repapertodo") {
    throw "Android static smoke record applicationId does not match RePaperTodo."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "apkApplicationId") -ne
      [string](Get-RecordPropertyValue -Record $Record -Name "applicationId")) {
    throw "Android static smoke record APK applicationId must match the manifest package."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "launcherActivity") -ne
      "com.aligez.repapertodo.MainActivity") {
    throw "Android static smoke record launcherActivity must match RePaperTodo MainActivity."
  }
  foreach ($property in @(
    "launcherIntentPresent",
    "singleTopLaunchMode",
    "emptyTaskAffinity",
    "adjustResizeWindow",
    "hardwareAcceleratedActivity",
    "backgroundWorkManagerInitializer",
    "backgroundWorkManagerSystemJobService",
    "backgroundWorkManagerRescheduleReceiver",
    "backgroundSyncNetworkPermission",
    "backgroundSyncWakeLockPermission",
    "backgroundSyncBootReschedulePermission"
  )) {
    if ([bool](Get-RecordPropertyValue -Record $Record -Name $property) -ne $true) {
      throw "Android static smoke record must confirm $property."
    }
  }
  if ([int](Get-RecordPropertyValue -Record $Record -Name "minSdk") -ne
      [int]$AndroidSdkConfig["minSdk"] -or
      [int](Get-RecordPropertyValue -Record $Record -Name "targetSdk") -ne
      [int]$AndroidSdkConfig["targetSdk"] -or
      [int](Get-RecordPropertyValue -Record $Record -Name "compileSdk") -ne
      [int]$AndroidSdkConfig["compileSdk"]) {
    throw "Android static smoke record SDK values do not match the validated Android build configuration."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "debuggable") -ne
      "false") {
    throw "Android static smoke record must describe a non-debuggable APK."
  }
  if ([bool](Get-RecordPropertyValue -Record $Record -Name "cleartextWebDavAllowed") -ne
      $true) {
    throw "Android static smoke record must confirm generic HTTP WebDAV cleartext support."
  }
  if ([bool](Get-RecordPropertyValue -Record $Record -Name "broadExternalStoragePermissionsAbsent") -ne
      $true) {
    throw "Android static smoke record must confirm broad external storage permissions are absent."
  }
  if ([bool](Get-RecordPropertyValue -Record $Record -Name "forbiddenLocalizedResourceConfigurationsAbsent") -ne
      $true) {
    throw "Android static smoke record must confirm APK localized resources are limited to supported runtime languages."
  }
  if ([bool](Get-RecordPropertyValue -Record $Record -Name "androidLocaleConfigPresent") -ne
      $true) {
    throw "Android static smoke record must confirm APK localeConfig is present."
  }
  Assert-ReleaseMetadataStringSequence `
    -Name "android.staticSmoke.expectedResourceLanguages" `
    -Actual (Get-RecordPropertyValue -Record $Record -Name "expectedResourceLanguages") `
    -Expected @("zh", "en")
  Assert-ReleaseMetadataStringSequence `
    -Name "android.staticSmoke.localeConfigLanguages" `
    -Actual (Get-RecordPropertyValue -Record $Record -Name "localeConfigLanguages") `
    -Expected @("zh", "en")
  if ([string]::IsNullOrWhiteSpace(
      [string](Get-RecordPropertyValue -Record $Record -Name "fileProviderPathsResource"))) {
    throw "Android static smoke record must include the FileProvider paths resource."
  }
  if ([string]::IsNullOrWhiteSpace(
      [string](Get-RecordPropertyValue -Record $Record -Name "localeConfigResource"))) {
    throw "Android static smoke record must include the localeConfig resource."
  }
  $apkFileName = [string](Get-RecordPropertyValue -Record $Record -Name "apkFileName")
  if ([string]::IsNullOrWhiteSpace($apkFileName) -or
      [IO.Path]::GetExtension($apkFileName) -ine ".apk") {
    throw "Android static smoke record must reference an APK file name."
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedApkPath)) {
    Assert-AndroidStaticSmokeApkPath `
      -ApkPath ([string](Get-RecordPropertyValue -Record $Record -Name "apkPath")) `
      -ExpectedApkPath $ExpectedApkPath
  }
}

function Assert-AndroidDeviceSmokeRecord {
  param(
    [object]$Record,
    [string]$ExpectedApkFileName,
    [string]$ExpectedApkPath = ""
  )

  if ($null -eq $Record) {
    throw "Android device smoke record is missing."
  }

  $status = [string](Get-RecordPropertyValue -Record $Record -Name "status")
  $checkedAtUtcText =
    [string](Get-RecordPropertyValue -Record $Record -Name "checkedAtUtc")
  if ([string]::IsNullOrWhiteSpace($checkedAtUtcText)) {
    throw "Android device smoke record checkedAtUtc must not be blank."
  }
  try {
    $checkedAtUtc = [DateTimeOffset]::Parse($checkedAtUtcText)
  } catch {
    throw "Android device smoke record checkedAtUtc is not a valid timestamp."
  }
  if ($checkedAtUtc.Offset -ne [TimeSpan]::Zero) {
    throw "Android device smoke record checkedAtUtc must be a UTC timestamp."
  }

  if ($status -eq "skipped") {
    if ([string]::IsNullOrWhiteSpace(
        [string](Get-RecordPropertyValue -Record $Record -Name "reason"))) {
      throw "Skipped Android device smoke record must include a reason."
    }
    return
  }
  if ($status -ne "passed") {
    throw "Android device smoke record must have status 'passed' or 'skipped'."
  }

  $packageName = [string](Get-RecordPropertyValue -Record $Record -Name "packageName")
  $apkApplicationId =
    [string](Get-RecordPropertyValue -Record $Record -Name "apkApplicationId")
  if ($packageName -ne "com.aligez.repapertodo") {
    throw "Android device smoke record packageName does not match RePaperTodo."
  }
  if ($apkApplicationId -ne $packageName) {
    throw "Android device smoke record APK applicationId must match the launched package."
  }

  $apiLevel = [int](Get-RecordPropertyValue -Record $Record -Name "apiLevel")
  $minSupportedApi =
    [int](Get-RecordPropertyValue -Record $Record -Name "minSupportedApi")
  $maxSupportedApi =
    [int](Get-RecordPropertyValue -Record $Record -Name "maxSupportedApi")
  if ($minSupportedApi -ne 34 -or $maxSupportedApi -ne 37 -or
      $apiLevel -lt $minSupportedApi -or $apiLevel -gt $maxSupportedApi) {
    throw "Android device smoke record API level must be inside Android 14-17/API 34-37."
  }
  foreach ($property in @(
    "adb",
    "apkAnalyzer",
    "deviceSerial",
    "processId",
    "foregroundPackage"
  )) {
    if ([string]::IsNullOrWhiteSpace(
        [string](Get-RecordPropertyValue -Record $Record -Name $property))) {
      throw "Android device smoke record $property must not be blank."
    }
  }
  $foregroundPackage =
    [string](Get-RecordPropertyValue -Record $Record -Name "foregroundPackage")
  if ($foregroundPackage -ne $packageName) {
    throw "Android device smoke record foregroundPackage must match the launched package."
  }
  $processId =
    [string](Get-RecordPropertyValue -Record $Record -Name "processId")
  if ($processId -cnotmatch "^\d+$" -or [int64]$processId -le 0) {
    throw "Android device smoke record processId must be a positive integer."
  }
  $apkFileName = [string](Get-RecordPropertyValue -Record $Record -Name "apkFileName")
  if ([string]::IsNullOrWhiteSpace($apkFileName) -or
      [IO.Path]::GetExtension($apkFileName) -ine ".apk") {
    throw "Android device smoke record must reference an APK file name."
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedApkFileName) -and
      $apkFileName -ne $ExpectedApkFileName) {
    throw "Android device smoke record APK file name must match the packaged Android APK."
  }
  $apkBytes = Get-RecordPropertyValue -Record $Record -Name "apkBytes"
  $apkSha256 = Get-RecordPropertyValue -Record $Record -Name "apkSha256"
  Assert-ReleaseByteCount `
    -Bytes $apkBytes `
    -Context "Android device smoke APK"
  Assert-ReleaseSha256 `
    -Sha256 $apkSha256 `
    -Context "Android device smoke APK"
  if (-not [string]::IsNullOrWhiteSpace($ExpectedApkPath)) {
    Assert-FileExists `
      -Path $ExpectedApkPath `
      -Message "Android device smoke expected APK was not found: $ExpectedApkPath"
    $apkItem = Get-Item -LiteralPath $ExpectedApkPath
    if ([int64]$apkBytes -ne [int64]$apkItem.Length) {
      throw "Android device smoke APK byte count must match the packaged Android APK."
    }
    $apkHash = Get-FileHash -Algorithm SHA256 -LiteralPath $ExpectedApkPath
    if ([string]$apkSha256 -ne $apkHash.Hash.ToLowerInvariant()) {
      throw "Android device smoke APK SHA-256 must match the packaged Android APK."
    }
  }
}

function Assert-RecordUtcTimestamp {
  param(
    [object]$Record,
    [string]$PropertyName,
    [string]$Context
  )

  $timestampText =
    [string](Get-RecordPropertyValue -Record $Record -Name $PropertyName)
  if ([string]::IsNullOrWhiteSpace($timestampText)) {
    throw "$Context $PropertyName must not be blank."
  }
  try {
    $timestamp = [DateTimeOffset]::Parse($timestampText)
  } catch {
    throw "$Context $PropertyName is not a valid timestamp."
  }
  if ($timestamp.Offset -ne [TimeSpan]::Zero) {
    throw "$Context $PropertyName must be a UTC timestamp."
  }
}

function Assert-WindowsManualQaArtifact {
  param(
    [object]$Record,
    [string]$BytesProperty,
    [string]$Sha256Property,
    [string]$ExpectedPath,
    [string]$Context
  )

  $recordBytes = Get-RecordPropertyValue -Record $Record -Name $BytesProperty
  $recordSha256 = Get-RecordPropertyValue -Record $Record -Name $Sha256Property
  Assert-ReleaseByteCount -Bytes $recordBytes -Context $Context
  Assert-ReleaseSha256 -Sha256 $recordSha256 -Context $Context

  if ([string]::IsNullOrWhiteSpace($ExpectedPath)) {
    return
  }

  Assert-FileExists `
    -Path $ExpectedPath `
    -Message "$Context expected file was not found: $ExpectedPath"
  $item = Get-Item -LiteralPath $ExpectedPath
  if ([int64]$recordBytes -ne [int64]$item.Length) {
    throw "$Context byte count does not match the current Windows release build."
  }
  $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $ExpectedPath
  if ([string]$recordSha256 -ne $hash.Hash.ToLowerInvariant()) {
    throw "$Context SHA-256 does not match the current Windows release build."
  }
}

function Assert-WindowsManualQaRecord {
  param(
    [object]$Record,
    [string]$ExpectedExePath = "",
    [string]$ExpectedAppSoPath = ""
  )

  if ($null -eq $Record) {
    throw "Windows manual QA record is missing."
  }
  $status = [string](Get-RecordPropertyValue -Record $Record -Name "status")
  Assert-RecordUtcTimestamp `
    -Record $Record `
    -PropertyName "checkedAtUtc" `
    -Context "Windows manual QA record"
  if ($status -eq "skipped") {
    if ([string]::IsNullOrWhiteSpace(
        [string](Get-RecordPropertyValue -Record $Record -Name "reason"))) {
      throw "Skipped Windows manual QA record must include a reason."
    }
    return
  }
  if ($status -ne "passed" -and
      $status -ne "passedWithDeferredMultiMonitor") {
    throw "Windows manual QA record must have status 'passed', 'passedWithDeferredMultiMonitor', or 'skipped'."
  }
  if ([bool](Get-RecordPropertyValue -Record $Record -Name "allowSkipped") -ne $false) {
    throw "Windows manual QA record used -AllowSkipped and cannot prove release parity."
  }
  $deferMultiMonitor =
    [bool](Get-RecordPropertyValue -Record $Record -Name "deferMultiMonitor")
  $deferredItemValue =
    Get-RecordPropertyValue -Record $Record -Name "deferredItemIds"
  $deferredItemIds = @()
  if ($null -ne $deferredItemValue) {
    $deferredItemIds = @($deferredItemValue)
  }
  if ($status -eq "passedWithDeferredMultiMonitor") {
    if (-not $deferMultiMonitor) {
      throw "Deferred multi-monitor Windows manual QA record must set deferMultiMonitor."
    }
    if ($deferredItemIds.Count -ne 1 -or
        [string]$deferredItemIds[0] -ne "multiMonitorEdgeDocking") {
      throw "Deferred multi-monitor Windows manual QA record must identify only multiMonitorEdgeDocking."
    }
    if ([string]::IsNullOrWhiteSpace(
        [string](Get-RecordPropertyValue -Record $Record -Name "reason"))) {
      throw "Deferred multi-monitor Windows manual QA record must include a reason."
    }
    if ([string]::IsNullOrWhiteSpace(
        [string](Get-RecordPropertyValue -Record $Record -Name "notes"))) {
      throw "Deferred multi-monitor Windows manual QA record must include notes."
    }
  } elseif ($deferMultiMonitor -or $deferredItemIds.Count -ne 0) {
    throw "Passed Windows manual QA record must not contain deferred items."
  }
  if ([string]::IsNullOrWhiteSpace(
      [string](Get-RecordPropertyValue -Record $Record -Name "tester"))) {
    throw "Windows manual QA record tester must not be blank."
  }
  if ([string]::IsNullOrWhiteSpace(
      [string](Get-RecordPropertyValue -Record $Record -Name "windowsVersion"))) {
    throw "Windows manual QA record windowsVersion must not be blank."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "exeFileName") -ne
      "repapertodo.exe") {
    throw "Windows manual QA record exeFileName must be repapertodo.exe."
  }
  $recordReleaseDirectory =
    [string](Get-RecordPropertyValue -Record $Record -Name "releaseDirectory")
  if ([string]::IsNullOrWhiteSpace($recordReleaseDirectory)) {
    throw "Windows manual QA record releaseDirectory must not be blank."
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedExePath)) {
    $expectedReleaseDirectory =
      [IO.Path]::GetFullPath((Split-Path -Parent $ExpectedExePath))
    $recordReleaseDirectoryFullPath =
      [IO.Path]::GetFullPath($recordReleaseDirectory)
    if ($recordReleaseDirectoryFullPath -ne $expectedReleaseDirectory) {
      throw "Windows manual QA record releaseDirectory must match the Windows release build output."
    }
  }
  Assert-WindowsManualQaArtifact `
    -Record $Record `
    -BytesProperty "exeBytes" `
    -Sha256Property "exeSha256" `
    -ExpectedPath $ExpectedExePath `
    -Context "Windows manual QA repapertodo.exe"
  if ([string](Get-RecordPropertyValue -Record $Record -Name "appSoRelativePath") -ne
      "data/app.so") {
    throw "Windows manual QA record appSoRelativePath must be data/app.so."
  }
  Assert-WindowsManualQaArtifact `
    -Record $Record `
    -BytesProperty "appSoBytes" `
    -Sha256Property "appSoSha256" `
    -ExpectedPath $ExpectedAppSoPath `
    -Context "Windows manual QA data/app.so"
  $items = @(Get-RecordPropertyValue -Record $Record -Name "items")
  $expectedIds = @(
    "transparentBorderlessFeel",
    "taskSwitcherVisibility",
    "multiMonitorEdgeDocking",
    "fullscreenAvoidance",
    "trayAfterExplorerRestart",
    "longRunningScriptCapsule",
    "independentPaperSurfaces"
  )
  if ($items.Count -ne $expectedIds.Count) {
    throw "Windows manual QA record must include $($expectedIds.Count) checked items."
  }
  foreach ($id in $expectedIds) {
    $matches = @($items | Where-Object { [string]$_.id -eq $id })
    if ($matches.Count -ne 1) {
      throw "Windows manual QA record must include exactly one '$id' item."
    }
    $expectedStatus = if ($status -eq "passedWithDeferredMultiMonitor" -and
        $id -eq "multiMonitorEdgeDocking") {
      "skip"
    } else {
      "pass"
    }
    if ([string]$matches[0].status -ne $expectedStatus) {
      throw "Windows manual QA item '$id' must be $expectedStatus."
    }
  }
}

function Assert-WebDavLiveSmokeRecord {
  param(
    [object]$Record,
    [string]$ExpectedProviderId = ""
  )

  if ($null -eq $Record) {
    throw "WebDAV live smoke record is missing."
  }
  $status = [string](Get-RecordPropertyValue -Record $Record -Name "status")
  Assert-RecordUtcTimestamp `
    -Record $Record `
    -PropertyName "checkedAtUtc" `
    -Context "WebDAV live smoke record"
  if ($status -eq "skipped") {
    if ([string]::IsNullOrWhiteSpace(
        [string](Get-RecordPropertyValue -Record $Record -Name "reason"))) {
      throw "Skipped WebDAV live smoke record must include a reason."
    }
    return
  }
  if ($status -ne "passed") {
    throw "WebDAV live smoke record must have status 'passed' or 'skipped'."
  }
  foreach ($property in @("endpointHost", "providerId", "rootPath")) {
    if ([string]::IsNullOrWhiteSpace(
        [string](Get-RecordPropertyValue -Record $Record -Name $property))) {
      throw "WebDAV live smoke record $property must not be blank."
    }
  }
  Assert-RecordUtcTimestamp `
    -Record $Record `
    -PropertyName "startedAtUtc" `
    -Context "WebDAV live smoke record"
  $rootPath = [string](Get-RecordPropertyValue -Record $Record -Name "rootPath")
  $normalizedRootPath = $rootPath -replace "\\", "/"
  if ($normalizedRootPath.StartsWith("/") -or
      $normalizedRootPath -match "^[A-Za-z]:" -or
      -not $normalizedRootPath.Contains("/run-") -or
      $normalizedRootPath -match "[\x00-\x1F\x7F-\x9F]") {
    throw "WebDAV live smoke record rootPath must be a relative run-scoped path."
  }
  foreach ($segment in ($normalizedRootPath -split "/")) {
    if ([string]::IsNullOrWhiteSpace($segment) -or
        $segment -ne $segment.Trim() -or
        $segment -eq "." -or
        $segment -eq "..") {
      throw "WebDAV live smoke record rootPath must be a relative run-scoped path."
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedProviderId) -and
      [string](Get-RecordPropertyValue -Record $Record -Name "providerId") -ne
      $ExpectedProviderId) {
    throw "WebDAV live smoke record providerId must be '$ExpectedProviderId'."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "windowsUploadStatus") -ne
      "uploaded") {
    throw "WebDAV live smoke record must confirm Windows upload."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "androidDownloadStatus") -ne
      "downloaded") {
    throw "WebDAV live smoke record must confirm Android download."
  }
  if ([int](Get-RecordPropertyValue -Record $Record -Name "androidOperationUploadedCount") -lt 1) {
    throw "WebDAV live smoke record must confirm at least one Android operation upload."
  }
  if ([int](Get-RecordPropertyValue -Record $Record -Name "windowsOperationAppliedCount") -lt 1) {
    throw "WebDAV live smoke record must confirm at least one Windows operation merge."
  }
  $deviceSequences = Get-RecordPropertyValue -Record $Record -Name "deviceSequences"
  if ($null -eq $deviceSequences) {
    throw "WebDAV live smoke record must include deviceSequences."
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
      throw "WebDAV live smoke record must include a positive $deviceId device sequence."
    }
  }
  $cleanup = [string](Get-RecordPropertyValue -Record $Record -Name "remoteCleanup")
  if ($cleanup -ne "attempted" -and $cleanup -ne "skipped") {
    throw "WebDAV live smoke record remoteCleanup must be attempted or skipped."
  }
}

function Resolve-ReleaseQaJsonPath {
  param(
    [string]$Path,
    [string]$Context
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "$Context result JSON path was not provided."
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "$Context result JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "$Context result JSON path must not contain wildcard characters."
  }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path)
  } catch {
    throw "$Context result JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($fullPath))) {
    throw "$Context result JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -ne ".json") {
    throw "$Context result JSON path must use the .json extension."
  }
  return $fullPath
}

function Read-ReleaseQaRecord {
  param(
    [string]$Path,
    [string]$Context
  )

  $fullPath = Resolve-ReleaseQaJsonPath -Path $Path -Context $Context
  Assert-FileExists `
    -Path $fullPath `
    -Message "$Context result JSON was not found: $fullPath"
  try {
    $result = Get-Content -Raw -LiteralPath $fullPath | ConvertFrom-Json
  } catch {
    throw "$Context result JSON could not be parsed: $($_.Exception.Message)"
  }
  $record = [ordered]@{}
  foreach ($property in $result.PSObject.Properties) {
    $record[$property.Name] = $property.Value
  }
  return $record
}

function Assert-WindowsSmokeReleaseDirectory {
  param(
    [string]$RepoRoot,
    [string]$ReleaseDirectory
  )

  if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
    throw "Windows smoke record releaseDirectory must not be blank."
  }

  $resolvedReleaseDirectory = [IO.Path]::GetFullPath($ReleaseDirectory)
  $expectedReleaseDirectory =
    [IO.Path]::GetFullPath(
      (Join-Path $RepoRoot "build\windows\x64\runner\Release")
    )
  if ($resolvedReleaseDirectory -ine $expectedReleaseDirectory) {
    throw "Windows smoke record releaseDirectory must match the Windows release build output."
  }

  foreach ($requiredPath in @(
      (Join-Path $resolvedReleaseDirectory "repapertodo.exe"),
      (Join-Path $resolvedReleaseDirectory "flutter_windows.dll")
    )) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
      throw "Windows smoke record releaseDirectory is missing a required release file: $requiredPath"
    }
  }

  $dataDirectory = Join-Path $resolvedReleaseDirectory "data"
  if (-not (Test-Path -LiteralPath $dataDirectory -PathType Container)) {
    throw "Windows smoke record releaseDirectory is missing the Flutter data directory: $dataDirectory"
  }
}

function Assert-WindowsSmokeRecord {
  param(
    [object]$Record,
    [string]$RepoRoot
  )

  if ($null -eq $Record) {
    throw "Windows smoke record is missing."
  }

  $status = [string](Get-RecordPropertyValue -Record $Record -Name "status")
  if ($status -ne "passed") {
    throw "Windows smoke record must have status 'passed'."
  }

  $checkedAtUtcText =
    [string](Get-RecordPropertyValue -Record $Record -Name "checkedAtUtc")
  if ([string]::IsNullOrWhiteSpace($checkedAtUtcText)) {
    throw "Windows smoke record checkedAtUtc must not be blank."
  }
  try {
    $checkedAtUtc = [DateTimeOffset]::Parse($checkedAtUtcText)
  } catch {
    throw "Windows smoke record checkedAtUtc is not a valid timestamp."
  }
  if ($checkedAtUtc.Offset -ne [TimeSpan]::Zero) {
    throw "Windows smoke record checkedAtUtc must be a UTC timestamp."
  }

  if ([string](Get-RecordPropertyValue -Record $Record -Name "exeFileName") -ne
      "repapertodo.exe") {
    throw "Windows smoke record exeFileName must be repapertodo.exe."
  }
  if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    Assert-WindowsSmokeReleaseDirectory `
      -RepoRoot $RepoRoot `
      -ReleaseDirectory ([string](Get-RecordPropertyValue -Record $Record -Name "releaseDirectory"))
  } elseif ([string]::IsNullOrWhiteSpace(
      [string](Get-RecordPropertyValue -Record $Record -Name "releaseDirectory"))) {
    throw "Windows smoke record releaseDirectory must not be blank."
  }
  if ([int](Get-RecordPropertyValue -Record $Record -Name "initialPaperCount") -lt 1) {
    throw "Windows smoke record initialPaperCount must be at least 1."
  }
  if ([int](Get-RecordPropertyValue -Record $Record -Name "finalPaperCount") -lt 3) {
    throw "Windows smoke record finalPaperCount must be at least 3."
  }
  $initialVisibleTopLevelWindowCount =
    [int](Get-RecordPropertyValue -Record $Record -Name "initialVisibleTopLevelWindowCount")
  if ($initialVisibleTopLevelWindowCount -lt
      [int](Get-RecordPropertyValue -Record $Record -Name "initialPaperCount")) {
    throw "Windows smoke record initialVisibleTopLevelWindowCount must cover every initial paper."
  }
  $finalVisibleTopLevelWindowCount =
    [int](Get-RecordPropertyValue -Record $Record -Name "finalVisibleTopLevelWindowCount")
  if ($finalVisibleTopLevelWindowCount -lt 2) {
    throw "Windows smoke record finalVisibleTopLevelWindowCount must prove multiple visible paper HWNDs."
  }
  if ((Get-RecordPropertyValue -Record $Record -Name "independentPaperSurfaces") -ne $true) {
    throw "Windows smoke record independentPaperSurfaces must be true."
  }
  if ((Get-RecordPropertyValue -Record $Record -Name "geometryPersistenceVerified") -ne $true) {
    throw "Windows smoke record geometryPersistenceVerified must be true."
  }
  if ((Get-RecordPropertyValue -Record $Record -Name "contentEditGeometryStabilityVerified") -ne $true) {
    throw "Windows smoke record contentEditGeometryStabilityVerified must be true."
  }
  if ((Get-RecordPropertyValue -Record $Record -Name "settingsCoordinatorLifecycle") -ne $true) {
    throw "Windows smoke record settingsCoordinatorLifecycle must be true."
  }
  $visiblePaperCountBeforeSettings =
    [int](Get-RecordPropertyValue -Record $Record -Name "visiblePaperCountBeforeSettings")
  if ($visiblePaperCountBeforeSettings -lt 2 -or
      [int](Get-RecordPropertyValue -Record $Record -Name "visibleTopLevelWindowCountWhileSettingsOpen") -lt
        ($visiblePaperCountBeforeSettings + 1) -or
      [int](Get-RecordPropertyValue -Record $Record -Name "visibleTopLevelWindowCountAfterSettingsClose") -ne
        $visiblePaperCountBeforeSettings) {
    throw "Windows smoke record must prove the settings coordinator opens and closes without changing independent paper HWNDs."
  }
  if ([int](Get-RecordPropertyValue -Record $Record -Name "finalNotePaperCount") -le
      [int](Get-RecordPropertyValue -Record $Record -Name "initialNotePaperCount")) {
    throw "Windows smoke record finalNotePaperCount must be greater than initialNotePaperCount after --new-note."
  }
  if ([int](Get-RecordPropertyValue -Record $Record -Name "finalTodoPaperCount") -le
      [int](Get-RecordPropertyValue -Record $Record -Name "initialTodoPaperCount")) {
    throw "Windows smoke record finalTodoPaperCount must be greater than initialTodoPaperCount after --new-todo."
  }
  Assert-ReleaseMetadataStringSequence `
    -Name "windows.smoke.hiddenStartupCommands" `
    -Actual (Get-RecordPropertyValue -Record $Record -Name "hiddenStartupCommands") `
    -Expected @("--hide")
  Assert-ReleaseMetadataStringSequence `
    -Name "windows.smoke.ignoredSecondaryStartupCommands" `
    -Actual (Get-RecordPropertyValue -Record $Record -Name "ignoredSecondaryStartupCommands") `
    -Expected @("--unknown-startup-command")
  if ([int](Get-RecordPropertyValue -Record $Record -Name "visiblePaperCountAfterIgnoredCommand") -ne 0) {
    throw "Windows smoke record visiblePaperCountAfterIgnoredCommand must remain 0 after an unknown secondary startup command."
  }
  Assert-ReleaseMetadataStringSequence `
    -Name "windows.smoke.settingsStartupCommands" `
    -Actual (Get-RecordPropertyValue -Record $Record -Name "settingsStartupCommands") `
    -Expected @("--settings")
  Assert-ReleaseMetadataStringSequence `
    -Name "windows.smoke.secondaryStartupCommands" `
    -Actual (Get-RecordPropertyValue -Record $Record -Name "secondaryStartupCommands") `
    -Expected @("--new-note", "--new-todo", "--exit")
}

function Assert-WindowsPolicySmokeRecord {
  param(
    [object]$Record,
    [string]$RepoRoot
  )

  if ($null -eq $Record -or
      [string](Get-RecordPropertyValue -Record $Record -Name "status") -ne "passed") {
    throw "Windows policy smoke record must have status 'passed'."
  }
  $checkedAtUtcText =
    [string](Get-RecordPropertyValue -Record $Record -Name "checkedAtUtc")
  try { $checkedAtUtc = [DateTimeOffset]::Parse($checkedAtUtcText) } catch {
    throw "Windows policy smoke record checkedAtUtc is invalid."
  }
  if ($checkedAtUtc.Offset -ne [TimeSpan]::Zero) {
    throw "Windows policy smoke record checkedAtUtc must be UTC."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "exeFileName") -ne
      "repapertodo.exe") {
    throw "Windows policy smoke record exeFileName must be repapertodo.exe."
  }
  if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    Assert-WindowsSmokeReleaseDirectory `
      -RepoRoot $RepoRoot `
      -ReleaseDirectory ([string](Get-RecordPropertyValue -Record $Record -Name "releaseDirectory"))
  }
  foreach ($property in @(
      "trayIconRecoveredAfterTaskbarCreated",
      "fullscreenAvoidance",
      "fullscreenTopmostRestored",
      "longRunningScriptCapsule",
      "borderlessResizableWindow",
      "taskSwitcherVisibility",
      "capsuleEdgeDocking"
    )) {
    if ((Get-RecordPropertyValue -Record $Record -Name $property) -ne $true) {
      throw "Windows policy smoke record $property must be true."
    }
  }
}

function Assert-RepositoryEvidenceFile {
  param(
    [string]$Context,
    [string]$RepoRoot,
    [string]$RelativePath
  )

  if ([string]::IsNullOrWhiteSpace($RelativePath)) {
    throw "$Context must not be blank."
  }
  if ([IO.Path]::IsPathRooted($RelativePath)) {
    throw "$Context must be repository-relative: $RelativePath"
  }
  if ($RelativePath -match "[\x00-\x1F\x7F-\x9F]") {
    throw "$Context must not contain control characters: $RelativePath"
  }

  $normalizedRelativePath =
    $RelativePath.Replace("/", [IO.Path]::DirectorySeparatorChar)
  $segments = @(
    $normalizedRelativePath -split [regex]::Escape(
      [string][IO.Path]::DirectorySeparatorChar
    ) |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
  if ($segments | Where-Object { $_ -eq "." -or $_ -eq ".." }) {
    throw "$Context must not contain dot-segments: $RelativePath"
  }

  $resolvedPath =
    [IO.Path]::GetFullPath((Join-Path $RepoRoot $normalizedRelativePath))
  $resolvedRepoRoot = [IO.Path]::GetFullPath($RepoRoot)
  if (-not $resolvedRepoRoot.EndsWith(
      [string][IO.Path]::DirectorySeparatorChar
    )) {
    $resolvedRepoRoot =
      "$resolvedRepoRoot$([IO.Path]::DirectorySeparatorChar)"
  }
  if (-not $resolvedPath.StartsWith(
      $resolvedRepoRoot,
      [StringComparison]::OrdinalIgnoreCase
    )) {
    throw "$Context must stay inside the repository: $RelativePath"
  }
  if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
    throw "$Context was not found: $RelativePath"
  }
}

function Assert-WebDavSmokeRecord {
  param(
    [object]$Record,
    [string]$RepoRoot = ""
  )

  if ($null -eq $Record) {
    throw "WebDAV static smoke record is missing."
  }

  $status = [string](Get-RecordPropertyValue -Record $Record -Name "status")
  if ($status -ne "passed") {
    throw "WebDAV static smoke record must have status 'passed'."
  }

  $checkedAtUtcText =
    [string](Get-RecordPropertyValue -Record $Record -Name "checkedAtUtc")
  if ([string]::IsNullOrWhiteSpace($checkedAtUtcText)) {
    throw "WebDAV static smoke record checkedAtUtc must not be blank."
  }
  try {
    $checkedAtUtc = [DateTimeOffset]::Parse($checkedAtUtcText)
  } catch {
    throw "WebDAV static smoke record checkedAtUtc is not a valid timestamp."
  }
  if ($checkedAtUtc.Offset -ne [TimeSpan]::Zero) {
    throw "WebDAV static smoke record checkedAtUtc must be a UTC timestamp."
  }

  foreach ($property in @(
    "genericWebDavSupported",
    "jianguoyunPresetSupported",
    "encryptedPayloadsRequired",
    "operationLogsSupported",
    "crossDeviceOperationRoundTripCovered",
    "localHttpWebDavRoundTripCovered",
    "sharedWindowsAndroidSettings",
    "androidBackgroundSyncSharedDartPath",
    "androidBackgroundSyncRegistrationCovered",
    "androidBackgroundSyncAbsoluteStatePathCovered",
    "androidBackgroundSyncDataJsonStatePathCovered"
  )) {
    if ([bool](Get-RecordPropertyValue -Record $Record -Name $property) -ne
        $true) {
      throw "WebDAV static smoke record must confirm $property."
    }
  }
  Assert-ReleaseMetadataStringSequence `
    -Name "webDav.staticSmoke.evidenceFiles" `
    -Actual (Get-RecordPropertyValue -Record $Record -Name "evidenceFiles") `
    -Expected @(
      "lib/src/sync/webdav/webdav_client.dart",
      "lib/src/sync/webdav/webdav_state_sync_service.dart",
      "lib/src/sync/webdav/webdav_payload_codec.dart",
      "lib/src/core/model/webdav_presets.dart",
      "lib/src/core/model/sync_settings.dart",
      "lib/src/sync/android_background_sync.dart",
      "lib/src/ui/sync_settings_dialog.dart",
      "test/android_background_sync_test.dart",
      "test/webdav_state_sync_service_test.dart",
      "test/app_sync_service_test.dart",
      "test/webdav_client_test.dart",
      "test/webdav_payload_codec_test.dart",
      "test/webdav_presets_test.dart"
    )
  if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    foreach ($evidenceFile in @(
      Get-RecordPropertyValue -Record $Record -Name "evidenceFiles"
    )) {
      Assert-RepositoryEvidenceFile `
        -Context "WebDAV static smoke evidence file" `
        -RepoRoot $RepoRoot `
        -RelativePath ([string]$evidenceFile)
    }
  }
}

function Test-ReleaseMetadataRecordValueEqual {
  param(
    [string]$PropertyName,
    [object]$Actual,
    [object]$Expected
  )

  if ($PropertyName.EndsWith("AtUtc", [StringComparison]::Ordinal)) {
    try {
      $actualTimestamp = if ($Actual -is [DateTimeOffset]) {
        ([DateTimeOffset]$Actual).ToUniversalTime()
      } elseif ($Actual -is [DateTime]) {
        [DateTimeOffset]::new(([DateTime]$Actual).ToUniversalTime())
      } else {
        [DateTimeOffset]::Parse([string]$Actual).ToUniversalTime()
      }
      $expectedTimestamp = if ($Expected -is [DateTimeOffset]) {
        ([DateTimeOffset]$Expected).ToUniversalTime()
      } elseif ($Expected -is [DateTime]) {
        [DateTimeOffset]::new(([DateTime]$Expected).ToUniversalTime())
      } else {
        [DateTimeOffset]::Parse([string]$Expected).ToUniversalTime()
      }
      return $actualTimestamp.UtcDateTime.Ticks -eq $expectedTimestamp.UtcDateTime.Ticks
    } catch {
      return $false
    }
  }
  return [string]$Actual -eq [string]$Expected
}

function Assert-ReleaseMetadataFile {
  param(
    [string]$RepoRoot,
    [string]$MetadataFile,
    [string]$Version,
    [string]$TagName,
    [string]$GitCommit,
    [bool]$DirtyWorkingTreeAllowed,
    [object]$AndroidSdkConfig,
    [string]$AndroidSigningMode,
    [object]$AndroidSdkTools,
    [string]$AndroidApkPath,
    [object]$WindowsSmokeRecord,
    [object]$WindowsPolicySmokeRecord,
    [object]$WindowsManualQaRecord,
    [object]$WebDavSmokeRecord,
    [object]$WebDavLiveSmokeRecord,
    [object]$WebDavDomesticLiveSmokeRecord,
    [object]$AndroidStaticSmokeRecord,
    [object]$AndroidDeviceSmokeRecord,
    [string[]]$SupportedRuntimeLanguages,
    [string]$PackageResolution,
    [object]$ToolchainInfo,
    [object]$DependencyLockRecord,
    [object]$ReleaseNotesRecord,
    [string[]]$ValidationExecuted,
    [string[]]$ValidationSkipped,
    [object[]]$ArtifactRecords
  )

  try {
    $metadata = Get-Content -Raw -LiteralPath $MetadataFile | ConvertFrom-Json
  } catch {
    throw "Release metadata JSON '$MetadataFile' could not be parsed: $($_.Exception.Message)"
  }

  if ([string]$metadata.version -ne $Version) {
    throw "Release metadata JSON version does not match pubspec.yaml."
  }
  if ([string]$metadata.tagName -ne $TagName) {
    throw "Release metadata JSON tagName does not match the release tag."
  }
  if ([string]$metadata.gitCommit -ne $GitCommit) {
    throw "Release metadata JSON gitCommit does not match the validated commit."
  }
  if ([bool]$metadata.dirtyWorkingTreeAllowed -ne $DirtyWorkingTreeAllowed) {
    throw "Release metadata JSON dirtyWorkingTreeAllowed does not match release options."
  }
  if ([string]::IsNullOrWhiteSpace([string]$metadata.builtAtUtc)) {
    throw "Release metadata JSON builtAtUtc must not be blank."
  }
  try {
    $builtAtUtc = [DateTimeOffset]::Parse([string]$metadata.builtAtUtc)
  } catch {
    throw "Release metadata JSON builtAtUtc is not a valid timestamp."
  }
  if ($builtAtUtc.Offset -ne [TimeSpan]::Zero) {
    throw "Release metadata JSON builtAtUtc must be a UTC timestamp."
  }

  if ($null -eq $metadata.windows) {
    throw "Release metadata JSON windows is missing."
  }
  if ($null -eq $metadata.windows.smoke) {
    throw "Release metadata JSON windows.smoke is missing."
  }
  Assert-WindowsSmokeRecord -Record $metadata.windows.smoke -RepoRoot $RepoRoot
  foreach ($property in $WindowsSmokeRecord.Keys) {
    $actualValue =
      $metadata.windows.smoke.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $WindowsSmokeRecord[$property])) {
      throw "Release metadata JSON windows.smoke.$property does not match the Windows smoke result."
    }
  }
  if ($null -eq $metadata.windows.policySmoke) {
    throw "Release metadata JSON windows.policySmoke is missing."
  }
  Assert-WindowsPolicySmokeRecord `
    -Record $metadata.windows.policySmoke `
    -RepoRoot $RepoRoot
  foreach ($property in $WindowsPolicySmokeRecord.Keys) {
    $actualValue =
      $metadata.windows.policySmoke.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $WindowsPolicySmokeRecord[$property])) {
      throw "Release metadata JSON windows.policySmoke.$property does not match the Windows policy smoke result."
    }
  }
  if ($null -eq $metadata.windows.manualQa) {
    throw "Release metadata JSON windows.manualQa is missing."
  }
  Assert-WindowsManualQaRecord -Record $metadata.windows.manualQa
  foreach ($property in $WindowsManualQaRecord.Keys) {
    $actualValue =
      $metadata.windows.manualQa.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $WindowsManualQaRecord[$property])) {
      throw "Release metadata JSON windows.manualQa.$property does not match the Windows manual QA result."
    }
  }

  if ($null -eq $metadata.webDav) {
    throw "Release metadata JSON webDav is missing."
  }
  if ($null -eq $metadata.webDav.staticSmoke) {
    throw "Release metadata JSON webDav.staticSmoke is missing."
  }
  Assert-WebDavSmokeRecord `
    -Record $metadata.webDav.staticSmoke `
    -RepoRoot $RepoRoot
  foreach ($property in $WebDavSmokeRecord.Keys) {
    $actualValue =
      $metadata.webDav.staticSmoke.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $WebDavSmokeRecord[$property])) {
      throw "Release metadata JSON webDav.staticSmoke.$property does not match the WebDAV static smoke result."
    }
  }
  if ($null -eq $metadata.webDav.liveSmoke) {
    throw "Release metadata JSON webDav.liveSmoke is missing."
  }
  Assert-WebDavLiveSmokeRecord `
    -Record $metadata.webDav.liveSmoke `
    -ExpectedProviderId "custom"
  foreach ($property in $WebDavLiveSmokeRecord.Keys) {
    $actualValue =
      $metadata.webDav.liveSmoke.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $WebDavLiveSmokeRecord[$property])) {
      throw "Release metadata JSON webDav.liveSmoke.$property does not match the WebDAV live smoke result."
    }
  }
  if ($null -eq $metadata.webDav.domesticLiveSmoke) {
    throw "Release metadata JSON webDav.domesticLiveSmoke is missing."
  }
  Assert-WebDavLiveSmokeRecord `
    -Record $metadata.webDav.domesticLiveSmoke `
    -ExpectedProviderId "jianguoyun"
  foreach ($property in $WebDavDomesticLiveSmokeRecord.Keys) {
    $actualValue =
      $metadata.webDav.domesticLiveSmoke.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $WebDavDomesticLiveSmokeRecord[$property])) {
      throw "Release metadata JSON webDav.domesticLiveSmoke.$property does not match the domestic WebDAV live smoke result."
    }
  }

  if ([int]$metadata.android.compileSdk -ne [int]$AndroidSdkConfig["compileSdk"] -or
      [int]$metadata.android.minSdk -ne [int]$AndroidSdkConfig["minSdk"] -or
      [int]$metadata.android.targetSdk -ne [int]$AndroidSdkConfig["targetSdk"] -or
      [string]$metadata.android.compatibility -ne [string]$AndroidSdkConfig["compatibility"] -or
      [string]$metadata.android.signing -ne $AndroidSigningMode) {
    throw "Release metadata JSON Android settings do not match the validated build configuration."
  }
  if ($null -eq $metadata.android.tools) {
    throw "Release metadata JSON android.tools is missing."
  }
  foreach ($property in @("apkAnalyzer", "aapt2")) {
    $actualValue = $metadata.android.tools.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $AndroidSdkTools[$property])) {
      throw "Release metadata JSON android.tools.$property does not match the validated Android SDK tool path."
    }
  }
  if ($null -eq $metadata.android.staticSmoke) {
    throw "Release metadata JSON android.staticSmoke is missing."
  }
  Assert-AndroidStaticSmokeRecord `
    -Record $metadata.android.staticSmoke `
    -AndroidSdkConfig $AndroidSdkConfig `
    -ExpectedApkPath $AndroidApkPath
  foreach ($property in $AndroidStaticSmokeRecord.Keys) {
    $actualValue =
      $metadata.android.staticSmoke.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $AndroidStaticSmokeRecord[$property])) {
      throw "Release metadata JSON android.staticSmoke.$property does not match the Android static smoke result."
    }
  }
  if ($null -eq $metadata.android.deviceSmoke) {
    throw "Release metadata JSON android.deviceSmoke is missing."
  }
  Assert-AndroidDeviceSmokeRecord `
    -Record $metadata.android.deviceSmoke `
    -ExpectedApkFileName ([IO.Path]::GetFileName($AndroidApkPath)) `
    -ExpectedApkPath $AndroidApkPath
  foreach ($property in $AndroidDeviceSmokeRecord.Keys) {
    $actualValue =
      $metadata.android.deviceSmoke.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $AndroidDeviceSmokeRecord[$property])) {
      throw "Release metadata JSON android.deviceSmoke.$property does not match the Android device smoke result."
    }
  }

  if ($null -eq $metadata.runtime) {
    throw "Release metadata JSON runtime is missing."
  }
  Assert-ReleaseMetadataStringSequence `
    -Name "runtime.supportedLanguages" `
    -Actual $metadata.runtime.supportedLanguages `
    -Expected $SupportedRuntimeLanguages

  if ([string]$metadata.packageResolution -ne $PackageResolution) {
    throw "Release metadata JSON packageResolution does not match the release run."
  }

  foreach ($property in @(
    "flutterFrameworkVersion",
    "flutterChannel",
    "flutterFrameworkRevision",
    "flutterEngineRevision",
    "dartSdkVersion"
  )) {
    $actualValue = $metadata.toolchain.PSObject.Properties[$property].Value
    if (-not (Test-ReleaseMetadataRecordValueEqual -PropertyName $property -Actual $actualValue -Expected $ToolchainInfo[$property])) {
      throw "Release metadata JSON toolchain.$property does not match the validated Flutter toolchain."
    }
  }

  Assert-ReleaseMetadataRecord `
    -Name "dependencyLock" `
    -Actual $metadata.dependencyLock `
    -Expected $DependencyLockRecord
  Assert-ReleaseMetadataRecord `
    -Name "releaseNotes" `
    -Actual $metadata.releaseNotes `
    -Expected $ReleaseNotesRecord
  Assert-ReleaseMetadataStringSequence `
    -Name "validation" `
    -Actual $metadata.validation `
    -Expected $ValidationExecuted
  Assert-ReleaseMetadataStringSequence `
    -Name "skippedValidation" `
    -Actual $metadata.skippedValidation `
    -Expected $ValidationSkipped
  Assert-ReleaseMetadataRecords `
    -Name "artifacts" `
    -Actual $metadata.artifacts `
    -Expected $ArtifactRecords
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

function Assert-PublishableReleaseQaOptions {
  param(
    [bool]$PublishGitHubRelease,
    [bool]$RunAndroidDeviceSmoke,
    [string]$AndroidDeviceSmokeResultJson,
    [string]$WindowsManualQaResultJson,
    [string]$WebDavLiveSmokeResultJson,
    [string]$WebDavDomesticLiveSmokeResultJson
  )

  if ($RunAndroidDeviceSmoke -and
      -not [string]::IsNullOrWhiteSpace($AndroidDeviceSmokeResultJson)) {
    throw "Use either -RunAndroidDeviceSmoke or -AndroidDeviceSmokeResultJson, not both."
  }

  if (-not $PublishGitHubRelease) {
    return
  }

  if ([string]::IsNullOrWhiteSpace($WindowsManualQaResultJson)) {
    throw "GitHub Release publishing requires Windows manual QA evidence. Pass -WindowsManualQaResultJson <path> with a passed scripts/windows_manual_qa.ps1 result."
  }
  if ([string]::IsNullOrWhiteSpace($WebDavLiveSmokeResultJson)) {
    throw "GitHub Release publishing requires generic WebDAV live smoke evidence. Pass -WebDavLiveSmokeResultJson <path> with a passed custom-provider scripts/webdav_live_smoke.ps1 result."
  }
  if ([string]::IsNullOrWhiteSpace($WebDavDomesticLiveSmokeResultJson)) {
    throw "GitHub Release publishing requires domestic WebDAV live smoke evidence. Pass -WebDavDomesticLiveSmokeResultJson <path> with a passed Jianguoyun scripts/webdav_live_smoke.ps1 result."
  }
  if (-not $RunAndroidDeviceSmoke -and
      [string]::IsNullOrWhiteSpace($AndroidDeviceSmokeResultJson)) {
    throw "GitHub Release publishing requires Android runtime smoke evidence. Pass -RunAndroidDeviceSmoke with an Android 14-17/API 34-37 device or emulator, or pass -AndroidDeviceSmokeResultJson <path> with a passed scripts/android_device_smoke.ps1 result."
  }
}

function Assert-PublishableReleaseQaRecords {
  param(
    [bool]$PublishGitHubRelease,
    [object]$WindowsManualQaRecord,
    [object]$WebDavLiveSmokeRecord,
    [object]$WebDavDomesticLiveSmokeRecord,
    [object]$AndroidDeviceSmokeRecord
  )

  if (-not $PublishGitHubRelease) {
    return
  }

  Assert-WindowsManualQaRecord -Record $WindowsManualQaRecord
  if ([string](Get-RecordPropertyValue -Record $WindowsManualQaRecord -Name "status") -ne
      "passed") {
    throw "GitHub Release publishing requires a passed Windows manual QA record."
  }
  Assert-WebDavLiveSmokeRecord `
    -Record $WebDavLiveSmokeRecord `
    -ExpectedProviderId "custom"
  if ([string](Get-RecordPropertyValue -Record $WebDavLiveSmokeRecord -Name "status") -ne
      "passed") {
    throw "GitHub Release publishing requires a passed generic WebDAV live smoke record."
  }
  Assert-WebDavLiveSmokeRecord `
    -Record $WebDavDomesticLiveSmokeRecord `
    -ExpectedProviderId "jianguoyun"
  if ([string](Get-RecordPropertyValue -Record $WebDavDomesticLiveSmokeRecord -Name "status") -ne
      "passed") {
    throw "GitHub Release publishing requires a passed domestic WebDAV live smoke record."
  }
  Assert-AndroidDeviceSmokeRecord `
    -Record $AndroidDeviceSmokeRecord `
    -ExpectedApkFileName ""
  if ([string](Get-RecordPropertyValue -Record $AndroidDeviceSmokeRecord -Name "status") -ne
      "passed") {
    throw "GitHub Release publishing requires a passed Android device smoke record."
  }
}

function Assert-GitHubAuthentication {
  $hasEnvironmentToken = -not [string]::IsNullOrWhiteSpace($env:GH_TOKEN) -or
    -not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  & gh auth status
  $authExitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorActionPreference
  if ($authExitCode -ne 0) {
    if ($hasEnvironmentToken) {
      throw 'GitHub Release publishing requires a valid GH_TOKEN or GITHUB_TOKEN for GitHub CLI. Refresh the token secret or unset it and run `gh auth refresh -h github.com` or `gh auth login -h github.com`, then rerun the release script.'
    }
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

function Assert-GitHubReleaseAssets {
  param(
    [string]$TagName,
    [string[]]$ArtifactPaths
  )

  $json = Invoke-NativeText "gh release view $TagName --json assets" {
    & gh release view $TagName --json assets
  }
  try {
    $release = $json | ConvertFrom-Json
  } catch {
    throw "GitHub Release asset metadata for '$TagName' could not be parsed: $($_.Exception.Message)"
  }

  if ($null -eq $release.assets) {
    throw "GitHub Release '$TagName' did not return an asset list."
  }
  $assets = @($release.assets)
  $expectedAssetNames = @(
    $ArtifactPaths | ForEach-Object {
      (Get-Item -LiteralPath $_).Name
    }
  )
  $unexpectedAssets = @(
    $assets | Where-Object {
      $expectedAssetNames -notcontains [string]$_.name
    } | ForEach-Object {
      [string]$_.name
    }
  )
  if ($unexpectedAssets.Count -gt 0) {
    throw "GitHub Release '$TagName' contains unexpected asset(s): $($unexpectedAssets -join ', '). Remove stale release assets before publishing can pass."
  }

  foreach ($path in $ArtifactPaths) {
    $item = Get-Item -LiteralPath $path
    $matches = @($assets | Where-Object { [string]$_.name -eq $item.Name })
    if ($matches.Count -ne 1) {
      throw "GitHub Release '$TagName' contains $($matches.Count) asset(s) named '$($item.Name)', expected exactly one."
    }
    $asset = $matches[0]
    $sizeProperty = $asset.PSObject.Properties["size"]
    if ($null -eq $sizeProperty) {
      throw "GitHub Release '$TagName' asset '$($item.Name)' is missing its size."
    }
    if ([int64]$sizeProperty.Value -ne [int64]$item.Length) {
      throw "GitHub Release '$TagName' asset '$($item.Name)' size does not match the packaged file."
    }
    $stateProperty = $asset.PSObject.Properties["state"]
    if ($null -eq $stateProperty -or
        [string]::IsNullOrWhiteSpace([string]$stateProperty.Value)) {
      throw "GitHub Release '$TagName' asset '$($item.Name)' is missing its upload state."
    }
    if ([string]$stateProperty.Value -ne "uploaded") {
      throw "GitHub Release '$TagName' asset '$($item.Name)' is not fully uploaded."
    }
  }
}

function Assert-GitHubReleaseDownloadedAssets {
  param(
    [string]$TagName,
    [string[]]$ArtifactPaths
  )

  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $downloadRoot =
    Join-Path $tempRoot "repapertodo-release-assets-$([Guid]::NewGuid().ToString("N"))"

  try {
    New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
    foreach ($path in $ArtifactPaths) {
      $item = Get-Item -LiteralPath $path
      Invoke-Native "gh release download $TagName $($item.Name)" {
        & gh release download $TagName `
          --pattern $item.Name `
          --dir $downloadRoot `
          --clobber
      }

      $downloadedPath = Join-Path $downloadRoot $item.Name
      Assert-FileExists `
        -Path $downloadedPath `
        -Message "Downloaded GitHub Release asset '$($item.Name)' was not found."

      $downloadedItem = Get-Item -LiteralPath $downloadedPath
      if ([int64]$downloadedItem.Length -ne [int64]$item.Length) {
        throw "Downloaded GitHub Release asset '$($item.Name)' size does not match the packaged file."
      }

      $expectedHash =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $item.FullName).Hash.ToLowerInvariant()
      $downloadedHash =
        (Get-FileHash -Algorithm SHA256 -LiteralPath $downloadedPath).Hash.ToLowerInvariant()
      if ($downloadedHash -ne $expectedHash) {
        throw "Downloaded GitHub Release asset '$($item.Name)' SHA-256 does not match the packaged file."
      }
    }
  } finally {
    if (Test-Path -LiteralPath $downloadRoot -PathType Container) {
      $resolvedDownloadRoot = [IO.Path]::GetFullPath($downloadRoot)
      if ($resolvedDownloadRoot.StartsWith(
          $tempRoot,
          [StringComparison]::OrdinalIgnoreCase
        )) {
        Remove-Item -LiteralPath $resolvedDownloadRoot -Recurse -Force
      }
    }
  }
}

function Format-ReleaseNotesCommandList {
  param([string[]]$Commands)

  if ($null -eq $Commands -or $Commands.Count -eq 0) {
    return "- none"
  }

  return (($Commands | ForEach-Object { "- $_" }) -join "`n")
}

function Get-ChangelogUnreleasedNotes {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return "- No user-facing changes recorded."
  }

  $lines = Get-Content -LiteralPath $Path
  $start = -1
  for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match "^##\s+Unreleased\s*$") {
      $start = $index + 1
      break
    }
  }

  if ($start -lt 0) {
    return "- No user-facing changes recorded."
  }

  $selected = New-Object System.Collections.Generic.List[string]
  for ($index = $start; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match "^##\s+" ) {
      break
    }
    $selected.Add($lines[$index])
  }

  $text = (($selected | ForEach-Object { $_.TrimEnd() }) -join "`n").Trim()
  if ([string]::IsNullOrWhiteSpace($text)) {
    return "- No user-facing changes recorded."
  }
  return $text
}

function New-ReleaseNotes {
  param(
    [string]$version,
    [string]$androidSigningMode,
    [bool]$dirtyWorkingTreeAllowed,
    [string]$packageResolution,
    [string]$flutterFrameworkVersion,
    [string]$flutterChannel,
    [string]$dartSdkVersion,
    [string]$userFacingChanges,
    [string[]]$supportedRuntimeLanguages,
    [string[]]$validationExecuted,
    [string[]]$validationSkipped,
    [object]$windowsSmokeRecord,
    [object]$windowsPolicySmokeRecord,
    [object]$windowsManualQaRecord,
    [object]$webDavSmokeRecord,
    [object]$webDavLiveSmokeRecord,
    [object]$webDavDomesticLiveSmokeRecord,
    [object]$androidStaticSmokeRecord,
    [object]$androidDeviceSmokeRecord
  )

  $validationExecutedText =
    Format-ReleaseNotesCommandList -Commands $validationExecuted
  $validationSkippedText =
    Format-ReleaseNotesCommandList -Commands $validationSkipped
  $windowsManualQaStatus =
    [string](Get-RecordPropertyValue -Record $windowsManualQaRecord -Name "status")
  $windowsManualQaCheckedAtUtc =
    [string](Get-RecordPropertyValue -Record $windowsManualQaRecord -Name "checkedAtUtc")
  $windowsManualQaSummary = if ($windowsManualQaStatus -eq "passed") {
    $windowsManualQaItems = @(Get-RecordPropertyValue -Record $windowsManualQaRecord -Name "items")
    "passed at $windowsManualQaCheckedAtUtc with $($windowsManualQaItems.Count) desktop parity item(s)"
  } elseif ($windowsManualQaStatus -eq "passedWithDeferredMultiMonitor") {
    "passed for a local release candidate at $windowsManualQaCheckedAtUtc with multi-monitor edge docking explicitly deferred ($([string](Get-RecordPropertyValue -Record $windowsManualQaRecord -Name "notes")))"
  } else {
    "skipped at $windowsManualQaCheckedAtUtc ($([string](Get-RecordPropertyValue -Record $windowsManualQaRecord -Name "reason")))"
  }
  $webDavLiveSmokeStatus =
    [string](Get-RecordPropertyValue -Record $webDavLiveSmokeRecord -Name "status")
  $webDavLiveSmokeCheckedAtUtc =
    [string](Get-RecordPropertyValue -Record $webDavLiveSmokeRecord -Name "checkedAtUtc")
  $webDavLiveSmokeSummary = if ($webDavLiveSmokeStatus -eq "passed") {
    "passed at $webDavLiveSmokeCheckedAtUtc against $([string](Get-RecordPropertyValue -Record $webDavLiveSmokeRecord -Name "endpointHost")) root $([string](Get-RecordPropertyValue -Record $webDavLiveSmokeRecord -Name "rootPath")); Android operations uploaded $([string](Get-RecordPropertyValue -Record $webDavLiveSmokeRecord -Name "androidOperationUploadedCount")); Windows operations applied $([string](Get-RecordPropertyValue -Record $webDavLiveSmokeRecord -Name "windowsOperationAppliedCount"))"
  } else {
    "skipped at $webDavLiveSmokeCheckedAtUtc ($([string](Get-RecordPropertyValue -Record $webDavLiveSmokeRecord -Name "reason")))"
  }
  $webDavDomesticLiveSmokeStatus =
    [string](Get-RecordPropertyValue -Record $webDavDomesticLiveSmokeRecord -Name "status")
  $webDavDomesticLiveSmokeCheckedAtUtc =
    [string](Get-RecordPropertyValue -Record $webDavDomesticLiveSmokeRecord -Name "checkedAtUtc")
  $webDavDomesticLiveSmokeSummary = if ($webDavDomesticLiveSmokeStatus -eq "passed") {
    "passed at $webDavDomesticLiveSmokeCheckedAtUtc against $([string](Get-RecordPropertyValue -Record $webDavDomesticLiveSmokeRecord -Name "endpointHost")) root $([string](Get-RecordPropertyValue -Record $webDavDomesticLiveSmokeRecord -Name "rootPath")); Android operations uploaded $([string](Get-RecordPropertyValue -Record $webDavDomesticLiveSmokeRecord -Name "androidOperationUploadedCount")); Windows operations applied $([string](Get-RecordPropertyValue -Record $webDavDomesticLiveSmokeRecord -Name "windowsOperationAppliedCount"))"
  } else {
    "skipped at $webDavDomesticLiveSmokeCheckedAtUtc ($([string](Get-RecordPropertyValue -Record $webDavDomesticLiveSmokeRecord -Name "reason")))"
  }
  $androidDeviceSmokeStatus =
    [string](Get-RecordPropertyValue -Record $androidDeviceSmokeRecord -Name "status")
  $androidDeviceSmokeCheckedAtUtc =
    [string](Get-RecordPropertyValue -Record $androidDeviceSmokeRecord -Name "checkedAtUtc")
  $androidDeviceSmokeSummary = if ($androidDeviceSmokeStatus -eq "passed") {
    "passed at $androidDeviceSmokeCheckedAtUtc on API $([string](Get-RecordPropertyValue -Record $androidDeviceSmokeRecord -Name "apiLevel")) device $([string](Get-RecordPropertyValue -Record $androidDeviceSmokeRecord -Name "deviceSerial")) with foreground package $([string](Get-RecordPropertyValue -Record $androidDeviceSmokeRecord -Name "foregroundPackage"))"
  } else {
    "skipped at $androidDeviceSmokeCheckedAtUtc ($([string](Get-RecordPropertyValue -Record $androidDeviceSmokeRecord -Name "reason")))"
  }

  return @"
Release build for RePaperTodo $version.

Artifacts:
- Windows x64 release zip containing repapertodo.exe and runtime files.
- Android release APK targeting Android 14-17 / API 34-37.
- SHA-256 checksums for release artifacts.
- Release metadata JSON with version, commit, Windows smoke, WebDAV smoke, Android SDK/signing, Android smoke, runtime language, validation, and artifact hashes.
- Release notes markdown used by GitHub Release publishing.

Android signing: $androidSigningMode.
Dirty working tree allowed: $dirtyWorkingTreeAllowed.
Package resolution: $packageResolution.
Runtime UI languages: $($supportedRuntimeLanguages -join ', ').
Flutter toolchain: Flutter $flutterFrameworkVersion ($flutterChannel), Dart $dartSdkVersion.

Verification summary:
- Windows smoke: $([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "status")); exe $([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "exeFileName")); persisted papers $([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "finalPaperCount")); independent visible HWNDs $([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "finalVisibleTopLevelWindowCount")); native geometry persistence $([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "geometryPersistenceVerified")); content-edit geometry stability $([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "contentEditGeometryStabilityVerified")); todo papers $([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "initialTodoPaperCount"))->$([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "finalTodoPaperCount")); note papers $([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "initialNotePaperCount"))->$([string](Get-RecordPropertyValue -Record $windowsSmokeRecord -Name "finalNotePaperCount")).
- Windows policy smoke: $([string](Get-RecordPropertyValue -Record $windowsPolicySmokeRecord -Name "status")); tray recovery $([string](Get-RecordPropertyValue -Record $windowsPolicySmokeRecord -Name "trayIconRecoveredAfterTaskbarCreated")); fullscreen avoidance $([string](Get-RecordPropertyValue -Record $windowsPolicySmokeRecord -Name "fullscreenAvoidance")); topmost restoration $([string](Get-RecordPropertyValue -Record $windowsPolicySmokeRecord -Name "fullscreenTopmostRestored")).
- Windows manual QA: $windowsManualQaSummary.
- WebDAV static smoke: $([string](Get-RecordPropertyValue -Record $webDavSmokeRecord -Name "status")); generic WebDAV $([string](Get-RecordPropertyValue -Record $webDavSmokeRecord -Name "genericWebDavSupported")); Jianguoyun preset $([string](Get-RecordPropertyValue -Record $webDavSmokeRecord -Name "jianguoyunPresetSupported")); operation logs $([string](Get-RecordPropertyValue -Record $webDavSmokeRecord -Name "operationLogsSupported")); Windows/Android round trip $([string](Get-RecordPropertyValue -Record $webDavSmokeRecord -Name "crossDeviceOperationRoundTripCovered")); local HTTP WebDAV protocol round trip $([string](Get-RecordPropertyValue -Record $webDavSmokeRecord -Name "localHttpWebDavRoundTripCovered")); Android background shared Dart sync path $([string](Get-RecordPropertyValue -Record $webDavSmokeRecord -Name "androidBackgroundSyncSharedDartPath")); Android background absolute state path gate $([string](Get-RecordPropertyValue -Record $webDavSmokeRecord -Name "androidBackgroundSyncAbsoluteStatePathCovered")); Android background data.json state path gate $([string](Get-RecordPropertyValue -Record $webDavSmokeRecord -Name "androidBackgroundSyncDataJsonStatePathCovered")).
- WebDAV generic live smoke: $webDavLiveSmokeSummary.
- WebDAV domestic live smoke: $webDavDomesticLiveSmokeSummary.
- Android static smoke: $([string](Get-RecordPropertyValue -Record $androidStaticSmokeRecord -Name "status")); APK application ID $([string](Get-RecordPropertyValue -Record $androidStaticSmokeRecord -Name "apkApplicationId")); minSdk $([string](Get-RecordPropertyValue -Record $androidStaticSmokeRecord -Name "minSdk")); targetSdk $([string](Get-RecordPropertyValue -Record $androidStaticSmokeRecord -Name "targetSdk")); debuggable $([string](Get-RecordPropertyValue -Record $androidStaticSmokeRecord -Name "debuggable")); launcher $([string](Get-RecordPropertyValue -Record $androidStaticSmokeRecord -Name "launcherActivity")); singleTop $([string](Get-RecordPropertyValue -Record $androidStaticSmokeRecord -Name "singleTopLaunchMode")); empty task affinity $([string](Get-RecordPropertyValue -Record $androidStaticSmokeRecord -Name "emptyTaskAffinity")); WorkManager background sync $([string](Get-RecordPropertyValue -Record $androidStaticSmokeRecord -Name "backgroundWorkManagerSystemJobService")).
- Android device smoke: $androidDeviceSmokeSummary.

User-facing changes:
$userFacingChanges

Validation executed:
$validationExecutedText

Validation skipped:
$validationSkippedText
"@
}

function Get-PackageResolutionMode {
  param(
    [bool]$SkipTests,
    [bool]$SkipBuild,
    [bool]$OfflinePubGet
  )

  if ($SkipTests -and $SkipBuild) {
    return "skipped (both -SkipTests and -SkipBuild were provided)"
  }
  if ($OfflinePubGet) {
    return "flutter pub get --offline"
  }
  return "flutter pub get"
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
$apkAnalyzerToolName = if ($IsWindows -or $env:OS -eq "Windows_NT") {
  "apkanalyzer.bat"
} else {
  "apkanalyzer"
}
$apkAnalyzer = Find-AndroidSdkTool -ToolName $apkAnalyzerToolName
$aapt2ToolName = if ($IsWindows -or $env:OS -eq "Windows_NT") {
  "aapt2.exe"
} else {
  "aapt2"
}
$aapt2 = Find-AndroidSdkTool -ToolName $aapt2ToolName
$androidSdkTools = [ordered]@{
  apkAnalyzer = $apkAnalyzer
  aapt2 = $aapt2
}
Assert-PublishableReleaseOptions `
  -PublishGitHubRelease $PublishGitHubRelease `
  -SkipTests $SkipTests `
  -SkipBuild $SkipBuild `
  -AllowDirty $AllowDirty `
  -AndroidSigningMode $androidSigningMode
Assert-PublishableReleaseQaOptions `
  -PublishGitHubRelease $PublishGitHubRelease `
  -RunAndroidDeviceSmoke $RunAndroidDeviceSmoke `
  -AndroidDeviceSmokeResultJson $AndroidDeviceSmokeResultJson `
  -WindowsManualQaResultJson $WindowsManualQaResultJson `
  -WebDavLiveSmokeResultJson $WebDavLiveSmokeResultJson `
  -WebDavDomesticLiveSmokeResultJson $WebDavDomesticLiveSmokeResultJson
if ($PublishGitHubRelease) {
  Assert-Command "gh"
  Assert-GitHubAuthentication
}

$version = Get-FlutterVersion
Assert-FlutterVersion -Version $version
$artifactVersion = Get-ReleaseArtifactVersion -Version $version
if ([string]::IsNullOrWhiteSpace($TagName)) {
  $TagName = "v$version"
}
if ([string]::IsNullOrWhiteSpace($ReleaseTitle)) {
  $ReleaseTitle = "RePaperTodo $version"
}
Assert-ReleaseTagName -TagName $TagName
Assert-ReleaseTitle -ReleaseTitle $ReleaseTitle
Assert-PublishTagMatchesVersion `
  -PublishGitHubRelease $PublishGitHubRelease `
  -TagName $TagName `
  -Version $version
$validatedRuntimeLanguages = Get-RuntimeSupportedLanguages -RepoRoot $repoRoot
Assert-RuntimeSupportedLanguages `
  -Actual $validatedRuntimeLanguages `
  -Expected $supportedRuntimeLanguages
$toolchainInfo = Get-FlutterToolchainInfo -Flutter $flutter
$packageResolution = Get-PackageResolutionMode `
  -SkipTests $SkipTests `
  -SkipBuild $SkipBuild `
  -OfflinePubGet $OfflinePubGet
Write-Host "Android signing mode: $androidSigningMode"
Write-Host "Android SDK config: compileSdk=$($androidSdkConfig["compileSdk"]), minSdk=$($androidSdkConfig["minSdk"]), targetSdk=$($androidSdkConfig["targetSdk"])"
Write-Host "Android APK analyzer: $apkAnalyzer"
Write-Host "Android AAPT2: $aapt2"
Write-Host "Flutter toolchain: Flutter $($toolchainInfo["flutterFrameworkVersion"]) ($($toolchainInfo["flutterChannel"])), Dart $($toolchainInfo["dartSdkVersion"])"
Write-Host "Runtime UI languages: $($validatedRuntimeLanguages -join ', ')"

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
$validationExecuted += "scripts/windows_smoke.ps1"
$validationExecuted += "scripts/windows_policy_smoke.ps1"
$validationExecuted += "scripts/webdav_smoke.ps1"
$validationExecuted += "scripts/android_smoke.ps1"
$androidDeviceSmokeRecord = [ordered]@{
  status = "skipped"
  checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  reason = "optional; pass -RunAndroidDeviceSmoke"
}
$windowsManualQaRecord = [ordered]@{
  status = "skipped"
  checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  reason = "optional; pass -WindowsManualQaResultJson <path>"
}
$webDavLiveSmokeRecord = [ordered]@{
  status = "skipped"
  checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  reason = "optional; pass -WebDavLiveSmokeResultJson <path>"
}
$webDavDomesticLiveSmokeRecord = [ordered]@{
  status = "skipped"
  checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  reason = "optional; pass -WebDavDomesticLiveSmokeResultJson <path>"
}
if ($RunAndroidDeviceSmoke) {
  $validationExecuted += "scripts/android_device_smoke.ps1"
} elseif (-not [string]::IsNullOrWhiteSpace($AndroidDeviceSmokeResultJson)) {
  $androidDeviceSmokeRecord =
    Read-ReleaseQaRecord `
      -Path $AndroidDeviceSmokeResultJson `
      -Context "Android device smoke"
  Assert-AndroidDeviceSmokeRecord `
    -Record $androidDeviceSmokeRecord `
    -ExpectedApkFileName ""
  $validationExecuted += "scripts/android_device_smoke.ps1 result: $AndroidDeviceSmokeResultJson"
} else {
  $validationSkipped += "scripts/android_device_smoke.ps1 (optional; pass -RunAndroidDeviceSmoke)"
}
if (-not [string]::IsNullOrWhiteSpace($WindowsManualQaResultJson)) {
  $windowsManualQaRecord =
    Read-ReleaseQaRecord `
      -Path $WindowsManualQaResultJson `
      -Context "Windows manual QA"
  Assert-WindowsManualQaRecord -Record $windowsManualQaRecord
  $validationExecuted += "scripts/windows_manual_qa.ps1 result: $WindowsManualQaResultJson"
} else {
  $validationSkipped += "scripts/windows_manual_qa.ps1 (optional; pass -WindowsManualQaResultJson <path>)"
}
if (-not [string]::IsNullOrWhiteSpace($WebDavLiveSmokeResultJson)) {
  $webDavLiveSmokeRecord =
    Read-ReleaseQaRecord `
      -Path $WebDavLiveSmokeResultJson `
      -Context "generic WebDAV live smoke"
  Assert-WebDavLiveSmokeRecord `
    -Record $webDavLiveSmokeRecord `
    -ExpectedProviderId "custom"
  $validationExecuted += "scripts/webdav_live_smoke.ps1 result: $WebDavLiveSmokeResultJson"
} else {
  $validationSkipped += "scripts/webdav_live_smoke.ps1 (optional; pass -WebDavLiveSmokeResultJson <path>)"
}
if (-not [string]::IsNullOrWhiteSpace($WebDavDomesticLiveSmokeResultJson)) {
  $webDavDomesticLiveSmokeRecord =
    Read-ReleaseQaRecord `
      -Path $WebDavDomesticLiveSmokeResultJson `
      -Context "domestic WebDAV live smoke"
  Assert-WebDavLiveSmokeRecord `
    -Record $webDavDomesticLiveSmokeRecord `
    -ExpectedProviderId "jianguoyun"
  $validationExecuted += "scripts/webdav_live_smoke.ps1 domestic result: $WebDavDomesticLiveSmokeResultJson"
} else {
  $validationSkipped += "scripts/webdav_live_smoke.ps1 domestic (optional; pass -WebDavDomesticLiveSmokeResultJson <path>)"
}

$dist = Join-Path $repoRoot "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$windowsSmokeResultFile =
  Join-Path $dist "repapertodo-$artifactVersion-windows-smoke.json"
$windowsPolicySmokeResultFile =
  Join-Path $dist "repapertodo-$artifactVersion-windows-policy-smoke.json"
$webDavSmokeResultFile =
  Join-Path $dist "repapertodo-$artifactVersion-webdav-smoke.json"
if (Test-Path -LiteralPath $windowsSmokeResultFile) {
  Remove-Item -LiteralPath $windowsSmokeResultFile -Force
}
if (Test-Path -LiteralPath $windowsPolicySmokeResultFile) {
  Remove-Item -LiteralPath $windowsPolicySmokeResultFile -Force
}
if (Test-Path -LiteralPath $webDavSmokeResultFile) {
  Remove-Item -LiteralPath $webDavSmokeResultFile -Force
}
$windowsSmokeRecord = [ordered]@{}
$windowsPolicySmokeRecord = [ordered]@{}
$webDavSmokeRecord = [ordered]@{}

Invoke-Step "Run Windows release smoke" {
  & (Join-Path $PSScriptRoot "windows_smoke.ps1") `
    -ReleaseDirectory (Join-Path $repoRoot "build\windows\x64\runner\Release") `
    -StartupTimeoutSeconds 120 `
    -ExitTimeoutSeconds 60 `
    -ResultJson $windowsSmokeResultFile
}

try {
  $windowsSmokeResult =
    Get-Content -Raw -LiteralPath $windowsSmokeResultFile |
    ConvertFrom-Json
} catch {
  throw "Windows smoke result JSON could not be parsed: $($_.Exception.Message)"
}
foreach ($property in $windowsSmokeResult.PSObject.Properties) {
  $windowsSmokeRecord[$property.Name] = $property.Value
}
Remove-Item -LiteralPath $windowsSmokeResultFile -Force

Invoke-Step "Run Windows policy smoke" {
  & (Join-Path $PSScriptRoot "windows_policy_smoke.ps1") `
    -ReleaseDirectory (Join-Path $repoRoot "build\windows\x64\runner\Release") `
    -StartupTimeoutSeconds 120 `
    -ExitTimeoutSeconds 60 `
    -ResultJson $windowsPolicySmokeResultFile
}

try {
  $windowsPolicySmokeResult =
    Get-Content -Raw -LiteralPath $windowsPolicySmokeResultFile |
    ConvertFrom-Json
} catch {
  throw "Windows policy smoke result JSON could not be parsed: $($_.Exception.Message)"
}
foreach ($property in $windowsPolicySmokeResult.PSObject.Properties) {
  $windowsPolicySmokeRecord[$property.Name] = $property.Value
}
Remove-Item -LiteralPath $windowsPolicySmokeResultFile -Force

Invoke-Step "Run WebDAV static smoke" {
  & (Join-Path $PSScriptRoot "webdav_smoke.ps1") `
    -ResultJson $webDavSmokeResultFile
}

try {
  $webDavSmokeResult =
    Get-Content -Raw -LiteralPath $webDavSmokeResultFile |
    ConvertFrom-Json
} catch {
  throw "WebDAV static smoke result JSON could not be parsed: $($_.Exception.Message)"
}
foreach ($property in $webDavSmokeResult.PSObject.Properties) {
  $webDavSmokeRecord[$property.Name] = $property.Value
}
Remove-Item -LiteralPath $webDavSmokeResultFile -Force

Invoke-Step "Verify release inputs stayed clean" {
  Assert-CleanGitTree
}

$userFacingChanges =
  Get-ChangelogUnreleasedNotes -Path (Join-Path $repoRoot "CHANGELOG.md")

New-Item -ItemType Directory -Force -Path $dist | Out-Null

$windowsReleaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$windowsReleaseExe = Join-Path $windowsReleaseDir "repapertodo.exe"
$windowsLauncherExe = Join-Path $windowsReleaseDir "repapertodo_launcher.exe"
$androidReleaseApkSource = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"
$windowsStagingDir = Join-Path $dist "repapertodo-windows-x64-$artifactVersion-staging"
$windowsZip = Join-Path $dist "repapertodo-windows-x64-$artifactVersion.zip"
$androidApk = Join-Path $dist "repapertodo-android-$artifactVersion.apk"
$androidStaticSmokeResultFile =
  Join-Path $dist "repapertodo-$artifactVersion-android-static-smoke.json"
$androidDeviceSmokeResultFile =
  Join-Path $dist "repapertodo-$artifactVersion-android-device-smoke.json"
$checksumsFile = Join-Path $dist "repapertodo-$artifactVersion-sha256.txt"
$metadataFile = Join-Path $dist "repapertodo-$artifactVersion-release.json"
$releaseNotesFile = Join-Path $dist "repapertodo-$artifactVersion-release-notes.md"

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
  if (Test-Path -LiteralPath $androidStaticSmokeResultFile) {
    Remove-Item -LiteralPath $androidStaticSmokeResultFile -Force
  }
  if (Test-Path -LiteralPath $androidDeviceSmokeResultFile) {
    Remove-Item -LiteralPath $androidDeviceSmokeResultFile -Force
  }
  if (Test-Path -LiteralPath $windowsSmokeResultFile) {
    Remove-Item -LiteralPath $windowsSmokeResultFile -Force
  }
  if (Test-Path -LiteralPath $webDavSmokeResultFile) {
    Remove-Item -LiteralPath $webDavSmokeResultFile -Force
  }
  if (Test-Path -LiteralPath $metadataFile) {
    Remove-Item -LiteralPath $metadataFile -Force
  }
  if (Test-Path -LiteralPath $releaseNotesFile) {
    Remove-Item -LiteralPath $releaseNotesFile -Force
  }
  Assert-PathExists `
    -Path $windowsReleaseDir `
    -Message "Windows release build output was not found. Run without -SkipBuild to create it."
  Assert-FileExists `
    -Path $windowsReleaseExe `
    -Message "Windows release executable was not found. Run without -SkipBuild to create it."
  Assert-FileExists `
    -Path $windowsLauncherExe `
    -Message "Windows release launcher was not found. Run without -SkipBuild to create it."
  foreach ($windowsRuntimeLibrary in @(
    "msvcp140.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "ucrtbase.dll"
  )) {
    Assert-FileExists `
      -Path (Join-Path $windowsReleaseDir $windowsRuntimeLibrary) `
      -Message "Windows release runtime dependency was not found: $windowsRuntimeLibrary"
  }
  Assert-WindowsManualQaRecord `
    -Record $windowsManualQaRecord `
    -ExpectedExePath $windowsReleaseExe `
    -ExpectedAppSoPath (Join-Path $windowsReleaseDir "data\app.so")
  Assert-FileExists `
    -Path $androidReleaseApkSource `
    -Message "Android release APK was not found. Run without -SkipBuild to create it."
  Assert-FileExtension `
    -Path $androidReleaseApkSource `
    -ExpectedExtension ".apk" `
    -Message "Android release artifact must be an .apk file. Run without -SkipBuild to create it."
  if (Test-Path -LiteralPath $windowsStagingDir) {
    Remove-Item -LiteralPath $windowsStagingDir -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $windowsStagingDir | Out-Null
  $windowsRuntimeStagingDir = Join-Path $windowsStagingDir "runtime"
  New-Item -ItemType Directory -Force -Path $windowsRuntimeStagingDir | Out-Null
  Copy-Item `
    -LiteralPath $windowsLauncherExe `
    -Destination (Join-Path $windowsStagingDir "repapertodo.exe") `
    -Force
  Get-ChildItem -LiteralPath $windowsReleaseDir -Force |
    Where-Object { $_.Name -ne "repapertodo_launcher.exe" } |
    Copy-Item `
    -Destination $windowsRuntimeStagingDir `
    -Recurse `
    -Force
  Move-Item `
    -LiteralPath (Join-Path $windowsRuntimeStagingDir "repapertodo.exe") `
    -Destination (Join-Path $windowsRuntimeStagingDir "repapertodo.runtime.exe") `
    -Force
  Remove-WindowsRuntimeStateFiles -StagingDirectory $windowsStagingDir
  try {
    New-ZipFromDirectory `
      -SourceDirectory $windowsStagingDir `
      -DestinationPath $windowsZip
  } finally {
    Remove-Item -LiteralPath $windowsStagingDir -Recurse -Force
  }
  Assert-ZipEntriesSafe `
    -ZipPath $windowsZip `
    -Message "Windows release zip contains unsafe entry paths."
  Assert-WindowsZipRootLayout -ZipPath $windowsZip
  Assert-ZipContainsExactFile `
    -ZipPath $windowsZip `
    -FileName "repapertodo.exe" `
    -Message "Windows release zip does not contain repapertodo.exe."
  Assert-ZipContainsExactFile `
    -ZipPath $windowsZip `
    -FileName "runtime/repapertodo.runtime.exe" `
    -Message "Windows release zip does not contain runtime/repapertodo.runtime.exe."
  Assert-ZipContainsExactFile `
    -ZipPath $windowsZip `
    -FileName "runtime/flutter_windows.dll" `
    -Message "Windows release zip does not contain runtime/flutter_windows.dll."
  foreach ($windowsRuntimeLibrary in @(
    "msvcp140.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "ucrtbase.dll"
  )) {
    Assert-ZipContainsExactFile `
      -ZipPath $windowsZip `
      -FileName "runtime/$windowsRuntimeLibrary" `
      -Message "Windows release zip does not contain runtime/$windowsRuntimeLibrary."
  }
  Assert-ZipContainsExactFile `
    -ZipPath $windowsZip `
    -FileName "runtime/data/app.so" `
    -Message "Windows release zip does not contain runtime/data/app.so."
  Assert-ZipContainsExactFile `
    -ZipPath $windowsZip `
    -FileName "runtime/data/icudtl.dat" `
    -Message "Windows release zip does not contain runtime/data/icudtl.dat."
  Assert-ZipContainsExactFile `
    -ZipPath $windowsZip `
    -FileName "runtime/data/flutter_assets/FontManifest.json" `
    -Message "Windows release zip does not contain Flutter asset files."
  foreach ($runtimeStateFile in @(
    "data.json",
    "data.backup.json",
    "data.crash_recovery.json",
    "data.json.tmp",
    "RePaperTodo.crash.log",
    "fullscreen-debug.log"
  )) {
    Assert-ZipDoesNotContainFile `
      -ZipPath $windowsZip `
      -FileName $runtimeStateFile `
      -Message "Windows release zip must not contain runtime state file '$runtimeStateFile'."
  }
  foreach ($runtimeStatePattern in @(
    "*.tmp",
    "*.failed_load.*",
    "*.used_for_recovery.*"
  )) {
    Assert-ZipDoesNotContainFilePattern `
      -ZipPath $windowsZip `
      -Pattern $runtimeStatePattern `
      -Message "Windows release zip must not contain runtime state files matching '$runtimeStatePattern'."
  }
  Copy-Item `
    -LiteralPath $androidReleaseApkSource `
    -Destination $androidApk
  Assert-ZipEntriesSafe `
    -ZipPath $androidApk `
    -Message "Android release APK contains unsafe entry paths."
  Assert-ZipContainsFile `
    -ZipPath $androidApk `
    -FileName "AndroidManifest.xml" `
    -Message "Android release APK does not contain AndroidManifest.xml."
  Assert-ZipContainsFile `
    -ZipPath $androidApk `
    -FileName "assets/flutter_assets/AssetManifest.bin" `
    -Message "Android release APK does not contain Flutter asset manifest."
  Assert-ZipContainsFile `
    -ZipPath $androidApk `
    -FileName "assets/flutter_assets/FontManifest.json" `
    -Message "Android release APK does not contain Flutter font manifest."
  Assert-ZipContainsFilePattern `
    -ZipPath $androidApk `
    -Pattern "lib/*/libapp.so" `
    -Message "Android release APK does not contain a Flutter app native library."
  Assert-ZipContainsFilePattern `
    -ZipPath $androidApk `
    -Pattern "lib/*/libflutter.so" `
    -Message "Android release APK does not contain a Flutter engine native library."
  Assert-AndroidApkSdkCompatibility `
    -ApkPath $androidApk `
    -SdkConfig $androidSdkConfig `
    -ApkAnalyzer $apkAnalyzer
  & (Join-Path $PSScriptRoot "android_smoke.ps1") `
    -ApkPath $androidApk `
    -ApkAnalyzer $apkAnalyzer `
    -Aapt2 $aapt2 `
    -ExpectedMinSdk $androidSdkConfig["minSdk"] `
    -ExpectedTargetSdk $androidSdkConfig["targetSdk"] `
    -ExpectedCompileSdk $androidSdkConfig["compileSdk"] `
    -ResultJson $androidStaticSmokeResultFile
  try {
    $androidStaticSmokeResult =
      Get-Content -Raw -LiteralPath $androidStaticSmokeResultFile |
      ConvertFrom-Json
  } catch {
    throw "Android static smoke result JSON could not be parsed: $($_.Exception.Message)"
  }
  $androidStaticSmokeRecord = [ordered]@{}
  foreach ($property in $androidStaticSmokeResult.PSObject.Properties) {
    $androidStaticSmokeRecord[$property.Name] = $property.Value
  }
  Remove-Item -LiteralPath $androidStaticSmokeResultFile -Force
  if ($RunAndroidDeviceSmoke) {
    $androidDeviceSmokeArgs = @{
      ApkPath = $androidApk
      ResultJson = $androidDeviceSmokeResultFile
    }
    if (-not [string]::IsNullOrWhiteSpace($AndroidDeviceSerial)) {
      $androidDeviceSmokeArgs["DeviceSerial"] = $AndroidDeviceSerial
    }
    & (Join-Path $PSScriptRoot "android_device_smoke.ps1") `
      @androidDeviceSmokeArgs
    try {
      $androidDeviceSmokeResult =
        Get-Content -Raw -LiteralPath $androidDeviceSmokeResultFile |
        ConvertFrom-Json
    } catch {
      throw "Android device smoke result JSON could not be parsed: $($_.Exception.Message)"
    }
    $androidDeviceSmokeRecord = [ordered]@{}
    foreach ($property in $androidDeviceSmokeResult.PSObject.Properties) {
      $androidDeviceSmokeRecord[$property.Name] = $property.Value
    }
    Remove-Item -LiteralPath $androidDeviceSmokeResultFile -Force
  }
  Assert-AndroidDeviceSmokeRecord `
    -Record $androidDeviceSmokeRecord `
    -ExpectedApkFileName ([IO.Path]::GetFileName($androidApk)) `
    -ExpectedApkPath $androidApk
  Assert-PublishableReleaseQaRecords `
    -PublishGitHubRelease $PublishGitHubRelease `
    -WindowsManualQaRecord $windowsManualQaRecord `
    -WebDavLiveSmokeRecord $webDavLiveSmokeRecord `
    -WebDavDomesticLiveSmokeRecord $webDavDomesticLiveSmokeRecord `
    -AndroidDeviceSmokeRecord $androidDeviceSmokeRecord

  $releaseNotes = New-ReleaseNotes `
    -Version $version `
    -AndroidSigningMode $androidSigningMode `
    -DirtyWorkingTreeAllowed $AllowDirty `
    -PackageResolution $packageResolution `
    -FlutterFrameworkVersion $toolchainInfo["flutterFrameworkVersion"] `
    -FlutterChannel $toolchainInfo["flutterChannel"] `
    -DartSdkVersion $toolchainInfo["dartSdkVersion"] `
    -UserFacingChanges $userFacingChanges `
    -SupportedRuntimeLanguages $validatedRuntimeLanguages `
    -ValidationExecuted $validationExecuted `
    -ValidationSkipped $validationSkipped `
    -WindowsSmokeRecord $windowsSmokeRecord `
    -WindowsPolicySmokeRecord $windowsPolicySmokeRecord `
    -WindowsManualQaRecord $windowsManualQaRecord `
    -WebDavSmokeRecord $webDavSmokeRecord `
    -WebDavLiveSmokeRecord $webDavLiveSmokeRecord `
    -WebDavDomesticLiveSmokeRecord $webDavDomesticLiveSmokeRecord `
    -AndroidStaticSmokeRecord $androidStaticSmokeRecord `
    -AndroidDeviceSmokeRecord $androidDeviceSmokeRecord

  $releaseNotes |
    Set-Content -LiteralPath $releaseNotesFile -Encoding ascii
  Assert-FileExists `
    -Path $releaseNotesFile `
    -Message "Release notes file was not created."
  if ((Get-Item -LiteralPath $releaseNotesFile).Length -le 0) {
    throw "Release notes file must not be empty."
  }
  $releaseNotesItem = Get-Item -LiteralPath $releaseNotesFile
  $releaseNotesHash =
    Get-FileHash -Algorithm SHA256 -LiteralPath $releaseNotesFile
  $releaseNotesRecord = [ordered]@{
    fileName = $releaseNotesItem.Name
    bytes = $releaseNotesItem.Length
    sha256 = $releaseNotesHash.Hash.ToLowerInvariant()
  }

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
  $pubspecLockPath = Join-Path $repoRoot "pubspec.lock"
  Assert-PathExists `
    -Path $pubspecLockPath `
    -Message "pubspec.lock was not found. Run Flutter package resolution before packaging."
  $pubspecLockItem = Get-Item -LiteralPath $pubspecLockPath
  $pubspecLockHash = Get-FileHash -Algorithm SHA256 -LiteralPath $pubspecLockPath
  $dependencyLockRecord = [ordered]@{
    fileName = $pubspecLockItem.Name
    bytes = $pubspecLockItem.Length
    sha256 = $pubspecLockHash.Hash.ToLowerInvariant()
  }

  [ordered]@{
    version = $version
    tagName = $TagName
    gitCommit = $gitCommit
    dirtyWorkingTreeAllowed = [bool]$AllowDirty
    builtAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    windows = [ordered]@{
      smoke = $windowsSmokeRecord
      policySmoke = $windowsPolicySmokeRecord
      manualQa = $windowsManualQaRecord
    }
    webDav = [ordered]@{
      staticSmoke = $webDavSmokeRecord
      liveSmoke = $webDavLiveSmokeRecord
      domesticLiveSmoke = $webDavDomesticLiveSmokeRecord
    }
    android = [ordered]@{
      compileSdk = $androidSdkConfig["compileSdk"]
      minSdk = $androidSdkConfig["minSdk"]
      targetSdk = $androidSdkConfig["targetSdk"]
      compatibility = $androidSdkConfig["compatibility"]
      signing = $androidSigningMode
      tools = $androidSdkTools
      staticSmoke = $androidStaticSmokeRecord
      deviceSmoke = $androidDeviceSmokeRecord
    }
    runtime = [ordered]@{
      supportedLanguages = $validatedRuntimeLanguages
    }
    packageResolution = $packageResolution
    toolchain = $toolchainInfo
    dependencyLock = $dependencyLockRecord
    releaseNotes = $releaseNotesRecord
    validation = $validationExecuted
    skippedValidation = $validationSkipped
    artifacts = $artifactRecords
  } |
    ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $metadataFile -Encoding ascii
  Assert-ReleaseMetadataFile `
    -RepoRoot $repoRoot `
    -MetadataFile $metadataFile `
    -Version $version `
    -TagName $TagName `
    -GitCommit $gitCommit `
    -DirtyWorkingTreeAllowed $AllowDirty `
    -AndroidSdkConfig $androidSdkConfig `
    -AndroidSigningMode $androidSigningMode `
    -AndroidSdkTools $androidSdkTools `
    -AndroidApkPath $androidApk `
    -WindowsSmokeRecord $windowsSmokeRecord `
    -WindowsPolicySmokeRecord $windowsPolicySmokeRecord `
    -WindowsManualQaRecord $windowsManualQaRecord `
    -WebDavSmokeRecord $webDavSmokeRecord `
    -WebDavLiveSmokeRecord $webDavLiveSmokeRecord `
    -WebDavDomesticLiveSmokeRecord $webDavDomesticLiveSmokeRecord `
    -AndroidStaticSmokeRecord $androidStaticSmokeRecord `
    -AndroidDeviceSmokeRecord $androidDeviceSmokeRecord `
    -SupportedRuntimeLanguages $validatedRuntimeLanguages `
    -PackageResolution $packageResolution `
    -ToolchainInfo $toolchainInfo `
    -DependencyLockRecord $dependencyLockRecord `
    -ReleaseNotesRecord $releaseNotesRecord `
    -ValidationExecuted $validationExecuted `
    -ValidationSkipped $validationSkipped `
    -ArtifactRecords $artifactRecords

  $metadataItem = Get-Item -LiteralPath $metadataFile
  $metadataHash = Get-FileHash -Algorithm SHA256 -LiteralPath $metadataFile
  $releasePackageRecords = $artifactRecords + [ordered]@{
    fileName = $metadataItem.Name
    bytes = $metadataItem.Length
    sha256 = $metadataHash.Hash.ToLowerInvariant()
  } + $releaseNotesRecord

  $releasePackageRecords |
    ForEach-Object { "$($_.sha256)  $($_.fileName)" } |
    Set-Content -LiteralPath $checksumsFile -Encoding ascii
  Assert-ReleaseChecksumFile `
    -ChecksumsFile $checksumsFile `
    -ArtifactDirectory $dist `
    -Records $releasePackageRecords
}

Get-Item -LiteralPath $windowsZip, $androidApk, $checksumsFile, $metadataFile, $releaseNotesFile |
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
          --notes-file $releaseNotesFile
      }
      Invoke-Native "gh release upload $TagName" {
        & gh release upload $TagName $windowsZip $androidApk $checksumsFile $metadataFile $releaseNotesFile --clobber
      }
    } else {
      Invoke-Native "gh release create $TagName" {
        & gh release create $TagName $windowsZip $androidApk $checksumsFile $metadataFile $releaseNotesFile `
          --target $gitCommit `
          --title $ReleaseTitle `
          --notes-file $releaseNotesFile
      }
    }
    Assert-GitHubReleaseAssets `
      -TagName $TagName `
      -ArtifactPaths @(
        $windowsZip,
        $androidApk,
        $checksumsFile,
        $metadataFile,
        $releaseNotesFile
      )
    Assert-GitHubReleaseDownloadedAssets `
      -TagName $TagName `
      -ArtifactPaths @(
        $windowsZip,
        $androidApk,
        $checksumsFile,
        $metadataFile,
        $releaseNotesFile
      )
  }
}
