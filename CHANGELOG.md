# RePaperTodo Changelog

## Unreleased

- Added a Dart controller one-shot exit guard so repeated tray, forwarded, or
  session-ending exit requests cannot duplicate platform cleanup.
- Shared duplicate UI exit requests through one save/sync-before-exit future so
  repeated exit commands cannot upload or final-sync twice before cleanup.
- Ignored late startup, tray open/delete, and native hidden-surface events while
  exit save/sync is active so shutdown retries cannot mutate papers.
- Restricted Android background WebDAV sync registration and execution to
  absolute `data.json` state paths.
- Clarified GitHub Release publishing authentication so `GH_TOKEN`/
  `GITHUB_TOKEN` failures are reported separately from missing CLI login.
- Gave release packaging a longer Windows smoke startup/exit window so slower
  hosts can still verify secondary startup command persistence.
- Rejected absolute Android signing `storeFile` values across the signing
  setup script, Gradle build, release packaging, and readiness audit.
- Required Windows manual QA release evidence to include a Windows version
  string and exactly the expected desktop parity checklist.
- Allowed release packaging to consume a previously recorded Android device
  smoke JSON result while still rejecting mixed live/result smoke sources.
- Required passed Windows manual QA, live WebDAV smoke, and Android device
  smoke evidence before GitHub Release publishing can run.
- Split Windows paper-surface registry refresh onto a dedicated
  `setPaperSurfaces` native channel instead of relying on tray-menu rebuilds.
- Added optional Windows manual QA and live WebDAV QA result inputs to release
  packaging metadata and generated release notes.
- Updated the roadmap to separate completed automated coverage from the
  Windows, live WebDAV provider, Android runtime, and release readiness checks
  still required before claiming full PaperTodo replacement parity.
- Added a project rule test that keeps roadmap completion-audit boundaries
  explicit while Windows parity, live WebDAV QA, Android runtime smoke, and
  signed release readiness remain unfinished.
- Queued foreground/background silent WebDAV sync requests behind an active
  sync so Android backgrounding does not drop the last opportunistic sync pass.
- Extended Android APK smoke evidence to verify the launcher Activity contract,
  including singleTop launch mode, empty task affinity, adjustResize, hardware
  acceleration, and MAIN/LAUNCHER intent entries.
- Extended Windows release smoke evidence so forwarded `--new-note` and
  `--new-todo` commands must increase persisted note and todo paper counts, not
  only the total paper count.
- Added Windows note/todo startup-command counts and Android launcher Activity
  contract details to generated GitHub Release notes.
- Added WebDAV retry-message coverage so cleaned provider response details are
  not shown when they duplicate the primary WebDAV failure message.
- Added an Android WorkManager/headless Dart background sync entrypoint that
  reloads the local StateStore and reuses the shared WebDAV sync service.
- Extended Android APK and release metadata smoke checks to verify WorkManager
  background sync services and network/wake/boot-reschedule permissions.
- Added a credentialed live WebDAV smoke entrypoint for real-provider
  Windows/Android snapshot and operation-log round-trip QA.
- Added a structured Windows manual QA recording script for desktop parity
  evidence that requires a real user session.
- Retargeted legacy Windows paper-surface events to the next visible paper
  after the active registered paper is explicitly hidden or closed from either
  native events or Dart platform calls.
- Retargeted legacy Windows paper-surface events when an active paper becomes
  hidden through a surface update before native callbacks finish.
- Retargeted Windows paper-surface legacy events after state refreshes hide the
  previously active registered paper.
- Counted visible non-active registered Windows paper surfaces when native
  toggle logic asks whether any paper is still visible.
- Strengthened Android device smoke evidence by requiring the launched APK to
  remain the foreground package after startup.
- Removed broad Android foreground-package fallback matching so device smoke
  only trusts focused or resumed activity records.
- Force-stopped the Android package from device smoke cleanup even when launch
  validation fails.
- Added local HTTP WebDAV protocol round-trip coverage for snapshot and
  operation-log sync evidence.
- Required uploaded GitHub Release assets to report an explicit `uploaded` state before publish verification can pass.
- Rejected stale extra assets on GitHub Releases during publish verification.
- Normalized local model IDs before generating WebDAV operation-log diffs.
- Stripped raw control characters from stored paper, todo item, linked note, and note-canvas IDs before Windows/WebDAV persistence.
- Verified published GitHub Release assets by downloading them and comparing SHA-256 hashes.
- Added a project rule test that requires every UI string key to have Chinese and English entries.
- Revalidated Android device smoke APK file names while checking release metadata.
- Revalidated Android static smoke APK paths while checking release metadata.
- Revalidated Windows smoke release directories while checking release metadata.
- Revalidated WebDAV static smoke evidence paths while checking release metadata.
- Hardened WebDAV static smoke evidence so release metadata references only real repository files.
- Added a UTC timestamp to skipped Android device smoke metadata and release notes for release auditability.
- Tightened Android signing setup so partially configured CI signing secrets fail before packaging.
- Recorded the GitHub Release notes markdown file in release metadata with byte count and SHA-256 evidence.
- Added a two-device WebDAV operation-log round-trip test for Windows/Android sync parity.
- Added structured WebDAV static smoke metadata for release packaging.
- Recorded structured Windows release smoke results in release metadata.
- Verified idempotent local WebDAV operation uploads still reapply canonical state to Windows platform integrations before the next sync.
- Added end-to-end StateStore coverage for representative PaperTodo data migration and canonical resave behavior.
- Limited Android APK localized resources to the supported Chinese and English runtime languages.
- Kept settings explanation help available when ordinary operation tooltips are disabled, matching PaperTodo's tooltip setting boundary.
- Allowed file-name-safe external Markdown suffixes such as `.todo.md` instead of limiting users to common Markdown extensions.
- Deferred silent WebDAV sync requests while settings are open and replayed them after unchanged settings close.
- Localized generic native platform open-file and open-link errors for Chinese and English UI.
