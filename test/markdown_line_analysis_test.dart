import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/core/model/markdown_line_analysis.dart';

void main() {
  test('classifies PaperTodo heading and quote lines', () {
    var style = MarkdownLineAnalysis.analyzeLine('# Title');
    expect(style.kind, MarkdownLineKind.heading1);
    expect(style.isHeading, true);
    expect(style.contentStart, 2);

    style = MarkdownLineAnalysis.analyzeLine('###   Title');
    expect(style.kind, MarkdownLineKind.heading3);
    expect(style.contentStart, 6);

    style = MarkdownLineAnalysis.analyzeLine('#### Title');
    expect(style.kind, MarkdownLineKind.heading);
    expect(style.contentStart, 5);

    style = MarkdownLineAnalysis.analyzeLine('   >   Quote');
    expect(style.kind, MarkdownLineKind.quote);
    expect(style.markerStart, 3);
    expect(style.contentStart, 7);

    expect(
      MarkdownLineAnalysis.analyzeLine('####### Too many').kind,
      MarkdownLineKind.plain,
    );
    expect(
      MarkdownLineAnalysis.analyzeLine('#NoSpace').kind,
      MarkdownLineKind.plain,
    );
  });

  test('classifies PaperTodo list and task lines', () {
    var style = MarkdownLineAnalysis.analyzeLine('- Read');
    expect(style.kind, MarkdownLineKind.unorderedList);
    expect(style.isUnorderedList, true);
    expect(style.markerStart, 0);
    expect(style.markerEnd, 1);
    expect(style.contentStart, 2);
    expect(style.isTask, false);

    style = MarkdownLineAnalysis.analyzeLine('  009. [X] Done');
    expect(style.kind, MarkdownLineKind.orderedList);
    expect(style.isOrderedList, true);
    expect(style.markerStart, 2);
    expect(style.markerEnd, 6);
    expect(style.contentStart, 7);
    expect(style.orderedNumberText, '009');
    expect(style.orderedDelimiter, '.');
    expect(style.isTask, true);

    style = MarkdownLineAnalysis.analyzeLine('    + [ ] Deep task');
    expect(style.kind, MarkdownLineKind.unorderedList);
    expect(style.markerStart, 4);
    expect(style.contentStart, 6);
    expect(style.isTask, true);

    expect(
      MarkdownLineAnalysis.analyzeLine('-NoSpace').kind,
      MarkdownLineKind.plain,
    );
    expect(
      MarkdownLineAnalysis.analyzeLine('1.NoSpace').kind,
      MarkdownLineKind.plain,
    );
  });

  test('classifies PaperTodo horizontal rules and fenced code', () {
    expect(
      MarkdownLineAnalysis.analyzeLine('---').kind,
      MarkdownLineKind.horizontalRule,
    );
    expect(
      MarkdownLineAnalysis.analyzeLine('- - -').kind,
      MarkdownLineKind.horizontalRule,
    );
    expect(
      MarkdownLineAnalysis.analyzeLine('  ***  ').kind,
      MarkdownLineKind.horizontalRule,
    );
    expect(
      MarkdownLineAnalysis.analyzeLine('__').kind,
      MarkdownLineKind.plain,
    );
    expect(
      MarkdownLineAnalysis.analyzeLine('--- text').kind,
      MarkdownLineKind.plain,
    );

    var style = MarkdownLineAnalysis.analyzeLine('```dart');
    expect(style.kind, MarkdownLineKind.codeFence);
    expect(style.markerEnd, 7);

    style = MarkdownLineAnalysis.analyzeLine('  ~~~');
    expect(style.kind, MarkdownLineKind.codeFence);
    expect(style.markerStart, 2);

    expect(
      MarkdownLineAnalysis.analyzeLine('    ```').kind,
      MarkdownLineKind.plain,
    );
    expect(
      MarkdownLineAnalysis.analyzeLine(
        '# code',
        isInFencedCodeBlock: true,
      ).kind,
      MarkdownLineKind.codeBlock,
    );
    expect(
      MarkdownLineAnalysis.analyzeLine(
        '```',
        isInFencedCodeBlock: true,
      ).kind,
      MarkdownLineKind.codeFence,
    );
  });

  test('tracks fenced code state across PaperTodo document lines', () {
    final styles = MarkdownLineAnalysis.analyzeLines(
      '```dart\r\n# code\r\n```\r\n# Title',
    );

    expect(
      styles.map((style) => style.kind),
      [
        MarkdownLineKind.codeFence,
        MarkdownLineKind.codeBlock,
        MarkdownLineKind.codeFence,
        MarkdownLineKind.heading1,
      ],
    );

    final crOnlyStyles = MarkdownLineAnalysis.analyzeLines(
      '```dart\r# code\r```\r# Title',
    );

    expect(
      crOnlyStyles.map((style) => style.kind),
      [
        MarkdownLineKind.codeFence,
        MarkdownLineKind.codeBlock,
        MarkdownLineKind.codeFence,
        MarkdownLineKind.heading1,
      ],
    );
  });
}
