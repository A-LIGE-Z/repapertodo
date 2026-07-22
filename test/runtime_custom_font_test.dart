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

  test('app font family normalizes unsafe explicit system font names', () {
    expect(
      resolveAppFontFamily(
        AppState(systemFontFamilyName: ' \u0000Microsoft YaHei UI\u007F '),
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

  test('app font family preserves PaperTodo YaHei and DengXian presets', () {
    final yaHeiState = AppState(uiFontPreset: UiFontPresets.yaHei);
    final dengXianState = AppState(uiFontPreset: UiFontPresets.dengXian);

    expect(resolveAppFontFamily(yaHeiState), isNull);
    expect(resolveAppFontFamilyFallback(yaHeiState), isNull);
    expect(resolveAppFontFamily(dengXianState), 'DengXian');
    expect(
      resolveAppFontFamilyFallback(dengXianState),
      const [
        'Segoe UI',
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'Microsoft JhengHei UI',
        'Microsoft JhengHei',
        'Yu Gothic UI',
        'Malgun Gothic',
        'Meiryo',
        'Segoe UI Symbol',
        'Segoe UI Emoji',
      ],
    );
  });

  test('native Windows dialogs use the same configured UI font family', () {
    expect(resolveWindowsNativeDialogFontFamily(AppState()), isEmpty);
    expect(
      resolveWindowsNativeDialogFontFamily(
        AppState(uiFontPreset: UiFontPresets.yaHei),
      ),
      'Microsoft YaHei UI',
    );
    expect(
      resolveWindowsNativeDialogFontFamily(
        AppState(uiFontPreset: UiFontPresets.dengXian),
      ),
      'DengXian',
    );
    expect(
      resolveWindowsNativeDialogFontFamily(
        AppState(uiFontPreset: UiFontPresets.serif),
      ),
      'Georgia',
    );
    expect(
      resolveWindowsNativeDialogFontFamily(
        AppState(uiFontPreset: UiFontPresets.mono),
      ),
      'Consolas',
    );
    expect(
      resolveWindowsNativeDialogFontFamily(
        AppState(),
        runtimeCustomFontFamily: ' PaperTodo Custom ',
      ),
      'PaperTodo Custom',
    );
    expect(
      resolveWindowsNativeDialogFontFamily(
        AppState(systemFontFamilyName: 'Consolas'),
        runtimeCustomFontFamily: 'PaperTodo Custom',
      ),
      'Consolas',
    );
  });

  test('note content font family preserves PaperTodo content chains', () {
    expect(resolveAppContentFontFamily(AppState()), 'Microsoft YaHei UI');
    expect(
      resolveAppContentFontFamilyFallback(AppState()),
      const [
        'Segoe UI',
        'Microsoft YaHei',
        'Segoe UI Symbol',
        'Segoe UI Emoji',
      ],
    );

    final dengXianState = AppState(uiFontPreset: UiFontPresets.dengXian);
    final yaHeiState = AppState(uiFontPreset: UiFontPresets.yaHei);
    expect(resolveAppContentFontFamily(yaHeiState), 'Microsoft YaHei UI');
    expect(
      resolveAppContentFontFamilyFallback(yaHeiState),
      resolveAppContentFontFamilyFallback(AppState()),
    );
    expect(resolveAppContentFontFamily(dengXianState), 'DengXian');
    expect(
      resolveAppContentFontFamilyFallback(dengXianState)?.first,
      'Segoe UI',
    );
    expect(
      resolveAppContentFontFamily(
        AppState(systemFontFamilyName: 'Consolas'),
        runtimeCustomFontFamily: paperTodoRuntimeCustomFontFamily,
      ),
      'Consolas',
    );
    expect(
      resolveAppContentFontFamily(
        AppState(),
        runtimeCustomFontFamily: paperTodoRuntimeCustomFontFamily,
      ),
      paperTodoRuntimeCustomFontFamily,
    );
  });
}
