abstract final class TodoPasteItems {
  static const maxItemsPerPaste = 200;
  static const maxLineLength = 5000;

  static final RegExp _checkboxPrefix = RegExp(r'^\s*[-*+]\s+\[(?: |x|X)\]\s*');
  static final RegExp _bulletPrefix = RegExp(r'^\s*[-*+]\s+');
  static final RegExp _numberPrefix =
      RegExp('^\\s*\\d+[\\.)\\u3001\\uFF0E]\\s*');
  static final RegExp _glyphPrefix =
      RegExp('^\\s*[\\u2610\\u2611\\u2713\\u2714]\\s*');

  static List<String> parseLines(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map(cleanLine)
        .where((line) => line.trim().isNotEmpty)
        .map(_clipLine)
        .take(maxItemsPerPaste)
        .toList();
    return lines;
  }

  static String cleanLine(String line) {
    var cleaned = line.trim();
    cleaned = cleaned.replaceFirst(_checkboxPrefix, '');
    cleaned = cleaned.replaceFirst(_bulletPrefix, '');
    cleaned = cleaned.replaceFirst(_numberPrefix, '');
    cleaned = cleaned.replaceFirst(_glyphPrefix, '');
    return cleaned.trim();
  }

  static String _clipLine(String line) {
    if (line.length <= maxLineLength) {
      return line;
    }
    return line.substring(0, maxLineLength);
  }
}
