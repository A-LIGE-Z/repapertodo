# Durable Local Sync Outbox Design

## Goal

Preserve local edits across crashes, Android process death, offline periods,
and WebDAV failures until the edits are represented by accepted operation logs
and incorporated into the final merged local state.

## Current failure mode

The UI currently keeps the pre-edit and latest states only in memory during a
five-second debounce. `data.json` may already contain the edit while no durable
record describes the operation that must be uploaded. A crash before the timer
fires loses that record. A later sync can download a newer remote snapshot and
replace the local edit before any operation log protects it.

## Approaches considered

1. Persist every generated `SyncOperation`. This gives exact retries but grows
   without bound while a user types offline and requires compaction rules.
2. Persist only the pre-edit snapshot. This is compact, but regenerated
   operation IDs and timestamps can change between retries unless additional
   sequence metadata is persisted.
3. Persist a deterministic operation batch descriptor. This stores the first
   pre-edit remote-safe snapshot, stable device ID, starting sequence, and one
   UTC timestamp. The final operations are regenerated from that baseline to
   the latest local state with stable IDs. This is the selected approach.

## Data model

`SyncSettings` gains an optional local-only `pendingOperationBatch` containing:

- `baseState`: a remote-safe canonical `AppState` JSON object with no WebDAV
  credentials, startup-at-login value, or nested pending batch;
- `deviceId`: normalized stable device identity;
- `startSequence`: the last locally applied sequence before this batch;
- `createdAtUtc`: one strict UTC timestamp used for every regeneration.

The batch is stored inside `data.json`, so the user state and the fact that the
state still needs operation-log protection are committed by the same atomic
`StateStore.save`. Remote snapshots explicitly omit the batch.

## Save path

Before a normal local save, the app loads the current stored state. When secure
WebDAV sync is configured and no batch exists, it asks `AppSyncService` to
create a batch descriptor from that stored state. Later saves keep the original
descriptor, so the outbox represents the complete offline change from the first
unprotected edit to the latest state. Disabling automatic sync does not discard
an existing batch.

## Sync path

1. Regenerate operations from `baseState` to the current state using the saved
   device ID, starting sequence, and timestamp.
2. Upload the operations. HTTP 409/412 idempotent acceptance keeps retries safe.
3. Run snapshot synchronization without clearing the batch.
4. If a remote snapshot is downloaded, reapply the pending operations to that
   snapshot before it can replace local data.
5. Merge remote operation logs.
6. Advance accepted device sequences, clear the batch, and save only after the
   final state includes the pending operations.

Failures at any earlier step preserve the batch for startup, manual, lifecycle,
or WorkManager retry.

## Boundaries

- The outbox is local metadata and never participates in settings diffs.
- Android and Windows use the same Dart implementation.
- Existing PaperTodo `data.json` files decode with no batch.
- Unknown batch fields are ignored through the normal forward-compatible JSON
  model rules.

## Verification

- Model round-trip, normalization, copy, and malformed-input tests.
- Remote snapshot encoding proves the batch and credentials are absent.
- Service tests prove stable regeneration, retry after upload failure, replay
  over a newer remote snapshot, and clearing only after successful merge.
- Bootstrap/background-sync tests prove a persisted batch is flushed after a
  simulated restart.
- Full Flutter tests, analysis, Windows build, Android APK build, and WebDAV
  static smoke remain required.
