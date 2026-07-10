import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/model/app_state.dart';
import '../core/state/app_state_codec.dart';
import '../core/storage/state_store.dart';

class CrashRecoveryWriter {
  const CrashRecoveryWriter({
    AppStateCodec codec = const AppStateCodec(),
  }) : _codec = codec;

  static const int _maxCrashLogBytes = 100 * 1024;
  static const int _keptCrashLogBytes = 80 * 1024;

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
    File(recoveryPathFor(store)).writeAsStringSync(
      _codec.encode(snapshot),
      flush: true,
    );

    if (error != null || stackTrace != null) {
      final logPath = logPathFor(store);
      _trimCrashLogSync(logPath);
      File(logPath).writeAsStringSync(
        [
          'Unhandled RePaperTodo error',
          'Time UTC: ${DateTime.now().toUtc().toIso8601String()}',
          if (error != null) 'Error: $error',
          if (stackTrace != null) 'Stack trace:\n$stackTrace',
          '',
        ].join('\n'),
        mode: FileMode.append,
        flush: true,
      );
    }
  }

  void _trimCrashLogSync(String logPath) {
    final log = File(logPath);
    if (!log.existsSync() || log.lengthSync() <= _maxCrashLogBytes) {
      return;
    }

    final bytes = log.readAsBytesSync();
    final keepStart = bytes.length > _keptCrashLogBytes
        ? bytes.length - _keptCrashLogBytes
        : 0;
    final tail = utf8.decode(
      bytes.sublist(keepStart),
      allowMalformed: true,
    );
    final marker =
        '[Crash log trimmed to last ${_keptCrashLogBytes ~/ 1024} KB at '
        '${DateTime.now().toUtc().toIso8601String()}]\n';
    log.writeAsStringSync(marker + tail, flush: true);
  }
}
