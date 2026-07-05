import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/ui/runtime_custom_font.dart';

void main() {
  test('PaperTodo runtime font candidates match the original exe convention',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_font_candidates_');
    addTearDown(() => directory.deleteSync(recursive: true));

    final candidates = paperTodoRuntimeCustomFontCandidates(
      baseDirectory: directory,
    );

    expect(
      candidates.map((file) => p.basename(file.path)),
      ['papertodo.ttf', 'papertodo.otf'],
    );
  });

  test('runtime custom font loader uses the first valid PaperTodo font',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_font_load_');
    addTearDown(() => directory.deleteSync(recursive: true));
    File(p.join(directory.path, 'papertodo.ttf')).writeAsBytesSync([1, 2, 3]);
    File(p.join(directory.path, 'papertodo.otf')).writeAsBytesSync([4, 5]);
    final loadedFamilies = <String>[];
    final loadedLengths = <int>[];
    final loader = PaperTodoRuntimeCustomFontLoader(
      baseDirectory: directory,
      loadFont: (family, font) async {
        loadedFamilies.add(family);
        loadedLengths.add((await font).lengthInBytes);
      },
    );

    expect(await loader.load(), paperTodoRuntimeCustomFontFamily);
    expect(await loader.load(), paperTodoRuntimeCustomFontFamily);

    expect(loadedFamilies, [paperTodoRuntimeCustomFontFamily]);
    expect(loadedLengths, [3]);
  });

  test('runtime custom font loader skips invalid fonts without failing startup',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_font_invalid_');
    addTearDown(() => directory.deleteSync(recursive: true));
    File(p.join(directory.path, 'papertodo.ttf')).writeAsBytesSync([1]);
    File(p.join(directory.path, 'papertodo.otf')).writeAsBytesSync([2, 3]);
    var attempts = 0;
    final loader = PaperTodoRuntimeCustomFontLoader(
      baseDirectory: directory,
      loadFont: (family, font) async {
        attempts += 1;
        await font;
        if (attempts == 1) {
          throw StateError('invalid font');
        }
      },
    );

    expect(await loader.load(), paperTodoRuntimeCustomFontFamily);

    expect(attempts, 2);
  });

  test('runtime custom font loader returns null when no candidate is usable',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_font_missing_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final loader = PaperTodoRuntimeCustomFontLoader(
      baseDirectory: directory,
      loadFont: (family, font) async {
        fail('No font should be loaded when PaperTodo candidates are missing.');
      },
    );

    expect(await loader.load(), isNull);
    expect(await loader.load(), isNull);
  });

  test('app font family prefers explicit system font before runtime font', () {
    expect(
      resolveAppFontFamily(
        AppState(systemFontFamilyName: '  Microsoft YaHei UI  '),
        runtimeCustomFontFamily: paperTodoRuntimeCustomFontFamily,
      ),
      'Microsoft YaHei UI',
    );
  });

  test('app font family prefers runtime font before built-in presets', () {
    expect(
      resolveAppFontFamily(
        AppState(uiFontPreset: UiFontPresets.mono),
        runtimeCustomFontFamily: paperTodoRuntimeCustomFontFamily,
      ),
      paperTodoRuntimeCustomFontFamily,
    );
    expect(
      resolveAppFontFamily(AppState(uiFontPreset: UiFontPresets.mono)),
      'monospace',
    );
  });
}
