import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/core/model/markdown_links.dart';

void main() {
  test('finds markdown links at source offsets like PaperTodo edit mode', () {
    const text = 'Read [PaperTodo](https://example.com/paper) today';

    expect(MarkdownLinks.hrefAt(text, text.indexOf('PaperTodo')),
        'https://example.com/paper');
    expect(MarkdownLinks.hrefAt(text, text.indexOf('https://')),
        'https://example.com/paper');
    expect(MarkdownLinks.hrefAt(text, text.indexOf('Read')), isNull);
    expect(MarkdownLinks.hrefAt(text, text.indexOf(' today')), isNull);
  });

  test('ignores markdown images and empty destinations', () {
    const text = '![Alt](https://example.com/image.png) [Empty]()';

    expect(MarkdownLinks.hrefAt(text, text.indexOf('Alt')), isNull);
    expect(MarkdownLinks.hrefAt(text, text.indexOf('Empty')), isNull);
  });

  test('finds single-line html anchor hrefs', () {
    const text =
        'Open <a class="x" href="https://example.com/html">HTML</a> link';

    expect(MarkdownLinks.hrefAt(text, text.indexOf('HTML')),
        'https://example.com/html');
  });

  test('does not resolve links across line boundaries', () {
    const text = 'Read [PaperTodo](https://example.com\n/paper) later';

    expect(MarkdownLinks.hrefAt(text, text.indexOf('PaperTodo')), isNull);
    expect(MarkdownLinks.hrefAt(text, text.indexOf('/paper')), isNull);
  });

  test('normalizes angle-bracket markdown destinations with spaces', () {
    const text = '[Spaced](<https://example.com/a b>)';

    expect(MarkdownLinks.hrefAt(text, text.indexOf('Spaced')),
        'https://example.com/a%20b');
  });
}
