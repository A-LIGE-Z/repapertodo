# RePaperTodo Changelog

## Unreleased

- Hardened the Windows pinned-paper capsule escape path: clicking a pinned
  paper's proxy now clears desktop pinning and explicitly activates the paper
  through the foreground input queue, so synthetic/native clicks cannot leave
  another window in front.
- Fixed capsule interaction state isolation: the master capsule now changes
  only the capsule queue without hiding collapsed paper HWNDs, queue drag
  ordering ignores expanded papers that have no deep-capsule proxy, and the
  expanded-proxy click action respects the configured click-to-retract option.
- Fixed paper-header collapse synchronization: collapsing or expanding a real
  paper now reconciles its Flutter HWND and edge-capsule registry as one
  serialized operation, so repeated paper/master capsule toggles cannot leave
  a stale or missing capsule.
- Isolated Windows policy-smoke data from the user's configured storage path
  and made persistent PowerShell capsule process trees terminate immediately
  when RePaperTodo exits.
- Compressed only the settings author signature's paint layer horizontally by
  99/103 with a right anchor, preserving its hit target, right edge and source
  Segoe UI style. Its visible bounds now match `x=675..773`; the footer crop
  falls from 8.6450 MAE to 5.2134 and the controlled Display page from 1.4087
  to 1.3860. Letter-spacing and reset-button expansion experiments remained
  capture-rejected and are not retained.
- Applied the same smallest raster-effective -0.001px tracking correction to
  the 11px Todo-spacing and Note-spacing field labels without moving either
  help glyph or editor. Their crops fall from 3.3801/4.3172 MAE to
  2.9437/3.4830, and the controlled Display page from 1.4177 to 1.4087. A
  half-pixel Note-label origin experiment had no raster effect and was removed.
- Applied the smallest raster-effective -0.001px tracking correction to the
  Todo-size field label without moving its help glyph or four-way selector.
  Its crop falls from 2.7842 MAE to 2.3097, the complete selector section from
  1.2564 to 1.1987 and the controlled Display page from 1.4210 to 1.4177.
- Applied the smallest raster-effective -0.003px tracking correction to the
  fullscreen-handling field label without moving its help glyph or selector.
  Its crop falls from 7.1015 MAE to 6.0720, the complete selector section from
  2.1517 to 2.0263 and the controlled Display page from 1.4283 to 1.4210.
- Calibrated the mixed Latin/CJK `Markdown display` field label independently
  with -0.02px tracking and a +1px local WPF paint origin. Its help glyph and
  selector remain fixed. The label crop falls from 7.0405 MAE to 3.6146, its
  complete selector section from 1.8319 to 1.4071 and the controlled Display
  page from 1.4525 to 1.4283.
- Moved only the installed-font TextField's editable text upward through
  `TextAlignVertical(y: -0.4)`, preserving the exact field, suffix-chevron and
  pointer geometry. Horizontal-padding compensation was capture-rejected and
  reverted. The text crop falls from 19.4863 MAE to 17.2571, the complete font
  field from 2.7083 to 2.4034 and the controlled Display page from 1.4630 to
  1.4525.
- Applied the smallest raster-effective -0.005px WPF tracking correction to
  the 11px system-font field label without moving its already-aligned help
  glyph or row. Its crop falls from 4.4403 MAE to 3.1799, the complete font row
  from 2.2005 to 2.0470 and the controlled Display page from 1.4717 to 1.4630.
  A 12.5px secondary theme-action experiment regressed and was reverted.
- Restored the custom-theme field label from the generic 12px Material label
  to PaperTodo's 11px field hierarchy and applied the smallest raster-effective
  -0.01px tracking correction. Its height now matches the reference and its
  crop falls from 16.0691 MAE to 8.0330; the full theme-color region falls from
  8.6146 to 6.9780 and the controlled Display page from 1.5252 to 1.4717.
- Scaled only the custom-theme primary action label vertically by 12/11 with
  a local -0.5px paint origin, preserving the exact 76x27 button and hit area.
  The secondary action's scale experiment regressed and was reverted. The
  primary-button crop falls from 10.9637 MAE to 5.9010, the theme-color region
  from 9.3814 to 8.6146 and the controlled Display page from 1.5502 to 1.5252.
- Shifted the settings custom-theme current-value label left 1px independently
  from its exact swatch, buttons and row layout. The visible label now matches
  the reference `x=248..335` bounds; its crop falls from 35.7512 MAE to
  25.8897, the complete theme-color region from 10.6684 to 9.3814 and the
  controlled Display page from 1.5923 to 1.5502. A heavier weight produced an
  identical fallback-font raster, so source-semantic SemiBold is retained.
- Split the native reminder message into clipped WPF paint layers without
  changing its wrapping width or text. The first visual line retains its
  already-exact origin; subsequent lines move up 1px to reproduce WPF's line
  advance. First-line output is unchanged, second-line MAE falls from 13.5369
  to 1.9833, the message crop from 10.2934 to 4.0482 and the complete reminder
  dialog from 2.9293 to 2.0809.
- Shifted only the reminder-unit label right 1px and moved that selector font
  to WPF-like grayscale antialiasing; the due numeric controls retain their
  separately calibrated ClearType font. The unit text crop falls from 12.2798
  MAE to 9.0008, its complete selector from 3.4443 to 2.6616 and the reminder
  dialog from 2.9671 to 2.9293.
- Recalibrated only the due picker's hour/minute text boxes: their numeric
  paint boxes move up 3px and use 1px inter-character compensation, while the
  already-aligned reminder-unit label remains untouched. Hour-region MAE falls
  from 7.5071 to 3.8339, minute from 5.7361 to 2.9060, the focused numeric
  text crop from 11.0721 to 5.1642 and the complete due dialog from 2.0371 to
  1.9023.
- Embedded the authoritative 20x18 WPF light DatePicker calendar raster in the
  Windows runner and scale it with the native dialog DPI. The dark picker
  retains its palette-derived vector fallback. At 96 DPI the calendar crop is
  pixel exact (25.4884 MAE to 0.0000), the date region falls from 5.5108 to
  2.9215 and the complete due dialog from 2.2085 to 2.0371.
- Replaced the native picker selectors' low outline-V chevrons with the
  source-shaped filled 5x5 down triangles. Hour, minute and reminder-unit
  arrows now share the reference visible bounds and vertical origin. The due
  chevron crop falls from 8.2383 MAE to 6.1133 and its dialog from 2.2212 to
  2.2085; reminder chevron MAE falls from 7.4306 to 5.5313 and its dialog to
  2.9671. Larger-title experiments regressed both dialogs and were reverted.
- Moved both native picker action-label paint boxes down one logical pixel
  without changing their 64x26 buttons or pointer targets. This matches the
  reference button glyph baselines in both dialogs. Due button-region MAE
  falls from 6.1512 to 3.4323 and the whole dialog from 2.6072 to 2.2212;
  reminder buttons fall from 8.0322 to 3.6890 and the dialog to 2.9748.
  A character-spacing expansion was capture-rejected and fully reverted.
- Switched only the native due/reminder action-button fonts from RGB ClearType
  to WPF-like grayscale antialiasing. Title, body, numeric and selector fonts
  retain their capture-proven ClearType rendering. Button-region MAE falls
  from 6.9211 to 6.1512 in the due picker and from 9.2088 to 8.0322 in the
  reminder picker; complete-dialog MAE reaches 2.6072 and 3.4282 respectively.
- Replaced the native reminder value field's mismatched Win32 focus capture
  with PaperTodo's 23px WPF raster: exact `#569DE5` perimeter, 21px backing
  edit and a light-only `#95C1DC` full-selection painter that preserves the
  real editable control and keyboard behavior. The focused value crop falls
  from 13.1998 MAE to 1.2424 and the complete 326x216 dialog from 4.4226 to
  3.5510; ordinary/partial selections and dark mode retain native painting.
- Reproduced WPF's selected light date editor inside the native due picker
  instead of tinting the complete 158px DatePicker surface. The local white
  edit strip, exact `#99C9EE` selection, `#D5C8B0` frame and calibrated text
  baseline leave the calendar-button area on the paper surface. Date-region
  MAE falls from 15.3369 to 5.5108 and the complete 354x242 dialog from
  3.3451 to 2.6948; dark-mode selection behavior is unchanged.
- Recalibrated the settings top-bar-button labels without moving their marks,
  help targets or rows. A 1px left-origin correction plus WPF-like -0.075px
  tracking matches the reference `x=205..306` visible bounds; the focused
  label crop falls from 20.2553 MAE to 19.1200 and the controlled Display page
  from 1.5987 to 1.5923.
- Calibrated the light Note status-bar separator independently from its
  already-matched surface and mode pill. Its 25/255 tint reproduces the
  reference `#E0CEA7` raster color, lowering the full 440x420 Note capture
  from 3.2243 MAE to 3.2197 without changing the 26px layout or dark theme.
- Replaced Material's undersized settings dropdown icon with a dedicated WPF
  filled chevron painter. Its 18px layout slot and 30px suffix hit area stay
  unchanged, while the visible triangle matches the reference 10x5 bounds
  `x=743..752, y=282..286`. Integer-snapped top coverage lowers the arrow crop
  from 22.3690 MAE to 1.3492 and the full font-dropdown crop from 2.6160 to
  0.4362; compact settings dropdowns share the same source glyph.
- Applied the same -0.5px/+0.5px WPF paint origin to settings group headings
  and field labels while leaving help glyphs and control geometry fixed.
  Todo/Notes settings MAE falls from 2.0991 to 2.0025, Display from 1.6510 to
  1.6017, General from 2.7551 to 2.6297 and Capsules from 1.5705 to 1.5623.
  Capsule glyph size/offset experiments were capture-rejected and fully
  reverted, preserving the prior best capsule rendering.
- Applied a shared -0.5px WPF paint origin to settings checkbox titles while
  leaving their 16px marks, 8px gap, help icons and hit targets unchanged.
  The separately calibrated top-bar-button labels compensate locally. Enabled
  Todo/Notes labels now begin on the reference `x=204`; page MAE falls from
  2.1921 to 2.0991, General from 2.8232 to 2.7551, Capsules from 1.6342 to
  1.5705 and Display from 1.7179 to 1.6510.
- Matched WPF's checked-settings-box background inset independently from the
  unchanged 16x16 unchecked border and hit target. Whole-pixel snapping keeps
  the active fill on the exact `x=182..193, y=96..107` 12x12 bounds while the
  source check path remains untouched. Todo/Notes settings MAE falls from
  2.2063 to 2.1921, General from 2.9321 to 2.8232 and Capsules from 1.7370 to
  1.6342.
- Unified the Windows settings shell's source padding to 16/14/16/16 instead
  of splitting its right inset between the shell and content. Form geometry
  stays fixed while the close surface returns to the WPF title grid. Local
  title and close-glyph paint origins plus capture-calibrated title tracking
  lower title MAE from 6.8778 to 2.2874, close-region MAE from 1.2506 to
  0.6608 and the complete header from 1.5974 to 0.5486 without changing drag
  or click hit targets.
- Corrected the settings content right inset from 14px to 13px, matching the
  source `x=762` right edge across segment selectors, fields, buttons and all
  help glyphs while leaving the scrollbar fixed. The custom-theme label alone
  receives a +2px WPF paint-origin correction, aligning its help glyph to
  `x=749..758, y=163..172` without moving the already-exact swatch. Display
  settings MAE falls from 1.9935 to 1.7179 (form crop 2.1021 to 1.8525),
  Capsules from 1.8532 to 1.7370 and General from 3.1091 to 2.9321.
- Aligned the settings navigation group to WPF's paint origin and restored
  the separator's source 55%-opacity paper-border composite. The selected
  Display item now matches `x=17..150, y=59..92`; the divider matches
  `x=163, y=59..673`, its `#EEE1C6` color and all 615 source pixels exactly,
  reducing the divider crop to 0.0000 MAE. The pure-English author signature
  explicitly retains PaperTodo's Segoe UI-first family.
- Restored PaperTodo's fixed WPF scrollbar resources globally: rest uses
  `#B39B74` at 34% opacity, hover uses `#96784F` at 54%, and drag uses the
  same hover color at 64%. The settings scrollbar also reproduces the source
  9px main-axis and 3px cross-axis margins, matching the reference
  `x=768..772, y=61..626` bounds and primary pixel count. Its crop falls from
  15.7650 MAE to 0.0056 and the Display page reaches 1.9782 in the controlled
  capture. Long-note scrollbar color now matches the same reference pixel
  exactly without changing its scroll extent.
- Restored PaperTodo's exact bilingual wording for the settings top-bar
  controls (`Show new todo/note button` and `显示新建待办/笔记按钮`). Their
  scroll-region text receives a local WPF paint-origin/tracking correction
  without changing the shared checkbox style. The visible label crop falls
  from 14.4809 MAE to 10.9107 and the full Display settings capture from
  2.2797 to 2.2248 while the theme swatch remains pixel exact.
- Removed anti-aliased clipping from the 58x42 settings theme swatch. Its
  WPF square border and fill now match every pixel in the reference crop,
  reducing that crop to 0.0000 MAE and the full Display settings capture from
  2.4208 to 2.2797.
- Restored the WPF-style light gradient on the native Windows due-time hour,
  minute and reminder-unit selectors. The reminder selector now paints a
  23px control inside a 27px cover surface, hiding the underlying Win32
  ComboBox shadow that previously leaked below it. Due-dialog MAE falls from
  3.4818 to 3.3451 (selector crop 6.5102 to 4.4200), while reminder-dialog MAE
  falls from 4.8353 to 4.4226 (selector crop 10.9352 to 3.2398).
- Calibrated fenced-code row joins separately for the opening, middle and
  closing visual lines. Their backgrounds now accumulate WPF's fractional
  line origins without moving the code text or changing layout height, and
  the light border uses the capture-equivalent 69/255 tint instead of the
  source alpha's darker Flutter composite. The focused code crop falls from
  3.6370 MAE to 2.0563 and the full 440x420 Note capture from 3.4024 to
  3.2243.
- Snapped the Markdown heading underline to WPF's actual raster row without
  moving the already-aligned heading text, fill or document flow. The default
  440x420 heading crop falls from 13.2577 MAE to 3.9864, its underline-only
  crop falls from 48.4015 to 0.1910, and the full capture falls from 3.8576
  to 3.4024.
- Extended Markdown code backgrounds independently of their already-aligned
  text. Each fenced row now bleeds one raster pixel above and below its local
  preview line box, matching the reference block's `y=281..331` extent while
  preserving text origins, wrapping and scroll height. In the focused code
  crop, MAE falls from 4.6960 to 3.6370.
- Refined the Note status mode pill after separating text and fill error. Its
  light fill now uses the capture-equivalent 33/255 tint (the resulting pixel
  is `#EAE0CC` versus WPF `#E9E0CC`) and the two-character label uses 0.7px
  Display tracking while retaining the 42px slot and exact vertical origin.
  Status-region MAE falls again from 5.5392 to 5.5121; blank status-bar areas
  remain effectively identical.
- Tightened Markdown block surfaces after the text metrics pass. Heading and
  quote fills now use 1px/8px left/right insets, quotes trim one trailing
  raster row with a 4px radius, and code fills use 4px/11px insets so their
  1px border no longer leaks left while the right edge remains fixed. These
  geometry corrections lower the same Note-body MAE further from 4.5148 to
  4.4759 and are shared by every preview palette.
- Matched the default Note preview's WPF visual-line origins without changing
  document flow, wrapping or scroll extent. H1 paints at -1px/+2px; quotes at
  -1px/0; the first item in each list run at 0/-2px; code fences and code rows
  at 0/-2px. Element-specific Display tracking is -0.09px for paragraphs,
  +0.05px for quotes, -0.075px for lists and +0.4px for Cascadia code. The
  same-data 440x420 capture now matches the H1, first-list and code bounds
  exactly; quote ends within 1px and paragraph within 1px. Note-body MAE falls
  from 6.9290 to 4.4759 while long wrapping, link hit testing and editor/preview
  viewport behavior remain covered.
- Calibrated the Note paper grid and status typography against the 440x420
  v2.27 capture. The 24px grid now uses the source phase (vertical +1px,
  horizontal -1px), a crisp one-pixel raster and WPF coverage-equivalent
  18/255 light and 24/255 dark line alpha; visible light grid pixels differ
  by at most one channel level. Status statistics use a +2px/-2px WPF origin
  with 0.05px tracking, matching the reference `x=72..176, y=393..403`
  bounds, while the zoom field moves up 1px. Status-region MAE falls from
  7.4073 to 5.5392 without changing the 42px mode pill, 38px zoom slot or
  narrow-width ellipsis layout.
- Aligned the title-leading `☑` / `✎` topmost glyphs to WPF without replacing
  their scalable font rendering. A shared +1px/+1px content-origin correction
  makes the inactive Todo glyph occupy the exact reference
  `x=23..32, y=23..31` bounds while preserving 0.58 rest opacity, hover,
  active SemiBold weight and DPI scaling. Todo leading-region MAE falls from
  6.8807 to 2.2503 light and 4.7416 to 1.3978 dark; the same correction lowers
  the 440px Note leading region from 4.3716 to 3.2138.
- Calibrated the remaining source Symbol actions independently instead of
  moving their 28x24 hit slots. `＋✓` now uses a -1px/+1px paint origin and
  -0.5px pair tracking; `＋✎` uses the same origin with -0.75px tracking; the
  collapse `─` uses a -1px/+1px origin and now occupies the exact reference
  eight-by-two pixel grid. Light/dark MAE falls to 3.5468/2.7212 for New Todo,
  2.0558/1.5727 for New Note, and 0.2990/0.2501 for collapse, while button
  geometry, hover feedback and responsive breakpoints remain unchanged.
- Restored PaperTodo's exact standalone title-row vertical allocation and
  desktop-pin rasterization. The header now uses the source `6,5,8,1` inset
  distribution instead of centering its six vertical pixels, while the title
  text compensates internally so its already matched glyph bounds do not
  move. The unchanged source `pin.png`/`unpin.png` assets now use 15px low
  filtering and a -2px WPF content-origin correction rather than a blurred
  medium-quality mipmap. Their visible bounds match `x=152..162, y=18..32`;
  pin-region MAE falls from 12.7773 to 0.1945 light and 2.7072 to 0.3662 dark.
- Corrected the standalone Todo checkbox's WPF corner geometry. The Flutter
  painter previously subtracted half the 1.5px stroke from the declared 4px
  radius a second time, producing a visibly square outline. Its inset stroke
  centerline now uses the capture-calibrated 4.75px radius while preserving
  the source 16px extent, colors and checked/hover paths. In the 280x340 rest
  capture, checkbox-region MAE falls from 3.2836 to 1.9979 light and from
  2.4664 to 1.5295 dark.
- Calibrated Todo editor content origins without changing row or wrapping
  widths. Main columns now redistribute the source-equivalent 4px horizontal
  and 6px vertical padding to compensate for Skia's different Segoe UI side
  bearing/baseline; extra columns apply the same 2px/1px correction while
  preserving their total insets. A -0.0625px WPF Display tracking correction
  keeps Latin advances aligned without touching the separately calibrated
  DengXian path. In fresh 280x340 captures, the Todo-row MAE falls from
  3.5468 to 2.1121 in light mode and from 4.2212 to 2.0770 in dark mode;
  long multi-column, due-row and all four visual-size layouts still pass.
- Calibrated compact Windows paper titles against the same-size v2.27
  captures instead of accepting Flutter's default font origin. Static and
  editable title layers now share the WPF Display-style 1px horizontal/3px
  vertical paint offset and -0.1px tracking, so switching into title editing
  cannot jump. `Todo1` now occupies the reference `x=44..71, y=22..29` dark
  glyph bounds; title-band MAE fell from 5.9994 to 3.4789 in dark mode and
  from 7.5104 to 5.3681 in light mode.
- Reproduced PaperTodo's native bottom-right resize grip pixel-for-pixel.
  The previous six solid Flutter squares are replaced by the source Windows
  four-row triangular grid with ten 2x2 points and its exact four-channel
  cool gray-blue antialias palette. A fresh 280x340 dark capture now matches
  all 40 reference grip pixels with zero channel error.
- Rebuilt the WebDAV settings page with PaperTodo's native settings rhythm
  instead of Material form chrome. Endpoint, remote path, credentials,
  passphrase and timing values now use 11px label-first rows with exact 28px
  rounded fields, no decorative prefix icons, compact 34x26 secret toggles,
  source-like focus/error borders and the same 0.55 disabled treatment as the
  rest of the settings window. Existing validation, password visibility,
  preset selection and keyboard behavior are preserved.
- Removed the last narrow-window Material form fallback from settings choice
  controls. Theme, Markdown, reminder-unit and WebDAV provider selectors now
  retain PaperTodo's external 11px label and 28px bordered control at compact
  widths, without floating labels or decorative prefix icons. The custom
  theme swatch also restores the source WPF button's square 58x42 outline.
- Matched the native Windows due-time and reminder interval pickers to
  PaperTodo's configured UI font chain. Chinese defaults now use Microsoft
  YaHei UI while date and interval numerals retain Segoe UI metrics; explicit
  system, preset and runtime fonts are forwarded consistently from Flutter.
  Native title sizing and content origins were recalibrated against v2.27,
  and the picker color bridge now uses WPF's separately rounded 8-bit alpha
  premultiplication so light and dark input/button surfaces keep their source
  pixels across all palettes.
- Removed the Windows 11 white non-client frame around expanded papers and
  restored PaperTodo's restrained outer depth with a dedicated non-activating,
  click-through per-pixel-alpha shadow HWND. Expanded Flutter papers no longer
  stack a second framework shadow, their 18px shell uses a hard outer clip, and
  four 1px color-key guards remove the dark antialias fringe at the inner edge
  of the 8px transparent chrome. Real desktop-composited light/dark captures
  now match the v2.27 shadow edge within 0-2 channel levels. The shadow follows
  move, resize, theme, visibility, capsule, desktop-pin and topmost changes and
  is excluded from covered-window detection.
- Hardened capsule and fullscreen window policy around the new native chrome.
  Fullscreen detection now accepts DWM-visible or raw windows that cover the
  monitor even when an invisible resize frame extends beyond it, and collapsed
  papers revoke `WS_EX_TOPMOST` before policy hiding. The capsule's existing
  26px leading drag target also exposes a native caption hit so Windows can
  start movement without depending solely on a Flutter pointer callback.
  Windows policy smoke now ignores shadow hosts, waits for stable 34px-or-wider
  master capsules, preserves failure LOG/state artifacts and verifies queue
  expansion, proxy routing, reminder hover, fullscreen restore, geometry
  stability, cross-edge drops, tray recovery and long-running scripts.
- Restored PaperTodo's 8px rounded pointer surface inside Windows paper,
  Todo-item, Markdown and canvas context menus. Flutter no longer paints a
  rectangular Material state layer behind compact commands, and mouse-down no
  longer stacks a second tint over the existing hover color. Paired real-window
  captures now show zero changed pixels between hover and press, matching the
  v2.27 reference; all four palettes in light and dark are covered by widget
  tests. A 220px Chinese Jianguoyun authentication failure also verifies that
  long feedback and its Retry action remain inside the paper and reflow onto
  separate rows.
- Calibrated PaperTodo's legacy Windows font presets with real Chinese
  reference captures. YaHei now reuses the source-identical default Windows
  chain instead of triggering Skia's wider explicit fallback, while DengXian
  keeps its selected glyphs with a `12.5/13` WPF Display-mode advance
  correction and unchanged line-box height. Compact recovery rows now cap long
  snapshot paths at three ellipsized lines, and automated focus checks cover
  the restore-list and restore-confirmation Tab loops.
- Corrected Markdown enhanced-preview list geometry against PaperTodo v2.27:
  hidden `- ` markers use the source-width span, bullets are centered on the
  first visual line after wrapping, and long list items now break at the same
  words as the reference. Canvas overlays now honor the source 2px/1px inner
  border origin, and code-block chrome restores PaperTodo's fixed `CODE`,
  `层 N`, `顶层 N`, and `CODE · 层 N` labels in every locale.
- Completed another Windows long-content parity pass. Todo papers now show the
  same always-visible auto scrollbar when their rows overflow, with the source
  7px end margins and edge placement; long multi-column rows vertically center
  shorter columns, checkboxes and drag handles against the tallest wrapped
  column, and every extra column remains transparent instead of inheriting a
  generic text-field fill. Long Markdown preview and editor views now expose
  the same automatic scrollbar and retain their viewport when switching modes.
  Title editing no longer paints the static title underneath the focused text
  field, eliminating the doubled text weight and transition flash.
- Recalibrated Note canvas block depth against real v2.27 pixels. Resting
  single-layer blocks no longer carry Flutter's oversized gray blur halo;
  selected and top-layer blocks keep a restrained depth cue while edge blocks
  remain clipped by the paper page exactly like PaperTodo.
- Calibrated all three Windows capsule rendering paths against PaperTodo
  v2.27 captures. Ordinary Todo/Note capsules now use source-matched title and
  symbol baselines; expanded-paper native proxies apply the WPF/GDI advance
  corrections and measure `102/106/100x46` for the shared `Todo1` fixture,
  while their resting visible slices match `62/65/59x46`. Native proxy text
  uses grayscale antialiasing and the weak-text icon color. Collapsed deep
  capsules now animate their edge reveal over the same 220ms/180ms ease-out
  durations as native proxies instead of jumping horizontally; real HWND
  sampling verifies both paths reveal exactly 20px and return to the screen
  edge with zero endpoint error.
- Unified Flutter fallback feedback with PaperTodo's paper language. Undo,
  sync and error snack bars now use the active paper surface, palette border,
  body text and Active action color instead of Material's dark floating bar.
  Confirmation and recovery dialogs now use PaperTodo's lighter 24/26px
  floating shadow, while the fixed paper-limit dialog retains its source 18px
  compact shadow. Windows native reminder bubbles keep their existing
  source-matched rendering and behavior.
- Recalibrated Windows paper, Markdown and canvas context menus against the
  original PaperTodo pixels. Desktop command rows now use the source 21px
  visual rhythm and 17px section headers, standalone separators use 7px, and
  canvas menus no longer insert a separator directly below their title. Menu
  headers blend weak text at 72% (`#AB9D88` in the warm light palette), disabled
  commands blend body text at 72% (`#6C6357`), and pressed menu feedback stays
  on the same 32/48-alpha hover surface as PaperTodo.
- Reconciled the Windows tray menu with PaperTodo's native footprint. The
  owner-drawn shell now measures 194px on a 96-DPI desktop (the source menu's
  190px minimum plus its native shell), uses the source compact text metrics
  and 72% disabled-header weak color, and renders paper titles without a
  duplicated type prefix. Todo, Note and script paper rows now use the source
  `✓`, `✎` and `⚡` symbols. GDI text now uses grayscale antialiasing instead of
  colored ClearType fringes on the popup, checked rows use the source 0.92
  active fill, and a menu-lifetime chrome worker applies the 10px rounded
  region after Win32 creates each real menu/submenu window. The required
  Toggle-all and Delete-paper commands remain available in the RePaperTodo
  menu.
- Replaced the remaining classic Win32 field chrome in the native Todo due
  and reminder dialogs with PaperTodo-matched surfaces. The due picker now
  keeps the original full-date selection, compact `15` calendar glyph and
  WPF-like hour/minute combo appearance while retaining the system calendar
  and drop-down lists underneath. The reminder interval editor now uses the
  source blue focus border and matching unit selector without changing its
  native keyboard and selection behavior.
- Restored PaperTodo's compact due-time badge rendering on Windows. Chinese
  relative durations now use the original day/hour/minute wording without
  added spaces, both relative and absolute badges size to their text instead
  of reserving a wide empty slot, the absolute badge again paints its Tint
  surface, and its press state uses the source 0.72 whole-badge opacity.
  Narrow Windows papers no longer hide the relative badge, and ordinary,
  short-year and full-year dates use the source `M/d`, `yy年M/d` and
  `yyyy年M/d` labels.
- Matched PaperTodo's multi-column Todo row geometry in real Windows captures:
  the active 14/14/16/19px reorder handles now sit inside the original
  18/18/20/23px trailing grid slots, restoring the text-column width previously
  lost by 4px. Column separators now use one non-antialiased PaperBorder pixel
  at 0.9 opacity with exact 4px vertical insets instead of a rounded 72%-height
  line, and the `≡` glyph uses PaperTodo's Segoe UI Symbol family.
- Matched the Windows resize affordance to PaperTodo's system-style cool
  blue-gray grip across light and dark paper themes, instead of tinting the
  grip with each paper's active accent color.
- Restored PaperTodo's source-width Todo canvas and capsule title metrics:
  independent Todo rows and the append area now use the original compact
  horizontal insets, while capsule icons use their rendered advance width so
  short titles no longer ellipsize early without shrinking the drag target.
- Restored the paper shell's full palette border color instead of applying a
  second transparency pass that made every light and dark paper outline too
  faint.
- Corrected the Windows title-bar divider compositing so it matches the
  original paper-over-tint pixel color rather than darkening twice over the
  already tinted title background.
- Restored PaperTodo Markdown's natural font-metric line height: note preview
  lines now use the configured spacing as a minimum, so blank lines, quotes,
  lists and fenced code keep the original vertical rhythm.
- Matched the captured Note page's horizontal rhythm without narrowing its
  text viewport: content starts two pixels farther from the binding line while
  heading, quote and code backgrounds end eight pixels before the text edge.
  Preview body clicks and inline links retain separate gesture handling.
- Replaced the Windows runner's estimated capsule title width with DPI-aware
  GDI measurement using the active PaperTodo UI font. Normal Todo, Note and
  script capsules now match v2.27's captured `93x46`, `97x46` and `91x46`
  geometry for the same `Todo1` title, while short titles retain the original
  76px minimum.
- Refined the Windows paper chrome and capsule glyph language against the
  current PaperTodo source. Title-bar creation actions now use the original
  compact `＋✓` / `＋✎` symbols with 32/48-alpha hover feedback instead of
  heavier Material creation icons. Normal capsules now keep the source 12px
  radius, 21px hide area, 0.08 shadow, `✓` / `✎` / `⚡` type glyphs and 18px
  `×`; native deep-capsule proxies distinguish Note and script papers with the
  same glyphs at DPI-scaled 13/15px sizes. Deep capsules now mirror the original
  30px edge-side close area, keep close hover/press feedback independent from
  the paper action, derive every native palette and custom accent exactly, and
  measure the selected Windows font plus symbol glyphs through GDI before
  applying the original 34/54px resting/hover reveal limits.
- Restored PaperTodo's original 15px `pin.png` / `unpin.png` title-bar assets
  and their 0.72 inactive opacity. Legacy YaHei and DengXian presets now keep
  `Segoe UI` first and use the source-ordered CJK fallbacks, preserving the
  original Latin label and control metrics.
- Removed non-source hover interpolation from the Windows title host and Todo
  rows, keeping pointer feedback immediate while retaining PaperTodo's timed
  completion, insertion, deletion and capsule geometry transitions.
- Replaced the remaining Material glyphs in Windows Todo append/trash and
  compact linked-note controls with PaperTodo's original symbol-font glyphs,
  sizing, and script-label spacing.
- Separated PaperTodo's default note content typography from UI chrome:
  Markdown and non-code canvas text now use the original Microsoft YaHei
  UI-first content chain while titles, menus and controls keep UI metrics.
- Matched Windows title-button pointer states exactly: hover now promotes weak
  symbols to paper text, and press uses PaperTodo's 0.7 whole-button opacity
  over the same hover tint without a Material ripple or stronger state layer.
- Replaced the Windows Todo Material checkbox with PaperTodo's exact 16px
  rounded checkbox, source check-path geometry, 1.5px border and independent
  unchecked/checked hover colors.
- Replaced Material settings checkbox tiles and the close icon with
  PaperTodo's compact 16px source-path toggle rows, 0.55 disabled state and
  28x24 `×` hover/Active close-button treatment.
- Restored all 40 PaperTodo settings explanations with the original Chinese
  and English resource text, trailing 18px `ⓘ` controls, 200ms hover delay and
  20-second tooltip duration. Help controls remain usable for disabled options
  and no longer share a toggle's click target.
- Replaced the remaining desktop Material settings choices with PaperTodo's
  28px equal-column segment selector and rebuilt the title-length stepper at
  its exact 28px/34px metrics. Settings pages now use the source navigation and
  group wording without page-top dividers; hotkey, line-spacing, reminder and
  extension editors use source-sized label-first fields and separate compact
  actions. Reminder-off and relative-date modes no longer disable settings the
  original app leaves editable. The source `Designed by trigger` footer again
  has its hover state, URL tooltip and platform-routed click action.
- Matched PaperTodo's Todo append/trash transformation and row state details:
  the footer now uses the original tint and danger alpha levels, glyph sizes,
  margins and highlighted 1.5px border; multi-column rows no longer gain an
  extra bottom inset; completed rows settle at 0.75 opacity with the original
  full-column 1.35px completion rule; and due badges use the source 10-minute
  urgency threshold, compact padding, minimum metrics and hover colors without
  truncating the absolute date. Todo checkboxes now keep the source fixed 16px
  size and 1.5px/4px outline, the right drag handle uses the compact 0.48/0.78
  `≡` treatment with whole-row 0.25 drag feedback, and linked-note buttons use
  the source checkbox-column sizing plus exact rest, hover and press states.
  Their single/multiline title metrics now follow the rendered Todo line count,
  including automatic wrapping, with stable hysteresis at the 44/50px boundary.
- Restored PaperTodo Note toolbar/status density: the canvas toolbar is 31px
  with a 28x24 `{}` action, source 13px weak-text/hover/0.7-press states and
  one-line element counts; the 26px status bar keeps its 42px mode pill and
  38px zoom field, with scale-down protection for narrow fonts so `100%` never
  grows the bar.
- Restored the current PaperTodo Windows title bar at its real default widths:
  the leading topmost control now uses PaperTodo's exact `☑` Todo and `✎` Note
  symbols with the original weak 0.58/hover opacity; the 38-86px title host keeps
  its bottom divider, asymmetric padding and hover paper tint; action buttons
  regain their one-pixel gaps and source order. The 220px Todo now retains
  desktop pin, new Todo, new Note and collapse exactly like v2.27, while the
  190px stress width still keeps only collapse/hide. The added sync button sits
  to the left of the complete PaperTodo action group, so appearing at 280px does
  not move the source controls away from the right edge. Notes use a separate
  fit threshold: 280px preserves the full source title/actions without sync,
  while the default 320px Note has room for the extension without truncation.
- Replaced the generic rendered Markdown preview with PaperTodo's source-first
  note renderer. Basic mode keeps active-color syntax markers; Enhanced preview
  fades syntax, hides quote/list markers and redraws list bullets while keeping
  the original source selectable. Heading typography, inline emphasis, links,
  source-like images/tables, horizontal rules, quotes and fenced code now use
  the current PaperTodo metrics and semantic colors. The editable source uses
  the same syntax model, falls back to native spans during IME composition, and
  keeps full-line quote/code backgrounds aligned while the editor scrolls.
- Split the Flutter theme into PaperTodo's original semantic colors instead of
  reusing Material `primary` for every accent: Active, Tint, Danger, Link,
  CheckBox and QuoteBorder now retain their independent light/dark values and
  custom-accent derivation. Paper headers, Todo hover/drop/append/link/due
  surfaces, Note canvas chrome, Markdown links/quotes/code, completed Todo
  text, reminder bubbles, settings navigation and checkbox interaction states
  now consume the same bases and alpha levels as the current PaperTodo source.
- Corrected Note paper chrome to the current PaperTodo source: the status bar
  now keeps its fixed 42px mode pill and read-only 38px zoom field, non-default
  zoom exposes a separate 10.5px/55%-opacity reset overlay, and even 72x48
  canvas blocks retain their real editor instead of becoming a one-line
  summary. Canvas block fonts, header/badge padding, and directional
  light/dark layer shadows now use `NoteTypography` and
  `AppUi.NoteCanvasElementShadow` metrics; the note page also restores the
  source 24/12/14/12 content margins, 104/88 binding tint and separate
  28/34 canvas-border tint without double-padding Markdown preview content.
- Restored PaperTodo's Todo-row motion language: newly inserted rows now fade
  and rise over 250 ms, multi-line paste rows use the original 40 ms stagger
  with separate 200/220 ms fade/slide timing, single deletes fade and slide
  right over 200 ms, and Clear completed uses the source 30 ms stagger with
  180 ms departures while applying data and undo state immediately.
- Rebuilt the Windows settings host as PaperTodo's transparent borderless
  paper window: its 672-792 by 520-720 logical sizing now follows monitor DPI,
  it stays out of the taskbar and window switcher, supports native edge/corner
  resizing and title dragging, and no longer leaves an opaque system-window
  canvas around the rounded settings sheet. The coordinator now intercepts
  non-client layout and paint before Flutter can restore the creation-time
  caption, clears stale native titles on every reveal, and fills the 8px
  shadow chrome with the active paper color so the settings page is a single
  rounded sheet rather than a sheet inside a blue system frame.
- Restored PaperTodo's 8px transparent shadow chrome around standalone paper
  HWNDs and 30px capsule bodies inside their 46px hosts, with native paper and
  capsule metrics now scaled from logical pixels on the active monitor.
- Reorganized the settings window to match PaperTodo's current Display,
  Todo/Note, Capsule and General grouping, removed inactive/internal controls
  from the visible UI, replaced Material sliders and selected-segment marks
  with compact PaperTodo fields and steppers, removed decorative toggle icons,
  and made both English and Chinese layouts fit the 560x360 minimum window.
- Replaced every remaining default Flutter alert surface with the shared
  rounded paper dialog shell, including cross-platform due, reminder and color
  picker fallbacks.
- Replaced the Windows custom-theme HSV popup with PaperTodo's native expanded
  color chooser, rebuilt delete/recovery/canvas-geometry dialogs as rounded
  paper surfaces, made long settings choices switch to compact selectors based
  on their real available width, and aligned menu hover/focus feedback with the
  original light/dark tint strengths.
- Replaced the default rectangular Windows tray menu with a PaperTodo-style
  owner-drawn menu: compact 24px rows, 22px headers, custom 13px visibility
  checks and paper icons, themed hover/submenu states, high-DPI sizing, and a
  rounded Windows 10/11 menu shell now follow the active palette and custom
  accent.
- Kept multi-column Todo rows readable at 220-320px paper widths by using
  PaperTodo's narrower checkbox/drag columns, constraining the absolute due
  badge, and revealing the separate relative-time badge only when the paper
  has enough width for its columns.
- Rebuilt the Windows per-item reminder interval editor as PaperTodo's
  326x216 native rounded paper dialog, including the compact value/unit row,
  Global/Cancel/OK actions, keyboard handling, theme colors and high-DPI
  placement; the Flutter dialog remains available outside standalone Windows
  paper windows.
- Corrected the native due dialog's 12px shell radius and refined reminder
  bubbles with PaperTodo's separate subtle icon tint, active exclamation,
  stronger tinted border and native popup shadow.
- Reframed Windows papers as the HWND itself instead of an inset card: the
  paper now fills the native window, header and body share one continuous
  surface, note editing no longer nests a second paper, and todo rows use quiet
  ruled separation.
- Rebuilt responsive paper chrome around actual available width, with distinct
  always-on-top and desktop-pin affordances and only the essential trailing
  action at minimum width.
- Removed the legacy Flutter path that replaced a queue's first real paper with
  the master capsule; the master is now exclusively an independent native HWND.
- Tightened the Android product boundary by ignoring Windows collapse/pin
  presentation and removing capsule, topmost, desktop-pin, and window-geometry
  actions from mobile paper UI.
- Rerouted stale Windows capsule collapse events for desktop-pinned papers to
  the authoritative unpin-and-activate path, preventing proxy refresh races
  from collapsing a pinned paper behind the desktop.
- Decoupled master-capsule retraction from paper rendering, made desktop-pin
  capsule activation restore the paper directly to the foreground, removed the
  duplicate Windows due picker, and progressively reveal paper-header actions
  as the paper grows.
- Made capsule configuration Windows-local: Android no longer exposes capsule
  controls, and WebDAV snapshots and operations no longer transfer capsule
  layout or collapsed state while still consuming compatible historical logs;
  capsule-only operation slots now serialize as validated empty-setting no-ops
  so device sequences remain contiguous without leaking Windows presentation
  state or causing false WebDAV 412 conflicts.
- Unified Windows papers into a softer rounded paper surface and removed the
  competing Flutter cross-fade from native paper-window transitions.
- Matched PaperTodo's paper hierarchy more closely with a solid 18px paper
  shell, lightly tinted title strip, compact title-edit focus treatment,
  theme-aware scrollbars and controls, split due badges, and local-only Todo
  hover/completion transitions.
- Rebuilt Note papers around PaperTodo's fixed canvas toolbar and status bar,
  gridded outer canvas, inset paper page, binding line, in-page overlay blocks,
  compact block headers, layered shadows, and corner resize grips; Markdown
  formatting now stays in shortcuts and the editor context menu as upstream.
- Kept capsules visible while hovered, restored per-paper capsule click
  behavior for pinned and unpinned papers, and ensured the master capsule only
  collapses or expands the capsule queue without changing paper state.
- Prevented desktop-pinned papers from flashing on ordinary clicks by keeping
  no-activate behavior without repeatedly rewriting their Z order.
- Matched PaperTodo's capsule queue behavior: dragging a master moves its
  visible queue, individual capsules can be reordered, master collapse/expand
  affects capsules only, and opening a paper keeps its edge capsule available.
- Create the seven-day `LOG` diagnostics folder as soon as the configured data
  directory is resolved, including before state loading completes.
- Added a separate native Windows date/time picker window and tightened the
  right-edge due badge so relative and absolute due information stays readable.
- Restored normal Windows edge and corner resizing for both Todo and Note paper
  HWNDs by starting the native resize loop immediately on pointer-down and
  widening the visible resize target.
- Fixed desktop-pinned papers disappearing behind the Windows 11 wallpaper by
  keeping them as interactive top-level windows at `HWND_BOTTOM` instead of
  reparenting them into an unreliable `WorkerW` desktop layer.
- Locked desktop-pinned papers to the bottom layer without activation or
  dragging, leaving only the unpin control interactive and preventing the Todo
  header checkbox from accidentally unpinning the paper.
- Kept paper chrome anchored during native resizing, made capsules start native
  dragging on pointer-down, and removed the double-click and flash races when a
  capsule restores its paper.
- Moved Windows settings onto the hidden coordinator's dedicated window,
  removed paper taskbar buttons, and refresh capsule fullscreen hiding every
  250 ms for prompt restoration.
- Added a native Windows folder picker for first-run and settings-driven data
  directory selection with safe state relocation; Windows packaging remains the
  conventional release directory/zip containing the EXE and Flutter runtime.
- Added app-local MSVC and Universal CRT runtime libraries to Windows builds so
  the packaged application starts on Windows 10 without requiring a separately
  installed Visual C++ Redistributable.
- Reworked the Windows ZIP so its root contains only `repapertodo.exe`; a
  dependency-free launcher starts the Flutter executable and complete runtime
  from the nested `runtime/` directory.
- Fixed collapse-all queues and tray Show all by clearing stale queue state,
  restoring every paper in one native reconciliation, and routing capsule
  clicks by stable queue/paper identity.
- Added redacted daily text diagnostics under the data directory's `LOG`
  folder for settings, paper, application, and sync events, with automatic
  seven-day retention on Windows and Android.
- Added a manual sync action to every paper header and clarified that
  Jianguoyun requires its generated WebDAV app password rather than the account
  login password; authentication failures now give a provider-specific recovery
  message.
- Kept Todo columns in one row at compact paper widths with divider-only
  separation, and replaced large due-date dialogs/chips with a compact
  date-time selector and right-aligned relative/absolute due status.

- Made Jianguoyun conditional manifest updates compatible with its unquoted
  opaque ETags: sync still tries the standard quoted `If-Match` first, then
  retries the provider's original conditional value only after a 412, without
  ever falling back to an unconditional overwrite.
- Validate Jianguoyun's 30-character sandbox-name limit directly in WebDAV
  settings, with a focused inline recovery message instead of exposing a raw
  provider XML error only after sync starts.
- Reset stale durable outbox and remote device-sequence progress when the
  WebDAV endpoint, account, encryption passphrase, or remote folder changes,
  preventing a new sync target from entering a permanent conflict loop.
- Reworked the Android board around one PaperTodo paper surface instead of
  nested cards: compact 52px navigation, integrated 56px paper headers,
  borderless todo rows, an original-style plus append surface with compact
  undo/redo controls, a darker neutral desktop canvas, 44-48px touch targets,
  and the same phone layout in portrait and landscape across light and dark
  themes.
- Restored PaperTodo's persistent settings category rail with independently
  scrollable display, todo/note, capsule, general, and WebDAV sections; compact
  windows retain icon-sized 48px navigation targets.
- Removed the retired font-preset selector from settings and now expose only
  the installed-system-font picker while preserving legacy preset data during
  migration.
- Replaced the raw custom-theme hex field with PaperTodo's swatch/current
  color/choose/reset interaction and a cross-platform full-gamut HSV picker.
- Replaced line-spacing sliders with keyboard-editable todo/note fields,
  explicit default reset controls, and the original 0.8-5.0 bounds.
- Made collapsed paper windows adapt to the rendered title length and matched
  PaperTodo's title-only resting viewport plus partial hover reveal for deep
  capsules instead of forcing every capsule to a fixed 92px width.
- Routed Windows todo reminders to the independent paper that owns the item;
  the hidden coordinator no longer emits invisible reminders and sibling paper
  engines no longer duplicate the same reminder.
- Replaced in-paper Windows reminder snackbars with compact native bubbles
  positioned beside the owning paper or capsule; hovering pauses dismissal and
  clicking opens the due todo paper.
- Added native deep-capsule drop routing so capsules can be dragged between
  monitor edges and reordered inside a queue without overwriting the paper's
  normal saved position or size; master-capsule drags update queue start height.
- Added lightweight native master capsules that remain in slot 0 while queues
  are expanded or retracted, plus edge proxies for expanded papers; proxy
  clicks activate or collapse their paper according to the PaperTodo setting,
  and proxy drags preserve normal cross-edge queue reordering without creating
  additional Flutter engines.
- Made expanded-paper native proxy clicks activate their owning HWND
  synchronously during the Windows mouse event, before the action crosses the
  Dart platform channel, so foreground activation cannot be lost to timing.
- Kept real deep-capsule queue offsets relative to each monitor's work area so
  capsules remain correctly stacked on displays positioned above or below the
  primary monitor instead of being clamped together at the screen edge.
- Synchronized native master/proxy lifecycle after individual and bulk paper
  show or hide actions so hidden queues cannot leave clickable capsule windows
  behind.
- Stacked deep capsules on PaperTodo's 46px pill plus 4px gap geometry instead
  of reusing unrelated paper coordinates, keeping multiple papers in stable
  per-monitor, per-edge queues.
- Matched the original PaperTodo paper palette, transparent 8px shadow chrome,
  compact 31px title bar, original tint strengths, 24-28px paper controls,
  rounded shell, subtle todo rows, plus-only append area, and direct todo drag
  handles across light and dark color schemes.
- Restyled the settings window with the original paper shell, compact density,
  leading checkbox toggles, a desktop-sized viewport, and a dedicated close
  action while retaining validation and explicit save behavior.
- Matched PaperTodo note interaction by entering edit mode from the paper
  preview, returning to preview on focus loss, and removing the persistent
  edit/preview/split selector; notes now render inside a bound paper page with
  a compact canvas toolbar and status bar.
- Rebuilt independent paper capsules as the original 92x46 transparent chrome
  with an inset 30px pill, compact icon/title area, drag gesture, and dedicated
  right-side hide button while preserving script click behavior.
- Deep capsules now rest with only 54px exposed at the configured screen edge,
  reveal the full pill on pointer hover, and retract again on pointer exit on
  both left- and right-docked monitor queues.
- Paper and todo context menus now use the active paper palette, compact
  Windows 36px rows, rounded outlined surfaces, restrained shadows, and dense
  dividers while Android retains 48px touch targets.
- Kept independent Windows paper positions and sizes stable when titles, todo
  items, note text, or canvas content change during or after a drag/resize;
  child-window move events now update the coordinator's native geometry caches,
  tray reconciliation preserves live HWND bounds, and title/topmost/desktop-pin
  refreshes no longer call the full geometry-applying surface path. Expanding
  a capsule or opening a reminder now also restores the saved normal paper
  bounds instead of adopting the capsule HWND's minimum size and edge position.
- Extended Windows Release smoke to move and resize a real independent paper,
  type into its Flutter content field through native input, wait for the edit to
  persist, and then require both model and HWND geometry to remain unchanged.
- Normalized local paper IDs at the Windows platform boundary before sending
  surface, tray, bounds, visibility, and work-area channel payloads.
- Rejected unsafe paper IDs inside the Windows native surface registry so
  malformed registry refreshes cannot create stale native paper targets.
- Wired the Windows `forwardToPrimary` platform channel to the single-instance
  named pipe and shared the startup-command canonicalizer with the process
  entrypoint.
- Extended Windows release smoke evidence to verify that an unknown secondary
  startup command does not restore papers after a forwarded `--hide`.
- Added a Dart controller one-shot exit guard so repeated tray, forwarded, or
  session-ending exit requests cannot duplicate platform cleanup.
- Shared duplicate UI exit requests through one save/sync-before-exit future so
  repeated exit commands cannot upload or final-sync twice before cleanup.
- Ignored late startup, tray open/delete, and native hidden-surface events while
  exit save/sync is active so shutdown retries cannot mutate papers.
- Restricted Android background WebDAV sync registration and execution to
  absolute `data.json` state paths.
- Clarified GitHub Release publishing authentication so `GH_TOKEN`/
  `GITHUB_TOKEN` failures are reported separately from missing CLI login.
- Gave release packaging a longer Windows smoke startup/exit window so slower
  hosts can still verify secondary startup command persistence.
- Rejected absolute Android signing `storeFile` values across the signing
  setup script, Gradle build, release packaging, and readiness audit.
- Required Windows manual QA release evidence to include a Windows version
  string and exactly the expected desktop parity checklist.
- Rejected unsafe release evidence `-ResultJson` paths before smoke scripts,
  manual QA, or readiness audit write reusable release records.
- Rejected unsafe external QA/smoke JSON input paths before release packaging
  or readiness audit reads reusable evidence.
- Allowed release packaging to consume a previously recorded Android device
  smoke JSON result while still rejecting mixed live/result smoke sources.
- Required passed Windows manual QA, live WebDAV smoke, and Android device
  smoke evidence before GitHub Release publishing can run.
- Split Windows paper-surface registry refresh onto a dedicated
  `setPaperSurfaces` native channel instead of relying on tray-menu rebuilds.
- Added optional Windows manual QA and live WebDAV QA result inputs to release
  packaging metadata and generated release notes.
- Updated the roadmap to separate completed automated coverage from the
  Windows, live WebDAV provider, Android runtime, and release readiness checks
  still required before claiming full PaperTodo replacement parity.
- Added a project rule test that keeps roadmap completion-audit boundaries
  explicit while Windows parity, live WebDAV QA, Android runtime smoke, and
  signed release readiness remain unfinished.
- Queued foreground/background silent WebDAV sync requests behind an active
  sync so Android backgrounding does not drop the last opportunistic sync pass.
- Extended Android APK smoke evidence to verify the launcher Activity contract,
  including singleTop launch mode, empty task affinity, adjustResize, hardware
  acceleration, and MAIN/LAUNCHER intent entries.
- Extended Windows release smoke evidence so forwarded `--new-note` and
  `--new-todo` commands must increase persisted note and todo paper counts, not
  only the total paper count.
- Added Windows note/todo startup-command counts and Android launcher Activity
  contract details to generated GitHub Release notes.
- Added WebDAV retry-message coverage so cleaned provider response details are
  not shown when they duplicate the primary WebDAV failure message.
- Added an Android WorkManager/headless Dart background sync entrypoint that
  reloads the local StateStore and reuses the shared WebDAV sync service.
- Extended Android APK and release metadata smoke checks to verify WorkManager
  background sync services and network/wake/boot-reschedule permissions.
- Added a credentialed live WebDAV smoke entrypoint for real-provider
  Windows/Android snapshot and operation-log round-trip QA.
- Added a structured Windows manual QA recording script for desktop parity
  evidence that requires a real user session.
- Retargeted legacy Windows paper-surface events to the next visible paper
  after the active registered paper is explicitly hidden or closed from either
  native events or Dart platform calls.
- Retargeted legacy Windows paper-surface events when an active paper becomes
  hidden through a surface update before native callbacks finish.
- Retargeted Windows paper-surface legacy events after state refreshes hide the
  previously active registered paper.
- Counted visible non-active registered Windows paper surfaces when native
  toggle logic asks whether any paper is still visible.
- Strengthened Android device smoke evidence by requiring the launched APK to
  remain the foreground package after startup.
- Removed broad Android foreground-package fallback matching so device smoke
  only trusts focused or resumed activity records.
- Force-stopped the Android package from device smoke cleanup even when launch
  validation fails.
- Added local HTTP WebDAV protocol round-trip coverage for snapshot and
  operation-log sync evidence.
- Required uploaded GitHub Release assets to report an explicit `uploaded` state before publish verification can pass.
- Rejected stale extra assets on GitHub Releases during publish verification.
- Normalized local model IDs before generating WebDAV operation-log diffs.
- Stripped raw control characters from stored paper, todo item, linked note, and note-canvas IDs before Windows/WebDAV persistence.
- Verified published GitHub Release assets by downloading them and comparing SHA-256 hashes.
- Added a project rule test that requires every UI string key to have Chinese and English entries.
- Revalidated Android device smoke APK file names while checking release metadata.
- Revalidated Android static smoke APK paths while checking release metadata.
- Revalidated Windows smoke release directories while checking release metadata.
- Revalidated WebDAV static smoke evidence paths while checking release metadata.
- Hardened WebDAV static smoke evidence so release metadata references only real repository files.
- Added a UTC timestamp to skipped Android device smoke metadata and release notes for release auditability.
- Tightened Android signing setup so partially configured CI signing secrets fail before packaging.
- Recorded the GitHub Release notes markdown file in release metadata with byte count and SHA-256 evidence.
- Added a two-device WebDAV operation-log round-trip test for Windows/Android sync parity.
- Added structured WebDAV static smoke metadata for release packaging.
- Recorded structured Windows release smoke results in release metadata.
- Verified idempotent local WebDAV operation uploads still reapply canonical state to Windows platform integrations before the next sync.
- Added end-to-end StateStore coverage for representative PaperTodo data migration and canonical resave behavior.
- Limited Android APK localized resources to the supported Chinese and English runtime languages.
- Kept settings explanation help available when ordinary operation tooltips are disabled, matching PaperTodo's tooltip setting boundary.
- Allowed file-name-safe external Markdown suffixes such as `.todo.md` instead of limiting users to common Markdown extensions.
- Deferred silent WebDAV sync requests while settings are open and replayed them after unchanged settings close.
- Localized generic native platform open-file and open-link errors for Chinese and English UI.
