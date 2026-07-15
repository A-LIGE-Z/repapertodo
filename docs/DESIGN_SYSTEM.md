# RePaperTodo Design Baseline

RePaperTodo is a quiet productivity utility, not a marketing app.

The interface should stay close to PaperTodo's "sheets of paper" metaphor:

- Calm, compact, and direct.
- No dashboard-first experience on Windows.
- No decorative hero screens.
- No heavy card nesting.
- No visual noise that competes with the user's notes.
- Touch targets on Android must meet platform minimums.
- Desktop controls should remain precise and keyboard-friendly.
- Light and dark mode must be designed together.
- Motion must explain state changes such as collapse, expand, dock, and restore.

## Flutter UI Rules

- Use semantic theme tokens rather than raw colors in widgets.
- Keep paper surfaces visually quiet, with restrained shadows and borders.
- Prefer platform-appropriate controls over custom controls unless PaperTodo parity requires custom behavior.
- Preserve visible focus states and screen-reader labels for every interactive control.
- Scope runtime localization to Chinese and English; unsupported system
  languages fall back to English, and new user-facing strings only need those
  two language entries. Every declared `PaperTodoStringKeys` entry must exist
  in both runtime maps.
- The Tooltips setting only controls ordinary operation hints. Settings-page
  explanation/info affordances must remain available when it is off.
- Respect reduced motion.
- Avoid emoji as structural icons.
- Make compact desktop UI and touch-friendly Android UI from the same design language, not the same exact density.
- On Android, place the PaperTodo-colored sheets on a subtly darker neutral
  canvas so each paper keeps the original floating-sheet hierarchy without
  turning the screen into a generic Material card dashboard.

## Windows Priority

Windows is not a scaled-up mobile app. The first Windows milestone must feel like independent desktop papers, not a single Flutter dashboard pretending to contain papers.

The Windows platform channel treats each paper as an addressable surface. The
custom runner owns one child Flutter engine and one top-level HWND per visible
paper; the primary coordinator HWND stays hidden during normal paper use and
remains responsible for the tray, startup commands, persistence, and sync.
Opening settings temporarily presents that coordinator as a dedicated settings
window; settings must never be embedded into a paper surface. Paper HWNDs are
removed from the taskbar through the native taskbar API without coupling that
policy to the separately configurable Alt+Tab visibility setting.
Child engines receive canonical state for rendering but return only their own
normalized `PaperData`, so concurrent paper edits cannot overwrite global state
from a stale child snapshot. The release smoke enumerates visible top-level
process windows and requires the count to match visible papers.
Each child HWND independently applies always-on-top, Alt+Tab visibility,
desktop-worker pinning, fullscreen topmost avoidance, and covered/fullscreen
deep-capsule hiding. Collapsed child windows use the PaperTodo 92x46 capsule
size while retaining expanded dimensions in `PaperData` for restoration.

The compatibility registry described below remains the routing and fallback
boundary for tray state, early startup events, and legacy native calls.
Window and tray events may include a `paperId` so Dart can route bounds,
show/hide, close, and open requests to the correct `PaperData` even while the
native runner manages multiple Flutter windows. The native runner should
preserve that `paperId` in follow-up window events after Dart sends it through
show, hide, bounds, or tray commands.
Events that explicitly name an unknown `paperId` should be ignored instead of
falling back to the active paper, while legacy events without a `paperId` may
still target the active paper for backward compatibility.
Explicit `paperId` event values must already be normalized: Dart should ignore
values with leading or trailing whitespace or raw control characters instead of
trimming them into a known paper ID.
Stored local paper IDs should be stripped of raw control characters during
model normalization before any Windows surface payload is assembled.
Native direct paper surface operations must follow the same rule. A structured
argument that explicitly provides an unsafe or unnormalized `paperId` should be
ignored rather than falling back to the active paper.
Dedicated registry refreshes from restore and registry refreshes reused by tray
rebuild should prune paper IDs that are no longer present in the current state
so late native events from deleted or replaced papers are ignored.
Surface commands that change visibility, desktop pinning, or always-on-top
state should send structured arguments with the `paperId`, while the runner
keeps compatibility with older string and bool arguments. The runner should
also accept structured window title updates with both `paperId` and `title`,
while keeping the older string title argument as a fallback. The runner should
cache per-paper bounds from `setBounds` and move/resize events so a bounds query
for a non-active paper does not overwrite that paper with the active window's
geometry. Structured surface refreshes for a non-active paper should update the
runner's per-paper registry without stealing the active paper, moving the
current host window, changing the current host title, or applying z-order
changes until that paper is shown. Startup restore and tray menu rebuilds
should include paper geometry so the native surface registry can refresh every
paper without moving the current window. When the active native surface is
hidden or closed while another registered paper is still visible, the runner
should retarget the host window to the next visible surface after the hidden
paper in the latest Dart registry order instead of hiding the whole app window.
For independent paper HWNDs, live Win32 bounds remain authoritative after a
drag or resize: content edits, title refreshes, tray rebuilds, topmost changes,
and desktop-pin refreshes must not replay stale model geometry. Only an
explicit geometry operation may move or resize an existing expanded paper.
Live bounds may override a registry refresh only when the native HWND is
already expanded. During capsule-to-paper transitions, the saved normal paper
geometry remains authoritative so capsule size and edge coordinates can never
become the expanded paper's position or dimensions.
The 8px paper-shadow chrome around Windows child HWNDs must remain genuinely
transparent; the runner uses a reserved color key so Flutter's transparent
scaffold pixels reveal the desktop instead of becoming a white rectangular
frame around the rounded paper.
Startup restore should use the dedicated `setPaperSurfaces` channel instead of
depending on tray-menu rebuilds as a side effect. Registry payloads should also
include
the paper's capsule side and monitor device name so edge-docked and
deep-capsule surfaces can keep their queue identity when the native layer
refreshes or rebuilds tray state. The Windows runner should normalize the
primary monitor device name to an empty queue name, matching PaperTodo's
primary-monitor fallback semantics, while preserving non-primary monitor names.
The Dart Windows platform host should apply that native normalization before
restore, tray-registry payloads, and direct paper surface operations so
imported primary-monitor state is cleaned back to the canonical empty queue
name.
Minimized Windows surfaces must not persist
bounds updates,
because Windows can report synthetic minimized coordinates that would corrupt a
paper's saved position.
Normal startup should restore every non-deleted paper as visible for the
current session, matching PaperTodo's model where closing or hiding a paper
does not make it feel lost on the next launch. Explicit startup exit commands
must not perform this visibility restore. When no primary instance is running,
an explicit `exit` or `quit` startup command should return before creating the
Flutter window, matching PaperTodo's lightweight self-check path; when a
primary instance is running, the secondary process should still forward the
exit command so Dart can save, sync, and clean up normally.
Secondary startup commands can arrive before the Flutter UI has subscribed to
platform startup events, so the Windows platform host must buffer early
commands and replay them in order once the app listener is attached.
The Windows tray paper list should expose useful paper state at a glance:
visible papers are checked, while hidden, collapsed, desktop-pinned, and
topmost states are shown in the menu label. Platform close/show/hide events
should refresh the tray menu promptly when they change paper visibility, while
plain move/resize bounds updates should not trigger extra tray rebuilds.
Paper deletion should remain available from the Windows tray with an explicit
confirmation step, then route through Dart deletion so PaperTodo tombstones,
linked-note cleanup, undo, surface hiding, and tray refresh stay consistent.
Deep-capsule collapse-all follows PaperTodo's queue model: the master capsule
acts on one `(monitor, side)` queue, while the board-level fallback may still
toggle all papers for compatibility with the current Flutter surface.
Imported or restored collapse-all queue maps should normalize queue aliases
with exact canonical `(monitor|side)` entries taking precedence over legacy
aliases, including canonical `false` values that remove an older alias.
Deep-capsule monitor fields should strip raw control characters before they
become local state, while imported collapse-all or start-margin queue-map keys
that contain raw control characters should be dropped.
Disabling capsule mode should immediately restore all collapsed papers, clear
deep-capsule collapse-all state, reset deep-capsule start margins, and refresh
the platform paper surfaces just as PaperTodo updates live paper windows.
Showing a collapsed paper that can no longer display as a capsule, such as a
linked note hidden from capsules or any paper while capsule mode is disabled,
should expand it before handing it to the platform surface host.
New visible papers created in deep capsule mode should resolve the target
Windows work area and open away from the deep capsule edge strip when expanded
capsules remain visible, using PaperTodo's capsule width, gap, and expanded
edge inset constants.
Deep-capsule visibility policies should preserve PaperTodo's separate
settings: fullscreen-app hiding and external-window covered-area hiding are
independent toggles. Reading legacy PascalCase `HideDeepCapsulesWhenFullscreen`
must map to `hideDeepCapsulesWhenFullscreen`, not collapse into
`hideDeepCapsulesWhenCovered`, so WebDAV operation logs and local saves keep
the two behaviors distinct.
New papers created from an existing paper should follow PaperTodo's source
paper behavior: open 30px down and right from the source, inherit always-on-top
state, and keep the source capsule queue when one is set.
New paper default titles should follow PaperTodo's first-unused-number rule:
scan same-type default titles such as `Todo1` and `Todo3`, ignore custom
titles, and assign the lowest missing positive number such as `Todo2`.
New desktop papers should follow PaperTodo's cascade placement: start near
`140,140`, offset each new paper by the existing paper count, and nudge again
when the target position is already occupied.
Paper creation must stop at PaperTodo's 100-paper limit. User-triggered
creation should show an in-app cleanup prompt instead of adding a 101st paper,
and background startup commands should quietly no-op at the limit.
Before a new desktop paper is first shown, clamp its dimensions and position to
the resolved Windows work area so large cascades or small screens do not create
lost off-screen papers.
Startup restore should also rescue persisted papers into their resolved work
area before native surfaces are restored, matching PaperTodo's disconnected
monitor recovery behavior.
The tray icon should be resilient to Windows Explorer/taskbar restarts by
handling the `TaskbarCreated` broadcast and re-adding the notification icon.
For PaperTodo parity, a `PaperTodo.ico` or `RePaperTodo.ico` file next to the
Windows executable should override the embedded tray icon.
The executable directory lookup for external tray icons should use the same
dynamically sized module path logic as startup-at-login so long install
directories do not disable runtime icon overrides.
The first tray menu row should match PaperTodo's version header pattern by
showing `RePaperTodo v<version>` from the packaged Flutter version, with build
metadata after `+` hidden from the visible label.
Tray icon primary-button handling should match PaperTodo: double-click restores
all papers through the same `show` startup command path, while a single left
click does not show or create paper windows.
Native Windows tray menus that create nested popup menus should keep each
`HMENU` scoped until `AppendMenu(..., MF_POPUP, ...)` succeeds, so failed menu
construction paths do not leak confirmation or delete submenus.
Tray-level Show and Hide commands should be routed as startup commands so they
apply to every paper, not just the active surface.
Tray-level Toggle should use the same startup command path and let Dart decide
whether all papers should be shown or hidden from current visibility state.
Pinning a paper to the desktop should follow PaperTodo's surface-mode rules:
the paper becomes visible and expanded, always-on-top is cleared, capsule and
deep-capsule mode are enabled, and missing capsule queue fields are initialized.
Expanded desktop-pinned paper surfaces should be interaction-locked like
PaperTodo: the title and paper body ignore editing, chrome actions such as
hide/delete/collapse/zoom/always-on-top are unavailable, and the desktop unpin
control remains reachable.
On Windows, pinned papers remain top-level `WS_POPUP | WS_THICKFRAME` windows
placed at `HWND_BOTTOM`; they must not be reparented into `WorkerW`, because the
selected worker can sit behind the wallpaper compositor and hide the paper.
Desktop pinning does not enable native click-through, so the unpin control stays
usable while the PaperTodo interaction lock is active.
Pinned HWNDs use no-activate behavior, reject native move requests, and enforce
`HWND_BOTTOM` during window-position changes so clicks cannot raise or move
them. Every paper control except unpin must be disabled while this mode is
active.
Activating a collapsed desktop-pinned paper should follow PaperTodo's capsule
path by clearing desktop pinning and restoring the paper expanded instead of
leaving a pinned expanded surface behind.
Surface mode controls such as desktop pinning and always-on-top should update
the native paper surface, persist local state, and rebuild the tray menu
immediately after the user toggles them.
Hiding a paper should follow PaperTodo's single-paper rules: clear desktop
pinning, mark the paper hidden, and expand it before persisting or refreshing
platform surfaces. Deleting the last remaining paper should immediately create
a visible default Todo paper so the app never settles into an empty board.
Native hide requests for a specific non-active paper must update that paper's
surface state without hiding the currently active Windows host window.
Tray-level Exit and forwarded `quit`/`exit` commands must also go through the
Dart startup command path so the app can save local state and run the configured
sync-before-exit flow before the native runner destroys the window.
Once the Dart controller has started exit cleanup, later exit startup commands
must be ignored so tray exit, forwarded `--exit`, and session-ending retries do
not duplicate hotkey unregister, tray disposal, or native exit calls.
Before that platform cleanup starts, duplicate exit requests must share the
same Dart save/sync-before-exit future so pending WebDAV operation upload and
the final sync are also one-shot.
Once that future exists, late startup commands, tray paper open/delete
requests, and native hidden-surface updates must be ignored so shutdown noise
cannot hide, delete, or create papers while the final sync is waiting.
Windows session-ending messages should follow the same path: `WM_QUERYENDSESSION`
and confirmed `WM_ENDSESSION` should request the `exit` startup command once so
logoff, shutdown, or restart can still reach Dart's save/sync-before-exit flow
instead of closing only the native host. The one-shot session-ending guard
should be set only after the Flutter method channel is available, so an early
or teardown-phase message that cannot be delivered does not suppress a later
confirmed session-ending retry.
Startup command parsing should be forgiving for command-line and second-instance
use: skip unknown arguments, accept hyphen/underscore/space variants, and keep
aliases such as `new todo`, `new_note`, `add-note`, `close`, `prefs`, and
`quit`. The Windows secondary-process forwarder should canonicalize these
aliases before writing to the primary-instance pipe so Dart receives the same
stable command strings as tray actions. Empty secondary launches should still
default to `show`, but launches that provide only unknown arguments should
forward no command instead of showing every paper.
The primary-instance listener should transfer queued command ownership to the
window message queue only after `PostMessageW` succeeds; failed posts during
teardown must release the command without leaking or dispatching stale startup
actions.
Startup-at-login registration should write the current Windows executable path
to the user Run key using a dynamically sized module path buffer so long install
directories do not silently disable the setting.
Always-on-top papers should be refreshed against the foreground fullscreen
state after startup and while the app is running. In the default avoid mode, a
topmost paper should temporarily leave the topmost band while another
application owns a fullscreen foreground window, then return to topmost after
that fullscreen window is gone. Desktop-pinned papers stay at the bottom and do
not participate in topmost recovery. Display changes, system setting changes,
and power-resume broadcasts should clear the native z-order cache and refresh
the active paper immediately so Windows does not leave non-topmost or
desktop-pinned papers in a stale layer after monitor, sleep, or screen-lock
transitions.
Task-switcher visibility changes should report native Windows failures instead
of pretending the setting was applied; style reads, style writes, and the
follow-up frame refresh must all succeed before the platform call completes.
Fullscreen detection should match PaperTodo's defensive Windows behavior:
prefer DWM extended frame bounds, tolerate small border differences, ignore
tool, cloaked, shell, hidden, minimized, and current-process windows, and scan
foreground-process top-level windows when the foreground handle itself is not
the fullscreen surface.
Global hotkey settings should use PaperTodo-style capture fields: modifier-only
presses are ignored, single-key shortcuts are ignored, `Esc`, `Backspace`, and
`Delete` clear the field, and modifier-plus-key presses write a stable shortcut
string such as `Ctrl+Alt+T`. The Windows runner should still accept forgiving
key aliases: spaced names such as `Page Up`, arrow-key names, lock keys,
number-pad names, and common punctuation names such as `Plus`, `Minus`, and
`Slash`.
Global hotkey registration should follow PaperTodo's safety model: a valid
hotkey must include at least one real modifier (`Ctrl`, `Alt`, `Shift`, or
`Win`) plus one non-modifier key, so single-key global shortcuts are ignored
instead of stealing normal typing.
When a non-empty hotkey cannot be registered because it is invalid or already
claimed by another app, the Windows runner should report a platform setting
failure and undo any partial hotkey registration from the same request.
Pinned paper hotkeys should follow PaperTodo's reveal model: the Todo and Note
hotkeys reveal the first visible desktop-pinned paper of the matching type and
do not create new papers when no matching pinned surface exists. Revealing a
desktop-pinned paper must use a dedicated platform path instead of ordinary
show, so Windows can temporarily move the pinned surface to the top without
clearing desktop pinning or immediately returning it to the desktop bottom.
Hotkey settings should strip control characters before saving or platform
registration while preserving ordinary spaces used by aliases.
For PaperTodo font parity, when no explicit system font family is configured,
the app should try to load `papertodo.ttf` and then `papertodo.otf` from the
Windows executable directory before falling back to built-in font presets.
Missing, invalid, or unsupported runtime font files must not block startup.
Original PaperTodo font preset migration must preserve `yahei` and `dengxian`
instead of silently normalizing them to the default preset.
The custom font family setting should refresh the installed Windows font list
each time settings opens, combining GDI-discovered families with both
`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts` and
`HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts` registry entries so
system fonts and per-user "installed for me" fonts are selectable. The setting
must still allow manual font-family entry when a family is unavailable from the
platform list.
Paper title editing should preserve PaperTodo's hard title rules: the editor
accepts no more than 40 text elements, control characters are removed before
the title is stored, blank titles display the default paper title, and Windows
surface and tray titles use the same cleaned value.
Paper titles should behave like PaperTodo's title host: show as plain title
text by default, use the "Click to edit title" tooltip, enter editing on title
click/focus, end editing on Enter or focus loss, and restore the pre-edit title
on Escape. Collapsed papers and desktop-pinned papers should not begin title
editing until restored or unpinned.
Desktop secondary-click on a paper header/chrome should open a PaperTodo-style
paper context menu. The menu should reuse existing paper actions instead of
forking behavior: create Todo or Note papers from the current paper as the
source, open the paper surface, open note Markdown externally, adjust text
zoom, toggle topmost/desktop pin/collapse state, capture bounds, hide, or
delete the paper. Todo papers should expose the same clear-completed action as
the Todo editor, including sync tombstones and a fallback blank row when every
item was completed. Expanded Note papers should expose the same add-code-block
canvas action as the Note editor. Markdown note preview mode should use this
same paper context menu on secondary-click, while source edit mode should keep
the editor-specific formatting menu. Paper, Todo item, Markdown editor, and
canvas block context menus should keep PaperTodo-style disabled section headers
for scanability, including New, Todo, Canvas, Desktop pin, Format, Text, and
Item sections where those menus expose the corresponding actions.
Paper context menu collapse actions should keep PaperTodo's capsule wording:
expanded papers show Collapse to capsule, while collapsed papers show Restore
window.
Paper-specific chrome and menus should keep PaperTodo's precise wording for
common actions: hide uses Hide this paper, and Note external editor actions use
Open in default `{extension}` editor with the current external Markdown
extension.
The top-bar external-open setting should follow PaperTodo's Note behavior: it
only shows on Note paper surfaces, opens that note in the default Markdown
editor, and displays the first two uppercase characters of the configured
extension such as `MD` or `TX`. The exported file must contain the current Note
editor text, including edits that have not waited for a persistence debounce.

## Android Priority

Android may use a mobile-native navigation model, but the data concepts must remain identical: papers, todo items, notes, linked notes, settings, sync, and conflict recovery.
System back from an opened paper surface should return to the board before the
app route is allowed to pop, matching the visible Back to board control.
Desktop-only settings such as start-at-login, task-switcher visibility,
fullscreen/topmost policy, global hotkeys, and PowerShell script capsules
should be hidden on Android unless the platform layer exposes a real
implementation.
External Markdown exports should be written under the platform documents area
so Windows keeps portable files near the executable and Android FileProvider can
grant temporary read access to other apps. Android FileProvider paths must not
expose the external storage root; external sharing is limited to app-owned
files/cache roots and RePaperTodo-scoped external directories such as
`/storage/.../RePaperTodo`, `/storage/.../Documents/RePaperTodo`, and
`/storage/.../Download/RePaperTodo`. Android app files directory and
external-file channel paths must be absolute `/...` paths and must not contain
raw control characters before they become local state, export roots, or
FileProvider inputs. The native Android opener must canonicalize file paths and
reject files outside those configured share roots before calling FileProvider.
External Markdown export writes must flush before the path is handed to the
platform opener so external editors never observe a partially written note.
Android package visibility queries must cover the same external launch families
the app exposes: `http`, `https`, `mailto`, Markdown/text files, and the
generic file fallback used when a more specific viewer is unavailable.
Generated external Markdown export filenames must replace platform-reserved
characters and raw control characters, including DEL and C1 controls, before
file creation. External Markdown extension settings must reject
platform-reserved characters and raw control characters, including DEL and C1
controls, before saving, but must allow arbitrary file-name-safe suffixes such
as `.todo.md`; the setting should not be constrained to a hardcoded Markdown
extension allowlist or reject repeated dots by preference.
External launches, Markdown links, and script capsules should report platform
failures in the app instead of failing silently.
Script capsule hosts must reject blank scripts and unsupported execution
engines before invoking native launch paths.
Windows script capsule temporary files must be moved into their final `.ps1`
path, written completely, and deleted on write failure before PowerShell is
launched. Persistent PowerShell hosts should also run with `-NonInteractive` so
background capsules cannot hang waiting for console input.
Collapsed note papers whose content starts with a PaperTodo script capsule
marker should behave as script capsules: primary click runs the script without
expanding the note, while secondary click opens the note for editing.
Script capsule parsing should preserve PaperTodo marker and indentation rules:
recognized markers are read only from the first line, shared indentation is
removed from the script body, and the platform line terminator is used before
the normalized script body is handed to the host.
Platform URI and external-file hosts must trim and reject blank launch
arguments before invoking native method channels. Platform URI hosts must also
reject raw or percent-encoded control characters and malformed percent escapes.
Platform external-file paths must reject raw control characters while preserving
ordinary spaces in local filenames. Windows native launch handlers must reject
malformed UTF-8 before converting method-channel strings for `ShellExecuteW`,
so defensive native checks cannot fall back to opening mojibake paths or URIs.
Markdown links must reject raw or percent-encoded control characters and
malformed percent escapes or encoded authority separators before native URI
launch while preserving ordinary encoded path characters.
Markdown note link interaction should preserve PaperTodo edit/preview
semantics: preview-mode links open directly, while edit-mode source links open
only on Ctrl+click and otherwise keep normal text editing behavior. This applies
to Markdown links and the supported single-line inline HTML `a href` links.
Inline HTML anchor parsing should follow PaperTodo's small parser: attributes
must be well-formed `name=value` pairs, quoted values must close, unquoted href
values are allowed, quoted attribute values may contain `>`, and empty anchor bodies
are not link hit targets.
Inline HTML preview rendering should preserve PaperTodo's small single-line
subset only: `b`, `strong`, `i`, `em`, `s`, `del`, `u`, `code`, and `a href`.
It should not enable block HTML, HTML images, HTML tables, embedded content,
or arbitrary tags.
Markdown URL normalization should preserve PaperTodo's bare-host convenience:
links beginning with `www.` open as `https://www...` in both preview mode and
edit-mode source link handling before platform URI validation runs.
Markdown local path links should preserve PaperTodo Windows behavior while
remaining useful on Android: Windows drive/UNC paths, Android POSIX absolute
paths, and `file:` targets open through the external-file host, while Windows
device paths such as `\\.\` and `\\?\` are rejected before native launch.
`file:` targets with query or fragment components are rejected instead of
silently dropping those URI components and opening a different local path.
`file:` targets must also reject control characters after URI decoding, so
percent-encoded newlines or C1 controls cannot reach platform file open calls.
Markdown link hit-testing should skip links inside closed inline code spans,
matching PaperTodo's source editor highlighting and Ctrl+click behavior. It
should use the same CRLF/LF/standalone CR line boundaries as Markdown line
classification so Ctrl+click never resolves a source link across imported
legacy line endings.
Markdown image syntax should follow PaperTodo's lightweight scanner rather than
full Markdown image rendering: `![label](url)` is still treated as a source
link hit target on the label text.
Markdown preview should stay on a PaperTodo-scoped extension set: no GitHub
table or task-checkbox expansion, while code fences and strikethrough remain
available for lightweight notes.
Markdown source link scanning should stay deliberately small like PaperTodo:
the first literal `](` and following literal `)` delimit the target, backslash
escapes are not interpreted, CommonMark angle destinations and title suffixes
are not source link targets, and only `http`, `https`, `mailto`, `www.`,
Windows drive/UNC paths, Android POSIX absolute paths, and `file:` paths are
accepted before the app-level launch validation runs.
Markdown line classification should share one PaperTodo-compatible model for
heading, quote, unordered list, ordered list, task list, horizontal rule, fenced
code fence, and fenced code block detection so editor rendering and Enter-key
continuation cannot drift apart. Document-wide line classification should treat
CRLF, LF, and standalone CR as line delimiters so imported or pasted notes keep
the same fenced-code state regardless of their original newline style.
Markdown insert-link commands should use PaperTodo's English fallback label
`Link` when the selected text is blank.
Markdown notes should preserve PaperTodo's focus-driven reading flow: Markdown
enabled notes open in preview mode by default, clicking the preview body enters
the source editor, and losing editor focus returns the note to preview mode.
Markdown note paste safety should preserve PaperTodo's two-tier length model:
note text may reach 100000 characters, each paste insertion is limited to
30000 characters, incoming CR/LF line endings are preserved, and a pasted line
longer than 6000 characters truncates that paste at the oversized line instead
of continuing with later lines.
Markdown list continuation should preserve PaperTodo's ordered marker parsing:
leading zero markers continue from their numeric value, `long.MaxValue - 1`
may continue to `long.MaxValue`, and `long.MaxValue` or larger markers fall
back to ordinary Enter behavior instead of continuing or removing empty markers.
List continuation should preserve existing CRLF/LF document line delimiters
instead of mixing a new newline style into pasted or imported Markdown notes.
Markdown editors should accept Tab as content like PaperTodo's AvalonEdit
notes: Tab inserts or indents with literal tab characters, Shift+Tab outdents
one leading tab or up to four leading spaces, and focus should not leave the
note editor because of these keys.
Desktop secondary-click inside a Markdown note editor should open a
PaperTodo-style editor context menu with formatting, copy, paste, and select
all actions. Those actions should reuse the same toolbar formatting commands
and Markdown paste sanitation path as keyboard and normal paste input.
Opening or using that editor context menu must not trigger the focus-loss
preview fallback; the note should remain in source-edit mode while the menu is
open and after a formatting or text action restores focus.
Note paper text zoom should preserve PaperTodo's mouse path: Ctrl+mouse-wheel
adjusts the note `TextZoom` in 0.1 steps between 0.5 and 1.5, updates the
surface immediately, and consumes the wheel signal instead of scrolling the
paper body. The visible note zoom status should keep PaperTodo's reset
affordance: when zoom differs from 100%, clicking the status resets the paper
`TextZoom` to 100% through the same surface-update path.
Settings saves should keep ordinary app preferences while surfacing native
integration failures such as hotkey, startup, or script-process errors.
Windows data location changes use the native folder picker, write the current
state successfully before switching the active path, and retain the old file
as a recovery copy. A first run without portable data asks for the data folder;
an existing `data.json` beside the executable remains compatible.
On narrow screens, keep one primary sync action directly reachable and move
secondary board actions such as create, recovery, hidden papers, and settings
into an overflow menu so the app bar never depends on desktop-width space.
Recovery snapshot rows should keep desktop metadata dense, but narrow screens
should stack snapshot metadata above a full-width restore action so long WebDAV
paths do not compete with the touch target.
Paper headers on narrow screens should keep collapse/expand directly reachable
and move surface, external markdown, zoom, pinning, bounds, hide, and delete
actions into a per-paper overflow menu.
Settings controls with several mutually exclusive choices may stay as segmented
buttons on desktop, but Android narrow screens should use compact pickers for
long labels such as WebDAV provider presets.
Long settings rows that pair two input controls should stack vertically on
Android narrow screens, while desktop can keep paired fields side by side.
Settings validation should place recoverable errors on the relevant input field
first, with any summary text acting as context rather than the only clue.
When a settings save fails, focus the first invalid field in visual order so
keyboard and touch users can recover without hunting through the dialog.
Todo rows on narrow screens should keep the checkbox and text field dominant;
secondary item actions such as due date, reminder, columns, linked notes, and
delete belong in a per-item overflow menu.
Todo compact item actions should switch from the current paper/editor width,
not only the top-level window width, so narrow desktop papers keep the same
overflow-safe layout as narrow screens.
Todo due reminders should follow PaperTodo's timing model: without interval
mode, each unfinished due item can remind once from 10 minutes before due time
until 2 minutes after due time; with interval mode, reminders may repeat after
the configured interval once the due time is within that interval. The nearest
scope chooses the candidate closest to the current time, not merely the oldest
overdue item.
Deleting a Todo paper should clear active reminder state for that paper's items
and close any currently displayed reminder for those items, matching
PaperTodo's reminder bubble cleanup. Changing or clearing a todo due date or
per-item reminder interval should also reset that item's reminder state.
Reminder bubbles should pause their automatic close countdown while the pointer
hovers over the reminder content, then resume the remaining countdown when the
pointer leaves.
Opening a Todo reminder should follow PaperTodo's programmatic-open behavior:
make the Todo paper visible, expand it if it was collapsed, and reveal a
desktop-pinned reminder paper instead of sending it through an ordinary show
path.
Todo keyboard editing should follow PaperTodo: Enter with no modifiers inserts
an empty item directly after the focused item and moves focus there. Backspace
on an item whose main and extra text columns are blank deletes that item when
more than one item exists, preserves at least one row, and suppresses repeated
blank-row deletion until key up. After a blank-row Backspace delete, focus
should move to the previous Todo item's text end when one exists, otherwise to
the next Todo item's text start. These structural edits must use todo undo
snapshots and deleted-item tombstones.
New Todo rows created by Enter, the append affordance, or multiline paste
should follow PaperTodo's `AddItemAfter` semantics: the active row keeps its
existing columns, while newly inserted rows start as default single-column
items instead of inheriting the source row's column layout.
Multiline Todo paste should be available from every Todo text column, not only
the main column. The first cleaned line replaces the focused column text, and
subsequent cleaned lines create default single-column Todo rows after the
active row. After a multiline paste creates rows, focus should move to the last
newly inserted Todo item's main text field, matching PaperTodo's last-row
rebuild focus.
When a Todo column has a selection or caret, multiline paste should preserve
PaperTodo's `ReplaceSelection` behavior: the first cleaned line replaces only
the selected range while surrounding text remains intact.
Todo text fields should preserve PaperTodo's `MaxLength = 5000` rule for both
main and extra columns, so normal typing and single-line paste cannot exceed
the same per-column length used by multiline Todo paste cleanup.
Todo text editing should follow PaperTodo's undo snapshot timing: focusing a
main or extra todo text field records its original column text, losing focus
after a change pushes that pre-edit item snapshot, and structural edits first
commit any focused text edit before pushing their own undo snapshot. Ctrl+Z/Y
inside a text field with text undo or redo history should be handled by that
text field before falling back to structural todo undo or redo. A focused
uncommitted text edit should keep Ctrl+Z in the text editor, but should not
block Ctrl+Y unless a text redo entry actually exists. Todo snapshot restore
should clear active text tracking and text undo/redo history because PaperTodo
rebuilds the row text boxes after structural undo or redo.
Todo column editing should preserve PaperTodo per-column semantics: inserting
before column 1 moves the current main text into the first extra column and
creates a blank main column, while deleting column 1 promotes the next column
into the main text. Inserting or deleting later columns should keep the other
columns in order and preserve normalized per-column widths.
Todo column width resizing should preserve PaperTodo splitter semantics: wide
and compact multi-column rows stay on one horizontal line and show an
8px drag target with a single vertical divider between adjacent columns. Column-number
labels and individual field outlines are omitted. Dragging
resizes only that column pair, each column width is clamped to at least 0.2 and
at most 8. Width saves happen without creating a todo undo snapshot.
Todo due editing should preserve PaperTodo date-and-time precision: the picker
must expose compact year/month/day plus 00-23 hour and 00-59 minute choices,
default a
new due time to roughly one hour from now, and save local values as
`yyyy-MM-ddTHH:mm:ss` without milliseconds and with seconds reset to `00`.
The due date and reminder interval dialogs should keep PaperTodo's keyboard
dialog behavior: Enter saves through the same OK path, while Escape cancels
without changing the item.
The reminder interval dialog should focus the interval value field on open and
select the full value so typing immediately replaces the previous interval.
PaperTodo-compatible due dates read from storage should accept common
year-first, slash-separated, day-first, Chinese year/month/day, and .NET
seven-digit fractional-second timestamp forms before normalizing back to the
canonical local format.
The existing Todo due chip becomes a compact, right-aligned two-line due status
that still reopens the due editor like PaperTodo's due badge.
Clicking an existing Todo reminder chip should reopen the reminder interval
editor so chip affordances stay consistent with Todo item menus.
Todo overflow actions should mirror PaperTodo item menus for due and reminder
state: existing due dates show change plus clear actions, existing reminder
intervals show change plus clear actions, and clear actions no-op when the
field is already empty. Creating a per-item reminder interval should default
to the global reminder interval value and unit when the item has no custom
interval yet. Saving that dialog should follow PaperTodo's forgiving input
model: unparsable text falls back to the initial value, non-positive values
become 1, and values above 240 are clamped to 240.
Desktop secondary-click on a Todo row should open the same item action menu
used for compact overflow controls, preserving PaperTodo's right-click access
to due dates, reminders, columns, linked notes, deletion, and clear-completed
actions without creating a separate save or undo path. When the secondary-click
lands inside a Todo text column, insert-before and delete-column actions should
target that clicked column, matching PaperTodo's per-column context menu. The
clicked Todo text column should be focused before the menu opens so pending
edits in the previously focused column are committed through the same focus-loss
path as ordinary text navigation, and focus should return to that clicked column
when the menu closes without launching another dialog.
Absolute due labels without an explicit year should follow PaperTodo's compact
time-aware display: today is `HH:mm`, tomorrow is `Tomorrow HH:mm`, and other
dates keep month-day plus `HH:mm`.
Relative due labels should use PaperTodo's duration model rather than coarse
day names: round the absolute distance up to at least one minute, combine day,
hour, and minute units such as `2h5m`, then show `in {duration}` for future
items and `{duration} overdue` for past items. Todo rows keep one compact due
status at the far right: relative time is the emphasized first line when
enabled, absolute time remains the second line, and the same area edits or
clears the due date. The reminder timer should also refresh due rows even when no
reminder bubble is shown, so visible countdown text does not go stale.
Todo ordering should preserve PaperTodo's reorder data semantics: item moves
must push a todo undo snapshot, keep the moved item focused, normalize item
orders after every move, and expose a visible drag handle for pointer reordering
with move-up/move-down actions as a precise fallback. Dropping a dragged row on
the upper or lower half of another row should insert before or after that row
respectively, matching PaperTodo's boundary-based drag placement.
Dragging a Todo row handle onto the bottom delete area should follow the same
delete path as the explicit delete action, so PaperTodo tombstones, fallback
row creation, focus recovery, snackbar undo, and sync-safe save behavior stay
identical.
Deleting an individual Todo item should preserve PaperTodo's `RemoveItem`
semantics: the delete action remains available for the last remaining row,
deleting that row creates a blank fallback row, deleted-item tombstones are
recorded, focus moves to the fallback or neighboring row, and snackbar undo
removes any temporary fallback before restoring the original item.
Clearing completed Todo items should preserve PaperTodo's batch-delete
semantics: no-op when nothing is done, push one todo undo snapshot, remove every
completed row, create a blank fallback row when all rows were completed, record
deleted-item tombstones, and focus the previous focused survivor or first
nonblank remaining row.
Todo-note linking should preserve PaperTodo's item-link semantics: linking to
an existing different note pushes one todo undo snapshot, linking the same note
again is a no-op, unlinking is a no-op when no note is linked, unlink actions
remain available from Todo item menus, and link or unlink operations should
restore focus to the affected row where possible. Opening a linked note should
use the source Todo paper as an anchor: expand and show the note, place it on
the right side when the work area allows it, fall back to the left side near a
screen edge, then clamp it inside the work area like PaperTodo.
Note-to-Todo drag linking should preserve PaperTodo's drop model: note papers
expose a dedicated link drag handle, Todo rows accept only existing note IDs,
candidate rows highlight while hovered, and dropping a note onto a Todo row uses
the same undoable link path as menu linking.
Markdown note editing on narrow screens should keep high-frequency formatting
actions such as bold, italic, and link insertion directly reachable, while
secondary block or structural actions such as heading, quote, list, code block,
and strikethrough belong in a compact overflow menu.
Note canvas element geometry should preserve PaperTodo pointer semantics:
dragging the element header moves the block, dragging the bottom-right grip
resizes it, movement is clamped to the visible canvas, resize keeps the minimum
72x48 size, and geometry changes are saved when the gesture finishes. Pinned
desktop note papers should ignore canvas move, resize, and add-block gestures
plus edit, duplicate, layer, delete, and text-edit actions so desktop surface
mode cannot accidentally rearrange note blocks.
Desktop secondary-click on a note canvas block should open a PaperTodo-style
block context menu with one-step layer moves, front/back layer commands,
duplicate, and delete. Geometry editing remains a separate explicit tool button
rather than part of the right-click block menu.
New note canvas blocks should follow PaperTodo placement and layer rules:
only code blocks can be created, they default to 230x116 with
`Console.WriteLine("PaperTodo");`, and legacy text or sticky block types are
normalized to code blocks while preserving their text and geometry. New blocks
use the 28px origin plus a capped 12px cascade clamped to the canvas with a
10px margin, new and duplicated blocks use the current top z-index plus 10,
duplicates offset by 18px on both axes, one-step layer moves swap z-indexes, and
front/back commands assign max+10 or min-10. If imported or manually edited
canvas blocks share duplicate z-indexes, one-step layer moves first renumber
those blocks by current render rank so the requested block visibly moves exactly
one rank.
Note canvas code block editors should accept Tab like the main Markdown note
editor: Tab inserts or indents literal tab characters and Shift+Tab outdents
without moving focus away from the canvas block.
