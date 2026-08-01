# PaperTodo UI parity audit

Authoritative reference: `D:\AI\PaperToDo\PaperTodo-original`.

The audit compares visible structure, dimensions, colors and interaction
feedback. Functional compatibility alone does not mark a section complete.

Latest native-dialog calibration separates the antialiased paper shell from
the ordinary interactive dialog HWND. The lower non-activating layered window
retains the source-fitted 12.75px coverage and one-pixel border, while the
upper inset-region window owns every edit, date, combo and owner-drawn button.
This removes the single-layered-HWND failure where a correct-looking dialog
passed mouse input through to the Flutter paper. Real pointer runs now open
both native dropdowns, close through Cancel, destroy the paired shell, and
leave `data.json` byte-for-byte unchanged.
The same milestone replaces the remaining explanatory-message GDI ClearType
path with grayscale DirectWrite Natural rendering. Both messages use the
source +1px paint origin; wrapped reminder text adds one physical row to the
measured DirectWrite line advance, matching the WPF 16px rhythm without
manual double painting. The due message crop reaches 1.0773 MAE and its
interactive interior reaches 0.4688. The reminder message reaches 1.1500 MAE
(first/second lines 2.0001/0.5586), and its interactive interior reaches
0.5329. The separate shell retains the previously verified four-corner
coverage. Evidence is stored in
`.tmp/repapertodo-due-dialog-production-final.png.screen.png`,
`.tmp/repapertodo-reminder-dialog-production-final.png.screen.png`, and their
`.shell.png` companions.

Latest native-picker calibration: the due-time hour/minute and reminder-unit
selectors reproduce the WPF 240-to-229 light gradient. The reminder selector
uses a 23px control inside a 27px cover surface so the backing Win32 ComboBox
cannot leak its lower shadow. The due DatePicker now separates its WPF white
editor strip and `#99C9EE` selection from the surrounding paper/calendar
surface, with an exact `#D5C8B0` frame and calibrated text baseline. Same-state
due-dialog MAE is 2.6948 (date region 5.5108; previously 15.3369), while the
reminder-dialog selector crop remains 3.2398 MAE.
The native selector glyph is now the source-captured antialiased 5x5 WPF
chevron rather than a GDI-filled triangle. Date hour/minute and reminder-unit
surfaces share one DPI-scaled coverage painter, with the 96-DPI light glyph
using the source `#606060` foreground. Fresh `PrintWindow` captures lower the
due/reminder arrow crops from 11.8258/11.9773 to 0.0682/0.2273 MAE, their
complete selector crops from 2.4537/3.3899 to 1.7305/2.8077, and the complete
dialogs from 1.8152/1.9313 to 1.7789/1.9138. Evidence is stored in
`.tmp/repapertodo-due-dialog-chevron-mask.png` and
`.tmp/repapertodo-reminder-dialog-chevron-mask.png`.
The light selector gradients then use separate source-captured 29px and 23px
row maps instead of one rounded integer interpolation. This makes both arrow
crops pixel exact (`0.0000` MAE), lowers the due hour selector from 1.7305 to
1.6014 and the reminder unit selector from 2.8077 to 2.7102, and moves the
complete dialogs to 1.7725/1.8877. Evidence is stored in
`.tmp/repapertodo-due-dialog-gradient-exact.png` and
`.tmp/repapertodo-reminder-dialog-gradient-exact.png`.
An intermediate reminder-title pass used the same transparent-window
grayscale GDI path as the due title; its broad crop moved from 21.7996 to
21.6257 without changing font family, size, weight or layout. That path was
later superseded by the DirectWrite calibration above. An intermediate
single-HWND layered prototype then reproduced the WPF edge coverage: the
average four-corner crop fell from 5.2256 to 1.7194 MAE, the top-left crop to
1.6767, the complete due dialog from 1.7759 to 1.7125, and the complete
reminder dialog from 1.8873 to 1.8351. Later real hit testing proved that this
arrangement made the visible native children pointer-transparent on the
active desktop. Production therefore retains its calibrated coverage painter
only in the separate shell described above. Prototype evidence remains in
`.tmp/repapertodo-due-dialog-layered-tuned.png` and
`.tmp/repapertodo-reminder-dialog-layered-tuned.png`.
Native action buttons independently use grayscale antialiasing like WPF's
paper-surface text. A fresh same-data `PrintWindow` pair first moved the due
dialog's semibold title to grayscale antialiasing, lowering its title crop
from 26.0142 to 24.4212 MAE and the complete 354x242 dialog from 1.8687 to
1.8152. Messages, numeric fields and selectors keep their better-matching
ClearType path. Due/reminder button crops reach 6.1512
and 8.0322 MAE, reducing the complete dialogs to 2.6072 and 3.4282.
Both action-label paint boxes then receive the shared WPF +1px vertical
origin, reducing the due/reminder button crops further to 3.4323 and 3.6890
MAE and the complete dialogs to 2.2212 and 2.9748. A wider-tracking experiment
regressed both captures and is not retained.
The earlier filled-triangle selector experiment was superseded by the exact
antialiased WPF coverage painter documented above. Title-height/width
compensation experiments were rejected by both captures and are not retained.
The light DatePicker calendar button uses the authoritative 20x18 WPF raster
compiled into the runner and DPI-scaled at paint time; dark mode keeps its
dynamic palette-derived drawing. The 96-DPI calendar crop is pixel exact
(0.0000 MAE), lowering the date region from 5.5108 to 2.9215 and the complete
due dialog from 2.2085 to 2.0371.
The due hour/minute labels independently use a -3px WPF paint origin and 1px
two-digit spacing compensation; the reminder unit keeps its existing origin.
Hour/minute crops reach 3.8339/2.9060 MAE and the complete due dialog reaches
1.9023.
The reminder-unit label independently moves right 1px and uses grayscale WPF
antialiasing, while the due numeric controls remain on their calibrated
ClearType path. Its label/selector crops reach 9.0008/2.6616 MAE and the full
reminder dialog reaches 2.9293.
The reminder message now paints its already-aligned first line and later lines
through separate clip layers, moving only subsequent lines up 1px to match
WPF line advance. The second-line crop falls from 13.5369 to 1.9833 and the
complete reminder dialog reaches 2.0809 without changing wrapping width.
The custom-theme current-value label has an independent -1px WPF paint origin,
matching the reference `x=248..335` bounds without moving the pixel-exact
swatch or actions. Its crop falls from 35.7512 to 25.8897 MAE and the Display
page reaches 1.5502. SemiBold and Bold rasterized identically for the fallback
font, so the source-semantic SemiBold weight remains.
The custom-theme primary action label independently uses a 12/11 vertical
paint scale and -0.5px origin while its 76x27 layout/hit target stays fixed.
Its crop falls from 10.9637 to 5.9010 MAE and the Display page reaches 1.5252.
The secondary-action scaling experiment regressed and was fully reverted.
The custom-theme field label now uses the source 11px field hierarchy rather
than the generic 12px Material label, plus the smallest raster-effective
-0.01px tracking adjustment. Its crop falls from 16.0691 to 8.0330 MAE and the
controlled Display page reaches 1.4717.
The system-font field label independently uses the smallest raster-effective
-0.005px tracking correction while its help glyph stays fixed. Its crop falls
from 4.4403 to 3.1799 MAE and the Display page reaches 1.4630. The attempted
12.5px secondary theme-action font regressed and was reverted.
The installed-font field originally used `TextAlignVertical(y: -0.4)` for the
implicit Skia fallback. After the explicit PaperTodo CJK fallback was restored,
the same value left the new glyph run one raster row high; `y: -0.2` keeps the
frame and exact chevron fixed while aligning the actual WPF-family text.
Horizontal-padding compensation remains rejected.
The mixed Latin/CJK Markdown field label independently uses -0.02px tracking
and a +1px WPF paint origin while its help glyph and selector stay fixed. Its
crop falls from 7.0405 to 3.6146 MAE and the Display page reaches 1.4283.
The fullscreen-handling field label independently uses the smallest
raster-effective -0.003px tracking correction while its help glyph and
selector stay fixed. Its crop reaches 6.0720 MAE and the Display page 1.4210.
The Todo-size field label independently uses the smallest raster-effective
-0.001px tracking correction while its help glyph and selector stay fixed.
Its crop reaches 2.3097 MAE and the Display page 1.4177.
Todo-spacing and Note-spacing labels share the smallest raster-effective
-0.001px tracking correction while their help glyphs and editors stay fixed.
Their crops reach 2.9437/3.4830 MAE and the Display page 1.4087. A half-pixel
Note-label origin experiment produced no raster change and was removed.
The author signature's paint layer independently uses a right-anchored 99/103
horizontal scale while its hit target and Segoe UI style stay fixed. Its
visible bounds match `x=675..773`, its crop reaches 5.2134 MAE and the Display
page reaches 1.3860. Reset-button expansion experiments remain rejected.
The reminder value editor now keeps its real Win32 input behavior behind an
exact 23px `#569DE5` WPF focus frame and uses a light-only `#95C1DC` painter
when the initial value is fully selected. Its focused crop falls from 13.1998
MAE to 1.2424 and the complete reminder dialog from 4.4226 to 3.5510.

Latest settings calibration: the 58x42 custom-theme swatch uses hard square
clipping rather than anti-aliased corners. Its reference crop is pixel exact
(0.0000 MAE), and the full Display settings capture falls from 2.4208 to
2.2797. The top-bar button settings now use PaperTodo's exact Chinese and
English wording plus a local WPF text-origin/tracking correction; their label
crop falls from 14.4809 to 10.9107 and the full Display capture to 2.2248.
The settings scrollbar restores the source `#B39B74`/`#96784F` resources and
9px/3px margins, matching `x=768..772, y=61..626`; its crop falls from
15.7650 to 0.0056 and the controlled full-page capture to 1.9782. The same
fixed WPF colors now apply to paper scrollbars, including long notes.
The original navigation group uses the WPF +1px/-1px paint origin: the active
Display row matches `x=17..150, y=59..92`. Its 55%-opacity paper-border
separator matches all 615 reference pixels at `x=163, y=59..673`, reducing
that crop to 0.0000 MAE. The extra WebDAV row remains an intentional product
extension, is separated from the four source categories by a low-contrast
paper-tint rule, and is excluded from original-navigation parity measurements.
The content right inset is 13px, placing selectors, fields, buttons and help
glyphs on the reference `x=762` edge. The custom-theme label uses a local +2px
WPF origin so its help glyph matches `x=749..758, y=163..172` while its swatch
stays pixel exact. Display-page MAE reaches 1.7179; the same width correction
improves Capsules from 1.8532 to 1.7370 and General from 3.1091 to 2.9321.
The settings shell now uses the source 16/14/16/16 padding as one outer inset
rather than an 8+8 right split. The title and close glyph retain their source
hit targets but use independent WPF paint origins; title MAE falls from
6.8778 to 2.2874, close-region MAE from 1.2506 to 0.6608 and the full header
from 1.5974 to 0.5486.
Checked settings boxes preserve the source 16x16 host and unchecked border,
but snap their active background to WPF's inner 12x12 bounds
`x=182..193, y=96..107`; the check path and pointer target do not move. This
lowers Todo/Notes settings MAE from 2.2063 to 2.1921, General from 2.9321 to
2.8232 and Capsules from 1.7370 to 1.6342.
After the explicit Windows UI fallback changed the active glyph bearings,
settings checkbox titles use a shared +0.5px WPF paint origin independently
of their marks and 8px layout gap. The first enabled Todo/Notes, Capsules and
General labels now share the reference `x=204` origin and unchanged vertical
bounds. From the immediately preceding four-page capture, their full source
bodies fall from 2.0839/0.7508/2.9311 to 1.6752/0.4862/2.6156 MAE, while the
focused first-label crops fall from 4.3117/2.0007/2.5000 to
2.4003/1.7040/1.7945. Display remains pixel-for-pixel unchanged at 0.8365
because its already-calibrated top-bar labels apply the inverse local
compensation. Evidence is stored as
`.tmp/repapertodo-settings-page-checkbox-v4-{display,todo,capsules,general}.png`.
Settings group headings and field labels independently use a
-0.5px/+0.5px WPF paint origin; their help glyphs and controls remain fixed.
Todo/Notes page MAE reaches 2.0025, Display 1.6017, General 2.6297 and
Capsules 1.5623. Capture-rejected capsule glyph experiments are not retained.
Settings font and compact dropdowns use a dedicated filled WPF chevron rather
than Material's smaller icon. The visible glyph matches
`x=743..752, y=282..286`; arrow-crop MAE falls from 22.3690 to 1.3492 and the
font-dropdown crop from 2.6160 to 0.4362 without changing layout or hit area.
The desktop settings shell now uses a capture-equivalent 14px title/content
gap to account for Flutter's border not consuming layout space. The navigation
and divider use `Offset(1, -2)` paint layers; a fresh 792x720 `PrintWindow`
comparison reduces the common navigation crop from 4.6757 to 3.9273 and the
right-hand display body from 5.3762 to 1.4347 MAE. The custom-theme row fixes
its source 76x27 and 82x27 action widths instead of allowing the clear action to
grow into a second full-width run; compared with the pre-fix capture, the
display body falls from 17.2734 to 5.3762 MAE and the system-font crop from
10.6349 to 5.1609. The remaining WebDAV row and draft Confirm/Cancel footer are
intentional RePaperTodo extensions and are excluded from source-only crops.
Navigation, segment, text-field, dropdown, compact-action, color-swatch and
secret-button pointer states now switch at the source mouse frame without
pressed scaling or old/new icon overlap. Category selection also occurs on
mouse-down and resets the replacement page directly to its scroll origin.
The same interaction refactor preserves the capture-calibrated static WPF
metrics: title, navigation, divider, field and checkbox-label origins; custom
theme and top-bar-label tracking; the inner 12x12 checked fill; close-glyph
origin; and the right-anchored author-signature scale. These values must not be
normalized to zero merely because the pointer feedback is immediate.

Current-build verification (2026-07-30): the Windows Release executable was
rebuilt and its 792x720 settings coordinator was captured through
`PrintWindow` using the same light/default state as the PaperTodo reference.
With the explicit UI fallback and re-calibrated installed-font baseline, the
measured regions are: header 0.4133 MAE, common navigation 2.8745, theme
selector 1.1859, custom-theme row 5.1507, system-font row 0.8027, and the
complete right-hand Display body 0.9710 MAE. The preceding capture measured
0.5231/3.9273/2.2863/7.2175/1.3199/1.4347 respectively.
The custom-theme actions remain fixed at 76x27 and 82x27; the extra WebDAV
category and draft Confirm/Cancel footer are intentional RePaperTodo additions
and are excluded from source-only metrics. The captured artifact is
`.tmp/repapertodo-settings-ui-fallback-font-baseline.png`.

The follow-up custom-theme calibration restores the source WeakText color for
the field heading and keeps the source 12.5px SemiBold current-value label at
its zero WPF origin with a local -0.05px Display tracking correction. The
Default-color action uses a local 12px Medium/-0.125px correction while its
82x27 surface and hit target remain fixed. Tight heading/current/action crops
fall from 14.5438/13.8878/14.8683 to 6.6335/5.3600/7.7987 MAE. The complete
custom-theme row falls from 5.1507 to 2.7197 and the right-hand Display body
from 0.9710 to 0.8365. Evidence is stored as
`.tmp/repapertodo-settings-ui-custom-theme-metrics-v5.png` and
`.tmp/settings-custom-theme-metrics-v5-x4.png`.

The settings coordinator's parent `WM_NCHITTEST` already returned the correct
edge codes, but real pointer input landed on the full-size Flutter child HWND
and never entered USER32's sizing loop. Windows-only Flutter edge/corner
listeners now forward all eight resize directions through
`startSettingsResize` and `WM_NCLBUTTONDOWN`, without adding visible frame
chrome or changing Android hit testing. The rebuilt Release passed the full
Windows policy smoke with `settingsWindowMovable=true` and
`settingsWindowResizable=true`; the retained evidence is
`.tmp/windows-policy-smoke-settings-resize-fixed-rerun.json`. Current Windows
11/96-DPI hit targets are therefore verified; Windows 10 and mixed-DPI shadow
softness remain the settings-specific visual follow-up.

The settings compact Clear/Default actions and the custom-theme Pick/Clear
pair now retain the WPF button template's hard rectangular corners instead of
inheriting Flutter's generic 8px pill radius. Their dimensions, pointer colors,
press opacity and hit targets are unchanged. In a fresh 792x720 Display capture,
the complete custom-theme region falls from 7.2175 to 6.8030 MAE and the focused
166x27 action strip from 12.1621 to 10.2663. The same correction lowers the two
General-page hotkey Clear-action crop from 4.9501 to 4.5978. Evidence is stored
as `.tmp/repapertodo-settings-square-actions-light.png` and
`.tmp/repapertodo-settings-general-square-actions.png`.

After the explicit Chinese UI fallback was enabled, a fresh four-state audit
showed that the older per-string translations were compensating for obsolete
glyph origins. Display, Todo / Notes, Capsules and General / Advanced now all
use the source zero paint origin. Todo / Notes and General / Advanced use a
local -0.05px tracking correction; Capsules applies the same correction only
while selected. Across selected/inactive states, the focused label crops now
reach 0.6350/0.3572 MAE for Display, 2.0482/1.2778 for Todo / Notes,
1.0719/0.6628 for Capsules and 2.1640/1.4351 for General / Advanced. The
Display common navigation crop falls from 2.8745 to 0.5874, with every row and
shift search at `(0, 0)`. Stable per-category metric keys, a four-page Widget
test and project-rule checks keep these paint-only metrics independent of row
layout and hit targets. Evidence is stored as
`.tmp/papertodo-reference-settings-page-{display,todo,capsules,general}.png`
and `.tmp/repapertodo-settings-page-navigation-v2-{display,todo,capsules,general}.png`.

The next Todo/Notes page audit moved the RePaperTodo-only
`moveCompletedTodosToBottom` toggle below the source PaperTodo due, reminder
and linked-note controls. A fresh reference/current pair shows the
source-calibrated regions improve to 3.2388 MAE for the upper Todo block,
1.6050 for the reminder controls and 3.0979 for the linked-note block; the
previous upper/reminder values were 11.4704/25.4958 because the extension row
was inserted before the source controls. The extension remains available after
scrolling and retains its existing state/save behavior.

The reminder-mode toggle sits after a fractional label/segment stack. Its
layout box and every following 28px control already matched the source rows,
but Flutter rounded only that toggle's painted checkbox, title and help glyph
one pixel upward. A paint-only +1px correction with unchanged hit testing keeps
all later controls on their verified rows. The focused reminder-title crop
falls from 22.5456 to 5.3197 MAE, its best shift returns from `(0, +1)` to
`(0, 0)`, and the full Todo/Notes source body falls from 1.6752 to 1.4067.
The rejected 1px layout-gap experiment is not retained because it moved every
subsequent source-aligned control. Evidence is stored as
`.tmp/repapertodo-settings-page-reminder-paint-v6-todo.png` and
`.tmp/settings-todo-upper-reminder-paint-v6-x4.png`.

The Chinese Todo due-year field label uses a local -0.125px tracking correction
and +1px WPF paint origin; the neighboring help glyph and three-way selector do
not move. Its focused crop falls from 8.1848 to 3.0387 MAE, the shift search
returns to `(0, 0)`, and the full Todo/Notes source body falls from 1.4067 to
1.3581. English keeps the natural Segoe UI tracking. Evidence is stored as
`.tmp/repapertodo-settings-page-due-label-v11-todo.png`.

The Chinese Todo/Notes page heading now has its own -0.125px tracking and +1px
WPF paint-origin correction instead of changing the shared group-heading
style. Its visible bounds match the source exactly at `x=180..239,
y=74..84`; the controlled 84x24 heading crop falls from 7.1215 to 2.8151 MAE,
the best shift remains `(0, 0)`, and the complete source Todo/Notes body falls
from 1.3581 to 1.3347. English retains natural tracking. Hash comparison proves
that Display, Capsules and General captures are byte-for-byte unchanged.
Evidence is stored as
`.tmp/repapertodo-settings-page-todo-heading-final-v17-{display,todo,capsules,general}.png`.

The same-state Capsules page is already positionally stable: its toggle block,
title-length stepper and full source body measure 3.0220/1.4204/2.4847 MAE,
and every shift search retains `(0, 0)`. No speculative layout adjustment is
applied there. On General, the script-capsule group had a consistent one-pixel
lower paint origin than PaperTodo. A paint-only `Offset(0, -1)` keeps layout
and hit targets unchanged while reducing the script region from 5.3389 to
4.3538 MAE and the complete source-only General body from 2.9453 to 2.7205;
the new best shift is `(0, 0)`. The data-directory editor remains an intentional
RePaperTodo extension below the source sections.

A later per-row raster audit found that the first two script-capsule titles
still rounded one pixel below PaperTodo while the heading, third title,
checkboxes and help targets were already correctly placed. Those two text
paint layers now receive a local `Offset(0, -1)` without moving row layout or
hit testing. Their focused crops fall from 12.1487/11.4784 to 2.7782/3.3521
MAE, the complete script source block falls from 4.4889 to 1.9901, and the
same-state General body falls from 2.6156 to 2.2328. Display, Todo/Notes and
Capsules remain byte-for-byte unchanged. Evidence is stored as
`.tmp/repapertodo-settings-page-script-title-v18-{display,todo,capsules,general}.png`
and `.tmp/settings-general-script-title-v18-x4.png`.

The General external-open block now keeps each WPF raster correction local.
Its group heading moves up one paint pixel, reducing that crop from 6.7984 to
2.5863 MAE. The Chinese extension label uses -0.125px tracking with a +1px
origin, matching the source `x=180..267` bounds and reducing its crop from
2.4298 to 1.2069. The `.md` editor retains the same 28px field and focus area,
but uses source-matched 10/8/8/0 content padding; its visible text bounds now
match `x=191..211, y=373..382`, the tight crop falls from 17.3327 to 4.5130,
and the complete field falls from 1.0022 to 0.2994. The same-state General body
falls from 2.2328 to 2.1228 while Display, Todo/Notes and Capsules remain
byte-for-byte unchanged. Evidence is stored as
`.tmp/repapertodo-settings-page-external-value-v23-{display,todo,capsules,general}.png`
and `.tmp/settings-general-external-v23-x4.png`.

The Note status and outer-canvas dividers now use WPF-rounded opaque
precomposition of the shared 28/34 Tint resource. This prevents Flutter from
darkening translucent borders over their own tinted fills while retaining the
same source theme semantics.
The Display page's top-bar-button labels now share the reference
`x=205..306` visible bounds after a local 1px origin and tracking correction.
Their focused crop falls from 20.2553 MAE to 19.1200 and the controlled page
from 1.5987 to 1.5923 without moving check marks or help targets.
Windows UI chrome again uses PaperTodo's platform Segoe UI chain instead of the
wider YaHei-first content family. A fresh 280x340 warm-light `Todo1` capture no
longer ellipsizes and shares the reference `x=44..71, y=22..29` antialiased
glyph bounds. The source 38px title minimum is represented by a 41px Flutter
host compensation; both static and editable layers retain the same +1/+1 paint
origin so entering title edit cannot move the host content.
The Note status text declares the source 11px Regular metrics explicitly
instead of inheriting Material label weight and tracking. Its source 26px
minimum uses a capture-equivalent 27px Flutter host, while mode, statistics and
zoom use independent WPF paint origins of +1/0, +1/0 and -1/0. Statistics
retain zero source tracking. A later `PrintWindow` comparison showed that the
previous -1px statistics baseline sat one raster row above WPF: restoring its
vertical origin to zero lowers the broad statistics crop from 4.9516 to 2.0132,
the complete status crop from 6.5045 to 4.7727 and the full paper interior from
1.5244 to 1.4087. Mode, H1 and zoom shift searches retain their existing
origins. The mode-pill background resolves the source 32/48 Tint
with WPF floor compositing, moves only its paint layer right 1px and uses a 9px
Flutter radius while its text and hit target remain fixed. Its broad crop falls
from 7.8448 to 7.2479 and the warm-light fill becomes the exact `#E9E0CC`.
SemiBold and Bold produce identical mode-label rasters on the active Segoe UI
fallback, so the source-semantic SemiBold weight remains.
The next same-data Release audit found that default and `yahei` UI chrome still
left Chinese fallback selection entirely to Skia. Latin title pixels remained
correct, but the resulting `预览` and `元素` glyph outlines differed from the
explicit WPF `Segoe UI, Microsoft YaHei UI, Microsoft YaHei` chain. Keeping the
platform primary family while supplying the source CJK/Symbol fallback list
reduces the fixed toolbar/count probe from 0.7030/11.9791 to 0.1534/1.3571 MAE,
the complete status strip from 4.7727 to 3.5669, its mode-text crop from
15.1918 to 7.2053 and its statistics crop from 6.4133 to 1.6687. A separate
same-build English `Todo1` title comparison remains pixel-identical, proving
that the correction changes missing-glyph fallback rather than the calibrated
Segoe UI Latin path. Evidence is stored as
`.tmp/repapertodo-note-status-ui-fallback.png` and the paired 8x crops.
The same controlled Note pair exposes a common Markdown paint-origin drift that
does not belong in document layout. Paint-only compensation moves H1 +2px,
quote +2px/-2px, list rows +3px/-2px and fenced code +2px/-2px relative to the
previous calibrated layers; ordinary paragraph text uses +3px and 0.1px
tracking. The 440x420 full capture falls from 5.5524 to 3.4012 MAE, its paper
interior from 4.7245 to 2.3160 and the focused Note content from 6.9380 to
1.8673. Focused H1/paragraph/quote/list/code crops fall from
6.0673/23.6253/6.3699/11.9600/9.1453 to
2.2977/9.0807/1.1791/1.5109/1.7256. Wrapping and interaction geometry remain
unchanged because every correction is applied after layout.
The Note canvas-toolbar count now declares the original 11px Regular weight and
zero tracking, then uses an independent -1px/-1px WPF paint origin. Its
same-data 64x28 crop falls from 8.3516 to 4.6927 MAE, the complete toolbar from
1.3675 to 0.8843 and the paper interior from 2.3160 to 2.3054 without moving the
right-anchored count slot. The `{}` action independently uses a +1px horizontal
paint origin while retaining its 28x24 layout and hit target; its tight crop
falls from 10.2469 to 2.6811, the broad action crop from 2.7946 to 0.7312 and
the latest complete toolbar from 0.8575 to 0.6823 MAE.
The Note canvas code editor now reproduces WPF's token-boundary wrapping by
adding a display-only `U+200B` opportunity immediately before `(`. Raw/display
selection and composing ranges are mapped in both directions; model updates,
Tab/Shift+Tab formatting, copy/cut/paste and JSON persistence remain marker
free. The final 440x420 Release capture wraps `Console.WriteLine` at the same
boundary as v2.27 and keeps the exact source text bounds. The focused back-text
crop falls from 9.5791 to 5.2811 MAE, while the unaffected front text and both
headers remain at 6.3259/1.1208/2.1900. A scan of all three fixture data files
finds zero marker occurrences. Evidence is stored as
`.tmp/repapertodo-note-canvas-elements-wrap-final-v4.png`; the display-only
model, clipboard, serialization and marker-boundary behavior is covered by
`note canvas WPF wrap opportunities stay display-only`.
The Note-to-Todo `⌖` title action now centers its 13px Symbol glyph inside the
source 24x24 drag slot before applying a -1px/+1px WPF paint correction. This
fixes the previous top-aligned glyph without changing the draggable hit target;
the focused action crop falls from 6.1818 to 2.3411 MAE. A -0.5px `MD` tracking
probe regressed its independent crop and is not retained.
The leading Note `✎` topmost symbol now keeps the Todo symbol's calibrated
horizontal origin but uses an independent `Offset(1, 0)` paint origin. Its
focused 20x17 crop falls from 4.0676 to 1.4833 MAE, while Todo remains on its
verified `Offset(1, 1)` path and neither button layout nor hit testing moves.
The Note `MD` action independently moves its paint layer left 1px without
changing the 28x24 action slot. Its broad crop falls from 5.1033 to 4.7743 MAE
and the title strip from 2.0773 to 2.0581; the rejected tracking probe remains
rejected.
The fenced-code painter now extends its right edge by the two missing capture
pixels through a 1px/9px horizontal inset pair matching WPF's `Rect(1, ...)`
left origin. The right-edge crop falls from
4.5817 to 0.2986 MAE while the center remains pixel exact. Inline code retains
its glyph-run background, but fenced code text leaves the line background to
the dedicated rounded painter instead of drawing a second rectangular text
background. In the controlled `PrintWindow` interior capture this lowers the
complete code crop from 1.6415 to 1.5524 and the paper interior from 1.1307 to
1.1150. A code-row height reduction probe produced doubled boundary strokes
and was fully reverted.
The later source audit found that WPF starts the fenced background at x=1,
while Flutter still used x=4 and let the first code glyph protrude beyond the
rounded fill. Moving only the painter's left inset to 1 leaves text layout,
the center crop and the verified right edge unchanged. In a direct paired
440x420 `PrintWindow` capture, the complete fixed code region falls from
1.6145 to 1.3808 MAE, its left-edge crop from 8.4005 to 3.8193, and the paper
interior from 1.4087 to 1.3827.
The controlled 440x340 Todo pair also confirms that PaperTodo keeps both the
relative and absolute due badges on independent Windows papers even when the
periodic relative-time setting is disabled. RePaperTodo now preserves that
desktop source behavior while board/mobile surfaces continue to honor the
visibility setting.
An H1-only `FontWeight.w700` probe produces a pixel-identical Windows raster to
the retained semantic `FontWeight.w600` path, including the same 9.8209 tight
crop MAE, so the heavier declaration is not retained and should not be retried.

The native expanded-paper proxy now reproduces PaperTodo's separate Active
slot outline instead of reusing the ordinary paper border. The warm-light ring
uses the source-derived `RGB(132,109,76)`, 2px thickness, 1px chrome overlap,
13px radius and exact `y=7..38` bounds. The native capsule renderer then moved
from a clipped GDI `RoundRect`/`WindowRgn` to a 4x4 sampled per-pixel-alpha
layer while preserving the calibrated GDI glyph and title metrics. On the
controlled 82x46 proxy crop, left-curve MAE falls from 5.3783 to 4.5827 and the
complete crop from 4.5396 to 4.3067. Captures are stored as
`.tmp/papertodo-reference-capsule-proxy.png` and
`.tmp/repapertodo-capsule-proxy-layered.png`. The Windows policy smoke also
confirms repeated master toggles, retained child handles, monotonic collapse
and expansion alpha, proxy activation/drop routing and zero-pixel master-drag
frame error after the layered-rendering change.

A follow-up raster audit found that WPF `Border` expands and contracts its
stream geometry by half of `BorderThickness`; using the declared 12px/13px
corner values directly made both native curves visibly fuller than the source.
The layered renderer now uses 12.5/11.5px body radii and 14/12px Active-outline
radii at 96 DPI while leaving the 30px body, HWND bounds, text and hit targets
unchanged. In the same controlled crop, left-curve MAE falls from 4.5827 to
2.1878 and the complete 82x46 crop from 4.3067 to 3.6058. Evidence is stored
as `.tmp/capsule-radius-halfstroke.png`. The same body correction improves the
51x46 master capsule from 6.5851 to 6.1176 MAE and its first 24px curve from
3.0854 to 2.0921; evidence is `.tmp/capsule-master-halfstroke-visible.png`.
The full Windows policy smoke remains green in
`.tmp/windows-policy-capsule-halfstroke.json`.
An explicit `Microsoft YaHei UI` probe for the Chinese master label regresses
the complete 51x46 crop from 6.1176 to 6.4415 and its label region from 15.7802
to 16.8237 MAE. GDI's existing Segoe UI font-linking path remains retained and
the forced-family probe should not be repeated.

The mirrored master-capsule audit exposed a semantic mismatch that the right
edge had hidden through clipping: PaperTodo's idle label is exactly `收起` /
`Collapse`, not `收起全部` / `Collapse all`, and its active count is `{n} 个` /
`{n}` rather than a paper noun phrase. RePaperTodo now forwards those exact
source strings, so both edges reveal the same intended text. Controlled 96-DPI
left/right captures also show that the WPF label raster lands one device pixel
to the right on both edges while its vertical center needs no offset; the
chevron remains one pixel right and down. The earlier grayscale GDI label path
therefore used `(+1, 0)`, but its idle label crops remained 30.5457/26.3672
MAE. It is now superseded by DirectWrite Natural grayscale rendering. The
right edge keeps the common +1px layout origin; the mirrored left draw rect
moves back 2px, matching the source's opposite clipping direction. Idle label
crops fall to 2.8048/2.7958 and complete 51x46 MAE to 2.4815/1.6546. Active
`1 个` then moves up one raster row, lowering its label crops to
1.3838/1.7546. The mirrored chevron receives the same -2px horizontal
correction as the label. Final idle complete MAE is 1.5332/1.6546 and active
MAE is 1.8674/2.0250, down from the GDI 6.6202/5.3119 and 4.5151/3.4363. A
`DEFAULT_QUALITY` GDI variant remains rejected because it introduces colored
ClearType fringes absent from the transparent WPF window. Final idle evidence
is `.tmp/repapertodo-master-{left,right}-idle-final-v3-{full,visible}.png`;
active evidence is
`.tmp/repapertodo-master-{left,right}-active-final-v2-{full,visible}.png`.

The follow-up full-width audit used the source `CapsuleWindowWidth()` formula
rather than inferring hidden geometry from the 51px clipped viewport. At 96
DPI WPF measures the default Chinese idle label plus chevron to a 68px full
reserve while GDI measures the same pieces as 72px; other system fonts have
different deltas, so a fixed correction is not sufficient. RePaperTodo now
forwards the UI preset and exact system-family selection to the native surface,
uses DirectWrite advances for the master-only `35 + glyph + widest label` and
`29 + glyph + first label` formulas, and rounds only their final results.
Fresh default captures remain 68x46 full with unchanged 51x46 visible slices
in `.tmp/repapertodo-master-{left,right}-width68-{full,visible}.png`. An
explicit DengXian system-font pair also retains 68x46/51x46 and reaches 5.4467
left / 2.9300 right visible MAE on the old GDI label path, then 2.8809/2.0391
with the DirectWrite label renderer and finally 1.9327/2.0391 after mirrored
glyph calibration. Evidence is in
`.tmp/{papertodo-reference-,repapertodo-}master-{left,right}-system-dengxian-*.png`
and the matching `*-dwrite-*` captures. The real-window policy regression
remains green in `.tmp/windows-policy-master-final-v3.json`, covering
repeated master toggles, retained child handles, drag following, and monotonic
retract/release alpha.

The collapsed Flutter paper capsule now uses the same WPF half-stroke
outer/inner radius model instead of `BoxDecoration`'s generic border painter.
Its controlled 93x46 capture falls from 4.0964 to 3.6508 MAE; the first 24px
curve improves from 5.0909 to 4.1247 and the close-side region from 3.7128 to
2.8410, while the title crop remains pixel-identical. Evidence is
`.tmp/capsule-normal-halfstroke.png`.
The Todo capsule's 13px Symbol glyph keeps its layout slot but moves only its
paint layer up 1px, matching the source `y=19..27` ink bounds. Its focused
crop falls from 11.7976 to 3.3571, the complete left region from 4.1247 to
2.4460 and the full capsule from 3.6508 to 3.2089 MAE. Evidence is
`.tmp/capsule-normal-icon-up1.png`.
The final per-type measurement pass keeps the GDI-to-WPF advance correction
separate: Todo `-3px`, ordinary Note `-1px`, and script `-2px`. This restores
the source ordinary/deep Note widths from `96/105px` to `97/106px` without
changing the already-correct Todo and script widths. All ordinary capsule
titles then move only their paint layer up 1px; Note/script titles use a local
`-0.25px` tracking correction, and the 15px script lightning adds a paint-only
`-0.25px` horizontal origin. Fresh same-data captures reach 1.7308 MAE for
Todo, 2.0713 for Note, and 2.0004 for script. The Todo title crop falls from
12.7261 to 3.4815, the Note title crop from 14.5624 to 6.3465, and the script
icon crop from 3.1689 to 2.0089. Evidence is stored in
`.tmp/capsule-todo-icon-title-up1.png`,
`.tmp/capsule-note-tracking-minus025.png`, and
`.tmp/capsule-script-icon-xminus025.png`; the complete Windows policy smoke
passes in `.tmp/windows-policy-capsule-type-metrics.json`.
The first post-change policy run exposed an unrelated Windows sharing
violation while the smoke reader held `data.json`; the capsule click had
already reached Dart, but the failed delete prevented the expanded state from
persisting. `StateStore` now retries only transient Windows replace errors
(5/32/33), and three subsequent complete policy runs pass in
`.tmp/windows-policy-flutter-capsule-halfstroke-run{1,2,3}.json`.

The independent-paper activation path now also treats the hidden coordinator
as a permanently non-activating transport HWND. A capsule activation reports
success only after the intended paper is the actual foreground window, and a
child-engine `framePresented` handshake releases the temporary zero-alpha
reveal only after Flutter has composited the expanded paper dimensions. Three
independent full policy runs cover continuous 5ms foreground ownership,
collapse/expand alpha, repeated master toggles and retained HWNDs without the
former hidden-coordinator focus rebound or alpha-zero stall. Evidence is in
`.tmp/windows-policy-settings-native-hit-run{1,2,3}.json`.

The settings paper no longer depends on a Dart method-channel round trip to
begin a native move or resize. Its full-size `FLUTTERVIEW` child forwards the
20-64px title band and 12px edge/corner bands through synchronous native hit
testing, while the close/client controls remain Flutter-owned. Repeated traces
show root `HTCAPTION=2`, child `HTTRANSPARENT=-1` and exact 84x58 movement even
while the persistent script worker is active; the previous intermittent
immovable-title failure is therefore covered by the same three policy runs.

Latest Todo-row pointer and motion audit uses one populated 280x340 warm-light
paper with the cursor driven through a real leave/enter transition before each
click. The previous Flutter tree faded only the row contents, while PaperTodo
animates the complete bordered row. Moving `AnimatedOpacity` outside the row
surface now includes the hover fill and border in the 200ms EaseOutQuad fade to
0.75 and the 150ms linear restore. The translucent row border is also
precomposited against the paper before the hover fill is painted, matching
WPF's inner-background coverage; the hover-state delta MAE falls from 2.6360
to 1.4073 and the left straight-edge sample reaches `249,242,225` versus the
reference `249,241,225`. Across the captured completion/restore sequences the
mean frame-delta MAE is 1.1883/1.2595 and both settle to zero delta at their
source endpoints. The same capture exposed a text-origin regression: medium
Segoe UI glyph bounds were `x=43..148, y=54..66` instead of the reference
`x=45..150, y=55..67`. Restoring the documented padding redistribution keeps
the layout totals unchanged while matching both reference bounds exactly; the
populated hover-row MAE falls from 9.3347 to 6.3579 and its broad text crop
from 21.0542 to 14.2385. Evidence is stored in
`.tmp/reference-todo-completion/frames-v2` and
`.tmp/current-todo-completion/frames-text-final`.

The follow-up narrow-feedback audit restored the main Note editor's normal
zero tracking after a status-label calibration had leaked `0.7px` tracking
into editable body text. It also verified the Flutter Todo reminder fallback
at the minimum 220px paper width. The former multi-widget detail stack could
grow across most of a 640px paper when four long Chinese items were due.
PaperTodo's fixed 260x104 reminder instead gives its message a 48px maximum.
The fallback now keeps a one-line ellipsized title, a 5px gap and one combined
three-line clipped detail surface while preserving the complete reminder data
and Open action. The controlled 220x640 result is 220x101, with a 42px detail
surface and the 64x48 action fully inside the paper. Evidence is stored in
`.tmp/transient-feedback-220-current.png` and
`.tmp/transient-feedback-220-current.json`.

The Note lifecycle audit then covered PaperTodo's `MarkdownRenderModes.Off`
path, which had been hidden by a Flutter-only forced-editor branch. PaperTodo
uses the same note control for every render mode: a non-empty ordinary Note
opens read-only in Preview, a body click enters Edit, and losing editor focus
returns to Preview; only empty Notes and script-capsule Notes open directly in
Edit. RePaperTodo now follows that state model for Off as well as Basic and
Enhanced. The Off preview bypasses Markdown analysis, token styling and link
activation, keeps zero tracking and the source natural 20px line rhythm, and
shares the editor's calibrated `26/14/12/10` content inset so switching state
cannot move the text. In the controlled 440x420 warm-light fixture, both the
reference Preview and RePaperTodo Preview have body bounds `x=50..342,
y=105..158`; the new Preview raster is pixel-identical to the already
calibrated Edit raster, with a three-line MAE of 18.1423 and page MAE of
3.7119 against WPF. The same pass restored the status mode label's documented
0.7px tracking while keeping statistics at zero tracking. Evidence is stored
in `.tmp/repapertodo-current-note-preview-zero.png` and
`.tmp/note-preview-zero-metrics.json`.

The next Windows interaction pass removed a popup-transition race exposed by
the native due-date picker. Closing the Todo context menu can replace its
`TextFormField` in the same frame that a wrapped-line measurement callback is
due. The old callback previously walked an inactive element tree, producing a
scheduler exception during the native dialog transition and risking a visible
one-frame flash. Line measurement now verifies that the Focus attachment is
active and defers itself until the replacement editor is mounted. Both native
date/time and reminder-interval flows still issue exactly one platform dialog
request, and the expanded 23-test Due plus 23-test Reminder UI regressions pass
without scheduler exceptions.

The Display settings audit now includes the real bottom scroll state instead of
inferring it from the upper controls. PaperTodo was opened from its actual tray
icon, its 792x720 settings `ScrollViewer` was set to 100%, and `PrintWindow`
captured `.tmp/papertodo-reference-settings-display-bottom.png`; the original
`.tmp/data.json` SHA-256 remained unchanged. With the same data, the draft
Cancel/Confirm footer initially reduced Flutter's viewport by exactly 10px, so
every otherwise aligned source control moved ten rows upward at maximum scroll.
Compacting only that extension to a 2px gap and 24px actions restores the
source viewport: the complete source body falls from 13.9480 to 1.1128 MAE and
its best translation returns from `(0, +10)` to `(0, 0)`.

The newly visible Top-bar-button group also exposed a checked-mark raster
difference that the earlier upper-page text audit did not measure. The 16px
host, 1.5px source border and exact path stay unchanged, while a 3.5px
capture-equivalent checked radius plus a paint-only `Offset(2, 2)` reproduces
WPF's rounded fill and stroke placement. A local -1px paint correction aligns
only the nested Display heading and its three marks; titles, help targets and
row layout do not move. The repeated bottom marks fall from 16.0549 through
5.4028 to 0.7546 MAE, the Top-bar block from 2.6991 to 1.8559, and the complete
Display source body reaches 0.9902. The same checked mark on the unscrolled
Todo/Notes page falls from 9.3526 to 0.5626 MAE. Final evidence is stored in
`.tmp/repapertodo-settings-display-bottom-checkbox-v4.png` and
`.tmp/repapertodo-settings-checkbox-raster-v4-{display,todo,capsules,general}.png`.

The four settings pages now also have real dark-state reference captures made
through the original PaperTodo tray path, with the isolated dark fixture hash
unchanged. Palette, geometry and control state are already positionally stable:
header MAE is 0.3121 on every page, common navigation is
0.7662/0.8005/0.7482/0.7885, and every source-body shift search remains
`(0, 0)`. That pass exposed the remaining unchecked-toggle raster: Skia's
centered 1.5px stroke produced one full plus one half-covered straight row,
while WPF snaps two complete rows. Reusing the capture-calibrated
outer-minus-inner ring lowers the exact 16x16 crop from 7.0938 to 0.6849 in
light and from 5.6849 to 0.5911 in dark. Final dark source bodies reach
0.7569/1.0729/1.7811/1.1995 MAE for Display, Todo/Notes, Capsules and General.
Evidence is stored as
`.tmp/papertodo-reference-settings-dark-{display,todo,capsules,general}.png`
and
`.tmp/repapertodo-settings-unchecked-ring-v5-dark-{display,todo,capsules,general}.png`.

| Surface | PaperTodo reference | RePaperTodo status | Remaining work |
| --- | --- | --- | --- |
| Palette and typography | `Theme.cs`, `AppTypography.cs`, `NoteTypography.cs` | All four light/dark palettes and PaperTodo custom-accent derivation match exactly; Active, Tint, Danger, Link, CheckBox and QuoteBorder stay independent across paper chrome, Todo/Note states, Markdown, settings and native reminder payloads. Same-data Chinese Todo captures verify default and YaHei use the source-identical Windows chain; DengXian preserves its glyphs with a Flutter-only `12.5/13` WPF Display advance correction and unchanged line box. Default note Markdown and non-code canvas text use the separate Microsoft YaHei UI-first content chain | Final mixed-DPI font metric audit |
| Radius and elevation scale | `AppUi.cs` | 4/8/12/14/18 radius hierarchy applied to the main paper, controls, confirmation dialogs and recovery panels; Flutter confirmation/recovery dialogs use the source 24/26px floating shadow and the paper-limit dialog keeps its dedicated 18px compact shadow. Expanded Windows papers use a native Gaussian shadow instead of stacking a clipped Flutter blur | Verify dialog shadow softness on Windows 10 and mixed DPI |
| Paper shell | `PaperWindow.cs` | Continuous hard-clipped 18px paper surface and full palette border implemented inside the source-matched 8px transparent chrome; four 1px color-key guards remove the rounded-edge dark fringe, DWM non-client rendering is disabled, and a per-pixel-alpha no-activate shadow HWND follows the paper without entering coverage detection. Same-size Windows 11 desktop captures match v2.27 light/dark shadow samples within 0-2 channel levels. Title tint and precomposited divider match reference pixels; native bounds use logical monitor DPI. The bottom-right resize grip reproduces the source four-row triangular system grid: ten 2x2 points use the exact four cool gray-blue subpixel colors, and a fresh 280x340 dark capture matches all 40 reference pixels with zero channel error | Verify Windows 10 rendering and cross-monitor coordinate mapping |
| Title bar | `PaperWindow.cs::BuildTopBar` | 31px outer strip uses the source `6,5,8,1` content inset around its 24px action row. The scalable 13px `☑` Todo symbol uses a +1px/+1px WPF content origin, while the 15px `✎` Note symbol independently uses +1px/0; both retain 0.58 inactive opacity, full hover opacity and active SemiBold weight. Todo bounds match `x=23..32, y=23..31`; the focused Note glyph crop reaches 1.4833 MAE without moving either action slot. The source 38-86px title host uses a capture-calibrated 41-86px Flutter measurement range while preserving exact 4/5 padding and hover tint; static and editable layers are mutually exclusive and share a 1px/1px internal WPF Display paint offset with the source zero tracking. Same-size warm-light and dark `Todo1` captures share the reference `x=44..71, y=22..29` antialiased glyph bounds without an ellipsis; removing the former Flutter-only -0.1px tracking lowers the focused glyph crop from 10.7454 to 2.9355 MAE. The host keeps a transparent 1px layout border so display/edit centering cannot move, while its visible divider is independently painted at a 1px horizontal inset and -2px vertical origin with the source 8px radius. Divider MAE falls from 4.2544 to 0.1684 and the complete title-host crop reaches 1.5637. Source `pin.png` / `unpin.png` assets use 15px low-filter sampling and a -2px WPF content-origin correction: visible bounds match `x=152..162, y=18..32`, while pin-region MAE falls to 0.1945 light and 0.3662 dark. The `MD` label keeps its source typography and uses a paint-only -1px horizontal origin. Symbol actions retain their 28x24 slots but use independent WPF paint metrics: `＋✓` uses a 13.25px regular face, -1.5px/+1px origin and -0.25px tracking; `＋✎` uses the source 13px regular face, -1px/+1px origin and zero tracking; `─` remains -1px/+1px with the exact reference 8x2 grid. In the fresh warm-light 280x340 capture, the complete Todo action slot falls from 4.4177 to 1.1503 MAE, the Note action from 2.5605 to 1.0893, the title strip from 2.3729 to 1.5176 and the full paper from 0.3728 to 0.2871. The `×` hide action, 32/48-alpha hover feedback, one-pixel action gaps, native drag and progressive action breakpoints are implemented and covered. Real v2.27 comparisons at 220/280/320/440/560px confirm the source group remains right-anchored; the added manual-sync action expands to its left and uses a later Note threshold so it cannot truncate the title | Final mixed-DPI localized glyph/text metric audit |
| Todo rows | `PaperWindow.Todo.cs::BuildTodoRow`, `TodoTextBox.cs` | Subtle bordered rows, exact hover opacity, fixed 16px checkbox, compact `≡` handle and 0.25 drag feedback, 200/150ms completion fade to 0.75, full-column 1.35px completion rules, source-matched 250ms new-row rise and 40ms-staggered paste entrance, no extra multi-column bottom inset, rendered-line-aware linked-note sizing and source-metric due badges implemented. Empty standalone rows now remain visually blank like the source `TodoTextBox`; the localized New item hint is limited to board/mobile surfaces. The checkbox retains the source 1.5px BorderThickness and 4px CornerRadius as semantic metrics, but its unchecked outline now uses a capture-calibrated outer-minus-inner RRect instead of Skia's centered stroke. This reproduces WPF's 96-DPI device-pixel-snapped two-row/two-column straight edges: the exact 16x16 crop falls from 8.3398 to 1.3945 MAE, its 22x24 host from 4.0436 to 0.6761, the complete blank Todo row from 0.2969 to 0.0878 and the full 280x340 paper from 0.3934 to 0.3728. Main and extra editors redistribute their unchanged total padding by 2px horizontally and 1px vertically to compensate for Skia's Segoe UI bearing/baseline, while -0.0625px tracking reproduces WPF Display advances without affecting the separately calibrated DengXian path. Fresh 280x340 Todo-row MAE falls from 3.5468 to 2.1121 light and 4.2212 to 2.0770 dark for populated rows. Due badges use the source bilingual duration units, natural text width, `M/d`/`yy年M/d`/`yyyy年M/d` date formats, visible Tint surface and 0.72 absolute-badge press state; a same-minute 440x340 v2.27 comparison matches their vertical glyph bounds, while 220px papers retain both badges and clip the trailing group at the paper edge like WPF. Long multi-column captures prove shorter columns, the checkbox and trailing handle center against the tallest wrapped column; the source 3px first-column trailing margin and 6/3px extra-column margins reproduce the same nine-line wraps and total row height, added columns stay transparent, splitters span the full row, and overflowing lists expose a 5px auto scrollbar with 7px end margins. Multi-column rows reserve the source 18/18/20/23px trailing slots around the 14/14/16/19px Symbol-font drag handles; all four visual presets and 220/280/320/440/560px widths are covered | Final mixed-DPI render audit |
| Todo append/delete areas | `PaperWindow.Todo.cs::BuildTodoAppendArea` | Exact 6/2px margin, 8px radius, append tint/border/opacity values, per-size plus/trash glyphs and Danger light/dark transformation are implemented and covered through the full drag gesture. The drag anchor now preserves the pointer's offset inside the complete source row instead of anchoring to the compact handle, matching PaperTodo's left-extending feedback. Reorder hit testing reconstructs the actual pointer from Flutter's feedback-origin `DragTargetDetails.offset`, so that visual calibration cannot change before/after insertion semantics. The highlighted border uses a capture-equivalent 2px Flutter inside stroke because WPF's centered 1.5px stroke covers two complete raster rows at 96 DPI. Controlled captures measure 0.5434 MAE at append rest, 1.0419 on append hover and 0.5232 for the hover-state delta; the clean right side of the active delete area falls from 5.1657 to 0.9209 MAE, with the center border rows matching the reference RGB exactly. The 3px reorder insertion line, 200ms/30px single-delete departure and 30ms-staggered 180ms/20px Clear-completed departures also match. Evidence: `.tmp/repapertodo-todo-pointer-rest.png`, `.tmp/repapertodo-todo-pointer-append-hover.png`, `.tmp/repapertodo-todo-pointer-trash-active-final.png` and `.tmp/repapertodo-todo-pointer-trash-hover-final.png` | Windows 10 and mixed-DPI pointer audit |
| Note canvas toolbar | `PaperWindow.Note.cs::BuildNoteCanvasToolbar` | Exact 31px minimum, 9/3/9/4 padding, theme tint/divider alpha and fixed 28px `{}` action implemented. The right-anchored count uses the source 11px Regular/zero-tracking metrics with a -1px/-1px WPF paint origin; its same-data 440px crop falls from 8.3516 to 4.6927 MAE. The `{}` glyph uses an independent +1px horizontal paint origin without moving its button or hit target, reducing its tight/broad crops from 10.2469/2.7946 to 2.6811/0.7312 and the latest complete toolbar from 0.8575 to 0.6823. A 220x340 Chinese capture verifies count alignment at the minimum paper width | Final mixed-DPI count alignment |
| Note paper | `PaperWindow.Note.cs::BuildNoteSurface`, `NotePageContentMargin` | 24px grid canvas, 8/6/8/0 shell margin, 7px frame layout padding, 14px/12px radii, separate 28/34 border and WPF-coverage grid tints, 104/88 binding line, source-derived 24/12/14/12 Flutter content margin without preview double-padding, inner paper and in-page element overlay implemented. The grid phase is vertical +1px and horizontal -1px relative to Flutter's CustomPaint origin; non-antialiased one-pixel lines use effective 18/255 light and 24/255 dark alpha, reproducing the WPF integer-coordinate Pen coverage. Visible light grid pixels are aligned and differ by at most one channel level. The outer canvas keeps its original layout inset but paints its fill and WPF-precomposited foreground border one pixel inward horizontally; all four straight edges now match the reference x=17/422 and y=79/384 pixels, with focused left/right/top/bottom crops reaching 0.0323/0.0197/0.0253/0.0161 MAE. The inner page chrome paints one pixel inside the unchanged layout on the left and right while retaining the compensated bottom, matching straight WPF border columns x=25/414 and rows y=87/376 without shifting content. The binding strip uses capture-equivalent 16/15/15px left/top/bottom endpoints and exactly matches the reference visible bounds x=40..41, y=103..360, retaining its 0.0057 MAE crop. The complete controlled window falls from 3.5989 to 3.0960 MAE while its content crop is unchanged. Preview and editor expose the source-like 5px automatic scrollbar with 7px end margins only when content overflows; same-data long-note captures cover Warm, Ink, Forest and Rose in both light and dark modes | Final mixed-DPI scrolling audit |
| Markdown note rendering | `MarkdownTextBox.cs`, `NoteTypography.cs` | Off/Basic/Enhanced all follow PaperTodo's non-empty Preview, click-to-Edit and focus-loss-to-Preview lifecycle, while empty and script Notes open directly in Edit. Off bypasses Markdown analysis, styling and link activation and keeps plain zero-tracking text at the same calibrated origin in both states. Basic/Enhanced preview preserves selectable source; exact 19/16.5/15/14px headings, SemiBold emphasis, 13px Cascadia code, semantic syntax/link/quote colors, source-like image/table handling, Enhanced marker fading/list redrawing, editable source highlighting, IME fallback and scroll-synchronized editor quote/code backgrounds are implemented. Preview visual lines use capture-calibrated paint-only WPF origins without changing layout: H1 +1/+2px, quote +1/-2px, ordinary paragraphs +3/0, first list item +3/-4px, later list rows +3/-2px and code fences/rows +2/-4px. Display tracking is +0.1px paragraph, +0.05px quote, -0.075px list and +0.4px Cascadia code. Heading/quote block fills use 1px/8px horizontal insets, quote surfaces trim one trailing row with a 4px radius, and code fills use WPF-equivalent 1px/9px insets around their 1px border. Inline code keeps its glyph-run background; fenced code text does not duplicate the rounded line painter with rectangular text backgrounds. The heading underline remains independently snapped to WPF's raster row. In the fresh same-data 440x420 capture, the paper interior falls from 4.7245 to 2.3160 MAE and the focused H1/paragraph/quote/list/code crops reach 2.2977/9.0807/1.1791/1.5109/1.7256. The latest controlled fenced-code crop reaches 1.5524 MAE and its right edge 0.2986. Fenced-code backgrounds distinguish opening, middle and closing rows so their paint ranges reproduce WPF's fractional visual-line accumulation while keeping code text and document flow unchanged; the light border uses the capture-equivalent 69/255 tint. Wrapped list bullets stay on the first visual line and the hidden source marker uses the reference width. Preview body taps and inline links use separate gesture paths, and preview/editor switches transfer the viewport in both directions so long notes do not jump during focus changes. Long-note captures retain matching wraps, 20px rhythm and a last-line endpoint within 1px across every palette | Final mixed-DPI visual audit |
| Note status bar | `PaperWindow.Note.cs::BuildNoteStatusBar`, `PaperWindow.cs::BuildTextZoomOverlay` | The source 26px minimum is represented by a capture-equivalent 27px Flutter host so the top divider lands at y=385 while the paper bottom remains fixed; asymmetric padding, 42px mode pill, stats, read-only 38px zoom field and separate non-100% reset overlay retain their source behavior. The source 11px Regular statistics use zero tracking and a +1px/0 WPF content origin; zoom uses -1px/0, while the 11px SemiBold mode label keeps 0.7px Display tracking and +1px/0. The mode background uses source 32/48 Tint with WPF floor compositing, a paint-only +1px horizontal origin and a capture-equivalent 9px radius, producing exact warm-light `#E9E0CC` without moving text or the hit target. The final UI-font fallback pass keeps every measured text bound at the zero-shift optimum and lowers the fresh complete status crop to 3.5661 MAE; focused mode/statistics/zoom crops reach 7.2053/1.6687/2.3503. The remaining error is glyph antialiasing rather than geometry. A 220x340 Chinese long-note capture verifies that stats ellipsize between the fixed mode pill and 38px zoom field like PaperTodo. Evidence: `.tmp/repapertodo-note-status-current-latest.png` and `.tmp/note_status_metric_probe.ps1` | Final mixed-DPI text-trimming audit |
| Note canvas elements | `PaperWindow.Note.cs::BuildNoteCanvasElementView`, `AppUi.NoteCanvasElementShadow` | Exact code background, fixed 13px code typography independent of note zoom, light/dark header/badge/border alphas, 22px drag header, always-editable 72x48 minimum surface and 15px resize grip implemented. A same-data v2.27 capture proves the WPF element's clipped `DropShadowEffect` emits zero pixels below the block, so Flutter no longer adds its mismatched broad external `BoxShadow`. Code uses the captured 15px line rhythm, a zero Flutter top inset, +0.4px WPF Display tracking and a 2/16px redistribution of the unchanged 18px horizontal editor inset; `CODE` and layer badges keep independent -1px and top-layer +2/-1px paint origins. The embedded overlay preserves the source 2px/1px bordered-page origin and fixed `CODE`, `层 N`, `顶层 N` labels. Display-only `U+200B` opportunities before `(` reproduce WPF token-boundary wrapping without entering the model, clipboard or persistence. The final 440x420 Release capture gives both editors the exact source text bounds and wraps `Console.WriteLine` at the same boundary as v2.27: the focused back text falls from 14.3520 through 9.5791 to 5.2811 MAE and the front text from 12.3226 to 6.3259, while header rasters remain unchanged at 1.1208/2.1900. The previously mismatched bottom/right shadow regions remain pixel exact 0.0000. Evidence: `.tmp/papertodo-reference-note-canvas-elements.png` and `.tmp/repapertodo-note-canvas-elements-wrap-final-v4.png` | Final mixed-DPI font rendering audit |
| Context menus | `PaperWindow.cs` menu styles | Board/mobile surfaces retain the compact Flutter menu, while independent Windows Paper, Markdown-editor, canvas-element and Todo-item menus use an owner-drawn Win32 popup HWND. This removes the Flutter Overlay boundary that previously shifted a long Markdown menu upward and lets the popup begin at the real secondary-click anchor while extending below the paper HWND like WPF. The native host preserves the captured 20px/19px/17px section headers, 25px/21px command rows, 7px separators, 5px shell padding, 28px measured horizontal chrome and exact 93x286 / 80x330 / 132x209 / 89x187 outer geometry. Commands use the source 8px rounded hover surface with identical hover/pressed frames. Text now uses grayscale DirectWrite Natural rendering at the source 12px SemiBold header and 13px Regular command sizes; each owner-drawn row binds a local item clip, headers and 17/19/20/21px rows use a -2px WPF origin, 25px commands use -1px, and GDI remains the failure fallback. Separators reproduce the captured 43px leading indent, 13px trailing indent, two-pixel upward raster origin and 38% system-line blend. A scoped CBT hook clears USER32's broad `CS_DROPSHADOW` before popup creation and restores the system class during destruction; fresh light captures therefore retain the source's unshadowed paper popup without leaking the style to tray or later menus. Header weak text and disabled text retain separate 72% blends, Markdown suppresses the overlapping Flutter selection toolbar on Windows, and widget tests force the Flutter fallback through `FLUTTER_TEST`. Fresh dark same-anchor rest MAE is 3.6238/1.6991/1.9693/0.8081 for Paper/Markdown/Todo/Canvas, down from 6.5703/4.6914/22.1786/4.3628; light reaches 3.7817/1.1656/1.8878/0.8590, down from 8.1421/5.6373/21.6716/5.8676. Evidence: `.tmp/papertodo-reference-context-menu-{paper,markdown,todo,canvas}-{dark,light}-same-anchor-{rest,hover,pressed}.png` and `.tmp/repapertodo-context-menu-*-directwrite-source-size-v{7,8,9}-{rest,hover,pressed}.png` | Final mixed-DPI pointer audit |
| Transient feedback | Paper surfaces, `TodoReminderBubbleWindow.cs` | Flutter fallback undo, sync, error and reminder snack bars use the selected PaperTodo paper surface, palette border, body text and Active action color rather than Material's dark notification surface; Windows paper reminders continue to use the native source-matched adjacent bubble and hover-paused timer. A 220px Chinese Jianguoyun 401 fixture verifies that long failure text remains bounded and Retry reflows below it without a RenderFlex overflow. The 220px four-item Chinese reminder now mirrors the source's bounded message structure: one title line, a 5px gap and three clipped detail lines produce a 101px fallback surface versus PaperTodo's fixed 104px native bubble, while the Open action remains fully visible | Final mixed-DPI fallback text audit |
| Confirmation and recovery dialogs | `AppUi.cs`, PaperTodo paper surfaces | Paper limit, delete, restore, recovery-list, canvas-geometry, fallback due/reminder and fallback color flows use the source paper shell; fixed PaperTodo 340x176 paper-limit and 300x178 delete geometry use the title/message/action Grid proportions, and confirmation actions are compact text-only rows with source spacing and danger/active tint. Desktop paths stay single-line ellipsized, compact paths are capped at three lines, and automated focus checks cover delete/cancel, paper-limit OK, restore/close and cancel/restore loops; no default Flutter alert surfaces remain | Final Windows 10/11 shadow render audit |
| Date/time picker | `PaperWindow.Todo.cs::ShowTodoDueDialog` | 354×242 borderless rounded paper popup, themed owner-drawn buttons and source-matched single-row date/hour/minute grouping implemented in both the native picker and Flutter fallback; the native surface now reproduces the WPF full-date selection, compact `15` calendar glyph, source-raster combo gradient, exact antialiased 5x5 selector chevron and light borders while retaining the system calendar/lists underneath. Native font families, numeric metrics and WPF-rounded palette blending are forwarded from the configured Flutter state; title, message and action labels use their verified grayscale DirectWrite paths while editable date/time controls retain calibrated native rendering. A separate non-activating per-pixel-alpha shell provides source-fitted antialiased corners behind the ordinary interactive dialog, so native calendar/combo children remain visible and pointer-addressable. Stale Todo line-measurement callbacks defer across popup-route replacement instead of touching inactive editor elements, keeping the native transition exception-free and single-shot. Cancel/Clear/OK order and keyboard behavior are covered | Final mixed-DPI layered-corner and shadow audit |
| Reminder interval picker | `PaperWindow.Todo.cs::ShowTodoReminderIntervalDialog` | 326×216 native and Flutter rounded paper popup with exact title/message hierarchy, 32px value/unit row, Cancel/Global/OK actions, source blue edit focus border, WPF-like gray unit selector with source-raster gradient and the shared antialiased chevron, configured UI font forwarding, grayscale DirectWrite title/message/action rendering with source-matched wrapped line advance, WPF-rounded palette blending, focus/select-all behavior, keyboard handling, theme colors and high-DPI centering implemented and covered. Its separate non-activating layered shell preserves the antialiased paper edge while the ordinary upper dialog retains functional edit/combo/button children on Windows 10/11 | Final mixed-DPI layered-corner and shadow audit |
| Reminder bubble | `TodoReminderBubbleWindow.cs` | Native 260×104 adjacent layered bubble with 14px shell, 28px tinted icon, active `!`, themed grayscale-DirectWrite 13/12px text, hover-paused dismissal and tinted border implemented. A same-data 96-DPI `PrintWindow` pair reaches 0.5405 full-window MAE; icon/title/three message rows reach 0.3286/1.1849/0.9077/0.8429/0.9072. Solid-background screen capture proves the source emits no pixels outside its HWND, so the mismatched Win32 `CS_DROPSHADOW` was removed | Verify mixed-DPI glyph bounds and multi-line truncation |
| Settings window | `AppController.Settings.cs::BuildSettingsWindowContent` | Separate transparent borderless 18px paper HWND with 672-792 by 520-720 logical DPI-aware sizing, native edge/corner resize and title drag, 8px active-paper underlay, exact source navigation/group wording without page-top dividers, 34px marker navigation, 12/11px group/field hierarchy, custom 28px equal-column segment selectors, 28px text fields, 52/58x26 hotkey/spacing actions, 28px/34px title stepper, exact 16px source-path toggle marks, all 40 source `WrapWithHint` rows with original bilingual text and independent 18px `ⓘ` hit targets, and immediate 28x24 `×` close states, plus native color chooser. The desktop shell uses the capture-equivalent 14px title/content gap and independent `Offset(1, -2)` navigation/divider paint layers. All four source navigation labels now use the post-fallback zero WPF origin, with local -0.05px tracking only where WPF integer advances require it; the common Display navigation crop reaches 0.5874 MAE. The custom-theme editor preserves the 58x42 swatch with fixed 76x27 and 82x27 actions; its full row reaches 2.7197 MAE and the Display source body 0.8365. RePaperTodo intentionally keeps a dialog-local draft with explicit Confirm/Cancel actions so WebDAV validation and platform-setting failures cannot partially apply; those actions are the documented product extension. The added WebDAV page now follows the same 11px label-first/28px field system, compact 34x26 secret actions and 0.55 disabled treatment instead of Material floating-label fields; theme, Markdown, reminder-unit and WebDAV provider selectors retain that same label-first 28px chrome even at narrow fallback widths, and the 58x42 custom-color swatch preserves the source square WPF outline. Reminder-off and relative-date modes retain the source editor availability. Text editors use the source Active focus border, while mouse-only toggle/segment rows remain outside keyboard focus traversal like WPF; non-client layout/paint is intercepted before Flutter, the covering Flutter child now yields native caption/edge hit tests synchronously, and automated English/Chinese 560x360 plus repeated real desktop move/resize checks confirm the old caption strip and intermittent immovable-header failure are absent | Verify shadow softness on Windows 10/11 and mixed DPI |
| Capsules | `PaperWindow.Capsule.cs`, `PaperWindow.DeepCapsule.cs`, `MasterCapsuleWindow.cs` | 30px body inside a DPI-scaled 46px host with 8px transparent chrome, source 12px radius, 21px normal and mirrored 30px deep hide areas, independent close hover/press feedback, 0.08 normal shadow, 18px shifted close glyph and exact native preset/custom palette derivation implemented. Native and Flutter curves reproduce WPF Border's half-stroke outer/inner radii: the controlled Active proxy reaches 2.1878 left-curve and 3.6058 complete-crop MAE. Final ordinary Todo/Note/script captures reach 1.7308/2.0713/2.0004 MAE with per-type WPF advance corrections, paint-only title alignment and the script-glyph origin correction, without moving content or hit targets. Flutter/native proxies share the source `✓` / `✎` / `⚡` glyphs, weak-text color and 26px drag target; the Flutter capsule host also exposes that target as a native caption hit. Real v2.27 captures verify ordinary Todo/Note/script windows at 93/97/91x46, deep full proxy windows at 102/106/100x46, and resting screen-visible slices at 62/65/59x46. Both collapsed HWND paths follow the source 220/180ms ease-out reveal; 16ms sampling records a 20px reveal and zero-pixel settle error. Child-engine frame presentation now gates the final opaque expanded frame, and the hidden coordinator is non-activating outside settings. Transient Windows data-file readers no longer abort a capsule expansion save, and repeated policy runs verify stable master discovery, collapse/expand cycles, retained child handles, monotonic alpha, continuous foreground ownership after pinned activation, cross-edge proxy/drop routing, fullscreen topmost removal/restoration and reminder-hover persistence | Final cross-monitor localized/custom-font audit |
| Tray menu | `AppController.Tray.cs` | Owner-drawn menu preserves the source 190px minimum and measures 194px including the 96-DPI system shadow after compensating Win32's shell metrics. Capture-calibrated native geometry uses a 21px application header, 25px commands, a 22px paper header and 26px paper rows; the real separators land at y=81/113/195/275 after accounting for RePaperTodo's extra Toggle-all and Delete-paper commands. The application title begins at x=16/y=12 exactly like the reference. Application/paper headers now use the source 12px SemiBold and command/paper labels use 13px Regular through grayscale DirectWrite Natural rendering, with local owner-draw clips, independently calibrated WPF vertical origins and GDI retained only as a failure fallback. Every same-string region now has a zero-shift optimum; their weighted full-crop MAE falls from 5.9556 to 0.8150 and ink-only MAE from 55.7771 to 9.7840. The paper row reproduces the reference 14x13 visible check at x=17..30/y=228..240 plus the `✓` icon at x=39..49/y=229..239; the checked surface now uses per-primitive Direct2D antialiasing with the source half-pixel horizontal origin and retains the GDI fallback. Paper labels are title-only; source 0.92 checked fill, palette/custom-accent colors, the configured Windows UI font, 8px hover radius and a 10px native shell radius are retained. `.tmp/repapertodo-tray-menu-directwrite-v7-light-{screen,print}.png` records the final 194x311 extended menu, `.tmp/repapertodo-tray-menu-directwrite-v7-dark-retry-{screen,print}.png` verifies the dark palette, and `.tmp/compare_tray_menu_pairs.py` records the segmented metrics. `.tmp/repapertodo-tray-menu-right-edge-submenus.png` continues to prove the two delete levels choose opposite safe directions at the right work-area edge without overflow. Toggle-all and Delete-paper remain intentional RePaperTodo additions | Verify chrome on mixed-DPI Windows 10/11 |

## Verification gates

Latest Note parity work also restores the render-mode-independent Preview/Edit
lifecycle and plain Off-mode raster path. Preview heading, quote and code block
boxes use source-coordinate painters. The compact Windows title uses a separate
CharacterEllipsis display layer and capture-calibrated Segoe UI measurement,
while the editable field remains available only during title editing.

- Render representative Todo and Note papers in light/dark and all four color
  schemes.
- Verify widths at 220, 280, 320, 440 and 560 logical pixels.
- Verify normal, hover, pressed, focused, disabled, pinned and completed states.
- Run the full widget, project-rule and Windows platform suites.
- Build and package the Windows release after every stable UI milestone.

Latest real-font captures are stored under `.tmp` as
`ui-todo-current-{light,dark}.png`, `ui-note-current-{light,dark}.png`,
`ui-capsule-current-{light,dark}.png`, `ui-settings-navigation.png`,
`papertodo-reference-deep-capsule-{todo,note,script}-light.png`, and
`ui-deep-proxy-current-{todo,note,script}-gray-visible.png`. Long-content
evidence is in `papertodo-reference-todo-long-{todo,list,columns}-light.png`,
`ui-todo-long-{todo,list,columns}-light.png`,
`papertodo-reference-note-long-note-light{,-bottom}.png`,
`ui-note-long-note-light-{scrollbar,bottom}.png`, and the paired
`note-canvas-{center,edge,layered}` captures. Warm, Ink, Forest and Rose
long-note pairs are stored as `papertodo-reference-note-long-note-{scheme}-{theme}.png`
and `ui-note-long-note-{scheme}-{theme}.png` (Warm keeps the legacy reference
filename without a scheme suffix).
Localized preset evidence is stored as
`papertodo-reference-todo-localized-todo{-yahei,-dengxian}-light.png` and
`ui-todo-localized-{default,yahei,dengxian}-light-*.png`; the 220px Note
status pair uses `papertodo-reference-note-long-note-220-light.png` and
`ui-note-long-note-220-light.png`.

The current active desktop is a single 2560x1440 monitor at 96 DPI. Logical
DPI conversion remains covered by native tests, but real mixed-DPI visual
evidence still requires an active monitor with a non-96 DPI scale.

Flutter-side fractional-DPI coverage now exercises both Todo and Note paper
windows at 125% and 150% with 220px and 280px logical widths. The regression
holds the 8px native chrome inset, 31px title strip, right-anchored trailing
actions, 38-86px title host, Todo row/checkbox/append geometry, Note canvas and
27px status strip constant in logical pixels. It also enters and exits the
plain Markdown-Off editor at each size and proves that the calibrated content
box does not move between Preview and Edit. The fixture now runs in `zh-CN`
with mixed Chinese/Latin content and separately locks the right-anchored canvas
count plus the mode/statistics/zoom status slots; the one-line statistics field
retains character ellipsis without crossing either fixed neighbor. These checks
establish layout and state stability inside Flutter; they do not replace
DirectWrite/DWM captures from a real non-96-DPI Windows monitor.

The current title-bar implementation keeps the source pin/create/collapse group
right-anchored at 220/280/320/440/560px. RePaperTodo's added sync control grows
to the left of that group; Note papers use the later fit threshold so a 280px
Note keeps its source title and actions clear before sync is introduced.
