import '../core/model/json_helpers.dart';

class SyncManifest {
  SyncManifest({
    required this.schemaVersion,
    required this.updatedAtUtc,
    required this.latestSnapshotPath,
    Map<String, int>? deviceSequences,
  }) : deviceSequences = deviceSequences ?? <String, int>{};

  final int schemaVersion;
  final DateTime updatedAtUtc;
  final String latestSnapshotPath;
  final Map<String, int> deviceSequences;

  factory SyncManifest.empty() {
    return SyncManifest(
      schemaVersion: 1,
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      latestSnapshotPath: '',
    );
  }

  factory SyncManifest.fromJson(JsonMap json) {
    final rawSequences = json['deviceSequences'];
    return SyncManifest(
      schemaVersion: intValue(json['schemaVersion'], 1),
      updatedAtUtc: DateTime.tryParse(stringValue(json['updatedAtUtc'], ''))?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      latestSnapshotPath: stringValue(json['latestSnapshotPath'], ''),
      deviceSequences: {
        if (rawSequences is Map)
          for (final entry in rawSequences.entries)
            if (entry.key is String && entry.value is num)
              entry.key as String: (entry.value as num).round(),
      },
    );
  }

  JsonMap toJson() {
    return {
      'schemaVersion': schemaVersion,
      'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
      'latestSnapshotPath': latestSnapshotPath,
      'deviceSequences': deviceSequences,
    };
  }
}

