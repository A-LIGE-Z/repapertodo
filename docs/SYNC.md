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
uploading a distinct snapshot path and updating `manifest.json` conditionally
with WebDAV ETags.

```text
/RePaperTodo/
  manifest.json
  snapshots/
    snapshot-<timestamp>-<deviceId>.json
```

If a manifest conditional write fails, the uploaded local snapshot remains in
`snapshots/` so a later conflict recovery flow can inspect or restore it.
The sync core can enumerate this directory and expose snapshot metadata such as
device ID, timestamp, ETag, size, and last-modified time.
Selected snapshot files can also be downloaded and decoded for recovery.

## Target Remote Layout

Planned encrypted operation-log layout:

```text
/RePaperTodo/
  manifest.json.enc
  snapshots/
    snapshot-<timestamp>-<deviceId>.json.enc
  ops/
    <deviceId>-<sequence>.jsonl.enc
```

## Rules

- Encrypt before upload.
- Merge operation logs instead of replacing the whole state file.
- Use ETag/If-Match when supported.
- Preserve conflicts as recoverable user content.
- Keep tombstones long enough to prevent deleted content from reappearing from stale devices.
- Sync on startup, exit, foreground/background transitions, manual request, and debounced local edits.
