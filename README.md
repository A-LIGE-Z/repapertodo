# RePaperTodo

RePaperTodo is a Flutter-first reimplementation of PaperTodo.

The goal is to reproduce PaperTodo's full feature set and product philosophy, starting with the Windows exe experience, then expanding to Android 14-17 and cross-device WebDAV sync.

## Direction

- Flutter and Dart as the primary app language.
- Windows exe first.
- Android app second.
- Shared local-first data model.
- Generic WebDAV sync for Windows and Android.
- Domestic WebDAV presets may be added, while generic WebDAV remains mandatory.
- No fixed budget ceiling for reaching feature parity and reliable sync.

## Current Status

This repository now contains a Flutter Windows/Android codebase with the shared
PaperTodo-compatible data model, desktop-first paper UI, local persistence,
platform-service boundaries, startup command handling, and WebDAV snapshot plus
operation-log sync foundations.

See [AGENTS.md](AGENTS.md) for project rules and [docs/ROADMAP.md](docs/ROADMAP.md) for the staged implementation plan.

## Release Build

Use the local release script to verify, build, and package the Windows and
Android artifacts. The script also writes a SHA-256 checksum file beside the
artifacts in `dist/`, plus a release metadata JSON file with the version,
commit, Android SDK/signing mode, validation commands, and artifact hashes.

```powershell
.\scripts\release.ps1
```

To also create or update the GitHub Release for the version in `pubspec.yaml`:

```powershell
.\scripts\release.ps1 -PublishGitHubRelease
```

By default the release script refuses to package a dirty git working tree so
the artifact metadata commit matches the files being shipped. For a local-only
smoke package from uncommitted changes, pass `-AllowDirty`.

If dependencies are already cached and network access to pub.dev is unreliable,
use offline package resolution:

```powershell
.\scripts\release.ps1 -OfflinePubGet
```

### Android release signing

Android APK builds keep working without secrets by falling back to the debug
signing config. For a store-ready APK, create `android/key.properties` locally
and keep the keystore out of git:

```properties
storeFile=repapertodo-release.jks
storePassword=your-store-password
keyAlias=repapertodo
keyPassword=your-key-password
```

Generate a local keystore when needed:

```powershell
keytool -genkeypair -v -keystore android\repapertodo-release.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias repapertodo
```

The release script prints whether the APK used `android/key.properties` or the
debug fallback and records that mode in GitHub Release notes.
