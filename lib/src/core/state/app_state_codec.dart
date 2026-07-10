import 'dart:convert';

import '../model/app_state.dart';
import '../model/json_helpers.dart';
import '../model/sync_settings.dart';
import 'papertodo_legacy_migration.dart';

class AppStateCodec {
  const AppStateCodec();

  AppState decode(String source) {
    final decoded = _decodePaperTodoStateJson(source);
    final decodedMap = jsonMapOrNull(decoded);
    if (decodedMap == null) {
      throw const FormatException('PaperTodo state must be a JSON object.');
    }
    return AppState.fromJson(
      migrateLegacyPaperTodoJson(decodedMap),
    );
  }

  String encode(AppState state) {
    state.normalize();
    return _prettyJson.convert(state.toJson());
  }

  String encodeRemoteSnapshot(AppState state) {
    state.normalize();
    final json = state.toJson();
    json.remove('startAtLogin');
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
  final decodedMap = jsonMapOrNull(decoded);
  if (decodedMap == null) {
    throw const FormatException('Expected a JSON object.');
  }
  return decodedMap;
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

Object? _decodePaperTodoStateJson(String source) {
  final normalizedSource = _stripByteOrderMark(source);
  try {
    return jsonDecode(normalizedSource);
  } on FormatException {
    return jsonDecode(
      _removePaperTodoJsonTrailingCommas(
        _stripPaperTodoJsonComments(normalizedSource),
      ),
    );
  }
}

String _stripByteOrderMark(String source) {
  if (source.startsWith('\uFEFF')) {
    return source.substring(1);
  }
  return source;
}

String _stripPaperTodoJsonComments(String source) {
  final buffer = StringBuffer();
  var inString = false;
  var escaped = false;
  var inLineComment = false;
  var inBlockComment = false;

  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';

    if (inLineComment) {
      if (char == '\n' || char == '\r') {
        inLineComment = false;
        buffer.write(char);
      }
      continue;
    }

    if (inBlockComment) {
      if (char == '*' && next == '/') {
        inBlockComment = false;
        buffer.write(' ');
        index++;
      } else if (char == '\n' || char == '\r') {
        buffer.write(char);
      }
      continue;
    }

    if (inString) {
      buffer.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }

    if (char == '"') {
      inString = true;
      buffer.write(char);
      continue;
    }

    if (char == '/' && next == '/') {
      inLineComment = true;
      buffer.write(' ');
      index++;
      continue;
    }

    if (char == '/' && next == '*') {
      inBlockComment = true;
      buffer.write(' ');
      index++;
      continue;
    }

    buffer.write(char);
  }

  if (inBlockComment) {
    throw const FormatException('Unterminated PaperTodo JSON block comment.');
  }

  return buffer.toString();
}

String _removePaperTodoJsonTrailingCommas(String source) {
  final buffer = StringBuffer();
  var inString = false;
  var escaped = false;

  for (var index = 0; index < source.length; index++) {
    final char = source[index];

    if (inString) {
      buffer.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }

    if (char == '"') {
      inString = true;
      buffer.write(char);
      continue;
    }

    if (char == ',') {
      final nextToken = _nextNonWhitespace(source, index + 1);
      if (nextToken == ']' || nextToken == '}') {
        continue;
      }
    }

    buffer.write(char);
  }

  return buffer.toString();
}

String? _nextNonWhitespace(String source, int start) {
  for (var index = start; index < source.length; index++) {
    final char = source[index];
    if (char != ' ' && char != '\t' && char != '\n' && char != '\r') {
      return char;
    }
  }
  return null;
}
