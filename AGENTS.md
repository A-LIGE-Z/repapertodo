# RePaperTodo Project Rules

## Mission

RePaperTodo is a Flutter-first reimplementation of PaperTodo. The goal is to faithfully reproduce PaperTodo's product philosophy, features, and interaction details while preparing a shared Windows and Android codebase.

The project has no fixed budget ceiling. Engineering decisions should optimize for correctness, feature parity, long-term maintainability, data safety, and native desktop/mobile quality rather than short-term cost reduction.

## Product Boundary

RePaperTodo remains "a few sheets of paper on the desktop." It is not a task-management suite, knowledge base, calendar product, account system, analytics product, or cloud-first service.

The original PaperTodo feature set is the baseline:

- Independent paper windows.
- Todo papers.
- Note papers.
- Lightweight Markdown display/editing assistance.
- Capsule mode.
- Edge-docked/deep capsules.
- Master capsule/collapse-all behavior.
- Linked notes for todo items.
- Script capsules.
- External Markdown/file opening.
- Tray entry and command-line friendly startup actions.
- Themes, color schemes, typography, localization, tooltips, and settings.
- Startup at login.
- Data safety and recovery behavior.
- Global hotkeys.
- Fullscreen/topmost avoidance behavior.

Feature parity with the existing Windows exe is the first major milestone.

Runtime UI localization is intentionally limited to Chinese and English. New
user-facing strings must include those two languages only, and unsupported
system languages should fall back to English.

## Platform Priority

1. Windows exe first.
2. Android app second.
3. Cross-device sync after the local-first data model is stable.

Windows must receive special attention because PaperTodo's identity depends on native desktop window behavior: tray, transparent borderless windows, independent windows, topmost control, task-switcher visibility, fullscreen avoidance, edge docking, and script launching.

Android support must target Android 14 through Android 17, interpreted as Android API 34 through API 37 unless the Android ecosystem changes this mapping.

## Technology Direction

Flutter and Dart are the primary application language and UI layer.

Native platform code is allowed and expected when Flutter alone cannot provide the required behavior. Windows-specific functionality may use Win32 through FFI, platform channels, plugins, or a custom Windows runner.

The architecture should keep domain logic in Dart where possible so Windows and Android share the same data model, merge logic, sync logic, validation, and tests.

## Data And Compatibility

The original PaperTodo `data.json` is user data, not a cache. RePaperTodo must treat it as a compatibility contract.

Migration should preserve existing PaperTodo data wherever practical. The initial implementation should be able to read current PaperTodo data and migrate it into the RePaperTodo data model without destructive overwrite.

Long-term sync must not rely on blindly overwriting one `data.json` file. Prefer a local-first model based on snapshots plus operation logs:

- Encrypted snapshots for compact state.
- Per-device operation logs for mergeable changes.
- Stable IDs for papers, todo items, note elements, and devices.
- Tombstones for deletes.
- Conflict handling that preserves user content.

## Sync Direction

RePaperTodo must support WebDAV sync for Windows and Android.

Generic WebDAV must remain supported. Provider-specific presets may be added, but the app must not be locked to one service.

Recommended first preset: Jianguoyun WebDAV.

Sync design requirements:

- End-to-end encrypt sync payloads before upload.
- Use ETag or equivalent conditional writes when available.
- Batch small changes instead of uploading after every keystroke.
- Force sync on startup, exit, app backgrounding, and user request.
- Merge operation logs instead of last-writer-wins whole-file replacement.
- Keep local-first operation when the WebDAV endpoint is offline.
- Provide clear conflict recovery without silently discarding user data.

## Windows Requirements

Windows feature parity is the first implementation target.

Required Windows capabilities include:

- Multiple independent Flutter windows or equivalent native surfaces.
- Tray icon and tray menu.
- Startup commands: show, hide, toggle, new todo, new note, exit.
- Single-instance command forwarding.
- Global hotkeys.
- Borderless translucent paper windows.
- Window geometry persistence.
- Always-on-top and fullscreen avoidance.
- Task-switcher visibility control.
- Capsule and edge-docked capsule behavior.
- Startup at login.
- External file opening.
- Script capsule execution, with PowerShell behavior designed carefully.

## Android Requirements

Android must preserve the same data model and sync behavior as Windows.

The Android app may use a mobile-appropriate interaction model, but it should still preserve PaperTodo concepts: papers, todo items, notes, Markdown assistance, linked notes, settings, and sync.

Android 14-17 compatibility must be checked as part of release readiness.

## Implementation Discipline

Do not deliver a throwaway prototype as if it were the product.

Every major feature should have:

- A data model.
- A UI behavior definition.
- Platform constraints.
- Tests for pure Dart logic.
- Migration or compatibility notes when user data is affected.

Keep platform-specific code behind explicit boundaries. Do not mix Win32 behavior deeply into general UI/domain code.

## Release Discipline

Do not mark RePaperTodo as a replacement for PaperTodo until Windows feature parity is demonstrated.

Before public stable release:

- Verify migration from representative PaperTodo data files.
- Verify Windows multi-window behavior.
- Verify WebDAV sync with generic WebDAV and at least one domestic provider preset.
- Verify Android 14-17 compatibility.
- Verify conflict handling and offline behavior.
