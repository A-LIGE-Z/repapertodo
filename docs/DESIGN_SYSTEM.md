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
Surface commands that change visibility, desktop pinning, or always-on-top
state should send structured arguments with the `paperId`, while the runner
keeps compatibility with older string and bool arguments. The runner should
cache per-paper bounds from `setBounds` and move/resize events so a bounds query
for a non-active paper does not overwrite that paper with the active window's
geometry. Startup restore and tray menu rebuilds should include paper geometry
so the native surface registry can refresh every paper without moving the
current window. Minimized Windows surfaces must not persist bounds updates,
because Windows can report synthetic minimized coordinates that would corrupt a
paper's saved position.
The Windows tray paper list should expose useful paper state at a glance:
visible papers are checked, while hidden, collapsed, desktop-pinned, and
topmost states are shown in the menu label. Platform close/show/hide events
should refresh the tray menu promptly when they change paper visibility, while
plain move/resize bounds updates should not trigger extra tray rebuilds.
The tray icon should be resilient to Windows Explorer/taskbar restarts by
handling the `TaskbarCreated` broadcast and re-adding the notification icon.
For PaperTodo parity, a `PaperTodo.ico` or `RePaperTodo.ico` file next to the
Windows executable should override the embedded tray icon.
Tray-level Show and Hide commands should be routed as startup commands so they
apply to every paper, not just the active surface.
Tray-level Toggle should use the same startup command path and let Dart decide
whether all papers should be shown or hidden from current visibility state.
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
Global hotkey settings are entered as text for now, so the Windows runner
should accept forgiving key aliases: spaced names such as `Page Up`, arrow-key
names, lock keys, number-pad names, and common punctuation names such as
`Plus`, `Minus`, and `Slash`.
Hotkey settings should strip control characters before saving or platform
registration while preserving ordinary spaces used by aliases.

## Android Priority

Android may use a mobile-native navigation model, but the data concepts must remain identical: papers, todo items, notes, linked notes, settings, sync, and conflict recovery.
Desktop-only settings such as start-at-login, task-switcher visibility,
fullscreen/topmost policy, global hotkeys, and PowerShell script capsules
should be hidden on Android unless the platform layer exposes a real
implementation.
External Markdown exports should be written under the platform documents area
so Windows keeps portable files near the executable and Android FileProvider can
grant temporary read access to other apps.
Generated external Markdown export filenames must replace platform-reserved
characters and raw control characters, including DEL, before file creation.
External Markdown extension settings must reject platform-reserved characters
and raw control characters, including DEL, before saving.
External launches, Markdown links, and script capsules should report platform
failures in the app instead of failing silently.
Script capsule hosts must reject blank scripts and unsupported execution
engines before invoking native launch paths.
Platform URI and external-file hosts must trim and reject blank launch
arguments before invoking native method channels. Platform URI hosts must also
reject raw or percent-encoded control characters.
Platform external-file paths must reject raw control characters while preserving
ordinary spaces in local filenames.
Markdown links must reject raw or percent-encoded control characters and
encoded authority separators before native URI launch while preserving ordinary
encoded path characters.
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
Markdown note editing on narrow screens should keep high-frequency formatting
actions such as bold, italic, and link insertion directly reachable, while
secondary block or structural actions such as heading, quote, list, code block,
and strikethrough belong in a compact overflow menu.
