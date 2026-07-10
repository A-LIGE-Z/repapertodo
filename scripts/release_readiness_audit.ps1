param(
  [string]$WindowsManualQaResultJson = "",
  [string]$ExpectedWindowsReleaseDirectory = "",
  [string]$WebDavLiveSmokeResultJson = "",
  [string]$WebDavDomesticLiveSmokeResultJson = "",
  [string]$AndroidDeviceSmokeResultJson = "",
  [string]$ExpectedAndroidApkFileName = "",
  [string]$ExpectedAndroidApkPath = "",
  [string]$ReleaseMetadataJson = "",
  [Alias("ReleaseChecksumsPath")]
  [string]$ReleaseChecksumsFile = "",
  [string]$ResultJson = "",
  [switch]$FailOnBlocked
)

$ErrorActionPreference = "Stop"

function Resolve-ResultJsonPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Release readiness audit result JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "Release readiness audit result JSON path must not contain wildcard characters."
  }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path)
  } catch {
    throw "Release readiness audit result JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($fullPath))) {
    throw "Release readiness audit result JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -ne ".json") {
    throw "Release readiness audit result JSON path must use the .json extension."
  }
  return $fullPath
}

function Resolve-InputJsonPath {
  param(
    [string]$Path,
    [string]$Context
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "$Context JSON path was not provided."
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "$Context JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "$Context JSON path must not contain wildcard characters."
  }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path)
  } catch {
    throw "$Context JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($fullPath))) {
    throw "$Context JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -ne ".json") {
    throw "$Context JSON path must use the .json extension."
  }
  return $fullPath
}

function New-Check {
  param(
    [string]$Id,
    [string]$Status,
    [string]$Summary
  )

  [ordered]@{
    id = $Id
    status = $Status
    summary = $Summary
  }
}

function Add-Check {
  param(
    [string]$Id,
    [string]$Status,
    [string]$Summary
  )

  $script:checks.Add((New-Check -Id $Id -Status $Status -Summary $Summary)) |
    Out-Null
  if ($Status -eq "blocked") {
    $script:blockers.Add($Summary) | Out-Null
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
  $property = $Record.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Read-JsonRecord {
  param(
    [string]$Path,
    [string]$Context
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "$Context JSON path was not provided."
  }
  $fullPath = Resolve-InputJsonPath -Path $Path -Context $Context
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "$Context JSON was not found: $fullPath"
  }
  try {
    return Get-Content -Raw -LiteralPath $fullPath | ConvertFrom-Json
  } catch {
    throw "$Context JSON could not be parsed: $($_.Exception.Message)"
  }
}

function Test-UtcTimestamp {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }
  try {
    $timestamp = [DateTimeOffset]::Parse($Value)
    return $timestamp.Offset -eq [TimeSpan]::Zero
  } catch {
    return $false
  }
}

function Get-RuntimeSupportedLanguages {
  param([string]$RepoRoot)

  $stringsFile = Join-Path $RepoRoot "lib\src\ui\papertodo_strings.dart"
  if (-not (Test-Path -LiteralPath $stringsFile -PathType Leaf)) {
    throw "Runtime localization file was not found."
  }
  $content = Get-Content -Raw -LiteralPath $stringsFile
  $match = [regex]::Match(
    $content,
    "static\s+const\s+supportedLocales\s*=\s*\[(?<body>.*?)\];",
    [Text.RegularExpressions.RegexOptions]::Singleline
  )
  if (-not $match.Success) {
    throw "Runtime localization file does not declare supportedLocales."
  }
  return @(
    [regex]::Matches($match.Groups["body"].Value, "Locale\('(?<language>[^']+)'\)") |
      ForEach-Object { $_.Groups["language"].Value }
  )
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

function Get-FlutterExecutable {
  param([string]$RepoRoot)

  $puroConfig = Join-Path $RepoRoot ".puro.json"
  if (Test-Path -LiteralPath $puroConfig -PathType Leaf) {
    try {
      $puro = Get-Content -Raw -LiteralPath $puroConfig | ConvertFrom-Json
      $envName = [string](Get-RecordPropertyValue -Record $puro -Name "env")
      if (-not [string]::IsNullOrWhiteSpace($envName)) {
        $puroFlutter = Join-Path $HOME ".puro\envs\$envName\flutter\bin\flutter.bat"
        if (Test-Path -LiteralPath $puroFlutter -PathType Leaf) {
          return $puroFlutter
        }
      }
    } catch {
      throw "Unable to read .puro.json for Flutter toolchain audit: $($_.Exception.Message)"
    }
  }

  $command = Get-Command "flutter" -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }
  throw "Flutter executable was not found for release metadata toolchain audit."
}

function Get-FlutterToolchainInfo {
  param([string]$RepoRoot)

  $flutter = Get-FlutterExecutable -RepoRoot $RepoRoot
  $json = Invoke-NativeText "flutter --version --machine" {
    & $flutter --version --machine
  }
  try {
    $raw = $json | ConvertFrom-Json
  } catch {
    throw "Unable to parse Flutter toolchain metadata from 'flutter --version --machine': $($_.Exception.Message)"
  }

  $result = [ordered]@{}
  foreach ($property in @(
    "frameworkVersion",
    "channel",
    "frameworkRevision",
    "engineRevision",
    "dartSdkVersion"
  )) {
    if ([string]::IsNullOrWhiteSpace([string](Get-RecordPropertyValue -Record $raw -Name $property))) {
      throw "Flutter toolchain metadata is missing '$property'."
    }
  }

  $result["flutterFrameworkVersion"] = [string]$raw.frameworkVersion
  $result["flutterChannel"] = [string]$raw.channel
  $result["flutterFrameworkRevision"] = [string]$raw.frameworkRevision
  $result["flutterEngineRevision"] = [string]$raw.engineRevision
  $result["dartSdkVersion"] = [string]$raw.dartSdkVersion
  return $result
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

function Test-AndroidStoreFileValue {
  param([string]$StoreFile)

  if ([string]::IsNullOrWhiteSpace($StoreFile)) {
    return $false
  }
  if ($StoreFile -match "[\x00-\x1F\x7F-\x9F]" -or
      [IO.Path]::IsPathRooted($StoreFile) -or
      $StoreFile.Contains("*") -or
      $StoreFile.Contains("?")) {
    return $false
  }
  foreach ($segment in ($StoreFile -split "[\\/]+")) {
    if ($segment -eq "." -or $segment -eq "..") {
      return $false
    }
  }
  return $true
}

function Get-AndroidSigningMode {
  param([string]$RepoRoot)

  $keyProperties = Join-Path $RepoRoot "android\key.properties"
  if (-not (Test-Path -LiteralPath $keyProperties -PathType Leaf)) {
    return "debug fallback (android/key.properties not found)"
  }

  $content = Get-Content -LiteralPath $keyProperties
  $values = @{}
  foreach ($key in @("storeFile", "storePassword", "keyAlias", "keyPassword")) {
    $values[$key] = Get-AndroidKeyProperty -Content $content -Key $key
    if ([string]::IsNullOrWhiteSpace($values[$key]) -or
        $values[$key] -match "[\x00-\x1F\x7F-\x9F]") {
      return "debug fallback (android/key.properties is incomplete)"
    }
  }

  if (-not (Test-AndroidStoreFileValue -StoreFile $values["storeFile"])) {
    return "debug fallback (android/key.properties storeFile is invalid)"
  }
  $storeFile = $values["storeFile"]
  $keystorePath = [IO.Path]::GetFullPath(
    (Join-Path (Join-Path $RepoRoot "android") $storeFile)
  )
  if (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
    return "debug fallback (android/key.properties storeFile not found)"
  }
  return "release keystore from android/key.properties"
}

function Test-CleanGitTree {
  param([string]$RepoRoot)

  Push-Location $RepoRoot
  try {
    $status = & git status --porcelain=v1 --untracked-files=all
    if ($LASTEXITCODE -ne 0) {
      throw "git status --porcelain failed with exit code $LASTEXITCODE."
    }
    return @($status).Count -eq 0
  } finally {
    Pop-Location
  }
}

function Test-WindowsManualQaRecord {
  param(
    [object]$Record,
    [string]$ExpectedWindowsReleaseDirectory = ""
  )

  if (([string](Get-RecordPropertyValue -Record $Record -Name "status")) -ne
      "passed") {
    return "Windows manual QA evidence must have status passed."
  }
  if (-not (Test-UtcTimestamp -Value ([string](Get-RecordPropertyValue -Record $Record -Name "checkedAtUtc")))) {
    return "Windows manual QA evidence must include a UTC checkedAtUtc timestamp."
  }
  if ([bool](Get-RecordPropertyValue -Record $Record -Name "allowSkipped") -ne
      $false) {
    return "Windows manual QA evidence must not use -AllowSkipped."
  }
  if ([string]::IsNullOrWhiteSpace(
      [string](Get-RecordPropertyValue -Record $Record -Name "tester"))) {
    return "Windows manual QA evidence must include a tester."
  }
  if ([string]::IsNullOrWhiteSpace(
      [string](Get-RecordPropertyValue -Record $Record -Name "windowsVersion"))) {
    return "Windows manual QA evidence must include windowsVersion."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "exeFileName") -ne
      "repapertodo.exe") {
    return "Windows manual QA evidence must reference repapertodo.exe."
  }
  foreach ($property in @("exeBytes", "appSoBytes")) {
    $value = Get-RecordPropertyValue -Record $Record -Name $property
    if (-not ($value -is [byte] -or
        $value -is [sbyte] -or
        $value -is [int16] -or
        $value -is [uint16] -or
        $value -is [int32] -or
        $value -is [uint32] -or
        $value -is [int64]) -or [int64]$value -le 0) {
      return "Windows manual QA evidence must include positive $property."
    }
  }
  foreach ($property in @("exeSha256", "appSoSha256")) {
    if ([string](Get-RecordPropertyValue -Record $Record -Name $property) -cnotmatch
        '^[0-9a-f]{64}$') {
      return "Windows manual QA evidence must include lowercase SHA-256 $property."
    }
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "appSoRelativePath") -ne
      "data/app.so") {
    return "Windows manual QA evidence must reference data/app.so."
  }
  $recordReleaseDirectory =
    [string](Get-RecordPropertyValue -Record $Record -Name "releaseDirectory")
  if ([string]::IsNullOrWhiteSpace($recordReleaseDirectory)) {
    return "Windows manual QA evidence must include releaseDirectory."
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedWindowsReleaseDirectory)) {
    $releaseDirectory = [IO.Path]::GetFullPath($ExpectedWindowsReleaseDirectory)
    if (-not (Test-Path -LiteralPath $releaseDirectory -PathType Container)) {
      return "Windows manual QA expected release directory was not found: $releaseDirectory"
    }
    $recordReleaseDirectoryFullPath =
      [IO.Path]::GetFullPath($recordReleaseDirectory)
    if ($recordReleaseDirectoryFullPath -ne $releaseDirectory) {
      return "Windows manual QA evidence releaseDirectory must match the expected release directory."
    }
    $exePath = Join-Path $releaseDirectory "repapertodo.exe"
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
      return "Windows manual QA expected release exe was not found: $exePath"
    }
    $appSoPath = Join-Path $releaseDirectory "data\app.so"
    if (-not (Test-Path -LiteralPath $appSoPath -PathType Leaf)) {
      return "Windows manual QA expected data/app.so was not found: $appSoPath"
    }
    $exeItem = Get-Item -LiteralPath $exePath
    if ([int64](Get-RecordPropertyValue -Record $Record -Name "exeBytes") -ne
        [int64]$exeItem.Length) {
      return "Windows manual QA evidence exe byte count must match the expected release build."
    }
    $exeHashRecord = Get-FileHash -Algorithm SHA256 -LiteralPath $exePath
    $exeHash = $exeHashRecord.Hash.ToLowerInvariant()
    if ([string](Get-RecordPropertyValue -Record $Record -Name "exeSha256") -ne
        $exeHash) {
      return "Windows manual QA evidence exe SHA-256 must match the expected release build."
    }
    $appSoItem = Get-Item -LiteralPath $appSoPath
    if ([int64](Get-RecordPropertyValue -Record $Record -Name "appSoBytes") -ne
        [int64]$appSoItem.Length) {
      return "Windows manual QA evidence data/app.so byte count must match the expected release build."
    }
    $appSoHashRecord =
      Get-FileHash -Algorithm SHA256 -LiteralPath $appSoPath
    $appSoHash = $appSoHashRecord.Hash.ToLowerInvariant()
    if ([string](Get-RecordPropertyValue -Record $Record -Name "appSoSha256") -ne
        $appSoHash) {
      return "Windows manual QA evidence data/app.so SHA-256 must match the expected release build."
    }
  }
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
    return "Windows manual QA evidence must include exactly $($expectedIds.Count) checked items."
  }
  foreach ($id in $expectedIds) {
    $matches = @($items | Where-Object { [string]$_.id -eq $id })
    if ($matches.Count -ne 1 -or [string]$matches[0].status -ne "pass") {
      return "Windows manual QA item '$id' must be present and pass."
    }
  }
  return ""
}

function Test-WebDavLiveSmokeRecord {
  param(
    [object]$Record,
    [string]$ExpectedProviderId
  )

  if (([string](Get-RecordPropertyValue -Record $Record -Name "status")) -ne
      "passed") {
    return "WebDAV live smoke evidence must have status passed."
  }
  if (-not (Test-UtcTimestamp -Value ([string](Get-RecordPropertyValue -Record $Record -Name "checkedAtUtc")))) {
    return "WebDAV live smoke evidence must include a UTC checkedAtUtc timestamp."
  }
  if (-not (Test-UtcTimestamp -Value ([string](Get-RecordPropertyValue -Record $Record -Name "startedAtUtc")))) {
    return "WebDAV live smoke evidence must include a UTC startedAtUtc timestamp."
  }
  foreach ($property in @("endpointHost", "providerId", "rootPath")) {
    if ([string]::IsNullOrWhiteSpace(
        [string](Get-RecordPropertyValue -Record $Record -Name $property))) {
      return "WebDAV live smoke evidence must include $property."
    }
  }
  $rootPath = [string](Get-RecordPropertyValue -Record $Record -Name "rootPath")
  $normalizedRootPath = $rootPath -replace "\\", "/"
  if ($normalizedRootPath.StartsWith("/") -or
      $normalizedRootPath -match "^[A-Za-z]:" -or
      -not $normalizedRootPath.Contains("/run-") -or
      $normalizedRootPath -match "[\x00-\x1F\x7F-\x9F]") {
    return "WebDAV live smoke evidence rootPath must be a relative run-scoped path."
  }
  foreach ($segment in ($normalizedRootPath -split "/")) {
    if ([string]::IsNullOrWhiteSpace($segment) -or
        $segment -ne $segment.Trim() -or
        $segment -eq "." -or
        $segment -eq "..") {
      return "WebDAV live smoke evidence rootPath must be a relative run-scoped path."
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedProviderId) -and
      [string](Get-RecordPropertyValue -Record $Record -Name "providerId") -ne
      $ExpectedProviderId) {
    return "WebDAV live smoke evidence must use providerId $ExpectedProviderId."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "windowsUploadStatus") -ne
      "uploaded") {
    return "WebDAV live smoke evidence must confirm Windows upload."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "androidDownloadStatus") -ne
      "downloaded") {
    return "WebDAV live smoke evidence must confirm Android download."
  }
  if ([int](Get-RecordPropertyValue -Record $Record -Name "androidOperationUploadedCount") -lt 1) {
    return "WebDAV live smoke evidence must include at least one Android operation upload."
  }
  if ([int](Get-RecordPropertyValue -Record $Record -Name "windowsOperationAppliedCount") -lt 1) {
    return "WebDAV live smoke evidence must include at least one Windows operation merge."
  }
  $deviceSequences = Get-RecordPropertyValue -Record $Record -Name "deviceSequences"
  if ($null -eq $deviceSequences) {
    return "WebDAV live smoke evidence must include deviceSequences."
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
      return "WebDAV live smoke evidence must include a positive $deviceId device sequence."
    }
  }
  $cleanup = [string](Get-RecordPropertyValue -Record $Record -Name "remoteCleanup")
  if ($cleanup -ne "attempted" -and $cleanup -ne "skipped") {
    return "WebDAV live smoke evidence remoteCleanup must be attempted or skipped."
  }
  return ""
}

function Test-AndroidDeviceSmokeRecord {
  param(
    [object]$Record,
    [string]$ExpectedApkFileName,
    [string]$ExpectedApkPath = "",
    [string]$ArtifactVersion = ""
  )

  if (([string](Get-RecordPropertyValue -Record $Record -Name "status")) -ne
      "passed") {
    return "Android device smoke evidence must have status passed."
  }
  if (-not (Test-UtcTimestamp -Value ([string](Get-RecordPropertyValue -Record $Record -Name "checkedAtUtc")))) {
    return "Android device smoke evidence must include a UTC checkedAtUtc timestamp."
  }
  $packageName = [string](Get-RecordPropertyValue -Record $Record -Name "packageName")
  $apkApplicationId =
    [string](Get-RecordPropertyValue -Record $Record -Name "apkApplicationId")
  if ($packageName -ne "com.aligez.repapertodo" -or
      $apkApplicationId -ne $packageName) {
    return "Android device smoke evidence must launch com.aligez.repapertodo."
  }
  $apiLevel = [int](Get-RecordPropertyValue -Record $Record -Name "apiLevel")
  $minSupportedApi =
    [int](Get-RecordPropertyValue -Record $Record -Name "minSupportedApi")
  $maxSupportedApi =
    [int](Get-RecordPropertyValue -Record $Record -Name "maxSupportedApi")
  if ($minSupportedApi -ne 34 -or $maxSupportedApi -ne 37 -or
      $apiLevel -lt 34 -or $apiLevel -gt 37) {
    return "Android device smoke evidence must be from Android 14-17/API 34-37."
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
      return "Android device smoke evidence must include $property."
    }
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "foregroundPackage") -ne
      $packageName) {
    return "Android device smoke evidence must show RePaperTodo in the foreground."
  }
  $processId = [string](Get-RecordPropertyValue -Record $Record -Name "processId")
  if ($processId -cnotmatch '^\d+$' -or [int64]$processId -le 0) {
    return "Android device smoke evidence must include a positive integer processId."
  }
  $apkFileName = [string](Get-RecordPropertyValue -Record $Record -Name "apkFileName")
  if ([string]::IsNullOrWhiteSpace($apkFileName) -or
      [IO.Path]::GetExtension($apkFileName) -ine ".apk") {
    return "Android device smoke evidence must reference an APK file name."
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedApkFileName) -and
      $apkFileName -ne $ExpectedApkFileName) {
    return "Android device smoke evidence must match the expected APK file name."
  }
  if (-not [string]::IsNullOrWhiteSpace($ArtifactVersion)) {
    $versionedApkFileName = "repapertodo-android-$ArtifactVersion.apk"
    if ([string]::IsNullOrWhiteSpace($ExpectedApkFileName) -or
        $ExpectedApkFileName -ne $versionedApkFileName) {
      return "Android device smoke expected APK file name must match pubspec.yaml version."
    }
    if ($apkFileName -ne $versionedApkFileName) {
      return "Android device smoke evidence APK file name must match pubspec.yaml version."
    }
  }
  $apkBytes = Get-RecordPropertyValue -Record $Record -Name "apkBytes"
  if (-not ($apkBytes -is [byte] -or
      $apkBytes -is [sbyte] -or
      $apkBytes -is [int16] -or
      $apkBytes -is [uint16] -or
      $apkBytes -is [int32] -or
      $apkBytes -is [uint32] -or
      $apkBytes -is [int64]) -or [int64]$apkBytes -le 0) {
    return "Android device smoke evidence must include positive apkBytes."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "apkSha256") -cnotmatch
      '^[0-9a-f]{64}$') {
    return "Android device smoke evidence must include lowercase SHA-256 apkSha256."
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedApkPath)) {
    $expectedApkFullPath = [IO.Path]::GetFullPath($ExpectedApkPath)
    if (-not (Test-Path -LiteralPath $expectedApkFullPath -PathType Leaf)) {
      return "Android device smoke expected APK was not found: $expectedApkFullPath"
    }
    if ([IO.Path]::GetExtension($expectedApkFullPath).ToLowerInvariant() -ne
        ".apk") {
      return "Android device smoke expected APK path must reference an APK file."
    }
    if (-not [string]::IsNullOrWhiteSpace($ArtifactVersion) -and
        [IO.Path]::GetFileName($expectedApkFullPath) -ne
          "repapertodo-android-$ArtifactVersion.apk") {
      return "Android device smoke expected APK path must match pubspec.yaml version."
    }
    $expectedApk = Get-Item -LiteralPath $expectedApkFullPath
    if ([int64]$apkBytes -ne [int64]$expectedApk.Length) {
      return "Android device smoke evidence APK byte count must match the expected APK."
    }
    $expectedApkHashRecord =
      Get-FileHash -Algorithm SHA256 -LiteralPath $expectedApkFullPath
    $expectedApkHash = $expectedApkHashRecord.Hash.ToLowerInvariant()
    if ([string](Get-RecordPropertyValue -Record $Record -Name "apkSha256") -ne
        $expectedApkHash) {
      return "Android device smoke evidence APK SHA-256 must match the expected APK."
    }
  }
  return ""
}

function Test-StringSequence {
  param(
    [object]$Actual,
    [string[]]$Expected
  )

  $actualValues = @($Actual | ForEach-Object { [string]$_ })
  if ($actualValues.Count -ne $Expected.Count) {
    return $false
  }
  for ($index = 0; $index -lt $Expected.Count; $index++) {
    if ($actualValues[$index] -ne $Expected[$index]) {
      return $false
    }
  }
  return $true
}

function Get-PubspecVersion {
  param([string]$RepoRoot)

  $pubspecPath = Join-Path $RepoRoot "pubspec.yaml"
  if (-not (Test-Path -LiteralPath $pubspecPath -PathType Leaf)) {
    throw "pubspec.yaml was not found for release metadata audit."
  }
  $pubspec = Get-Content -LiteralPath $pubspecPath
  $versionLine =
    $pubspec |
      Where-Object { $_ -match "^\s*version:\s*(?<version>\S+)\s*$" } |
      Select-Object -First 1
  if ($null -eq $versionLine) {
    throw "pubspec.yaml does not declare a version."
  }
  $match = [regex]::Match($versionLine, "^\s*version:\s*(?<version>\S+)\s*$")
  return $match.Groups["version"].Value
}

function Get-ReleaseArtifactVersion {
  param([string]$Version)

  if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "Release artifact version cannot be blank."
  }
  return $Version -replace "\+", "-"
}

function Test-ReleaseArtifactRecords {
  param(
    [object]$Records,
    [string]$MetadataDirectory,
    [string]$ArtifactVersion
  )

  $items = @($Records)
  if ($items.Count -lt 2) {
    return "Release metadata must include Windows and Android artifact records."
  }
  foreach ($expectedExtension in @(".zip", ".apk")) {
    $matches = @($items | Where-Object {
        [IO.Path]::GetExtension([string]$_.fileName).ToLowerInvariant() -eq
          $expectedExtension
      })
    if ($matches.Count -lt 1) {
      return "Release metadata must include a $expectedExtension artifact record."
    }
  }
  $expectedFileNames = @(
    "repapertodo-windows-x64-$ArtifactVersion.zip",
    "repapertodo-android-$ArtifactVersion.apk"
  )
  foreach ($expectedFileName in $expectedFileNames) {
    $matches = @($items | Where-Object {
        [string](Get-RecordPropertyValue -Record $_ -Name "fileName") -eq
          $expectedFileName
      })
    if ($matches.Count -ne 1) {
      return "Release metadata artifacts must include exactly one '$expectedFileName' record."
    }
  }
  foreach ($item in $items) {
    $fileName = [string]$item.fileName
    if ([string]::IsNullOrWhiteSpace($fileName) -or
        $fileName -ne [IO.Path]::GetFileName($fileName)) {
      return "Release metadata artifact file names must be safe leaf names."
    }
    $bytes = Get-RecordPropertyValue -Record $item -Name "bytes"
    if (-not ($bytes -is [byte] -or
        $bytes -is [sbyte] -or
        $bytes -is [int16] -or
        $bytes -is [uint16] -or
        $bytes -is [int32] -or
        $bytes -is [uint32] -or
        $bytes -is [int64]) -or [int64]$bytes -le 0) {
      return "Release metadata artifact records must include positive byte counts."
    }
    if ([string]$item.sha256 -cnotmatch '^[0-9a-f]{64}$') {
      return "Release metadata artifact records must include lowercase SHA-256 hashes."
    }
    $artifactPath = Join-Path $MetadataDirectory $fileName
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
      return "Release metadata artifact file was not found: $artifactPath"
    }
    $artifact = Get-Item -LiteralPath $artifactPath
    if ([int64]$bytes -ne [int64]$artifact.Length) {
      return "Release metadata artifact '$fileName' byte count must match the file."
    }
    $artifactHashRecord =
      Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath
    $artifactHash = $artifactHashRecord.Hash.ToLowerInvariant()
    if ([string]$item.sha256 -ne $artifactHash) {
      return "Release metadata artifact '$fileName' SHA-256 must match the file."
    }
  }
  return ""
}

function Test-ReleaseFileRecord {
  param(
    [object]$Record,
    [string]$Directory,
    [string]$ExpectedFileName,
    [string]$Context
  )

  if ($null -eq $Record) {
    return "Release metadata must include $Context."
  }
  $fileName = [string](Get-RecordPropertyValue -Record $Record -Name "fileName")
  if ([string]::IsNullOrWhiteSpace($fileName) -or
      $fileName -ne [IO.Path]::GetFileName($fileName)) {
    return "Release metadata $Context file name must be a safe leaf name."
  }
  if ($fileName -ne $ExpectedFileName) {
    return "Release metadata $Context file name must match pubspec.yaml version."
  }
  $bytes = Get-RecordPropertyValue -Record $Record -Name "bytes"
  if (-not ($bytes -is [byte] -or
      $bytes -is [sbyte] -or
      $bytes -is [int16] -or
      $bytes -is [uint16] -or
      $bytes -is [int32] -or
      $bytes -is [uint32] -or
      $bytes -is [int64]) -or [int64]$bytes -le 0) {
    return "Release metadata $Context must include a positive byte count."
  }
  $sha256 = [string](Get-RecordPropertyValue -Record $Record -Name "sha256")
  if ($sha256 -cnotmatch '^[0-9a-f]{64}$') {
    return "Release metadata $Context must include a lowercase SHA-256 hash."
  }
  $path = Join-Path $Directory $fileName
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return "Release metadata $Context file was not found: $path"
  }
  $item = Get-Item -LiteralPath $path
  if ([int64]$bytes -ne [int64]$item.Length) {
    return "Release metadata $Context byte count must match the file."
  }
  $hashRecord = Get-FileHash -Algorithm SHA256 -LiteralPath $path
  if ($sha256 -ne $hashRecord.Hash.ToLowerInvariant()) {
    return "Release metadata $Context SHA-256 must match the file."
  }
  return ""
}

function Test-ReleaseMetadataRecord {
  param(
    [object]$Record,
    [string]$MetadataFile,
    [string]$RepoRoot
  )

  if (-not (Test-UtcTimestamp -Value ([string](Get-RecordPropertyValue -Record $Record -Name "builtAtUtc")))) {
    return "Release metadata must include a UTC builtAtUtc timestamp."
  }
  try {
    $pubspecVersion = Get-PubspecVersion -RepoRoot $RepoRoot
    $artifactVersion = Get-ReleaseArtifactVersion -Version $pubspecVersion
  } catch {
    return $_.Exception.Message
  }
  $metadataFileName =
    [IO.Path]::GetFileName([IO.Path]::GetFullPath($MetadataFile))
  if ($metadataFileName -ne "repapertodo-$artifactVersion-release.json") {
    return "Release metadata JSON file name must match pubspec.yaml version."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "version") -ne
      $pubspecVersion) {
    return "Release metadata version must match pubspec.yaml."
  }
  if ([string](Get-RecordPropertyValue -Record $Record -Name "tagName") -ne
      "v$pubspecVersion") {
    return "Release metadata tagName must match pubspec.yaml version."
  }
  if ($null -eq $Record.toolchain) {
    return "Release metadata must include Flutter toolchain information."
  }
  try {
    $toolchainInfo = Get-FlutterToolchainInfo -RepoRoot $RepoRoot
  } catch {
    return $_.Exception.Message
  }
  foreach ($property in @(
    "flutterFrameworkVersion",
    "flutterChannel",
    "flutterFrameworkRevision",
    "flutterEngineRevision",
    "dartSdkVersion"
  )) {
    $actualValue =
      [string](Get-RecordPropertyValue -Record $Record.toolchain -Name $property)
    if ([string]::IsNullOrWhiteSpace($actualValue)) {
      return "Release metadata toolchain.$property must not be blank."
    }
    if ($actualValue -cne [string]$toolchainInfo[$property]) {
      return "Release metadata toolchain.$property must match the current Flutter toolchain."
    }
  }
  if ($null -eq $Record.dependencyLock) {
    return "Release metadata must include dependencyLock."
  }
  $dependencyLockFileName =
    [string](Get-RecordPropertyValue -Record $Record.dependencyLock -Name "fileName")
  if ($dependencyLockFileName -ne "pubspec.lock") {
    return "Release metadata dependencyLock must reference pubspec.lock."
  }
  $pubspecLockPath = Join-Path $RepoRoot "pubspec.lock"
  if (-not (Test-Path -LiteralPath $pubspecLockPath -PathType Leaf)) {
    return "pubspec.lock was not found for release metadata audit."
  }
  $dependencyLockBytes =
    Get-RecordPropertyValue -Record $Record.dependencyLock -Name "bytes"
  if (-not ($dependencyLockBytes -is [byte] -or
      $dependencyLockBytes -is [sbyte] -or
      $dependencyLockBytes -is [int16] -or
      $dependencyLockBytes -is [uint16] -or
      $dependencyLockBytes -is [int32] -or
      $dependencyLockBytes -is [uint32] -or
      $dependencyLockBytes -is [int64]) -or
      [int64]$dependencyLockBytes -le 0) {
    return "Release metadata dependencyLock must include a positive byte count."
  }
  $dependencyLockSha256 =
    [string](Get-RecordPropertyValue -Record $Record.dependencyLock -Name "sha256")
  if ($dependencyLockSha256 -cnotmatch '^[0-9a-f]{64}$') {
    return "Release metadata dependencyLock must include a lowercase SHA-256 hash."
  }
  $pubspecLockItem = Get-Item -LiteralPath $pubspecLockPath
  if ([int64]$dependencyLockBytes -ne [int64]$pubspecLockItem.Length) {
    return "Release metadata dependencyLock byte count must match pubspec.lock."
  }
  $pubspecLockHashRecord =
    Get-FileHash -Algorithm SHA256 -LiteralPath $pubspecLockPath
  if ($dependencyLockSha256 -ne $pubspecLockHashRecord.Hash.ToLowerInvariant()) {
    return "Release metadata dependencyLock SHA-256 must match pubspec.lock."
  }
  if ($null -eq $Record.runtime -or
      -not (Test-StringSequence `
        -Actual $Record.runtime.supportedLanguages `
        -Expected @("zh", "en"))) {
    return "Release metadata runtime.supportedLanguages must be exactly zh,en."
  }
  if ($null -eq $Record.windows -or
      $null -eq $Record.windows.smoke -or
      [string]$Record.windows.smoke.status -ne "passed" -or
      [string]$Record.windows.smoke.exeFileName -ne "repapertodo.exe") {
    return "Release metadata must include passed Windows smoke evidence for repapertodo.exe."
  }
  if ($null -eq $Record.webDav -or
      $null -eq $Record.webDav.staticSmoke -or
      [string]$Record.webDav.staticSmoke.status -ne "passed") {
    return "Release metadata must include passed WebDAV static smoke evidence."
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
    if ([bool](Get-RecordPropertyValue -Record $Record.webDav.staticSmoke -Name $property) -ne $true) {
      return "Release metadata WebDAV static smoke must confirm $property."
    }
  }
  if ($null -eq $Record.android -or
      [int]$Record.android.minSdk -ne 34 -or
      [int]$Record.android.targetSdk -ne 37 -or
      [int]$Record.android.compileSdk -ne 37) {
    return "Release metadata Android SDK fields must target Android 14-17/API 34-37."
  }
  if ($null -eq $Record.android.staticSmoke -or
      [string]$Record.android.staticSmoke.status -ne "passed" -or
      [string]$Record.android.staticSmoke.applicationId -ne
        "com.aligez.repapertodo" -or
      [bool]$Record.android.staticSmoke.forbiddenLocalizedResourceConfigurationsAbsent -ne
        $true -or
      [bool]$Record.android.staticSmoke.androidLocaleConfigPresent -ne
        $true -or
      -not (Test-StringSequence `
        -Actual $Record.android.staticSmoke.expectedResourceLanguages `
        -Expected @("zh", "en")) -or
      -not (Test-StringSequence `
        -Actual $Record.android.staticSmoke.localeConfigLanguages `
        -Expected @("zh", "en"))) {
    return "Release metadata Android static smoke must pass with only zh,en localized resources and localeConfig."
  }
  $metadataDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($MetadataFile))
  if ([string]::IsNullOrWhiteSpace($metadataDirectory)) {
    $metadataDirectory = [IO.Directory]::GetCurrentDirectory()
  }
  $releaseNotesIssue = Test-ReleaseFileRecord `
    -Record $Record.releaseNotes `
    -Directory $metadataDirectory `
    -ExpectedFileName "repapertodo-$artifactVersion-release-notes.md" `
    -Context "releaseNotes"
  if (-not [string]::IsNullOrWhiteSpace($releaseNotesIssue)) {
    return $releaseNotesIssue
  }
  $artifactIssue = Test-ReleaseArtifactRecords `
    -Records $Record.artifacts `
    -MetadataDirectory $metadataDirectory `
    -ArtifactVersion $artifactVersion
  if (-not [string]::IsNullOrWhiteSpace($artifactIssue)) {
    return $artifactIssue
  }
  return ""
}

function Test-ReleaseChecksumsFile {
  param(
    [string]$ChecksumsFile,
    [object]$MetadataRecord,
    [string]$MetadataFile
  )

  if ([string]::IsNullOrWhiteSpace($MetadataFile) -or $null -eq $MetadataRecord) {
    return "Release checksum audit requires -ReleaseMetadataJson."
  }
  $checksumsPath = [IO.Path]::GetFullPath($ChecksumsFile)
  if (-not (Test-Path -LiteralPath $checksumsPath -PathType Leaf)) {
    return "Release checksum file was not found: $checksumsPath"
  }
  try {
    $artifactVersion =
      Get-ReleaseArtifactVersion -Version ([string](Get-RecordPropertyValue -Record $MetadataRecord -Name "version"))
  } catch {
    return $_.Exception.Message
  }
  $checksumFileName = [IO.Path]::GetFileName($checksumsPath)
  if ($checksumFileName -ne "repapertodo-$artifactVersion-sha256.txt") {
    return "Release checksum file name must match release metadata version."
  }
  $metadataPath = [IO.Path]::GetFullPath($MetadataFile)
  if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    return "Release metadata JSON was not found for checksum audit: $metadataPath"
  }
  $artifactDirectory = Split-Path -Parent $checksumsPath
  if ([string]::IsNullOrWhiteSpace($artifactDirectory)) {
    $artifactDirectory = [IO.Directory]::GetCurrentDirectory()
  }
  $metadataItem = Get-Item -LiteralPath $metadataPath
  $metadataHashRecord = Get-FileHash -Algorithm SHA256 -LiteralPath $metadataPath
  $records = New-Object System.Collections.Generic.List[object]
  foreach ($artifactRecord in @($MetadataRecord.artifacts)) {
    $records.Add($artifactRecord) | Out-Null
  }
  $records.Add([pscustomobject]@{
      fileName = $metadataItem.Name
      bytes = $metadataItem.Length
      sha256 = $metadataHashRecord.Hash.ToLowerInvariant()
    }) | Out-Null
  if ($null -eq $MetadataRecord.releaseNotes) {
    return "Release metadata must include releaseNotes for checksum audit."
  }
  $records.Add($MetadataRecord.releaseNotes) | Out-Null

  $expectedLines = @()
  foreach ($record in @($records.ToArray())) {
    $fileName = [string](Get-RecordPropertyValue -Record $record -Name "fileName")
    if ([string]::IsNullOrWhiteSpace($fileName) -or
        $fileName -ne [IO.Path]::GetFileName($fileName)) {
      return "Release checksum records must use safe leaf file names."
    }
    $bytes = Get-RecordPropertyValue -Record $record -Name "bytes"
    if (-not ($bytes -is [byte] -or
        $bytes -is [sbyte] -or
        $bytes -is [int16] -or
        $bytes -is [uint16] -or
        $bytes -is [int32] -or
        $bytes -is [uint32] -or
        $bytes -is [int64]) -or [int64]$bytes -le 0) {
      return "Release checksum records must include positive byte counts."
    }
    $sha256 = [string](Get-RecordPropertyValue -Record $record -Name "sha256")
    if ($sha256 -cnotmatch '^[0-9a-f]{64}$') {
      return "Release checksum records must include lowercase SHA-256 hashes."
    }
    $artifactPath = Join-Path $artifactDirectory $fileName
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
      return "Release checksum file references missing artifact '$fileName'."
    }
    $artifact = Get-Item -LiteralPath $artifactPath
    if ([int64]$bytes -ne [int64]$artifact.Length) {
      return "Release checksum artifact '$fileName' byte count must match the file."
    }
    $artifactHashRecord = Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath
    if ($sha256 -ne $artifactHashRecord.Hash.ToLowerInvariant()) {
      return "Release checksum artifact '$fileName' SHA-256 must match the file."
    }
    $expectedLines += "$sha256  $fileName"
  }

  $actualLines = @(Get-Content -LiteralPath $checksumsPath)
  if ($actualLines.Count -ne $expectedLines.Count) {
    return "Release checksum file must contain $($expectedLines.Count) line(s); found $($actualLines.Count)."
  }
  for ($index = 0; $index -lt $expectedLines.Count; $index++) {
    if ($actualLines[$index] -ne $expectedLines[$index]) {
      return "Release checksum file line $($index + 1) must match the release metadata record."
    }
  }
  return ""
}

$resultJsonFullPath = Resolve-ResultJsonPath -Path $ResultJson
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$checks = New-Object System.Collections.Generic.List[object]
$blockers = New-Object System.Collections.Generic.List[string]

try {
  $languages = Get-RuntimeSupportedLanguages -RepoRoot $repoRoot
  if (($languages -join ",") -eq "zh,en") {
    Add-Check "runtimeLanguages" "passed" "Runtime UI languages are limited to zh and en."
  } else {
    Add-Check "runtimeLanguages" "blocked" "Runtime UI languages must be exactly zh,en; actual: $($languages -join ',')."
  }
} catch {
  Add-Check "runtimeLanguages" "blocked" $_.Exception.Message
}

$releaseMetadataRecord = $null
if ([string]::IsNullOrWhiteSpace($ReleaseMetadataJson)) {
  Add-Check "releaseMetadata" "skipped" "Release metadata JSON was not provided."
} else {
  try {
    $releaseMetadataRecord = Read-JsonRecord `
      -Path $ReleaseMetadataJson `
      -Context "release metadata"
    $issue = Test-ReleaseMetadataRecord `
      -Record $releaseMetadataRecord `
      -MetadataFile $ReleaseMetadataJson `
      -RepoRoot $repoRoot
    if ([string]::IsNullOrWhiteSpace($issue)) {
      Add-Check "releaseMetadata" "passed" "Release metadata pins zh,en runtime and static smoke evidence."
    } else {
      Add-Check "releaseMetadata" "blocked" $issue
    }
  } catch {
    Add-Check "releaseMetadata" "blocked" $_.Exception.Message
  }
}

if ([string]::IsNullOrWhiteSpace($ReleaseChecksumsFile)) {
  Add-Check "releaseChecksums" "skipped" "Release checksum file was not provided."
} else {
  try {
    $issue = Test-ReleaseChecksumsFile `
      -ChecksumsFile $ReleaseChecksumsFile `
      -MetadataRecord $releaseMetadataRecord `
      -MetadataFile $ReleaseMetadataJson
    if ([string]::IsNullOrWhiteSpace($issue)) {
      Add-Check "releaseChecksums" "passed" "Release checksum file matches metadata and packaged files."
    } else {
      Add-Check "releaseChecksums" "blocked" $issue
    }
  } catch {
    Add-Check "releaseChecksums" "blocked" $_.Exception.Message
  }
}

$signingMode = Get-AndroidSigningMode -RepoRoot $repoRoot
if ($signingMode -eq "release keystore from android/key.properties") {
  Add-Check "androidSigning" "passed" $signingMode
} else {
  Add-Check "androidSigning" "blocked" "Android release publishing requires a release keystore; current mode: $signingMode."
}

try {
  if (Test-CleanGitTree -RepoRoot $repoRoot) {
    Add-Check "cleanGitTree" "passed" "Working tree is clean."
  } else {
    Add-Check "cleanGitTree" "blocked" "GitHub Release publishing requires a clean working tree."
  }
} catch {
  Add-Check "cleanGitTree" "blocked" $_.Exception.Message
}

try {
  $record = Read-JsonRecord `
    -Path $WindowsManualQaResultJson `
    -Context "Windows manual QA"
  $issue = Test-WindowsManualQaRecord `
    -Record $record `
    -ExpectedWindowsReleaseDirectory $ExpectedWindowsReleaseDirectory
  if ([string]::IsNullOrWhiteSpace($issue)) {
    Add-Check "windowsManualQa" "passed" "Windows manual QA evidence is publishable."
  } else {
    Add-Check "windowsManualQa" "blocked" $issue
  }
} catch {
  Add-Check "windowsManualQa" "blocked" $_.Exception.Message
}

try {
  $record = Read-JsonRecord `
    -Path $WebDavLiveSmokeResultJson `
    -Context "generic WebDAV live smoke"
  $issue = Test-WebDavLiveSmokeRecord `
    -Record $record `
    -ExpectedProviderId "custom"
  if ([string]::IsNullOrWhiteSpace($issue)) {
    Add-Check "webDavLiveSmoke" "passed" "Generic WebDAV live evidence is publishable."
  } else {
    Add-Check "webDavLiveSmoke" "blocked" $issue
  }
} catch {
  Add-Check "webDavLiveSmoke" "blocked" $_.Exception.Message
}

try {
  $record = Read-JsonRecord `
    -Path $WebDavDomesticLiveSmokeResultJson `
    -Context "domestic WebDAV live smoke"
  $issue = Test-WebDavLiveSmokeRecord `
    -Record $record `
    -ExpectedProviderId "jianguoyun"
  if ([string]::IsNullOrWhiteSpace($issue)) {
    Add-Check "webDavDomesticLiveSmoke" "passed" "Domestic WebDAV live evidence is publishable."
  } else {
    Add-Check "webDavDomesticLiveSmoke" "blocked" $issue
  }
} catch {
  Add-Check "webDavDomesticLiveSmoke" "blocked" $_.Exception.Message
}

try {
  $record = Read-JsonRecord `
    -Path $AndroidDeviceSmokeResultJson `
    -Context "Android device smoke"
  $artifactVersion =
    Get-ReleaseArtifactVersion -Version (Get-PubspecVersion -RepoRoot $repoRoot)
  $issue = Test-AndroidDeviceSmokeRecord `
    -Record $record `
    -ExpectedApkFileName $ExpectedAndroidApkFileName `
    -ExpectedApkPath $ExpectedAndroidApkPath `
    -ArtifactVersion $artifactVersion
  if ([string]::IsNullOrWhiteSpace($issue)) {
    Add-Check "androidDeviceSmoke" "passed" "Android device smoke evidence is publishable."
  } else {
    Add-Check "androidDeviceSmoke" "blocked" $issue
  }
} catch {
  Add-Check "androidDeviceSmoke" "blocked" $_.Exception.Message
}

$ready = $blockers.Count -eq 0
$status = if ($ready) { "ready" } else { "blocked" }
$checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
$blockerRecords = @($blockers.ToArray())
$checkRecords = @($checks.ToArray())
$record = [ordered]@{
  status = $status
  checkedAtUtc = $checkedAtUtc
  readyForGitHubRelease = $ready
  blockers = $blockerRecords
  checks = $checkRecords
}

$json = $record | ConvertTo-Json -Depth 6
if (-not [string]::IsNullOrWhiteSpace($ResultJson)) {
  $resultDirectory = Split-Path -Parent $resultJsonFullPath
  if (-not [string]::IsNullOrWhiteSpace($resultDirectory)) {
    New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
  }
  $json | Set-Content -LiteralPath $resultJsonFullPath -Encoding ascii
}

Write-Output $json

if (-not $ready -and $FailOnBlocked) {
  throw "Release readiness audit is blocked: $($blockers -join '; ')"
}
