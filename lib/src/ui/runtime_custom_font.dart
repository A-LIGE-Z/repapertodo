import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const paperTodoRuntimeCustomFontFamily = 'PaperTodoRuntimeCustom';

typedef RuntimeFontLoadCallback = Future<void> Function(
  String family,
  Future<ByteData> font,
);

class PaperTodoRuntimeCustomFontLoader {
  PaperTodoRuntimeCustomFontLoader({
    Directory? baseDirectory,
    RuntimeFontLoadCallback loadFont = loadFlutterRuntimeFont,
  })  : _baseDirectory = baseDirectory,
        _loadFont = loadFont;

  final Directory? _baseDirectory;
  final RuntimeFontLoadCallback _loadFont;
  bool _loaded = false;
  String? _loadedFamily;

  Future<String?> load() async {
    if (_loaded) {
      return _loadedFamily;
    }

    for (final file in paperTodoRuntimeCustomFontCandidates(
      baseDirectory: _baseDirectory,
    )) {
      try {
        if (!await file.exists()) {
          continue;
        }
        final bytes = await file.readAsBytes();
        await _loadFont(
          paperTodoRuntimeCustomFontFamily,
          Future<ByteData>.value(ByteData.sublistView(bytes)),
        );
        _loaded = true;
        _loadedFamily = paperTodoRuntimeCustomFontFamily;
        return _loadedFamily;
      } catch (_) {
        // Invalid or unsupported custom fonts must not affect startup.
      }
    }

    _loaded = true;
    return null;
  }
}

List<File> paperTodoRuntimeCustomFontCandidates({Directory? baseDirectory}) {
  final directory = baseDirectory ?? _runtimeExecutableDirectory();
  return [
    File(p.join(directory.path, 'papertodo.ttf')),
    File(p.join(directory.path, 'papertodo.otf')),
  ];
}

Future<void> loadFlutterRuntimeFont(
  String family,
  Future<ByteData> font,
) async {
  final loader = FontLoader(family)..addFont(font);
  await loader.load();
}

Directory _runtimeExecutableDirectory() {
  final executablePath = Platform.resolvedExecutable.trim();
  if (executablePath.isEmpty) {
    return Directory.current;
  }
  return File(executablePath).absolute.parent;
}
