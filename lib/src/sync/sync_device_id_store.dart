import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/storage/state_store.dart';

class SyncDeviceIdStore {
  const SyncDeviceIdStore({required this.filePath});

  factory SyncDeviceIdStore.forStateStore(StateStore store) {
    return SyncDeviceIdStore(
      filePath: p.join(p.dirname(store.filePath), 'sync-device-id'),
    );
  }

  static final _validDeviceId = RegExp(r'^[a-z0-9][a-z0-9_-]{7,63}$');

  final String filePath;

  Future<String> loadOrCreate() async {
    final file = File(filePath);
    if (await file.exists()) {
      final stored = _normalize(await file.readAsString());
      if (stored != null) {
        return stored;
      }
    }

    final created = 'device-${const Uuid().v4()}';
    await file.parent.create(recursive: true);
    await file.writeAsString(created);
    return created;
  }

  String? _normalize(String value) {
    final normalized = value.trim().toLowerCase();
    return _validDeviceId.hasMatch(normalized) ? normalized : null;
  }
}
