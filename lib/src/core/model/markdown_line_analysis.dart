enum MarkdownLineKind {
  plain,
  heading1,
  heading2,
  heading3,
  heading,
  quote,
  unorderedList,
  orderedList,
  codeFence,
  codeBlock,
  horizontalRule,
}

class MarkdownLineStyle {
  const MarkdownLineStyle({
    required this.kind,
    required this.markerStart,
    required this.markerEnd,
    required this.contentStart,
    this.orderedNumberText,
    this.orderedDelimiter,
    this.isTask = false,
  });

  const MarkdownLineStyle.plain()
      : kind = MarkdownLineKind.plain,
        markerStart = 0,
        markerEnd = 0,
        contentStart = 0,
        orderedNumberText = null,
        orderedDelimiter = null,
        isTask = false;

  final MarkdownLineKind kind;
  final int markerStart;
  final int markerEnd;
  final int contentStart;
  final String? orderedNumberText;
  final String? orderedDelimiter;
  final bool isTask;

  bool get isList =>
      kind == MarkdownLineKind.unorderedList ||
      kind == MarkdownLineKind.orderedList;

  bool get isOrderedList => kind == MarkdownLineKind.orderedList;

  bool get isUnorderedList => kind == MarkdownLineKind.unorderedList;

  bool get isHeading =>
      kind == MarkdownLineKind.heading1 ||
      kind == MarkdownLineKind.heading2 ||
      kind == MarkdownLineKind.heading3 ||
      kind == MarkdownLineKind.heading;
}

abstract final class MarkdownLineAnalysis {
  static MarkdownLineStyle analyzeLine(
    String text, {
    bool isInFencedCodeBlock = false,
  }) {
    if (text.isEmpty) {
      return const MarkdownLineStyle.plain();
    }

    final indent = _countIndent(text);
    if (indent >= text.length) {
      return const MarkdownLineStyle.plain();
    }

    if (_isFenceLine(text)) {
      return MarkdownLineStyle(
        kind: MarkdownLineKind.codeFence,
        markerStart: indent,
        markerEnd: text.length,
        contentStart: text.length,
      );
    }

    if (isInFencedCodeBlock) {
      return const MarkdownLineStyle(
        kind: MarkdownLineKind.codeBlock,
        markerStart: 0,
        markerEnd: 0,
        contentStart: 0,
      );
    }

    if (_isHorizontalRuleLine(text, indent)) {
      return MarkdownLineStyle(
        kind: MarkdownLineKind.horizontalRule,
        markerStart: indent,
        markerEnd: text.length,
        contentStart: text.length,
      );
    }

    if (text[indent] == '#') {
      final count = _countRepeated(text, indent, '#');
      var end = indent + count;
      if (count <= 6 && end < text.length && _isWhitespace(text[end])) {
        while (end < text.length && _isWhitespace(text[end])) {
          end++;
        }
        return MarkdownLineStyle(
          kind: switch (count) {
            1 => MarkdownLineKind.heading1,
            2 => MarkdownLineKind.heading2,
            3 => MarkdownLineKind.heading3,
            _ => MarkdownLineKind.heading,
          },
          markerStart: indent,
          markerEnd: end,
          contentStart: end,
        );
      }
    }

    if (text[indent] == '>') {
      var end = indent + 1;
      while (end < text.length && _isWhitespace(text[end])) {
        end++;
      }
      return MarkdownLineStyle(
        kind: MarkdownLineKind.quote,
        markerStart: indent,
        markerEnd: end,
        contentStart: end,
      );
    }

    final byIndent = _tryAnalyzeList(text, indent);
    if (byIndent != null) {
      return byIndent;
    }

    final leadingSpaces = _countLeadingSpaces(text);
    if (leadingSpaces != indent) {
      final byLeadingSpaces = _tryAnalyzeList(text, leadingSpaces);
      if (byLeadingSpaces != null) {
        return byLeadingSpaces;
      }
    }

    return const MarkdownLineStyle.plain();
  }

  static List<MarkdownLineStyle> analyzeLines(String text) {
    final styles = <MarkdownLineStyle>[];
    var isInFence = false;
    for (final line in _splitLines(text)) {
      final style = analyzeLine(line, isInFencedCodeBlock: isInFence);
      styles.add(style);
      if (style.kind == MarkdownLineKind.codeFence) {
        isInFence = !isInFence;
      }
    }
    return styles;
  }

  static MarkdownLineStyle? _tryAnalyzeList(String text, int start) {
    if (start >= text.length) {
      return null;
    }

    final marker = text[start];
    if (marker == '-' || marker == '*' || marker == '+') {
      if (start + 1 < text.length && !_isWhitespace(text[start + 1])) {
        return null;
      }
      var end = start + 1;
      while (end < text.length && _isWhitespace(text[end])) {
        end++;
      }
      return _withTaskState(
        MarkdownLineStyle(
          kind: MarkdownLineKind.unorderedList,
          markerStart: start,
          markerEnd: start + 1,
          contentStart: end,
        ),
        text,
      );
    }

    if (!_isDigit(marker)) {
      return null;
    }
    var delimiter = start + 1;
    while (delimiter < text.length && _isDigit(text[delimiter])) {
      delimiter++;
    }
    if (delimiter >= text.length ||
        (text[delimiter] != '.' && text[delimiter] != ')')) {
      return null;
    }
    if (delimiter + 1 < text.length && !_isWhitespace(text[delimiter + 1])) {
      return null;
    }
    var end = delimiter + 1;
    while (end < text.length && _isWhitespace(text[end])) {
      end++;
    }
    return _withTaskState(
      MarkdownLineStyle(
        kind: MarkdownLineKind.orderedList,
        markerStart: start,
        markerEnd: delimiter + 1,
        contentStart: end,
        orderedNumberText: text.substring(start, delimiter),
        orderedDelimiter: text[delimiter],
      ),
      text,
    );
  }

  static MarkdownLineStyle _withTaskState(
    MarkdownLineStyle style,
    String text,
  ) {
    return MarkdownLineStyle(
      kind: style.kind,
      markerStart: style.markerStart,
      markerEnd: style.markerEnd,
      contentStart: style.contentStart,
      orderedNumberText: style.orderedNumberText,
      orderedDelimiter: style.orderedDelimiter,
      isTask: _isTaskList(style, text),
    );
  }

  static bool _isTaskList(MarkdownLineStyle style, String text) {
    if (!style.isList || style.contentStart + 2 >= text.length) {
      return false;
    }
    final start = style.contentStart;
    final value = text[start + 1];
    return text[start] == '[' &&
        text[start + 2] == ']' &&
        (value == ' ' || value == 'x' || value == 'X');
  }

  static bool _isFenceLine(String text) {
    final start = _countIndent(text);
    if (start >= text.length) {
      return false;
    }
    return (text[start] == '`' && _countRepeated(text, start, '`') >= 3) ||
        (text[start] == '~' && _countRepeated(text, start, '~') >= 3);
  }

  static bool _isHorizontalRuleLine(String text, int start) {
    if (start >= text.length ||
        (text[start] != '-' && text[start] != '_' && text[start] != '*')) {
      return false;
    }
    final marker = text[start];
    var count = 0;
    for (var i = start; i < text.length; i++) {
      if (text[i] == marker) {
        count++;
        continue;
      }
      if (!_isWhitespace(text[i])) {
        return false;
      }
    }
    return count >= 3;
  }

  static Iterable<String> _splitLines(String text) sync* {
    if (text.isEmpty) {
      yield '';
      return;
    }
    var start = 0;
    for (var index = 0; index < text.length; index++) {
      if (text[index] != '\n') {
        continue;
      }
      var end = index;
      if (end > start && text[end - 1] == '\r') {
        end--;
      }
      yield text.substring(start, end);
      start = index + 1;
    }
    var end = text.length;
    if (end > start && text[end - 1] == '\r') {
      end--;
    }
    yield text.substring(start, end);
  }

  static int _countIndent(String text) {
    var indent = 0;
    while (indent < text.length && indent < 3 && text[indent] == ' ') {
      indent++;
    }
    return indent;
  }

  static int _countLeadingSpaces(String text) {
    var indent = 0;
    while (indent < text.length && text[indent] == ' ') {
      indent++;
    }
    return indent;
  }

  static int _countRepeated(String text, int start, String character) {
    var count = 0;
    while (start + count < text.length && text[start + count] == character) {
      count++;
    }
    return count;
  }

  static bool _isWhitespace(String value) => value.trim().isEmpty;

  static bool _isDigit(String value) {
    if (value.length != 1) {
      return false;
    }
    final codeUnit = value.codeUnitAt(0);
    return codeUnit >= 0x30 && codeUnit <= 0x39;
  }
}
