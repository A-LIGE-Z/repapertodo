import 'dart:convert';

import '../model/app_state.dart';
import '../model/json_helpers.dart';

class AppStateCodec {
  const AppStateCodec();

  AppState decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('PaperTodo state must be a JSON object.');
    }
    return AppState.fromJson(Map<String, Object?>.from(decoded));
  }

  String encode(AppState state) {
    state.normalize();
    return const JsonEncoder.withIndent('  ').convert(state.toJson());
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

