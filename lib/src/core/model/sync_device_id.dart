const int maxSyncDeviceSequence = 999999999999;
const int syncDeviceSequenceWireWidth = 12;
const int minSyncDeviceIdLength = 8;
const int maxSyncDeviceIdLength = 64;

bool isSyncDeviceSequenceInRange(int sequence) {
  return sequence > 0 && sequence <= maxSyncDeviceSequence;
}

String normalizeSyncDeviceId(
  String value, {
  String fallback = 'local-device',
}) {
  final stable = normalizeSyncDeviceIdForDisplay(value);
  return stable.length < minSyncDeviceIdLength ? fallback : stable;
}

String normalizeSyncDeviceIdForDisplay(String value) {
  final normalized = value.trim().toLowerCase();
  final cleaned = normalized.replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
  final collapsed = cleaned.replaceAll(RegExp('-+'), '-');
  final trimmed = collapsed.replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
  final capped = trimmed.length > maxSyncDeviceIdLength
      ? trimmed.substring(0, maxSyncDeviceIdLength)
      : trimmed;
  return capped.replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
}

Map<String, int> normalizeSyncDeviceSequences(
  Map<String, int>? source,
) {
  final normalized = <String, int>{};
  for (final entry in (source ?? const <String, int>{}).entries) {
    if (!isSyncDeviceSequenceInRange(entry.value)) {
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
