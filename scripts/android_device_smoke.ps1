param(
  [string]$ApkPath = "build\app\outputs\flutter-apk\app-release.apk",
  [string]$Adb = "",
  [string]$ApkAnalyzer = "",
  [string]$DeviceSerial = "",
  [string]$ExpectedApplicationId = "com.aligez.repapertodo",
  [int]$MinSupportedApi = 34,
  [int]$MaxSupportedApi = 37,
  [int]$LaunchWaitSeconds = 15,
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

function Invoke-AdbText {
  param(
    [string]$Name,
    [string[]]$Arguments
  )

  $adbArguments = @()
  if (-not [string]::IsNullOrWhiteSpace($script:resolvedDeviceSerial)) {
    $adbArguments += @("-s", $script:resolvedDeviceSerial)
  }
  $adbArguments += $Arguments
  return Invoke-NativeText $Name {
    & $script:resolvedAdb @adbArguments
  }
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
    $tool = Get-ChildItem `
      -LiteralPath $root `
      -Recurse `
      -Filter $ToolName `
      -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($tool) {
      return $tool.FullName
    }
  }

  throw "Android SDK tool '$ToolName' was not found. Install Android platform-tools so a device smoke test can run."
}

function Get-AndroidDeviceSerial {
  param(
    [string]$AdbPath,
    [string]$ConfiguredSerial
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfiguredSerial)) {
    $trimmedSerial = $ConfiguredSerial.Trim()
    if ($trimmedSerial -match "[\x00-\x20\x7F-\x9F]") {
      throw "Android device serial must not contain whitespace or control characters."
    }
    return $trimmedSerial
  }

  $devicesText = Invoke-NativeText "adb devices" {
    & $AdbPath devices
  }
  $devices = @()
  foreach ($line in ($devicesText -split "\r?\n")) {
    $match = [regex]::Match($line, "^([^\s]+)\s+device$")
    if ($match.Success) {
      $devices += $match.Groups[1].Value
    }
  }

  if ($devices.Count -eq 0) {
    throw "No online Android device or emulator was found. Start an Android 14-17/API 34-37 emulator or connect a device, then rerun the smoke script."
  }
  if ($devices.Count -gt 1) {
    throw "Multiple Android devices are online. Pass -DeviceSerial with one adb serial: $($devices -join ', ')"
  }
  return $devices[0]
}

function Get-AndroidProcessId {
  param([string]$PackageName)

  $adbArguments = @()
  if (-not [string]::IsNullOrWhiteSpace($script:resolvedDeviceSerial)) {
    $adbArguments += @("-s", $script:resolvedDeviceSerial)
  }
  $adbArguments += @("shell", "pidof", $PackageName)
  $processIdText = (& $script:resolvedAdb @adbArguments) -join "`n"
  if (-not [string]::IsNullOrWhiteSpace($processIdText)) {
    return $processIdText.Trim()
  }

  $processes = Invoke-AdbText "adb shell ps" @("shell", "ps", "-A")
  foreach ($line in ($processes -split "\r?\n")) {
    if ($line -match "\s$([regex]::Escape($PackageName))$") {
      return ($line -split "\s+")[1]
    }
  }
  return ""
}

function Get-ApkApplicationId {
  param(
    [string]$ApkAnalyzerPath,
    [string]$ApkFile
  )

  $applicationId = Invoke-NativeText "apkanalyzer manifest application-id" {
    & $ApkAnalyzerPath manifest application-id $ApkFile
  }
  if ([string]::IsNullOrWhiteSpace($applicationId)) {
    throw "Android device smoke could not read the APK applicationId."
  }
  return $applicationId.Trim()
}

function Get-AndroidForegroundPackage {
  param([string]$ExpectedPackageName)

  $windowText = Invoke-AdbText "adb shell dumpsys window" `
    @("shell", "dumpsys", "window")
  $windowForegroundPackage = Get-ForegroundPackageFromDump `
    -DumpText $windowText `
    -FocusLinePattern "mCurrentFocus|mFocusedApp|topResumedActivity|focusedApp"
  if (-not [string]::IsNullOrWhiteSpace($windowForegroundPackage)) {
    return $windowForegroundPackage
  }

  $activityText = Invoke-AdbText "adb shell dumpsys activity activities" `
    @("shell", "dumpsys", "activity", "activities")
  $activityForegroundPackage = Get-ForegroundPackageFromDump `
    -DumpText $activityText `
    -FocusLinePattern "topResumedActivity|mResumedActivity|ResumedActivity|mFocusedActivity"
  if (-not [string]::IsNullOrWhiteSpace($activityForegroundPackage)) {
    return $activityForegroundPackage
  }
  throw "Android device smoke could not determine the foreground package from dumpsys window output."
}

function Get-ForegroundPackageFromDump {
  param(
    [string]$DumpText,
    [string]$FocusLinePattern
  )

  $focusLines = @(
    $DumpText -split "\r?\n" |
      Where-Object { $_ -match $FocusLinePattern }
  )
  foreach ($line in $focusLines) {
    $match = [regex]::Match(
      $line,
      "\b(?<package>[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)/"
    )
    if ($match.Success) {
      return $match.Groups["package"].Value
    }
  }
  return ""
}

function Stop-AndroidPackageQuietly {
  param([string]$PackageName)

  try {
    Invoke-AdbText "adb shell am force-stop" `
      @("shell", "am", "force-stop", $PackageName) | Out-Null
  } catch {
    Write-Warning "Android device smoke could not force-stop '$PackageName': $($_.Exception.Message)"
  }
}

function Resolve-ResultJsonPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Android device smoke result JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "Android device smoke result JSON path must not contain wildcard characters."
  }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path)
  } catch {
    throw "Android device smoke result JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($fullPath))) {
    throw "Android device smoke result JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -ne ".json") {
    throw "Android device smoke result JSON path must use the .json extension."
  }
  return $fullPath
}

if ($LaunchWaitSeconds -lt 1 -or $LaunchWaitSeconds -gt 60) {
  throw "Android launch wait must be between 1 and 60 seconds."
}
$resultJsonFullPath = Resolve-ResultJsonPath -Path $ResultJson

$apkFullPath = [IO.Path]::GetFullPath($ApkPath)
if (-not (Test-Path -LiteralPath $apkFullPath -PathType Leaf)) {
  throw "Android release APK was not found: $apkFullPath"
}
if ([IO.Path]::GetExtension($apkFullPath).ToLowerInvariant() -ne ".apk") {
  throw "Android device smoke input must be an .apk file: $apkFullPath"
}
$apkItem = Get-Item -LiteralPath $apkFullPath
$apkHash = Get-FileHash -Algorithm SHA256 -LiteralPath $apkFullPath

$adbToolName = if ($IsWindows -or $env:OS -eq "Windows_NT") {
  "adb.exe"
} else {
  "adb"
}
$apkAnalyzerToolName = if ($IsWindows -or $env:OS -eq "Windows_NT") {
  "apkanalyzer.bat"
} else {
  "apkanalyzer"
}
$resolvedApkAnalyzer = Find-AndroidSdkTool `
  -ToolName $apkAnalyzerToolName `
  -ConfiguredPath $ApkAnalyzer
$apkApplicationId = Get-ApkApplicationId `
  -ApkAnalyzerPath $resolvedApkAnalyzer `
  -ApkFile $apkFullPath
if ($apkApplicationId -ne $ExpectedApplicationId) {
  throw "Android device smoke APK applicationId '$apkApplicationId' does not match expected package '$ExpectedApplicationId'."
}
$script:resolvedAdb = Find-AndroidSdkTool `
  -ToolName $adbToolName `
  -ConfiguredPath $Adb
$script:resolvedDeviceSerial = Get-AndroidDeviceSerial `
  -AdbPath $script:resolvedAdb `
  -ConfiguredSerial $DeviceSerial

$apiLevelText = Invoke-AdbText "adb shell getprop ro.build.version.sdk" `
  @("shell", "getprop", "ro.build.version.sdk")
if ($apiLevelText -notmatch "^\d+$") {
  throw "Android device API level '$apiLevelText' is not an integer."
}
$apiLevel = [int]$apiLevelText
if ($apiLevel -lt $MinSupportedApi -or $apiLevel -gt $MaxSupportedApi) {
  throw "Android device smoke requires Android 14-17/API $MinSupportedApi-$MaxSupportedApi; connected device '$script:resolvedDeviceSerial' is API $apiLevel."
}

Invoke-AdbText "adb install" @("install", "-r", $apkFullPath) | Out-Null
Stop-AndroidPackageQuietly -PackageName $ExpectedApplicationId

try {
  Invoke-AdbText "adb shell am start" @(
    "shell",
    "am",
    "start",
    "-W",
    "-a",
    "android.intent.action.MAIN",
    "-c",
    "android.intent.category.LAUNCHER",
    "-n",
    "$ExpectedApplicationId/.MainActivity"
  ) | Out-Null

  Start-Sleep -Seconds $LaunchWaitSeconds
  $processId = Get-AndroidProcessId -PackageName $ExpectedApplicationId
  if ([string]::IsNullOrWhiteSpace($processId)) {
    throw "Android device smoke did not observe a running '$ExpectedApplicationId' process after launch."
  }
  if ($processId -notmatch "^\d+$" -or [int64]$processId -le 0) {
    throw "Android device smoke observed process ID must be a positive integer; found '$processId'."
  }
  $foregroundPackage = Get-AndroidForegroundPackage `
    -ExpectedPackageName $ExpectedApplicationId
  if ($foregroundPackage -ne $ExpectedApplicationId) {
    throw "Android device smoke expected '$ExpectedApplicationId' to be foreground after launch, but found '$foregroundPackage'."
  }

  $result = [ordered]@{
    status = "passed"
    checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    adb = $script:resolvedAdb
    apkAnalyzer = $resolvedApkAnalyzer
    deviceSerial = $script:resolvedDeviceSerial
    apiLevel = $apiLevel
    minSupportedApi = $MinSupportedApi
    maxSupportedApi = $MaxSupportedApi
    packageName = $ExpectedApplicationId
    apkApplicationId = $apkApplicationId
    apkPath = $apkFullPath
    apkFileName = [IO.Path]::GetFileName($apkFullPath)
    apkBytes = $apkItem.Length
    apkSha256 = $apkHash.Hash.ToLowerInvariant()
    launchWaitSeconds = $LaunchWaitSeconds
    processId = $processId
    foregroundPackage = $foregroundPackage
  }
} finally {
  Stop-AndroidPackageQuietly -PackageName $ExpectedApplicationId
}
if (-not [string]::IsNullOrWhiteSpace($ResultJson)) {
  $resultJsonDirectory = [IO.Path]::GetDirectoryName($resultJsonFullPath)
  if (-not [string]::IsNullOrWhiteSpace($resultJsonDirectory)) {
    New-Item -ItemType Directory -Force -Path $resultJsonDirectory | Out-Null
  }
  $result |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $resultJsonFullPath -Encoding ascii
}
Write-Host "Android device smoke passed on $script:resolvedDeviceSerial (API $apiLevel) with process $processId."
