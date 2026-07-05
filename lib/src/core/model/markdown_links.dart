import 'package:path/path.dart' as p;

final _windowsPathContext = p.Context(style: p.Style.windows);

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

      final labelEnd = text.indexOf('](', labelStart + 1);
      if (labelEnd < 0) {
        break;
      }

      final destinationStart = labelEnd + 2;
      final destinationEnd = text.indexOf(')', destinationStart);
      if (destinationEnd < 0) {
        break;
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

  static int _lineStartBefore(String text, int offset) {
    final searchFrom = offset <= 0 ? 0 : offset - 1;
    final previousBreak = text.lastIndexOf('\n', searchFrom);
    return previousBreak < 0 ? 0 : previousBreak + 1;
  }

  static int _lineEndAfter(String text, int offset) {
    final nextBreak = text.indexOf('\n', offset);
    return nextBreak < 0 ? text.length : nextBreak;
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
    return _normalizeHref(rawDestination);
  }

  static String? _normalizeHref(String? rawHref) {
    var href = rawHref?.trim();
    if (href == null || href.isEmpty) {
      return null;
    }
    if (href.toLowerCase().startsWith('www.')) {
      href = 'https://$href';
    }

    final localPath = _normalizeLocalMarkdownPath(href);
    if (localPath != null) {
      return localPath;
    }

    final uri = Uri.tryParse(href);
    if (uri == null) {
      return null;
    }
    if (uri.scheme.toLowerCase() == 'file') {
      return _normalizeFileUriMarkdownPath(uri);
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https' && scheme != 'mailto') {
      return null;
    }
    if ((scheme == 'http' || scheme == 'https') &&
        !_hasValidRawUriAuthority(href)) {
      return null;
    }
    return uri.toString();
  }

  static String? _normalizeFileUriMarkdownPath(Uri uri) {
    try {
      return _normalizeLocalMarkdownPath(uri.toFilePath(windows: true));
    } on UnsupportedError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static String? _normalizeLocalMarkdownPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        _hasRawControlCharacter(trimmed) ||
        !_looksLikeLocalMarkdownPath(trimmed) ||
        _isDeviceMarkdownPath(trimmed)) {
      return null;
    }

    try {
      final fullPath = _windowsPathContext.normalize(
        _windowsPathContext.absolute(trimmed),
      );
      return _isDeviceMarkdownPath(fullPath) ? null : fullPath;
    } on ArgumentError {
      return null;
    }
  }

  static bool _looksLikeLocalMarkdownPath(String value) {
    return _isWindowsDrivePath(value) || _isUncPath(value);
  }

  static bool _isWindowsDrivePath(String value) {
    return value.length >= 3 &&
        _isAsciiLetter(value[0]) &&
        value[1] == ':' &&
        _isDirectorySeparator(value[2]);
  }

  static bool _isUncPath(String value) {
    return value.length >= 3 &&
        _isDirectorySeparator(value[0]) &&
        _isDirectorySeparator(value[1]) &&
        !_isDirectorySeparator(value[2]);
  }

  static bool _isDeviceMarkdownPath(String value) {
    final normalized = value.replaceAll('/', r'\');
    return normalized.startsWith(r'\\.\') || normalized.startsWith(r'\\?\');
  }

  static bool _isDirectorySeparator(String value) {
    return value == r'\' || value == '/';
  }

  static bool _hasValidRawUriAuthority(String value) {
    final separator = value.indexOf('://');
    if (separator < 0) {
      return false;
    }
    final authorityStart = separator + 3;
    var authorityEnd = value.length;
    for (final delimiter in const ['/', '?', '#']) {
      final delimiterIndex = value.indexOf(delimiter, authorityStart);
      if (delimiterIndex >= 0 && delimiterIndex < authorityEnd) {
        authorityEnd = delimiterIndex;
      }
    }
    final authority = value.substring(authorityStart, authorityEnd);
    return authority.isNotEmpty && !_hasRawWhitespaceOrControl(authority);
  }

  static bool _isAsciiLetter(String value) {
    if (value.length != 1) {
      return false;
    }
    final codeUnit = value.codeUnitAt(0);
    return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A);
  }

  static bool _hasRawControlCharacter(String value) {
    return value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7F);
  }

  static bool _hasRawWhitespaceOrControl(String value) {
    return value.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7F);
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
