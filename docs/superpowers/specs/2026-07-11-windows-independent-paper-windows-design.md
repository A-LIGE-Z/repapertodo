# Windows Independent Paper Windows Design

## Goal

Replace the current single-HWND paper-surface emulation with one real top-level
Windows HWND and one Flutter engine per visible paper while keeping the primary
engine authoritative for `AppState`, persistence, WebDAV, tray, startup
commands, global hotkeys, and process lifetime.

## Architecture

The primary window remains the coordinator. The custom Windows runner owns one
child `FlutterViewController` and top-level HWND per paper ID. It creates,
shows, hides, updates, and destroys those windows and translates child-window
messages into the existing `surfaceUpdates`, `paperOpenRequests`, and
`paperDeleteRequests` streams. Existing controller and widget save paths remain
the only writers of the canonical `data.json`. Keeping this support in the
runner avoids requiring Windows Developer Mode solely for plugin symlinks.

Each paper window receives a sanitized full-state snapshot for rendering but
may send only its own paper record or an explicit command back to the primary
engine. It never opens the canonical `StateStore`, performs WebDAV sync, owns a
tray icon, registers startup integration, or overwrites global state. This
prevents stale child engines from replacing concurrent edits made in other
paper windows.

Cross-engine communication uses two boundaries:

- The existing primary `repapertodo/window` channel accepts paper updates and
  commands brokered by the runner from every child engine.
- Each child owns a `repapertodo/paper_window` channel so the runner can push
  current state, native window flags, and close requests to the matching paper
  engine.

## Window Lifecycle

`restoreAll` reconciles the desired visible paper IDs with live child windows.
Missing visible papers create hidden windows, receive their initial snapshot
and native style, then show. Existing windows receive the latest state. Papers
that are no longer visible hide but stay reusable during the process lifetime;
deleted papers close and are removed from the registry.

Closing a paper HWND is intercepted in the child engine and reported as a hide
request. It does not terminate the application. Exiting from the coordinator
closes all children before native platform cleanup.

## Native Presentation

The runner configures each child as a transparent, borderless top-level window
with persisted paper bounds. It applies always-on-top, task-switcher policy,
and visibility independently. Desktop pinning and fullscreen avoidance remain
explicit follow-up native policies; they must be applied per HWND rather than
through the coordinator HWND.

Expanded papers render the existing Flutter `PaperPreview` surface without the
board app bar. Collapsed papers render as compact capsules. Deep-capsule queue
placement remains calculated from the shared model and is reflected in each
paper's native bounds.

## Data Flow

1. A local edit occurs in a child paper window.
2. Its in-memory store emits only that paper's normalized JSON to the
   coordinator channel.
3. The primary `WindowsPaperWindowHost` publishes a `surfaceUpdates` event.
4. `PaperBoardScreen` merges the paper, persists `data.json` with the durable
   sync outbox, rebuilds the tray, and pushes the canonical state back to the
   relevant child windows.
5. Bounds changes follow the same path and are debounced by the existing
   primary-engine surface-save logic.

## Failure Handling

If multi-window plugin initialization or child creation fails, the host keeps
the primary board usable and surfaces the failure through the existing platform
error path. It must not silently fall back to claiming independent-paper parity.
Malformed child arguments or messages are rejected without changing state.
Unknown or deleted paper IDs are ignored.

## Verification

Automated tests cover argument validation, per-paper routing, stale/deleted ID
rejection, independent show/hide/update calls, child-only paper persistence,
and project rules requiring real multi-window dependencies. A Windows runtime
smoke enumerates process HWNDs and requires one visible top-level window per
visible paper after startup commands. Manual QA still verifies transparency,
Alt+Tab policy, multi-monitor docking, desktop pinning, and fullscreen
avoidance under real foreground applications.
