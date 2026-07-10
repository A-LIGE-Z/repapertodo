DateTime? parsePaperTodoDueAtLocal(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }

  final isoDate = _parseStrictIsoLikeDateTime(trimmed);
  if (isoDate != null) {
    return isoDate;
  }

  final normalized = _normalizeDateSeparators(trimmed);
  return _parseYearFirstDateTime(normalized) ??
      _parseMonthOrDayFirstDateTime(normalized);
}

String formatPaperTodoDueAtLocal(DateTime date) {
  final localDate = date.toLocal();
  final year = localDate.year.toString().padLeft(4, '0');
  final month = localDate.month.toString().padLeft(2, '0');
  final day = localDate.day.toString().padLeft(2, '0');
  final hour = localDate.hour.toString().padLeft(2, '0');
  final minute = localDate.minute.toString().padLeft(2, '0');
  final second = localDate.second.toString().padLeft(2, '0');
  return '$year-$month-${day}T$hour:$minute:$second';
}

DateTime? _parseYearFirstDateTime(String value) {
  final match = RegExp(
    r'^(\d{4})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{1,2})(?:[\sT]+(\d{1,2})(?::(\d{1,2})(?::(\d{1,2}))?)?\s*([aApP][mM])?)?$',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }
  return _buildDateTime(
    yearText: match.group(1),
    monthText: match.group(2),
    dayText: match.group(3),
    hourText: match.group(4),
    minuteText: match.group(5),
    secondText: match.group(6),
    meridiemText: match.group(7),
  );
}

DateTime? _parseStrictIsoLikeDateTime(String value) {
  final match = _isoLikeDateTimePattern.firstMatch(value);
  if (match == null) {
    return null;
  }

  final validated = _buildDateTime(
    yearText: match.group(1),
    monthText: match.group(2),
    dayText: match.group(3),
    hourText: match.group(4),
    minuteText: match.group(5),
    secondText: match.group(6),
    meridiemText: null,
  );
  if (validated == null) {
    return null;
  }

  final parsed =
      DateTime.tryParse(_normalizeIsoFractionForDart(value))?.toLocal();
  if (parsed == null) {
    return null;
  }
  return parsed;
}

DateTime? _parseMonthOrDayFirstDateTime(String value) {
  final match = RegExp(
    r'^(\d{1,2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{4})(?:[\sT]+(\d{1,2})(?::(\d{1,2})(?::(\d{1,2}))?)?\s*([aApP][mM])?)?$',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }

  final first = int.tryParse(match.group(1)!);
  final second = int.tryParse(match.group(2)!);
  if (first == null || second == null) {
    return null;
  }

  final month = first > 12 && second <= 12 ? second : first;
  final day = first > 12 && second <= 12 ? first : second;
  return _buildDateTime(
    yearText: match.group(3),
    monthText: month.toString(),
    dayText: day.toString(),
    hourText: match.group(4),
    minuteText: match.group(5),
    secondText: match.group(6),
    meridiemText: match.group(7),
  );
}

DateTime? _buildDateTime({
  required String? yearText,
  required String? monthText,
  required String? dayText,
  required String? hourText,
  required String? minuteText,
  required String? secondText,
  required String? meridiemText,
}) {
  final year = int.tryParse(yearText ?? '');
  final month = int.tryParse(monthText ?? '');
  final day = int.tryParse(dayText ?? '');
  if (year == null || month == null || day == null) {
    return null;
  }

  final hour = _normalizeHour(hourText, meridiemText);
  final minute = int.tryParse(minuteText ?? '0');
  final second = int.tryParse(secondText ?? '0');
  if (hour == null ||
      minute == null ||
      second == null ||
      minute < 0 ||
      minute > 59 ||
      second < 0 ||
      second > 59) {
    return null;
  }

  final date = DateTime(year, month, day, hour, minute, second);
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      date.hour != hour ||
      date.minute != minute ||
      date.second != second) {
    return null;
  }
  return date;
}

final _isoLikeDateTimePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[ T]'
  r'(\d{2}):(\d{2})(?::(\d{2}))?'
  r'(?:\.\d{1,7})?'
  r'(?:[zZ]|[+-]\d{2}:?\d{2})?$',
);

String _normalizeIsoFractionForDart(String value) {
  return value.replaceFirstMapped(
    RegExp(r'\.(\d{7})(?=[zZ]|[+-]\d{2}:?\d{2}$|$)'),
    (match) => '.${match.group(1)!.substring(0, 6)}',
  );
}

int? _normalizeHour(String? hourText, String? meridiemText) {
  final hour = int.tryParse(hourText ?? '0');
  if (hour == null) {
    return null;
  }
  final meridiem = meridiemText?.toLowerCase();
  if (meridiem == null) {
    return hour >= 0 && hour <= 23 ? hour : null;
  }
  if (hour < 1 || hour > 12) {
    return null;
  }
  if (meridiem == 'am') {
    return hour == 12 ? 0 : hour;
  }
  return hour == 12 ? 12 : hour + 12;
}

String _normalizeDateSeparators(String value) {
  return value
      .replaceAll('\u5e74', '-')
      .replaceAll('\u6708', '-')
      .replaceAll('\u65e5', '')
      .replaceAll('\uff1a', ':')
      .trim();
}
