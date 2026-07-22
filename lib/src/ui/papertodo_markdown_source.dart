import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/model/markdown_line_analysis.dart';
import '../core/model/markdown_links.dart';
import 'papertodo_theme.dart';

const _codeFontFamily = 'Cascadia Mono';
const _codeFontFamilyFallback = [
  'Consolas',
  'Microsoft YaHei UI',
  'Segoe UI Symbol',
  'Segoe UI Emoji',
];
const _paperTodoPreviewLineHeight = 1.26;
const _paperTodoHiddenListMarkerFontSize = 12.0;
const _supportedHtmlTags = {
  'a',
  'b',
  'strong',
  'i',
  'em',
  's',
  'del',
  'u',
  'code',
};

class PaperTodoMarkdownSourcePreview extends StatefulWidget {
  const PaperTodoMarkdownSourcePreview({
    super.key,
    required this.data,
    required this.textZoom,
    required this.lineSpacing,
    required this.enhanced,
    required this.onTapLink,
    this.onTap,
  });

  final String data;
  final double textZoom;
  final double lineSpacing;
  final bool enhanced;
  final ValueChanged<String> onTapLink;
  final VoidCallback? onTap;

  @override
  State<PaperTodoMarkdownSourcePreview> createState() =>
      _PaperTodoMarkdownSourcePreviewState();
}

class _PaperTodoMarkdownSourcePreviewState
    extends State<PaperTodoMarkdownSourcePreview> {
  List<TapGestureRecognizer> _recognizers = [];

  @override
  Widget build(BuildContext context) {
    final oldRecognizers = _recognizers;
    final nextRecognizers = <TapGestureRecognizer>[];
    _recognizers = nextRecognizers;
    if (oldRecognizers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final recognizer in oldRecognizers) {
          recognizer.dispose();
        }
      });
    }

    final lines = widget.data.split(RegExp(r'\r\n|\r|\n'));
    final analyses = MarkdownLineAnalysis.analyzeLines(widget.data);
    final colors = PaperTodoThemeColors.of(context);
    final baseStyle = PaperTodoTypography.of(context)
        .contentStyle(
          Theme.of(context).textTheme.bodyMedium ??
              const TextStyle(fontSize: 14),
        )
        .copyWith(
          fontSize: 14 * widget.textZoom,
          height: _paperTodoPreviewLineHeight,
          color: colors.text,
          fontWeight: FontWeight.normal,
        );

    return SelectionArea(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < lines.length; index++)
              _line(
                context,
                index: index,
                text: lines[index],
                analysis: analyses[index],
                previousAnalysis: index == 0 ? null : analyses[index - 1],
                nextAnalysis:
                    index + 1 == analyses.length ? null : analyses[index + 1],
                colors: colors,
                baseStyle: baseStyle,
                recognizers: nextRecognizers,
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(
    BuildContext context, {
    required int index,
    required String text,
    required MarkdownLineStyle analysis,
    required MarkdownLineStyle? previousAnalysis,
    required MarkdownLineStyle? nextAnalysis,
    required PaperTodoThemeColors colors,
    required TextStyle baseStyle,
    required List<TapGestureRecognizer> recognizers,
  }) {
    final minimumLineHeight = 14 * widget.textZoom * widget.lineSpacing;
    if (analysis.kind == MarkdownLineKind.horizontalRule) {
      return SizedBox(
        key: ValueKey('papertodo-markdown-line-$index'),
        height: minimumLineHeight,
        child: Center(
          child: Divider(
            height: 1,
            thickness: 1,
            color: colors.paperBorder,
          ),
        ),
      );
    }

    final lineStyle = _lineStyle(baseStyle, analysis, colors);
    final paintsBlockBackground = analysis.isHeading ||
        analysis.kind == MarkdownLineKind.quote ||
        analysis.kind == MarkdownLineKind.codeFence ||
        analysis.kind == MarkdownLineKind.codeBlock;
    final visibleText = text.isEmpty ? '\u200B' : text;
    final line = Container(
      key: ValueKey('papertodo-markdown-line-$index'),
      constraints: BoxConstraints(minHeight: minimumLineHeight),
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (paintsBlockBackground)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: ValueKey('papertodo-markdown-background-$index'),
                    painter: _PaperTodoMarkdownBlockPainter(
                      kind: analysis.kind,
                      colors: colors,
                      codeContinuesAbove: _isCode(previousAnalysis),
                      codeContinuesBelow: _isCode(nextAnalysis),
                    ),
                  ),
                ),
              ),
            Text.rich(
              _lineSpan(
                visibleText,
                analysis: analysis,
                colors: colors,
                baseStyle: lineStyle,
                recognizers: recognizers,
              ),
              softWrap: true,
              textAlign: TextAlign.start,
              strutStyle: StrutStyle(
                fontFamily: baseStyle.fontFamily,
                fontFamilyFallback: baseStyle.fontFamilyFallback,
                fontSize: 14 * widget.textZoom,
                height: widget.lineSpacing,
              ),
            ),
            if (widget.enhanced && analysis.isList && !analysis.isTask)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: ValueKey('papertodo-markdown-list-marker-$index'),
                    painter: _PaperTodoMarkdownListMarkerPainter(
                      text: text,
                      analysis: analysis,
                      style: baseStyle.copyWith(
                        fontSize: 14 * widget.textZoom,
                        color: colors.text,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final paintOffset = _previewLinePaintOffset(
      text: text,
      analysis: analysis,
      previousAnalysis: previousAnalysis,
    );
    if (paintOffset == Offset.zero) return line;
    return Transform.translate(
      key: ValueKey('papertodo-markdown-line-metrics-$index'),
      offset: paintOffset,
      child: line,
    );
  }

  bool _isCode(MarkdownLineStyle? analysis) {
    return analysis?.kind == MarkdownLineKind.codeFence ||
        analysis?.kind == MarkdownLineKind.codeBlock;
  }

  Offset _previewLinePaintOffset({
    required String text,
    required MarkdownLineStyle analysis,
    required MarkdownLineStyle? previousAnalysis,
  }) {
    if (analysis.kind == MarkdownLineKind.heading1) {
      return const Offset(-1, 2);
    }
    if (analysis.kind == MarkdownLineKind.quote) {
      return const Offset(-1, 0);
    }
    if (analysis.kind == MarkdownLineKind.codeFence ||
        analysis.kind == MarkdownLineKind.codeBlock) {
      return const Offset(0, -2);
    }
    if (analysis.isList) {
      return previousAnalysis?.isList == true
          ? Offset.zero
          : const Offset(0, -2);
    }
    if (text.isNotEmpty) {
      return Offset.zero;
    }
    return Offset.zero;
  }

  TextStyle _lineStyle(
    TextStyle base,
    MarkdownLineStyle analysis,
    PaperTodoThemeColors colors,
  ) {
    if (analysis.isList) {
      return base.copyWith(letterSpacing: -0.075);
    }
    return switch (analysis.kind) {
      MarkdownLineKind.heading1 => base.copyWith(
          fontSize: 19 * widget.textZoom,
          fontWeight: FontWeight.w600,
        ),
      MarkdownLineKind.heading2 => base.copyWith(
          fontSize: 16.5 * widget.textZoom,
          fontWeight: FontWeight.w600,
        ),
      MarkdownLineKind.heading3 => base.copyWith(
          fontSize: 15 * widget.textZoom,
          fontWeight: FontWeight.w600,
        ),
      MarkdownLineKind.heading => base.copyWith(fontWeight: FontWeight.w600),
      MarkdownLineKind.quote => base.copyWith(
          color: colors.weakText,
          letterSpacing: 0.05,
        ),
      MarkdownLineKind.codeFence || MarkdownLineKind.codeBlock => base.copyWith(
          fontFamily: _codeFontFamily,
          fontFamilyFallback: _codeFontFamilyFallback,
          fontSize: 13 * widget.textZoom,
          letterSpacing: 0.4,
        ),
      _ => base.copyWith(letterSpacing: -0.09),
    };
  }

  TextSpan _lineSpan(
    String text, {
    required MarkdownLineStyle analysis,
    required PaperTodoThemeColors colors,
    required TextStyle baseStyle,
    required List<TapGestureRecognizer> recognizers,
  }) {
    final syntaxColor = widget.enhanced
        ? colors.text.withValues(alpha: colors.isDark ? 78 / 255 : 72 / 255)
        : colors.active;
    final patches = <_MarkdownStylePatch>[];
    final ignored = <_MarkdownRange>[];
    final normalSymbolStyle = TextStyle(color: syntaxColor);
    final codeStyle = TextStyle(
      color: colors.active,
      backgroundColor: colors.code,
      fontFamily: _codeFontFamily,
      fontFamilyFallback: _codeFontFamilyFallback,
      fontSize: 13 * widget.textZoom,
      fontStyle: FontStyle.normal,
      fontWeight: FontWeight.normal,
    );

    if (analysis.markerEnd > analysis.markerStart) {
      final hidesEnhancedMarker = widget.enhanced &&
          (analysis.kind == MarkdownLineKind.quote ||
              (analysis.isList && !analysis.isTask));
      patches.add(
        _MarkdownStylePatch(
          analysis.markerStart,
          analysis.markerEnd.clamp(0, text.length),
          hidesEnhancedMarker
              ? TextStyle(
                  color: Colors.transparent,
                  fontSize: analysis.isList && !analysis.isTask
                      ? _paperTodoHiddenListMarkerFontSize * widget.textZoom
                      : null,
                )
              : analysis.kind == MarkdownLineKind.codeFence
                  ? codeStyle.copyWith(color: syntaxColor)
                  : normalSymbolStyle,
        ),
      );
    }
    if (analysis.kind == MarkdownLineKind.codeBlock ||
        analysis.kind == MarkdownLineKind.codeFence) {
      patches.add(
        _MarkdownStylePatch(
          0,
          text.length,
          codeStyle.copyWith(color: colors.text),
        ),
      );
      if (analysis.kind == MarkdownLineKind.codeFence) {
        patches.add(
          _MarkdownStylePatch(
              0,
              text.length,
              codeStyle.copyWith(
                color: syntaxColor,
              )),
        );
      }
      return _segments(text, baseStyle, patches);
    }

    _addInlineCode(text, patches, ignored, normalSymbolStyle, codeStyle);
    _addLinks(
      text,
      patches,
      ignored,
      normalSymbolStyle,
      syntaxColor,
      colors,
      recognizers,
    );
    _addHtmlInlineTags(
      text,
      patches,
      ignored,
      normalSymbolStyle,
      codeStyle,
    );
    _addDelimited(
      text,
      delimiter: '~~',
      contentStyle: const TextStyle(decoration: TextDecoration.lineThrough),
      markerStyle: normalSymbolStyle,
      patches: patches,
      ignored: ignored,
    );
    _addDelimited(
      text,
      delimiter: '**',
      contentStyle: const TextStyle(fontWeight: FontWeight.w600),
      markerStyle: normalSymbolStyle,
      patches: patches,
      ignored: ignored,
    );
    _addDelimited(
      text,
      delimiter: '__',
      contentStyle: const TextStyle(fontWeight: FontWeight.w600),
      markerStyle: normalSymbolStyle,
      patches: patches,
      ignored: ignored,
    );
    _addSingleDelimited(
      text,
      delimiter: '*',
      markerStyle: normalSymbolStyle,
      patches: patches,
      ignored: ignored,
    );
    _addSingleDelimited(
      text,
      delimiter: '_',
      markerStyle: normalSymbolStyle,
      patches: patches,
      ignored: ignored,
    );
    _addTaskMarker(text, analysis, patches, normalSymbolStyle, colors);
    return _segments(text, baseStyle, patches);
  }

  void _addInlineCode(
    String text,
    List<_MarkdownStylePatch> patches,
    List<_MarkdownRange> ignored,
    TextStyle markerStyle,
    TextStyle codeStyle,
  ) {
    var search = 0;
    while (search < text.length) {
      final start = text.indexOf('`', search);
      if (start < 0) return;
      final end = text.indexOf('`', start + 1);
      if (end < 0) {
        patches.add(_MarkdownStylePatch(start, start + 1, markerStyle));
        return;
      }
      patches
        ..add(_MarkdownStylePatch(
            start,
            start + 1,
            markerStyle.copyWith(
              fontFamily: _codeFontFamily,
              fontFamilyFallback: _codeFontFamilyFallback,
              fontSize: 13 * widget.textZoom,
            )))
        ..add(_MarkdownStylePatch(start + 1, end, codeStyle))
        ..add(_MarkdownStylePatch(
            end,
            end + 1,
            markerStyle.copyWith(
              fontFamily: _codeFontFamily,
              fontFamilyFallback: _codeFontFamilyFallback,
              fontSize: 13 * widget.textZoom,
            )));
      ignored.add(_MarkdownRange(start, end + 1));
      search = end + 1;
    }
  }

  void _addLinks(
    String text,
    List<_MarkdownStylePatch> patches,
    List<_MarkdownRange> ignored,
    TextStyle symbolStyle,
    Color syntaxColor,
    PaperTodoThemeColors colors,
    List<TapGestureRecognizer> recognizers,
  ) {
    for (final link in MarkdownLinks.spans(text)) {
      if (_overlaps(ignored, link.start, link.end)) continue;
      final raw = text.substring(link.start, link.end);
      final labelEnd = raw.indexOf('](');
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onTapLink(link.href);
      recognizers.add(recognizer);
      if (labelEnd >= 1 && raw.startsWith('[')) {
        final absoluteLabelEnd = link.start + labelEnd;
        final urlStart = absoluteLabelEnd + 2;
        patches
          ..add(_MarkdownStylePatch(
            link.start,
            link.start + 1,
            symbolStyle,
            recognizer: recognizer,
          ))
          ..add(_MarkdownStylePatch(
            link.start + 1,
            absoluteLabelEnd,
            TextStyle(
              color: colors.link,
              decoration: TextDecoration.underline,
              decorationColor: colors.link,
            ),
            recognizer: recognizer,
          ))
          ..add(_MarkdownStylePatch(
            absoluteLabelEnd,
            urlStart,
            symbolStyle,
            recognizer: recognizer,
          ))
          ..add(_MarkdownStylePatch(
            urlStart,
            link.end - 1,
            TextStyle(
              color: widget.enhanced ? syntaxColor : colors.weakText,
            ),
            recognizer: recognizer,
          ))
          ..add(_MarkdownStylePatch(
            link.end - 1,
            link.end,
            symbolStyle,
            recognizer: recognizer,
          ));
      } else {
        final openEnd = raw.indexOf('>');
        final closeStart = raw.lastIndexOf('</');
        if (openEnd >= 0 && closeStart > openEnd) {
          patches
            ..add(_MarkdownStylePatch(
              link.start,
              link.start + openEnd + 1,
              symbolStyle,
              recognizer: recognizer,
            ))
            ..add(_MarkdownStylePatch(
              link.start + openEnd + 1,
              link.start + closeStart,
              TextStyle(
                color: colors.link,
                decoration: TextDecoration.underline,
                decorationColor: colors.link,
              ),
              recognizer: recognizer,
            ))
            ..add(_MarkdownStylePatch(
              link.start + closeStart,
              link.end,
              symbolStyle,
              recognizer: recognizer,
            ));
        }
      }
      ignored.add(_MarkdownRange(link.start, link.end));
    }
  }

  void _addDelimited(
    String text, {
    required String delimiter,
    required TextStyle contentStyle,
    required TextStyle markerStyle,
    required List<_MarkdownStylePatch> patches,
    required List<_MarkdownRange> ignored,
  }) {
    var search = 0;
    while (search < text.length) {
      final start = text.indexOf(delimiter, search);
      if (start < 0) return;
      final contentStart = start + delimiter.length;
      final end = text.indexOf(delimiter, contentStart);
      if (end < 0) return;
      final spanEnd = end + delimiter.length;
      if (end > contentStart && !_overlaps(ignored, start, spanEnd)) {
        patches
          ..add(_MarkdownStylePatch(start, contentStart, markerStyle))
          ..add(_MarkdownStylePatch(contentStart, end, contentStyle))
          ..add(_MarkdownStylePatch(end, spanEnd, markerStyle));
      }
      search = spanEnd;
    }
  }

  void _addHtmlInlineTags(
    String text,
    List<_MarkdownStylePatch> patches,
    List<_MarkdownRange> ignored,
    TextStyle markerStyle,
    TextStyle codeStyle,
  ) {
    for (final html in _htmlInlineSpans(text)) {
      if (_overlaps(ignored, html.start, html.end)) continue;
      patches
        ..add(_MarkdownStylePatch(html.start, html.openEnd, markerStyle))
        ..add(_MarkdownStylePatch(html.closeStart, html.end, markerStyle));
      final contentStyle = switch (html.tagName) {
        'b' || 'strong' => const TextStyle(fontWeight: FontWeight.w600),
        'i' || 'em' => const TextStyle(fontStyle: FontStyle.italic),
        's' || 'del' => const TextStyle(decoration: TextDecoration.lineThrough),
        'u' => const TextStyle(decoration: TextDecoration.underline),
        'code' => codeStyle,
        _ => const TextStyle(),
      };
      patches.add(
        _MarkdownStylePatch(html.openEnd, html.closeStart, contentStyle),
      );
      ignored.add(_MarkdownRange(html.start, html.end));
    }
  }

  Iterable<_MarkdownHtmlSpan> _htmlInlineSpans(String text) sync* {
    var search = 0;
    while (search < text.length) {
      final start = text.indexOf('<', search);
      if (start < 0) return;
      final open = _parseHtmlOpenTag(text, start);
      if (open == null) {
        search = start + 1;
        continue;
      }
      final close = _findHtmlCloseTag(
        text,
        open.tagName,
        open.openEnd,
      );
      if (close == null || close.closeStart <= open.openEnd) {
        search = open.openEnd;
        continue;
      }
      yield _MarkdownHtmlSpan(
        start: start,
        openEnd: open.openEnd,
        closeStart: close.closeStart,
        end: close.end,
        tagName: open.tagName,
      );
      search = close.end;
    }
  }

  _MarkdownHtmlOpenTag? _parseHtmlOpenTag(String text, int start) {
    if (start + 2 >= text.length || text[start + 1] == '/') return null;
    var nameEnd = start + 1;
    while (nameEnd < text.length && _isHtmlTagNameChar(text[nameEnd])) {
      nameEnd++;
    }
    if (nameEnd == start + 1) return null;
    final tagName = text.substring(start + 1, nameEnd).toLowerCase();
    if (!_supportedHtmlTags.contains(tagName)) return null;
    final tagEnd = _findHtmlTagEnd(text, nameEnd);
    if (tagEnd < 0) return null;
    final attributes = text.substring(nameEnd, tagEnd).trim();
    if (tagName != 'a' && attributes.isNotEmpty) return null;
    return _MarkdownHtmlOpenTag(tagName, tagEnd + 1);
  }

  _MarkdownHtmlCloseTag? _findHtmlCloseTag(
    String text,
    String tagName,
    int start,
  ) {
    var search = start;
    while (search < text.length) {
      final closeStart = text.indexOf('</', search);
      if (closeStart < 0) return null;
      var nameEnd = closeStart + 2;
      while (nameEnd < text.length && _isHtmlTagNameChar(text[nameEnd])) {
        nameEnd++;
      }
      if (nameEnd > closeStart + 2 &&
          text.substring(closeStart + 2, nameEnd).toLowerCase() == tagName) {
        var end = nameEnd;
        while (end < text.length && text[end].trim().isEmpty) {
          end++;
        }
        if (end < text.length && text[end] == '>') {
          return _MarkdownHtmlCloseTag(closeStart, end + 1);
        }
      }
      search = closeStart + 2;
    }
    return null;
  }

  int _findHtmlTagEnd(String text, int start) {
    var quote = '';
    for (var index = start; index < text.length; index++) {
      final char = text[index];
      if (quote.isNotEmpty) {
        if (char == quote) quote = '';
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '>') return index;
    }
    return -1;
  }

  bool _isHtmlTagNameChar(String value) {
    final unit = value.codeUnitAt(0);
    return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
  }

  void _addSingleDelimited(
    String text, {
    required String delimiter,
    required TextStyle markerStyle,
    required List<_MarkdownStylePatch> patches,
    required List<_MarkdownRange> ignored,
  }) {
    var search = 0;
    while (search < text.length) {
      final start = _singleDelimiter(text, delimiter, search);
      if (start < 0) return;
      final end = _singleDelimiter(text, delimiter, start + 1);
      if (end < 0) return;
      if (end > start + 1 && !_overlaps(ignored, start, end + 1)) {
        patches
          ..add(_MarkdownStylePatch(start, start + 1, markerStyle))
          ..add(_MarkdownStylePatch(
            start + 1,
            end,
            const TextStyle(fontStyle: FontStyle.italic),
          ))
          ..add(_MarkdownStylePatch(end, end + 1, markerStyle));
      }
      search = end + 1;
    }
  }

  int _singleDelimiter(String text, String delimiter, int start) {
    for (var index = start; index < text.length; index++) {
      if (text[index] != delimiter) continue;
      final previousSame = index > 0 && text[index - 1] == delimiter;
      final nextSame = index + 1 < text.length && text[index + 1] == delimiter;
      if (!previousSame && !nextSame) return index;
    }
    return -1;
  }

  void _addTaskMarker(
    String text,
    MarkdownLineStyle analysis,
    List<_MarkdownStylePatch> patches,
    TextStyle markerStyle,
    PaperTodoThemeColors colors,
  ) {
    if (!analysis.isTask || analysis.contentStart + 2 >= text.length) return;
    final start = analysis.contentStart;
    final checked = text[start + 1] != ' ';
    patches
      ..add(_MarkdownStylePatch(start, start + 1, markerStyle))
      ..add(_MarkdownStylePatch(
        start + 1,
        start + 2,
        TextStyle(
          color: colors.active,
          fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
        ),
      ))
      ..add(_MarkdownStylePatch(start + 2, start + 3, markerStyle));
  }

  TextSpan _segments(
    String text,
    TextStyle baseStyle,
    List<_MarkdownStylePatch> patches,
  ) {
    final boundaries = <int>{0, text.length};
    for (final patch in patches) {
      boundaries
        ..add(patch.start.clamp(0, text.length))
        ..add(patch.end.clamp(0, text.length));
    }
    final points = boundaries.toList()..sort();
    final children = <InlineSpan>[];
    for (var index = 0; index + 1 < points.length; index++) {
      final start = points[index];
      final end = points[index + 1];
      if (end <= start) continue;
      var style = baseStyle;
      GestureRecognizer? recognizer;
      for (final patch in patches) {
        if (patch.start <= start && patch.end >= end) {
          style = style.merge(patch.style);
          recognizer ??= patch.recognizer;
        }
      }
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: style,
          recognizer: recognizer,
          mouseCursor: recognizer == null ? null : SystemMouseCursors.click,
        ),
      );
    }
    return TextSpan(style: baseStyle, children: children);
  }

  bool _overlaps(List<_MarkdownRange> ranges, int start, int end) {
    return ranges.any((range) => start < range.end && end > range.start);
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }
}

class _PaperTodoMarkdownBlockPainter extends CustomPainter {
  const _PaperTodoMarkdownBlockPainter({
    required this.kind,
    required this.colors,
    required this.codeContinuesAbove,
    required this.codeContinuesBelow,
  });

  final MarkdownLineKind kind;
  final PaperTodoThemeColors colors;
  final bool codeContinuesAbove;
  final bool codeContinuesBelow;

  bool get isCode =>
      kind == MarkdownLineKind.codeFence || kind == MarkdownLineKind.codeBlock;
  bool get isQuote => kind == MarkdownLineKind.quote;
  double get leftInset => isCode ? 4 : 1;
  double get rightInset => isCode ? 11 : 8;
  double get cornerRadius => isCode ? 6 : (isQuote ? 4 : 5);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    // Flutter's preview line box includes the same leading/trailing space
    // that WPF accounts for in VisualLine.Top/Height. Code text keeps its
    // capture-calibrated -2px paint origin, while its background bleeds one
    // pixel above and below the local line box so the combined fenced block
    // reaches the same raster rows as WPF without changing document flow.
    final rect = isCode
        ? _codeRect(size)
        : isQuote
            ? Rect.fromLTWH(
                leftInset,
                0,
                (size.width - rightInset).clamp(0.0, double.infinity),
                (size.height - 1).clamp(1.0, double.infinity),
              )
            : Rect.fromLTWH(
                leftInset,
                1,
                (size.width - rightInset).clamp(0.0, double.infinity),
                (size.height - 2).clamp(1.0, double.infinity),
              );

    if (isCode) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = colors.code,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()
          ..color = _codeBorderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      return;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(cornerRadius),
      ),
      Paint()
        ..color = colors.tint.withValues(
          alpha: isQuote
              ? colors.isDark
                  ? 34 / 255
                  : 22 / 255
              : colors.isDark
                  ? 30 / 255
                  : 18 / 255,
        ),
    );
    if (isQuote) {
      canvas.drawLine(
        const Offset(4.5, 1),
        Offset(4.5, (size.height - 1).clamp(1.0, double.infinity)),
        Paint()
          ..color = colors.quoteBorder
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    final y = _snapStrokeY(
      (size.height - 1).clamp(1.0, double.infinity),
    );
    canvas.drawLine(
      Offset(7, y),
      Offset((size.width - 12).clamp(7.0, double.infinity), y),
      Paint()
        ..color = colors.active
        ..strokeWidth = 1,
    );
  }

  Rect _codeRect(Size size) {
    final top = !codeContinuesAbove
        ? -1.0
        : codeContinuesBelow
            ? 0.0
            : 1.0;
    final bottom = !codeContinuesBelow
        ? size.height
        : codeContinuesAbove
            ? size.height + 2
            : size.height + 1;
    return Rect.fromLTRB(
      leftInset,
      top,
      (size.width - rightInset).clamp(leftInset, double.infinity),
      bottom.clamp(top + 1, double.infinity),
    );
  }

  Color get _codeBorderColor => colors.tint.withValues(
        alpha: colors.isDark ? 92 / 255 : 69 / 255,
      );

  double _snapStrokeY(double value) {
    final lower = value.floorToDouble();
    final fraction = value - lower;
    final rounded = fraction == 0.5
        ? lower.toInt().isEven
            ? lower
            : lower + 1
        : value.roundToDouble();
    return rounded + 0.5;
  }

  @override
  bool shouldRepaint(
    covariant _PaperTodoMarkdownBlockPainter oldDelegate,
  ) {
    return oldDelegate.kind != kind ||
        oldDelegate.colors != colors ||
        oldDelegate.codeContinuesAbove != codeContinuesAbove ||
        oldDelegate.codeContinuesBelow != codeContinuesBelow;
  }
}

class PaperTodoMarkdownTextEditingController extends TextEditingController {
  PaperTodoMarkdownTextEditingController({
    super.text,
    required bool markdownEnabled,
  }) : _markdownEnabled = markdownEnabled;

  bool _markdownEnabled;

  bool get markdownEnabled => _markdownEnabled;

  bool get hasActiveComposing =>
      value.composing.isValid && !value.composing.isCollapsed;

  void setMarkdownEnabled(bool enabled) {
    if (_markdownEnabled == enabled) return;
    _markdownEnabled = enabled;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!_markdownEnabled ||
        (withComposing &&
            value.composing.isValid &&
            !value.composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return _PaperTodoMarkdownEditorSpanBuilder(
      colors: PaperTodoThemeColors.of(context),
      baseStyle: style ?? DefaultTextStyle.of(context).style,
    ).build(text);
  }
}

class PaperTodoMarkdownEditorBackgroundPainter extends CustomPainter {
  PaperTodoMarkdownEditorBackgroundPainter({
    required this.data,
    required this.textSpan,
    required this.colors,
    required this.scrollController,
    required this.textDirection,
    required this.textScaler,
  }) : super(repaint: scrollController);

  final String data;
  final TextSpan textSpan;
  final PaperTodoThemeColors colors;
  final ScrollController scrollController;
  final TextDirection textDirection;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: size.width);
    final analyses = MarkdownLineAnalysis.analyzeLines(data);
    final lines = _logicalLines(data);
    final scrollOffset =
        scrollController.hasClients ? scrollController.offset : 0.0;

    for (var index = 0; index < lines.length; index++) {
      final analysis = analyses[index];
      final isCode = analysis.kind == MarkdownLineKind.codeFence ||
          analysis.kind == MarkdownLineKind.codeBlock;
      final isQuote = analysis.kind == MarkdownLineKind.quote;
      if (!isCode && !isQuote) continue;
      final line = lines[index];
      final selectionEnd = line.end > line.start
          ? line.end
          : (line.start < data.length ? line.start + 1 : line.start);
      final boxes = selectionEnd > line.start
          ? textPainter.getBoxesForSelection(
              TextSelection(
                baseOffset: line.start,
                extentOffset: selectionEnd,
              ),
            )
          : const <TextBox>[];
      var top = double.infinity;
      var bottom = double.negativeInfinity;
      for (final box in boxes) {
        if (box.top < top) top = box.top;
        if (box.bottom > bottom) bottom = box.bottom;
      }
      if (!top.isFinite || !bottom.isFinite || bottom <= top) {
        final caret = textPainter.getOffsetForCaret(
          TextPosition(offset: line.start),
          Rect.zero,
        );
        top = caret.dy;
        bottom = top + textPainter.preferredLineHeight;
      }
      top -= scrollOffset;
      bottom -= scrollOffset;
      if (bottom < 0 || top > size.height) continue;
      final height = (bottom - top).clamp(1.0, double.infinity);

      if (isCode) {
        final rect = Rect.fromLTWH(
          1,
          top + 1,
          (size.width - 6).clamp(0.0, double.infinity),
          (height - 2).clamp(1.0, double.infinity),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = colors.code,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()
            ..color = colors.tint.withValues(
              alpha: colors.isDark ? 92 / 255 : 70 / 255,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        continue;
      }

      final rect = Rect.fromLTWH(
        0,
        top + 1,
        (size.width - 6).clamp(0.0, double.infinity),
        (height - 2).clamp(1.0, double.infinity),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()
          ..color = colors.tint.withValues(
            alpha: colors.isDark ? 34 / 255 : 22 / 255,
          ),
      );
      canvas.drawLine(
        Offset(4.5, top + 3),
        Offset(4.5, top + (height - 3).clamp(3.0, double.infinity)),
        Paint()
          ..color = colors.quoteBorder
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  List<_MarkdownLogicalLine> _logicalLines(String text) {
    final lines = <_MarkdownLogicalLine>[];
    var start = 0;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char != '\r' && char != '\n') continue;
      lines.add(_MarkdownLogicalLine(start, index));
      if (char == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
        index++;
      }
      start = index + 1;
    }
    lines.add(_MarkdownLogicalLine(start, text.length));
    return lines;
  }

  @override
  bool shouldRepaint(
    covariant PaperTodoMarkdownEditorBackgroundPainter oldDelegate,
  ) {
    return oldDelegate.data != data ||
        oldDelegate.textSpan != textSpan ||
        oldDelegate.colors != colors ||
        oldDelegate.scrollController != scrollController ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler;
  }
}

class _MarkdownLogicalLine {
  const _MarkdownLogicalLine(this.start, this.end);

  final int start;
  final int end;
}

class _PaperTodoMarkdownEditorSpanBuilder {
  const _PaperTodoMarkdownEditorSpanBuilder({
    required this.colors,
    required this.baseStyle,
  });

  final PaperTodoThemeColors colors;
  final TextStyle baseStyle;

  TextSpan build(String data) {
    final lines = data.split(RegExp(r'\r\n|\r|\n'));
    final analyses = MarkdownLineAnalysis.analyzeLines(data);
    final children = <InlineSpan>[];
    for (var index = 0; index < lines.length; index++) {
      if (index > 0) {
        children.add(TextSpan(text: '\n', style: baseStyle));
      }
      children.add(_lineSpan(lines[index], analyses[index]));
    }
    return TextSpan(style: baseStyle, children: children);
  }

  TextSpan _lineSpan(String text, MarkdownLineStyle analysis) {
    final lineStyle = switch (analysis.kind) {
      MarkdownLineKind.heading1 => baseStyle.copyWith(
          fontSize: _scaledFontSize(19),
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
      MarkdownLineKind.heading2 => baseStyle.copyWith(
          fontSize: _scaledFontSize(16.5),
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
      MarkdownLineKind.heading3 => baseStyle.copyWith(
          fontSize: _scaledFontSize(15),
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
      MarkdownLineKind.heading => baseStyle.copyWith(
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
      MarkdownLineKind.quote => baseStyle.copyWith(color: colors.weakText),
      MarkdownLineKind.codeFence ||
      MarkdownLineKind.codeBlock =>
        baseStyle.copyWith(
          fontFamily: _codeFontFamily,
          fontFamilyFallback: _codeFontFamilyFallback,
          fontSize: _scaledFontSize(13),
          color: colors.text,
        ),
      _ => baseStyle.copyWith(color: colors.text),
    };
    if (text.isEmpty) return TextSpan(text: '', style: lineStyle);

    final markerStyle = TextStyle(color: colors.active);
    final codeStyle = TextStyle(
      color: colors.active,
      backgroundColor: colors.code,
      fontFamily: _codeFontFamily,
      fontFamilyFallback: _codeFontFamilyFallback,
      fontSize: _scaledFontSize(13),
      fontStyle: FontStyle.normal,
      fontWeight: FontWeight.normal,
    );
    final patches = <_MarkdownStylePatch>[];
    final ignored = <_MarkdownRange>[];

    if (analysis.markerEnd > analysis.markerStart) {
      patches.add(
        _MarkdownStylePatch(
          analysis.markerStart,
          analysis.markerEnd.clamp(0, text.length),
          analysis.kind == MarkdownLineKind.codeFence
              ? TextStyle(
                  color: colors.active,
                  fontFamily: _codeFontFamily,
                  fontFamilyFallback: _codeFontFamilyFallback,
                  fontSize: _scaledFontSize(13),
                  fontStyle: FontStyle.normal,
                  fontWeight: FontWeight.normal,
                )
              : markerStyle,
        ),
      );
    }
    if (analysis.kind == MarkdownLineKind.codeBlock) {
      return _segments(
        text,
        lineStyle,
        [
          _MarkdownStylePatch(
            0,
            text.length,
            TextStyle(
              color: colors.text,
              fontFamily: _codeFontFamily,
              fontFamilyFallback: _codeFontFamilyFallback,
              fontSize: _scaledFontSize(13),
              fontStyle: FontStyle.normal,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      );
    }
    if (analysis.kind == MarkdownLineKind.codeFence ||
        analysis.kind == MarkdownLineKind.horizontalRule) {
      return _segments(text, lineStyle, patches);
    }

    _addInlineCode(text, patches, ignored, markerStyle, codeStyle);
    _addLinks(text, patches, ignored, markerStyle);
    _addHtmlInlineTags(text, patches, ignored, markerStyle, codeStyle);
    _addDelimited(
      text,
      delimiter: '~~',
      contentStyle: const TextStyle(decoration: TextDecoration.lineThrough),
      markerStyle: markerStyle,
      patches: patches,
      ignored: ignored,
    );
    _addDelimited(
      text,
      delimiter: '**',
      contentStyle: const TextStyle(fontWeight: FontWeight.w600),
      markerStyle: markerStyle,
      patches: patches,
      ignored: ignored,
    );
    _addDelimited(
      text,
      delimiter: '__',
      contentStyle: const TextStyle(fontWeight: FontWeight.w600),
      markerStyle: markerStyle,
      patches: patches,
      ignored: ignored,
    );
    _addSingleDelimited(text, '*', markerStyle, patches, ignored);
    _addSingleDelimited(text, '_', markerStyle, patches, ignored);
    _addTaskMarker(text, analysis, patches, markerStyle);
    return _segments(text, lineStyle, patches);
  }

  double _scaledFontSize(double sourceSize) {
    final baseSize = baseStyle.fontSize ?? 14;
    return sourceSize * baseSize / 14;
  }

  void _addInlineCode(
    String text,
    List<_MarkdownStylePatch> patches,
    List<_MarkdownRange> ignored,
    TextStyle markerStyle,
    TextStyle codeStyle,
  ) {
    var search = 0;
    while (search < text.length) {
      final start = text.indexOf('`', search);
      if (start < 0) return;
      final end = text.indexOf('`', start + 1);
      if (end < 0) {
        patches.add(_MarkdownStylePatch(start, text.length, markerStyle));
        ignored.add(_MarkdownRange(start, text.length));
        return;
      }
      final codeMarkerStyle = markerStyle.copyWith(
        fontFamily: _codeFontFamily,
        fontFamilyFallback: _codeFontFamilyFallback,
        fontSize: _scaledFontSize(13),
      );
      patches
        ..add(_MarkdownStylePatch(start, start + 1, codeMarkerStyle))
        ..add(_MarkdownStylePatch(start + 1, end, codeStyle))
        ..add(_MarkdownStylePatch(end, end + 1, codeMarkerStyle));
      ignored.add(_MarkdownRange(start, end + 1));
      search = end + 1;
    }
  }

  void _addLinks(
    String text,
    List<_MarkdownStylePatch> patches,
    List<_MarkdownRange> ignored,
    TextStyle markerStyle,
  ) {
    for (final link in MarkdownLinks.spans(text)) {
      if (_overlaps(ignored, link.start, link.end)) continue;
      final raw = text.substring(link.start, link.end);
      final labelEnd = raw.indexOf('](');
      if (labelEnd >= 1 && raw.startsWith('[')) {
        final absoluteLabelEnd = link.start + labelEnd;
        final urlStart = absoluteLabelEnd + 2;
        patches
          ..add(_MarkdownStylePatch(link.start, link.start + 1, markerStyle))
          ..add(_MarkdownStylePatch(
            absoluteLabelEnd,
            urlStart,
            markerStyle,
          ))
          ..add(_MarkdownStylePatch(
            urlStart,
            link.end - 1,
            TextStyle(color: colors.weakText),
          ))
          ..add(_MarkdownStylePatch(link.end - 1, link.end, markerStyle));
      } else {
        final openEnd = raw.indexOf('>');
        final closeStart = raw.lastIndexOf('</');
        if (openEnd >= 0 && closeStart > openEnd) {
          patches
            ..add(_MarkdownStylePatch(
              link.start,
              link.start + openEnd + 1,
              markerStyle,
            ))
            ..add(_MarkdownStylePatch(
              link.start + closeStart,
              link.end,
              markerStyle,
            ));
        }
      }
      ignored.add(_MarkdownRange(link.start, link.end));
    }
  }

  void _addHtmlInlineTags(
    String text,
    List<_MarkdownStylePatch> patches,
    List<_MarkdownRange> ignored,
    TextStyle markerStyle,
    TextStyle codeStyle,
  ) {
    for (final html in _htmlInlineSpans(text)) {
      if (_overlaps(ignored, html.start, html.end)) continue;
      patches
        ..add(_MarkdownStylePatch(html.start, html.openEnd, markerStyle))
        ..add(_MarkdownStylePatch(html.closeStart, html.end, markerStyle));
      final contentStyle = switch (html.tagName) {
        'b' || 'strong' => const TextStyle(fontWeight: FontWeight.w600),
        'i' || 'em' => const TextStyle(fontStyle: FontStyle.italic),
        's' || 'del' => const TextStyle(decoration: TextDecoration.lineThrough),
        'u' => const TextStyle(decoration: TextDecoration.underline),
        'code' => codeStyle,
        _ => const TextStyle(),
      };
      patches.add(
        _MarkdownStylePatch(html.openEnd, html.closeStart, contentStyle),
      );
      ignored.add(_MarkdownRange(html.start, html.end));
    }
  }

  Iterable<_MarkdownHtmlSpan> _htmlInlineSpans(String text) sync* {
    var search = 0;
    while (search < text.length) {
      final start = text.indexOf('<', search);
      if (start < 0) return;
      final open = _parseHtmlOpenTag(text, start);
      if (open == null) {
        search = start + 1;
        continue;
      }
      final close = _findHtmlCloseTag(text, open.tagName, open.openEnd);
      if (close == null || close.closeStart <= open.openEnd) {
        search = open.openEnd;
        continue;
      }
      yield _MarkdownHtmlSpan(
        start: start,
        openEnd: open.openEnd,
        closeStart: close.closeStart,
        end: close.end,
        tagName: open.tagName,
      );
      search = close.end;
    }
  }

  _MarkdownHtmlOpenTag? _parseHtmlOpenTag(String text, int start) {
    if (start + 2 >= text.length || text[start + 1] == '/') return null;
    var nameEnd = start + 1;
    while (nameEnd < text.length && _isHtmlTagNameChar(text[nameEnd])) {
      nameEnd++;
    }
    if (nameEnd == start + 1) return null;
    final tagName = text.substring(start + 1, nameEnd).toLowerCase();
    if (!_supportedHtmlTags.contains(tagName)) return null;
    final tagEnd = _findHtmlTagEnd(text, nameEnd);
    if (tagEnd < 0) return null;
    final attributes = text.substring(nameEnd, tagEnd).trim();
    if (tagName != 'a' && attributes.isNotEmpty) return null;
    return _MarkdownHtmlOpenTag(tagName, tagEnd + 1);
  }

  _MarkdownHtmlCloseTag? _findHtmlCloseTag(
    String text,
    String tagName,
    int start,
  ) {
    var search = start;
    while (search < text.length) {
      final closeStart = text.indexOf('</', search);
      if (closeStart < 0) return null;
      var nameEnd = closeStart + 2;
      while (nameEnd < text.length && _isHtmlTagNameChar(text[nameEnd])) {
        nameEnd++;
      }
      if (nameEnd > closeStart + 2 &&
          text.substring(closeStart + 2, nameEnd).toLowerCase() == tagName) {
        var end = nameEnd;
        while (end < text.length && text[end].trim().isEmpty) {
          end++;
        }
        if (end < text.length && text[end] == '>') {
          return _MarkdownHtmlCloseTag(closeStart, end + 1);
        }
      }
      search = closeStart + 2;
    }
    return null;
  }

  int _findHtmlTagEnd(String text, int start) {
    var quote = '';
    for (var index = start; index < text.length; index++) {
      final char = text[index];
      if (quote.isNotEmpty) {
        if (char == quote) quote = '';
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '>') return index;
    }
    return -1;
  }

  bool _isHtmlTagNameChar(String value) {
    final unit = value.codeUnitAt(0);
    return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
  }

  void _addDelimited(
    String text, {
    required String delimiter,
    required TextStyle contentStyle,
    required TextStyle markerStyle,
    required List<_MarkdownStylePatch> patches,
    required List<_MarkdownRange> ignored,
  }) {
    var search = 0;
    while (search < text.length) {
      final start = text.indexOf(delimiter, search);
      if (start < 0) return;
      final contentStart = start + delimiter.length;
      final end = text.indexOf(delimiter, contentStart);
      if (end < 0) return;
      final spanEnd = end + delimiter.length;
      if (end > contentStart && !_overlaps(ignored, start, spanEnd)) {
        patches
          ..add(_MarkdownStylePatch(start, contentStart, markerStyle))
          ..add(_MarkdownStylePatch(contentStart, end, contentStyle))
          ..add(_MarkdownStylePatch(end, spanEnd, markerStyle));
      }
      search = spanEnd;
    }
  }

  void _addSingleDelimited(
    String text,
    String delimiter,
    TextStyle markerStyle,
    List<_MarkdownStylePatch> patches,
    List<_MarkdownRange> ignored,
  ) {
    var search = 0;
    while (search < text.length) {
      final start = _singleDelimiter(text, delimiter, search);
      if (start < 0) return;
      final end = _singleDelimiter(text, delimiter, start + 1);
      if (end < 0) return;
      if (end > start + 1 && !_overlaps(ignored, start, end + 1)) {
        patches
          ..add(_MarkdownStylePatch(start, start + 1, markerStyle))
          ..add(_MarkdownStylePatch(
            start + 1,
            end,
            const TextStyle(fontStyle: FontStyle.italic),
          ))
          ..add(_MarkdownStylePatch(end, end + 1, markerStyle));
      }
      search = end + 1;
    }
  }

  int _singleDelimiter(String text, String delimiter, int start) {
    for (var index = start; index < text.length; index++) {
      if (text[index] != delimiter) continue;
      final previousSame = index > 0 && text[index - 1] == delimiter;
      final nextSame = index + 1 < text.length && text[index + 1] == delimiter;
      if (!previousSame && !nextSame) return index;
    }
    return -1;
  }

  void _addTaskMarker(
    String text,
    MarkdownLineStyle analysis,
    List<_MarkdownStylePatch> patches,
    TextStyle markerStyle,
  ) {
    if (!analysis.isTask || analysis.contentStart + 2 >= text.length) return;
    final start = analysis.contentStart;
    final checked = text[start + 1] != ' ';
    patches
      ..add(_MarkdownStylePatch(start, start + 1, markerStyle))
      ..add(_MarkdownStylePatch(
        start + 1,
        start + 2,
        TextStyle(
          color: colors.active,
          fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
        ),
      ))
      ..add(_MarkdownStylePatch(start + 2, start + 3, markerStyle));
  }

  TextSpan _segments(
    String text,
    TextStyle style,
    List<_MarkdownStylePatch> patches,
  ) {
    final boundaries = <int>{0, text.length};
    for (final patch in patches) {
      boundaries
        ..add(patch.start.clamp(0, text.length))
        ..add(patch.end.clamp(0, text.length));
    }
    final points = boundaries.toList()..sort();
    final children = <InlineSpan>[];
    for (var index = 0; index + 1 < points.length; index++) {
      final start = points[index];
      final end = points[index + 1];
      if (end <= start) continue;
      var segmentStyle = style;
      for (final patch in patches) {
        if (patch.start <= start && patch.end >= end) {
          segmentStyle = segmentStyle.merge(patch.style);
        }
      }
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: segmentStyle,
        ),
      );
    }
    return TextSpan(style: style, children: children);
  }

  bool _overlaps(List<_MarkdownRange> ranges, int start, int end) {
    return ranges.any((range) => start < range.end && end > range.start);
  }
}

class _MarkdownRange {
  const _MarkdownRange(this.start, this.end);

  final int start;
  final int end;
}

class _MarkdownStylePatch {
  const _MarkdownStylePatch(
    this.start,
    this.end,
    this.style, {
    this.recognizer,
  });

  final int start;
  final int end;
  final TextStyle style;
  final GestureRecognizer? recognizer;
}

class _MarkdownHtmlSpan {
  const _MarkdownHtmlSpan({
    required this.start,
    required this.openEnd,
    required this.closeStart,
    required this.end,
    required this.tagName,
  });

  final int start;
  final int openEnd;
  final int closeStart;
  final int end;
  final String tagName;
}

class _MarkdownHtmlOpenTag {
  const _MarkdownHtmlOpenTag(this.tagName, this.openEnd);

  final String tagName;
  final int openEnd;
}

class _MarkdownHtmlCloseTag {
  const _MarkdownHtmlCloseTag(this.closeStart, this.end);

  final int closeStart;
  final int end;
}

class _PaperTodoMarkdownListMarkerPainter extends CustomPainter {
  const _PaperTodoMarkdownListMarkerPainter({
    required this.text,
    required this.analysis,
    required this.style,
  });

  final String text;
  final MarkdownLineStyle analysis;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final markerStart = analysis.markerStart.clamp(0, text.length);
    final markerEnd = analysis.markerEnd.clamp(markerStart, text.length);
    if (markerEnd <= markerStart) return;
    final prefixPainter = TextPainter(
      text: TextSpan(text: text.substring(0, markerStart), style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final marker = text.substring(markerStart, markerEnd).trimRight();
    final markerPainter = TextPainter(
      text: TextSpan(text: marker, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final left = prefixPainter.width;
    // The marker belongs to the first visual line. Centering it in the full
    // logical-line height moves bullets onto the second line after wrapping.
    final centerY = markerPainter.height / 2;
    if (analysis.isUnorderedList) {
      final radius = ((style.fontSize ?? 14) * 0.16).clamp(2.0, 3.2);
      canvas.drawCircle(
        Offset(left + markerPainter.width / 2, centerY),
        radius,
        Paint()..color = style.color ?? Colors.black,
      );
      return;
    }
    markerPainter.paint(
      canvas,
      Offset(left, centerY - markerPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_PaperTodoMarkdownListMarkerPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.analysis.kind != analysis.kind ||
        oldDelegate.analysis.markerStart != analysis.markerStart ||
        oldDelegate.analysis.markerEnd != analysis.markerEnd ||
        oldDelegate.style != style;
  }
}
