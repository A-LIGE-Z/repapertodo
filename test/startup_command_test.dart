import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('parses PaperTodo-compatible startup commands', () {
    expect(StartupCommand.parse(['--show']).kind, StartupCommandKind.show);
    expect(StartupCommand.parse(['/hide']).kind, StartupCommandKind.hide);
    expect(StartupCommand.parse(['toggle']).kind, StartupCommandKind.toggle);
    expect(StartupCommand.parse(['todo']).kind, StartupCommandKind.newTodo);
    expect(StartupCommand.parse(['paper']).kind, StartupCommandKind.newNote);
    expect(StartupCommand.parse(['prefs']).kind, StartupCommandKind.settings);
    expect(StartupCommand.parse(['quit']).kind, StartupCommandKind.exit);
  });

  test('parses forgiving startup command spellings', () {
    expect(StartupCommand.parse(['--unknown', '--new-note']).kind,
        StartupCommandKind.newNote);
    expect(
        StartupCommand.parse(['new', 'todo']).kind, StartupCommandKind.newTodo);
    expect(StartupCommand.parse(['new note']).kind, StartupCommandKind.newNote);
    expect(
        StartupCommand.parse(['/add_note']).kind, StartupCommandKind.newNote);
    expect(StartupCommand.parse(['close']).kind, StartupCommandKind.hide);
  });

  test('parses option-style startup command spellings', () {
    expect(
      StartupCommand.parse(['--new=todo']).kind,
      StartupCommandKind.newTodo,
    );
    expect(
      StartupCommand.parse(['/new:note']).kind,
      StartupCommandKind.newNote,
    );
    expect(
      StartupCommand.parse(['--preferences=true']).kind,
      StartupCommandKind.settings,
    );
  });

  test('empty args use caller-provided default', () {
    final command = StartupCommand.parse(
      const [],
      defaultWhenEmpty: StartupCommandKind.show,
    );

    expect(command.kind, StartupCommandKind.show);
  });
}
