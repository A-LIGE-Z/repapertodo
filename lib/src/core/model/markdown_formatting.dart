import 'package:flutter/services.dart';

abstract final class MarkdownFormatting {
  static const defaultLinkLabel = 'link';

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
