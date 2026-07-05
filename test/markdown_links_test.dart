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

  test('treats markdown image labels as links like PaperTodo', () {
    const text = '![Alt](https://example.com/image.png) [Empty]()';

    expect(MarkdownLinks.hrefAt(text, text.indexOf('Alt')),
        'https://example.com/image.png');
    expect(MarkdownLinks.hrefAt(text, text.indexOf('Empty')), isNull);
  });

  test('finds single-line html anchor hrefs', () {
    const text =
        'Open <a class="x" href="https://example.com/html">HTML</a> link';

    expect(MarkdownLinks.hrefAt(text, text.indexOf('HTML')),
        'https://example.com/html');
  });

  test('parses html anchor attributes like PaperTodo', () {
    const unquoted =
        '<a data-id=paper href=https://example.com/html class=x>HTML</a>';
    const invalidAttribute = '<a broken href="https://example.com/bad">Bad</a>';
    const unclosedQuote =
        '<a href="https://example.com/bad>Bad</a> <a href="https://ok">Ok</a>';
    const emptyContent = '<a href="https://example.com/empty"></a>';

    expect(MarkdownLinks.hrefAt(unquoted, unquoted.indexOf('HTML')),
        'https://example.com/html');
    expect(
        MarkdownLinks.hrefAt(invalidAttribute, invalidAttribute.indexOf('Bad')),
        isNull);
    expect(MarkdownLinks.hrefAt(unclosedQuote, unclosedQuote.indexOf('Bad')),
        isNull);
    expect(MarkdownLinks.hrefAt(unclosedQuote, unclosedQuote.indexOf('Ok')),
        'https://ok');
    expect(MarkdownLinks.spans(emptyContent), isEmpty);
  });

  test('does not resolve links across line boundaries', () {
    const text = 'Read [PaperTodo](https://example.com\n/paper) later';

    expect(MarkdownLinks.hrefAt(text, text.indexOf('PaperTodo')), isNull);
    expect(MarkdownLinks.hrefAt(text, text.indexOf('/paper')), isNull);
  });

  test('uses PaperTodo lightweight markdown delimiter scanning', () {
    const escapedLabel = r'[Escaped \](https://example.com/escaped-label)';
    const escapedDestination =
        r'[Escaped destination](https://example.com/a\)b)';

    expect(
      MarkdownLinks.hrefAt(escapedLabel, escapedLabel.indexOf('Escaped')),
      'https://example.com/escaped-label',
    );
    expect(
      MarkdownLinks.hrefAt(
        escapedDestination,
        escapedDestination.indexOf('Escaped destination'),
      ),
      'https://example.com/a/',
    );
  });

  test('keeps PaperTodo source scanner smaller than CommonMark', () {
    const angleDestination = '[Spaced](<https://example.com/a b>)';
    const titledDestination = '[Titled](https://example.com "title")';

    expect(
      MarkdownLinks.hrefAt(
        angleDestination,
        angleDestination.indexOf('Spaced'),
      ),
      isNull,
    );
    expect(
      MarkdownLinks.hrefAt(
        titledDestination,
        titledDestination.indexOf('Titled'),
      ),
      isNull,
    );
  });

  test('normalizes bare www links like PaperTodo', () {
    const markdown = '[Site](www.example.com/paper)';
    const html = '<a href="www.example.com/html">HTML</a>';

    expect(MarkdownLinks.hrefAt(markdown, markdown.indexOf('Site')),
        'https://www.example.com/paper');
    expect(MarkdownLinks.hrefAt(html, html.indexOf('HTML')),
        'https://www.example.com/html');
  });

  test('accepts only PaperTodo markdown URL target families', () {
    const localPath = r'[Local](C:/PaperTodo/My File.md)';
    const fileUri = '[File](file:///C:/PaperTodo/File%20Uri.md)';
    const mailto = '[Mail](mailto:paper@example.com)';
    const ftp = '[FTP](ftp://example.com/file)';
    const script = '[Script](javascript:alert(1))';

    expect(
      MarkdownLinks.hrefAt(localPath, localPath.indexOf('Local'))
          ?.replaceAll(r'\', '/'),
      'C:/PaperTodo/My File.md',
    );
    expect(
      MarkdownLinks.hrefAt(fileUri, fileUri.indexOf('File'))
          ?.replaceAll(r'\', '/'),
      'C:/PaperTodo/File Uri.md',
    );
    expect(MarkdownLinks.hrefAt(mailto, mailto.indexOf('Mail')),
        'mailto:paper@example.com');
    expect(MarkdownLinks.hrefAt(ftp, ftp.indexOf('FTP')), isNull);
    expect(MarkdownLinks.hrefAt(script, script.indexOf('Script')), isNull);
  });

  test('ignores links inside closed inline code spans like PaperTodo', () {
    const markdown =
        '`[Code](https://example.com/code)` [Real](https://example.com/real)';
    const html = '`<a href="https://example.com/code">Code</a>` '
        '<a href="https://example.com/real">Real</a>';

    expect(MarkdownLinks.hrefAt(markdown, markdown.indexOf('Code')), isNull);
    expect(MarkdownLinks.hrefAt(markdown, markdown.indexOf('Real')),
        'https://example.com/real');
    expect(MarkdownLinks.hrefAt(html, html.indexOf('Code')), isNull);
    expect(MarkdownLinks.hrefAt(html, html.indexOf('Real')),
        'https://example.com/real');
  });
}
