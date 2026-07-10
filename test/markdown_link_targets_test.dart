import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/core/model/markdown_link_targets.dart';

void main() {
  test('normalizes Windows local markdown link targets', () {
    expect(
      normalizeMarkdownLocalPathTarget(
        ' C:/PaperTodo/My File.md ',
        isWindows: true,
      )?.replaceAll(r'\', '/'),
      'C:/PaperTodo/My File.md',
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        'file:///C:/PaperTodo/File%20Uri.md',
        isWindows: true,
      )?.replaceAll(r'\', '/'),
      'C:/PaperTodo/File Uri.md',
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        r'\\Server\Share\File.md',
        isWindows: true,
      )?.replaceAll(r'\', '/'),
      '//Server/Share/File.md',
    );
  });

  test('normalizes Android POSIX local markdown link targets', () {
    expect(
      normalizeMarkdownLocalPathTarget(
        ' /storage/emulated/0/Download/Paper Todo.md ',
        isWindows: false,
      ),
      '/storage/emulated/0/Download/Paper Todo.md',
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        'file:///storage/emulated/0/Download/File%20Uri.md',
        isWindows: false,
      ),
      '/storage/emulated/0/Download/File Uri.md',
    );
    expect(
      normalizeMarkdownLocalPathTarget('/data/user/0/app/files/export.md',
          isWindows: false),
      '/data/user/0/app/files/export.md',
    );
  });

  test('rejects ambiguous or unsafe local markdown link targets', () {
    expect(
      normalizeMarkdownLocalPathTarget('//example.com/paper.md',
          isWindows: false),
      isNull,
    );
    expect(
      normalizeMarkdownLocalPathTarget('relative/paper.md', isWindows: false),
      isNull,
    );
    expect(
      normalizeMarkdownLocalPathTarget(r'\\?\C:\PaperTodo\paper.md',
          isWindows: true),
      isNull,
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        '/storage/emulated/0/bad\u0085paper.md',
        isWindows: false,
      ),
      isNull,
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        'file:///C:/PaperTodo/paper.md?download=1',
        isWindows: true,
      ),
      isNull,
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        'file:///storage/emulated/0/paper.md#section',
        isWindows: false,
      ),
      isNull,
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        'file:///storage/emulated/0/bad%0Apaper.md',
        isWindows: false,
      ),
      isNull,
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        'file:///storage/emulated/0/bad%C2%85paper.md',
        isWindows: false,
      ),
      isNull,
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        'file:///C:/PaperTodo/bad%0Apaper.md',
        isWindows: true,
      ),
      isNull,
    );
    expect(
      normalizeMarkdownLocalPathTarget(
        'file:///C:/PaperTodo/bad%C2%85paper.md',
        isWindows: true,
      ),
      isNull,
    );
  });
}
