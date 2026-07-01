abstract final class MarkdownPasteText {
  static const maxPasteLength = 30000;
  static const maxLineLength = 6000;

  static String sanitize(String text) {
    final clippedText = text.length <= maxPasteLength
        ? text
        : text.substring(0, maxPasteLength);
    return clippedText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map(_clipLine)
        .join('\n');
  }

  static String _clipLine(String line) {
    if (line.length <= maxLineLength) {
      return line;
    }
    return line.substring(0, maxLineLength);
  }
}
