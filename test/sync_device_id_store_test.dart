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
    expect(await File('${file.path}.tmp').exists(), false);
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
    expect(await File('${file.path}.tmp').exists(), false);
  });

  test('recovers a valid temp id when the primary id is missing', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_device_id_tmp_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'sync-device-id'));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(' Device Temp ');
    final store = SyncDeviceIdStore(filePath: file.path);

    final deviceId = await store.loadOrCreate();

    expect(deviceId, 'device-temp');
    expect(await file.readAsString(), 'device-temp');
    expect(await temp.exists(), false);
  });

  test('recovers a valid temp id when the primary id is invalid', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_device_id_invalid_primary_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'sync-device-id'));
    final temp = File('${file.path}.tmp');
    await file.writeAsString('bad');
    await temp.writeAsString(' Device Temp ');
    final store = SyncDeviceIdStore(filePath: file.path);

    final deviceId = await store.loadOrCreate();

    expect(deviceId, 'device-temp');
    expect(await file.readAsString(), 'device-temp');
    expect(await temp.exists(), false);
  });

  test('serializes concurrent device id creation for one file path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_device_id_concurrent_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'sync-device-id'));

    final ids = await Future.wait([
      for (var index = 0; index < 24; index += 1)
        SyncDeviceIdStore(filePath: file.path).loadOrCreate(),
    ]);

    expect(ids.toSet(), hasLength(1));
    expect(await file.readAsString(), ids.first);
    expect(await File('${file.path}.tmp').exists(), false);
  });
}
