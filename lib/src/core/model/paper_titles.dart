import 'package:characters/characters.dart';

import 'paper_constants.dart';

abstract final class PaperTitles {
  static const maxTitleLength = 40;
  static const defaultMaxTitleLength = 6;
  static const minConfigurableTitleLength = 2;
  static const maxConfigurableTitleLength = 20;

  static int normalizeMaxTitleLength(int value) {
    if (value <= 0) {
      return defaultMaxTitleLength;
    }
    return value
        .clamp(minConfigurableTitleLength, maxConfigurableTitleLength)
        .toInt();
  }

  static String defaultTitle(String paperType, int number) {
    final prefix = paperType == PaperTypes.note ? 'Note' : 'Todo';
    return '$prefix${number < 1 ? 1 : number}';
  }

  static String cleanCustomTitle(
    String? title, {
    int maxLength = maxTitleLength,
  }) {
    final cleaned = (title ?? '')
        .trim()
        .runes
        .where((rune) => !_isControlRune(rune))
        .map(String.fromCharCode)
        .join();
    return shorten(cleaned, maxLength.clamp(1, maxTitleLength).toInt());
  }

  static String effectiveTitle({
    required String paperType,
    required String? title,
    required int fallbackNumber,
  }) {
    final cleanedTitle = cleanCustomTitle(title);
    return cleanedTitle.trim().isEmpty
        ? defaultTitle(paperType, fallbackNumber)
        : cleanedTitle;
  }

  static String capsuleText({
    required String paperType,
    required String? title,
    required int fallbackNumber,
  }) {
    return effectiveTitle(
      paperType: paperType,
      title: title,
      fallbackNumber: fallbackNumber,
    );
  }

  static String shorten(String title, int maxLength) {
    final normalizedMaxLength = maxLength.clamp(1, maxTitleLength).toInt();
    final characters = title.characters;
    if (characters.length <= normalizedMaxLength) {
      return title;
    }
    return characters.take(normalizedMaxLength).toString();
  }

  static bool _isControlRune(int rune) {
    return rune < 0x20 || (rune >= 0x7F && rune <= 0x9F);
  }
}
