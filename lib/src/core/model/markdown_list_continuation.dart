import 'package:flutter/services.dart';

import 'markdown_line_analysis.dart';

abstract final class MarkdownListContinuation {
  static const _maxContinuableOrderedListNumber = 9223372036854775806;

  static TextEditingValue formatEnter(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final insertedNewline = _plainEnterNewline(oldValue, newValue);
    if (insertedNewline == null) {
      return newValue;
    }

    final caret = oldValue.selection.baseOffset;
    final line = _lineAt(oldValue.text, caret);
    final style = MarkdownLineAnalysis.analyzeLine(line.text);
    if (!style.isList) {
      return newValue;
    }

    final indexInLine = caret - line.start;
    if (indexInLine < style.contentStart.clamp(0, line.text.length)) {
      return newValue;
    }

    final newline = _newlineFor(oldValue.text, line, insertedNewline);
    final continuation = _continuationFor(style, line.text);
    if (continuation == null) {
      return newValue;
    }

    final emptyContentStart = style.isTask
        ? _taskContentStart(style.contentStart, line.text)
        : style.contentStart;
    if (_isLineContentEmpty(line.text, emptyContentStart)) {
      if (indexInLine < emptyContentStart.clamp(0, line.text.length)) {
        return newValue;
      }
      final removeStart = line.start + style.markerStart;
      final removeEnd = line.start +
          emptyContentStart.clamp(
            style.markerStart,
            line.text.length,
          );
      final text = oldValue.text.replaceRange(removeStart, removeEnd, '');
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: removeStart),
      );
    }

    final text =
        oldValue.text.replaceRange(caret, caret, '$newline$continuation');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: caret + newline.length + continuation.length,
      ),
    );
  }

  static String? _plainEnterNewline(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (!selection.isCollapsed || !newValue.selection.isCollapsed) {
      return null;
    }
    final caret = selection.baseOffset;
    if (caret < 0 || caret > oldValue.text.length) {
      return null;
    }
    for (final newline in const ['\r\n', '\n', '\r']) {
      final expected = oldValue.text.replaceRange(caret, caret, newline);
      if (newValue.text == expected &&
          newValue.selection.baseOffset == caret + newline.length) {
        return newline;
      }
    }
    return null;
  }

  static _MarkdownLine _lineAt(String text, int caret) {
    final safeCaret = caret.clamp(0, text.length).toInt();
    var start = 0;
    for (var index = safeCaret - 1; index >= 0; index--) {
      if (text[index] == '\n' || text[index] == '\r') {
        start = index + 1;
        break;
      }
    }

    var end = safeCaret;
    while (end < text.length && text[end] != '\n' && text[end] != '\r') {
      end++;
    }

    var delimiter = '';
    if (end < text.length) {
      if (text[end] == '\r' && end + 1 < text.length && text[end + 1] == '\n') {
        delimiter = '\r\n';
      } else {
        delimiter = text[end];
      }
    }

    return _MarkdownLine(
      start: start,
      text: text.substring(start, end),
      delimiter: delimiter,
    );
  }

  static String? _continuationFor(MarkdownLineStyle style, String text) {
    final taskSuffix = style.isTask ? '[ ] ' : '';
    if (style.isUnorderedList) {
      return '${text.substring(0, style.contentStart)}$taskSuffix';
    }
    final numberText = style.orderedNumberText;
    final delimiter = style.orderedDelimiter;
    if (!style.isOrderedList ||
        numberText == null ||
        delimiter == null ||
        style.markerEnd > style.contentStart ||
        style.markerEnd > text.length) {
      return null;
    }
    final number = int.tryParse(numberText);
    if (number == null || number > _maxContinuableOrderedListNumber) {
      return null;
    }
    return '${text.substring(0, style.markerStart)}'
        '${number + 1}$delimiter'
        '${text.substring(style.markerEnd, style.contentStart)}'
        '$taskSuffix';
  }

  static int _taskContentStart(int contentStart, String text) {
    var start = (contentStart + 3).clamp(0, text.length).toInt();
    while (start < text.length && _isWhitespace(text[start])) {
      start++;
    }
    return start;
  }

  static bool _isLineContentEmpty(String text, int contentStart) {
    for (var i = contentStart.clamp(0, text.length).toInt();
        i < text.length;
        i++) {
      if (!_isWhitespace(text[i])) {
        return false;
      }
    }
    return true;
  }

  static String _newlineFor(
    String text,
    _MarkdownLine line,
    String insertedNewline,
  ) {
    if (line.delimiter.isNotEmpty) {
      return line.delimiter;
    }
    return _firstLineDelimiter(text) ?? insertedNewline;
  }

  static String? _firstLineDelimiter(String text) {
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '\r') {
        if (index + 1 < text.length && text[index + 1] == '\n') {
          return '\r\n';
        }
        return '\r';
      }
      if (char == '\n') {
        return '\n';
      }
    }
    return null;
  }

  static bool _isWhitespace(String value) => value.trim().isEmpty;
}

class _MarkdownLine {
  const _MarkdownLine({
    required this.start,
    required this.text,
    required this.delimiter,
  });

  final int start;
  final String text;
  final String delimiter;
}
