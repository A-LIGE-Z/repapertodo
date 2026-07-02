String normalizeSyncDeviceId(
  String value, {
  String fallback = 'local-device',
}) {
  final normalized = value.trim().toLowerCase();
  final cleaned = normalized.replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
  final collapsed = cleaned.replaceAll(RegExp('-+'), '-');
  final trimmed = collapsed.replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
  if (trimmed.length < 8) {
    return fallback;
  }
  final capped = trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed;
  final stable = capped.replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
  return stable.length < 8 ? fallback : stable;
}

Map<String, int> normalizeSyncDeviceSequences(
  Map<String, int>? source,
) {
  final normalized = <String, int>{};
  for (final entry in (source ?? const <String, int>{}).entries) {
    if (entry.value <= 0) {
      continue;
    }
    final deviceId = normalizeSyncDeviceId(entry.key, fallback: '');
    if (deviceId.isEmpty) {
      continue;
    }
    final previous = normalized[deviceId] ?? 0;
    if (entry.value > previous) {
      normalized[deviceId] = entry.value;
    }
  }
  return normalized;
}
