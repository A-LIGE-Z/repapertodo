# PaperTodo UI parity audit

Authoritative reference: `D:\AI\PaperToDo\PaperTodo-original`.

The audit compares visible structure, dimensions, colors and interaction
feedback. Functional compatibility alone does not mark a section complete.

Latest native-picker calibration: the due-time hour/minute and reminder-unit
selectors reproduce the WPF 240-to-229 light gradient. The reminder selector
uses a 23px control inside a 27px cover surface so the backing Win32 ComboBox
cannot leak its lower shadow. The due DatePicker now separates its WPF white
editor strip and `#99C9EE` selection from the surrounding paper/calendar
surface, with an exact `#D5C8B0` frame and calibrated text baseline. Same-state
due-dialog MAE is 2.6948 (date region 5.5108; previously 15.3369), while the
reminder-dialog selector crop remains 3.2398 MAE.
Native action buttons independently use grayscale antialiasing like WPF's
paper-surface text, while titles, messages, numeric fields and selectors keep
their better-matching ClearType path. Due/reminder button crops reach 6.1512
and 8.0322 MAE, reducing the complete dialogs to 2.6072 and 3.4282.
Both action-label paint boxes then receive the shared WPF +1px vertical
origin, reducing the due/reminder button crops further to 3.4323 and 3.6890
MAE and the complete dialogs to 2.2212 and 2.9748. A wider-tracking experiment
regressed both captures and is not retained.
Hour, minute and reminder-unit selectors now use the same filled 5x5 down
triangle as the reference rather than a low outline V. Their chevron crops
reach 6.1133 and 5.5313 MAE, reducing the complete due/reminder dialogs to
2.2085 and 2.9671. Title-height/width compensation experiments were rejected
by both captures and are not retained.
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
The installed-font field independently uses `TextAlignVertical(y: -0.4)` for
its editable text while its frame and exact chevron remain fixed. Its text and
complete-field crops reach 17.2571/2.4034 MAE and the Display page reaches
1.4525. Horizontal-padding compensation regressed and was reverted.
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
Settings checkbox titles use a shared -0.5px WPF paint origin independently
of their marks and 8px layout gap; enabled Todo/Notes labels now start at the
reference `x=204`. Todo/Notes page MAE reaches 2.0991, General 2.7551,
Capsules 1.5705 and Display 1.6510. The already-calibrated top-bar labels
compensate locally so their captured origin does not regress.
Settings group headings and field labels independently use a
-0.5px/+0.5px WPF paint origin; their help glyphs and controls remain fixed.
Todo/Notes page MAE reaches 2.0025, Display 1.6017, General 2.6297 and
Capsules 1.5623. Capture-rejected capsule glyph experiments are not retained.
Settings font and compact dropdowns use a dedicated filled WPF chevron rather
than Material's smaller icon. The visible glyph matches
`x=743..752, y=282..286`; arrow-crop MAE falls from 22.3690 to 1.3492 and the
font-dropdown crop from 2.6160 to 0.4362 without changing layout or hit area.
The light Note status separator now uses an independently calibrated 25/255
tint, matching the reference `#E0CEA7` raster color and reducing the full
440x420 Note capture from 3.2243 MAE to 3.2197 without moving status content.
The Display page's top-bar-button labels now share the reference
`x=205..306` visible bounds after a local 1px origin and tracking correction.
Their focused crop falls from 20.2553 MAE to 19.1200 and the controlled page
from 1.5987 to 1.5923 without moving check marks or help targets.

| Surface | PaperTodo reference | RePaperTodo status | Remaining work |
| --- | --- | --- | --- |
| Palette and typography | `Theme.cs`, `AppTypography.cs`, `NoteTypography.cs` | All four light/dark palettes and PaperTodo custom-accent derivation match exactly; Active, Tint, Danger, Link, CheckBox and QuoteBorder stay independent across paper chrome, Todo/Note states, Markdown, settings and native reminder payloads. Same-data Chinese Todo captures verify default and YaHei use the source-identical Windows chain; DengXian preserves its glyphs with a Flutter-only `12.5/13` WPF Display advance correction and unchanged line box. Default note Markdown and non-code canvas text use the separate Microsoft YaHei UI-first content chain | Final mixed-DPI font metric audit |
| Radius and elevation scale | `AppUi.cs` | 4/8/12/14/18 radius hierarchy applied to the main paper, controls, confirmation dialogs and recovery panels; Flutter confirmation/recovery dialogs use the source 24/26px floating shadow and the paper-limit dialog keeps its dedicated 18px compact shadow. Expanded Windows papers use a native Gaussian shadow instead of stacking a clipped Flutter blur | Verify dialog shadow softness on Windows 10 and mixed DPI |
| Paper shell | `PaperWindow.cs` | Continuous hard-clipped 18px paper surface and full palette border implemented inside the source-matched 8px transparent chrome; four 1px color-key guards remove the rounded-edge dark fringe, DWM non-client rendering is disabled, and a per-pixel-alpha no-activate shadow HWND follows the paper without entering coverage detection. Same-size Windows 11 desktop captures match v2.27 light/dark shadow samples within 0-2 channel levels. Title tint and precomposited divider match reference pixels; native bounds use logical monitor DPI. The bottom-right resize grip reproduces the source four-row triangular system grid: ten 2x2 points use the exact four cool gray-blue subpixel colors, and a fresh 280x340 dark capture matches all 40 reference pixels with zero channel error | Verify Windows 10 rendering and cross-monitor coordinate mapping |
| Title bar | `PaperWindow.cs::BuildTopBar` | 31px outer strip uses the source `6,5,8,1` content inset around its 24px action row. The scalable 13px `☑` Todo and 15px `✎` Note topmost symbols use a shared +1px/+1px WPF content origin while retaining 0.58 inactive opacity, full hover opacity and active SemiBold weight; Todo bounds now match `x=23..32, y=23..31`, reducing leading-region MAE to 2.2503 light and 1.3978 dark, while the 440px Note region falls from 4.3716 to 3.2138. The 38-86px title host preserves exact 4/5 padding, divider and hover tint; static and editable layers are mutually exclusive and share a capture-calibrated 1px/1px internal WPF Display paint offset plus -0.1px tracking. Same-size `Todo1` dark captures share the reference `x=44..71, y=22..29` glyph bounds. Source `pin.png` / `unpin.png` assets use 15px low-filter sampling and a -2px WPF content-origin correction: visible bounds match `x=152..162, y=18..32`, while pin-region MAE falls to 0.1945 light and 0.3662 dark. Symbol actions retain their 28x24 slots but use individual WPF paint metrics: `＋✓` is -1px/+1px with -0.5px tracking, `＋✎` is -1px/+1px with -0.75px tracking, and `─` is -1px/+1px with the exact reference 8x2 grid. Their final light/dark MAE values are 3.5468/2.7212, 2.0558/1.5727 and 0.2990/0.2501 respectively. The `×` hide action, 32/48-alpha hover feedback, one-pixel action gaps, native drag and progressive action breakpoints are implemented and covered. Real v2.27 comparisons at 220/280/320/440/560px confirm the source group remains right-anchored; the added manual-sync action expands to its left and uses a later Note threshold so it cannot truncate the title | Final mixed-DPI localized glyph/text metric audit |
| Todo rows | `PaperWindow.Todo.cs::BuildTodoRow`, `TodoTextBox.cs` | Subtle bordered rows, exact hover opacity, fixed 16px checkbox, compact `≡` handle and 0.25 drag feedback, 200/150ms completion fade to 0.75, full-column 1.35px completion rules, source-matched 250ms new-row rise and 40ms-staggered paste entrance, no extra multi-column bottom inset, rendered-line-aware linked-note sizing and source-metric due badges implemented. The checkbox retains the source 1.5px stroke and 4px WPF radius on its outer element; Flutter's inset stroke uses a calibrated 4.75px centerline radius, reducing checkbox-region MAE from 3.2836 to 1.9979 light and 2.4664 to 1.5295 dark. Main and extra editors redistribute their unchanged total padding by 2px horizontally and 1px vertically to compensate for Skia's Segoe UI bearing/baseline, while -0.0625px tracking reproduces WPF Display advances without affecting the separately calibrated DengXian path. Fresh 280x340 Todo-row MAE falls from 3.5468 to 2.1121 light and 4.2212 to 2.0770 dark. Due badges use the source bilingual duration units, natural text width, `M/d`/`yy年M/d`/`yyyy年M/d` date formats, visible Tint surface and 0.72 absolute-badge press state; a same-minute 440x340 v2.27 comparison matches their vertical glyph bounds, while 220px papers retain both badges and clip the trailing group at the paper edge like WPF. Long multi-column captures prove shorter columns, the checkbox and trailing handle center against the tallest wrapped column; the source 3px first-column trailing margin and 6/3px extra-column margins reproduce the same nine-line wraps and total row height, added columns stay transparent, splitters span the full row, and overflowing lists expose a 5px auto scrollbar with 7px end margins. Multi-column rows reserve the source 18/18/20/23px trailing slots around the 14/14/16/19px Symbol-font drag handles; all four visual presets and 220/280/320/440/560px widths are covered | Final mixed-DPI render audit |
| Todo append/delete areas | `PaperWindow.Todo.cs::BuildTodoAppendArea` | Exact 6/2px margin, 8px radius, append tint/border/opacity values, per-size plus/trash glyphs, Danger light/dark transformation and highlighted 1.5px border are implemented and covered through the full drag gesture; the 3px reorder insertion line, 200ms/30px single-delete departure and 30ms-staggered 180ms/20px Clear-completed departures also match | Final rendered pointer audit on Windows 10/11 |
| Note canvas toolbar | `PaperWindow.Note.cs::BuildNoteCanvasToolbar` | Exact 31px minimum, 9/3/9/4 padding, theme tint/divider alpha, fixed 28px `{}` action and right count implemented; a 220x340 Chinese capture verifies count alignment at the minimum paper width | Final mixed-DPI count alignment |
| Note paper | `PaperWindow.Note.cs::BuildNoteSurface`, `NotePageContentMargin` | 24px grid canvas, 8/6/8/0 shell margin, 7px frame padding, 14px/12px radii, separate 28/34 border and WPF-coverage grid tints, 104/88 binding line, capture-calibrated 26/12/14/12 Flutter content margin without preview double-padding, inner paper and in-page element overlay implemented. The grid phase is vertical +1px and horizontal -1px relative to Flutter's CustomPaint origin; non-antialiased one-pixel lines use effective 18/255 light and 24/255 dark alpha, reproducing the WPF integer-coordinate Pen coverage. Visible light grid pixels are aligned and differ by at most one channel level. Preview and editor expose the source-like 5px automatic scrollbar with 7px end margins only when content overflows; same-data long-note captures cover Warm, Ink, Forest and Rose in both light and dark modes | Final mixed-DPI scrolling audit |
| Markdown note rendering | `MarkdownTextBox.cs`, `NoteTypography.cs` | Basic/Enhanced preview preserves selectable source; exact 19/16.5/15/14px headings, SemiBold emphasis, 13px Cascadia code, semantic syntax/link/quote colors, source-like image/table handling, Enhanced marker fading/list redrawing, editable source highlighting, IME fallback and scroll-synchronized editor quote/code backgrounds are implemented. Preview visual lines use capture-calibrated WPF paint origins without changing layout: H1 -1/+2px, quote -1/0, first list item 0/-2px, and code fences/rows 0/-2px. Display tracking is -0.09px paragraph, +0.05px quote, -0.075px list and +0.4px Cascadia code. Heading/quote block fills use 1px/8px horizontal insets, quote surfaces trim one trailing row with a 4px radius, and code fills use 4px/11px insets to account for their 1px border. The heading underline is snapped independently to WPF's raster row, lowering its focused crop from 48.4015 MAE to 0.1910 without moving the heading text or fill. Fenced-code backgrounds distinguish opening, middle and closing rows so their paint ranges reproduce WPF's fractional visual-line accumulation while keeping code text and document flow unchanged; the light border uses the capture-equivalent 69/255 tint. The focused code crop falls from 4.6960 MAE to 2.0563 and the full 440x420 capture from 3.8576 to 3.2243. The same-data capture matches H1, first-list and code text bounds exactly and leaves paragraph/quote endpoints within 1px. Wrapped list bullets stay on the first visual line and the hidden source marker uses the reference width. Preview body taps and inline links use separate gesture paths, and preview/editor switches transfer the viewport in both directions so long notes do not jump during focus changes. Long-note captures retain matching wraps, 20px rhythm and a last-line endpoint within 1px across every palette | Final mixed-DPI visual audit |
| Note status bar | `PaperWindow.Note.cs::BuildNoteStatusBar`, `PaperWindow.cs::BuildTextZoomOverlay` | Exact 26px minimum, asymmetric padding, 42px mode pill, stats, read-only 38px zoom field and separate non-100% reset overlay with source hover/opacity behavior implemented. Statistics use a +2px/-2px WPF content origin and 0.05px tracking, matching the 440px reference `x=72..176, y=393..403` bounds; the zoom text uses a -1px vertical origin. The mode label uses 0.7px Display tracking and its light fill uses the capture-equivalent 33/255 tint, producing `#EAE0CC` within one red-channel level of WPF `#E9E0CC`. Status-region MAE falls from 7.4073 to 5.5121. A 220x340 Chinese long-note capture verifies that stats ellipsize between the fixed mode pill and 38px zoom field like PaperTodo | Final mixed-DPI text-trimming audit |
| Note canvas elements | `PaperWindow.Note.cs::BuildNoteCanvasElementView`, `AppUi.NoteCanvasElementShadow` | Exact code background, fixed 13px code typography independent of note zoom, light/dark header/badge/border alphas, 22px drag header, always-editable 72x48 minimum surface, 9/7 editor padding and 15px resize grip implemented. The embedded overlay preserves the source 2px/1px bordered-page origin and fixed `CODE`, `层 N`, `顶层 N` labels. Same-data center/edge captures show WPF clips the resting effect at the element bounds; Flutter therefore omits its incompatible resting halo, while a two-layer capture verifies the compact 6px/2px selected/top-layer depth cue | Final mixed-DPI font-rendering audit |
| Context menus | `PaperWindow.cs` menu styles | 12px rounded shell, compact 36px rows, section headers and list-tile-free column actions implemented; independent Windows paper, Markdown-editor, canvas-element and Todo-item menus use the capture-verified source 17px headers, 21px text-only rows and 7px separators while board/mobile menus retain their platform affordances. Commands now paint the source 8px rounded pointer surface instead of Flutter's rectangular state layer. Header weak text and disabled command text keep separate 72% blends. Real warm-light rest/hover/pressed captures are stored as `.tmp/{papertodo-reference-,ui-}context-menu-*-light.png`; both reference and current hover/pressed pairs have zero changed pixels, while automated checks cover all four palettes in light and dark | Final mixed-DPI pointer render audit |
| Transient feedback | Paper surfaces, `TodoReminderBubbleWindow.cs` | Flutter fallback undo, sync, error and reminder snack bars use the selected PaperTodo paper surface, palette border, body text and Active action color rather than Material's dark notification surface; Windows paper reminders continue to use the native source-matched adjacent bubble and hover-paused timer. A 220px Chinese Jianguoyun 401 fixture verifies that long failure text remains bounded and Retry reflows below it without a RenderFlex overflow | Verify fallback reminders at narrow widths |
| Confirmation and recovery dialogs | `AppUi.cs`, PaperTodo paper surfaces | Paper limit, delete, restore, recovery-list, canvas-geometry, fallback due/reminder and fallback color flows use the source paper shell; fixed PaperTodo 340x176 paper-limit and 300x178 delete geometry use the title/message/action Grid proportions, and confirmation actions are compact text-only rows with source spacing and danger/active tint. Desktop paths stay single-line ellipsized, compact paths are capped at three lines, and automated focus checks cover delete/cancel, paper-limit OK, restore/close and cancel/restore loops; no default Flutter alert surfaces remain | Final Windows 10/11 shadow render audit |
| Date/time picker | `PaperWindow.Todo.cs::ShowTodoDueDialog` | 354×242 borderless rounded paper popup, themed owner-drawn buttons and source-matched single-row date/hour/minute grouping implemented in both the native picker and Flutter fallback; the native surface now reproduces the WPF full-date selection, compact `15` calendar glyph, gray combo chrome and light borders while retaining the system calendar/lists underneath. Native title/body fonts, numeric metrics and WPF-rounded palette blending are forwarded from the configured Flutter state; Cancel/Clear/OK order and keyboard behavior are covered | Visual audit on mixed-DPI monitors |
| Reminder interval picker | `PaperWindow.Todo.cs::ShowTodoReminderIntervalDialog` | 326×216 native and Flutter rounded paper popup with exact title/message hierarchy, 32px value/unit row, Cancel/Global/OK actions, source blue edit focus border, WPF-like gray unit selector, configured UI font forwarding, WPF-rounded palette blending, focus/select-all behavior, keyboard handling, theme colors and high-DPI centering implemented and covered | Final mixed-DPI render audit on Windows 10/11 |
| Reminder bubble | `TodoReminderBubbleWindow.cs` | Native 260×104 adjacent bubble with 14px shell, 28px tinted icon, active `!`, themed 13/12px text, hover-paused dismissal, tinted border and popup shadow implemented | Verify shadow softness and multi-line truncation at mixed DPI |
| Settings window | `AppController.Settings.cs::BuildSettingsWindowContent` | Separate transparent borderless 18px paper HWND with 672-792 by 520-720 logical DPI-aware sizing, native edge/corner resize and title drag, 8px active-paper underlay, exact source navigation/group wording without page-top dividers, 34px marker navigation, 12/11px group/field hierarchy, custom 28px equal-column segment selectors, 28px text fields, 52/58x26 hotkey/spacing actions, 28px/34px title stepper, exact 16px source-path toggle marks, all 40 source `WrapWithHint` rows with original bilingual text and independent 18px `ⓘ` hit targets, and 28x24 `×` close-to-save states, plus native color chooser. The added WebDAV page now follows the same 11px label-first/28px field system, compact 34x26 secret actions and 0.55 disabled treatment instead of Material floating-label fields; theme, Markdown, reminder-unit and WebDAV provider selectors retain that same label-first 28px chrome even at narrow fallback widths, and the 58x42 custom-color swatch preserves the source square WPF outline. Reminder-off and relative-date modes retain the source editor availability. Text editors use the source Active focus border, while mouse-only toggle/segment rows remain outside keyboard focus traversal like WPF; non-client layout/paint is intercepted before Flutter, and automated English/Chinese 560x360 plus real desktop screenshot checks confirm the old caption strip is absent | Visually verify resize hit targets and shadow softness on Windows 10/11 |
| Capsules | `PaperWindow.Capsule.cs`, `PaperWindow.DeepCapsule.cs`, `MasterCapsuleWindow.cs` | 30px body inside a DPI-scaled 46px host with 8px transparent chrome, source 12px radius, 21px normal and mirrored 30px deep hide areas, independent close hover/press feedback, 0.08 normal shadow, 18px shifted close glyph and exact native preset/custom palette derivation implemented. Flutter/native proxies share the source `✓` / `✎` / `⚡` glyphs, weak-text color and 26px drag target; the Flutter capsule host also exposes that target as a native caption hit. Real v2.27 captures verify ordinary Todo/Note/script windows at 93/97/91x46, deep full proxy windows at 102/106/100x46, and resting screen-visible slices at 62/65/59x46. Both collapsed HWND paths follow the source 220/180ms ease-out reveal; 16ms sampling records a 20px reveal and zero-pixel settle error. Windows policy smoke verifies stable 68px master discovery, independent queue expansion, cross-edge proxy/drop routing, fullscreen topmost removal/restoration and reminder-hover persistence | Final cross-monitor text measurement audit |
| Tray menu | `AppController.Tray.cs` | Owner-drawn menu preserves the source 190px minimum and measures 194px including the 96-DPI system shadow after compensating Win32's shell metrics; 4px shell padding, 24px rows, 22px headers, 8px hover radius, 13px visibility checks, source `✓`/`✎`/`⚡` paper icons, title-only labels, source 0.92 checked fill, grayscale antialiasing, palette/custom-accent colors and a 10px native shell radius are implemented. `.tmp/ui-tray-menu-current.png` matches the reference outer width, while `.tmp/ui-tray-menu-current-product-rounded-visible.png` proves the real `#32768` menu returns a rounded `COMPLEXREGION`; Toggle-all and Delete-paper remain available as RePaperTodo additions | Verify submenu placement and text metrics on mixed-DPI Windows 10/11 |

## Verification gates

Latest Note parity work replaces preview heading, quote and code block boxes
with source-coordinate painters. The compact Windows title uses a separate
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

The current title-bar implementation keeps the source pin/create/collapse group
right-anchored at 220/280/320/440/560px. RePaperTodo's added sync control grows
to the left of that group; Note papers use the later fit threshold so a 280px
Note keeps its source title and actions clear before sync is introduced.
