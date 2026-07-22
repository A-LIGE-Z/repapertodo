import 'package:flutter/material.dart';

import '../core/model/paper_constants.dart';

@immutable
class PaperTodoTypography extends ThemeExtension<PaperTodoTypography> {
  const PaperTodoTypography({
    required this.contentFontFamily,
    required this.contentFontFamilyFallback,
  });

  final String? contentFontFamily;
  final List<String>? contentFontFamilyFallback;

  TextStyle contentStyle(TextStyle style) {
    return style.copyWith(
      fontFamily: contentFontFamily,
      fontFamilyFallback: contentFontFamilyFallback,
    );
  }

  static PaperTodoTypography of(BuildContext context) {
    return Theme.of(context).extension<PaperTodoTypography>() ??
        const PaperTodoTypography(
          contentFontFamily: null,
          contentFontFamilyFallback: null,
        );
  }

  @override
  PaperTodoTypography copyWith({
    String? contentFontFamily,
    List<String>? contentFontFamilyFallback,
  }) {
    return PaperTodoTypography(
      contentFontFamily: contentFontFamily ?? this.contentFontFamily,
      contentFontFamilyFallback:
          contentFontFamilyFallback ?? this.contentFontFamilyFallback,
    );
  }

  @override
  PaperTodoTypography lerp(
    covariant PaperTodoTypography? other,
    double t,
  ) {
    if (other == null || t < 0.5) {
      return this;
    }
    return other;
  }
}

@immutable
class PaperTodoThemeColors extends ThemeExtension<PaperTodoThemeColors> {
  const PaperTodoThemeColors({
    required this.paper,
    required this.paperBorder,
    required this.text,
    required this.weakText,
    required this.active,
    required this.code,
    required this.quoteBorder,
    required this.link,
    required this.checkBox,
    required this.tint,
    required this.danger,
    required this.brightness,
  });

  final Color paper;
  final Color paperBorder;
  final Color text;
  final Color weakText;
  final Color active;
  final Color code;
  final Color quoteBorder;
  final Color link;
  final Color checkBox;
  final Color tint;
  final Color danger;
  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;
  Color get hover => tint.withValues(alpha: isDark ? 48 / 255 : 32 / 255);
  Color get dangerHover => _mix(danger, Colors.white, 0.14);
  Color get brightWeakText =>
      isDark ? _mix(weakText, Colors.white, 0.22) : weakText;
  Color get checkBoxHoverBorder => _mix(checkBox, text, 0.35);
  Color get checkBoxActiveHover => _mix(active, Colors.black, 0.12);
  Color get checkBoxUncheckedHover => tint.withValues(alpha: 20 / 255);

  Color tintAt(num alpha) => tint.withValues(alpha: alpha.toDouble() / 255);
  Color dangerAt(num alpha) => danger.withValues(alpha: alpha.toDouble() / 255);

  static PaperTodoThemeColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<PaperTodoThemeColors>() ??
        PaperTodoThemeColors(
          paper: theme.colorScheme.surface,
          paperBorder: theme.colorScheme.outline,
          text: theme.colorScheme.onSurface,
          weakText: theme.colorScheme.onSurfaceVariant,
          active: theme.colorScheme.primary,
          code: theme.colorScheme.surfaceContainerHigh,
          quoteBorder: theme.colorScheme.outline,
          link: theme.colorScheme.primary,
          checkBox: theme.colorScheme.outline,
          tint: theme.colorScheme.primary,
          danger: theme.colorScheme.error,
          brightness: theme.brightness,
        );
  }

  static PaperTodoThemeColors resolve({
    required Brightness brightness,
    required String colorScheme,
    required String customThemeColorHex,
  }) {
    final dark = brightness == Brightness.dark;
    final pair = _palettes[ColorSchemes.normalize(colorScheme)]!;
    final base = dark ? pair.dark : pair.light;
    final custom = _parseHexColor(customThemeColorHex);
    if (custom == null) {
      return base;
    }

    final luminance = custom.computeLuminance();
    final active = dark
        ? _mix(custom, Colors.white, luminance < 0.26 ? 0.36 : 0.12)
        : luminance > 0.78
            ? _mix(custom, Colors.black, 0.30)
            : custom;
    final paper = dark
        ? _mix(custom, Colors.black, 0.82)
        : _mix(custom, Colors.white, 0.90);
    final text = dark
        ? _mix(custom, Colors.white, 0.82)
        : _mix(custom, Colors.black, 0.72);
    final border = _mix(paper, text, dark ? 0.17 : 0.16);
    return PaperTodoThemeColors(
      paper: paper,
      paperBorder: border,
      text: text,
      weakText: _mix(text, paper, 0.46),
      active: active,
      code: dark
          ? _mix(custom, Colors.black, 0.74)
          : _mix(custom, Colors.white, 0.82),
      quoteBorder: _mix(active, border, dark ? 0.34 : 0.40),
      link: _mix(active, text, dark ? 0.10 : 0.12),
      checkBox: _mix(active, border, dark ? 0.30 : 0.34),
      tint: dark
          ? _mix(active, Colors.white, 0.50)
          : _mix(active, Colors.black, 0.10),
      danger: base.danger,
      brightness: brightness,
    );
  }

  @override
  PaperTodoThemeColors copyWith({
    Color? paper,
    Color? paperBorder,
    Color? text,
    Color? weakText,
    Color? active,
    Color? code,
    Color? quoteBorder,
    Color? link,
    Color? checkBox,
    Color? tint,
    Color? danger,
    Brightness? brightness,
  }) {
    return PaperTodoThemeColors(
      paper: paper ?? this.paper,
      paperBorder: paperBorder ?? this.paperBorder,
      text: text ?? this.text,
      weakText: weakText ?? this.weakText,
      active: active ?? this.active,
      code: code ?? this.code,
      quoteBorder: quoteBorder ?? this.quoteBorder,
      link: link ?? this.link,
      checkBox: checkBox ?? this.checkBox,
      tint: tint ?? this.tint,
      danger: danger ?? this.danger,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  PaperTodoThemeColors lerp(
    covariant PaperTodoThemeColors? other,
    double t,
  ) {
    if (other == null) {
      return this;
    }
    return PaperTodoThemeColors(
      paper: Color.lerp(paper, other.paper, t)!,
      paperBorder: Color.lerp(paperBorder, other.paperBorder, t)!,
      text: Color.lerp(text, other.text, t)!,
      weakText: Color.lerp(weakText, other.weakText, t)!,
      active: Color.lerp(active, other.active, t)!,
      code: Color.lerp(code, other.code, t)!,
      quoteBorder: Color.lerp(quoteBorder, other.quoteBorder, t)!,
      link: Color.lerp(link, other.link, t)!,
      checkBox: Color.lerp(checkBox, other.checkBox, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}

typedef _PaperTodoPalettePair = ({
  PaperTodoThemeColors light,
  PaperTodoThemeColors dark,
});

const _palettes = <String, _PaperTodoPalettePair>{
  ColorSchemes.warm: (
    light: PaperTodoThemeColors(
      paper: Color(0xFFFFF9EA),
      paperBorder: Color(0xFFE0CEA7),
      text: Color(0xFF33291E),
      weakText: Color(0xFF8A7A63),
      active: Color(0xFF8C7350),
      code: Color(0xFFF7EDD2),
      quoteBorder: Color(0xFFD4BE92),
      link: Color(0xFFB06242),
      checkBox: Color(0xFFB4A078),
      tint: Color(0xFF785C30),
      danger: Color(0xFFB05A46),
      brightness: Brightness.light,
    ),
    dark: PaperTodoThemeColors(
      paper: Color(0xFF211F1C),
      paperBorder: Color(0xFF4C453D),
      text: Color(0xFFE7E0D4),
      weakText: Color(0xFF92897B),
      active: Color(0xFFA88E6A),
      code: Color(0xFF2D2A26),
      quoteBorder: Color(0xFF5E564B),
      link: Color(0xFFD69678),
      checkBox: Color(0xFF6E6455),
      tint: Color(0xFFE6DFD3),
      danger: Color(0xFFE66E5A),
      brightness: Brightness.dark,
    ),
  ),
  ColorSchemes.ink: (
    light: PaperTodoThemeColors(
      paper: Color(0xFFF6F7F9),
      paperBorder: Color(0xFFD0D6DE),
      text: Color(0xFF262C36),
      weakText: Color(0xFF767E8A),
      active: Color(0xFF5A6C86),
      code: Color(0xFFECEFF3),
      quoteBorder: Color(0xFFC6CED8),
      link: Color(0xFF42689C),
      checkBox: Color(0xFFAAB4C2),
      tint: Color(0xFF465A78),
      danger: Color(0xFFBC5450),
      brightness: Brightness.light,
    ),
    dark: PaperTodoThemeColors(
      paper: Color(0xFF1A1C20),
      paperBorder: Color(0xFF3C424C),
      text: Color(0xFFDEE3EA),
      weakText: Color(0xFF8A929E),
      active: Color(0xFF849CBC),
      code: Color(0xFF26292F),
      quoteBorder: Color(0xFF4E5662),
      link: Color(0xFF84AAD6),
      checkBox: Color(0xFF606A78),
      tint: Color(0xFFB4C8E4),
      danger: Color(0xFFE0746C),
      brightness: Brightness.dark,
    ),
  ),
  ColorSchemes.forest: (
    light: PaperTodoThemeColors(
      paper: Color(0xFFF3F8F1),
      paperBorder: Color(0xFFC8DAC6),
      text: Color(0xFF26322A),
      weakText: Color(0xFF6E8070),
      active: Color(0xFF588260),
      code: Color(0xFFE9F2E7),
      quoteBorder: Color(0xFFC0D6C0),
      link: Color(0xFF3C8260),
      checkBox: Color(0xFFA8C0A8),
      tint: Color(0xFF466E50),
      danger: Color(0xFFBC604C),
      brightness: Brightness.light,
    ),
    dark: PaperTodoThemeColors(
      paper: Color(0xFF1A1E1B),
      paperBorder: Color(0xFF3A463C),
      text: Color(0xFFDCE4DC),
      weakText: Color(0xFF869488),
      active: Color(0xFF7CA886),
      code: Color(0xFF252A26),
      quoteBorder: Color(0xFF4A5A4C),
      link: Color(0xFF80BE96),
      checkBox: Color(0xFF5C6E5E),
      tint: Color(0xFFB4D0BA),
      danger: Color(0xFFDE7C68),
      brightness: Brightness.dark,
    ),
  ),
  ColorSchemes.rose: (
    light: PaperTodoThemeColors(
      paper: Color(0xFFFDF5F6),
      paperBorder: Color(0xFFE4CDD2),
      text: Color(0xFF36262A),
      weakText: Color(0xFF8C7278),
      active: Color(0xFF9E6876),
      code: Color(0xFFF8ECEE),
      quoteBorder: Color(0xFFE0C6CC),
      link: Color(0xFFB2546E),
      checkBox: Color(0xFFD8B8C0),
      tint: Color(0xFF965060),
      danger: Color(0xFFBC524E),
      brightness: Brightness.light,
    ),
    dark: PaperTodoThemeColors(
      paper: Color(0xFF211C1E),
      paperBorder: Color(0xFF4E4044),
      text: Color(0xFFE8DCDF),
      weakText: Color(0xFF988489),
      active: Color(0xFFBE8694),
      code: Color(0xFF2C2628),
      quoteBorder: Color(0xFF5C4C50),
      link: Color(0xFFE094AA),
      checkBox: Color(0xFF604E52),
      tint: Color(0xFFE0B4BE),
      danger: Color(0xFFE67264),
      brightness: Brightness.dark,
    ),
  ),
};

Color _mix(Color first, Color second, double amount) {
  final t = amount.clamp(0.0, 1.0);
  int channel(double a, double b) =>
      ((a + (b - a) * t) * 255).round().clamp(0, 255);
  return Color.fromARGB(
    255,
    channel(first.r, second.r),
    channel(first.g, second.g),
    channel(first.b, second.b),
  );
}

Color? _parseHexColor(String value) {
  final match = RegExp(r'^#?([0-9A-Fa-f]{6})$').firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  return Color(int.parse('FF${match.group(1)!}', radix: 16));
}
