import 'dart:io';

class ScriptCapsuleSpec {
  const ScriptCapsuleSpec({
    required this.engine,
    required this.script,
    required this.usePersistentProcess,
  });

  final String engine;
  final String script;
  final bool usePersistentProcess;

  static ScriptCapsuleSpec? tryParse(String? text) {
    final value = text ?? '';
    if (value.isEmpty) {
      return null;
    }

    final firstLineEnd = value.indexOf(RegExp(r'[\r\n]'));
    final firstLine =
        firstLineEnd >= 0 ? value.substring(0, firstLineEnd) : value;
    final marker = _markerSpec(firstLine);
    if (marker == null) {
      return null;
    }

    var scriptStart = firstLineEnd < 0 ? value.length : firstLineEnd;
    if (scriptStart < value.length && value.codeUnitAt(scriptStart) == 13) {
      scriptStart++;
    }
    if (scriptStart < value.length && value.codeUnitAt(scriptStart) == 10) {
      scriptStart++;
    }

    return ScriptCapsuleSpec(
      engine: marker.engine,
      script: normalizeIndent(value.substring(scriptStart)),
      usePersistentProcess: marker.usePersistentProcess,
    );
  }

  static bool isScriptCapsuleContent(String? text) => tryParse(text) != null;

  static String normalizeIndent(String script) {
    if (script.isEmpty) {
      return script;
    }
    final normalized = script.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    var commonIndent = 1 << 30;
    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      commonIndent = commonIndent < _leadingWhitespaceLength(line)
          ? commonIndent
          : _leadingWhitespaceLength(line);
    }
    if (commonIndent == 1 << 30 || commonIndent <= 0) {
      return script;
    }
    return [
      for (final line in lines)
        line.substring(
          commonIndent < _leadingWhitespaceLength(line)
              ? commonIndent
              : _leadingWhitespaceLength(line),
        ),
    ].join(Platform.lineTerminator);
  }

  static _ScriptCapsuleMarkerSpec? _markerSpec(String firstLine) {
    final marker = firstLine
            .trim()
            .toLowerCase()
            .split(' ')
            .where((part) => part.isNotEmpty)
            .firstOrNull ??
        '';
    return switch (marker) {
      '!pf' || '!powerf' => const _ScriptCapsuleMarkerSpec(
          engine: 'auto',
          usePersistentProcess: true,
        ),
      '!p' || '!power' => const _ScriptCapsuleMarkerSpec(
          engine: 'auto',
          usePersistentProcess: false,
        ),
      '!pwsh' || '!ps7' => const _ScriptCapsuleMarkerSpec(
          engine: 'pwsh',
          usePersistentProcess: false,
        ),
      '!ps5' || '!winps' => const _ScriptCapsuleMarkerSpec(
          engine: 'powershell',
          usePersistentProcess: false,
        ),
      _ => null,
    };
  }
}

class ScriptCapsuleRunRequest {
  const ScriptCapsuleRunRequest({
    required this.engine,
    required this.script,
    required this.usePersistentProcess,
    required this.usePersistentPowerShellProcess,
    required this.preferPowerShell7,
    required this.hideScriptRunWindow,
  });

  final String engine;
  final String script;
  final bool usePersistentProcess;
  final bool usePersistentPowerShellProcess;
  final bool preferPowerShell7;
  final bool hideScriptRunWindow;

  Map<String, Object?> toJson() {
    return {
      'engine': engine,
      'script': script,
      'usePersistentProcess': usePersistentProcess,
      'usePersistentPowerShellProcess': usePersistentPowerShellProcess,
      'preferPowerShell7': preferPowerShell7,
      'hideScriptRunWindow': hideScriptRunWindow,
    };
  }
}

class _ScriptCapsuleMarkerSpec {
  const _ScriptCapsuleMarkerSpec({
    required this.engine,
    required this.usePersistentProcess,
  });

  final String engine;
  final bool usePersistentProcess;
}

int _leadingWhitespaceLength(String text) {
  var length = 0;
  while (length < text.length) {
    final unit = text.codeUnitAt(length);
    if (unit != 32 && unit != 9) {
      break;
    }
    length++;
  }
  return length;
}
