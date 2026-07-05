abstract final class MarkdownPasteText {
  static const maxTextLength = 100000;
  static const maxPasteLength = 30000;
  static const maxLineLength = 6000;

  static String sanitize(
    String text, {
    int pasteLengthLimit = maxPasteLength,
    int lineLengthLimit = maxLineLength,
  }) {
    if (pasteLengthLimit <= 0 || lineLengthLimit <= 0) {
      return '';
    }
    if (text.length <= pasteLengthLimit &&
        !_containsLineLongerThan(text, lineLengthLimit)) {
      return text;
    }
    return _clipPasteText(text, pasteLengthLimit, lineLengthLimit);
  }

  static String trimToMaxTextLength(String text) {
    if (text.length <= maxTextLength) {
      return text;
    }
    return text.substring(0, maxTextLength);
  }

  static String _clipPasteText(
    String text,
    int maxLength,
    int maxLineLength,
  ) {
    final buffer = StringBuffer();
    var lineLength = 0;
    for (final codeUnit in text.codeUnits) {
      if (buffer.length >= maxLength) {
        break;
      }
      final char = String.fromCharCode(codeUnit);
      if (char == '\r' || char == '\n') {
        buffer.write(char);
        lineLength = 0;
        continue;
      }
      if (lineLength >= maxLineLength) {
        break;
      }
      buffer.write(char);
      lineLength++;
    }
    return buffer.toString();
  }

  static bool _containsLineLongerThan(String text, int maxLength) {
    if (text.isEmpty || maxLength <= 0) {
      return false;
    }
    var lineLength = 0;
    for (final codeUnit in text.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      if (char == '\r' || char == '\n') {
        lineLength = 0;
        continue;
      }
      lineLength++;
      if (lineLength > maxLength) {
        return true;
      }
    }
    return false;
  }
}
