import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('saves primary data and rotates backup', () async {
    final directory = await Directory.systemTemp.createTemp('repapertodo_store_test_');
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(AppState(theme: 'light'));
    await store.save(AppState(theme: 'dark'));

    final primary = await File(store.filePath).readAsString();
    final backup = await File(store.backupPath).readAsString();

    expect(primary, contains('"theme": "dark"'));
    expect(backup, contains('"theme": "light"'));
  });

  test('loads backup when primary data is corrupt', () async {
    final directory = await Directory.systemTemp.createTemp('repapertodo_store_recover_test_');
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString('{bad json');
    await File(store.backupPath).writeAsString('{"theme":"dark","papers":[]}');

    final state = await store.load();

    expect(state.theme, 'dark');
    expect(
      directory.listSync().where((entry) => p.basename(entry.path).contains('failed_load')),
      isNotEmpty,
    );
  });
}

