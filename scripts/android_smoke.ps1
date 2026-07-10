param(
  [string]$ApkPath = "build\app\outputs\flutter-apk\app-release.apk",
  [string]$ApkAnalyzer = "",
  [string]$Aapt2 = "",
  [int]$ExpectedMinSdk = 34,
  [int]$ExpectedTargetSdk = 37,
  [int]$ExpectedCompileSdk = 37,
  [string]$ExpectedApplicationId = "com.aligez.repapertodo",
  [string[]]$ExpectedResourceLanguages = @("zh", "en"),
  [string]$ResultJson = ""
)

$ErrorActionPreference = "Stop"

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

function Find-AndroidSdkTool {
  param(
    [string]$ToolName,
    [string]$ConfiguredPath = ""
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
    if (-not (Test-Path -LiteralPath $ConfiguredPath -PathType Leaf)) {
      throw "Configured Android SDK tool was not found: $ConfiguredPath"
    }
    return $ConfiguredPath
  }

  $command = Get-Command $ToolName -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }
  foreach ($root in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)) {
    if ([string]::IsNullOrWhiteSpace($root) -or
        -not (Test-Path -LiteralPath $root -PathType Container)) {
      continue
    }
    $tool = Get-ChildItem -LiteralPath $root -Recurse -Filter $ToolName |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($tool) {
      return $tool.FullName
    }
  }
  throw "Android APK analyzer '$ToolName' was not found. Install Android SDK command-line tools."
}

function Assert-ContainsText {
  param(
    [string]$Text,
    [string]$Needle,
    [string]$Message
  )

  if (-not $Text.Contains($Needle)) {
    throw $Message
  }
}

function Assert-DoesNotContainText {
  param(
    [string]$Text,
    [string]$Needle,
    [string]$Message
  )

  if ($Text.Contains($Needle)) {
    throw $Message
  }
}

function Assert-ManifestPair {
  param(
    [string]$Manifest,
    [string]$Name,
    [string]$Value,
    [string]$Message
  )

  Assert-ContainsText `
    -Text $Manifest `
    -Needle "$Name=`"$Value`"" `
    -Message $Message
}

function Get-AndroidXmlResourceFile {
  param(
    [string]$Resources,
    [string]$ResourceName
  )

  $lines = $Resources -split "\r?\n"
  for ($index = 0; $index -lt $lines.Count; $index += 1) {
    if ($lines[$index] -notmatch "resource\s+0x[0-9a-fA-F]+\s+$([regex]::Escape($ResourceName))\b") {
      continue
    }
    for ($cursor = $index + 1; $cursor -lt $lines.Count; $cursor += 1) {
      if ($lines[$cursor] -match "^\s*resource\s+0x[0-9a-fA-F]+") {
        break
      }
      $fileMatch = [regex]::Match(
        $lines[$cursor],
        "\(\)\s+\(file\)\s+([^\s]+)\s+type=XML"
      )
      if ($fileMatch.Success) {
        return $fileMatch.Groups[1].Value
      }
    }
  }

  throw "Android APK resource '$ResourceName' was not found as a compiled XML file."
}

function Get-XmlTreePathElements {
  param([string]$XmlTree)

  $elements = @()
  $current = $null
  foreach ($line in ($XmlTree -split "\r?\n")) {
    $elementMatch = [regex]::Match($line, "^\s+E:\s+([A-Za-z0-9_-]+)\b")
    if ($elementMatch.Success) {
      if ($null -ne $current) {
        $elements += [pscustomobject]$current
      }
      $current = [ordered]@{
        element = $elementMatch.Groups[1].Value
        name = ""
        path = ""
      }
      continue
    }

    if ($null -eq $current) {
      continue
    }

    $nameMatch = [regex]::Match($line, 'A:\s+name="([^"]*)"')
    if ($nameMatch.Success) {
      $current["name"] = $nameMatch.Groups[1].Value
      continue
    }

    $pathMatch = [regex]::Match($line, 'A:\s+path="([^"]*)"')
    if ($pathMatch.Success) {
      $current["path"] = $pathMatch.Groups[1].Value
    }
  }

  if ($null -ne $current) {
    $elements += [pscustomobject]$current
  }
  return $elements
}

function Assert-PathElement {
  param(
    [object[]]$Elements,
    [string]$Element,
    [string]$Name,
    [string]$Path
  )

  $matches = @(
    $Elements |
      Where-Object {
        $_.element -eq $Element -and $_.name -eq $Name -and $_.path -eq $Path
      }
  )
  if ($matches.Count -ne 1) {
    throw "Android APK FileProvider paths must contain exactly one <$Element name='$Name' path='$Path'> entry."
  }
}

function Assert-FileProviderPaths {
  param([string]$XmlTree)

  Assert-ContainsText `
    -Text $XmlTree `
    -Needle "E: paths" `
    -Message "Android APK FileProvider paths resource must contain a <paths> root."
  Assert-DoesNotContainText `
    -Text $XmlTree `
    -Needle "E: root-path" `
    -Message "Android APK FileProvider paths must not expose device root paths."

  $pathElements = @(Get-XmlTreePathElements -XmlTree $XmlTree)
  Assert-PathElement `
    -Elements $pathElements `
    -Element "cache-path" `
    -Name "cache" `
    -Path "."
  Assert-PathElement `
    -Elements $pathElements `
    -Element "files-path" `
    -Name "files" `
    -Path "."
  Assert-PathElement `
    -Elements $pathElements `
    -Element "external-cache-path" `
    -Name "external_cache" `
    -Path "."
  Assert-PathElement `
    -Elements $pathElements `
    -Element "external-files-path" `
    -Name "external_files" `
    -Path "."

  $allowedExternalPaths = @(
    [pscustomobject]@{
      name = "external_repapertodo"
      path = "RePaperTodo/"
    },
    [pscustomobject]@{
      name = "external_documents_repapertodo"
      path = "Documents/RePaperTodo/"
    },
    [pscustomobject]@{
      name = "external_download_repapertodo"
      path = "Download/RePaperTodo/"
    }
  )
  foreach ($allowed in $allowedExternalPaths) {
    Assert-PathElement `
      -Elements $pathElements `
      -Element "external-path" `
      -Name $allowed.name `
      -Path $allowed.path
  }

  $externalPathElements = @(
    $pathElements | Where-Object { $_.element -eq "external-path" }
  )
  foreach ($externalPath in $externalPathElements) {
    $isAllowed = $false
    foreach ($allowed in $allowedExternalPaths) {
      if ($externalPath.name -eq $allowed.name -and
          $externalPath.path -eq $allowed.path) {
        $isAllowed = $true
        break
      }
    }
    if (-not $isAllowed) {
      throw "Android APK FileProvider external-path '$($externalPath.name)' must stay scoped to RePaperTodo directories; found path '$($externalPath.path)'."
    }
  }
}

function Get-XmlTreeLocaleNames {
  param([string]$XmlTree)

  $names = @()
  foreach ($line in ($XmlTree -split "\r?\n")) {
    $nameMatch = [regex]::Match(
      $line,
      'A:\s+(?:.*:)?name(?:\([^)]+\))?="([^"]*)"'
    )
    if ($nameMatch.Success) {
      $names += $nameMatch.Groups[1].Value.Trim().ToLowerInvariant()
    }
  }
  return $names
}

function Assert-LocaleConfig {
  param(
    [string]$XmlTree,
    [string[]]$ExpectedLanguages
  )

  Assert-ContainsText `
    -Text $XmlTree `
    -Needle "E: locale-config" `
    -Message "Android APK locale config resource must contain a <locale-config> root."

  $actualLanguages = @(Get-XmlTreeLocaleNames -XmlTree $XmlTree)
  if ($actualLanguages.Count -ne $ExpectedLanguages.Count) {
    throw "Android APK locale config must contain exactly $($ExpectedLanguages -join ', '); found $($actualLanguages -join ', ')."
  }
  for ($index = 0; $index -lt $ExpectedLanguages.Count; $index += 1) {
    $expected = $ExpectedLanguages[$index].Trim().ToLowerInvariant()
    if ($actualLanguages[$index] -ne $expected) {
      throw "Android APK locale config language at index $index must be '$expected'; found '$($actualLanguages[$index])'."
    }
  }
}

function Get-AndroidResourceConfigurationLanguage {
  param([string]$Configuration)

  $trimmed = $Configuration.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    return ""
  }
  if ($trimmed -match '^(?<tag>b\+[a-z]{2,3}(?:\+[A-Za-z0-9]+)*)') {
    $parts = $matches["tag"] -split '\+'
    return $parts[1].ToLowerInvariant()
  }
  $firstQualifier = ($trimmed -split '-')[0].ToLowerInvariant()
  if (@(
    "car",
    "desk",
    "television",
    "appliance",
    "watch",
    "vrheadset"
  ) -contains $firstQualifier) {
    return ""
  }
  if ($trimmed -match '^(?<language>[a-z]{2,3})(?:-|$)') {
    return $matches["language"].ToLowerInvariant()
  }
  return ""
}

function Get-AndroidResourceLocaleConfigurations {
  param([string]$Configurations)

  $localized = @()
  foreach ($line in ($Configurations -split "\r?\n")) {
    $configuration = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($configuration)) {
      continue
    }
    $language = Get-AndroidResourceConfigurationLanguage `
      -Configuration $configuration
    if (-not [string]::IsNullOrWhiteSpace($language)) {
      $localized += [pscustomobject]@{
        configuration = $configuration
        language = $language
      }
    }
  }
  return $localized
}

function Assert-AndroidResourceLanguages {
  param(
    [object[]]$LocalizedConfigurations,
    [string[]]$ExpectedLanguages
  )

  $expected = @{}
  foreach ($language in $ExpectedLanguages) {
    $normalized = $language.Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
      $expected[$normalized] = $true
    }
  }
  foreach ($configuration in $LocalizedConfigurations) {
    if (-not $expected.ContainsKey($configuration.language)) {
      throw "Android APK localized resource configuration '$($configuration.configuration)' is outside the supported runtime languages: $($ExpectedLanguages -join ', ')."
    }
  }
}

$apkFullPath = [IO.Path]::GetFullPath($ApkPath)
if (-not (Test-Path -LiteralPath $apkFullPath -PathType Leaf)) {
  throw "Android release APK was not found: $apkFullPath"
}
if ([IO.Path]::GetExtension($apkFullPath).ToLowerInvariant() -ne ".apk") {
  throw "Android smoke input must be an .apk file: $apkFullPath"
}

$apkAnalyzerToolName = if ($IsWindows -or $env:OS -eq "Windows_NT") {
  "apkanalyzer.bat"
} else {
  "apkanalyzer"
}
$resolvedApkAnalyzer = Find-AndroidSdkTool `
  -ToolName $apkAnalyzerToolName `
  -ConfiguredPath $ApkAnalyzer
$aapt2ToolName = if ($IsWindows -or $env:OS -eq "Windows_NT") {
  "aapt2.exe"
} else {
  "aapt2"
}
$resolvedAapt2 = Find-AndroidSdkTool `
  -ToolName $aapt2ToolName `
  -ConfiguredPath $Aapt2

$minSdk = Invoke-NativeText "apkanalyzer manifest min-sdk" {
  & $resolvedApkAnalyzer manifest min-sdk $apkFullPath
}
$targetSdk = Invoke-NativeText "apkanalyzer manifest target-sdk" {
  & $resolvedApkAnalyzer manifest target-sdk $apkFullPath
}
$debuggable = Invoke-NativeText "apkanalyzer manifest debuggable" {
  & $resolvedApkAnalyzer manifest debuggable $apkFullPath
}
$applicationId = Invoke-NativeText "apkanalyzer manifest application-id" {
  & $resolvedApkAnalyzer manifest application-id $apkFullPath
}
$permissions = Invoke-NativeText "apkanalyzer manifest permissions" {
  & $resolvedApkAnalyzer manifest permissions $apkFullPath
}
$manifest = Invoke-NativeText "apkanalyzer manifest print" {
  & $resolvedApkAnalyzer manifest print $apkFullPath
}
$resources = Invoke-NativeText "aapt2 dump resources" {
  & $resolvedAapt2 dump resources $apkFullPath
}
$resourceConfigurations = Invoke-NativeText "aapt2 dump configurations" {
  & $resolvedAapt2 dump configurations $apkFullPath
}

if ([int]$minSdk -ne $ExpectedMinSdk) {
  throw "Android APK minSdk must be $ExpectedMinSdk for Android 14-17 support; found $minSdk."
}
if ([int]$targetSdk -ne $ExpectedTargetSdk) {
  throw "Android APK targetSdk must be $ExpectedTargetSdk for Android 17 readiness; found $targetSdk."
}
if ($debuggable -ne "false") {
  throw "Android release APK must not be debuggable."
}
if ($applicationId -ne $ExpectedApplicationId) {
  throw "Android APK applicationId must be $ExpectedApplicationId; found $applicationId."
}

Assert-ManifestPair `
  -Manifest $manifest `
  -Name "package" `
  -Value $ExpectedApplicationId `
  -Message "Android APK package id does not match RePaperTodo."
Assert-ManifestPair `
  -Manifest $manifest `
  -Name "android:compileSdkVersion" `
  -Value ([string]$ExpectedCompileSdk) `
  -Message "Android APK compile SDK does not match Android 17 readiness."
Assert-ManifestPair `
  -Manifest $manifest `
  -Name "android:label" `
  -Value "RePaperTodo" `
  -Message "Android APK application label must remain RePaperTodo."
Assert-ManifestPair `
  -Manifest $manifest `
  -Name "android:usesCleartextTraffic" `
  -Value "true" `
  -Message "Android APK must keep cleartext traffic enabled for generic HTTP WebDAV endpoints."
Assert-ContainsText `
  -Text $manifest `
  -Needle 'android:localeConfig=' `
  -Message "Android APK manifest must declare a localeConfig resource for zh/en app language support."

Assert-ContainsText `
  -Text $permissions `
  -Needle "android.permission.INTERNET" `
  -Message "Android APK must request INTERNET for WebDAV sync."
foreach ($requiredBackgroundPermission in @(
  "android.permission.ACCESS_NETWORK_STATE",
  "android.permission.WAKE_LOCK",
  "android.permission.RECEIVE_BOOT_COMPLETED"
)) {
  Assert-ContainsText `
    -Text $permissions `
    -Needle $requiredBackgroundPermission `
    -Message "Android APK must keep WorkManager background WebDAV sync permission: $requiredBackgroundPermission"
}
foreach ($forbiddenPermission in @(
  "android.permission.MANAGE_EXTERNAL_STORAGE",
  "android.permission.READ_EXTERNAL_STORAGE",
  "android.permission.WRITE_EXTERNAL_STORAGE"
)) {
  Assert-DoesNotContainText `
    -Text $permissions `
    -Needle $forbiddenPermission `
    -Message "Android APK must not request broad external storage permission: $forbiddenPermission"
}

foreach ($requiredText in @(
  'android:name="com.aligez.repapertodo.MainActivity"',
  'android:exported="true"',
  'android:taskAffinity=""',
  'android:launchMode="1"',
  'android:windowSoftInputMode="0x10"',
  'android:hardwareAccelerated="true"',
  'android:name="android.intent.action.MAIN"',
  'android:name="android.intent.category.LAUNCHER"',
  'android:name="androidx.core.content.FileProvider"',
  'android:exported="false"',
  'android:authorities="com.aligez.repapertodo.fileprovider"',
  'android:grantUriPermissions="true"',
  'android:name="android.support.FILE_PROVIDER_PATHS"',
  'android:name="flutterEmbedding"',
  'android:value="2"',
  'android:name="androidx.work.WorkManagerInitializer"',
  'android:name="androidx.work.impl.background.systemjob.SystemJobService"',
  'android:permission="android.permission.BIND_JOB_SERVICE"',
  'android:name="androidx.work.impl.background.systemalarm.RescheduleReceiver"'
)) {
  Assert-ContainsText `
    -Text $manifest `
    -Needle $requiredText `
    -Message "Android APK manifest is missing required entry: $requiredText"
}

foreach ($requiredQuery in @(
  'android:name="android.intent.action.PROCESS_TEXT"',
  'android:name="android.intent.action.VIEW"',
  'android:scheme="http"',
  'android:scheme="https"',
  'android:scheme="mailto"',
  'android:mimeType="text/markdown"',
  'android:mimeType="text/plain"',
  'android:mimeType="*/*"'
)) {
  Assert-ContainsText `
    -Text $manifest `
    -Needle $requiredQuery `
    -Message "Android APK manifest is missing package visibility query: $requiredQuery"
}

$fileProviderPathsFile = Get-AndroidXmlResourceFile `
  -Resources $resources `
  -ResourceName "xml/file_paths"
$fileProviderPathsXml = Invoke-NativeText "aapt2 dump xmltree $fileProviderPathsFile" {
  & $resolvedAapt2 dump xmltree --file $fileProviderPathsFile $apkFullPath
}
Assert-FileProviderPaths -XmlTree $fileProviderPathsXml
$localeConfigFile = Get-AndroidXmlResourceFile `
  -Resources $resources `
  -ResourceName "xml/locales_config"
$localeConfigXml = Invoke-NativeText "aapt2 dump xmltree $localeConfigFile" {
  & $resolvedAapt2 dump xmltree --file $localeConfigFile $apkFullPath
}
Assert-LocaleConfig `
  -XmlTree $localeConfigXml `
  -ExpectedLanguages $ExpectedResourceLanguages
$localizedResourceConfigurations = @(
  Get-AndroidResourceLocaleConfigurations -Configurations $resourceConfigurations
)
Assert-AndroidResourceLanguages `
  -LocalizedConfigurations $localizedResourceConfigurations `
  -ExpectedLanguages $ExpectedResourceLanguages

if (-not [string]::IsNullOrWhiteSpace($ResultJson)) {
  $resultPath = [IO.Path]::GetFullPath($ResultJson)
  $resultDirectory = [IO.Path]::GetDirectoryName($resultPath)
  if (-not [string]::IsNullOrWhiteSpace($resultDirectory) -and
      -not (Test-Path -LiteralPath $resultDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $resultDirectory | Out-Null
  }
  $permissionList = @(
    $permissions -split "\r?\n" |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
  $localizedResourceConfigurationList = @(
    $localizedResourceConfigurations |
      ForEach-Object { $_.configuration }
  )
  [ordered]@{
    status = "passed"
    checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    apkAnalyzer = $resolvedApkAnalyzer
    aapt2 = $resolvedAapt2
    apkPath = $apkFullPath
    apkFileName = [IO.Path]::GetFileName($apkFullPath)
    applicationId = $ExpectedApplicationId
    apkApplicationId = $applicationId
    launcherActivity = "$ExpectedApplicationId.MainActivity"
    launcherIntentPresent = $true
    singleTopLaunchMode = $true
    emptyTaskAffinity = $true
    adjustResizeWindow = $true
    hardwareAcceleratedActivity = $true
    minSdk = [int]$minSdk
    targetSdk = [int]$targetSdk
    compileSdk = [int]$ExpectedCompileSdk
    debuggable = $debuggable
    permissions = $permissionList
    fileProviderPathsResource = $fileProviderPathsFile
    localeConfigResource = $localeConfigFile
    localeConfigLanguages = @(Get-XmlTreeLocaleNames -XmlTree $localeConfigXml)
    androidLocaleConfigPresent = $true
    cleartextWebDavAllowed = $true
    backgroundWorkManagerInitializer = $true
    backgroundWorkManagerSystemJobService = $true
    backgroundWorkManagerRescheduleReceiver = $true
    backgroundSyncNetworkPermission = $true
    backgroundSyncWakeLockPermission = $true
    backgroundSyncBootReschedulePermission = $true
    broadExternalStoragePermissionsAbsent = $true
    expectedResourceLanguages = $ExpectedResourceLanguages
    localizedResourceConfigurations = $localizedResourceConfigurationList
    forbiddenLocalizedResourceConfigurationsAbsent = $true
  } |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $resultPath -Encoding ascii
}

Write-Host "Android APK smoke passed for $apkFullPath."
