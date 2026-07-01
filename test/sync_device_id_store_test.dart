import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('normalizes existing device ids and writes them back', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_device_id_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'sync-device-id'));
    await file.writeAsString(' Device A ');
    final store = SyncDeviceIdStore(filePath: file.path);

    final deviceId = await store.loadOrCreate();

    expect(deviceId, 'device-a');
    expect(await file.readAsString(), 'device-a');
  });

  test('creates a new id when the stored id cannot be normalized', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_device_id_new_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'sync-device-id'));
    await file.writeAsString('bad');
    final store = SyncDeviceIdStore(filePath: file.path);

    final deviceId = await store.loadOrCreate();

    expect(deviceId, startsWith('device-'));
    expect(await file.readAsString(), deviceId);
  });
}
