import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  const builder = SyncOperationDiffBuilder();
  const applier = SyncOperationApplier();

  test('builds note content and settings operations', () {
    final before = AppState(
      theme: 'light',
      enableToolTips: true,
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'Old body',
        ),
      ],
    );
    final after = AppState(
      theme: 'dark',
      enableToolTips: false,
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'New body',
        ),
      ],
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-a',
      startSequence: 7,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(
      operations.map((operation) => operation.kind),
      [
        SyncOperationKind.updateSettings,
        SyncOperationKind.updateNoteContent,
      ],
    );
    expect(operations.map((operation) => operation.sequence), [8, 9]);
    expect(operations.first.id, 'device-a-8');
    expect(operations.first.payload['settings'], {
      'theme': 'dark',
      'enableToolTips': false,
    });
    expect(operations.last.payload, {
      'paperId': 'note',
      'content': 'New body',
    });

    final result = applier.apply(
      before,
      operations,
      deviceSequences: {'device-a': 7},
    );

    expect(result.appliedCount, 2);
    expect(result.deviceSequences, {'device-a': 9});
    expect(result.state.theme, 'dark');
    expect(result.state.enableToolTips, false);
    expect(result.state.papers.single.content, 'New body');
  });

  test('builds well-formed note content operations when content is cleared',
      () {
    final before = AppState(
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'Body to clear',
        ),
      ],
    );
    final after = AppState(
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: '',
        ),
      ],
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(operations, hasLength(1));
    expect(operations.single.kind, SyncOperationKind.updateNoteContent);
    expect(operations.single.payload, {
      'paperId': 'note',
      'content': '',
    });

    final result = applier.apply(before, operations);

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.papers.single.content, isEmpty);
  });

  test('normalizes local model ids before building operation payloads', () {
    final noteBefore = AppState(
      papers: [
        PaperData(
          id: ' note\u0000-paper ',
          type: PaperTypes.note,
          title: 'Note',
          content: 'Old body',
        ),
      ],
    );
    final noteAfter = AppState(
      papers: [
        PaperData(
          id: ' note\u0000-paper ',
          type: PaperTypes.note,
          title: 'Note',
          content: 'New body',
        ),
      ],
    );

    final noteOperations = builder.build(
      before: noteBefore,
      after: noteAfter,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(noteOperations, hasLength(1));
    expect(noteOperations.single.kind, SyncOperationKind.updateNoteContent);
    expect(noteOperations.single.payload, {
      'paperId': 'note-paper',
      'content': 'New body',
    });
    expect(isSyncOperationPayloadWellFormed(noteOperations.single), true);

    final todoBefore = AppState(
      papers: [
        PaperData(
          id: ' todo\u0000-paper ',
          type: PaperTypes.todo,
          items: [
            PaperItem(
              id: ' item\u007F-one ',
              text: 'Delete me',
              linkedNoteId: ' note\u0085-paper ',
            ),
          ],
        ),
      ],
    );
    final todoAfter = AppState(
      papers: [
        PaperData(
          id: ' todo\u0000-paper ',
          type: PaperTypes.todo,
          items: const [],
        ),
      ],
    );

    final todoOperations = builder.build(
      before: todoBefore,
      after: todoAfter,
      deviceId: 'device-a',
      startSequence: 1,
      createdAtUtc: DateTime.utc(2026, 7, 1, 11),
    );

    expect(todoOperations, hasLength(1));
    expect(todoOperations.single.kind, SyncOperationKind.deleteTodoItem);
    expect(todoOperations.single.payload, {
      'paperId': 'todo-paper',
      'itemId': 'item-one',
    });
    expect(isSyncOperationPayloadWellFormed(todoOperations.single), true);

    final upsertOperations = builder.build(
      before: AppState(),
      after: AppState(
        papers: [
          PaperData(id: ' note\u0085-paper ', type: PaperTypes.note),
          PaperData(
            id: ' todo\u0000-paper ',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: ' item\u007F-one ',
                text: 'Upload me',
                linkedNoteId: ' note\u0085-paper ',
              ),
            ],
          ),
        ],
      ),
      deviceId: 'device-a',
      startSequence: 2,
      createdAtUtc: DateTime.utc(2026, 7, 1, 12),
    );

    final todoUpsert = upsertOperations.firstWhere(
      (operation) =>
          operation.kind == SyncOperationKind.upsertPaper &&
          (operation.payload['paper'] as Map)['type'] == PaperTypes.todo,
    );
    final paper = todoUpsert.payload['paper'] as Map;
    final item = (paper['items'] as List).single as Map;
    expect(paper['id'], 'todo-paper');
    expect(item['id'], 'item-one');
    expect(item['linkedNoteId'], 'note-paper');
    expect(isSyncOperationPayloadWellFormed(todoUpsert), true);
  });

  test('excludes local sync and startup settings from settings operations', () {
    final before = AppState(
      theme: 'light',
      startAtLogin: false,
      extra: {'localExtensionSetting': 'before'},
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings(
          endpoint: 'https://dav.example.test/',
          username: 'local-user',
          password: 'local-password',
          encryptionPassphrase: 'local-secret',
          rootPath: 'RePaperTodo',
          autoSyncIntervalMinutes: 15,
          requestTimeoutSeconds: 45,
        ),
        operationDeviceSequences: {'device-a': 7},
      ),
    );
    final syncOnlyAfter = AppState(
      theme: 'light',
      startAtLogin: true,
      extra: {'localExtensionSetting': 'after'},
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings(
          endpoint: 'https://dav.example.test/changed/',
          username: 'changed-user',
          password: 'changed-password',
          encryptionPassphrase: 'changed-secret',
          rootPath: 'ChangedRoot',
          autoSyncIntervalMinutes: 60,
          requestTimeoutSeconds: 90,
        ),
        operationDeviceSequences: {'device-a': 8},
      ),
    );
    final settingsAfter = AppState.fromJson(syncOnlyAfter.toJson())
      ..theme = 'dark';

    final syncOnlyOperations = builder.build(
      before: before,
      after: syncOnlyAfter,
      deviceId: 'device-a',
      startSequence: 7,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );
    final settingsOperations = builder.build(
      before: before,
      after: settingsAfter,
      deviceId: 'device-a',
      startSequence: 7,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(syncOnlyOperations, isEmpty);
    expect(settingsOperations, hasLength(1));
    expect(settingsOperations.single.kind, SyncOperationKind.updateSettings);
    expect(settingsOperations.single.payload['settings'], {'theme': 'dark'});
    expect(isSyncOperationPayloadWellFormed(settingsOperations.single), true);
  });

  test('normalizes setting diffs before building operations', () {
    final longHotKey = 'Ctrl+Alt+${List.filled(80, 'A').join()}';
    final before = AppState(
      theme: 'dark',
      colorScheme: ColorSchemes.forest,
      customThemeColorHex: '#336699',
      markdownRenderMode: MarkdownRenderModes.basic,
      todoVisualSize: TodoVisualSizes.extraLarge,
      uiFontPreset: UiFontPresets.mono,
      systemFontFamilyName: 'Paper Font',
      externalMarkdownExtension: '.md',
      todoDueYearDisplayMode: TodoDueYearDisplayModes.full,
      todoReminderIntervalUnit: TodoReminderIntervalUnits.hours,
      todoReminderScope: TodoReminderScopes.nearest,
      pinnedTodoHotKey: 'Ctrl+Alt+T',
      pinnedNoteHotKey: longHotKey.substring(0, 64),
      fullscreenTopmostMode: FullscreenTopmostModes.stayOnTop,
      deepCapsuleSide: DeepCapsuleSides.left,
      deepCapsuleMonitorDeviceName: 'Primary',
      capsuleCollapseAllActiveQueues: {
        '|left': true,
        'Primary|right': true,
      },
      deepCapsuleQueueStartTopMargins: {
        '|left': 16.25,
        'Primary|right': 8.0,
      },
    );
    final after = AppState(
      theme: ' DARK ',
      colorScheme: ' FOREST ',
      customThemeColorHex: '336699',
      markdownRenderMode: 'BASIC',
      todoVisualSize: 'EXTRALARGE',
      uiFontPreset: 'MONO',
      systemFontFamilyName: ' \u0000Paper Font\u007F ',
      externalMarkdownExtension: '*.MD',
      todoDueYearDisplayMode: 'FULL',
      todoReminderIntervalUnit: 'HOURS',
      todoReminderScope: 'NEAREST',
      pinnedTodoHotKey: ' Ctrl+\nAlt+\u007FT ',
      pinnedNoteHotKey: '$longHotKey\n',
      fullscreenTopmostMode: 'STAYONTOP',
      deepCapsuleSide: 'LEFT',
      deepCapsuleMonitorDeviceName: ' Primary ',
      capsuleCollapseAllActiveQueues: {
        'left': true,
        ' Primary | RIGHT ': true,
        'Ghost|left': false,
      },
      deepCapsuleQueueStartTopMargins: {
        'left': 16.25,
        ' Primary | RIGHT ': 2,
      },
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(operations, isEmpty);
  });

  test('ignores queue map diffs that only change alias precedence', () {
    final before = AppState(
      useCapsuleMode: true,
      useDeepCapsuleMode: true,
      useCapsuleCollapseAll: true,
      capsuleCollapseAllActive: true,
      capsuleCollapseAllActiveQueues: {
        'Primary|right': true,
      },
      deepCapsuleQueueStartTopMargins: {
        '|right': 8.0,
        'Primary|left': 10000.0,
      },
    );
    final after = AppState(
      useCapsuleMode: true,
      useDeepCapsuleMode: true,
      useCapsuleCollapseAll: true,
      capsuleCollapseAllActive: false,
      capsuleCollapseAllActiveQueues: {
        'left': true,
        '|left': false,
        'Primary | right ': false,
        'Primary|right': true,
      },
      deepCapsuleQueueStartTopMargins: {
        'right': 32.5,
        '|right': 4,
        'Primary | left ': 12,
        'Primary|left': 12000,
      },
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(operations, isEmpty);
  });

  test('drops invalid setting diffs and uploads only canonical values', () {
    final before = AppState(
      theme: 'light',
      enableToolTips: true,
      externalMarkdownExtension: '.md',
    );
    final invalidOnlyAfter = AppState(
      theme: 'mystery',
      externalMarkdownExtension: 'md:bad',
    );
    final mixedAfter = AppState(
      theme: 'mystery',
      enableToolTips: false,
      externalMarkdownExtension: '*.MARKDOWN',
    );

    final invalidOnlyOperations = builder.build(
      before: before,
      after: invalidOnlyAfter,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );
    final mixedOperations = builder.build(
      before: before,
      after: mixedAfter,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(invalidOnlyOperations, isEmpty);
    expect(mixedOperations, hasLength(1));
    expect(mixedOperations.single.kind, SyncOperationKind.updateSettings);
    expect(mixedOperations.single.payload['settings'], {
      'externalMarkdownExtension': '.markdown',
      'enableToolTips': false,
    });
    expect(isSyncOperationPayloadWellFormed(mixedOperations.single), true);
  });

  test('does not upload capsule settings that normalize back to local state',
      () {
    final normalized = AppState(
      useCapsuleMode: false,
      useDeepCapsuleMode: false,
      useCapsuleCollapseAll: false,
      capsuleCollapseAllActive: false,
      deepCapsuleStartTopMargin: 48,
    );
    final rawEquivalent = AppState(
      useCapsuleMode: false,
      useDeepCapsuleMode: true,
      useCapsuleCollapseAll: true,
      capsuleCollapseAllActive: true,
      capsuleCollapseAllActiveQueues: {
        'left': true,
      },
      deepCapsuleStartTopMargin: 16,
      deepCapsuleQueueStartTopMargins: {
        'left': 16,
      },
    );

    final operations = builder.build(
      before: normalized,
      after: rawEquivalent,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(operations, isEmpty);
  });

  test('builds paper add delete and todo item operations', () {
    final before = AppState(
      papers: [
        PaperData(
          id: 'old-paper',
          type: PaperTypes.note,
          title: 'Remove me',
        ),
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          title: 'Todo',
          items: [
            PaperItem(id: 'item-1', text: 'Old item'),
            PaperItem(id: 'item-2', text: 'Delete item'),
          ],
        ),
      ],
    );
    final after = AppState(
      papers: [
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          title: 'Todo',
          items: [
            PaperItem(id: 'item-1', text: 'Updated item', done: true),
            PaperItem(id: 'item-3', text: 'New item'),
          ],
        ),
        PaperData(
          id: 'new-note',
          type: PaperTypes.note,
          title: 'New note',
          content: 'Hello',
        ),
      ],
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-b',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 11),
    );

    expect(
      operations.map((operation) => operation.kind),
      [
        SyncOperationKind.deletePaper,
        SyncOperationKind.deleteTodoItem,
        SyncOperationKind.upsertTodoItem,
        SyncOperationKind.upsertTodoItem,
        SyncOperationKind.upsertPaper,
      ],
    );
    expect(operations.map((operation) => operation.sequence), [1, 2, 3, 4, 5]);

    final result = applier.apply(before, operations);
    final todo = result.state.papers.firstWhere((paper) => paper.id == 'todo');

    expect(result.deviceSequences, {'device-b': 5});
    expect(result.state.papers.map((paper) => paper.id), [
      'todo',
      'new-note',
    ]);
    expect(todo.items.map((item) => item.id), ['item-1', 'item-3']);
    expect(todo.items.first.text, 'Updated item');
    expect(todo.items.first.done, true);
    expect(result.state.papers.last.content, 'Hello');
  });

  test('falls back to paper upsert when paper metadata changes', () {
    final before = AppState(
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Old title',
          content: 'Body',
        ),
      ],
    );
    final after = AppState(
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'New title',
          content: 'Body',
        ),
      ],
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-c',
      startSequence: 2,
      createdAtUtc: DateTime.utc(2026, 7, 1, 12),
    );

    expect(operations, hasLength(1));
    expect(operations.single.kind, SyncOperationKind.upsertPaper);
    expect(operations.single.sequence, 3);
    expect(
      (operations.single.payload['paper'] as Map<String, Object?>)['title'],
      'New title',
    );
  });

  test('normalizes device ids before building operations', () {
    final before = AppState(
      papers: [
        PaperData(id: 'note', type: PaperTypes.note, content: 'Before'),
      ],
    );
    final after = AppState(
      papers: [
        PaperData(id: 'note', type: PaperTypes.note, content: 'After'),
      ],
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: ' Device A ',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 13),
    );

    expect(operations, hasLength(1));
    expect(operations.single.id, 'device-a-1');
    expect(operations.single.deviceId, 'device-a');
  });

  test('trims paper and item ids before comparing local diffs', () {
    final before = AppState(
      papers: [
        PaperData(
          id: ' note ',
          type: PaperTypes.note,
          title: 'Note',
          content: 'Before',
        ),
        PaperData(
          id: ' todo ',
          type: PaperTypes.todo,
          title: 'Todo',
          items: [PaperItem(id: ' item-1 ', text: 'Before item')],
        ),
      ],
    );
    final after = AppState(
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'After',
        ),
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          title: 'Todo',
          items: [PaperItem(id: 'item-1', text: 'After item')],
        ),
      ],
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 14),
    );

    expect(
      operations.map((operation) => operation.kind),
      [
        SyncOperationKind.updateNoteContent,
        SyncOperationKind.upsertTodoItem,
      ],
    );
    expect(operations.first.payload, {
      'paperId': 'note',
      'content': 'After',
    });
    expect(operations.last.payload['paperId'], 'todo');
    expect(
      (operations.last.payload['item'] as Map<String, Object?>)['id'],
      'item-1',
    );

    final result = applier.apply(
      before,
      operations,
      deviceSequences: {'device-a': 0},
    );
    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');
    final todo = result.state.papers.firstWhere((paper) => paper.id == 'todo');

    expect(result.appliedCount, 2);
    expect(note.content, 'After');
    expect(todo.items.single.id, 'item-1');
    expect(todo.items.single.text, 'After item');
  });

  test('trims ids in generated upsert payloads', () {
    final after = AppState(
      papers: [
        PaperData(
          id: ' todo ',
          type: PaperTypes.todo,
          title: 'Todo',
          items: [PaperItem(id: ' item-1 ', text: 'New item')],
        ),
      ],
    );

    final operations = builder.build(
      before: AppState(),
      after: after,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 15),
    );

    final paper = operations.single.payload['paper'] as Map<String, Object?>;
    final items = paper['items'] as List<Object?>;

    expect(operations.single.kind, SyncOperationKind.upsertPaper);
    expect(paper['id'], 'todo');
    expect((items.single as Map<String, Object?>)['id'], 'item-1');
  });

  test('ignores id whitespace-only local diffs', () {
    final before = AppState(
      papers: [
        PaperData(
          id: ' todo ',
          type: PaperTypes.todo,
          title: 'Todo',
          items: [PaperItem(id: ' item-1 ', text: 'Same item')],
        ),
      ],
    );
    final after = AppState(
      papers: [
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          title: 'Todo',
          items: [PaperItem(id: 'item-1', text: 'Same item')],
        ),
      ],
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 16),
    );

    expect(operations, isEmpty);
  });

  test('ignores note paper diffs that only change model-normalized fields', () {
    final before = AppState(
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          textZoom: 1.5,
          noteCanvasElements: [
            NoteCanvasElement(
              id: 'block',
              type: NoteCanvasElementTypes.code,
              width: 220,
              height: 110,
              zIndex: 10,
            ),
          ],
        ),
      ],
    );
    final after = AppState(
      papers: [
        PaperData(
          id: ' note ',
          type: 'NOTE',
          title: 'Note',
          textZoom: 9,
          noteCanvasElements: [
            NoteCanvasElement(
              id: ' block ',
              type: 'TEXT',
              width: 12,
              height: 12,
              zIndex: 0,
            ),
          ],
        ),
      ],
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 17),
    );

    expect(operations, isEmpty);
  });

  test('ignores todo item diffs that only change model-normalized fields', () {
    final before = AppState(
      papers: [
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          title: 'Todo',
          items: [
            PaperItem(
              id: 'item',
              text: 'Task',
              todoColumnCount: 4,
              todoExtraColumns: ['A', 'B', 'C'],
              todoColumnWidths: [1, 1.235, 8, 1],
              reminderIntervalValue: 240,
              reminderIntervalUnit: TodoReminderIntervalUnits.hours,
            ),
          ],
        ),
      ],
    );
    final after = AppState(
      papers: [
        PaperData(
          id: ' todo ',
          type: PaperTypes.todo,
          title: 'Todo',
          items: [
            PaperItem(
              id: ' item ',
              text: 'Task',
              todoColumnCount: 9,
              todoExtraColumns: ['A', 'B', 'C', 'D'],
              todoColumnWidths: [0, 1.23456, 99],
              reminderIntervalValue: 999,
              reminderIntervalUnit: 'HOURS',
            ),
          ],
        ),
      ],
    );

    final operations = builder.build(
      before: before,
      after: after,
      deviceId: 'device-a',
      startSequence: 0,
      createdAtUtc: DateTime.utc(2026, 7, 1, 18),
    );

    expect(operations, isEmpty);
  });

  test('returns no operations for empty device ids or unchanged state', () {
    final state = AppState(
      papers: [
        PaperData(id: 'paper', type: PaperTypes.todo, title: 'Same'),
      ],
    );

    expect(
      builder.build(
        before: state,
        after: state,
        deviceId: 'device-a',
        startSequence: 0,
      ),
      isEmpty,
    );
    expect(
      builder.build(
        before: state,
        after: AppState(papers: [PaperData(id: 'paper')]),
        deviceId: '   ',
        startSequence: 0,
      ),
      isEmpty,
    );
  });

  test('rejects generated operation sequences outside the remote range', () {
    final noteBefore = AppState(
      papers: [
        PaperData(id: 'note', type: PaperTypes.note, content: 'Before'),
      ],
    );
    final noteAfter = AppState(
      papers: [
        PaperData(id: 'note', type: PaperTypes.note, content: 'After'),
      ],
    );

    expect(
      () => builder.build(
        before: noteBefore,
        after: noteAfter,
        deviceId: 'device-a',
        startSequence: maxSyncDeviceSequence,
      ),
      throwsA(isA<RangeError>()),
    );

    final multiBefore = AppState(
      papers: [
        PaperData(id: 'note', type: PaperTypes.note, content: 'Before'),
      ],
    );
    final multiAfter = AppState(
      theme: 'dark',
      papers: [
        PaperData(id: 'note', type: PaperTypes.note, content: 'After'),
      ],
    );

    expect(
      () => builder.build(
        before: multiBefore,
        after: multiAfter,
        deviceId: 'device-a',
        startSequence: maxSyncDeviceSequence - 1,
      ),
      throwsA(isA<RangeError>()),
    );
  });
}
