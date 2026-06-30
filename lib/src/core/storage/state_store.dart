import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/app_state.dart';
import '../state/app_state_codec.dart';

class StateStore {
  StateStore({
    required this.filePath,
    AppStateCodec codec = const AppStateCodec(),
  })  : backupPath = p.join(p.dirname(filePath), 'data.backup.json'),
        _codec = codec;

  final String filePath;
  final String backupPath;
  final AppStateCodec _codec;

  Future<AppState> load() async {
    final primary = File(filePath);
    final backup = File(backupPath);

    if (!await primary.exists() && !await backup.exists()) {
      return AppState();
    }

    Object? primaryError;
    if (await primary.exists()) {
      try {
        return _codec.decode(await primary.readAsString());
      } catch (error) {
        primaryError = error;
      }
    }

    if (await backup.exists()) {
      try {
        final recovered = _codec.decode(await backup.readAsString());
        if (await primary.exists()) {
          await _copyRecoverySource(primary, 'failed_load');
          await _copyRecoverySource(backup, 'used_for_recovery');
        }
        return recovered;
      } catch (_) {
        // Preserve the original primary error if both files fail.
      }
    }

    throw StateStoreException('Unable to load PaperTodo state.', primaryError);
  }

  Future<void> save(AppState state) async {
    state.normalize();
    final directory = Directory(p.dirname(filePath));
    await directory.create(recursive: true);

    final primary = File(filePath);
    final backup = File(backupPath);
    final temp = File('$filePath.tmp');
    await temp.writeAsString(_codec.encode(state));

    if (await primary.exists()) {
      try {
        await primary.copy(backup.path);
      } catch (_) {
        // Backup failures must not block the primary atomic replace.
      }
    }

    if (await primary.exists()) {
      await primary.delete();
    }
    await temp.rename(filePath);
  }

  Future<void> _copyRecoverySource(File source, String suffix) async {
    if (!await source.exists()) {
      return;
    }
    final directory = p.dirname(source.path);
    final stem = p.basenameWithoutExtension(source.path);
    final extension = p.extension(source.path);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '');
    for (var index = 0; index < 1000; index++) {
      final extra = index == 0 ? '' : '.$index';
      final target = File(p.join(directory, '$stem.$suffix.$stamp$extra$extension'));
      if (!await target.exists()) {
        await source.copy(target.path);
        return;
      }
    }
  }
}

class StateStoreException implements Exception {
  const StateStoreException(this.message, this.cause);

  final String message;
  final Object? cause;

  @override
  String toString() {
    return cause == null ? message : '$message Cause: $cause';
  }
}

