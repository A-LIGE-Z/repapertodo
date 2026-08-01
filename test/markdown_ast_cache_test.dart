import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/ui/markdown_ast_cache.dart';
import 'package:repapertodo/src/core/model/markdown_line_analysis.dart';

void main() {
  test('MarkdownAstCache parses and reuses MarkdownLineStyle for identical lines', () {
    final cache = MarkdownAstCache();
    const input = '# Title\n- Item 1\n- Item 2';

    final styles1 = cache.analyzeLines(input);
    final styles2 = cache.analyzeLines(input);

    expect(styles1.length, equals(styles2.length));
    for (var i = 0; i < styles1.length; i++) {
      expect(identical(styles1[i], styles2[i]), isTrue);
    }
  });

  test('MarkdownAstCache matches empty string logic', () {
    final cache = MarkdownAstCache();
    final styles = cache.analyzeLines('');
    
    expect(styles.length, equals(1));
    expect(styles[0].kind, equals(MarkdownLineKind.plain));
  });
}
