# RePaperTodo Roadmap

This roadmap tracks the current refactor state against the PaperTodo parity
goal. A green automated check is evidence for that specific behavior only; it
does not by itself prove full Windows feature parity.

## Status Legend

- Done: implemented and covered by automated tests or release smoke checks.
- In progress: implemented enough to exercise, but still needs hardening,
  broader parity work, or manual QA.
- Pending: planned and required before the app can be called a full PaperTodo
  replacement.

## Phase 0: Repository And Architecture

Status: Done.

- Flutter-first repository layout is in place.
- Project rules are recorded in `AGENTS.md`.
- Runtime UI localization is intentionally limited to Chinese and English.
- Shared domain code, platform boundaries, sync code, and release scripts are
  separated.

## Phase 1: Data Core

Status: Done for the shared core, still audited as new PaperTodo fields appear.

- PaperTodo-compatible papers, todo items, note content, note canvas elements,
  settings, capsule state, tombstones, and sync settings are modeled.
- Original PaperTodo `data.json` migration is covered by representative
  StateStore and codec tests.
- Local model IDs are normalized before storage, platform calls, and WebDAV
  operation diffs.
- Unknown forward-compatible fields are preserved where the compatibility layer
  can safely retain them.

## Phase 2: Windows MVP

Status: In progress.

- Windows Flutter shell, local persistence, tray menu, startup commands,
  single-instance forwarding, startup at login, external file opening, script
  capsules, and global hotkeys are implemented behind platform boundaries.
- Todo and note editing are implemented in the Flutter UI and covered by widget
  and controller tests.
- The Windows runner now creates one top-level HWND and one Flutter engine per
  visible paper, while the hidden primary engine remains authoritative for
  persistence, tray, startup commands, and sync. Automated runtime smoke
  enumerates the process windows and requires one visible HWND per visible
  paper; it also opens and closes the settings coordinator and requires the
  independent paper HWND count and persisted visibility to remain unchanged.
- Per-HWND always-on-top, task-switcher policy, desktop pinning,
  fullscreen/covered deep-capsule avoidance, and 92x46 collapsed capsule chrome
  are implemented in the runner.
- Remaining native-window parity work is real multi-monitor queue QA,
  transparency/drag-resize polish, and sustained desktop-session validation.

## Phase 3: Windows Feature Parity

Status: In progress.

- Implemented and tested in the shared/controller/UI layers: capsule mode,
  deep capsule queue state, master collapse-all state, linked notes, Markdown
  assistance, external Markdown/file opening, script capsule settings, global
  hotkeys, fullscreen/topmost mode, themes, settings, tooltips, and startup
  behavior.
- A structured Windows manual QA recording script is available for release
  evidence when these desktop behaviors are checked in a real user session.
- Still requiring focused Windows parity QA: transparent borderless feel,
  task-switcher visibility, multi-monitor edge docking, fullscreen avoidance
  under real foreground apps, tray interactions after Explorer restart, and
  long-running script capsule process behavior.

## Phase 4: Sync Core

Status: Done for the local-first core, with continued hardening.

- Stable device IDs, snapshots, per-device operation logs, canonical operation
  payloads, delete tombstones, and merge application are implemented.
- Local edits persist a deterministic durable outbox in `data.json`; restart,
  manual, debounced, startup, and Android background sync retry the same
  operation IDs until snapshot sync and operation-log merge both finish.
- Downloaded snapshots replay the durable local batch before merge, and the
  batch is removed only after the final merged state is saved.
- Sync avoids last-writer-wins whole-file replacement by using snapshots plus
  operation logs.
- Operation-log diffs normalize local model IDs before upload.
- Conflict handling preserves local data and exposes recovery paths.

## Phase 5: WebDAV

Status: Done for generic/Jianguoyun static coverage, still needs real-provider
compatibility QA.

- Generic HTTP/HTTPS WebDAV sync is implemented.
- Jianguoyun WebDAV remains available as the first domestic preset.
- WebDAV client coverage includes path safety, PROPFIND fallback, ETags,
  conditional writes, redirects, Retry-After hints, charsets, malformed
  multistatus bodies, encrypted payloads, and operation logs.
- Static smoke checks prove the shared Windows/Android WebDAV code path remains
  present without requiring credentials.
- A live WebDAV smoke entrypoint is available for credentialed provider QA; it
  runs a real remote Windows/Android snapshot and operation-log round trip
  against the configured endpoint.
- Required before stable replacement claim: live WebDAV QA against generic
  WebDAV and at least one domestic provider account.

## Phase 6: Android

Status: In progress.

- Android builds from the same Flutter codebase and shares the data model,
  settings, WebDAV sync core, and operation-log merge logic.
- Android registers a WorkManager-backed headless Dart WebDAV sync task when
  secure WebDAV settings are enabled, so the background path reuses the shared
  StateStore and sync service instead of duplicating merge logic in native
  Android code.
- Release configuration targets Android 14-17/API 34-37 and static APK smoke
  checks validate the manifest, permissions, FileProvider scope, cleartext
  WebDAV support, package visibility, and language resource set.
- The release APK now passes install, launch, process, and foreground-package
  smoke on an Android 15/API 35 AOSP ATD emulator. This runtime check also
  guards the WorkManager Room database constructor from R8 removal before
  Flutter starts.
- The same API 35 emulator has completed a real WorkManager background Dart
  run against the repository-local HTTP WebDAV server: the worker returned
  success, uploaded encrypted snapshot/operation/manifest files, and persisted
  its device sequence back to Android `data.json`.
- Required before stable replacement claim: repeat Android foreground and
  background sync against credentialed external WebDAV providers.

## Phase 7: Release Readiness

Status: In progress.

- Local release packaging builds and verifies the Windows zip, Android APK,
  SHA-256 file, release metadata JSON, and GitHub Release notes markdown.
- GitHub Release publishing flow is implemented with clean-tree enforcement,
  signing enforcement for public publish, tag/version validation, exact asset
  set checks, uploaded-state checks, size checks, and downloaded SHA-256
  verification.
- Local smoke packages may use `-AllowDirty`, `-SkipTests`, or `-SkipBuild`;
  public GitHub Release publishing rejects those shortcuts.
- Required before stable replacement claim: clean full release run from the
  intended commit, signed Android release configuration, live Android runtime
  smoke when a device/emulator is available, and manual Windows parity QA.
