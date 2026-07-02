# Sync Design

RePaperTodo sync is local-first. The app must remain useful without network access.

## Transport

The required transport is WebDAV.

Generic WebDAV support is mandatory. Provider presets may be added for convenience, but they must not replace custom WebDAV configuration.
Configured WebDAV endpoints must use `http` or `https` and must not include
embedded credentials, query components, or fragment components; unsupported
endpoint shapes are treated as incomplete settings.
Endpoint paths with dot-segments, raw or percent-encoded control characters, or
malformed percent encoding are also treated as incomplete settings so the
configured WebDAV base folder is not silently rewritten by URI normalization.
Backslashes are not accepted in configured endpoints for the same reason.
WebDAV Basic Auth usernames must be non-empty and must not contain colons or
control characters, because the wire format separates the username and password
with the first colon. Passwords are preserved as entered, may contain colons,
and must contain a non-whitespace character and no control characters.

Initial recommended preset:

- Jianguoyun WebDAV
- Endpoint: `https://dav.jianguoyun.com/dav/`
- Suggested remote path: `/RePaperTodo/`

Provider presets are maintained in a shared registry so UI labels, default
endpoints, and model defaults stay aligned. The custom generic WebDAV option
must remain available even when more provider presets are added. Preset IDs may
accept common aliases for import compatibility, but unknown provider IDs must
fall back to the generic WebDAV option.

## Current Remote Layout

Each device uploads a distinct snapshot path using `If-None-Match: *` and
updates `manifest.json` conditionally with WebDAV ETags. If a retry finds the
same snapshot bytes already present, the upload is treated as idempotently
accepted; if the existing snapshot differs, sync fails instead of overwriting
it. Snapshot and operation-log bytes pass through a dedicated WebDAV payload
codec.
User-facing sync is considered configured only when the WebDAV connection
fields and a sync encryption passphrase are present. Normal uploads write
AES-GCM-256 encrypted payloads with a PBKDF2-HMAC-SHA256 derived key while
preserving WebDAV path, ETag, retry, and merge behavior. The lower-level codec
can still read legacy plain JSON payloads during normal pull, operation-log
merge, and recovery restore so existing remote data can be migrated gradually.
Configuration validation should preserve field-level issue details for the UI:
endpoint, username, password, remote folder, and encryption passphrase errors
must be recoverable without making users infer which setting blocked sync.
When the latest downloaded snapshot is still legacy plain JSON, the app reports
that state and, when the manifest has an ETag, immediately attempts a
conditional re-upload so the latest snapshot is rewritten with encrypted
payload bytes. If no ETag is available or the remote manifest changes, the
download remains accepted and a later successful upload will retry encryption
migration without bypassing manifest condition checks.
Snapshot retry idempotency compares decoded canonical snapshot content rather
than encrypted bytes, because encrypted payloads use fresh nonces on each
write.
Encrypted payload decode failures are reported as unreadable remote data with
a passphrase-focused recovery message. They must not replace local state or be
shown as generic network failures.
User-visible sync-disabled, unreadable-payload, and missing-configuration
messages should offer a direct settings action so users can enable sync or fix
the WebDAV endpoint, credentials, or sync encryption passphrase without
searching through the app.
Transient manual sync failures should offer a retry action from the failure
message so users can recover from temporary WebDAV or network errors without
reopening the command surface.
Startup auto-sync is opportunistic: WebDAV or network failures during startup
must preserve local state and must not prevent the app from opening.
Recovery snapshot browsing should use the same configuration gate; incomplete
WebDAV settings must be reported as recoverable configuration problems instead
of showing an empty snapshot list.
Transient WebDAV listing failures in the recovery snapshot browser should keep
the dialog open and expose a retry action instead of forcing users to close and
reopen the flow.
Remote snapshots redact local WebDAV configuration and credentials before
upload. Downloading or restoring a snapshot preserves the current device's
local WebDAV settings while merging non-secret sync metadata such as device
sequence progress and delete tombstones.

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
Remote paths with parent-directory segments, including percent-encoded forms,
are rejected before any HTTP download so WebDAV responses cannot escape the
RePaperTodo sync folders. Malformed percent-encoded paths are rejected at the
same boundary. Paths with raw or percent-encoded control characters are also
rejected before trimming path segments so invisible characters cannot be used to
change the accepted remote path.
Listing responses may use absolute `href` values and percent-encoded folder
segments; the sync layer must decode and normalize those values before applying
snapshot and operation-log path rules.
The WebDAV client itself also refuses absolute or parent-traversing request
paths, paths with control characters, unsafe base URI paths including control
characters, and resolves all accepted paths beneath the configured endpoint.
Metadata reads prefer `HEAD`, but must fall back to `PROPFIND` with `Depth: 0`
when a provider does not implement `HEAD`.
WebDAV requests use a bounded client timeout so offline or stalled providers
surface as retryable sync failures instead of leaving manual or automatic sync
waiting on the platform network stack indefinitely. The timeout is stored in
WebDAV sync settings, defaults to 30 seconds, and is normalized to 1 through
300 seconds.
HTTP client and socket transport failures should be surfaced through the same
retryable WebDAV error path.
Collection creation treats common successful or already-existing `MKCOL`
statuses as accepted while preserving hard failures such as quota errors.
Configured WebDAV root folders use the same decoded path rules; unsafe or
malformed roots are treated as incomplete sync settings instead of falling back
to another remote folder. Root folders with raw or percent-encoded control
characters are treated as incomplete settings for the same reason. Explicit
empty root folder values remain incomplete after repeated normalization so an
invalid root cannot later fall back to the default remote folder.
Each push also writes one operation record in `ops/` that points at the
uploaded snapshot and advances that device's manifest sequence.
The sync core can enumerate and download these operation logs as merge inputs.
It applies operation-level merges for settings, papers, note content, and todo
items before saving the merged local state.
Operation logs are created with `If-None-Match: *` and treated as immutable
remote records so a repeated upload cannot overwrite an existing device
sequence. If a retry finds the same operation already present, the upload is
treated as idempotently accepted; if the existing operation differs, sync fails
instead of advancing local progress.
Operation upload `uploadedCount` reports only newly created remote log files.
Idempotently accepted existing logs still advance returned device sequence
progress but do not count as newly uploaded bytes.
Manifest wire keys are decoded case-insensitively for legacy or hand-edited
WebDAV metadata compatibility, while modern camelCase keys win when duplicate
legacy keys are present.
Manifest schema and sequence numbers accept positive integer JSON strings as
well as JSON numbers, while non-integer or non-positive values remain invalid.
When downloading an operation log, the `<deviceId>-<sequence>` file name is
treated as the authoritative operation identity so stale or hand-edited payload
metadata cannot advance the wrong device sequence.
Each decoded operation log payload must contain exactly one non-empty JSON
operation. Known operation wire keys are decoded case-insensitively for legacy
compatibility, while modern camelCase keys win when duplicate legacy keys are
present. Operation sequence numbers accept positive integer JSON strings for
hand-edited legacy logs, but the file name remains authoritative after decode.
When encrypted sync is enabled, downloaded legacy plain operation logs are
reported in the merge result. If the log entry includes an ETag, the sync layer
attempts a conditional same-path rewrite so the operation log payload becomes
encrypted without changing the operation identity, sequence, or manifest
progress. Missing ETags or conditional conflicts leave the merge accepted and
surface a retryable migration status instead of blocking user data.
During upload and merge, operation logs are selected and applied per device
only while their sequence numbers are contiguous from the locally recorded
progress. If sequence `2` is missing, sequence `3` is left untouched until the
gap is filled so later syncs can still apply the missing operation in order.
Matching duplicate upload candidates for the same device sequence are
deduplicated, while conflicting duplicates block that device so an arbitrary
operation is never chosen.
When multiple devices have ready operations at the same time, the merge core
keeps each device's sequence order but applies the ready operation with the
earliest `createdAtUtc` first. This prevents device ID sorting from deciding
delete/restore conflicts.

Delete operations also write local tombstones into sync state. These tombstones
prevent stale paper or todo-item upserts from older devices from recreating
content the user already deleted. Upserts created after the tombstone time are
treated as intentional restores and clear the matching tombstone. Undoing a
local delete clears the matching tombstone before the next save.
Tombstone timestamps only move forward. Paper tombstones remove todo-item
tombstones they cover, while preserving item tombstones that are newer than the
paper delete. Runtime marking and JSON normalization use the same rule.

Settings operations are intentionally limited to app preferences. They do not
replace local sync settings, WebDAV credentials, operation device sequences, or
delete tombstones. Sync progress comes from manifests, operation logs, and local
upload results instead.

Local device sequence progress must never move backward. Operation upload
progress comes from returned device sequence metadata and explicitly accepted
operation sequences, not from `uploadedCount`. The local state merges those
maps with the previous sequence map by taking the highest valid sequence per
device.
Downloaded manifest sequence progress is merged the same way with existing
local and snapshot sequence progress, so a sparse or stale manifest cannot drop
known device progress.
The UI refreshes its in-memory state whenever upload results change local sync
metadata, even when no new remote bytes were uploaded.

## Payload-Encrypted Remote Layout

Encryption keeps the path layout compatible with existing WebDAV folders.
Snapshot and operation-log file contents are encrypted for user-facing sync;
`manifest.json` remains plain sync metadata.

```text
/RePaperTodo/
  manifest.json
  snapshots/
    snapshot-<timestamp>-<deviceId>-seq-<sequence>.json
  ops/
    <deviceId>-<sequence>.jsonl
```

## Rules

- Require a sync encryption passphrase before user-facing WebDAV sync runs.
- Encrypt snapshot and operation-log payloads before normal upload.
- Treat encrypted payload decode failures as recoverable passphrase/configuration problems.
- Rewrite legacy plain operation logs with encrypted bytes only through conditional ETag-guarded PUTs.
- Merge operation logs instead of replacing the whole state file.
- Apply operation logs in per-device sequence order without skipping gaps.
- Apply ready cross-device operations by operation creation time, not by device ID.
- Upload operation logs in per-device sequence order without creating gaps.
- Deduplicate matching operation upload candidates and block conflicting duplicate device sequences.
- Count only newly created operation log files as uploaded while still advancing idempotently accepted sequences.
- Never regress local device sequence progress after upload or merge.
- Create snapshot files only when the target path does not already exist.
- Create operation log files only when the target path does not already exist.
- Use ETag/If-Match when supported.
- Preserve conflicts as recoverable user content.
- Surface conflict recovery from the sync result so preserved snapshots are easy to inspect.
- Keep tombstones long enough to prevent deleted content from reappearing from stale devices.
- Keep WebDAV settings, credentials, sequence progress, and tombstones out of remote settings operations.
- Keep WebDAV settings and credentials out of uploaded remote snapshots.
- Sync on startup, exit, foreground/background transitions, manual request, and debounced local edits.
- After any sync, recovery restore, or local-operation upload replaces local state, reapply the resulting state to the platform layer so Windows surfaces, tray state, hotkeys, and window policies match the accepted data.
- Offer retry actions for transient manual sync, recovery snapshot listing, and recovery restore failures.
