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
import compatibility, including Jianguoyun, Jian Guo Yun, Nutstore, and
`坚果云` spellings with spaces, underscores, or hyphens, but unknown provider
IDs must fall back to the generic WebDAV option.

Preset default root paths must normalize to safe relative WebDAV folders before
settings apply them. Built-in provider defaults must reject parent-directory
segments, control characters, and blank middle path segments instead of relying
on later upload-time validation.
When imported or restored WebDAV settings name a known provider preset but omit
the root path field, the model should apply that preset's default remote path;
explicit custom or blank root path values must remain user-controlled and be
validated normally.
New programmatic WebDAV settings for a known provider may also fill a blank
root path from the preset default, but unsafe explicit root paths must remain
invalid instead of being silently replaced by the provider default.

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
Payload format inspection must report non-JSON or non-UTF-8 plain bytes as
unknown instead of treating arbitrary remote bytes as legacy plain JSON.
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
structural data is not mistaken for a wrong passphrase. Envelope byte fields
must use unpadded base64url text; padded, non-URL-safe, control-character, or
impossible-length values are treated as corrupted payload structure before
decrypting. Neither case may replace local state or be shown as a generic
network failure.
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
the dialog open and expose retry and settings actions instead of forcing users
to close and reopen the flow or hunt for the sync configuration.
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
`//host/path`, are resolved with the configured endpoint scheme and accepted
only when they satisfy the same origin, credential, query, fragment, encoded
segment, and base-path checks as absolute listing entries. Cross-origin or
userinfo-bearing network-path listing entries are ignored for the same reason.
Relative-looking `href` values that decode into network-path or absolute URL
references are ignored before root-folder matching. Plain relative `href`
values with path separators must already start at the sync root, while bare
child file names from snapshot or operation-log collection listings may be
resolved relative to the requested collection. Server-absolute `href` values
must stay under the configured endpoint path before they can be reduced to
endpoint-relative sync paths.
The WebDAV client itself also refuses absolute or parent-traversing request
paths, request paths with backslashes, paths with control characters,
unsafe base URI authorities with encoded separators, unsafe base URI paths including control
characters, encoded path separators, blank path segments, and request path segments that decode to path
separators.
Request path segments that collapse to blank after trimming are also refused.
Request paths and their decoded segments must not contain leading or trailing
whitespace, so low-level callers cannot silently address a different remote
file by adding raw or percent-encoded edge spaces.
It resolves all accepted paths beneath the configured endpoint.
Metadata reads prefer `HEAD`, but must fall back to `PROPFIND` with `Depth: 0`
when a provider does not implement `HEAD` or forbids `HEAD` while still
allowing WebDAV property reads. Some providers also return a false `404` for
`HEAD` on existing resources; metadata reads may retry those with `PROPFIND`
and accept the resource only when a matching safe `href` is returned. When a
fallback `PROPFIND` response contains multiple entries, metadata must be taken
from the entry matching the requested resource path instead of blindly trusting
the first response entry.
Metadata `href` matches with query components or fragments are ignored instead
of silently dropping non-path URI parts. Absolute and scheme-relative metadata
`href` matches must also stay on the same WebDAV origin and must not contain
embedded credentials before their path can be used for fallback metadata
selection. Metadata `href`
matches with raw or percent-encoded control characters are ignored before their
paths can be compared with the requested resource. Metadata `href` matches
with raw or percent-encoded dot-segments are ignored instead of being normalized
to a different resource path. Safe percent-encoded metadata `href` paths, such
as UTF-8 file names, are compared by decoded path segment so providers that
return encoded `PROPFIND` hrefs still match the requested resource without
allowing encoded separators, control characters, blank segments, or
dot-segments.
Relative metadata `href` matches must be relative to the configured WebDAV
endpoint or to the requested resource's parent directory for `Depth: 0`
fallbacks, not an arbitrary suffix of the requested resource path.
Missing-resource responses should accept both `404 Not Found` and `410 Gone`
for metadata probes, idempotent cleanup deletes, and missing snapshot or
operation-log collections; direct payload downloads must still fail when the
selected remote file is gone.
If `manifest.json` disappears with `404` or `410` between metadata probing and
download, sync treats the manifest as missing again and recreates it only with
`If-None-Match: *`.
Provider `409` or `412` responses to that create-only manifest write are
treated as manifest conflicts so the uploaded snapshot remains recoverable and
the local state can retry instead of surfacing a provider-specific hard failure.
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
Collection listings use `PROPFIND` with `Depth: 1`. If a provider rejects or
redirects that collection request without a trailing slash, the client may retry
the same normalized path once with a trailing slash. This retry must not follow
an arbitrary `Location` header and must not be used for file-level metadata,
download, or upload requests.
WebDAV requests also send a stable `User-Agent` so provider logs and throttling
diagnostics can distinguish RePaperTodo from generic client traffic.
WebDAV `Content-Length` and `getcontentlength` metadata must be accepted only
as unsigned decimal digits without leading or trailing whitespace or control
characters; signed, decimal, negative, padded, or malformed size values are
ignored instead of being used for recovery sorting or diagnostics.
WebDAV `Last-Modified` and `getlastmodified` metadata must parse as exact HTTP
date values without leading or trailing whitespace or control characters.
Malformed date metadata is ignored instead of failing listing or recovery
metadata reads.
WebDAV requests must not follow HTTP redirects automatically; redirect
responses should tell users to check the configured endpoint so credentials and
payload writes stay bound to the intended provider origin.
HTTP client and socket transport failures should be surfaced through the same
retryable WebDAV error path.
WebDAV failure response bodies should respect declared HTTP charsets before
they are attached to sync diagnostics, so provider-localized quota,
permission, or throttling details remain readable when troubleshooting.
Non-empty provider response details should be shown in user-facing retryable
sync errors after whitespace/control-character cleanup, including DEL and C1
controls, and bounded truncation, unless they duplicate the primary WebDAV
failure message.
Closing a WebDAV client wrapper must always prevent later wrapper requests,
even when the underlying HTTP client was injected and remains owned by the
caller.
Provider `Retry-After` hints on throttling or temporary-unavailable responses
should be preserved in retryable WebDAV error messages so users can wait the
right amount of time before trying again. A zero-second retry hint is valid and
means the user can retry immediately; signed or decimal delay values are
malformed, and negative or malformed values are ignored.
Missing or weak ETags must not be used for manifest overwrite conditions:
manifest writes for an existing remote manifest require a strong ETag and are
treated as conflicts instead of unsafe unconditional overwrites when that ETag
is unavailable. Optional legacy operation-log migrations are skipped until a
strong ETag is available.
WebDAV ETag metadata with control characters, empty quoted tags, wildcard-only
values, or malformed quote structure is ignored before it can affect recovery
sorting or conditional writes. Unquoted provider ETags may be retained for
compatibility, but `If-Match` generation must quote them before transport and
must reject weak, control-character, or malformed values instead of sending an
unsafe condition header.
Collection creation treats common successful or already-existing `MKCOL`
responses as accepted, including provider-specific 409/412 responses only when
their body clearly reports that the collection already exists, including
localized already-exists wording, while preserving hard failures such as missing
parents, permission errors, and quota errors. English detection must not treat
generic `exist` wording such as `does not exist` as an already-existing
collection.
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
Operation upload queues must skip operations whose device ID normalizes to
blank, whose sequence falls outside the 12-digit remote sequence range, or
whose targeted payload is structurally incomplete before collection creation or
upload requests can reach WebDAV. Skipping a malformed local operation must not
allow a later operation from the same device to be uploaded out of sequence and
create a remote gap.
Manifest wire keys are decoded case-insensitively for legacy or hand-edited
WebDAV metadata compatibility, while modern camelCase keys win when duplicate
legacy keys are present.
Manifest `updatedAtUtc` wire timestamps must parse strictly with an explicit
time zone; overflow dates or times must be rejected instead of normalized to a
different instant, invalid time-zone offsets are rejected, and leading or
trailing whitespace is not accepted.
Manifest schema and sequence numbers accept unsigned decimal integer JSON
strings as well as JSON numbers, while signed, non-integer, non-positive, or
leading/trailing whitespace string values remain invalid. Decimal or exponent
numeric forms such as `1.0` or `1e0` are rejected instead of being rounded or
coerced into an integer.
Manifest device sequences must reject values outside the 12-digit remote
sequence range before they can advance local operation progress.
When downloading an operation log, the `<deviceId>-<sequence>` file name is
treated as the authoritative operation identity so stale or hand-edited payload
metadata cannot advance the wrong device sequence.
Each decoded operation log payload must contain exactly one non-empty JSON
operation. Known operation wire keys are decoded case-insensitively for legacy
compatibility, while modern camelCase keys win when duplicate legacy keys are
present. Operation sequence numbers accept unsigned decimal integer JSON strings
inside the supported remote sequence range for hand-edited legacy logs, while
signed strings, leading/trailing whitespace string values, and decimal or
exponent numeric forms remain invalid; the file name remains authoritative
after decode.
Delete operation payload keys must remain case-insensitive through the full app
sync merge path, including the local tombstone preservation step after the
merge applier runs, so legacy-cased `PaperID` or `ItemID` payloads cannot delete
data without recording the matching local delete tombstone.
Snapshot-marker operations do not modify local state, but they must still carry
a non-empty safe relative `snapshotPath` before they can advance operation
sequence progress. Snapshot marker paths must reject absolute URLs, scheme-like
or authority paths, parent-directory segments, blank path segments, backslashes,
control characters, and encoded path separators. Newly written snapshot-marker
operation logs must use the canonical payload shape with `snapshotPath` only,
so local diagnostic fields do not become part of the remote sync contract.
Paper and todo-item upsert payloads must compare by the same model
normalization that merge application uses when their IDs are stable, so legacy
PaperTodo casing, default dimensions, clamped text zoom, note-canvas z-order,
todo column limits, due dates, and reminder ranges do not turn equivalent
duplicate logs into conflicts. Local operation diff generation must use the
same model-normalized paper and todo-item payloads before comparing local
states or uploading new upsert logs, so Windows and Android do not publish
remote changes for values that normalize back to the same model state.
Malformed operation-log JSONL entries should preserve the physical line number
in their format error so damaged remote logs can be diagnosed without guessing.
Plain operation-log decoding should treat CRLF, LF, and standalone CR as
physical line delimiters for legacy or hand-repaired WebDAV files while newly
written canonical logs continue to use LF.
Operation kind values are matched case-insensitively for legacy compatibility,
but leading or trailing whitespace is rejected instead of being trimmed into a
different valid operation kind.
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
must be skipped at the same boundary. Structurally incomplete operation payloads
must also be skipped before legacy plain operation logs are rewritten as
encrypted payloads. Missing ETags or conditional conflicts leave the merge
accepted and surface a retryable migration status instead of blocking user data.
Legacy operation-log migration failures must be counted as not migrated while
still applying the downloaded operations.
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
Merge application must also block a device sequence when a targeted operation
payload is structurally incomplete, such as a missing paper, item, settings
object, paper ID, item ID, or note-content string field. Well-formed operations
that produce no local change because the target no longer exists or a tombstone
wins are still consumed, so stale but readable logs do not permanently block
later operations from that device.
Target paper IDs, todo-item IDs, linked-note IDs, and note-canvas element IDs
inside operation payloads must also be nonblank after trimming and must not
contain raw control characters. Malformed ID payloads block that device
sequence before they can write local state, tombstones, or uploaded canonical
operation logs.
Local model normalization strips raw control characters, including DEL and C1
controls, from stored paper IDs, todo-item IDs, linked-note IDs, and
note-canvas element IDs before de-duplication, link validation, platform
surface refresh, or WebDAV upload.
Todo-item payloads clear a linked note by omitting `linkedNoteId`; blank
`linkedNoteId` strings are structurally incomplete instead of being normalized
to an unlink operation during merge.
Upsert-paper payloads must also keep nested todo-item IDs and note-canvas
element IDs unique after trimming. Duplicate nested IDs are structurally
incomplete because normalizing them would mint replacement IDs differently on
each device.
Settings operations that contain only protected local fields such as WebDAV
sync settings, startup-at-login, or paper lists must be treated as structurally
incomplete instead of advancing device progress as no-op setting changes.
Settings operations also use an explicit app-preference whitelist: unknown
root setting fields must not be copied into local extension metadata, and a
settings operation containing only unknown fields must be treated as
structurally incomplete. Local operation diff generation must use the same
whitelist so unknown local `AppState.extra` fields are not uploaded as remote
settings changes, and it must generate canonical settings payloads with the
same enum, numeric, boolean, color, hotkey, extension, and queue-map
normalization used by merge application. Invalid local setting values must be
dropped before upload, and semantically equivalent setting formats must not
create remote operation logs. Integer app-preference settings accept JSON
integers and unsigned integer strings without leading or trailing whitespace
only; signed, whitespace-padded, fractional, decimal, or exponent forms must be
dropped instead of rounded into valid settings.
Double app-preference settings accept finite JSON numbers and unsigned decimal
strings without leading or trailing whitespace only; signed,
whitespace-padded, exponent, infinity, NaN, or malformed forms must be dropped
instead of parsed into valid settings.
Capsule-mode dependency settings must also be folded before comparison or
upload: disabling capsule mode, deep capsules, or collapse-all implies the same
dependent queue, active-state, and deep-capsule
margin resets that `AppState.normalize` applies locally.
Boolean queue-map settings such as collapse-all active queues must also use
the same alias precedence as `AppState.normalize`: exact canonical
`monitor|side` keys override older aliases, and canonical `false` values remove
an older truthy alias before upload or equivalence comparison.
Double queue-map settings such as deep-capsule start margins use the same exact
canonical key precedence, then clamp margins to the app's valid range before
upload or equivalence comparison.
Deep-capsule monitor names and queue-map keys with raw control characters are
dropped from remote settings operations before they can become local queue
state.
Upsert-paper top-level fields that preserve paper type, title, content,
window geometry, visibility flags, text zoom, or capsule identity must keep
their expected wire types when present; malformed known fields are
structurally incomplete instead of being defaulted into a different paper type,
blank title/content, fallback bounds, or changed visibility state during merge.
Paper `type` is required in `upsertPaper` operation payloads and must be `todo`
or `note` case-insensitively; missing types are structurally incomplete instead
of being defaulted to todo papers during merge.
Paper titles in upsert payloads must already match the app's hard stored-title
shape: no leading or trailing whitespace, no raw control characters, and no
more than the shared storage title length cap. Malformed title payloads are
structurally incomplete instead of being silently stripped or truncated during
merge.
Note content in `upsertPaper` and `updateNoteContent` operation payloads must
also stay within the shared Markdown editor storage limit. Todo-paper
`upsertPaper` payloads must not carry non-empty note `content`, so hidden note
body text cannot later resurface after a remote type change. Oversized note
content and non-empty todo-paper content are structurally incomplete instead of
being silently truncated or hidden during merge.
Paper window dimensions in operation payloads must stay at or above the shared
minimum paper size, and `textZoom` must be positive; dimensions that would fall
back to default bounds or non-positive zoom values are structurally incomplete
instead of being accepted as remote geometry changes.
Paper capsule identity fields must also keep safe values when present:
`capsuleSide` must be blank, `left`, or `right` case-insensitively, and
`capsuleMonitorDeviceName` must not contain raw control characters. Malformed
capsule payloads are structurally incomplete instead of being normalized into a
different edge or monitor during merge.
Nested operation payload objects such as `paper`, `item`, and `settings` must
remain JSON objects with string keys; malformed local or remote payload objects
must be treated as structurally incomplete instead of throwing during merge or
upload filtering.
When an upsert-paper payload includes nested collection fields such as `items`
or `noteCanvasElements`, those fields must be lists whose entries are JSON
objects with string keys. Malformed nested collection fields are structurally
incomplete instead of being silently dropped, because dropping them could
overwrite a local paper with a partial remote payload.
`upsertPaper` payloads must also keep non-empty collections on the matching
paper type: todo papers may carry todo `items`, note papers may carry
`noteCanvasElements`, and empty irrelevant lists remain compatible. Non-empty
wrong-type collections are structurally incomplete instead of being hidden in
the model and resurfacing after a later type change.
Todo-item collection subfields such as `todoExtraColumns` and
`todoColumnWidths` must also keep their expected list shapes when present;
malformed column payloads are structurally incomplete instead of being coerced
to empty or default columns during merge.
Zero-width legacy values in `todoColumnWidths` may still normalize to the
default width for compatibility, and oversized positive values may still clamp
to the app range. Negative column widths are structurally incomplete instead of
being silently reset to the default width during merge.
Remote operations that include `todoExtraColumns` or `todoColumnWidths` must
also include `todoColumnCount`, and those lists must not exceed the declared
column shape. Otherwise the operation is structurally incomplete instead of
being defaulted to one column or truncated by model normalization.
Todo column counts in operation payloads must be positive JSON integers when
present; positive values above the app limit remain legacy compatible and are
clamped by model normalization. Zero or negative column counts are
structurally incomplete instead of being silently normalized to one column
during merge.
Todo-item scalar subfields that preserve user content or scheduling state, such
as `text`, `done`, `order`, `todoColumnCount`, `linkedNoteId`, `dueAtLocal`,
`reminderIntervalValue`, and `reminderIntervalUnit`, must also keep their
expected wire types when present; malformed todo-item payloads are structurally
incomplete instead of being defaulted into blank text, unchecked state, fallback
ordering, cleared due dates, or changed reminder settings during merge.
Todo item text fields, including extra column text, must also stay within the
shared Todo text-entry line limit. Oversized Todo text payloads are
structurally incomplete instead of being truncated during merge or allowed to
bypass the local editor limit through WebDAV operation logs.
Todo due-date payloads may use PaperTodo-compatible parseable date strings,
including ISO-like, slash-separated, day-first, Chinese year/month/day, and
.NET seven-fractional-digit forms, and are canonicalized by model
normalization. If a `dueAtLocal` field is present, blank, control-character, or
unparseable values are structurally incomplete instead of clearing the todo's
due date during merge; clearing a due date is represented by omitting the field
from the full todo-item payload.
Todo reminder interval values in operation payloads must be positive JSON
integers when present; positive values above the app limit remain legacy
compatible and are clamped by model normalization. Reminder interval units may
appear only with a positive interval value, must be `minutes` or `hours`
case-insensitively, and must not contain leading or trailing whitespace or raw
control characters. Zero, negative, dangling, padded, control-character, or
unknown reminder interval payloads are structurally incomplete instead of
clearing reminders or silently defaulting the unit to minutes during merge.
Note-canvas element subfields that preserve user content, block kind, or
geometry, such as `type`, `text`, `x`, `y`, `width`, `height`, and `zIndex`,
must also keep their expected wire types when present; malformed canvas payloads
are structurally incomplete instead of being defaulted into blank code blocks,
code block types, or fallback geometry during merge.
Canvas element text payloads must stay within the shared Markdown text limit so
operation logs cannot inject blocks larger than the note editor accepts.
Oversized canvas text payloads are structurally incomplete instead of being
silently truncated during merge.
Canvas `type` payloads must already be one of the current or known legacy block
types (`code`, `text`, or `sticky`) case-insensitively, without leading or
trailing whitespace or raw control characters. Unknown canvas types are
structurally incomplete instead of being silently normalized to code blocks
during merge.
Canvas geometry values in operation payloads must also stay within the shared
note-canvas coordinate and size bounds; coordinates or dimensions that would be
clamped or defaulted by model normalization are structurally incomplete instead
of being accepted as remote canvas changes.
Canvas `zIndex` values must be JSON integers greater than or equal to zero;
legacy zero values remain accepted for model-normalized comparison, but
negative layers are structurally incomplete instead of being reassigned during
merge.
Matching duplicate upload candidates for the same device sequence are
deduplicated, while conflicting duplicates block that device so an arbitrary
operation is never chosen. Accepted operation upload candidates must be written
with canonical operation payloads, not whichever legacy-cased or hand-edited
duplicate happened to appear first, so remote logs keep a stable wire shape.
Malformed duplicate upload candidates for the current device sequence block
that device even when another candidate for the same sequence is well formed,
so upload selection never silently chooses around damaged local queue data.
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
Downloaded, decoded, or restored tombstone paper IDs and todo-item IDs must be
nonblank after trimming and must not contain raw control characters, including
leading or trailing control characters that `trim()` would otherwise remove.
Invalid tombstone IDs are discarded before they can preserve deletes or pollute
local sync metadata.

Settings operations are intentionally limited to app preferences. They do not
replace local sync settings, WebDAV credentials, operation device sequences, or
delete tombstones, and they do not replace local startup-at-login state. Sync
progress comes from manifests, operation logs, and local upload results instead.
They also do not replace unknown local `AppState.extra` fields, so future or
plugin-local settings cannot be injected through remote operation logs.

Local device sequence progress must never move backward. Operation upload
progress comes from returned device sequence metadata and explicitly accepted
operation sequences, not from `uploadedCount`. The local state merges those
maps with the previous sequence map by taking the highest valid sequence per
device. Upload result sequence maps must be normalized before saving so blank
device IDs, short-invalid device IDs, and sequence values outside the remote
range cannot pollute local sync progress.
Persisted or restored operation device sequence maps must accept only integer
JSON numbers or unsigned decimal integer strings; signed strings, decimal or
exponent numeric forms such as `1.0` or `1e0`, non-positive values, values
outside the remote range, and leading/trailing whitespace string values must be
discarded instead of rounded, coerced, or trimmed into valid sync progress.
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
Restoring a legacy plain recovery snapshot while encrypted sync is configured
must report the legacy plain source to the user, but the restore action itself
must not upload a migration snapshot; the next normal successful upload writes
encrypted payload bytes.

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
  If a foreground/background transition requests a silent sync while another
  WebDAV sync is already active, the lifecycle request must be queued and run
  once after the active sync finishes, so Android backgrounding does not drop
  the last opportunistic WebDAV pass.
  Exit commands must wait for any active manual or automatic sync attempt to
  finish before flushing pending local-edit operations and running the final
  sync, so platform cleanup does not race ahead of in-flight WebDAV work.
  Duplicate exit commands must share the same in-flight exit save/sync future,
  so tray exit, forwarded `--exit`, and Windows session-ending retries cannot
  upload the same pending operation or run the final sync more than once.
  While that exit future is active, late startup commands, tray open/delete
  requests, and native hidden-surface updates must be ignored so shutdown
  retries cannot mutate paper visibility or tombstones before cleanup.
  If the active sync fails, the exit flow must still continue with the final
  local-edit upload attempt and platform cleanup instead of leaving the app
  running half-closed.
  On Android, a WorkManager periodic task should register a headless Dart
  background dispatcher when WebDAV sync is securely configured. The background
  task receives only the local `data.json` path, reloads the StateStore, and
  reuses the shared `AppSyncService.syncAndMergeNow` path instead of
  reimplementing WebDAV merge logic in Kotlin. Incomplete or disabled WebDAV
  settings should cancel the periodic task. Registration and task execution
  must both reject unsafe, relative, or non-`data.json` state-file paths
  instead of scheduling doomed background work. The task must require network connectivity,
  use bounded backoff, and report failure to WorkManager only when it should be
  retried.
  Disabled sync,
  incomplete configuration, and unreadable remote payloads are user-recoverable
  non-retry states; remote write conflicts remain retryable so WorkManager can
  make another attempt after backoff.
  Saving sync settings while the app is running must refresh that Android
  background registration after the new StateStore contents are durably saved,
  so enabling or disabling WebDAV does not wait for the next app launch.
  Primary startup `exit` commands use the same exit-sync gate before platform
  cleanup even when startup auto-sync is disabled; WebDAV failures there are
  still opportunistic and must not prevent exit.
  Silent local-edit upload failures must keep the pending edit so later
  automatic, lifecycle, or manual sync attempts retry the same operation without
  requiring another user edit.
- Opening settings must pause pending debounced local-edit uploads and defer lifecycle/auto sync while the dialog is open; canceling settings or saving settings without changing sync configuration restores the pending upload, even when platform setting application reports errors, while saving sync setting changes clears stale pending uploads so edits are not sent under a new sync configuration. Settings save failures must surface as readable UI errors and must not drop the paused pending edit or leave later local edits blocked from debounced upload.
- After any sync, recovery restore, or local-operation upload replaces local state, reapply the resulting state to the platform layer so Windows surfaces, tray state, hotkeys, and window policies match the accepted data. This still applies when an operation upload is accepted idempotently and creates no new remote log, because sequence progress and canonicalized state affect later sync inputs and Windows integration.
- Offer retry actions for transient manual sync, recovery snapshot listing, and recovery restore failures.
