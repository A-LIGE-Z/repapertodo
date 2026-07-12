# Windows Independent Paper Windows Implementation Plan

## Task 1: Multi-window runtime boundary

- [x] Add a runner-owned child Flutter engine and HWND registry.
- [x] Register generated plugins for each child Flutter engine.
- [x] Parse and validate paper-window engine arguments before normal bootstrap.
- [x] Add tests for primary and paper-window argument routing.

## Task 2: Child paper application

- [x] Add a paper-window-only Flutter shell that renders one `PaperPreview`.
- [x] Add a memory store that reports only the current paper to the coordinator.
- [x] Apply pushed canonical state without writing `data.json` from the child.
- [x] Configure transparent frameless bounds and independent close handling.

## Task 3: Primary coordinator

- [x] Reconcile one child engine/HWND per visible paper in `restoreAll`.
- [x] Route show, hide, update, bounds capture, and delete independently.
- [x] Translate child paper changes and close requests into existing host streams.
- [x] Preserve the legacy native method channel for tray/startup/system services and compatibility routing.

## Task 4: Capsule and native policies

- [x] Render collapsed paper windows as 92x46 capsules without overwriting expanded model bounds.
- [x] Apply per-HWND always-on-top and task-switcher visibility.
- [x] Implement per-HWND desktop pinning and fullscreen topmost avoidance.
- [ ] Verify deep-capsule queues across multiple monitors.

## Task 5: Runtime verification

- [x] Add an `EnumWindows` smoke check that counts RePaperTodo top-level HWNDs.
- [x] Require independent paper windows in Windows manual QA and release evidence.
- [x] Run analyze, full tests, Windows release build, and Windows smoke.
