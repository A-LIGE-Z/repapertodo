import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/app_state.dart';
import '../state/app_state_codec.dart';

class StateStore {
  StateStore({
    required String filePath,
    AppStateCodec codec = const AppStateCodec(),
    Future<void> Function(String encodedState)? beforeWrite,
    Future<void> Function(File source, String targetPath)? recoveryCopy,
  })  : _filePath = filePath,
        _codec = codec,
        _beforeWrite = beforeWrite,
        _recoveryCopy = recoveryCopy;

  String _filePath;
  String get filePath => _filePath;
  String get backupPath => p.join(p.dirname(filePath), 'data.backup.json');
  String get tempPath => '$filePath.tmp';
  final AppStateCodec _codec;
  final Future<void> Function(String encodedState)? _beforeWrite;
  final Future<void> Function(File source, String targetPath)? _recoveryCopy;
  Future<void> _saveQueue = Future<void>.value();
  bool _skipNextBackupRotationAfterRecovery = false;

  Future<DateTime?> lastModifiedUtc() async {
    final primary = File(filePath);
    if (!await primary.exists()) {
      return null;
    }
    return (await primary.lastModified()).toUtc();
  }

  Future<AppState> load() async {
    _skipNextBackupRotationAfterRecovery = false;
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
          await _tryCopyRecoverySource(primary, 'failed_load');
          _skipNextBackupRotationAfterRecovery = true;
        }
        await _tryCopyRecoverySource(temp, 'used_for_recovery');
        return recovered;
      } catch (error) {
        tempError = error;
        await _tryCopyRecoverySource(temp, 'failed_load');
        // Fall back to the stable backup if the interrupted write was partial.
      }
    }

    if (await backup.exists()) {
      try {
        final recovered = _codec.decode(await backup.readAsString());
        if (primaryExists) {
          await _tryCopyRecoverySource(primary, 'failed_load');
          _skipNextBackupRotationAfterRecovery = true;
        }
        await _tryCopyRecoverySource(backup, 'used_for_recovery');
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

  Future<void> relocate(String nextFilePath, AppState state) async {
    final normalized = p.normalize(p.absolute(nextFilePath.trim()));
    if (normalized == p.normalize(p.absolute(filePath))) {
      return;
    }
    await _saveQueue.catchError((_) {});
    final target = StateStore(
      filePath: normalized,
      codec: _codec,
      beforeWrite: _beforeWrite,
      recoveryCopy: _recoveryCopy,
    );
    await target.save(state);
    _filePath = normalized;
    _saveQueue = Future<void>.value();
    _skipNextBackupRotationAfterRecovery = false;
  }

  Future<void> _writeEncodedState(String encodedState) async {
    final directory = Directory(p.dirname(filePath));
    await directory.create(recursive: true);

    final primary = File(filePath);
    final backup = File(backupPath);
    final temp = File(tempPath);
    final skipBackupRotation = _skipNextBackupRotationAfterRecovery;
    await _beforeWrite?.call(encodedState);
    await temp.writeAsString(encodedState, flush: true);

    if (!skipBackupRotation && await primary.exists()) {
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
    if (skipBackupRotation) {
      _skipNextBackupRotationAfterRecovery = false;
    }
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
        final recoveryCopy = _recoveryCopy;
        if (recoveryCopy == null) {
          await source.copy(target.path);
        } else {
          await recoveryCopy(source, target.path);
        }
        return;
      }
    }
  }

  Future<void> _tryCopyRecoverySource(File source, String suffix) async {
    try {
      await _copyRecoverySource(source, suffix);
    } catch (_) {
      // Recovery audit copies are best-effort; a valid recovered state must
      // stay loadable even when the local filesystem rejects extra copies.
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
