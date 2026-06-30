# Development

## Flutter Toolchain

This repository is configured as a Flutter project for Windows and Android.

During initial setup, Puro was used to install Flutter stable:

```powershell
winget install pingbird.Puro --accept-source-agreements --accept-package-agreements --silent
puro create stable
puro use stable
```

If the local shell has a malformed proxy value such as `<http://127.0.0.1:7897>`, override it for Flutter/GitHub commands:

```powershell
$env:HTTPS_PROXY = "http://127.0.0.1:7897"
$env:HTTP_PROXY = "http://127.0.0.1:7897"
```

## Checks

```powershell
puro flutter pub get
puro flutter analyze
puro flutter test
puro flutter build windows
puro flutter build apk --debug
```

## Current Build Outputs

Build outputs are ignored by Git:

- `build/windows/x64/runner/Release/repapertodo.exe`
- `build/app/outputs/flutter-apk/app-debug.apk`

