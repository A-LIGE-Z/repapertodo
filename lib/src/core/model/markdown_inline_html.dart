import 'package:markdown/markdown.dart' as md;

List<md.InlineSyntax> paperTodoMarkdownInlineHtmlSyntaxes() {
  return [PaperTodoMarkdownInlineHtmlSyntax()];
}

class PaperTodoMarkdownInlineHtmlSyntax extends md.InlineSyntax {
  PaperTodoMarkdownInlineHtmlSyntax()
      : super(
          r'<',
          startCharacter: 0x3C,
          caseSensitive: false,
        );

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final openStart = startMatchPos ?? parser.pos;
    if (openStart != parser.pos ||
        openStart >= parser.source.length ||
        parser.source.codeUnitAt(openStart) != 0x3C) {
      return false;
    }

    final span = _tryParseHtmlInlineSpan(parser.source, openStart);
    if (span == null) {
      return false;
    }

    final content = parser.source.substring(span.openEnd, span.closeStart);
    parser.writeText();
    parser.addNode(
      _inlineElement(
        parser,
        span.tagName,
        content,
        href: span.href,
      ),
    );
    parser.consume(span.closeEnd - openStart);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;

  static _HtmlInlineSpan? _tryParseHtmlInlineSpan(
    String text,
    int openStart,
  ) {
    final openTag = _tryParseHtmlOpeningTag(text, openStart);
    if (openTag == null) {
      return null;
    }

    final closeTag = _tryFindHtmlClosingTag(
      text,
      openTag.tagName,
      openTag.openEnd,
      _lineEndAfter(text, openStart),
    );
    if (closeTag == null || closeTag.closeStart <= openTag.openEnd) {
      return null;
    }

    return _HtmlInlineSpan(
      tagName: openTag.tagName,
      openEnd: openTag.openEnd,
      closeStart: closeTag.closeStart,
      closeEnd: closeTag.closeEnd,
      href: openTag.href,
    );
  }

  static _HtmlOpenTag? _tryParseHtmlOpeningTag(
    String text,
    int openStart,
  ) {
    if (openStart + 2 >= text.length ||
        text[openStart] != '<' ||
        text[openStart + 1] == '/') {
      return null;
    }

    final nameStart = openStart + 1;
    var nameEnd = nameStart;
    while (nameEnd < text.length && _isHtmlTagNameChar(text[nameEnd])) {
      nameEnd++;
    }
    if (nameEnd == nameStart) {
      return null;
    }

    final tagName = text.substring(nameStart, nameEnd).toLowerCase();
    if (!_isSupportedHtmlInlineTag(tagName)) {
      return null;
    }

    final tagEnd = _findHtmlTagEnd(text, nameEnd);
    if (tagEnd < 0) {
      return null;
    }

    final attributes = text.substring(nameEnd, tagEnd);
    String? href;
    if (tagName == 'a') {
      href = _tryGetHtmlHrefAttribute(attributes)?.trim();
      if (href == null || href.isEmpty) {
        return null;
      }
    } else if (attributes.trim().isNotEmpty) {
      return null;
    }

    return _HtmlOpenTag(
      tagName: tagName,
      openEnd: tagEnd + 1,
      href: href,
    );
  }

  static _HtmlCloseTag? _tryFindHtmlClosingTag(
    String text,
    String tagName,
    int searchStart,
    int lineEnd,
  ) {
    var search = searchStart;
    while (search < lineEnd) {
      final closeStart = text.indexOf('</', search);
      if (closeStart < 0 || closeStart >= lineEnd) {
        return null;
      }

      var nameEnd = closeStart + 2;
      while (nameEnd < lineEnd && _isHtmlTagNameChar(text[nameEnd])) {
        nameEnd++;
      }

      if (nameEnd > closeStart + 2 &&
          text.substring(closeStart + 2, nameEnd).toLowerCase() == tagName) {
        var end = nameEnd;
        while (end < lineEnd && text[end].trim().isEmpty) {
          end++;
        }
        if (end < lineEnd && text[end] == '>') {
          return _HtmlCloseTag(
            closeStart: closeStart,
            closeEnd: end + 1,
          );
        }
      }

      search = closeStart + 2;
    }
    return null;
  }

  static int _findHtmlTagEnd(String text, int start) {
    var quote = '';
    for (var index = start; index < text.length; index++) {
      final char = text[index];
      if (char == '\r' || char == '\n') {
        return -1;
      }
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
        return index;
      }
    }
    return -1;
  }

  static md.Element _inlineElement(
    md.InlineParser parser,
    String tag,
    String content, {
    String? href,
  }) {
    return switch (tag) {
      'a' => _linkElement(parser, href!, content),
      'b' || 'strong' => md.Element(
          'strong',
          parser.document.parseInline(content),
        ),
      'i' || 'em' => md.Element(
          'em',
          parser.document.parseInline(content),
        ),
      's' || 'del' => md.Element(
          'del',
          parser.document.parseInline(content),
        ),
      'u' => md.Element.text('u', content),
      'code' => md.Element.text('code', content),
      _ => md.Element.text('span', content),
    };
  }

  static md.Element _linkElement(
    md.InlineParser parser,
    String href,
    String content,
  ) {
    final element = md.Element('a', parser.document.parseInline(content));
    element.attributes['href'] = href;
    return element;
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

      final value = _readAttributeValue(attributes, index);
      if (value == null) {
        return null;
      }
      index = value.end;

      if (name.toLowerCase() == 'href') {
        return value.text;
      }
    }
    return null;
  }

  static _HtmlAttributeValue? _readAttributeValue(
    String attributes,
    int start,
  ) {
    if (attributes[start] == '"' || attributes[start] == "'") {
      final quote = attributes[start];
      final valueStart = start + 1;
      final valueEnd = attributes.indexOf(quote, valueStart);
      if (valueEnd < 0) {
        return null;
      }
      return _HtmlAttributeValue(
        text: attributes.substring(valueStart, valueEnd),
        end: valueEnd + 1,
      );
    }

    var end = start;
    while (end < attributes.length && attributes[end].trim().isNotEmpty) {
      end++;
    }
    return _HtmlAttributeValue(
      text: attributes.substring(start, end),
      end: end,
    );
  }

  static int _lineEndAfter(String text, int offset) {
    for (var index = offset; index < text.length; index++) {
      if (text[index] == '\r' || text[index] == '\n') {
        return index;
      }
    }
    return text.length;
  }

  static bool _isSupportedHtmlInlineTag(String tagName) {
    return switch (tagName) {
      'b' ||
      'strong' ||
      'i' ||
      'em' ||
      's' ||
      'del' ||
      'u' ||
      'code' ||
      'a' =>
        true,
      _ => false,
    };
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
}

class _HtmlInlineSpan {
  const _HtmlInlineSpan({
    required this.tagName,
    required this.openEnd,
    required this.closeStart,
    required this.closeEnd,
    required this.href,
  });

  final String tagName;
  final int openEnd;
  final int closeStart;
  final int closeEnd;
  final String? href;
}

class _HtmlOpenTag {
  const _HtmlOpenTag({
    required this.tagName,
    required this.openEnd,
    required this.href,
  });

  final String tagName;
  final int openEnd;
  final String? href;
}

class _HtmlCloseTag {
  const _HtmlCloseTag({
    required this.closeStart,
    required this.closeEnd,
  });

  final int closeStart;
  final int closeEnd;
}

class _HtmlAttributeValue {
  const _HtmlAttributeValue({
    required this.text,
    required this.end,
  });

  final String text;
  final int end;
}
