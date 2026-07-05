import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/core/model/sync_wire_datetime.dart';

void main() {
  test('parses strict sync wire timestamps with explicit time zones', () {
    expect(
      parseStrictSyncWireDateTimeUtc(
        '2026-07-01T10:30:00+08:00',
        fieldName: 'Test timestamp',
      ),
      DateTime.utc(2026, 7, 1, 2, 30),
    );
    expect(
      parseStrictSyncWireDateTimeUtc(
        '2026-07-01T09:00:00.123456Z',
        fieldName: 'Test timestamp',
      ),
      DateTime.utc(2026, 7, 1, 9, 0, 0, 123, 456),
    );
    expect(
      parseStrictSyncWireDateTimeUtc(
        '2026-07-01T09:00:00z',
        fieldName: 'Test timestamp',
      ),
      DateTime.utc(2026, 7, 1, 9),
    );
    expect(
      parseStrictSyncWireDateTimeUtc(
        '2026-07-01T09:00:00+05:45',
        fieldName: 'Test timestamp',
      ),
      DateTime.utc(2026, 7, 1, 3, 15),
    );
    expect(
      parseStrictSyncWireDateTimeUtc(
        '2026-07-01T09:00:00-02:30',
        fieldName: 'Test timestamp',
      ),
      DateTime.utc(2026, 7, 1, 11, 30),
    );
  });

  test('rejects overflow sync wire timestamps', () {
    for (final value in const [
      '2026-13-01T09:00:00Z',
      '2026-02-30T09:00:00Z',
      '2026-07-01T24:00:00Z',
      '2026-07-01T09:60:00Z',
      '2026-07-01T09:00:60Z',
      '2026-07-01T09:00:00+24:00',
      '2026-07-01T09:00:00+99:99',
      '2026-07-01T09:00:00+05:60',
    ]) {
      expect(
        () => parseStrictSyncWireDateTimeUtc(
          value,
          fieldName: 'Test timestamp',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Test timestamp must be valid'),
          ),
        ),
        reason: value,
      );
      expect(tryParseStrictSyncWireDateTimeUtc(value), isNull, reason: value);
    }
  });

  test('rejects sync wire timestamps without explicit time zones', () {
    for (final value in const [
      '2026-07-01T09:00:00',
      '2026-07-01 09:00:00Z',
      '2026-07-01T09:00Z',
      '2026-07-01',
      ' 2026-07-01T09:00:00Z',
      '2026-07-01T09:00:00Z ',
    ]) {
      expect(tryParseStrictSyncWireDateTimeUtc(value), isNull, reason: value);
    }
  });

  test('rejects sync wire timestamps beyond microsecond precision', () {
    for (final value in const [
      '2026-07-01T09:00:00.1234567Z',
      '2026-07-01T09:00:00.1234567+08:00',
    ]) {
      expect(
        () => parseStrictSyncWireDateTimeUtc(
          value,
          fieldName: 'Test timestamp',
        ),
        throwsA(isA<FormatException>()),
        reason: value,
      );
      expect(tryParseStrictSyncWireDateTimeUtc(value), isNull, reason: value);
    }
  });
}
