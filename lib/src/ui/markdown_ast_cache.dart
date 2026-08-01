import '../core/model/markdown_line_analysis.dart';

/// Incremental AST cache for Markdown documents to avoid re-parsing
/// unchanged text lines during live editing.
class MarkdownAstCache {
  MarkdownAstCache({int maxCachedLines = 1000})
      : _maxCachedLines = maxCachedLines;

  final int _maxCachedLines;
  final Map<String, MarkdownLineStyle> _cache = {};

  Iterable<String> _splitLines(String text) sync* {
    if (text.isEmpty) {
      yield '';
      return;
    }
    var start = 0;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char != '\r' && char != '\n') continue;
      yield text.substring(start, index);
      if (char == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
        index++;
      }
      start = index + 1;
    }
    yield text.substring(start);
  }

  /// Analyzes a Markdown [text] into a list of [MarkdownLineStyle] objects,
  /// reusing cached parsed styles for unchanged lines.
  List<MarkdownLineStyle> analyzeLines(String text) {
    if (text.isEmpty) {
      // Must match _logicalLines which yields 1 empty line for empty string
      final style = MarkdownLineAnalysis.analyzeLine('', isInFencedCodeBlock: false);
      return [style];
    }

    final styles = <MarkdownLineStyle>[];
    var isInFence = false;

    for (final line in _splitLines(text)) {
      final key = '${isInFence ? '1' : '0'}|$line';
      var style = _cache[key];
      
      if (style == null) {
        style = MarkdownLineAnalysis.analyzeLine(line, isInFencedCodeBlock: isInFence);
        if (_cache.length >= _maxCachedLines) {
          _cache.clear();
        }
        _cache[key] = style;
      }
      
      styles.add(style);
      if (style.kind == MarkdownLineKind.codeFence) {
        isInFence = !isInFence;
      }
    }

    return styles;
  }

  /// Clears all cached Markdown AST nodes.
  void clear() {
    _cache.clear();
  }
}
