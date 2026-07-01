# Sync Design

RePaperTodo sync is local-first. The app must remain useful without network access.

## Transport

The required transport is WebDAV.

Generic WebDAV support is mandatory. Provider presets may be added for convenience, but they must not replace custom WebDAV configuration.

Initial recommended preset:

- Jianguoyun WebDAV
- Endpoint: `https://dav.jianguoyun.com/dav/`
- Suggested remote path: `/RePaperTodo/`

## Current Remote Layout

The current implementation stores plain JSON snapshots first, with each device
uploading a distinct snapshot path using `If-None-Match: *` and updating
`manifest.json` conditionally with WebDAV ETags. If a retry finds the same
snapshot bytes already present, the upload is treated as idempotently accepted;
if the existing snapshot differs, sync fails instead of overwriting it.

```text
/RePaperTodo/
  manifest.json
  snapshots/
    snapshot-<timestamp>-<deviceId>-seq-<sequence>.json
  ops/
    <deviceId>-<sequence>.jsonl
```

If a manifest conditional write fails, the uploaded local snapshot remains in
`snapshots/` so a later conflict recovery flow can inspect or restore it. The
matching state-snapshot operation log is removed best-effort so the failed push
does not advance that device's operation sequence.
The sync core can enumerate this directory and expose snapshot metadata such as
device ID, timestamp, ETag, size, and last-modified time.
Selected snapshot files can also be downloaded and decoded for recovery.
Legacy snapshot names without the `-seq-<sequence>` suffix remain accepted for
recovery.
Snapshot paths referenced by `manifest.json` are validated with the same
snapshot-directory and filename rules before download.
Remote paths with parent-directory segments are rejected before any HTTP
download so WebDAV responses cannot escape the RePaperTodo sync folders.
Each push also writes a one-line plain JSON operation record in `ops/` that
points at the uploaded snapshot and advances that device's manifest sequence.
The sync core can enumerate and download these operation logs as merge inputs.
It applies operation-level merges for settings, papers, note content, and todo
items before saving the merged local state.
Operation logs are created with `If-None-Match: *` and treated as immutable
remote records so a repeated upload cannot overwrite an existing device
sequence. If a retry finds the same operation already present, the upload is
treated as idempotently accepted; if the existing operation differs, sync fails
instead of advancing local progress.
When downloading an operation log, the `<deviceId>-<sequence>` file name is
treated as the authoritative operation identity so stale or hand-edited payload
metadata cannot advance the wrong device sequence.
Each operation log file must contain exactly one non-empty JSON operation.
During upload and merge, operation logs are selected and applied per device
only while their sequence numbers are contiguous from the locally recorded
progress. If sequence `2` is missing, sequence `3` is left untouched until the
gap is filled so later syncs can still apply the missing operation in order.

Delete operations also write local tombstones into sync state. These tombstones
prevent stale paper or todo-item upserts from older devices from recreating
content the user already deleted. Upserts created after the tombstone time are
treated as intentional restores and clear the matching tombstone. Undoing a
local delete clears the matching tombstone before the next save.

## Target Remote Layout

Planned encrypted operation-log layout:

```text
/RePaperTodo/
  manifest.json.enc
  snapshots/
    snapshot-<timestamp>-<deviceId>-seq-<sequence>.json.enc
  ops/
    <deviceId>-<sequence>.jsonl.enc
```

## Rules

- Encrypt before upload.
- Merge operation logs instead of replacing the whole state file.
- Apply operation logs in per-device sequence order without skipping gaps.
- Upload operation logs in per-device sequence order without creating gaps.
- Create snapshot files only when the target path does not already exist.
- Create operation log files only when the target path does not already exist.
- Use ETag/If-Match when supported.
- Preserve conflicts as recoverable user content.
- Keep tombstones long enough to prevent deleted content from reappearing from stale devices.
- Sync on startup, exit, foreground/background transitions, manual request, and debounced local edits.
