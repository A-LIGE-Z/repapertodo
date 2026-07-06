# Sync Design

RePaperTodo sync is local-first. The app must remain useful without network access.

## Transport

The required transport is WebDAV.

Generic WebDAV support is mandatory. Provider presets may be added for convenience, but they must not replace custom WebDAV configuration.
Configured WebDAV endpoints must use `http` or `https` and must not include
embedded credentials, query components, or fragment components; unsupported
endpoint shapes are treated as incomplete settings.
Endpoint authority values with percent-encoded separators and endpoint paths
with dot-segments, raw or percent-encoded control characters, percent-encoded
path separators, blank path segments, leading or trailing whitespace inside
decoded segments, or malformed percent encoding are also treated as incomplete
settings so the configured WebDAV base folder is not silently rewritten by URI
normalization.
Backslashes are not accepted in configured endpoints for the same reason.
WebDAV Basic Auth usernames are trimmed before storage and transport, must
contain a non-whitespace character after trimming, and must not contain colons
or control characters, because the wire format separates the username and
password with the first colon. Passwords are preserved as entered, may contain
colons, and must contain a non-whitespace character and no control characters.
Sync encryption passphrases must be trimmed, non-empty, and free of control
characters so invisible input cannot create cross-device decryption failures.

Initial recommended preset:

- Jianguoyun WebDAV
- Endpoint: `https://dav.jianguoyun.com/dav/`
- Suggested remote path: `/RePaperTodo/`

Provider presets are maintained in a shared registry so UI labels, default
endpoints, and model defaults stay aligned. Generic WebDAV is an explicit
registry entry without provider defaults, and it must remain available even
when more provider presets are added. Preset IDs may accept common aliases for
import compatibility, but unknown provider IDs must fall back to the generic
WebDAV option.

## Current Remote Layout

Each device uploads a distinct snapshot path using `If-None-Match: *` and
updates `manifest.json` conditionally with WebDAV ETags. If a retry finds the
same snapshot bytes already present, the upload is treated as idempotently
accepted; if the existing snapshot differs, sync fails instead of overwriting
it. Provider `409` or `412` create-only conflicts may be accepted only after
the existing remote bytes are downloaded and confirmed to represent the same
snapshot. If the existing remote bytes cannot be read, the original create-only
conflict is preserved. Snapshot and operation-log bytes pass through a
dedicated WebDAV payload codec.
User-facing sync is considered configured only when the WebDAV connection
fields and a sync encryption passphrase are present. Normal uploads write
AES-GCM-256 encrypted payloads with a PBKDF2-HMAC-SHA256 derived key while
preserving WebDAV path, ETag, retry, and merge behavior. The lower-level codec
can still read legacy plain JSON payloads during normal pull, operation-log
merge, and recovery restore so existing remote data can be migrated gradually.
Encrypted payload KDF iteration counts are bounded during both encoding and
decoding so malformed remote envelopes cannot force unbounded key derivation
work before surfacing as corrupted sync data.
Configuration validation should preserve field-level issue details for the UI:
endpoint, username, password, remote folder, and encryption passphrase errors
must be recoverable without making users infer which setting blocked sync.
When the latest downloaded snapshot is still legacy plain JSON, the app reports
that state and, when the manifest has a strong ETag, immediately attempts a
conditional re-upload so the latest snapshot is rewritten with encrypted
payload bytes. If no strong ETag is available or the remote manifest changes,
the download remains accepted and a later successful upload will retry
encryption migration without bypassing manifest condition checks. Legacy
snapshot migration failures must be reported as incomplete migration while
preserving the downloaded state as the sync result; migration metadata save
failures must not advance local sequence progress in memory unless that metadata
is durably saved.
Snapshot retry idempotency compares decoded canonical snapshot content rather
than encrypted bytes, because encrypted payloads use fresh nonces on each
write.
Encrypted payload authentication failures are reported as unreadable remote
data with a passphrase-focused recovery message. Malformed, unsupported, or
corrupted encrypted envelopes should be reported separately from passphrase
failures. V1 encrypted envelope fields must be present and non-empty, and salt,
nonce, and MAC field sizes must be validated before decrypting so malformed
structural data is not mistaken for a wrong passphrase. Neither case may
replace local state or be shown as a generic network failure.
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
Remote snapshots redact local WebDAV configuration, credentials, and
startup-at-login state before upload. Downloading or restoring a snapshot
preserves the current device's local WebDAV settings and startup-at-login state
while merging non-secret sync metadata such as device sequence progress and
delete tombstones.

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
Snapshot recovery lists must sort by snapshot timestamp descending and then by
stable metadata such as path and ETag, so provider listing order cannot decide
which same-time snapshot appears first.
Sync device IDs are normalized into filename-safe lowercase tokens and must
remain 8 through 64 characters after cleanup; blank or shorter normalized IDs
are invalid for remote path generation or operation progress.
Snapshot record device IDs are normalized from file names for display and
entries whose device ID collapses to blank are ignored. Display normalization
uses the same filename-safe cleanup and maximum length cap as sync device IDs,
but does not apply the minimum device-ID length gate.
Selected snapshot files can also be downloaded and decoded for recovery.
Legacy snapshot names without the `-seq-<sequence>` suffix remain accepted for
recovery.
Snapshot paths referenced by `manifest.json` are validated with the same
snapshot-directory and filename rules before download. Manifest-referenced
snapshot file names must contain a device ID that remains non-empty after
display normalization. Manifest-referenced snapshot timestamps must parse
strictly instead of being normalized to a different date before download.
Manifest-referenced snapshot sequence suffixes, when present, must be positive
integers inside the supported remote sequence range.
Generated snapshot and operation-log paths must reject device IDs that normalize
to blank and sequence numbers outside the 12-digit remote sequence range instead
of producing remote names that later fail validation.
Next device sequences must stay inside the 12-digit remote sequence range
before collection creation or upload requests can reach WebDAV.
Remote paths with parent-directory segments, including percent-encoded forms,
are rejected before any HTTP download so WebDAV responses cannot escape the
RePaperTodo sync folders. Malformed percent-encoded paths are rejected at the
same boundary. Paths with raw or percent-encoded control characters are also
rejected before trimming path segments so invisible characters cannot be used to
change the accepted remote path. Raw blank path segments and non-empty path
segments that collapse to blank after trimming are rejected before direct snapshot
or operation-log downloads can reach the network. Direct remote path segments
that decode to path separators are rejected for the same reason.
Direct snapshot and operation-log downloads must reference direct child files
of their respective collections; extra nested folders under `snapshots/` or
`ops/` are rejected before network access.
Remote layout components such as the manifest file name and snapshot or
operation-log collection names must not normalize to blank paths before upload
or manifest reads can reach WebDAV. Those layout components must also remain
single path segments instead of introducing extra nested remote folders.
Direct state sync root paths must not normalize to blank before upload,
manifest reads, recovery listings, direct recovery downloads, or operation-log
uploads can reach WebDAV, so low-level sync construction cannot silently write
or inspect `manifest.json`, snapshots, or operation logs at the configured
endpoint root.
Downloaded migration results supplied by callers must not bypass the same root
path check before legacy operation-log rewrite requests can reach WebDAV.
Listing responses may use absolute `href` values and percent-encoded folder
segments; the sync layer must decode and normalize those values before applying
snapshot and operation-log path rules.
Absolute `href` values are accepted only when they stay on the configured
WebDAV endpoint origin and under the configured endpoint path; cross-origin or
base-path-escaping listing entries are ignored before any snapshot or
operation-log rule can accept their paths. Absolute listing entries with
embedded credentials, query components, or fragments are also ignored so the
sync layer never silently drops non-path URI components. Encoded absolute
`href` path segments must not decode to path separators or dot-segments, so
ambiguous provider listings cannot widen the configured endpoint boundary. The
same encoded-segment rule applies to relative and server-absolute listing
`href` values. Raw blank segments and non-empty encoded path segments must also
not collapse to blank segments after trimming. Listing `href` paths with raw or
percent-encoded control characters are ignored before they can become local
snapshot or operation-log records.
Listing `href` path segments must keep their decoded edge characters; entries
with raw or percent-encoded leading or trailing whitespace inside a non-empty
segment are ignored instead of being trimmed into a different snapshot or
operation-log path.
Network-path `href` values with an authority but no scheme, such as
`//host/path`, are treated as absolute references and ignored for the same
reason. Relative-looking `href` values that decode into network-path or
absolute URL references are ignored before root-folder matching. Plain relative
`href` values must already start at the sync root; server-absolute `href`
values must stay under the configured endpoint path before they can be reduced
to endpoint-relative sync paths.
The WebDAV client itself also refuses absolute or parent-traversing request
paths, paths with control characters, unsafe base URI authorities with encoded
separators, unsafe base URI paths including control characters, encoded path
separators, blank path segments, and request path segments that decode to path
separators.
Request path segments that collapse to blank after trimming are also refused.
Request paths and their decoded segments must not contain leading or trailing
whitespace, so low-level callers cannot silently address a different remote
file by adding raw or percent-encoded edge spaces.
It resolves all accepted paths beneath the configured endpoint.
Metadata reads prefer `HEAD`, but must fall back to `PROPFIND` with `Depth: 0`
when a provider does not implement `HEAD`. When a fallback `PROPFIND` response
contains multiple entries, metadata must be taken from the entry matching the
requested resource path instead of blindly trusting the first response entry.
Metadata `href` matches with query components or fragments are ignored instead
of silently dropping non-path URI parts. Absolute metadata `href` matches must
also stay on the same WebDAV origin and must not contain embedded credentials
before their path can be used for fallback metadata selection. Metadata `href`
matches with raw or percent-encoded control characters are ignored before their
paths can be compared with the requested resource. Metadata `href` matches
with raw or percent-encoded dot-segments are ignored instead of being normalized
to a different resource path.
Relative metadata `href` matches must be relative to the configured WebDAV
endpoint, not an arbitrary suffix of the requested resource path.
Missing-resource responses should accept both `404 Not Found` and `410 Gone`
for metadata probes, idempotent cleanup deletes, and missing snapshot or
operation-log collections; direct payload downloads must still fail when the
selected remote file is gone.
If `manifest.json` disappears with `404` or `410` between metadata probing and
download, sync treats the manifest as missing again and recreates it only with
`If-None-Match: *`.
WebDAV requests use a bounded client timeout so offline or stalled providers
surface as retryable sync failures instead of leaving manual or automatic sync
waiting on the platform network stack indefinitely. The timeout is stored in
WebDAV sync settings, defaults to 30 seconds, and is normalized to 1 through
300 seconds.
Automatic sync intervals are stored in WebDAV sync settings, default to 15
minutes, and are normalized to 1 through 1440 minutes.
WebDAV requests send explicit `Accept` headers. Generic requests accept any
content type, while `PROPFIND` prefers XML responses before falling back to any
content type for provider compatibility.
WebDAV requests also send a stable `User-Agent` so provider logs and throttling
diagnostics can distinguish RePaperTodo from generic client traffic.
WebDAV requests must not follow HTTP redirects automatically; redirect
responses should tell users to check the configured endpoint so credentials and
payload writes stay bound to the intended provider origin.
HTTP client and socket transport failures should be surfaced through the same
retryable WebDAV error path.
Provider `Retry-After` hints on throttling or temporary-unavailable responses
should be preserved in retryable WebDAV error messages so users can wait the
right amount of time before trying again.
Missing or weak ETags must not be used for manifest overwrite conditions:
manifest writes for an existing remote manifest require a strong ETag and are
treated as conflicts instead of unsafe unconditional overwrites when that ETag
is unavailable. Optional legacy operation-log migrations are skipped until a
strong ETag is available.
Collection creation treats common successful or already-existing `MKCOL`
responses as accepted, including provider-specific 409/412 responses only when
their body clearly reports that the collection already exists, including
localized already-exists wording, while preserving hard failures such as missing
parents, permission errors, and quota errors.
Configured WebDAV root folders use the same decoded path rules; unsafe or
malformed roots are treated as incomplete sync settings instead of falling back
to another remote folder. Root folders with raw or percent-encoded control
characters, raw blank path segments, or non-empty segments that collapse to blank
after trimming, are treated as incomplete settings for the same reason.
Explicit empty root folder values remain incomplete after repeated normalization
so an invalid root cannot later fall back to the default remote folder.
Each push also writes one operation record in `ops/` that points at the
uploaded snapshot and advances that device's manifest sequence.
The sync core can enumerate and download these operation logs as merge inputs.
It applies operation-level merges for settings, papers, note content, and todo
items before saving the merged local state.
Operation logs are created with `If-None-Match: *` and treated as immutable
remote records so a repeated upload cannot overwrite an existing device
sequence. If a retry finds the same operation already present, the upload is
treated as idempotently accepted; if the existing operation differs, sync fails
instead of advancing local progress. Provider `409` or `412` create-only
conflicts may be accepted only after the existing remote log is downloaded and
matches the pending operation. If the existing remote log is unreadable, the
original create-only conflict is preserved.
Operation upload `uploadedCount` reports only newly created remote log files.
Idempotently accepted existing logs still advance returned device sequence
progress but do not count as newly uploaded bytes.
If local persistence of accepted operation upload progress fails, the upload
must surface as failed so pending local edits can retry instead of treating
unsaved sequence progress as accepted.
Operation upload queues must skip operations whose device ID normalizes to blank
or whose sequence falls outside the 12-digit remote sequence range before
collection creation or upload requests can reach WebDAV.
Manifest wire keys are decoded case-insensitively for legacy or hand-edited
WebDAV metadata compatibility, while modern camelCase keys win when duplicate
legacy keys are present.
Manifest `updatedAtUtc` wire timestamps must parse strictly with an explicit
time zone; overflow dates or times must be rejected instead of normalized to a
different instant, invalid time-zone offsets are rejected, and leading or
trailing whitespace is not accepted.
Manifest schema and sequence numbers accept positive integer JSON strings as
well as JSON numbers, while non-integer, non-positive, or leading/trailing
whitespace string values remain invalid.
Manifest device sequences must reject values outside the 12-digit remote
sequence range before they can advance local operation progress.
When downloading an operation log, the `<deviceId>-<sequence>` file name is
treated as the authoritative operation identity so stale or hand-edited payload
metadata cannot advance the wrong device sequence.
Each decoded operation log payload must contain exactly one non-empty JSON
operation. Known operation wire keys are decoded case-insensitively for legacy
compatibility, while modern camelCase keys win when duplicate legacy keys are
present. Operation sequence numbers accept positive integer JSON strings inside
the supported remote sequence range for hand-edited legacy logs, while
leading/trailing whitespace string values remain invalid; the file name remains
authoritative after decode.
Operation `createdAtUtc` wire timestamps must parse strictly with an explicit
time zone; overflow dates or times must be rejected instead of normalized to a
different instant, invalid time-zone offsets are rejected, and leading or
trailing whitespace is not accepted.
When encrypted sync is enabled, downloaded legacy plain operation logs are
reported in the merge result. If the log entry includes an ETag, the sync layer
attempts a conditional same-path rewrite so the operation log payload becomes
encrypted without changing the operation identity, sequence, or manifest
progress. Migration records whose device ID or sequence does not match their
operation-log path, or whose downloaded result path does not match the migration
record path, must be skipped before rewrite requests can reach WebDAV. Migration
downloads that are not legacy plain JSON or do not contain exactly one operation
must be skipped at the same boundary. Missing ETags or conditional conflicts
leave the merge accepted and surface a retryable migration status instead of
blocking user data. Legacy operation-log migration failures must be counted as
not migrated while still applying the downloaded operations.
During upload and merge, operation logs are selected and applied per device
only while their sequence numbers are contiguous from the locally recorded
progress. If sequence `2` is missing, sequence `3` is left untouched until the
gap is filled so later syncs can still apply the missing operation in order.
Merge candidate selection must skip blank-normalized device IDs, already
covered sequences, and sequences outside the remote range before downloading
operation log payloads. Explicit or locally stored previous device sequence
maps must be normalized before merge candidate selection so invalid progress
entries cannot hide valid remote sequence `1` operation logs.
Duplicate operation-log records for the same normalized device and sequence must
be ordered by stable metadata such as path and ETag before selecting downloads,
so provider listing order cannot decide which duplicate is applied.
Local operation diff generation and merge application must keep operation
sequences inside the same 12-digit remote sequence range used by WebDAV paths.
Merge application must apply matching duplicate operations for the same device
sequence at most once, and conflicting duplicate operations must block that
device sequence instead of applying an arbitrary candidate.
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
Downloaded, decoded, or restored tombstone timestamps must parse strictly with
an explicit time zone; overflow dates or times are discarded instead of
normalized to a different instant, and invalid time-zone offsets or
leading/trailing whitespace are discarded.

Settings operations are intentionally limited to app preferences. They do not
replace local sync settings, WebDAV credentials, operation device sequences, or
delete tombstones, and they do not replace local startup-at-login state. Sync
progress comes from manifests, operation logs, and local upload results instead.

Local device sequence progress must never move backward. Operation upload
progress comes from returned device sequence metadata and explicitly accepted
operation sequences, not from `uploadedCount`. The local state merges those
maps with the previous sequence map by taking the highest valid sequence per
device. Upload result sequence maps must be normalized before saving so blank
device IDs, short-invalid device IDs, and sequence values outside the remote
range cannot pollute local sync progress.
Persisted or restored operation device sequence maps must accept only integer
JSON numbers or integer strings; fractional numbers and leading/trailing
whitespace string values must be discarded instead of rounded or trimmed into
valid sync progress.
Downloaded or restored snapshot and manifest sequence progress is merged the
same way with existing local progress, so sparse, stale, or malformed remote
sequence maps cannot drop known device progress or save invalid device IDs
locally.
The UI refreshes its in-memory state whenever upload results change local sync
metadata, even when no new remote bytes were uploaded.
Remote operation merges must not return applied state as accepted if saving the
merged state fails; callers should keep the previous local state and retry
later instead of showing unsaved remote operation progress.
Local delete operation uploads must surface tombstone save failures instead of
reporting success, so delete tombstones and sequence progress can be retried or
reconciled from durable state.
Recovery snapshot restores must also surface local save failures instead of
reporting success, preserving the previous local state on disk.

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
- Keep WebDAV settings, credentials, sequence progress, tombstones, and local
  startup-at-login state out of remote settings operations.
- Keep WebDAV settings, credentials, and local startup-at-login state out of
  uploaded remote snapshots.
- Sync on startup, exit, foreground/background transitions, manual request, and debounced local edits.
  Foreground/background transitions must flush any pending local-edit operation upload before running the snapshot sync, instead of waiting for the debounce timer.
- Opening settings must pause pending debounced local-edit uploads; canceling settings or saving settings without changing sync configuration restores the pending upload, even when platform setting application reports errors, while saving sync setting changes clears stale pending uploads so edits are not sent under a new sync configuration. Settings save failures must surface as readable UI errors and must not leave later local edits blocked from debounced upload.
- After any sync, recovery restore, or local-operation upload replaces local state, reapply the resulting state to the platform layer so Windows surfaces, tray state, hotkeys, and window policies match the accepted data.
- Offer retry actions for transient manual sync, recovery snapshot listing, and recovery restore failures.
