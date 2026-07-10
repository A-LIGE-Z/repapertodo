import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('parses PaperTodo script capsule markers', () {
    final auto = ScriptCapsuleSpec.tryParse('!p\nWrite-Output 1');
    expect(auto, isNotNull);
    expect(auto!.engine, 'auto');
    expect(auto.usePersistentProcess, false);
    expect(auto.script, 'Write-Output 1');

    final persistent = ScriptCapsuleSpec.tryParse(' !powerf  \r\n  Get-Date');
    expect(persistent, isNotNull);
    expect(persistent!.engine, 'auto');
    expect(persistent.usePersistentProcess, true);
    expect(persistent.script, 'Get-Date');

    expect(ScriptCapsuleSpec.tryParse('!pwsh\npwsh-only')!.engine, 'pwsh');
    expect(
      ScriptCapsuleSpec.tryParse('!winps\nwindows-powershell')!.engine,
      'powershell',
    );
    expect(
      ScriptCapsuleSpec.tryParse('!p PaperTodo style comment\nWrite-Output ok'),
      isNotNull,
    );
    expect(
      ScriptCapsuleSpec.tryParse(
          '!p\tunsupported-tab-comment\nWrite-Output ok'),
      isNull,
    );
    expect(ScriptCapsuleSpec.tryParse('plain note'), isNull);
  });

  test('normalizes common script indentation like PaperTodo', () {
    final spec = ScriptCapsuleSpec.tryParse(
      '!ps7\n'
      '    if (\$true) {\n'
      '      Write-Output ok\n'
      '    }\n',
    );

    expect(
      spec!.script,
      [
        'if (\$true) {',
        '  Write-Output ok',
        '}',
        '',
      ].join(Platform.lineTerminator),
    );
  });
}
