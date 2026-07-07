import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('saves primary data and rotates backup', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_store_test_');
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await store.save(AppState(theme: 'light'));
    await store.save(AppState(theme: 'dark'));

    final primary = await File(store.filePath).readAsString();
    final backup = await File(store.backupPath).readAsString();

    expect(primary, contains('"theme": "dark"'));
    expect(backup, contains('"theme": "light"'));
  });

  test('serializes concurrent saves so older snapshots cannot win', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_concurrent_save_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final firstWriteStarted = Completer<void>();
    final releaseFirstWrite = Completer<void>();
    final store = StateStore(
      filePath: p.join(directory.path, 'data.json'),
      beforeWrite: (encodedState) async {
        if (encodedState.contains('"theme": "light"')) {
          if (!firstWriteStarted.isCompleted) {
            firstWriteStarted.complete();
          }
          await releaseFirstWrite.future;
        }
      },
    );

    final firstSave = store.save(AppState(theme: 'light'));
    await firstWriteStarted.future;
    final secondSave = store.save(AppState(theme: 'dark'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await File(store.filePath).exists(), false);

    releaseFirstWrite.complete();
    await Future.wait([firstSave, secondSave]);

    final primary = await File(store.filePath).readAsString();
    final backup = await File(store.backupPath).readAsString();
    expect(primary, contains('"theme": "dark"'));
    expect(backup, contains('"theme": "light"'));
  });

  test('loads backup when primary data is corrupt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_recover_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString('{bad json');
    await File(store.backupPath).writeAsString('{"theme":"dark","papers":[]}');

    final state = await store.load();

    expect(state.theme, 'dark');
    expect(
      directory
          .listSync()
          .where((entry) => p.basename(entry.path).contains('failed_load')),
      isNotEmpty,
    );
  });

  test('loads legacy PaperTodo primary data through the codec migration',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_legacy_primary_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString(_legacyPaperTodoJson(
      title: 'Legacy primary',
      theme: 'dark',
    ));

    final state = await store.load();

    expect(state.theme, 'dark');
    expect(state.papers.single.id, 'paper-legacy');
    expect(state.papers.single.title, 'Legacy');
    expect(state.papers.single.items.single.text, 'Imported item');
  });

  test('recovers valid temp data when primary is missing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_temp_recover_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.backupPath).writeAsString('{"theme":"light","papers":[]}');
    await File(store.tempPath).writeAsString('{"theme":"dark","papers":[]}');

    final state = await store.load();

    expect(state.theme, 'dark');
    expect(
      directory.listSync().where(
            (entry) =>
                p
                    .basename(entry.path)
                    .startsWith('data.json.used_for_recovery') &&
                p.basename(entry.path).endsWith('.tmp'),
          ),
      isNotEmpty,
    );
  });

  test('recovers valid temp data when primary is corrupt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_temp_over_corrupt_primary_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString('{bad json');
    await File(store.backupPath).writeAsString('{"theme":"light","papers":[]}');
    await File(store.tempPath).writeAsString('{"theme":"dark","papers":[]}');

    final state = await store.load();

    expect(state.theme, 'dark');
    final recoveryFiles = directory.listSync().map((entry) {
      return p.basename(entry.path);
    }).toList();
    expect(
      recoveryFiles.where((name) => name.startsWith('data.failed_load')),
      isNotEmpty,
    );
    expect(
      recoveryFiles.where(
        (name) =>
            name.startsWith('data.json.used_for_recovery') &&
            name.endsWith('.tmp'),
      ),
      isNotEmpty,
    );
  });

  test('recovers legacy PaperTodo temp data when primary is missing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_legacy_temp_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.backupPath).writeAsString('{"theme":"light","papers":[]}');
    await File(store.tempPath).writeAsString(_legacyPaperTodoJson(
      title: 'Legacy temp',
      theme: 'dark',
    ));

    final state = await store.load();

    expect(state.theme, 'dark');
    expect(state.papers.single.title, 'Legacy');
    expect(
      directory.listSync().where(
            (entry) =>
                p
                    .basename(entry.path)
                    .startsWith('data.json.used_for_recovery') &&
                p.basename(entry.path).endsWith('.tmp'),
          ),
      isNotEmpty,
    );
  });

  test('falls back to backup when temp data is corrupt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_temp_corrupt_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.backupPath).writeAsString('{"theme":"light","papers":[]}');
    await File(store.tempPath).writeAsString('{bad json');

    final state = await store.load();

    expect(state.theme, 'light');
    expect(
      directory.listSync().where(
            (entry) =>
                p.basename(entry.path).contains('failed_load') &&
                p.basename(entry.path).endsWith('.tmp'),
          ),
      isNotEmpty,
    );
  });

  test('reports corrupt temp data when no stable state exists', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_only_temp_corrupt_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.tempPath).writeAsString('{bad json');

    await expectLater(
      store.load(),
      throwsA(
        isA<StateStoreException>()
            .having((error) => error.message, 'message',
                'Unable to load PaperTodo state.')
            .having((error) => error.cause, 'cause', isNotNull),
      ),
    );
    expect(
      directory.listSync().where(
            (entry) =>
                p.basename(entry.path).contains('failed_load') &&
                p.basename(entry.path).endsWith('.tmp'),
          ),
      isNotEmpty,
    );
  });

  test('loads legacy PaperTodo backup data when primary is corrupt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_legacy_backup_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString('{bad json');
    await File(store.backupPath).writeAsString(_legacyPaperTodoJson(
      title: 'Legacy backup',
      theme: 'light',
    ));

    final state = await store.load();

    expect(state.theme, 'light');
    expect(state.papers.single.title, 'Legacy');
  });
}

String _legacyPaperTodoJson({
  required String title,
  required String theme,
}) {
  return '''
{
  "Theme": "$theme",
  "Papers": [
    {
      "Id": "paper-legacy",
      "Type": "todo",
      "Title": "$title",
      "Items": [
        {
          "Id": "item-legacy",
          "Text": "Imported item",
          "Done": false
        }
      ]
    }
  ]
}
''';
}
