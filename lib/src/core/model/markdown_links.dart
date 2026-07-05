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
    var search = 0;
    while (search < text.length) {
      final openStart = text.indexOf('<', search);
      if (openStart < 0) {
        break;
      }
      final openTag = _tryParseHtmlOpeningAnchor(text, openStart);
      if (openTag == null) {
        search = openStart + 1;
        continue;
      }
      final closeEnd = _findHtmlAnchorClose(text, openTag.openEnd);
      if (closeEnd == null) {
        search = openTag.openEnd;
        continue;
      }
      if (closeEnd.closeStart > openTag.openEnd) {
        yield MarkdownLinkSpan(
          start: openStart,
          end: closeEnd.end,
          href: openTag.href,
        );
      }
      search = closeEnd.end;
    }
  }

  static _HtmlOpenAnchor? _tryParseHtmlOpeningAnchor(
      String text, int openStart) {
    if (openStart + 2 >= text.length ||
        text[openStart] != '<' ||
        text[openStart + 1] == '/') {
      return null;
    }

    var nameEnd = openStart + 1;
    while (nameEnd < text.length && _isHtmlTagNameChar(text[nameEnd])) {
      nameEnd++;
    }
    if (nameEnd == openStart + 1 ||
        text.substring(openStart + 1, nameEnd).toLowerCase() != 'a') {
      return null;
    }

    final tagEnd = _findHtmlTagEnd(text, nameEnd);
    if (tagEnd < 0) {
      return null;
    }

    final rawHref = _tryGetHtmlHrefAttribute(text.substring(nameEnd, tagEnd));
    final href = _normalizeHref(rawHref);
    if (href == null) {
      return null;
    }
    return _HtmlOpenAnchor(openEnd: tagEnd + 1, href: href);
  }

  static _HtmlCloseTag? _findHtmlAnchorClose(String text, int searchStart) {
    var search = searchStart;
    while (search < text.length) {
      final start = text.indexOf('</', search);
      if (start < 0) {
        return null;
      }
      var nameEnd = start + 2;
      while (nameEnd < text.length && _isHtmlTagNameChar(text[nameEnd])) {
        nameEnd++;
      }
      if (nameEnd > start + 2 &&
          text.substring(start + 2, nameEnd).toLowerCase() == 'a') {
        var end = nameEnd;
        while (end < text.length && text[end].trim().isEmpty) {
          end++;
        }
        if (end < text.length && text[end] == '>') {
          return _HtmlCloseTag(closeStart: start, end: end + 1);
        }
      }
      search = start + 2;
    }
    return null;
  }

  static int _findHtmlTagEnd(String text, int start) {
    var quote = '';
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (quote.isNotEmpty) {
        if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '>') {
        return i;
      }
    }
    return -1;
  }

  static String? _tryGetHtmlHrefAttribute(String attributes) {
    var index = 0;
    while (index < attributes.length) {
      while (index < attributes.length && attributes[index].trim().isEmpty) {
        index++;
      }

      final nameStart = index;
      while (index < attributes.length &&
          _isHtmlAttributeNameChar(attributes[index])) {
        index++;
      }
      if (index == nameStart) {
        return null;
      }

      final name = attributes.substring(nameStart, index);
      while (index < attributes.length && attributes[index].trim().isEmpty) {
        index++;
      }
      if (index >= attributes.length || attributes[index] != '=') {
        return null;
      }

      index++;
      while (index < attributes.length && attributes[index].trim().isEmpty) {
        index++;
      }
      if (index >= attributes.length) {
        return null;
      }

      String value;
      if (attributes[index] == '"' || attributes[index] == "'") {
        final quote = attributes[index];
        final valueStart = ++index;
        final valueEnd = attributes.indexOf(quote, valueStart);
        if (valueEnd < 0) {
          return null;
        }
        value = attributes.substring(valueStart, valueEnd);
        index = valueEnd + 1;
      } else {
        final valueStart = index;
        while (
            index < attributes.length && attributes[index].trim().isNotEmpty) {
          index++;
        }
        value = attributes.substring(valueStart, index);
      }

      if (name.toLowerCase() == 'href') {
        return value;
      }
    }
    return null;
  }

  static bool _isHtmlTagNameChar(String value) {
    final codeUnit = value.codeUnitAt(0);
    return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A);
  }

  static bool _isHtmlAttributeNameChar(String value) {
    final codeUnit = value.codeUnitAt(0);
    return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        value == '-' ||
        value == '_';
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

class _HtmlOpenAnchor {
  const _HtmlOpenAnchor({required this.openEnd, required this.href});

  final int openEnd;
  final String href;
}

class _HtmlCloseTag {
  const _HtmlCloseTag({required this.closeStart, required this.end});

  final int closeStart;
  final int end;
}
