param(
  [string]$ResultJson = ""
)

$ErrorActionPreference = "Stop"

function Assert-TextContains {
  param(
    [string]$Text,
    [string]$Expected,
    [string]$Message
  )

  if (-not $Text.Contains($Expected)) {
    throw $Message
  }
}

function Resolve-ResultJsonPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "WebDAV static smoke result JSON path must not contain control characters."
  }
  if ($Path -match "[*?]") {
    throw "WebDAV static smoke result JSON path must not contain wildcard characters."
  }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path)
  } catch {
    throw "WebDAV static smoke result JSON path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($fullPath))) {
    throw "WebDAV static smoke result JSON path must include a file name."
  }
  if ([IO.Path]::GetExtension($fullPath).ToLowerInvariant() -ne ".json") {
    throw "WebDAV static smoke result JSON path must use the .json extension."
  }
  return $fullPath
}

function Read-RepoText {
  param([string]$RelativePath)

  $path = Join-Path $repoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required WebDAV smoke input was not found: $RelativePath"
  }
  return Get-Content -Raw -LiteralPath $path
}

function Assert-RepoEvidenceFile {
  param([string]$RelativePath)

  if ([string]::IsNullOrWhiteSpace($RelativePath)) {
    throw "WebDAV smoke evidence file path must not be blank."
  }
  if ([IO.Path]::IsPathRooted($RelativePath)) {
    throw "WebDAV smoke evidence file path must be relative: $RelativePath"
  }
  if ($RelativePath -match "[\x00-\x1F\x7F-\x9F]") {
    throw "WebDAV smoke evidence file path must not contain control characters: $RelativePath"
  }

  $normalizedRelativePath = $RelativePath.Replace("/", [IO.Path]::DirectorySeparatorChar)
  $segments = @(
    $normalizedRelativePath -split [regex]::Escape([string][IO.Path]::DirectorySeparatorChar) |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
  if ($segments | Where-Object { $_ -eq "." -or $_ -eq ".." }) {
    throw "WebDAV smoke evidence file path must not contain dot-segments: $RelativePath"
  }

  $resolvedPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $normalizedRelativePath))
  $resolvedRepoRoot = [IO.Path]::GetFullPath([string]$repoRoot)
  if (-not $resolvedRepoRoot.EndsWith([string][IO.Path]::DirectorySeparatorChar)) {
    $resolvedRepoRoot = "$resolvedRepoRoot$([IO.Path]::DirectorySeparatorChar)"
  }
  if (-not $resolvedPath.StartsWith($resolvedRepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "WebDAV smoke evidence file path must stay inside the repository: $RelativePath"
  }
  if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
    throw "WebDAV smoke evidence file was not found: $RelativePath"
  }
}

$resultJsonFullPath = Resolve-ResultJsonPath -Path $ResultJson
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

$evidenceFiles = @(
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
foreach ($evidenceFile in $evidenceFiles) {
  Assert-RepoEvidenceFile -RelativePath $evidenceFile
}

$clientSource = Read-RepoText "lib\src\sync\webdav\webdav_client.dart"
$syncServiceSource =
  Read-RepoText "lib\src\sync\webdav\webdav_state_sync_service.dart"
$payloadCodecSource =
  Read-RepoText "lib\src\sync\webdav\webdav_payload_codec.dart"
$presetsSource = Read-RepoText "lib\src\core\model\webdav_presets.dart"
$settingsSource = Read-RepoText "lib\src\core\model\sync_settings.dart"
$androidBackgroundSyncSource =
  Read-RepoText "lib\src\sync\android_background_sync.dart"
$settingsDialogSource = Read-RepoText "lib\src\ui\sync_settings_dialog.dart"
$androidBackgroundSyncTest = Read-RepoText "test\android_background_sync_test.dart"
$webDavStateSyncTest = Read-RepoText "test\webdav_state_sync_service_test.dart"
$appSyncServiceTest = Read-RepoText "test\app_sync_service_test.dart"
$webDavClientTest = Read-RepoText "test\webdav_client_test.dart"
$webDavPayloadCodecTest = Read-RepoText "test\webdav_payload_codec_test.dart"
$webDavPresetsTest = Read-RepoText "test\webdav_presets_test.dart"

Assert-TextContains `
  -Text $clientSource `
  -Expected "WebDAV base URI must use http or https and include a host." `
  -Message "Generic HTTP/HTTPS WebDAV endpoint validation is missing."
Assert-TextContains `
  -Text $clientSource `
  -Expected "request.followRedirects = false" `
  -Message "WebDAV redirect safety implementation is missing."
Assert-TextContains `
  -Text $clientSource `
  -Expected "const _webDavUserAgent = 'RePaperTodo/1 WebDAV';" `
  -Message "Stable WebDAV User-Agent is missing."

Assert-TextContains `
  -Text $presetsSource `
  -Expected "Generic WebDAV" `
  -Message "Generic WebDAV preset is missing."
Assert-TextContains `
  -Text $presetsSource `
  -Expected "Jianguoyun WebDAV" `
  -Message "Jianguoyun WebDAV preset is missing."
Assert-TextContains `
  -Text $presetsSource `
  -Expected "https://dav.jianguoyun.com/dav/" `
  -Message "Jianguoyun WebDAV endpoint is missing."

Assert-TextContains `
  -Text $payloadCodecSource `
  -Expected "RePaperTodo-Encrypted-Payload-v1" `
  -Message "Encrypted WebDAV payload envelope is missing."
Assert-TextContains `
  -Text $payloadCodecSource `
  -Expected "WebDAV encryption passphrase must not be empty." `
  -Message "WebDAV encryption passphrase validation is missing."

Assert-TextContains `
  -Text $syncServiceSource `
  -Expected "snapshotDirectoryName = 'snapshots'" `
  -Message "WebDAV snapshot path layout is missing."
Assert-TextContains `
  -Text $syncServiceSource `
  -Expected "operationDirectoryName = 'ops'" `
  -Message "WebDAV operation-log path layout is missing."
Assert-TextContains `
  -Text $syncServiceSource `
  -Expected "uploadOperationLogs" `
  -Message "WebDAV operation-log upload support is missing."
Assert-TextContains `
  -Text $syncServiceSource `
  -Expected "migrateLegacyPlainOperationLog" `
  -Message "WebDAV legacy plain operation-log migration is missing."
Assert-TextContains `
  -Text $syncServiceSource `
  -Expected "EncryptedWebDavPayloadCodec" `
  -Message "Configured WebDAV sync does not select encrypted payloads."

Assert-TextContains `
  -Text $settingsSource `
  -Expected "encryptionPassphrase" `
  -Message "WebDAV sync settings do not expose an encryption passphrase."
Assert-TextContains `
  -Text $settingsDialogSource `
  -Expected "syncEncryptionPassphrase" `
  -Message "WebDAV sync settings UI does not expose the encryption passphrase."
Assert-TextContains `
  -Text $settingsDialogSource `
  -Expected "webDavProvider" `
  -Message "WebDAV sync settings UI does not expose provider selection."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "Workmanager().executeTask" `
  -Message "Android WebDAV background sync dispatcher is missing."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "runRePaperTodoBackgroundSync(inputData)" `
  -Message "Android WebDAV background dispatcher does not enter the shared Dart sync path."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "StateStore(filePath: stateFilePath)" `
  -Message "Android WebDAV background sync does not reload the shared StateStore."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "AppSyncService()).syncAndMergeNow" `
  -Message "Android WebDAV background sync does not reuse AppSyncService."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "Constraints(networkType: NetworkType.connected)" `
  -Message "Android WebDAV background sync does not require network connectivity."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "ExistingPeriodicWorkPolicy.update" `
  -Message "Android WebDAV background sync does not update existing periodic work."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "_backgroundSyncCompletedWithoutRetry" `
  -Message "Android WebDAV background sync retry policy is missing."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "_isAbsoluteBackgroundStateFilePath" `
  -Message "Android WebDAV background sync does not reject relative state paths before scheduling or running."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "_backgroundStateFileName" `
  -Message "Android WebDAV background sync does not verify the state file name before scheduling or running."
Assert-TextContains `
  -Text $androidBackgroundSyncSource `
  -Expected "!= 'data.json'" `
  -Message "Android WebDAV background sync does not reject non-data.json state paths before scheduling or running."

Assert-TextContains `
  -Text $webDavStateSyncTest `
  -Expected "push uploads a state snapshot and manifest" `
  -Message "WebDAV snapshot upload test coverage is missing."
Assert-TextContains `
  -Text $webDavStateSyncTest `
  -Expected "encrypts payloads from configured WebDAV settings" `
  -Message "WebDAV encrypted payload test coverage is missing."
Assert-TextContains `
  -Text $webDavStateSyncTest `
  -Expected "round trips snapshots and operation logs through a local HTTP WebDAV server" `
  -Message "Local HTTP WebDAV protocol round-trip test coverage is missing."
Assert-TextContains `
  -Text $webDavStateSyncTest `
  -Expected "creates a sync service from Jianguoyun WebDAV settings" `
  -Message "Jianguoyun WebDAV preset test coverage is missing."
Assert-TextContains `
  -Text $appSyncServiceTest `
  -Expected "requires an encryption passphrase for configured WebDAV sync" `
  -Message "User-facing WebDAV passphrase gate test coverage is missing."
Assert-TextContains `
  -Text $appSyncServiceTest `
  -Expected "round trips Windows and Android edits through shared WebDAV operation logs" `
  -Message "Windows/Android WebDAV operation-log round-trip test coverage is missing."
Assert-TextContains `
  -Text $androidBackgroundSyncTest `
  -Expected "Android background sync registers periodic WebDAV work when configured" `
  -Message "Android WebDAV background registration test coverage is missing."
Assert-TextContains `
  -Text $androidBackgroundSyncTest `
  -Expected "Android background sync accepts POSIX absolute state paths" `
  -Message "Android WebDAV background registration does not cover Android absolute state paths."
Assert-TextContains `
  -Text $androidBackgroundSyncTest `
  -Expected "relative/data.json" `
  -Message "Android WebDAV background registration does not cover relative state-path rejection."
Assert-TextContains `
  -Text $androidBackgroundSyncTest `
  -Expected "state.json" `
  -Message "Android WebDAV background registration does not cover non-data.json state-path rejection."
Assert-TextContains `
  -Text $androidBackgroundSyncTest `
  -Expected "Android background sync reports conflicts as retryable" `
  -Message "Android WebDAV background retry test coverage is missing."
Assert-TextContains `
  -Text $webDavClientTest `
  -Expected "allows http endpoints for generic WebDAV sync" `
  -Message "Generic HTTP WebDAV test coverage is missing."
Assert-TextContains `
  -Text $webDavPayloadCodecTest `
  -Expected "encrypted payload codec round trips snapshots and operation logs" `
  -Message "Encrypted WebDAV codec round-trip test coverage is missing."
Assert-TextContains `
  -Text $webDavPresetsTest `
  -Expected "keeps generic WebDAV as an explicit fallback preset" `
  -Message "Generic WebDAV preset test coverage is missing."

$result = [ordered]@{
  status = "passed"
  checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  genericWebDavSupported = $true
  jianguoyunPresetSupported = $true
  encryptedPayloadsRequired = $true
  operationLogsSupported = $true
  crossDeviceOperationRoundTripCovered = $true
  localHttpWebDavRoundTripCovered = $true
  sharedWindowsAndroidSettings = $true
  androidBackgroundSyncSharedDartPath = $true
  androidBackgroundSyncRegistrationCovered = $true
  androidBackgroundSyncAbsoluteStatePathCovered = $true
  androidBackgroundSyncDataJsonStatePathCovered = $true
  evidenceFiles = $evidenceFiles
}

if (-not [string]::IsNullOrWhiteSpace($ResultJson)) {
  $resultDirectory = Split-Path -Parent $resultJsonFullPath
  if (-not [string]::IsNullOrWhiteSpace($resultDirectory)) {
    New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
  }
  $result |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $resultJsonFullPath -Encoding ascii
}

Write-Host "WebDAV static smoke passed for generic WebDAV, Jianguoyun preset, encrypted payloads, local HTTP protocol round trip, operation logs, and Android background sync evidence."
