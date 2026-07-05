import 'package:flutter/services.dart';

abstract final class MarkdownFormatting {
  static const defaultLinkLabel = 'Link';
  static const tabIndent = '\t';

  static TextEditingValue wrapSelection(
    TextEditingValue value,
    String prefix,
    String suffix,
  ) {
    final selection = _normalizedSelection(value);
    final start = selection.start;
    final end = selection.end;
    final selected = value.text.substring(start, end);
    final wrapEachLine = !selection.isCollapsed &&
        _hasLineBreak(selected) &&
        !_hasLineBreak(prefix) &&
        !_hasLineBreak(suffix);
    final replacement = wrapEachLine
        ? _wrapEachSelectedLine(selected, prefix, suffix)
        : '$prefix$selected$suffix';
    final text = value.text.replaceRange(start, end, replacement);

    if (selection.isCollapsed) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: start + prefix.length),
      );
    }
    if (wrapEachLine) {
      return TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: start,
          extentOffset: start + replacement.length,
        ),
      );
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: start + prefix.length,
        extentOffset: start + prefix.length + selected.length,
      ),
    );
  }

  static TextEditingValue insertLinePrefix(
    TextEditingValue value,
    String prefix,
  ) {
    final selection = _normalizedSelection(value);
    final start = selection.start;
    final searchFrom = start == 0 ? 0 : start - 1;
    final previousBreak = value.text.lastIndexOf('\n', searchFrom);
    final lineStart = previousBreak < 0 ? 0 : previousBreak + 1;
    final text = value.text.replaceRange(lineStart, lineStart, prefix);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + prefix.length),
    );
  }

  static TextEditingValue insertMarkdownLink(
    TextEditingValue value, {
    String defaultLabel = defaultLinkLabel,
  }) {
    final selection = _normalizedSelection(value);
    final start = selection.start;
    final end = selection.end;
    final selected = value.text.substring(start, end);
    final label = selected.trim().isEmpty ? defaultLabel : selected;
    final markdown = '[$label](https://)';
    final text = value.text.replaceRange(start, end, markdown);
    final urlStart = start + markdown.lastIndexOf('https://');
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: urlStart,
        extentOffset: urlStart + 'https://'.length,
      ),
    );
  }

  static TextEditingValue handleTab(
    TextEditingValue value, {
    bool outdent = false,
  }) {
    final selection = _normalizedSelection(value);
    if (selection.isCollapsed && !outdent) {
      final offset = selection.start;
      final text = value.text.replaceRange(offset, offset, tabIndent);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset + tabIndent.length),
      );
    }

    final lineRange = _selectedLineRange(value.text, selection);
    return outdent
        ? _outdentLines(value, selection, lineRange)
        : _indentLines(value, selection, lineRange);
  }

  static TextSelection _normalizedSelection(TextEditingValue value) {
    final length = value.text.length;
    final selection = value.selection;
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: length);
    }
    final base = selection.baseOffset.clamp(0, length).toInt();
    final extent = selection.extentOffset.clamp(0, length).toInt();
    return TextSelection(
      baseOffset: base < extent ? base : extent,
      extentOffset: base < extent ? extent : base,
    );
  }

  static bool _hasLineBreak(String text) =>
      text.contains('\n') || text.contains('\r');

  static _LineRange _selectedLineRange(String text, TextSelection selection) {
    final start = selection.start.clamp(0, text.length).toInt();
    var end = selection.end.clamp(0, text.length).toInt();
    if (!selection.isCollapsed && end > start && text[end - 1] == '\n') {
      end--;
    }
    final lineStart = text.lastIndexOf('\n', start == 0 ? 0 : start - 1);
    final rangeStart = lineStart < 0 ? 0 : lineStart + 1;
    final lineEnd = text.indexOf('\n', end);
    final rangeEnd = lineEnd < 0 ? text.length : lineEnd;
    return _LineRange(rangeStart, rangeEnd);
  }

  static TextEditingValue _indentLines(
    TextEditingValue value,
    TextSelection selection,
    _LineRange lineRange,
  ) {
    final buffer = StringBuffer();
    var index = lineRange.start;
    var inserted = 0;
    var firstLine = true;
    while (index <= lineRange.end) {
      if (!firstLine) {
        buffer.write('\n');
      }
      firstLine = false;
      buffer.write(tabIndent);
      inserted += tabIndent.length;
      final nextBreak = value.text.indexOf('\n', index);
      final lineEnd = nextBreak < 0 || nextBreak > lineRange.end
          ? lineRange.end
          : nextBreak;
      buffer.write(value.text.substring(index, lineEnd));
      if (nextBreak < 0 || nextBreak >= lineRange.end) {
        break;
      }
      index = nextBreak + 1;
    }

    final replacement = buffer.toString();
    final text =
        value.text.replaceRange(lineRange.start, lineRange.end, replacement);
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: selection.start + tabIndent.length,
        extentOffset: selection.end + inserted,
      ),
    );
  }

  static TextEditingValue _outdentLines(
    TextEditingValue value,
    TextSelection selection,
    _LineRange lineRange,
  ) {
    final buffer = StringBuffer();
    var index = lineRange.start;
    var removedBeforeStart = 0;
    var removedBeforeEnd = 0;
    var firstLine = true;
    while (index <= lineRange.end) {
      if (!firstLine) {
        buffer.write('\n');
      }
      firstLine = false;
      final nextBreak = value.text.indexOf('\n', index);
      final lineEnd = nextBreak < 0 || nextBreak > lineRange.end
          ? lineRange.end
          : nextBreak;
      final line = value.text.substring(index, lineEnd);
      final removeCount = _leadingIndentToRemove(line);
      if (index < selection.start) {
        removedBeforeStart += removeCount;
      }
      if (index < selection.end) {
        removedBeforeEnd += removeCount;
      }
      buffer.write(line.substring(removeCount));
      if (nextBreak < 0 || nextBreak >= lineRange.end) {
        break;
      }
      index = nextBreak + 1;
    }

    final replacement = buffer.toString();
    final text =
        value.text.replaceRange(lineRange.start, lineRange.end, replacement);
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: (selection.start - removedBeforeStart)
            .clamp(0, text.length)
            .toInt(),
        extentOffset:
            (selection.end - removedBeforeEnd).clamp(0, text.length).toInt(),
      ),
    );
  }

  static int _leadingIndentToRemove(String line) {
    if (line.startsWith(tabIndent)) {
      return tabIndent.length;
    }
    var spaces = 0;
    while (spaces < line.length && spaces < 4 && line[spaces] == ' ') {
      spaces++;
    }
    return spaces;
  }

  static String _wrapEachSelectedLine(
    String selected,
    String prefix,
    String suffix,
  ) {
    final buffer = StringBuffer();
    var index = 0;

    while (index < selected.length) {
      final lineStart = index;
      while (index < selected.length &&
          selected[index] != '\r' &&
          selected[index] != '\n') {
        index++;
      }

      final line = selected.substring(lineStart, index);
      buffer.write(line.trim().isEmpty ? line : '$prefix$line$suffix');

      if (index >= selected.length) {
        break;
      }

      if (selected[index] == '\r' &&
          index + 1 < selected.length &&
          selected[index + 1] == '\n') {
        buffer.write('\r\n');
        index += 2;
      } else {
        buffer.write(selected[index]);
        index++;
      }
    }

    return buffer.toString();
  }
}

class _LineRange {
  const _LineRange(this.start, this.end);

  final int start;
  final int end;
}
