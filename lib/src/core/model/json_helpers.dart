typedef JsonMap = Map<String, Object?>;

String stringValue(Object? value, String fallback) {
  return value is String ? value : fallback;
}

bool boolValue(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

int intValue(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return fallback;
}

double doubleValue(Object? value, double fallback) {
  if (value is num && value.isFinite) {
    return value.toDouble();
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
      if (entry.key is String && entry.value is bool)
        entry.key as String: entry.value as bool,
  };
}

Map<String, int> intMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value is num)
        entry.key as String: (entry.value as num).round(),
  };
}

Map<String, double> doubleMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return {
    for (final entry in value.entries)
      if (entry.key is String &&
          entry.value is num &&
          (entry.value as num).isFinite)
        entry.key as String: (entry.value as num).toDouble(),
  };
}

JsonMap preserveUnknown(JsonMap source, Set<String> knownKeys) {
  return {
    for (final entry in source.entries)
      if (!knownKeys.contains(entry.key)) entry.key: entry.value,
  };
}
