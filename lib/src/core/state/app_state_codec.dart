import 'dart:convert';

import '../model/app_state.dart';
import '../model/json_helpers.dart';
import '../model/sync_settings.dart';
import 'papertodo_legacy_migration.dart';

class AppStateCodec {
  const AppStateCodec();

  AppState decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('PaperTodo state must be a JSON object.');
    }
    return AppState.fromJson(
      migrateLegacyPaperTodoJson(Map<String, Object?>.from(decoded)),
    );
  }

  String encode(AppState state) {
    state.normalize();
    return _prettyJson.convert(state.toJson());
  }

  String encodeRemoteSnapshot(AppState state) {
    state.normalize();
    final json = state.toJson();
    json['sync'] = _remoteSnapshotSyncJson(state.sync);
    return _prettyJson.convert(json);
  }

  AppState decodeOrEmpty(String? source) {
    if (source == null || source.trim().isEmpty) {
      return AppState();
    }
    return decode(source);
  }
}

JsonMap decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('Expected a JSON object.');
  }
  return Map<String, Object?>.from(decoded);
}

JsonMap _remoteSnapshotSyncJson(SyncSettings settings) {
  final sync = settings.copy()..normalize();
  return SyncSettings(
    enabled: false,
    provider: SyncProviderIds.none,
    webDav: WebDavSyncSettings(),
    operationDeviceSequences: sync.operationDeviceSequences,
    deletedPaperTombstones: Map<String, String>.from(
      sync.deletedPaperTombstones,
    ),
    deletedTodoItemTombstones: {
      for (final entry in sync.deletedTodoItemTombstones.entries)
        entry.key: Map<String, String>.from(entry.value),
    },
  ).toJson();
}

const _prettyJson = JsonEncoder.withIndent('  ');
