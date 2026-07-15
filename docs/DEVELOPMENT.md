# Development

## Flutter Toolchain

This repository is configured as a Flutter project for Windows and Android.

During initial setup, Puro was used to install Flutter stable:

```powershell
winget install pingbird.Puro --accept-source-agreements --accept-package-agreements --silent
puro create stable
puro use stable
```

If the local shell has a malformed or stale proxy value, clear proxy
environment variables before running Flutter, Gradle, or release packaging.
Some Android SDK tools treat even empty or angle-bracketed proxy values as
malformed URLs. `scripts/release.ps1` already performs this cleanup before its
own checks and builds.

```powershell
Remove-Item Env:\HTTP_PROXY,Env:\HTTPS_PROXY,Env:\ALL_PROXY,Env:\http_proxy,Env:\https_proxy,Env:\all_proxy -ErrorAction SilentlyContinue
```

## Checks

```powershell
puro flutter pub get
puro flutter analyze
puro flutter test
puro flutter build windows
puro flutter build apk --debug
```

For a local release-packaging smoke test from the current worktree, use:

```powershell
.\scripts\release.ps1 -AllowDirty -SkipTests
```

This command is for local verification only. It still resolves packages, checks
diff whitespace, builds the Windows release exe, builds the Android release APK,
runs the Windows release smoke test, verifies the copied APK manifest with `apkanalyzer`,
uses the same resolved Android SDK `aapt2` binary for compiled XML inspection,
and writes the Windows zip, Android APK, checksum file, release metadata JSON,
and release notes markdown to `dist/`. It records the dirty-worktree and
skipped-test flags in release metadata, along with the Windows smoke result,
WebDAV static smoke result, and runtime supported
language set (`zh` and `en`). It also records the release notes file record
so the markdown used for GitHub Release publishing is auditable from metadata.
Do not use `-AllowDirty` or `-SkipTests` with
GitHub Release publishing. Publishing also reads the GitHub Release asset list
after upload, rejects stale extra assets, requires GitHub to report each asset
as fully uploaded, then downloads each uploaded asset and compares its SHA-256
hash with the packaged local file.
Publishing also requires real QA records: pass
`-WindowsManualQaResultJson dist\windows-manual-qa.json`,
`-WebDavLiveSmokeResultJson dist\webdav-live-smoke.json`,
`-WebDavDomesticLiveSmokeResultJson dist\webdav-domestic-live-smoke.json`, and either
`-RunAndroidDeviceSmoke` or
`-AndroidDeviceSmokeResultJson dist\android-device-smoke.json`. The script
rejects skipped Windows manual QA, skipped generic WebDAV live smoke, skipped
domestic WebDAV live smoke, and skipped Android device smoke records on the
public GitHub Release path, and it rejects using both Android smoke sources in
the same release run.
For GitHub Actions publishing, first run the normal package job, then dispatch
`.github/workflows/qa-evidence.yml` on a self-hosted Windows x64 QA runner with
that package run ID. The QA workflow downloads the exact candidate, binds the
Windows manual QA record to its extracted `repapertodo.exe` and `data/app.so`,
runs generic and Jianguoyun live WebDAV checks, runs the connected Android
device smoke, and uploads a `repapertodo-qa-evidence` artifact. Finally dispatch
the release workflow with `publishRelease: true` and `qaEvidenceRunId` set to
the QA workflow run ID. The publish job downloads all four JSON files and
passes them explicitly to `scripts/release.ps1`.
The script also reads `PaperTodoStrings.supportedLocales` before packaging and
fails if the runtime language list drifts away from Chinese and English.
Use `scripts/release_readiness_audit.ps1` when you want the same release
blockers summarized without building or uploading artifacts:

```powershell
.\scripts\release_readiness_audit.ps1 `
  -WindowsManualQaResultJson dist\windows-manual-qa.json `
  -ExpectedWindowsReleaseDirectory build\windows\x64\runner\Release `
  -WebDavLiveSmokeResultJson dist\webdav-live-smoke.json `
  -WebDavDomesticLiveSmokeResultJson dist\webdav-domestic-live-smoke.json `
  -AndroidDeviceSmokeResultJson dist\android-device-smoke.json `
  -ExpectedAndroidApkFileName repapertodo-android-<version>.apk `
  -ExpectedAndroidApkPath dist\repapertodo-android-<version>.apk `
  -ReleaseMetadataJson dist\repapertodo-<version>-release.json `
  -ReleaseChecksumsFile dist\repapertodo-<version>-sha256.txt
```

It emits JSON with `readyForGitHubRelease`, per-check status, and blockers for
the clean tree, Android release signing, Windows manual QA, expected Windows
exe and `data/app.so` byte/hash matching when a release directory is supplied,
generic and domestic live WebDAV QA, Android 14-17/API 34-37 device smoke,
expected APK byte/hash matching when an APK path is supplied, release metadata
JSON/checksum file names, `version`/`tagName`, and artifact file names matching
`pubspec.yaml`, runtime/static-smoke evidence, release metadata artifact file
name, byte-count, and SHA-256 matching against the neighboring Windows zip and
Android APK files,
checksum-file line matching for the Windows zip, Android APK, metadata JSON, and
release notes markdown, metadata release notes file name/byte/hash matching the
neighboring release notes markdown, metadata Flutter/Dart toolchain fields
matching the current `flutter --version --machine` output, metadata
`pubspec.lock` byte/hash matching against the current dependency lock, and the
runtime language set (`zh` and `en`). Add
`-FailOnBlocked` only when a blocked audit should fail the command.
It also emits `readyForLocalRelease` and `localBlockers`. A dirty worktree and
an explicitly deferred multi-monitor QA item block GitHub publishing but do not
block a local release candidate; use `-FailOnLocalBlocked` for that local gate.
The Windows release smoke and Android smoke validation run inside release
packaging. The Android smoke validation can also be run directly after an APK
build:

```powershell
.\scripts\android_smoke.ps1
```

It verifies the actual APK manifest, including Android 14-17 SDK settings, the
APK application ID, release non-debuggability, launcher Activity
singleTop/empty-task-affinity behavior, INTERNET permission, no broad
external-storage permissions, the FileProvider declaration, the compiled
`@xml/file_paths` resource, package-visibility queries, the intentional
cleartext flag required for generic HTTP WebDAV endpoints, and localized APK
resource configurations.
Those localized resource configurations must stay within the runtime language
set (`zh` and `en`). When run with `-ResultJson`, it writes a structured smoke
result with the resolved Android SDK tools, APK file name, package id, APK
application ID, launcher Activity contract, SDK values, permissions,
FileProvider resource, cleartext WebDAV flag, broad-storage permission absence,
localized resource configuration result, and UTC check time. Release packaging records this static smoke result in metadata
by default and revalidates that the recorded APK path is the packaged Android
APK in `dist/`.

For an optional connected-device or emulator smoke test, build the APK, start
one Android 14-17/API 34-37 device, then run:

```powershell
.\scripts\android_device_smoke.ps1
```

The device smoke script resolves `apkanalyzer` and `adb`, verifies the APK
application ID is `com.aligez.repapertodo`, selects the only online device
unless `-DeviceSerial` is provided, verifies the connected API level is 34-37,
installs the APK without uninstalling existing app data, launches
`com.aligez.repapertodo`, checks that the package process appears and remains
foreground, then force-stops the app even when launch validation fails. It is
not part of the default release script because CI
and local machines may not have an Android device attached, but it is the
preferred runtime proof before publishing an APK. When run with `-ResultJson`,
it writes a structured smoke result with the resolved adb and apkanalyzer
paths, device serial, API level, package name, APK application ID, APK file
name, APK byte count, APK SHA-256, launch wait, observed process ID, and UTC
check time. Release packaging revalidates that this APK file name, byte count,
and SHA-256 match the packaged Android APK when the device smoke runs.

The release build includes an explicit R8 keep rule for
`androidx.work.impl.WorkDatabase_Impl`. WorkManager constructs this generated
Room database class reflectively during Android startup; removing its
no-argument constructor makes the release APK crash before Flutter renders, so
device smoke is required in addition to manifest/static APK inspection.

`tool/local_webdav_server.dart` provides a repository-local authenticated
WebDAV endpoint for emulator protocol QA. It implements the HEAD, GET, PUT,
DELETE, MKCOL, and PROPFIND methods used by RePaperTodo and writes a JSON-lines
request log. An Android emulator reaches a host instance through
`http://10.0.2.2:<port>/`. Passing this local protocol test proves the real
WorkManager/headless-Dart/network/storage path, but it does not replace live
compatibility checks against generic or domestic WebDAV providers.
Release evidence scripts that write `-ResultJson` require a `.json` file path
without wildcard or control characters. Android device smoke validates this
before installing or launching the APK, and live WebDAV smoke validates it
before reading provider credentials.
Release packaging and readiness audit use the same input JSON path checks when
they consume existing Windows manual QA, WebDAV live smoke, Android device
smoke, or release metadata evidence.
Readiness audit also requires the Android device smoke expected APK file name
and path to match the current `pubspec.yaml` artifact version before accepting
the APK hash evidence.
To include the same runtime check in release packaging metadata, pass
`-RunAndroidDeviceSmoke`; add `-AndroidDeviceSerial <adb-serial>` when multiple
devices are connected. To include a device smoke result that was already
recorded for the same APK file name and hash, pass
`-AndroidDeviceSmokeResultJson dist\android-device-smoke.json` instead. If
release packaging skips the device smoke, it still records the UTC skip time
and recovery hint in metadata:

```powershell
.\scripts\release.ps1 -AllowDirty -SkipTests -SkipBuild -RunAndroidDeviceSmoke -AndroidDeviceSerial 192.168.1.10:5555
```

For a local Windows release executable smoke test after a Windows release build,
use:

```powershell
.\scripts\windows_smoke.ps1
```

The smoke script copies `build/windows/x64/runner/Release` to an ignored
workspace `.tmp/` directory, starts that isolated `repapertodo.exe`, verifies a primary instance
can create its initial `data.json`, forwards secondary `--hide` and an unknown
startup command to confirm unknown-only arguments do not restore hidden papers,
forwards secondary `--new-note` and `--new-todo` startup commands to the primary
instance, waits for those papers to persist, requires one visible top-level HWND
per visible paper, forwards `--settings`, requires one additional visible
coordinator HWND while settings is open, closes it, and proves the independent
paper HWND count and persisted visibility are unchanged before forwarding
`--exit` and removing the temp copy. This keeps
smoke-test state out of the build output while still exercising the real
packaged Windows runner. When run with `-ResultJson`, it
writes a structured smoke result with the checked EXE file name, source release
directory, initial/final persisted paper counts, note/todo type count increases
from forwarded startup commands, the ignored unknown startup command evidence,
the settings coordinator lifecycle counts, timeout settings, and UTC check time.
Release packaging records this Windows smoke result in metadata by
default and revalidates that the recorded source release directory is the current
Windows build output with `repapertodo.exe`, `flutter_windows.dll`, and `data`.
The Release directory also carries the app-local MSVC and Universal CRT DLLs,
so a clean Windows 10 machine does not need a separate Visual C++ Redistributable
installation before starting the application.
Create the user-facing layered ZIP with
`scripts/package_windows_zip.ps1`. Its root contains only the statically linked
`repapertodo.exe` launcher; the Flutter executable, engine, CRT DLLs, assets,
and AOT data are stored under `runtime/`.

Runtime diagnostics are written as daily `.txt` files under `LOG` beside the
configured `data.json`. Entries record settings, paper lifecycle/state, startup,
and sync events without card text or credential values, and files older than
seven calendar days are deleted automatically.

For focused Windows parity QA on a real desktop session, first build the
Windows release exe, manually exercise the current build, then record the
results with:

```powershell
.\scripts\windows_manual_qa.ps1 `
  -TransparentBorderlessFeel pass `
  -TaskSwitcherVisibility pass `
  -MultiMonitorEdgeDocking pass `
  -FullscreenAvoidance pass `
  -TrayAfterExplorerRestart pass `
  -LongRunningScriptCapsule pass `
  -IndependentPaperSurfaces pass `
  -Tester "$env:USERNAME" `
  -ResultJson dist\windows-manual-qa.json
```

This manual QA record covers the Windows behaviors that cannot be proven by the
headless smoke scripts: transparent borderless paper feel, task-switcher
visibility, multi-monitor edge docking, and end-user interaction quality. The release pipeline also
runs `scripts/windows_policy_smoke.ps1`, which removes and recovers the real
notification icon through `TaskbarCreated`, then uses a separate fullscreen
process to verify topmost avoidance and restoration. The same policy smoke
executes a persistent 20-second script capsule, opens settings while it is
still running, and verifies the PowerShell worker is removed on app exit.
Manual QA retains those checks as an end-user confirmation on the target
desktop. Skipped items fail by default; `-AllowSkipped` is only for exploratory
non-publishable records. When only a single-monitor workstation is available,
pass `-MultiMonitorEdgeDocking skip`, `-DeferMultiMonitor`, `-Tester <name>`,
and `-Notes <reason>`. This creates `passedWithDeferredMultiMonitor` evidence
accepted only for a local release candidate. All other six items must pass, and
public GitHub Release publishing continues to require the multi-monitor item to
pass.
Passed records also bind the observation to the concrete build by recording the
source release directory plus byte counts and SHA-256 hashes for
`repapertodo.exe` and `data/app.so`, and they require a non-empty tester name;
release packaging rechecks those values against the current Windows release output
before accepting the evidence.
Pass a real result into release packaging with
`-WindowsManualQaResultJson dist\windows-manual-qa.json`. When omitted, release
metadata and release notes keep an explicit skipped Windows manual QA record
with a UTC timestamp and recovery hint.

For a local WebDAV sync static smoke test, use:

```powershell
.\scripts\webdav_smoke.ps1
```

The script does not need real WebDAV credentials. It audits the source and test
suite for generic HTTP/HTTPS WebDAV support, Jianguoyun WebDAV preset support,
encrypted payload enforcement, operation-log sync support, a Windows/Android
two-store operation-log round trip, a local HTTP WebDAV protocol round trip,
and the Android background sync absolute `data.json` state-path gate.
When run with `-ResultJson`, it writes a structured smoke result with those
booleans, repository-relative evidence file paths, and UTC check time. The
evidence paths must stay inside the repository and point at real files. Release
packaging records this WebDAV static smoke result in metadata by default and
revalidates those evidence paths while checking the release metadata file.

For real-provider WebDAV QA, set credentials in environment variables and run
the live smoke script:

```powershell
$env:REPAPERTODO_WEBDAV_ENDPOINT = "https://dav.example.com/dav/"
$env:REPAPERTODO_WEBDAV_USERNAME = "user@example.com"
$env:REPAPERTODO_WEBDAV_PASSWORD = "<provider-app-password>"
$env:REPAPERTODO_WEBDAV_PASSPHRASE = "<sync-encryption-passphrase>"
$env:REPAPERTODO_WEBDAV_ROOT = "repapertodo-live-smoke"
.\scripts\webdav_live_smoke.ps1 -ResultJson dist\webdav-live-smoke.json
```

For Jianguoyun, `REPAPERTODO_WEBDAV_PASSWORD` must be the generated password
from Third-party app management. The normal account login password returns HTTP
401. `REPAPERTODO_WEBDAV_PASSPHRASE` is a separate RePaperTodo encryption value
and is never used for HTTP authentication.

For the required domestic-provider QA, set
`REPAPERTODO_WEBDAV_PROVIDER=jianguoyun` against a Jianguoyun account and write
a separate result:

```powershell
$env:REPAPERTODO_WEBDAV_PROVIDER = "jianguoyun"
.\scripts\webdav_live_smoke.ps1 -ResultJson dist\webdav-domestic-live-smoke.json
```

The live script invokes `tool/webdav_live_smoke.dart`, creates a unique remote
root under `REPAPERTODO_WEBDAV_ROOT`, simulates Windows and Android stores with
separate device IDs, uploads an encrypted snapshot, downloads it on the second
store, uploads an Android-side operation log, merges it back on the Windows
store, writes structured JSON with UTC start/check timestamps, a relative
`.../run-*` remote root, positive `windows-live-smoke` and
`android-live-smoke` device sequences, and the remote cleanup status, then
deletes the temporary remote root unless `REPAPERTODO_WEBDAV_KEEP_REMOTE=true`
is set. Keep credentials in environment variables so they do not appear in
shell history.
Pass real results into release packaging with
`-WebDavLiveSmokeResultJson dist\webdav-live-smoke.json` and
`-WebDavDomesticLiveSmokeResultJson dist\webdav-domestic-live-smoke.json`.
When omitted, release metadata and release notes keep explicit skipped WebDAV
live smoke records with UTC timestamps and recovery hints.

To include both optional QA records in a local package after the artifacts
already exist, run:

```powershell
.\scripts\release.ps1 -AllowDirty -SkipTests -SkipBuild `
  -WindowsManualQaResultJson dist\windows-manual-qa.json `
  -WebDavLiveSmokeResultJson dist\webdav-live-smoke.json `
  -WebDavDomesticLiveSmokeResultJson dist\webdav-domestic-live-smoke.json
```

## Android Gradle Compatibility

`android/gradle.properties` intentionally keeps `android.newDsl=false` and
`android.builtInKotlin=false` while the current Flutter Gradle plugin is used
with Android Gradle Plugin 9. Removing those compatibility switches makes the
Android project fail during Gradle configuration before APK packaging starts.
Use the following quick configuration-phase check when adjusting Android build
logic; it should pass before running APK packaging:

```powershell
Push-Location android
.\gradlew.bat tasks --no-daemon
Pop-Location
```

## Local State Safety

`StateStore` writes `data.json.tmp` before replacing `data.json`, rotates the
previous primary file to `data.backup.json`, and loads a valid temp file if an
interrupted save leaves the primary missing. A corrupt temp file must not block
fallback to the stable backup. Save calls are serialized inside `StateStore`
itself, and each call encodes its JSON snapshot before entering the write queue
so an older asynchronous save cannot overwrite a newer state. Temporary state
and device-ID files are flushed before they replace their primary files, and
device-ID creation is serialized per normalized file path so overlapping sync
startup paths keep one stable local device identity.
When a corrupt primary, temp file, or backup triggers recovery, preserving
`*.failed_load.*` and `*.used_for_recovery.*` audit copies is best-effort only;
copy failures must not block loading an already decoded valid state.
If recovery loads a temp file or backup while a failed primary still exists, the
first successful save must skip backup rotation so the known-good
`data.backup.json` is not overwritten by the failed primary.
Unhandled Flutter, platform-dispatcher, or zone errors synchronously write the
current in-memory state to `data.crash_recovery.json` beside the primary data
file, with a flushed `RePaperTodo.crash.log`, without mutating the live state.
Crash logs append new failures and follow PaperTodo's bounded diagnostic model:
when the previous log exceeds 100 KB, preserve the last 80 KB with a trim marker
before writing the new crash entry.

`AppStateCodec` treats PaperTodo `data.json` as a compatibility boundary. Before
decoding, it tolerates UTF-8 BOMs, comments, and trailing commas like the
original PaperTodo `StateStore`, then migrates known legacy PaperTodo model keys
to the current camelCase RePaperTodo schema with case-insensitive matching,
while modern camelCase keys win if both versions are present. User-data map
keys, such as capsule queue names, must not be rewritten by this migration pass.
Retired PaperTodo fields without an active RePaperTodo setting, such as
`TopBarHeight`, should still be normalized to their camelCase key and preserved
in `AppState.extra` so migration remains non-destructive.
Sync provider values are normalized case-insensitively so legacy or hand-edited
`webDav` settings do not silently fall back to disabled sync.
Model enum-like values such as theme, paper type, markdown mode, visual size,
capsule side, queue side, and reminder units are also normalized
case-insensitively, then written back as canonical RePaperTodo values.
Hand-edited primitive values are tolerated when unambiguous: `true`/`false`,
integer strings, and finite decimal strings decode like their JSON primitive
counterparts before normal model clamping is applied.
`StateStore` tests must keep at least one representative PaperTodo fixture path
that loads through the real `data.json` store and saves back a canonical
RePaperTodo JSON file while preserving unknown future fields.

## Current Build Outputs

Build outputs are ignored by Git:

- `build/windows/x64/runner/Release/repapertodo.exe`
- `build/app/outputs/flutter-apk/app-debug.apk`
- `build/app/outputs/flutter-apk/app-release.apk`
- `dist/repapertodo-windows-x64-<version>.zip`
- `dist/repapertodo-android-<version>.apk`
- `dist/repapertodo-<version>-sha256.txt`
- `dist/repapertodo-<version>-release.json`
- `dist/repapertodo-<version>-release-notes.md`
