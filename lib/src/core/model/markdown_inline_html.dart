import 'package:markdown/markdown.dart' as md;

List<md.InlineSyntax> paperTodoMarkdownInlineHtmlSyntaxes() {
  return [PaperTodoMarkdownInlineHtmlSyntax()];
}

class PaperTodoMarkdownInlineHtmlSyntax extends md.InlineSyntax {
  PaperTodoMarkdownInlineHtmlSyntax()
      : super(
          r'<(b|strong|i|em|s|del|u|code)\s*>([^\r\n]*?)</\1\s*>|<a\b([^>\r\n]*)>([^\r\n]*?)</a\s*>',
          startCharacter: 0x3C,
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final styleTag = match[1]?.toLowerCase();
    if (styleTag != null) {
      final content = match[2] ?? '';
      parser.addNode(_styledElement(parser, styleTag, content));
      return true;
    }

    final href = _tryGetHtmlHrefAttribute(match[3] ?? '')?.trim();
    final content = match[4] ?? '';
    if (href == null || href.isEmpty || content.isEmpty) {
      return false;
    }

    final element = md.Element('a', parser.document.parseInline(content));
    element.attributes['href'] = href;
    parser.addNode(element);
    return true;
  }

  static md.Element _styledElement(
    md.InlineParser parser,
    String tag,
    String content,
  ) {
    return switch (tag) {
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

  static bool _isHtmlAttributeNameChar(String value) {
    final codeUnit = value.codeUnitAt(0);
    return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        value == '-' ||
        value == '_';
  }
}

class _HtmlAttributeValue {
  const _HtmlAttributeValue({
    required this.text,
    required this.end,
  });

  final String text;
  final int end;
}
