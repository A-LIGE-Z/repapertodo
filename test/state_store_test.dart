import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('relocates current state to a new data directory', () async {
    final source =
        await Directory.systemTemp.createTemp('repapertodo_store_source_');
    final target =
        await Directory.systemTemp.createTemp('repapertodo_store_target_');
    addTearDown(() async {
      await source.delete(recursive: true);
      await target.delete(recursive: true);
    });
    final sourcePath = p.join(source.path, 'data.json');
    final targetPath = p.join(target.path, 'data.json');
    final store = StateStore(filePath: sourcePath);
    final state = AppState(theme: 'dark');
    await store.save(state);

    await store.relocate(targetPath, state);

    expect(store.filePath, p.normalize(p.absolute(targetPath)));
    expect(await File(sourcePath).exists(), true);
    expect(await File(targetPath).readAsString(), contains('"theme": "dark"'));
  });

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
    expect(
      directory.listSync().where(
            (entry) =>
                p.basename(entry.path).startsWith(
                      'data.backup.used_for_recovery',
                    ) &&
                p.basename(entry.path).endsWith('.json'),
          ),
      isNotEmpty,
    );
  });

  test('preserves recovery backup on first save after backup load', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_preserve_backup_recovery_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString('{bad json');
    await File(store.backupPath).writeAsString('{"theme":"dark","papers":[]}');

    final recovered = await store.load();
    expect(recovered.theme, 'dark');

    await store.save(AppState(theme: 'light'));

    final primary = await File(store.filePath).readAsString();
    final backup = await File(store.backupPath).readAsString();
    expect(primary, contains('"theme": "light"'));
    expect(backup, contains('"theme":"dark"'));
    expect(backup, isNot(contains('{bad json')));
  });

  test('loads backup when recovery audit copies fail', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_recovery_copy_failure_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(
      filePath: p.join(directory.path, 'data.json'),
      recoveryCopy: (source, targetPath) async {
        throw const FileSystemException('copy denied');
      },
    );
    await File(store.filePath).writeAsString('{bad json');
    await File(store.backupPath).writeAsString('{"theme":"dark","papers":[]}');

    final state = await store.load();

    expect(state.theme, 'dark');
    expect(
      directory
          .listSync()
          .where((entry) => p.basename(entry.path).contains('failed_load')),
      isEmpty,
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

  test('loads representative PaperTodo data and resaves canonical state',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_representative_migration_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final sourceJson = jsonDecode(
      File('test/fixtures/papertodo_original_data.json').readAsStringSync(),
    ) as Map<String, Object?>;
    sourceJson['futureRootField'] = 'keep-root';
    final sourcePapers = sourceJson['papers']! as List<Object?>;
    final sourceTodo = sourcePapers.first! as Map<String, Object?>;
    sourceTodo['futurePaperField'] = 'keep-paper';
    final sourceTodoItems = sourceTodo['items']! as List<Object?>;
    final sourceTodoItem = sourceTodoItems.first! as Map<String, Object?>;
    sourceTodoItem['futureItemField'] = 'keep-item';
    final sourceNote = sourcePapers.last! as Map<String, Object?>;
    final sourceCanvasElements =
        sourceNote['noteCanvasElements']! as List<Object?>;
    final sourceCanvas = sourceCanvasElements.single! as Map<String, Object?>;
    sourceCanvas['futureCanvasField'] = 'keep-canvas';

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(sourceJson),
    );

    final state = await store.load();
    await store.save(state);

    final canonical = jsonDecode(await File(store.filePath).readAsString())
        as Map<String, Object?>;
    final canonicalPapers = canonical['papers']! as List<Object?>;
    final canonicalTodo = canonicalPapers.first! as Map<String, Object?>;
    final canonicalTodoItems = canonicalTodo['items']! as List<Object?>;
    final canonicalTodoItem = canonicalTodoItems.first! as Map<String, Object?>;
    final canonicalNote = canonicalPapers.last! as Map<String, Object?>;
    final canonicalCanvasElements =
        canonicalNote['noteCanvasElements']! as List<Object?>;
    final canonicalCanvas =
        canonicalCanvasElements.single! as Map<String, Object?>;

    expect(state.papers.map((paper) => paper.id), [
      'todo-paper-001',
      'note-paper-001',
    ]);
    expect(state.theme, 'dark');
    expect(state.sync.provider, SyncProviderIds.none);
    expect(canonical.containsKey('Papers'), false);
    expect(canonical.containsKey('topBarHeight'), false);
    expect(canonical['futureRootField'], 'keep-root');
    expect(canonicalTodo['futurePaperField'], 'keep-paper');
    expect(canonicalTodoItem['futureItemField'], 'keep-item');
    expect(canonicalTodoItem['order'], 0);
    expect(canonicalCanvas['futureCanvasField'], 'keep-canvas');
    expect(canonicalCanvas['zIndex'], 10);
    expect(canonical['sync'], isA<Map<String, Object?>>());
  });

  test(
      'loads hand-edited PaperTodo primary data with comments and trailing commas',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_lenient_json_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString('''
{
  // Kept compatible with original PaperTodo StateStore options.
  "theme": "dark",
  "papers": [
    {
      "id": "hand-edited-note",
      "type": "note",
      "content": "Text with // and /* markers */ inside a string.",
    },
  ],
}
''');

    final state = await store.load();

    expect(state.theme, 'dark');
    expect(state.papers.single.id, 'hand-edited-note');
    expect(
      state.papers.single.content,
      'Text with // and /* markers */ inside a string.',
    );
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

  test('recovers valid temp data when recovery audit copies fail', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_temp_recovery_copy_failure_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(
      filePath: p.join(directory.path, 'data.json'),
      recoveryCopy: (source, targetPath) async {
        throw const FileSystemException('copy denied');
      },
    );
    await File(store.backupPath).writeAsString('{"theme":"light","papers":[]}');
    await File(store.tempPath).writeAsString('{"theme":"dark","papers":[]}');

    final state = await store.load();

    expect(state.theme, 'dark');
    expect(
      directory.listSync().where(
            (entry) =>
                p.basename(entry.path).contains('used_for_recovery') ||
                p.basename(entry.path).contains('failed_load'),
          ),
      isEmpty,
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

  test('preserves recovery backup on first save after temp recovery', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_store_preserve_temp_recovery_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(store.filePath).writeAsString('{bad json');
    await File(store.backupPath).writeAsString('{"theme":"light","papers":[]}');
    await File(store.tempPath).writeAsString('{"theme":"dark","papers":[]}');

    final recovered = await store.load();
    expect(recovered.theme, 'dark');

    await store.save(AppState(theme: 'system'));

    final primary = await File(store.filePath).readAsString();
    final backup = await File(store.backupPath).readAsString();
    expect(primary, contains('"theme": "system"'));
    expect(backup, contains('"theme":"light"'));
    expect(backup, isNot(contains('{bad json')));
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
    expect(
      directory.listSync().where(
            (entry) =>
                p.basename(entry.path).startsWith(
                      'data.backup.used_for_recovery',
                    ) &&
                p.basename(entry.path).endsWith('.json'),
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
