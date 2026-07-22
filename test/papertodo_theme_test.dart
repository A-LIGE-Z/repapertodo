import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/app_controller.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/storage/state_store.dart';
import 'package:repapertodo/src/platform/noop_platform_services.dart';
import 'package:repapertodo/src/ui/papertodo_theme.dart';

void main() {
  test('PaperTodo palettes preserve every original light and dark color', () {
    const expected = <String, Map<Brightness, List<int>>>{
      ColorSchemes.warm: {
        Brightness.light: [
          0xFFFFF9EA,
          0xFFE0CEA7,
          0xFF33291E,
          0xFF8A7A63,
          0xFF8C7350,
          0xFFF7EDD2,
          0xFFD4BE92,
          0xFFB06242,
          0xFFB4A078,
          0xFF785C30,
          0xFFB05A46,
        ],
        Brightness.dark: [
          0xFF211F1C,
          0xFF4C453D,
          0xFFE7E0D4,
          0xFF92897B,
          0xFFA88E6A,
          0xFF2D2A26,
          0xFF5E564B,
          0xFFD69678,
          0xFF6E6455,
          0xFFE6DFD3,
          0xFFE66E5A,
        ],
      },
      ColorSchemes.ink: {
        Brightness.light: [
          0xFFF6F7F9,
          0xFFD0D6DE,
          0xFF262C36,
          0xFF767E8A,
          0xFF5A6C86,
          0xFFECEFF3,
          0xFFC6CED8,
          0xFF42689C,
          0xFFAAB4C2,
          0xFF465A78,
          0xFFBC5450,
        ],
        Brightness.dark: [
          0xFF1A1C20,
          0xFF3C424C,
          0xFFDEE3EA,
          0xFF8A929E,
          0xFF849CBC,
          0xFF26292F,
          0xFF4E5662,
          0xFF84AAD6,
          0xFF606A78,
          0xFFB4C8E4,
          0xFFE0746C,
        ],
      },
      ColorSchemes.forest: {
        Brightness.light: [
          0xFFF3F8F1,
          0xFFC8DAC6,
          0xFF26322A,
          0xFF6E8070,
          0xFF588260,
          0xFFE9F2E7,
          0xFFC0D6C0,
          0xFF3C8260,
          0xFFA8C0A8,
          0xFF466E50,
          0xFFBC604C,
        ],
        Brightness.dark: [
          0xFF1A1E1B,
          0xFF3A463C,
          0xFFDCE4DC,
          0xFF869488,
          0xFF7CA886,
          0xFF252A26,
          0xFF4A5A4C,
          0xFF80BE96,
          0xFF5C6E5E,
          0xFFB4D0BA,
          0xFFDE7C68,
        ],
      },
      ColorSchemes.rose: {
        Brightness.light: [
          0xFFFDF5F6,
          0xFFE4CDD2,
          0xFF36262A,
          0xFF8C7278,
          0xFF9E6876,
          0xFFF8ECEE,
          0xFFE0C6CC,
          0xFFB2546E,
          0xFFD8B8C0,
          0xFF965060,
          0xFFBC524E,
        ],
        Brightness.dark: [
          0xFF211C1E,
          0xFF4E4044,
          0xFFE8DCDF,
          0xFF988489,
          0xFFBE8694,
          0xFF2C2628,
          0xFF5C4C50,
          0xFFE094AA,
          0xFF604E52,
          0xFFE0B4BE,
          0xFFE67264,
        ],
      },
    };

    for (final scheme in expected.entries) {
      for (final variant in scheme.value.entries) {
        final colors = PaperTodoThemeColors.resolve(
          brightness: variant.key,
          colorScheme: scheme.key,
          customThemeColorHex: '',
        );
        expect(
          _paletteArgb(colors),
          variant.value,
          reason: '${scheme.key} ${variant.key.name}',
        );
      }
    }
  });

  test('custom accents use the original PaperTodo derivation rules', () {
    final dark = PaperTodoThemeColors.resolve(
      brightness: Brightness.dark,
      colorScheme: ColorSchemes.warm,
      customThemeColorHex: '#000000',
    );
    expect(_paletteArgb(dark), [
      0xFF000000,
      0xFF242424,
      0xFFD1D1D1,
      0xFF717171,
      0xFF5C5C5C,
      0xFF000000,
      0xFF494949,
      0xFF686868,
      0xFF4B4B4B,
      0xFFAEAEAE,
      0xFFE66E5A,
    ]);

    final light = PaperTodoThemeColors.resolve(
      brightness: Brightness.light,
      colorScheme: ColorSchemes.warm,
      customThemeColorHex: '#FFFFFF',
    );
    expect(_paletteArgb(light), [
      0xFFFFFFFF,
      0xFFE2E2E2,
      0xFF474747,
      0xFF9C9C9C,
      0xFFB3B3B3,
      0xFFFFFFFF,
      0xFFC6C6C6,
      0xFFA6A6A6,
      0xFFC3C3C3,
      0xFFA1A1A1,
      0xFFB05A46,
    ]);
  });

  test('derived interaction colors remain tied to their semantic bases', () {
    final light = PaperTodoThemeColors.resolve(
      brightness: Brightness.light,
      colorScheme: ColorSchemes.warm,
      customThemeColorHex: '',
    );
    expect(light.hover.toARGB32(), 0x20785C30);
    expect(light.dangerHover.toARGB32(), 0xFFBB7160);
    expect(light.checkBoxHoverBorder.toARGB32(), 0xFF877659);
    expect(light.checkBoxActiveHover.toARGB32(), 0xFF7B6546);
    expect(light.checkBoxUncheckedHover.toARGB32(), 0x14785C30);

    final dark = PaperTodoThemeColors.resolve(
      brightness: Brightness.dark,
      colorScheme: ColorSchemes.warm,
      customThemeColorHex: '',
    );
    expect(dark.brightWeakText.toARGB32(), 0xFFAAA398);
  });

  testWidgets('app theme registers PaperTodo colors and checkbox states',
      (tester) async {
    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        colorScheme: ColorSchemes.warm,
        papers: const [],
      ),
      platform: NoopPlatformServices(),
    );
    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: StateStore(filePath: 'build/test-theme-data.json'),
      ),
    );

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    final colors = theme.extension<PaperTodoThemeColors>();
    expect(colors, isNotNull);
    expect(theme.colorScheme.primary.toARGB32(), 0xFF8C7350);
    expect(theme.colorScheme.tertiary.toARGB32(), 0xFFB06242);
    expect(theme.colorScheme.error.toARGB32(), 0xFFB05A46);
    expect(colors!.tint.toARGB32(), 0xFF785C30);

    final fill = theme.checkboxTheme.fillColor!;
    expect(
      fill.resolve({WidgetState.selected}),
      const Color(0xFF8C7350),
    );
    expect(
      fill.resolve({WidgetState.selected, WidgetState.hovered}),
      colors.checkBoxActiveHover,
    );
    expect(
      fill.resolve({WidgetState.hovered}),
      const Color(0x14785C30),
    );
    final side = theme.checkboxTheme.side! as WidgetStateBorderSide;
    expect(
      side.resolve({WidgetState.hovered})?.color,
      colors.checkBoxHoverBorder,
    );
  });

  testWidgets('standalone menus keep rounded source states in every palette',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final brightness in const ['light', 'dark']) {
      for (final scheme in const [
        ColorSchemes.warm,
        ColorSchemes.ink,
        ColorSchemes.forest,
        ColorSchemes.rose,
      ]) {
        final paperId = 'menu-$brightness-$scheme';
        final controller = RePaperTodoController(
          initialState: AppState(
            theme: brightness,
            colorScheme: scheme,
            papers: [
              PaperData(
                id: paperId,
                type: PaperTypes.note,
                title: 'Menu states',
                content: 'PaperTodo menu state verification.',
              ),
            ],
          ),
          platform: NoopPlatformServices(),
        );
        await tester.pumpWidget(
          RePaperTodoApp(
            controller: controller,
            store: StateStore(
              filePath: 'build/test-theme-menu-$brightness-$scheme.json',
            ),
            initialSurfacePaperId: paperId,
            paperWindowMode: true,
          ),
        );
        await tester.pumpAndSettle();

        final header = find.byKey(ValueKey('$paperId-paper-header'));
        await tester.tapAt(
          tester.getTopLeft(header) + const Offset(12, 12),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        final item = find.ancestor(
          of: find.text('+ Todo paper'),
          matching: find.byWidgetPredicate(
            (widget) => widget is PopupMenuItem<String>,
          ),
        );
        final ink = find.descendant(of: item, matching: find.byType(InkWell));
        expect(ink, findsOneWidget, reason: '$brightness $scheme');
        final inkWidget = tester.widget<InkWell>(ink);
        final colors = PaperTodoThemeColors.of(tester.element(ink));
        expect(
          inkWidget.borderRadius,
          BorderRadius.circular(8),
          reason: '$brightness $scheme',
        );
        expect(
          inkWidget.hoverColor,
          colors.hover,
          reason: '$brightness $scheme',
        );
        expect(
          inkWidget.highlightColor,
          Colors.transparent,
          reason: '$brightness $scheme',
        );
        await tester.tap(item);
        await tester.pumpAndSettle();
      }
    }
  });
}

List<int> _paletteArgb(PaperTodoThemeColors colors) => [
      colors.paper.toARGB32(),
      colors.paperBorder.toARGB32(),
      colors.text.toARGB32(),
      colors.weakText.toARGB32(),
      colors.active.toARGB32(),
      colors.code.toARGB32(),
      colors.quoteBorder.toARGB32(),
      colors.link.toARGB32(),
      colors.checkBox.toARGB32(),
      colors.tint.toARGB32(),
      colors.danger.toARGB32(),
    ];
