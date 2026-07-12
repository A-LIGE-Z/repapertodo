import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/windows/paper_window_arguments.dart';

void main() {
  test('parses a strict paper window engine launch', () {
    final result = PaperWindowArguments.tryParse(
      const [PaperWindowArguments.marker, 'paper-123'],
    );

    expect(result?.paperId, 'paper-123');
  });

  test('keeps normal startup arguments on the primary engine path', () {
    for (final arguments in const <List<String>>[
      [],
      ['--settings'],
      ['--new-note'],
      [PaperWindowArguments.marker],
      [PaperWindowArguments.marker, ' paper-123 '],
      [PaperWindowArguments.marker, 'paper\n123'],
      [PaperWindowArguments.marker, 'paper-123', 'extra'],
    ]) {
      expect(
        PaperWindowArguments.tryParse(arguments),
        isNull,
        reason: arguments.toString(),
      );
    }
  });
}
