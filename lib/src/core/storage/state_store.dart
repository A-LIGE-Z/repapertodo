import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/app_state.dart';
import '../state/app_state_codec.dart';

class StateStore {
  StateStore({
    required this.filePath,
    AppStateCodec codec = const AppStateCodec(),
    Future<void> Function(String encodedState)? beforeWrite,
  })  : backupPath = p.join(p.dirname(filePath), 'data.backup.json'),
        tempPath = '$filePath.tmp',
        _codec = codec,
        _beforeWrite = beforeWrite;

  final String filePath;
  final String backupPath;
  final String tempPath;
  final AppStateCodec _codec;
  final Future<void> Function(String encodedState)? _beforeWrite;
  Future<void> _saveQueue = Future<void>.value();

  Future<DateTime?> lastModifiedUtc() async {
    final primary = File(filePath);
    if (!await primary.exists()) {
      return null;
    }
    return (await primary.lastModified()).toUtc();
  }

  Future<AppState> load() async {
    final primary = File(filePath);
    final backup = File(backupPath);
    final temp = File(tempPath);

    if (!await primary.exists() &&
        !await backup.exists() &&
        !await temp.exists()) {
      return AppState();
    }

    Object? primaryError;
    Object? tempError;
    final primaryExists = await primary.exists();
    if (primaryExists) {
      try {
        return _codec.decode(await primary.readAsString());
      } catch (error) {
        primaryError = error;
      }
    }

    if (await temp.exists()) {
      try {
        final recovered = _codec.decode(await temp.readAsString());
        if (primaryExists) {
          await _copyRecoverySource(primary, 'failed_load');
        }
        await _copyRecoverySource(temp, 'used_for_recovery');
        return recovered;
      } catch (error) {
        tempError = error;
        await _copyRecoverySource(temp, 'failed_load');
        // Fall back to the stable backup if the interrupted write was partial.
      }
    }

    if (await backup.exists()) {
      try {
        final recovered = _codec.decode(await backup.readAsString());
        if (primaryExists) {
          await _copyRecoverySource(primary, 'failed_load');
          await _copyRecoverySource(backup, 'used_for_recovery');
        }
        return recovered;
      } catch (_) {
        // Preserve the original primary error if both files fail.
      }
    }

    throw StateStoreException(
      'Unable to load PaperTodo state.',
      primaryError ?? tempError,
    );
  }

  Future<void> save(AppState state) async {
    state.normalize();
    final encodedState = _codec.encode(state);
    final previousSave = _saveQueue;
    final save = previousSave.catchError((_) {}).then((_) {
      return _writeEncodedState(encodedState);
    });
    _saveQueue = save;
    await save;
  }

  Future<void> _writeEncodedState(String encodedState) async {
    final directory = Directory(p.dirname(filePath));
    await directory.create(recursive: true);

    final primary = File(filePath);
    final backup = File(backupPath);
    final temp = File(tempPath);
    await _beforeWrite?.call(encodedState);
    await temp.writeAsString(encodedState);

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
      final target =
          File(p.join(directory, '$stem.$suffix.$stamp$extra$extension'));
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
