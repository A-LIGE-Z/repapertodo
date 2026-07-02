import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/storage/state_store.dart';
import 'sync_device_id.dart';

class SyncDeviceIdStore {
  const SyncDeviceIdStore({required this.filePath});

  factory SyncDeviceIdStore.forStateStore(StateStore store) {
    return SyncDeviceIdStore(
      filePath: p.join(p.dirname(store.filePath), 'sync-device-id'),
    );
  }

  final String filePath;

  Future<String> loadOrCreate() async {
    final file = File(filePath);
    final temp = File('$filePath.tmp');
    if (await file.exists()) {
      final stored = _normalize(await file.readAsString());
      if (stored != null) {
        await _writeDeviceId(stored);
        return stored;
      }
    }

    if (await temp.exists()) {
      final stored = _normalize(await temp.readAsString());
      if (stored != null) {
        await _writeDeviceId(stored);
        return stored;
      }
    }

    final created = 'device-${const Uuid().v4()}';
    await _writeDeviceId(created);
    return created;
  }

  String? _normalize(String value) {
    final normalized = normalizeSyncDeviceId(value, fallback: '');
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _writeDeviceId(String value) async {
    final file = File(filePath);
    final temp = File('$filePath.tmp');
    await file.parent.create(recursive: true);
    await temp.writeAsString(value);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(filePath);
  }
}
