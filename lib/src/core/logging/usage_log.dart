import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../model/app_state.dart';
import '../model/paper_data.dart';
import '../model/paper_item.dart';

class UsageLog {
  UsageLog({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final UsageLog instance = UsageLog();
  static const retentionDays = 7;

  final DateTime Function() _now;
  String? _directoryPath;
  Future<void> _writeQueue = Future<void>.value();

  String? get directoryPath => _directoryPath;

  Future<void> configureForStateFile(String stateFilePath) async {
    final trimmed = stateFilePath.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final directoryPath = p.join(p.dirname(trimmed), 'LOG');
    // Do this outside the queued cleanup so the folder exists immediately,
    // even when the first state load fails or the app exits during startup.
    await Directory(directoryPath).create(recursive: true);
    _directoryPath = directoryPath;
    await _enqueue(() async {
      final directory = Directory(_directoryPath!);
      await directory.create(recursive: true);
      await _removeExpiredLogs(directory);
    });
  }

  Future<void> record(
    String category,
    String action, {
    Map<String, Object?> details = const <String, Object?>{},
    String level = 'INFO',
  }) async {
    if (_directoryPath == null) {
      return;
    }
    final timestamp = _now().toLocal();
    final safeDetails = _sanitizeMap(details);
    final line = '[${timestamp.toIso8601String()}]'
        '[${_safeToken(level)}]'
        '[${_safeToken(category)}] '
        '${_safeAction(action)}'
        '${safeDetails.isEmpty ? '' : ' ${jsonEncode(safeDetails)}'}\n';
    await _enqueue(() async {
      final directory = Directory(_directoryPath!);
      await directory.create(recursive: true);
      await _removeExpiredLogs(directory);
      final file = File(p.join(directory.path, '${_dateKey(timestamp)}.txt'));
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    });
  }

  Future<void> recordStateChange({
    required AppState before,
    required AppState after,
    required String source,
  }) async {
    final changedSettings = _changedPaths(
      _settingsSnapshot(before),
      _settingsSnapshot(after),
    );
    if (changedSettings.isNotEmpty) {
      await record('settings', 'changed', details: {
        'source': source,
        'fields': changedSettings,
      });
    }

    final beforePapers = {for (final paper in before.papers) paper.id: paper};
    final afterPapers = {for (final paper in after.papers) paper.id: paper};
    final beforePaperIds = beforePapers.keys.toSet();
    final afterPaperIds = afterPapers.keys.toSet();
    for (final paperId in afterPaperIds.difference(beforePaperIds)) {
      final paper = afterPapers[paperId]!;
      await record('paper', 'created', details: {
        'source': source,
        'paperId': paperId,
        'paperType': paper.type,
      });
    }
    for (final paperId in beforePaperIds.difference(afterPaperIds)) {
      await record('paper', 'deleted', details: {
        'source': source,
        'paperId': paperId,
        'paperType': beforePapers[paperId]!.type,
      });
    }
    for (final paperId in beforePaperIds.intersection(afterPaperIds)) {
      final previous = beforePapers[paperId]!;
      final current = afterPapers[paperId]!;
      final changedFields = _changedPaths(
        _paperSnapshot(previous),
        _paperSnapshot(current),
      );
      final itemChanges = _itemChanges(previous.items, current.items);
      if (changedFields.isEmpty && itemChanges.isEmpty) {
        continue;
      }
      await record('paper', 'changed', details: {
        'source': source,
        'paperId': paperId,
        'paperType': current.type,
        if (changedFields.isNotEmpty) 'fields': changedFields,
        ...itemChanges,
      });
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      try {
        await operation();
      } catch (_) {
        // Diagnostics must never break the application action being logged.
      }
    });
    return _writeQueue;
  }

  Future<void> _removeExpiredLogs(Directory directory) async {
    final today = _dateOnly(_now().toLocal());
    final oldestKeptDay = today.subtract(
      const Duration(days: retentionDays - 1),
    );
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.txt') {
        continue;
      }
      final fileDate =
          _dateFromLogName(p.basenameWithoutExtension(entity.path));
      final expired = fileDate != null
          ? fileDate.isBefore(oldestKeptDay)
          : (await entity.lastModified()).isBefore(oldestKeptDay);
      if (expired) {
        await entity.delete();
      }
    }
  }
}

Map<String, Object?> _settingsSnapshot(AppState state) {
  final stateJson = Map<String, Object?>.from(state.toJson())
    ..remove('papers')
    ..remove('sync')
    ..remove('capsuleCollapseAllActive')
    ..remove('capsuleCollapseAllActiveQueues')
    ..remove('deepCapsuleQueueStartTopMargins');
  final webDav = state.sync.webDav;
  stateJson['sync'] = <String, Object?>{
    'enabled': state.sync.enabled,
    'provider': state.sync.provider,
    'webDav': <String, Object?>{
      'presetId': webDav.presetId,
      'endpoint': webDav.endpoint,
      'username': webDav.username,
      'password': _fingerprint(webDav.password),
      'encryptionPassphrase': _fingerprint(webDav.encryptionPassphrase),
      'rootPath': webDav.rootPath,
      'autoSyncOnStart': webDav.autoSyncOnStart,
      'autoSyncIntervalMinutes': webDav.autoSyncIntervalMinutes,
      'requestTimeoutSeconds': webDav.requestTimeoutSeconds,
    },
  };
  return stateJson;
}

Map<String, Object?> _paperSnapshot(PaperData paper) {
  return <String, Object?>{
    'type': paper.type,
    'titleHash': _fingerprint(paper.title),
    'x': paper.x.round(),
    'y': paper.y.round(),
    'width': paper.width.round(),
    'height': paper.height.round(),
    'isVisible': paper.isVisible,
    'alwaysOnTop': paper.alwaysOnTop,
    'isCollapsed': paper.isCollapsed,
    'isPinnedToDesktop': paper.isPinnedToDesktop,
    'textZoom': paper.textZoom,
    'capsuleSide': paper.capsuleSide,
    'capsuleMonitorDeviceName': paper.capsuleMonitorDeviceName,
    'contentHash': _fingerprint(paper.content),
    'contentLength': paper.content.length,
    'itemCount': paper.items.length,
    'doneCount': paper.items.where((item) => item.done).length,
    'canvasElementCount': paper.noteCanvasElements.length,
  };
}

Map<String, Object?> _itemSnapshot(PaperItem item) {
  return <String, Object?>{
    'textHash': _fingerprint(item.text),
    'done': item.done,
    'columnCount': item.todoColumnCount,
    'extraColumnHashes': item.todoExtraColumns.map(_fingerprint).toList(),
    'columnWidths': item.todoColumnWidths,
    'dueAtLocal': item.dueAtLocal,
    'reminderIntervalValue': item.reminderIntervalValue,
    'reminderIntervalUnit': item.reminderIntervalUnit,
    'linkedNoteId': item.linkedNoteId,
  };
}

Map<String, Object?> _itemChanges(
  List<PaperItem> before,
  List<PaperItem> after,
) {
  final previous = {for (final item in before) item.id: item};
  final current = {for (final item in after) item.id: item};
  final previousIds = previous.keys.toSet();
  final currentIds = current.keys.toSet();
  final created = currentIds.difference(previousIds).toList()..sort();
  final deleted = previousIds.difference(currentIds).toList()..sort();
  final changed = <String>[];
  for (final itemId in previousIds.intersection(currentIds)) {
    if (_changedPaths(
      _itemSnapshot(previous[itemId]!),
      _itemSnapshot(current[itemId]!),
    ).isNotEmpty) {
      changed.add(itemId);
    }
  }
  changed.sort();
  return <String, Object?>{
    if (created.isNotEmpty) 'itemsCreated': created,
    if (deleted.isNotEmpty) 'itemsDeleted': deleted,
    if (changed.isNotEmpty) 'itemsChanged': changed,
  };
}

List<String> _changedPaths(
  Map<String, Object?> before,
  Map<String, Object?> after, [
  String prefix = '',
]) {
  final result = <String>[];
  final keys = {...before.keys, ...after.keys}.toList()..sort();
  for (final key in keys) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    final previous = before[key];
    final current = after[key];
    if (previous is Map && current is Map) {
      result.addAll(_changedPaths(
        previous.map((key, value) => MapEntry(key.toString(), value)),
        current.map((key, value) => MapEntry(key.toString(), value)),
        path,
      ));
      continue;
    }
    if (jsonEncode(previous) != jsonEncode(current)) {
      result.add(path);
    }
  }
  return result;
}

Map<String, Object?> _sanitizeMap(Map<String, Object?> value) {
  return value.map((key, item) {
    final normalizedKey = key.toLowerCase();
    if (normalizedKey.contains('password') ||
        normalizedKey.contains('passphrase') ||
        normalizedKey.contains('authorization') ||
        normalizedKey.contains('token') ||
        normalizedKey.contains('secret')) {
      return MapEntry(key, '<redacted>');
    }
    if (item is Map<String, Object?>) {
      return MapEntry(key, _sanitizeMap(item));
    }
    if (item is Iterable) {
      return MapEntry(
        key,
        item
            .map((entry) =>
                entry is Map<String, Object?> ? _sanitizeMap(entry) : entry)
            .toList(),
      );
    }
    return MapEntry(key, item);
  });
}

String _fingerprint(String value) {
  if (value.isEmpty) {
    return '';
  }
  return sha256.convert(utf8.encode(value)).toString().substring(0, 12);
}

String _safeToken(String value) {
  final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return normalized.substring(0, normalized.length.clamp(0, 48).toInt());
}

String _safeAction(String value) =>
    value.replaceAll(RegExp(r'[\r\n\x00-\x1F\x7F-\x9F]+'), ' ').trim();

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime? _dateFromLogName(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) {
    return null;
  }
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}
