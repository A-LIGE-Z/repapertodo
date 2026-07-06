import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('parses PaperTodo due date formats', () {
    final cases = {
      '2026-06-30T09:08:07': DateTime(2026, 6, 30, 9, 8, 7),
      '2026-06-30 09:08:07': DateTime(2026, 6, 30, 9, 8, 7),
      '2026-06-30T09:08:07.999': DateTime(2026, 6, 30, 9, 8, 7, 999),
      '2026/6/30 9:08': DateTime(2026, 6, 30, 9, 8),
      '2026.6.30': DateTime(2026, 6, 30),
      '6/30/2026 9:08 PM': DateTime(2026, 6, 30, 21, 8),
      '30/6/2026 09:08': DateTime(2026, 6, 30, 9, 8),
      '2026\u5e746\u670830\u65e5 09\uff1a08': DateTime(2026, 6, 30, 9, 8),
    };

    for (final entry in cases.entries) {
      expect(parsePaperTodoDueAtLocal(entry.key), entry.value);
    }
  });

  test('rejects invalid PaperTodo due date formats', () {
    for (final value in [
      '',
      'not a date',
      '2026-02-30 09:08',
      '2026-06-30 24:00',
      '2026-06-30 09:60',
      '2026-06-30 09:08:60',
      '2026-06-30 13:00 PM',
      '30/30/2026 09:08',
    ]) {
      expect(parsePaperTodoDueAtLocal(value), isNull, reason: value);
    }
  });

  test('formats PaperTodo due dates without milliseconds', () {
    expect(
      formatPaperTodoDueAtLocal(DateTime(2026, 6, 30, 9, 8, 7, 999)),
      '2026-06-30T09:08:07',
    );
  });
}
