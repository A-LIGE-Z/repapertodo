import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

String? normalizeMarkdownLocalPathTarget(
  String value, {
  bool? isWindows,
}) {
  final windows = isWindows ?? Platform.isWindows;
  var trimmed = value.trim();
  if (trimmed.isEmpty || _hasControlCharacter(trimmed)) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme.toLowerCase() == 'file') {
    if (uri.hasQuery || uri.hasFragment) {
      return null;
    }
    try {
      trimmed = uri.toFilePath(windows: windows);
    } on UnsupportedError {
      return null;
    } on ArgumentError {
      return null;
    }
    if (trimmed.isEmpty || _hasControlCharacter(trimmed)) {
      return null;
    }
  }

  if (!_looksLikeLocalPath(trimmed, isWindows: windows) ||
      _isUnsafeDevicePath(trimmed, isWindows: windows)) {
    return null;
  }

  final context = p.Context(
    style: windows ? p.Style.windows : p.Style.posix,
  );
  try {
    final fullPath = context.normalize(context.absolute(trimmed));
    if (_hasControlCharacter(fullPath) ||
        _isUnsafeDevicePath(fullPath, isWindows: windows)) {
      return null;
    }
    return fullPath;
  } on ArgumentError {
    return null;
  }
}

bool _looksLikeLocalPath(String value, {required bool isWindows}) {
  if (isWindows) {
    return _isWindowsDrivePath(value) || _isUncPath(value);
  }
  return _isPosixAbsolutePath(value);
}

bool _isWindowsDrivePath(String value) {
  return value.length >= 3 &&
      _isAsciiLetter(value.codeUnitAt(0)) &&
      value[1] == ':' &&
      _isDirectorySeparator(value[2]);
}

bool _isUncPath(String value) {
  return value.length >= 3 &&
      _isDirectorySeparator(value[0]) &&
      _isDirectorySeparator(value[1]) &&
      !_isDirectorySeparator(value[2]);
}

bool _isPosixAbsolutePath(String value) {
  return value.length >= 2 && value.startsWith('/') && !value.startsWith('//');
}

bool _isUnsafeDevicePath(String value, {required bool isWindows}) {
  if (!isWindows) {
    return false;
  }
  final normalized = value.replaceAll('/', r'\');
  return normalized.startsWith(r'\\.\') || normalized.startsWith(r'\\?\');
}

bool _isDirectorySeparator(String value) => value == r'\' || value == '/';

bool _isAsciiLetter(int codeUnit) {
  return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);
}

bool _hasControlCharacter(String value) {
  return value.runes.any(
    (rune) => rune < 0x20 || (rune >= 0x7F && rune <= 0x9F),
  );
}
