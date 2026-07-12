param(
  [string]$KeyPropertiesPath = "android\key.properties",
  [string]$KeystorePath = "android\repapertodo-release.jks",
  [string]$StoreFile = "repapertodo-release.jks"
)

$ErrorActionPreference = "Stop"

$androidSigningSecretNames = @(
  "ANDROID_KEYSTORE_BASE64",
  "ANDROID_STORE_PASSWORD",
  "ANDROID_KEY_ALIAS",
  "ANDROID_KEY_PASSWORD"
)

function Get-AndroidSigningSecret {
  param([string]$Name)

  $item = Get-Item -LiteralPath "Env:\$Name" -ErrorAction SilentlyContinue
  if ($null -eq $item) {
    return ""
  }
  return [string]$item.Value
}

function Assert-AndroidSigningSecret {
  param(
    [string]$Name,
    [string]$Value
  )

  if ($Value -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Android release signing secret '$Name' must not contain control characters."
  }
}

function Assert-AndroidStoreFile {
  param([string]$Value)

  Assert-AndroidSigningSecret -Name "storeFile" -Value $Value
  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "Android signing storeFile must not be blank."
  }
  if ([IO.Path]::IsPathRooted($Value)) {
    throw "Android signing storeFile must be relative to the Android project."
  }
  if ($Value.Contains("*") -or $Value.Contains("?")) {
    throw "Android signing storeFile must not contain wildcard characters."
  }
  $segments = @(
    $Value -split "[\\/]" |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
  if ($segments | Where-Object { $_ -eq "." -or $_ -eq ".." }) {
    throw "Android signing storeFile must not contain dot-segments."
  }
}

function Convert-AndroidKeystoreSecret {
  param([string]$Value)

  Assert-AndroidSigningSecret -Name "ANDROID_KEYSTORE_BASE64" -Value $Value
  try {
    return [Convert]::FromBase64String($Value)
  } catch {
    throw "Android release signing secret 'ANDROID_KEYSTORE_BASE64' must be valid base64."
  }
}

function Resolve-AndroidSigningOutputPath {
  param(
    [string]$Path,
    [string]$Description
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "Android signing $Description path must not be blank."
  }
  if ($Path -match "[\x00-\x1F\x7F-\x9F]") {
    throw "Android signing $Description path must not contain control characters."
  }
  if ($Path.Contains("*") -or $Path.Contains("?")) {
    throw "Android signing $Description path must not contain wildcard characters."
  }
  try {
    $resolvedPath = if ([IO.Path]::IsPathRooted($Path)) {
      [IO.Path]::GetFullPath($Path)
    } else {
      [IO.Path]::GetFullPath((Join-Path $PWD $Path))
    }
  } catch {
    throw "Android signing $Description path is invalid: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($resolvedPath))) {
    throw "Android signing $Description path must include a file name."
  }
  if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
    throw "Android signing $Description path must include a file name."
  }
  return $resolvedPath
}

try {
  $androidSigningSecrets = [ordered]@{}
  foreach ($name in $androidSigningSecretNames) {
    $androidSigningSecrets[$name] = Get-AndroidSigningSecret -Name $name
  }

  $configuredSecrets = @(
    $androidSigningSecretNames |
      Where-Object {
        -not [string]::IsNullOrWhiteSpace($androidSigningSecrets[$_])
      }
  )
  if ($configuredSecrets.Count -eq 0) {
    Write-Host "Android release signing secrets are not configured; release packaging will use debug fallback unless publishing is requested."
    return
  }

  if ($configuredSecrets.Count -ne $androidSigningSecretNames.Count) {
    $missing = @()
    foreach ($name in $androidSigningSecretNames) {
      if ([string]::IsNullOrWhiteSpace($androidSigningSecrets[$name])) {
        $missing += $name
      }
    }
    throw "Android release signing secrets are incomplete: $($missing -join ', ')."
  }

  foreach ($name in $androidSigningSecretNames) {
    Assert-AndroidSigningSecret `
      -Name $name `
      -Value $androidSigningSecrets[$name]
  }

  $keystoreSecret = $androidSigningSecrets["ANDROID_KEYSTORE_BASE64"]
  $keystoreBytes = Convert-AndroidKeystoreSecret -Value $keystoreSecret
  Assert-AndroidStoreFile -Value $StoreFile
  $resolvedKeystorePath = Resolve-AndroidSigningOutputPath `
    -Path $KeystorePath `
    -Description "keystore"
  $resolvedKeyPropertiesPath = Resolve-AndroidSigningOutputPath `
    -Path $KeyPropertiesPath `
    -Description "key.properties"

  $keystoreParent = [IO.Path]::GetDirectoryName($resolvedKeystorePath)
  $keyPropertiesParent = [IO.Path]::GetDirectoryName($resolvedKeyPropertiesPath)
  if (-not [string]::IsNullOrWhiteSpace($keystoreParent)) {
    New-Item -ItemType Directory -Force -Path $keystoreParent | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($keyPropertiesParent)) {
    New-Item -ItemType Directory -Force -Path $keyPropertiesParent | Out-Null
  }

  [IO.File]::WriteAllBytes($resolvedKeystorePath, $keystoreBytes)
  @"
storeFile=$StoreFile
storePassword=$($androidSigningSecrets["ANDROID_STORE_PASSWORD"])
keyAlias=$($androidSigningSecrets["ANDROID_KEY_ALIAS"])
keyPassword=$($androidSigningSecrets["ANDROID_KEY_PASSWORD"])
"@ | Set-Content -LiteralPath $resolvedKeyPropertiesPath -Encoding ascii
} finally {
  foreach ($name in $androidSigningSecretNames) {
    Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
  }
}
