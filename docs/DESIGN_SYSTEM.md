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
- Respect reduced motion.
- Avoid emoji as structural icons.
- Make compact desktop UI and touch-friendly Android UI from the same design language, not the same exact density.

## Windows Priority

Windows is not a scaled-up mobile app. The first Windows milestone must feel like independent desktop papers, not a single Flutter dashboard pretending to contain papers.

The Windows platform channel should treat each paper as an addressable surface.
Window and tray events may include a `paperId` so Dart can route bounds,
show/hide, close, and open requests to the correct `PaperData` even while the
current runner still hosts one Flutter window. The native runner should
preserve that `paperId` in follow-up window events after Dart sends it through
show, hide, bounds, or tray commands.
Events that explicitly name an unknown `paperId` should be ignored instead of
falling back to the active paper, while legacy events without a `paperId` may
still target the active paper for backward compatibility.
Registry refreshes from restore or tray rebuild should prune paper IDs that are
no longer present in the current state so late native events from deleted or
replaced papers are ignored.
Surface commands that change visibility, desktop pinning, or always-on-top
state should send structured arguments with the `paperId`, while the runner
keeps compatibility with older string and bool arguments. The runner should
also accept structured window title updates with both `paperId` and `title`,
while keeping the older string title argument as a fallback. The runner should
cache per-paper bounds from `setBounds` and move/resize events so a bounds query
for a non-active paper does not overwrite that paper with the active window's
geometry. Startup restore and tray menu rebuilds should include paper geometry
so the native surface registry can refresh every paper without moving the
current window. Minimized Windows surfaces must not persist bounds updates,
because Windows can report synthetic minimized coordinates that would corrupt a
paper's saved position.
Normal startup should restore every non-deleted paper as visible for the
current session, matching PaperTodo's model where closing or hiding a paper
does not make it feel lost on the next launch. Explicit startup exit commands
must not perform this visibility restore.
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
Startup command parsing should be forgiving for command-line and second-instance
use: skip unknown arguments, accept hyphen/underscore/space variants, and keep
aliases such as `new todo`, `new_note`, `add-note`, `close`, `prefs`, and
`quit`. The Windows secondary-process forwarder should canonicalize these
aliases before writing to the primary-instance pipe so Dart receives the same
stable command strings as tray actions.
Always-on-top papers should be refreshed against the foreground fullscreen
state after startup and while the app is running. In the default avoid mode, a
topmost paper should temporarily leave the topmost band while another
application owns a fullscreen foreground window, then return to topmost after
that fullscreen window is gone. Desktop-pinned papers stay at the bottom and do
not participate in topmost recovery.
Fullscreen detection should match PaperTodo's defensive Windows behavior:
prefer DWM extended frame bounds, tolerate small border differences, ignore
tool, cloaked, shell, hidden, minimized, and current-process windows, and scan
foreground-process top-level windows when the foreground handle itself is not
the fullscreen surface.
Global hotkey settings are entered as text for now, so the Windows runner
should accept forgiving key aliases: spaced names such as `Page Up`, arrow-key
names, lock keys, number-pad names, and common punctuation names such as
`Plus`, `Minus`, and `Slash`.
Global hotkey registration should follow PaperTodo's safety model: a valid
hotkey must include at least one real modifier (`Ctrl`, `Alt`, `Shift`, or
`Win`) plus one non-modifier key, so single-key global shortcuts are ignored
instead of stealing normal typing.
Pinned paper hotkeys should follow PaperTodo's reveal model: the Todo and Note
hotkeys reveal the first visible desktop-pinned paper of the matching type and
do not create new papers when no matching pinned surface exists.
Hotkey settings should strip control characters before saving or platform
registration while preserving ordinary spaces used by aliases.
For PaperTodo font parity, when no explicit system font family is configured,
the app should try to load `papertodo.ttf` and then `papertodo.otf` from the
Windows executable directory before falling back to built-in font presets.
Missing, invalid, or unsupported runtime font files must not block startup.
Original PaperTodo font preset migration must preserve `yahei` and `dengxian`
instead of silently normalizing them to the default preset.
Paper title editing should preserve PaperTodo's hard title rules: the editor
accepts no more than 40 text elements, control characters are removed before
the title is stored, blank titles display the default paper title, and Windows
surface and tray titles use the same cleaned value.

## Android Priority

Android may use a mobile-native navigation model, but the data concepts must remain identical: papers, todo items, notes, linked notes, settings, sync, and conflict recovery.
Desktop-only settings such as start-at-login, task-switcher visibility,
fullscreen/topmost policy, global hotkeys, and PowerShell script capsules
should be hidden on Android unless the platform layer exposes a real
implementation.
External Markdown exports should be written under the platform documents area
so Windows keeps portable files near the executable and Android FileProvider can
grant temporary read access to other apps. Android FileProvider paths should
also include accessible external storage so validated `/storage/...` Markdown
links can be handed to the user's preferred editor or viewer.
Generated external Markdown export filenames must replace platform-reserved
characters and raw control characters, including DEL and C1 controls, before
file creation. External Markdown extension settings must reject
platform-reserved characters and raw control characters, including DEL and C1
controls, before saving.
External launches, Markdown links, and script capsules should report platform
failures in the app instead of failing silently.
Script capsule hosts must reject blank scripts and unsupported execution
engines before invoking native launch paths.
Collapsed note papers whose content starts with a PaperTodo script capsule
marker should behave as script capsules: primary click runs the script without
expanding the note, while secondary click opens the note for editing.
Script capsule parsing should preserve PaperTodo marker and indentation rules:
recognized markers are read only from the first line, shared indentation is
removed from the script body, and the platform line terminator is used before
the normalized script body is handed to the host.
Platform URI and external-file hosts must trim and reject blank launch
arguments before invoking native method channels. Platform URI hosts must also
reject raw or percent-encoded control characters.
Platform external-file paths must reject raw control characters while preserving
ordinary spaces in local filenames.
Markdown links must reject raw or percent-encoded control characters and
encoded authority separators before native URI launch while preserving ordinary
encoded path characters.
Markdown note link interaction should preserve PaperTodo edit/preview
semantics: preview-mode links open directly, while edit-mode source links open
only on Ctrl+click and otherwise keep normal text editing behavior. This applies
to Markdown links and the supported single-line inline HTML `a href` links.
Inline HTML anchor parsing should follow PaperTodo's small parser: attributes
must be well-formed `name=value` pairs, quoted values must close, unquoted href
values are allowed, and empty anchor bodies are not link hit targets.
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
Markdown link hit-testing should skip links inside closed inline code spans,
matching PaperTodo's source editor highlighting and Ctrl+click behavior.
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
continuation cannot drift apart.
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
Markdown editors should accept Tab as content like PaperTodo's AvalonEdit
notes: Tab inserts or indents with literal tab characters, Shift+Tab outdents
one leading tab or up to four leading spaces, and focus should not leave the
note editor because of these keys.
Note paper text zoom should preserve PaperTodo's mouse path: Ctrl+mouse-wheel
adjusts the note `TextZoom` in 0.1 steps between 0.5 and 1.5, updates the
surface immediately, and consumes the wheel signal instead of scrolling the
paper body.
Settings saves should keep ordinary app preferences while surfacing native
integration failures such as hotkey, startup, or script-process errors.
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
Todo keyboard editing should follow PaperTodo: Enter with no modifiers inserts
an empty item directly after the focused item and moves focus there. Backspace
on an item whose main and extra text columns are blank deletes that item when
more than one item exists, preserves at least one row, and suppresses repeated
blank-row deletion until key up. These structural edits must use todo undo
snapshots and deleted-item tombstones.
New Todo rows created by Enter, the append affordance, or multiline paste
should follow PaperTodo's `AddItemAfter` semantics: the active row keeps its
existing columns, while newly inserted rows start as default single-column
items instead of inheriting the source row's column layout.
Multiline Todo paste should be available from every Todo text column, not only
the main column. The first cleaned line replaces the focused column text, and
subsequent cleaned lines create default single-column Todo rows after the
active row.
Todo text editing should follow PaperTodo's undo snapshot timing: focusing a
main todo text field records its original text, losing focus after a change
pushes that pre-edit item snapshot, and structural edits first commit any
focused text edit before pushing their own undo snapshot. Ctrl+Z/Y inside a
text field with uncommitted edits should be left to the text editor.
Todo column editing should preserve PaperTodo per-column semantics: inserting
before column 1 moves the current main text into the first extra column and
creates a blank main column, while deleting column 1 promotes the next column
into the main text. Inserting or deleting later columns should keep the other
columns in order and preserve normalized per-column widths.
Todo column width resizing should preserve PaperTodo splitter semantics: wide
multi-column rows show an 8px drag target between adjacent columns, dragging
resizes only that column pair, each column width is clamped to at least 0.2,
and the normalized widths are saved without creating a todo undo snapshot.
Todo due editing should preserve PaperTodo date-and-time precision: the picker
must expose a calendar date plus 00-23 hour and 00-59 minute choices, default a
new due time to roughly one hour from now, and save local values as
`yyyy-MM-ddTHH:mm:ss` without milliseconds.
Clicking an existing Todo due chip should reopen the due editor just like
PaperTodo's due badge.
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
Absolute due labels without an explicit year should follow PaperTodo's compact
time-aware display: today is `HH:mm`, tomorrow is `Tomorrow HH:mm`, and other
dates keep month-day plus `HH:mm`.
Relative due labels should use PaperTodo's duration model rather than coarse
day names: round the absolute distance up to at least one minute, combine day,
hour, and minute units such as `2h5m`, then show `in {duration}` for future
items and `{duration} overdue` for past items. When relative due labels are
enabled, the reminder timer should also refresh due rows even when no reminder
bubble is shown, so visible countdown text does not go stale.
Todo ordering should preserve PaperTodo's reorder data semantics: item moves
must push a todo undo snapshot, keep the moved item focused, normalize item
orders after every move, and expose a visible drag handle for pointer reordering
with move-up/move-down actions as a precise fallback.
Clearing completed Todo items should preserve PaperTodo's batch-delete
semantics: no-op when nothing is done, push one todo undo snapshot, remove every
completed row, create a blank fallback row when all rows were completed, record
deleted-item tombstones, and focus the previous focused survivor or first
nonblank remaining row.
Todo-note linking should preserve PaperTodo's item-link semantics: linking to
an existing different note pushes one todo undo snapshot, linking the same note
again is a no-op, unlinking is a no-op when no note is linked, unlink actions
remain available from Todo item menus, and link or unlink operations should
restore focus to the affected row where possible.
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
New note canvas blocks should follow PaperTodo placement and layer rules:
code blocks default to 230x116 with `Console.WriteLine("PaperTodo");`, new
blocks use the 28px origin plus a capped 12px cascade clamped to the canvas with
a 10px margin, new and duplicated blocks use the current top z-index plus 10,
duplicates offset by 18px on both axes, one-step layer moves swap z-indexes, and
front/back commands assign max+10 or min-10.
Note canvas text and code block editors should accept Tab like the main
Markdown note editor: Tab inserts or indents literal tab characters and
Shift+Tab outdents without moving focus away from the canvas block.
