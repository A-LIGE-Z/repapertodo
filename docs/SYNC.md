# Sync Design

RePaperTodo sync is local-first. The app must remain useful without network access.

## Transport

The required transport is WebDAV.

Generic WebDAV support is mandatory. Provider presets may be added for convenience, but they must not replace custom WebDAV configuration.

Initial recommended preset:

- Jianguoyun WebDAV
- Endpoint: `https://dav.jianguoyun.com/dav/`
- Suggested remote path: `/RePaperTodo/`

## Remote Layout

Proposed remote layout:

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

