# RePaperTodo Roadmap

## Phase 0: Repository And Architecture

- Define project rules.
- Create Flutter-first repository layout.
- Define package boundaries.
- Prepare original PaperTodo data compatibility notes.

## Phase 1: Data Core

- Model PaperTodo-compatible papers, todo items, note content, note canvas elements, settings, and capsule state.
- Read current PaperTodo `data.json`.
- Write a non-destructive migrated RePaperTodo state.
- Add pure Dart tests for normalization, migration, and compatibility.

## Phase 2: Windows MVP

- Create Windows Flutter app shell.
- Implement multiple independent paper windows or an equivalent native window model.
- Implement todo paper editing.
- Implement note paper editing.
- Implement local save and restore.
- Implement tray entry and startup commands.

## Phase 3: Windows Feature Parity

- Capsule mode.
- Edge-docked/deep capsules.
- Master capsule.
- Linked notes.
- Markdown modes.
- External open.
- Script capsules.
- Global hotkeys.
- Fullscreen/topmost avoidance.
- Themes, settings, localization, startup at login.

## Phase 4: Sync Core

- Add device IDs.
- Add snapshots plus operation logs.
- Add merge logic.
- Add encrypted sync payloads.
- Add conflict preservation.

## Phase 5: WebDAV

- Implement generic WebDAV.
- Add Jianguoyun WebDAV preset.
- Support Windows and Android.
- Verify ETag/conditional writes and offline behavior.

## Phase 6: Android

- Build Android UI based on the same data and sync core.
- Target Android 14-17/API 34-37.
- Verify background/foreground sync behavior.
- Verify WebDAV sync and conflict handling.

## Phase 7: Release Readiness

- Migration tests with representative PaperTodo data.
- Windows multi-window manual QA.
- WebDAV compatibility QA.
- Android 14-17 QA.
- Packaging and release automation.

