# Durable Sync Outbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist a deterministic local operation batch in `data.json` and keep it until WebDAV upload, snapshot replay, and operation-log merge succeed.

**Architecture:** `SyncSettings` owns a local-only batch descriptor. `AppSyncService` creates and regenerates the batch, while the UI save path persists it atomically with user state. Remote snapshot encoding strips it. The combined sync path uploads and replays it before clearing.

**Tech Stack:** Dart 3.12, Flutter 3.44, JSON state codec, WebDAV operation logs, `flutter_test`.

---

### Task 1: Pending batch model

**Files:**
- Modify: `lib/src/core/model/sync_settings.dart`
- Test: `test/sync_settings_test.dart`

- [x] Add failing tests that round-trip a batch, deep-copy its base JSON, reject blank device IDs and invalid sequences/timestamps, and preserve no batch for legacy JSON.
- [x] Run `puro flutter test test/sync_settings_test.dart` and confirm the new tests fail because `pendingOperationBatch` is undefined.
- [x] Add `PendingSyncOperationBatch` with `fromJson`, `toJson`, `copy`, and normalization; add the optional field to `SyncSettings` constructor, known keys, copy, normalize, and JSON.
- [x] Rerun the focused test and confirm it passes.

### Task 2: Keep the batch local

**Files:**
- Modify: `lib/src/core/state/app_state_codec.dart`
- Test: `test/app_state_codec_test.dart`

- [x] Add a regression test that local encoding contains `pendingOperationBatch` while `encodeRemoteSnapshot` omits it and still strips WebDAV credentials/startup state.
- [x] Run the focused test and confirm the existing remote snapshot boundary already excludes the batch.
- [x] Verify `_remoteSnapshotSyncJson` constructs sync metadata without the pending batch; no production change was needed.
- [x] Rerun the focused test and confirm it passes.

### Task 3: Create and regenerate deterministic batches

**Files:**
- Modify: `lib/src/sync/app_sync_service.dart`
- Test: `test/app_sync_service_test.dart`

- [x] Add failing tests for creating a batch from the first before-state, keeping an existing batch across later edits, and regenerating identical operation IDs/timestamps after serialization.
- [x] Run the focused tests and confirm the new service API is missing.
- [x] Add `preparePendingLocalOperationBatch` and deterministic regeneration using `SyncDeviceIdStore`, `AppStateCodec.encodeRemoteSnapshot`, and `SyncOperationDiffBuilder`.
- [x] Rerun the focused and full service tests; confirm disk-batch priority, corruption preservation, and sequence exhaustion behavior pass.

### Task 4: Persist the batch with each local save

**Files:**
- Modify: `lib/src/app.dart`
- Test: `test/widget_test.dart`

- [x] Add failing widget tests that persist content and a pending batch before the five-second debounce, preserve disk authority, and tolerate preparation failures.
- [x] Run the focused tests and confirm the batch is absent or stale runtime metadata is overwritten before the fix.
- [x] In `_saveState`, prepare/preserve the batch before the single `StateStore.save`; keep disk batch authority (including null) and preserve all settings runtime metadata.
- [x] Rerun focused and full widget tests; 235/235 pass without changing the existing upload debounce.

### Task 5: Upload, replay, and clear safely

**Files:**
- Modify: `lib/src/sync/app_sync_service.dart`
- Test: `test/app_sync_service_test.dart`

- [x] Add failing tests that upload a persisted batch after restart, keep it after an upload error, replay it over a downloaded newer snapshot, retry with identical operation IDs after partial acceptance, and clear it only after the final merge succeeds.
- [x] Run the focused tests and confirm current `syncAndMergeNow` can lose or ignore the batch.
- [x] Upload regenerated operations before snapshot sync, preserve the descriptor through downloaded-state replacement, apply the pending operations to downloaded state, merge remote logs, advance accepted sequences, then clear and save.
- [x] Rerun the focused tests and confirm they pass, including manual and five-second debounced UI sync without duplicate legacy uploads.

### Task 6: Startup and Android background integration

**Files:**
- Modify: `lib/src/bootstrap/app_bootstrap.dart`
- Modify: `lib/src/sync/android_background_sync.dart`
- Test: `test/app_bootstrap_test.dart`
- Test: `test/android_background_sync_test.dart`

- [x] Add restart/background tests with a persisted batch and a fake WebDAV service.
- [x] Run the focused tests and verify the persisted batch reaches the combined sync path.
- [x] Confirm both startup and WorkManager paths already use the batch-aware `syncAndMergeNow` state returned by the service; no production routing change was needed.
- [x] Rerun the focused tests and confirm startup and Android background workers upload and clear the batch.

### Task 7: Documentation and full verification

**Files:**
- Modify: `docs/SYNC.md`
- Modify: `docs/ROADMAP.md`
- Modify: `README.md`
- Modify: `test/project_rules_test.dart`

- [x] Document the durable batch, retry semantics, remote exclusion, and crash recovery behavior.
- [x] Run `git diff --check`.
- [x] Run `flutter analyze`.
- [x] Run `flutter test --reporter compact` (1053/1053 passed).
- [x] Run `flutter build windows --release`.
- [x] Run `flutter build apk --release`.
- [x] Run Windows, Android, and WebDAV smoke scripts.
