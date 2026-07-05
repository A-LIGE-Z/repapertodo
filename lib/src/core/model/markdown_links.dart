class MarkdownLinkSpan {
  const MarkdownLinkSpan({
    required this.start,
    required this.end,
    required this.href,
  });

  final int start;
  final int end;
  final String href;

  bool containsOffset(int offset) => offset >= start && offset < end;
}

abstract final class MarkdownLinks {
  static String? hrefAt(String text, int offset) {
    if (text.isEmpty) {
      return null;
    }
    final normalizedOffset = offset.clamp(0, text.length).toInt();
    final lineStart = _lineStartBefore(text, normalizedOffset);
    final lineEnd = _lineEndAfter(text, normalizedOffset);
    final line = text.substring(lineStart, lineEnd);
    final offsetInLine =
        (normalizedOffset - lineStart).clamp(0, line.length).toInt();
    for (final link in spans(line)) {
      if (link.containsOffset(offsetInLine)) {
        return link.href;
      }
    }
    return null;
  }

  static Iterable<MarkdownLinkSpan> spans(String text) sync* {
    final ignoredSpans = _closedInlineCodeSpans(text).toList();
    for (final link in _markdownLinks(text)) {
      if (!_isIgnored(ignoredSpans, link.start, link.end)) {
        yield link;
      }
    }
    for (final link in _htmlAnchorLinks(text)) {
      if (!_isIgnored(ignoredSpans, link.start, link.end)) {
        yield link;
      }
    }
  }

  static Iterable<MarkdownLinkSpan> _markdownLinks(String text) sync* {
    var searchStart = 0;
    while (searchStart < text.length) {
      final labelStart = text.indexOf('[', searchStart);
      if (labelStart < 0) {
        break;
      }
      if (labelStart > 0 && text[labelStart - 1] == '!') {
        searchStart = labelStart + 1;
        continue;
      }

      final labelEnd = _findUnescaped(text, ']', labelStart + 1);
      if (labelEnd < 0 ||
          labelEnd + 1 >= text.length ||
          text[labelEnd + 1] != '(') {
        searchStart = labelStart + 1;
        continue;
      }

      final destinationStart = labelEnd + 2;
      final destinationEnd = _findUnescaped(text, ')', destinationStart);
      if (destinationEnd < 0) {
        searchStart = labelStart + 1;
        continue;
      }

      final href = _normalizeMarkdownDestination(
        text.substring(destinationStart, destinationEnd),
      );
      if (href != null) {
        yield MarkdownLinkSpan(
          start: labelStart,
          end: destinationEnd + 1,
          href: href,
        );
      }
      searchStart = destinationEnd + 1;
    }
  }

  static Iterable<MarkdownLinkSpan> _htmlAnchorLinks(String text) sync* {
    final pattern = RegExp(
      "<a\\s+[^>]*href\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))[^>]*>.*?<\\/a>",
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(text)) {
      final rawHref = match.group(1) ?? match.group(2) ?? match.group(3);
      final href = _normalizeHref(rawHref);
      if (href == null) {
        continue;
      }
      yield MarkdownLinkSpan(
        start: match.start,
        end: match.end,
        href: href,
      );
    }
  }

  static int _findUnescaped(String text, String character, int start) {
    var index = start;
    while (index < text.length) {
      index = text.indexOf(character, index);
      if (index < 0) {
        return -1;
      }
      if (!_isEscaped(text, index)) {
        return index;
      }
      index++;
    }
    return -1;
  }

  static int _lineStartBefore(String text, int offset) {
    final searchFrom = offset <= 0 ? 0 : offset - 1;
    final previousBreak = text.lastIndexOf('\n', searchFrom);
    return previousBreak < 0 ? 0 : previousBreak + 1;
  }

  static int _lineEndAfter(String text, int offset) {
    final nextBreak = text.indexOf('\n', offset);
    return nextBreak < 0 ? text.length : nextBreak;
  }

  static bool _isEscaped(String text, int index) {
    var slashCount = 0;
    var cursor = index - 1;
    while (cursor >= 0 && text[cursor] == r'\') {
      slashCount++;
      cursor--;
    }
    return slashCount.isOdd;
  }

  static Iterable<_InlineCodeSpan> _closedInlineCodeSpans(String text) sync* {
    var index = 0;
    while (index < text.length) {
      final start = text.indexOf('`', index);
      if (start < 0) {
        break;
      }
      final end = text.indexOf('`', start + 1);
      if (end < 0) {
        break;
      }
      yield _InlineCodeSpan(start: start, end: end + 1);
      index = end + 1;
    }
  }

  static bool _isIgnored(
    List<_InlineCodeSpan> ignoredSpans,
    int start,
    int end,
  ) {
    for (final span in ignoredSpans) {
      if (span.intersects(start, end)) {
        return true;
      }
    }
    return false;
  }

  static String? _normalizeMarkdownDestination(String rawDestination) {
    var destination = rawDestination.trim();
    if (destination.isEmpty) {
      return null;
    }
    if (destination.startsWith('<')) {
      final closingBracket = destination.indexOf('>');
      if (closingBracket <= 0) {
        return null;
      }
      return _normalizeHref(destination.substring(1, closingBracket));
    }

    final whitespace = RegExp(r'\s').firstMatch(destination);
    if (whitespace != null) {
      destination = destination.substring(0, whitespace.start);
    }
    return _normalizeHref(destination);
  }

  static String? _normalizeHref(String? rawHref) {
    var href = rawHref?.trim();
    if (href == null || href.isEmpty) {
      return null;
    }
    if (href.toLowerCase().startsWith('www.')) {
      href = 'https://$href';
    }
    return href.replaceAll(' ', '%20');
  }
}

class _InlineCodeSpan {
  const _InlineCodeSpan({required this.start, required this.end});

  final int start;
  final int end;

  bool intersects(int start, int end) => start < this.end && end > this.start;
}
