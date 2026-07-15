# RePaperTodo Changelog

## Unreleased

- Restored normal Windows edge and corner resizing for both Todo and Note paper
  HWNDs by starting the native resize loop immediately on pointer-down and
  widening the visible resize target.
- Fixed desktop-pinned papers disappearing behind the Windows 11 wallpaper by
  keeping them as interactive top-level windows at `HWND_BOTTOM` instead of
  reparenting them into an unreliable `WorkerW` desktop layer.
- Locked desktop-pinned papers to the bottom layer without activation or
  dragging, leaving only the unpin control interactive and preventing the Todo
  header checkbox from accidentally unpinning the paper.
- Kept paper chrome anchored during native resizing, made capsules start native
  dragging on pointer-down, and removed the double-click and flash races when a
  capsule restores its paper.
- Moved Windows settings onto the hidden coordinator's dedicated window,
  removed paper taskbar buttons, and refresh capsule fullscreen hiding every
  250 ms for prompt restoration.
- Added a native Windows folder picker for first-run and settings-driven data
  directory selection with safe state relocation; Windows packaging remains the
  conventional release directory/zip containing the EXE and Flutter runtime.
- Added app-local MSVC and Universal CRT runtime libraries to Windows builds so
  the packaged application starts on Windows 10 without requiring a separately
  installed Visual C++ Redistributable.
- Reworked the Windows ZIP so its root contains only `repapertodo.exe`; a
  dependency-free launcher starts the Flutter executable and complete runtime
  from the nested `runtime/` directory.
- Fixed collapse-all queues and tray Show all by clearing stale queue state,
  restoring every paper in one native reconciliation, and routing capsule
  clicks by stable queue/paper identity.
- Added redacted daily text diagnostics under the data directory's `LOG`
  folder for settings, paper, application, and sync events, with automatic
  seven-day retention on Windows and Android.
- Added a manual sync action to every paper header and clarified that
  Jianguoyun requires its generated WebDAV app password rather than the account
  login password; authentication failures now give a provider-specific recovery
  message.
- Kept Todo columns in one row at compact paper widths with divider-only
  separation, and replaced large due-date dialogs/chips with a compact
  date-time selector and right-aligned relative/absolute due status.

- Made Jianguoyun conditional manifest updates compatible with its unquoted
  opaque ETags: sync still tries the standard quoted `If-Match` first, then
  retries the provider's original conditional value only after a 412, without
  ever falling back to an unconditional overwrite.
- Validate Jianguoyun's 30-character sandbox-name limit directly in WebDAV
  settings, with a focused inline recovery message instead of exposing a raw
  provider XML error only after sync starts.
- Reset stale durable outbox and remote device-sequence progress when the
  WebDAV endpoint, account, encryption passphrase, or remote folder changes,
  preventing a new sync target from entering a permanent conflict loop.
- Reworked the Android board around one PaperTodo paper surface instead of
  nested cards: compact 52px navigation, integrated 56px paper headers,
  borderless todo rows, an original-style plus append surface with compact
  undo/redo controls, a darker neutral desktop canvas, 44-48px touch targets,
  and the same phone layout in portrait and landscape across light and dark
  themes.
- Restored PaperTodo's persistent settings category rail with independently
  scrollable display, todo/note, capsule, general, and WebDAV sections; compact
  windows retain icon-sized 48px navigation targets.
- Removed the retired font-preset selector from settings and now expose only
  the installed-system-font picker while preserving legacy preset data during
  migration.
- Replaced the raw custom-theme hex field with PaperTodo's swatch/current
  color/choose/reset interaction and a cross-platform full-gamut HSV picker.
- Replaced line-spacing sliders with keyboard-editable todo/note fields,
  explicit default reset controls, and the original 0.8-5.0 bounds.
- Made collapsed paper windows adapt to the rendered title length and matched
  PaperTodo's title-only resting viewport plus partial hover reveal for deep
  capsules instead of forcing every capsule to a fixed 92px width.
- Routed Windows todo reminders to the independent paper that owns the item;
  the hidden coordinator no longer emits invisible reminders and sibling paper
  engines no longer duplicate the same reminder.
- Replaced in-paper Windows reminder snackbars with compact native bubbles
  positioned beside the owning paper or capsule; hovering pauses dismissal and
  clicking opens the due todo paper.
- Added native deep-capsule drop routing so capsules can be dragged between
  monitor edges and reordered inside a queue without overwriting the paper's
  normal saved position or size; master-capsule drags update queue start height.
- Added lightweight native master capsules that remain in slot 0 while queues
  are expanded or retracted, plus edge proxies for expanded papers; proxy
  clicks activate or collapse their paper according to the PaperTodo setting,
  and proxy drags preserve normal cross-edge queue reordering without creating
  additional Flutter engines.
- Made expanded-paper native proxy clicks activate their owning HWND
  synchronously during the Windows mouse event, before the action crosses the
  Dart platform channel, so foreground activation cannot be lost to timing.
- Kept real deep-capsule queue offsets relative to each monitor's work area so
  capsules remain correctly stacked on displays positioned above or below the
  primary monitor instead of being clamped together at the screen edge.
- Synchronized native master/proxy lifecycle after individual and bulk paper
  show or hide actions so hidden queues cannot leave clickable capsule windows
  behind.
- Stacked deep capsules on PaperTodo's 46px pill plus 4px gap geometry instead
  of reusing unrelated paper coordinates, keeping multiple papers in stable
  per-monitor, per-edge queues.
- Matched the original PaperTodo paper palette, transparent 8px shadow chrome,
  compact 31px title bar, original tint strengths, 24-28px paper controls,
  rounded shell, subtle todo rows, plus-only append area, and direct todo drag
  handles across light and dark color schemes.
- Restyled the settings window with the original paper shell, compact density,
  leading checkbox toggles, a desktop-sized viewport, and a dedicated close
  action while retaining validation and explicit save behavior.
- Matched PaperTodo note interaction by entering edit mode from the paper
  preview, returning to preview on focus loss, and removing the persistent
  edit/preview/split selector; notes now render inside a bound paper page with
  a compact canvas toolbar and status bar.
- Rebuilt independent paper capsules as the original 92x46 transparent chrome
  with an inset 30px pill, compact icon/title area, drag gesture, and dedicated
  right-side hide button while preserving script click behavior.
- Deep capsules now rest with only 54px exposed at the configured screen edge,
  reveal the full pill on pointer hover, and retract again on pointer exit on
  both left- and right-docked monitor queues.
- Paper and todo context menus now use the active paper palette, compact
  Windows 36px rows, rounded outlined surfaces, restrained shadows, and dense
  dividers while Android retains 48px touch targets.
- Kept independent Windows paper positions and sizes stable when titles, todo
  items, note text, or canvas content change during or after a drag/resize;
  child-window move events now update the coordinator's native geometry caches,
  tray reconciliation preserves live HWND bounds, and title/topmost/desktop-pin
  refreshes no longer call the full geometry-applying surface path. Expanding
  a capsule or opening a reminder now also restores the saved normal paper
  bounds instead of adopting the capsule HWND's minimum size and edge position.
- Extended Windows Release smoke to move and resize a real independent paper,
  type into its Flutter content field through native input, wait for the edit to
  persist, and then require both model and HWND geometry to remain unchanged.
- Normalized local paper IDs at the Windows platform boundary before sending
  surface, tray, bounds, visibility, and work-area channel payloads.
- Rejected unsafe paper IDs inside the Windows native surface registry so
  malformed registry refreshes cannot create stale native paper targets.
- Wired the Windows `forwardToPrimary` platform channel to the single-instance
  named pipe and shared the startup-command canonicalizer with the process
  entrypoint.
- Extended Windows release smoke evidence to verify that an unknown secondary
  startup command does not restore papers after a forwarded `--hide`.
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
- Rejected unsafe release evidence `-ResultJson` paths before smoke scripts,
  manual QA, or readiness audit write reusable release records.
- Rejected unsafe external QA/smoke JSON input paths before release packaging
  or readiness audit reads reusable evidence.
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
