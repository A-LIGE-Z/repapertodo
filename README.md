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
- Runtime UI localization is limited to Chinese and English.
- No fixed budget ceiling for reaching feature parity and reliable sync.

## Current Status

This repository now contains a Flutter Windows/Android codebase with the shared
PaperTodo-compatible data model, desktop-first paper UI, local persistence,
platform-service boundaries, startup command handling, and WebDAV snapshot plus
operation-log sync foundations. Syncable edits are persisted with a local-only
durable outbox, so manual, debounced, startup, and Android background sync can
retry deterministic operation IDs after restart without losing local changes;
the outbox clears only after snapshot sync and remote operation merge succeed.

See [AGENTS.md](AGENTS.md) for project rules and [docs/ROADMAP.md](docs/ROADMAP.md) for the staged implementation plan.

## Release Build

Use the local release script to verify, build, and package the Windows and
Android artifacts. The script also writes release notes, including the
user-facing `CHANGELOG.md` Unreleased entries, and a SHA-256 checksum file
beside the artifacts in `dist/` that covers the Windows zip, Android APK,
release metadata JSON file, and release notes markdown file.
The script verifies that checksum file against the packaged files before upload
and also writes release metadata JSON with the version,
commit, Android 14-17/API 34-37 compatibility, signing mode, validation
commands, skipped validation commands for local smoke packages, package
resolution mode, Windows smoke result, WebDAV static smoke result, Android SDK
tool paths, Android static smoke result, optional Windows manual QA result,
optional generic and domestic WebDAV live smoke results, optional Android device smoke result,
Flutter/Dart toolchain versions, runtime supported languages (`zh` and `en`),
`pubspec.lock` hash, release notes file hash, and artifact hashes.
Before release notes or metadata are written, the script reads
`PaperTodoStrings.supportedLocales` and fails if the runtime language list is
anything other than Chinese and English in that order.
The script reads that metadata JSON back before checksumming it and verifies
that its UTC build timestamp, dependency lock, validation lists,
Windows smoke pass status, UTC timestamp, EXE file name, persisted paper
counts, startup command forwarding list, WebDAV static smoke pass status,
generic WebDAV support, Jianguoyun preset support, encrypted payload and
operation-log evidence, local HTTP WebDAV protocol round-trip coverage,
Windows/Android operation-log round-trip coverage, Windows manual QA skip/pass
status, generic and domestic WebDAV live smoke skip/pass status, Android SDK/signing fields,
Android SDK tool paths, Android static smoke pass status, UTC timestamp, SDK
values, APK file name, runtime language fields, toolchain fields, and artifact records match the files and command path that were just validated.
Checksum and metadata artifact file names must also stay safe single file names rather than paths,
artifact byte counts must be positive integers, and artifact hashes must be 64-character
lowercase SHA-256 values. The
generated Windows zip and Android APK are also opened before
checksumming so the packages must actually contain a non-empty
`repapertodo.exe`, the Flutter Windows runtime files
(`flutter_windows.dll`, `data/app.so`, `data/icudtl.dat`, and
`data/flutter_assets/FontManifest.json`), and Android APK runtime entries:
`AndroidManifest.xml`, `assets/flutter_assets/AssetManifest.bin`,
`assets/flutter_assets/FontManifest.json`, `lib/*/libapp.so`, and
`lib/*/libflutter.so`.
The copied APK is then inspected with `apkanalyzer` so its actual manifest
`min-sdk` and `target-sdk` values must match the Android 14-17/API 34-37
release configuration before checksums or metadata are written. The release
script resolves both `apkanalyzer` and `aapt2` from the Android SDK and passes
those exact tools into Android smoke validation, keeping local and CI package
checks on the same SDK toolchain. Android smoke
validation also checks that the
release APK has the expected application ID, is not debuggable, keeps the
launcher Activity singleTop/empty-task-affinity contract, keeps INTERNET and generic HTTP WebDAV cleartext support,
keeps WorkManager background sync services and network/wake/boot-reschedule permissions,
avoids broad external-storage
permissions, preserves FileProvider
sharing, dumps the compiled
`@xml/file_paths` resource to confirm that external sharing stays scoped to
`RePaperTodo` directories, and declares package-visibility queries for `http`,
`https`, `mailto`, Markdown/text files, and generic file viewers. When run
through release packaging, the same static smoke writes structured metadata
with the inspected APK file name, SDK values, resolved Android SDK tools,
APK application ID, permissions, FileProvider resource, cleartext WebDAV flag, broad-storage
permission absence, and APK localized resource configurations, which must stay
within the runtime language set (`zh` and `en`). Release metadata revalidates
that the static smoke APK path is the packaged Android APK in `dist/`.
The Windows release output is smoke-tested before packaging by copying the
built runner to a temporary directory, launching the isolated
`repapertodo.exe`, forwarding secondary `--new-note`, `--new-todo`, and
`--settings` startup commands, confirming the expected papers are persisted,
opening and closing the settings coordinator without changing paper visibility,
and enumerating the process top-level windows to prove every visible paper owns
an independent HWND before finally forwarding `--exit`.
The Windows smoke script writes the same evidence into structured metadata so
release packages record and revalidate the checked build output directory, EXE
name, initial/final paper and note/todo type counts, forwarded startup commands, timeout settings,
settings coordinator open/close HWND counts, and UTC check time.
The WebDAV static smoke script also runs during release packaging and records
that generic WebDAV remains present, the Jianguoyun preset is still available,
encrypted payloads are required for configured sync, operation logs remain
implemented, a local HTTP WebDAV protocol round-trip covers real
MKCOL/PUT/PROPFIND/GET traffic, a Windows/Android two-store round trip is
covered through the shared WebDAV operation-log path, Android registers a
WorkManager/headless Dart background sync task that reuses the shared WebDAV
StateStore path when secure sync is configured, Android background sync rejects
relative or non-`data.json` state-file paths before scheduling or running, and
the shared settings UI exposes the same sync model used by Windows and Android.
For real-provider QA, `scripts/webdav_live_smoke.ps1` reads WebDAV credentials
from `REPAPERTODO_WEBDAV_*` environment variables and runs the same
Windows/Android snapshot plus operation-log round trip against the configured
endpoint, writing structured JSON when requested. Publishable live evidence
must include positive `windows-live-smoke` and `android-live-smoke` device
sequences so the release gate proves both sides used the shared operation-log
path, plus UTC start/check timestamps, a relative `.../run-*` remote root, and
a recorded remote cleanup status.
Release packaging records skipped Windows manual QA and WebDAV live smoke
entries by default. To include real generic WebDAV QA evidence in local release metadata and
release notes, pass:

```powershell
.\scripts\release.ps1 -AllowDirty -SkipTests -SkipBuild `
  -WindowsManualQaResultJson dist\windows-manual-qa.json `
  -WebDavLiveSmokeResultJson dist\webdav-live-smoke.json
```

When an Android 14-17/API 34-37 device or emulator is available,
`scripts/android_device_smoke.ps1` can also verify the APK application ID,
install the APK, launch `com.aligez.repapertodo`, confirm the package process
starts, confirm the launched package remains foreground, and force-stop it
without uninstalling existing app data, including when launch validation fails.
This optional runtime smoke is kept out of the default release script so headless CI
packaging remains possible. Pass `-RunAndroidDeviceSmoke` to
`scripts/release.ps1` to include it in local release metadata, and pass
`-AndroidDeviceSerial` when more than one adb device is online. When it runs
through the release script, metadata records the resolved adb and apkanalyzer
paths, device serial, API level, package name, APK application ID, APK file
name, APK byte count, APK SHA-256, launch wait, observed process ID, and
foreground package. Release metadata revalidates that this device-smoked APK
file name, byte count, and SHA-256 match the packaged Android APK and that the
foreground package matches the launched package. When it is skipped, metadata
still records the UTC skip time and the
`-RunAndroidDeviceSmoke` recovery hint.

For emulator-only background protocol QA, `tool/local_webdav_server.dart` can
serve an authenticated WebDAV root from the repository. The API 35 release
runtime has been verified through a real WorkManager background Dart isolate,
including encrypted snapshot and operation-log uploads. This local endpoint is
test evidence for the Android background path, not evidence of compatibility
with a third-party WebDAV provider.
Release evidence scripts that write `-ResultJson` validate the result path
before doing the expensive or credentialed work: it must be a `.json` file path
without wildcard or control characters, so smoke and QA evidence is captured
before it can be reused by release packaging.
Release packaging and readiness audit apply the same `.json` path rules when
they read external QA or smoke evidence files.
Readiness audit also requires the Android device smoke expected APK file name
and path to match the current `pubspec.yaml` artifact version before the APK
hash evidence is accepted.
The script also rejects package entries with absolute paths, parent-directory
segments, blank or whitespace-padded path segments, or control characters
before checksums are written. Windows zip entries are created with normalized
forward-slash paths, so the package layout is stable across PowerShell hosts and
unzip tools.
Windows packaging is staged outside the release build folder first, so
local runtime state such as `data.json`, backup/recovery JSON files, temp files,
and crash/fullscreen logs are excluded even if the built exe was run locally.
Validation includes `git diff --check`, tests, analysis, Windows/APK release
builds, and Windows/WebDAV/Android smoke scripts. Release packaging reads the Android Gradle SDK settings and stops if they drift from Android 14-17/API 34-37.
Before artifact paths or release metadata are generated, the script validates
the `pubspec.yaml` version as SemVer, converts it to a filename-safe artifact
version token, rejects unsafe GitHub Release tags, and rejects release titles
with leading/trailing whitespace or control characters.

The same release script is wired into GitHub Actions. Pushes and pull requests
to `main` run the full validation, build, and package flow, then upload the
packaged `dist/` files as workflow artifacts from a read-only `contents`
permission job. Manual `workflow_dispatch` runs with `publishRelease: true`
use a separate write-permission job that reruns the full validation, build,
package, and GitHub Release publish path. Publishing also requires a
`qaEvidenceRunId`: the run ID from `.github/workflows/qa-evidence.yml` whose
`repapertodo-qa-evidence` artifact contains the four build-bound QA records.
That evidence workflow runs on a self-hosted Windows x64 runner because it
needs a real desktop session, an Android API 34-37 device or emulator, and
generic plus Jianguoyun WebDAV credentials. It downloads the packaged
candidate identified by `candidateRunId`, records the seven Windows manual QA
results against the extracted exe, runs both live WebDAV checks and the Android
device smoke, then uploads the JSON evidence consumed by the publish job.

The GitHub Actions release sequence is therefore:

1. Run the package workflow for the intended commit and retain its run ID.
2. Manually verify that candidate, then dispatch `Collect Release QA Evidence`
   with the package run ID on the configured self-hosted QA runner.
3. Dispatch `Build and Release` with `publishRelease: true` and
   `qaEvidenceRunId` set to the completed QA evidence run ID.

```powershell
.\scripts\release.ps1
```

To also create or update the GitHub Release for the version in `pubspec.yaml`:

```powershell
.\scripts\release.ps1 -PublishGitHubRelease `
  -AndroidDeviceSmokeResultJson dist\android-device-smoke.json `
  -WindowsManualQaResultJson dist\windows-manual-qa.json `
  -WebDavLiveSmokeResultJson dist\webdav-live-smoke.json `
  -WebDavDomesticLiveSmokeResultJson dist\webdav-domestic-live-smoke.json
```

Publishing checks `gh auth status` before running the expensive Flutter
validation and build steps. It accepts `GH_TOKEN` or `GITHUB_TOKEN` when the
environment provides one, and otherwise expects an authenticated GitHub CLI
session, so missing or expired GitHub credentials fail early with a direct
`gh auth refresh -h github.com` or `gh auth login -h github.com` recovery
command.
Publishing also fetches `origin/main` and requires the local `main` HEAD to
match it before building, so release metadata, artifacts, and the GitHub tag
all point at the same commit.
New release tags are created against the validated commit SHA, not a moving
branch name.
GitHub Release publishing also requires the tag to match the `pubspec.yaml`
version exactly as `v<version>`, so a package built from one version cannot be
published under a different public tag.
If the target tag already exists on GitHub, it must already point to the same
commit being packaged; otherwise the script stops so a reused version cannot
publish new artifacts under an old tag.

When the tag already has a GitHub Release, the script updates the release title
and notes before clobbering the Windows, Android, checksum, metadata, and
release notes artifacts.
After either creating or updating the GitHub Release, the script reads the
release asset list back from GitHub and verifies that each uploaded artifact
exists exactly once, that no stale extra assets remain on the Release, and
that each asset is reported by GitHub as fully uploaded with the same byte count
as the packaged local file. It
then downloads each uploaded asset to a temporary directory and compares its
SHA-256 hash with the packaged local artifact before the publish step can pass.

By default the release script refuses to package a dirty git working tree so
the artifact metadata commit matches the files being shipped. For a local-only
smoke package from uncommitted changes, pass `-AllowDirty`. Local smoke
packages made with `-AllowDirty` record `dirtyWorkingTreeAllowed: true` in the
release metadata JSON, and packages made with `-SkipTests` or `-SkipBuild`
record those skipped validation steps there as well. The metadata also records
whether dependencies were resolved with `flutter pub get`,
`flutter pub get --offline`, or skipped because both tests and builds were
skipped.
The clean-tree check also runs again immediately before packaging, so package
resolution or generated project files cannot drift away from the metadata
commit unnoticed.
That packaging check compares real working-tree, staged, and untracked content
after refreshing Git's index, so Flutter's Windows build can touch generated
plugin files without falsely failing the release when their normalized content
is unchanged.

GitHub Release publishing always requires the full validation path. The script
will refuse `-PublishGitHubRelease` when it is combined with `-SkipTests`,
`-SkipBuild`, or `-AllowDirty`. It also refuses publishing unless the release
run includes passed Windows manual QA evidence, passed generic/custom WebDAV
live smoke evidence, passed Jianguoyun/domestic WebDAV live smoke evidence, and
passed Android 14-17/API 34-37 device or emulator smoke evidence.
Android runtime smoke evidence may come from `-RunAndroidDeviceSmoke` on a
connected device/emulator or from a previously generated
`-AndroidDeviceSmokeResultJson` record; the script rejects using both sources
in the same release run.
The publish workflow downloads those four JSON files from the explicitly
selected QA evidence run and passes every path to `release.ps1`; missing or
stale evidence therefore fails before any GitHub Release assets are replaced.

To inspect those publish gates without building, uploading, or touching remote
services, run the release readiness audit:

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

The audit prints structured JSON with `readyForGitHubRelease`, individual
check results, and blockers for the clean tree, Android signing, Windows manual
QA, expected Windows exe and `data/app.so` byte/hash matching when a release
directory is supplied, generic and domestic live WebDAV QA, Android 14-17 device
smoke, expected APK byte/hash matching when an APK path is supplied, release
metadata JSON/checksum file names, metadata `version`/`tagName`, and artifact
file names matching `pubspec.yaml`, runtime/static-smoke checks, release
metadata artifact file name, byte-count, and SHA-256 matching against the
neighboring Windows zip and Android APK files,
checksum-file line matching for the Windows zip, Android APK, metadata JSON, and
release notes markdown, metadata release notes file name/byte/hash matching the
neighboring release notes markdown, metadata Flutter/Dart toolchain fields
matching the current `flutter --version --machine` output, metadata
`pubspec.lock` byte/hash matching against the current dependency lock, and the
runtime language set (`zh` and `en`). Add
`-FailOnBlocked` when the audit should act as a CI gate.

If dependencies are already cached and network access to pub.dev is unreliable,
use offline package resolution:

```powershell
.\scripts\release.ps1 -OfflinePubGet
```

When using `-SkipBuild`, existing Windows and Android release artifacts must
already be present under `build/`; otherwise the script stops with a direct
message telling you to rerun without `-SkipBuild`. The Windows release folder
must include `repapertodo.exe` plus the Flutter Windows runtime files, and the
Android APK path must point to an APK file.

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
debug fallback and records that mode in GitHub Release notes. Those notes also
include whether a dirty working tree was allowed, which package resolution mode
was used, user-facing `CHANGELOG.md` Unreleased entries, the runtime UI
language set (`zh` and `en`), the Flutter and Dart toolchain versions, and
which validation commands were executed or skipped. They also include a
verification summary with the Windows smoke result, WebDAV static smoke result,
Android APK application ID and SDK values, Windows note/todo startup-command
counts, Android launcher Activity contract, and optional Android device smoke
status.
Windows desktop parity that requires observation in a real user session can be
recorded with `scripts/windows_manual_qa.ps1`. That script requires explicit
pass/fail/skip results for transparent borderless feel, task-switcher
visibility, multi-monitor edge docking, fullscreen avoidance, tray recovery
after Explorer restarts, long-running script capsules, and independent paper
surfaces; skipped items fail unless `-AllowSkipped` is used for exploratory
records. Passed records also include the byte counts and SHA-256 hashes for
`repapertodo.exe` and `data/app.so`, the source release directory, plus a non-empty tester name,
the Windows version string, and exactly the expected seven checked parity items;
release packaging verifies those values against the current Windows release build
before using the manual QA evidence.
The script treats
the release signing config as present only when all four properties are filled
and `storeFile` points to an existing keystore file. Signing property values
must not contain control characters, and `storeFile` must not contain wildcard
characters, absolute paths, or dot-segments such as `.` or `..`. The same validation also runs
inside the Android Gradle build, and Gradle uses the same trimmed signing
values that the release script validates, so direct APK builds cannot use
weaker signing rules than the release script. Local smoke packages may use the
debug fallback, but
`-PublishGitHubRelease` refuses to publish unless Android release signing comes
from `android/key.properties`.

GitHub Actions can create `android/key.properties` during a manual publish run
when these repository secrets are configured. The workflow validates the
keystore base64, password, and alias secrets before writing
`android/key.properties` by calling `scripts/configure_android_signing.ps1`,
then clears those signing secret environment variables from the step in a
`finally` block, so CI fails with a clear signing-secret error instead of
producing a malformed properties file or leaving secrets in the process
environment. If any Android signing secret is present, all four secrets must be
present; otherwise the signing configuration step fails instead of silently
falling back to debug signing.
The signing configuration script also rejects unsafe `storeFile` override
values with control characters, wildcard characters, absolute paths, or
dot-segments before it writes `android/key.properties` or the keystore.

The required secrets are:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded contents of
  `android/repapertodo-release.jks`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
