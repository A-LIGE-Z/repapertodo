import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/app_state.dart';
import '../core/state/app_state_codec.dart';
import '../core/storage/state_store.dart';

class CrashRecoveryWriter {
  const CrashRecoveryWriter({
    AppStateCodec codec = const AppStateCodec(),
  }) : _codec = codec;

  final AppStateCodec _codec;

  String recoveryPathFor(StateStore store) {
    return p.join(p.dirname(store.filePath), 'data.crash_recovery.json');
  }

  String logPathFor(StateStore store) {
    return p.join(p.dirname(store.filePath), 'RePaperTodo.crash.log');
  }

  void saveSync({
    required StateStore store,
    required AppState state,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final directory = Directory(p.dirname(store.filePath));
    directory.createSync(recursive: true);

    final snapshot = AppState.fromJson(state.toJson());
    File(recoveryPathFor(store)).writeAsStringSync(_codec.encode(snapshot));

    if (error != null || stackTrace != null) {
      File(logPathFor(store)).writeAsStringSync(
        [
          'Unhandled RePaperTodo error',
          'Time UTC: ${DateTime.now().toUtc().toIso8601String()}',
          if (error != null) 'Error: $error',
          if (stackTrace != null) 'Stack trace:\n$stackTrace',
          '',
        ].join('\n'),
      );
    }
  }
}
