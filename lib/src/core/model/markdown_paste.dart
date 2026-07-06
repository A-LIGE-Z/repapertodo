import 'package:flutter/services.dart';

abstract final class MarkdownPasteText {
  static const maxTextLength = 100000;
  static const maxPasteLength = 30000;
  static const maxLineLength = 6000;

  static String sanitize(
    String text, {
    int pasteLengthLimit = maxPasteLength,
    int lineLengthLimit = maxLineLength,
  }) {
    if (pasteLengthLimit <= 0 || lineLengthLimit <= 0) {
      return '';
    }
    if (text.length <= pasteLengthLimit &&
        !_containsLineLongerThan(text, lineLengthLimit)) {
      return text;
    }
    return _clipPasteText(text, pasteLengthLimit, lineLengthLimit);
  }

  static String trimToMaxTextLength(String text) {
    if (text.length <= maxTextLength) {
      return text;
    }
    return text.substring(0, maxTextLength);
  }

  static TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final diff = _TextEditDiff.betweenValues(oldValue, newValue);
    final inserted = newValue.text.substring(diff.start, diff.newEnd);
    final preservedLength = oldValue.text.length - diff.removedLength;
    final pasteLengthLimit = (maxTextLength - preservedLength)
        .clamp(0, maxPasteLength)
        .toInt();
    final sanitizedInsert = inserted.isEmpty
        ? inserted
        : sanitize(
            inserted,
            pasteLengthLimit: pasteLengthLimit,
          );
    var text = oldValue.text.replaceRange(
      diff.start,
      diff.oldEnd,
      sanitizedInsert,
    );
    var selectionOffset = sanitizedInsert == inserted
        ? newValue.selection.extentOffset
        : diff.start + sanitizedInsert.length;
    if (text.length > maxTextLength) {
      text = trimToMaxTextLength(text);
      selectionOffset = selectionOffset.clamp(0, text.length).toInt();
    }
    if (text == newValue.text) {
      return newValue;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selectionOffset.clamp(0, text.length).toInt(),
      ),
    );
  }

  static String _clipPasteText(
    String text,
    int maxLength,
    int maxLineLength,
  ) {
    final buffer = StringBuffer();
    var lineLength = 0;
    for (final codeUnit in text.codeUnits) {
      if (buffer.length >= maxLength) {
        break;
      }
      final char = String.fromCharCode(codeUnit);
      if (char == '\r' || char == '\n') {
        buffer.write(char);
        lineLength = 0;
        continue;
      }
      if (lineLength >= maxLineLength) {
        break;
      }
      buffer.write(char);
      lineLength++;
    }
    return buffer.toString();
  }

  static bool _containsLineLongerThan(String text, int maxLength) {
    if (text.isEmpty || maxLength <= 0) {
      return false;
    }
    var lineLength = 0;
    for (final codeUnit in text.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      if (char == '\r' || char == '\n') {
        lineLength = 0;
        continue;
      }
      lineLength++;
      if (lineLength > maxLength) {
        return true;
      }
    }
    return false;
  }
}

class _TextEditDiff {
  const _TextEditDiff({
    required this.start,
    required this.oldEnd,
    required this.newEnd,
  });

  factory _TextEditDiff.between(String oldText, String newText) {
    final minLength =
        oldText.length < newText.length ? oldText.length : newText.length;
    var start = 0;
    while (start < minLength && oldText[start] == newText[start]) {
      start++;
    }
    if (start == 0 &&
        oldText.isNotEmpty &&
        newText.isNotEmpty &&
        oldText[0] != newText[0]) {
      return _TextEditDiff(
        start: 0,
        oldEnd: oldText.length,
        newEnd: newText.length,
      );
    }

    var oldEnd = oldText.length;
    var newEnd = newText.length;
    while (oldEnd > start &&
        newEnd > start &&
        oldText[oldEnd - 1] == newText[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }

    return _TextEditDiff(start: start, oldEnd: oldEnd, newEnd: newEnd);
  }

  factory _TextEditDiff.betweenValues(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (selection.isValid) {
      final oldText = oldValue.text;
      final newText = newValue.text;
      final start = selection.start.clamp(0, oldText.length).toInt();
      final oldEnd = selection.end.clamp(start, oldText.length).toInt();
      final suffixLength = oldText.length - oldEnd;
      final newEnd = newText.length - suffixLength;
      if (newEnd >= start &&
          newText.startsWith(oldText.substring(0, start)) &&
          newText.endsWith(oldText.substring(oldEnd))) {
        return _TextEditDiff(start: start, oldEnd: oldEnd, newEnd: newEnd);
      }
    }
    return _TextEditDiff.between(oldValue.text, newValue.text);
  }

  final int start;
  final int oldEnd;
  final int newEnd;

  int get removedLength => oldEnd - start;
}
