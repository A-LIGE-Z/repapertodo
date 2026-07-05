DateTime parseStrictSyncWireDateTimeUtc(
  String value, {
  required String fieldName,
}) {
  final trimmed = value.trim();
  if (trimmed != value) {
    throw FormatException('$fieldName must be valid: $value');
  }
  final match = _strictDateTimePattern.firstMatch(trimmed);
  final parsed = DateTime.tryParse(trimmed)?.toUtc();
  if (match == null || parsed == null) {
    throw FormatException('$fieldName must be valid: $value');
  }
  final offset = _timeZoneOffset(match.group(8)!);
  if (offset == null) {
    throw FormatException('$fieldName must be valid: $value');
  }
  final local = parsed.add(offset);
  final fraction = (match.group(7) ?? '').padRight(6, '0');
  final microsecond = fraction.isEmpty ? 0 : int.parse(fraction);
  final fieldMatches = local.year == int.parse(match.group(1)!) &&
      local.month == int.parse(match.group(2)!) &&
      local.day == int.parse(match.group(3)!) &&
      local.hour == int.parse(match.group(4)!) &&
      local.minute == int.parse(match.group(5)!) &&
      local.second == int.parse(match.group(6)!) &&
      local.millisecond == microsecond ~/ 1000 &&
      local.microsecond == microsecond % 1000;
  if (!fieldMatches) {
    throw FormatException('$fieldName must be valid: $value');
  }
  return parsed;
}

DateTime? tryParseStrictSyncWireDateTimeUtc(String value) {
  try {
    return parseStrictSyncWireDateTimeUtc(
      value,
      fieldName: 'Sync timestamp',
    );
  } on FormatException {
    return null;
  }
}

final _strictDateTimePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T'
  r'(\d{2}):(\d{2}):(\d{2})'
  r'(?:\.(\d{1,6}))?'
  r'(Z|z|[+-]\d{2}:\d{2})$',
);

Duration? _timeZoneOffset(String value) {
  if (value.toUpperCase() == 'Z') {
    return Duration.zero;
  }
  final sign = value.startsWith('-') ? -1 : 1;
  final hours = int.parse(value.substring(1, 3));
  final minutes = int.parse(value.substring(4, 6));
  if (hours > 23 || minutes > 59) {
    return null;
  }
  return Duration(minutes: sign * (hours * 60 + minutes));
}
