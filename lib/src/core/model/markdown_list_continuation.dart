import 'package:flutter/services.dart';

abstract final class MarkdownListContinuation {
  static TextEditingValue formatEnter(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!_isPlainEnter(oldValue, newValue)) {
      return newValue;
    }

    final caret = oldValue.selection.baseOffset;
    final line = _lineAt(oldValue.text, caret);
    final style = _analyzeList(line.text);
    if (style == null) {
      return newValue;
    }

    final indexInLine = caret - line.start;
    if (indexInLine < style.contentStart.clamp(0, line.text.length)) {
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

    final continuation = _continuationFor(style, line.text);
    if (continuation == null) {
      return newValue;
    }
    final text = oldValue.text.replaceRange(caret, caret, '\n$continuation');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: caret + 1 + continuation.length,
      ),
    );
  }

  static bool _isPlainEnter(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (!selection.isCollapsed || !newValue.selection.isCollapsed) {
      return false;
    }
    final caret = selection.baseOffset;
    if (caret < 0 || caret > oldValue.text.length) {
      return false;
    }
    final expected = oldValue.text.replaceRange(caret, caret, '\n');
    return newValue.text == expected &&
        newValue.selection.baseOffset == caret + 1;
  }

  static _MarkdownLine _lineAt(String text, int caret) {
    final safeCaret = caret.clamp(0, text.length).toInt();
    final before = text.lastIndexOf('\n', safeCaret - 1);
    final after = text.indexOf('\n', safeCaret);
    final start = before < 0 ? 0 : before + 1;
    final end = after < 0 ? text.length : after;
    return _MarkdownLine(start: start, text: text.substring(start, end));
  }

  static _ListStyle? _analyzeList(String text) {
    if (text.isEmpty) {
      return null;
    }
    final indent = _countIndent(text);
    final byIndent = _tryAnalyzeList(text, indent);
    if (byIndent != null) {
      return byIndent;
    }
    final leadingSpaces = _countLeadingSpaces(text);
    if (leadingSpaces != indent) {
      return _tryAnalyzeList(text, leadingSpaces);
    }
    return null;
  }

  static _ListStyle? _tryAnalyzeList(String text, int start) {
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
      final style = _ListStyle.unordered(
        markerStart: start,
        contentStart: end,
      );
      return style.copyWith(isTask: _isTaskList(style, text));
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
    final number = int.tryParse(text.substring(start, delimiter));
    if (number == null) {
      return null;
    }
    final style = _ListStyle.ordered(
      markerStart: start,
      contentStart: end,
      number: number,
      delimiter: text[delimiter],
    );
    return style.copyWith(isTask: _isTaskList(style, text));
  }

  static String? _continuationFor(_ListStyle style, String text) {
    final taskSuffix = style.isTask ? '[ ] ' : '';
    if (style.kind == _ListKind.unordered) {
      return '${text.substring(0, style.contentStart)}$taskSuffix';
    }
    final markerEnd = style.markerStart + style.number.toString().length + 1;
    if (markerEnd > style.contentStart || markerEnd > text.length) {
      return null;
    }
    return '${text.substring(0, style.markerStart)}'
        '${style.number + 1}${style.delimiter}'
        '${text.substring(markerEnd, style.contentStart)}'
        '$taskSuffix';
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

  static bool _isTaskList(_ListStyle style, String text) {
    if (style.contentStart + 2 >= text.length) {
      return false;
    }
    final start = style.contentStart;
    final value = text[start + 1];
    return text[start] == '[' &&
        text[start + 2] == ']' &&
        (value == ' ' || value == 'x' || value == 'X');
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

  static bool _isWhitespace(String value) => value.trim().isEmpty;

  static bool _isDigit(String value) {
    if (value.length != 1) {
      return false;
    }
    final codeUnit = value.codeUnitAt(0);
    return codeUnit >= 0x30 && codeUnit <= 0x39;
  }
}

class _MarkdownLine {
  const _MarkdownLine({required this.start, required this.text});

  final int start;
  final String text;
}

enum _ListKind { unordered, ordered }

class _ListStyle {
  const _ListStyle._({
    required this.kind,
    required this.markerStart,
    required this.contentStart,
    required this.number,
    required this.delimiter,
    required this.isTask,
  });

  factory _ListStyle.unordered({
    required int markerStart,
    required int contentStart,
  }) {
    return _ListStyle._(
      kind: _ListKind.unordered,
      markerStart: markerStart,
      contentStart: contentStart,
      number: 0,
      delimiter: '',
      isTask: false,
    );
  }

  factory _ListStyle.ordered({
    required int markerStart,
    required int contentStart,
    required int number,
    required String delimiter,
  }) {
    return _ListStyle._(
      kind: _ListKind.ordered,
      markerStart: markerStart,
      contentStart: contentStart,
      number: number,
      delimiter: delimiter,
      isTask: false,
    );
  }

  final _ListKind kind;
  final int markerStart;
  final int contentStart;
  final int number;
  final String delimiter;
  final bool isTask;

  _ListStyle copyWith({required bool isTask}) {
    return _ListStyle._(
      kind: kind,
      markerStart: markerStart,
      contentStart: contentStart,
      number: number,
      delimiter: delimiter,
      isTask: isTask,
    );
  }
}
