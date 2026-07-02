typedef JsonMap = Map<String, Object?>;

String stringValue(Object? value, String fallback) {
  return value is String ? value : fallback;
}

bool boolValue(Object? value, bool fallback) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return switch (value.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => fallback,
    };
  }
  return fallback;
}

int intValue(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

double doubleValue(Object? value, double fallback) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return fallback;
}

List<JsonMap> jsonMapList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

List<String> stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is String) item,
  ];
}

List<double> doubleList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is num && item.isFinite) item.toDouble(),
  ];
}

Map<String, bool> boolMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    for (final entry in value.entries)
      if (entry.key is String && _boolValueOrNull(entry.value) != null)
        entry.key as String: _boolValueOrNull(entry.value)!,
  };
}

Map<String, int> intMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    for (final entry in value.entries)
      if (entry.key is String && _intValueOrNull(entry.value) != null)
        entry.key as String: _intValueOrNull(entry.value)!,
  };
}

Map<String, double> doubleMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    for (final entry in value.entries)
      if (entry.key is String && _doubleValueOrNull(entry.value) != null)
        entry.key as String: _doubleValueOrNull(entry.value)!,
  };
}

JsonMap preserveUnknown(JsonMap source, Set<String> knownKeys) {
  return {
    for (final entry in source.entries)
      if (!knownKeys.contains(entry.key)) entry.key: entry.value,
  };
}

bool? _boolValueOrNull(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return switch (value.trim().toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }
  return null;
}

int? _intValueOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

double? _doubleValueOrNull(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return null;
}
