import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  const applier = SyncOperationApplier();

  test('upserts and deletes papers', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'Old'),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'paper-1',
              type: PaperTypes.note,
              title: 'Updated',
              content: 'Remote body',
            ).toJson(),
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'paper-2',
              type: PaperTypes.todo,
              title: 'Added',
            ).toJson(),
          },
        ),
        _operation(
          sequence: 3,
          kind: SyncOperationKind.deletePaper,
          payload: {'paperId': 'paper-2'},
        ),
      ],
    );

    expect(result.appliedCount, 3);
    expect(result.deviceSequences, {'device-a': 3});
    expect(result.state.papers, hasLength(1));
    expect(result.state.papers.single.type, PaperTypes.note);
    expect(result.state.papers.single.title, 'Updated');
    expect(result.state.papers.single.content, 'Remote body');
  });

  test('upserts and deletes todo items', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'item-1', text: 'One')],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-2', text: 'Two', done: true).toJson(),
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.deleteTodoItem,
          payload: {'paperId': 'todo', 'itemId': 'item-1'},
        ),
      ],
    );

    expect(result.state.papers.single.items, hasLength(1));
    expect(result.state.papers.single.items.single.id, 'item-2');
    expect(result.state.papers.single.items.single.done, true);
  });

  test('tombstones keep deleted papers and todo items from reappearing', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.note, title: 'Local'),
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(id: 'item-1', text: 'Delete me'),
              PaperItem(id: 'item-2', text: 'Keep me'),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.deletePaper,
          payload: {'paperId': 'paper-1'},
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 8, 59),
          payload: {
            'paper': PaperData(
              id: 'paper-1',
              type: PaperTypes.note,
              title: 'Stale remote',
            ).toJson(),
          },
        ),
        _operation(
          sequence: 3,
          kind: SyncOperationKind.deleteTodoItem,
          payload: {'paperId': 'todo', 'itemId': 'item-1'},
        ),
        _operation(
          sequence: 4,
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 0, 2),
          payload: {
            'paper': PaperData(
              id: 'todo',
              type: PaperTypes.todo,
              items: [
                PaperItem(id: 'item-1', text: 'Stale item'),
                PaperItem(id: 'item-2', text: 'Updated keep'),
              ],
            ).toJson(),
          },
        ),
      ],
    );

    expect(result.appliedCount, 4);
    expect(
      result.state.sync.deletedPaperTombstones['paper-1'],
      DateTime.utc(2026, 7, 1, 9, 0, 1).toIso8601String(),
    );
    expect(
      result.state.sync.deletedTodoItemTombstones['todo']?['item-1'],
      DateTime.utc(2026, 7, 1, 9, 0, 3).toIso8601String(),
    );
    expect(result.state.papers.map((paper) => paper.id), ['todo']);
    expect(result.state.papers.single.items.map((item) => item.id), [
      'item-2',
    ]);
    expect(result.state.papers.single.items.single.text, 'Updated keep');
  });

  test('orders ready cross-device operations by creation time', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.note, title: 'Local'),
        ],
      ),
      [
        _operation(
          deviceId: 'device-z',
          sequence: 1,
          kind: SyncOperationKind.deletePaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 10),
          payload: {'paperId': 'paper-1'},
        ),
        _operation(
          deviceId: 'device-a',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 10, 5),
          payload: {
            'paper': PaperData(
              id: 'paper-1',
              type: PaperTypes.note,
              title: 'Restored',
            ).toJson(),
          },
        ),
      ],
    );

    expect(result.appliedCount, 2);
    expect(result.deviceSequences, {'device-z': 1, 'device-a': 1});
    expect(
        result.state.sync.deletedPaperTombstones, isNot(contains('paper-1')));
    expect(result.state.papers.single.title, 'Restored');
  });

  test('newer upserts restore deleted papers and todo items', () {
    final deletedAtUtc = DateTime.utc(2026, 7, 1, 9);
    final result = applier.apply(
      AppState(
        sync: SyncSettings(
          deletedPaperTombstones: {
            'paper-1': deletedAtUtc.toIso8601String(),
            'todo': deletedAtUtc.toIso8601String(),
          },
          deletedTodoItemTombstones: {
            'todo': {
              'item-1': deletedAtUtc.toIso8601String(),
            },
          },
        ),
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'item-2', text: 'Keep me')],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          deviceId: ' Device A ',
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 5),
          payload: {
            'paper': PaperData(
              id: 'paper-1',
              type: PaperTypes.note,
              title: 'Restored',
            ).toJson(),
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 6),
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-1', text: 'Restored item').toJson(),
          },
        ),
      ],
    );

    expect(
        result.state.sync.deletedPaperTombstones, isNot(contains('paper-1')));
    expect(result.state.sync.deletedPaperTombstones, isNot(contains('todo')));
    expect(
      result.state.sync.deletedTodoItemTombstones['todo'],
      isNot(contains('item-1')),
    );
    expect(result.state.papers.map((paper) => paper.id), [
      'todo',
      'paper-1',
    ]);
    expect(result.state.papers.last.title, 'Restored');
    expect(result.state.papers.first.items.map((item) => item.id), [
      'item-2',
      'item-1',
    ]);
  });

  test('updates note content and settings', () {
    final result = applier.apply(
      AppState(
        theme: 'light',
        enableToolTips: true,
        papers: [
          PaperData(id: 'note', type: PaperTypes.note, content: 'Local'),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Remote'},
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'theme': 'dark',
              'enableToolTips': false,
            },
          },
        ),
      ],
    );

    expect(result.state.papers.single.content, 'Remote');
    expect(result.state.theme, 'dark');
    expect(result.state.enableToolTips, false);
  });

  test('trims payload ids before applying targeted operations', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'note', type: PaperTypes.note, content: 'Local'),
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'item-1', text: 'Remove me')],
          ),
          PaperData(id: 'deleted-note', type: PaperTypes.note),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': ' note ', 'content': 'Remote'},
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.deleteTodoItem,
          payload: {'paperId': ' todo ', 'itemId': ' item-1 '},
        ),
        _operation(
          sequence: 3,
          kind: SyncOperationKind.deletePaper,
          payload: {'paperId': ' deleted-note '},
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');
    final todo = result.state.papers.firstWhere((paper) => paper.id == 'todo');

    expect(result.appliedCount, 3);
    expect(note.content, 'Remote');
    expect(todo.items.map((item) => item.id), isNot(contains('item-1')));
    expect(
      result.state.papers.map((paper) => paper.id),
      isNot(contains('deleted-note')),
    );
    expect(
      result.state.sync.deletedPaperTombstones,
      contains('deleted-note'),
    );
    expect(
      result.state.sync.deletedTodoItemTombstones['todo'],
      contains('item-1'),
    );
  });

  test('trims upsert payload ids before tombstone checks', () {
    final deletedAtUtc = DateTime.utc(2026, 7, 1, 9);
    final result = applier.apply(
      AppState(
        sync: SyncSettings(
          deletedPaperTombstones: {
            'paper-1': deletedAtUtc.toIso8601String(),
          },
          deletedTodoItemTombstones: {
            'todo': {
              'item-1': deletedAtUtc.toIso8601String(),
            },
          },
        ),
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'item-2', text: 'Keep me')],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 8, 59),
          payload: {
            'paper': PaperData(
              id: ' paper-1 ',
              type: PaperTypes.note,
              title: 'Stale remote',
            ).toJson(),
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          createdAtUtc: DateTime.utc(2026, 7, 1, 8, 59),
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: ' item-1 ', text: 'Stale item').toJson(),
          },
        ),
        _operation(
          sequence: 3,
          kind: SyncOperationKind.upsertPaper,
          createdAtUtc: DateTime.utc(2026, 7, 1, 9, 1),
          payload: {
            'paper': PaperData(
              id: ' todo ',
              type: PaperTypes.todo,
              items: [
                PaperItem(id: ' item-1 ', text: 'Restored item'),
                PaperItem(id: ' item-2 ', text: 'Updated keep'),
              ],
            ).toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.single;

    expect(result.appliedCount, 3);
    expect(todo.id, 'todo');
    expect(result.state.papers.map((paper) => paper.id),
        isNot(contains('paper-1')));
    expect(todo.items.map((item) => item.id), ['item-1', 'item-2']);
    expect(todo.items.map((item) => item.text), [
      'Restored item',
      'Updated keep',
    ]);
    expect(result.state.sync.deletedPaperTombstones, contains('paper-1'));
    expect(result.state.sync.deletedTodoItemTombstones['todo'],
        isNot(contains('item-1')));
  });

  test('migrates legacy PaperTodo operation payloads', () {
    final result = applier.apply(
      AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'local-user',
            password: 'local-password',
            encryptionPassphrase: 'local-secret',
            rootPath: 'RePaperTodo',
          ),
        ),
        papers: [
          PaperData(id: 'todo-paper', type: PaperTypes.todo),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'Paper': {
              'Id': 'legacy-note',
              'Type': 'note',
              'Title': 'Legacy Note',
              'Content': '# Migrated note',
              'NoteCanvasElements': [
                {
                  'Id': 'legacy-code',
                  'Text': 'Console.WriteLine();',
                  'ZIndex': 0,
                },
              ],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'PaperId': 'todo-paper',
            'Item': {
              'Id': 'legacy-item',
              'Text': 'Migrated item',
              'Done': true,
              'TodoColumnCount': 2,
              'TodoExtraColumns': ['source'],
            },
          },
        ),
        _operation(
          sequence: 3,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'Settings': {
              'Theme': 'dark',
              'ShowTopBarNewPaperButtons': false,
              'Sync': {
                'Enabled': false,
                'Provider': SyncProviderIds.none,
                'WebDav': {
                  'Endpoint': 'https://remote.example.test/',
                  'Username': 'remote-user',
                  'Password': 'remote-password',
                  'EncryptionPassphrase': 'remote-secret',
                },
              },
            },
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere(
      (paper) => paper.id == 'legacy-note',
    );
    final todo = result.state.papers.firstWhere(
      (paper) => paper.id == 'todo-paper',
    );
    final item = todo.items.firstWhere(
      (item) => item.id == 'legacy-item',
    );

    expect(note.title, 'Legacy Note');
    expect(note.content, '# Migrated note');
    expect(note.noteCanvasElements.single.id, 'legacy-code');
    expect(note.noteCanvasElements.single.zIndex, 10);
    expect(item.text, 'Migrated item');
    expect(item.done, true);
    expect(item.todoColumnCount, 2);
    expect(item.todoExtraColumns, ['source']);
    expect(result.state.theme, 'dark');
    expect(result.state.showTopBarNewTodoButton, false);
    expect(result.state.showTopBarNewNoteButton, false);
    expect(result.state.sync.enabled, true);
    expect(result.state.sync.provider, SyncProviderIds.webDav);
    expect(result.state.sync.webDav.endpoint, 'https://dav.example.test/');
    expect(result.state.sync.webDav.username, 'local-user');
    expect(result.state.sync.webDav.password, 'local-password');
    expect(result.state.sync.webDav.encryptionPassphrase, 'local-secret');
  });

  test('settings operations cannot replace local sync settings', () {
    final deletedAtUtc = DateTime.utc(2026, 7, 1, 9);
    final result = applier.apply(
      AppState(
        theme: 'light',
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'local-user',
            password: 'local-password',
            encryptionPassphrase: 'local-sync-secret',
            rootPath: 'RePaperTodo',
            autoSyncIntervalMinutes: 60,
            requestTimeoutSeconds: 45,
          ),
          operationDeviceSequences: {'device-local': 7},
          deletedPaperTombstones: {
            'paper-1': deletedAtUtc.toIso8601String(),
          },
        ),
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'theme': 'dark',
              'sync': {
                'enabled': false,
                'provider': SyncProviderIds.none,
                'operationDeviceSequences': {'remote-device': 99},
                'deletedPaperTombstones': {
                  'paper-2': DateTime.utc(2026, 7, 1, 10).toIso8601String(),
                },
                'webDav': {
                  'endpoint': 'https://evil.example.test/',
                  'username': 'remote-user',
                  'password': 'remote-password',
                  'encryptionPassphrase': 'remote-sync-secret',
                  'rootPath': 'RemoteRoot',
                  'autoSyncIntervalMinutes': 5,
                  'requestTimeoutSeconds': 300,
                },
              },
            },
          },
        ),
      ],
    );

    expect(result.state.theme, 'dark');
    expect(result.state.sync.enabled, true);
    expect(result.state.sync.provider, SyncProviderIds.webDav);
    expect(result.state.sync.webDav.endpoint, 'https://dav.example.test/');
    expect(result.state.sync.webDav.username, 'local-user');
    expect(result.state.sync.webDav.password, 'local-password');
    expect(
      result.state.sync.webDav.encryptionPassphrase,
      'local-sync-secret',
    );
    expect(result.state.sync.webDav.rootPath, 'RePaperTodo');
    expect(result.state.sync.webDav.autoSyncIntervalMinutes, 60);
    expect(result.state.sync.webDav.requestTimeoutSeconds, 45);
    expect(result.state.sync.operationDeviceSequences, {'device-local': 7});
    expect(result.state.sync.deletedPaperTombstones, {
      'paper-1': deletedAtUtc.toIso8601String(),
    });
  });

  test('settings operations keep incomplete local WebDAV root paths', () {
    final result = applier.apply(
      AppState(
        theme: 'light',
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'local-user',
            password: 'local-password',
            encryptionPassphrase: 'local-sync-secret',
            rootPath: '',
          ),
        ),
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'theme': 'dark',
              'sync': {
                'enabled': true,
                'provider': SyncProviderIds.webDav,
                'webDav': {
                  'endpoint': 'https://remote.example.test/',
                  'username': 'remote-user',
                  'password': 'remote-password',
                  'encryptionPassphrase': 'remote-sync-secret',
                  'rootPath': 'RemoteRoot',
                },
              },
            },
          },
        ),
      ],
    );

    expect(result.state.theme, 'dark');
    expect(result.state.sync.enabled, true);
    expect(result.state.sync.provider, SyncProviderIds.webDav);
    expect(result.state.sync.webDav.endpoint, 'https://dav.example.test/');
    expect(result.state.sync.webDav.username, 'local-user');
    expect(result.state.sync.webDav.password, 'local-password');
    expect(result.state.sync.webDav.encryptionPassphrase, 'local-sync-secret');
    expect(result.state.sync.webDav.rootPath, isEmpty);
    expect(result.state.sync.webDav.isSecurelyConfigured, false);
  });

  test('skips snapshot markers and already applied sequences', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'Local'),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'paper-1',
              type: PaperTypes.todo,
              title: 'Stale',
            ).toJson(),
          },
        ),
        _operation(
          sequence: 2,
          deviceId: ' Device A ',
          kind: SyncOperationKind.stateSnapshot,
          payload: {'snapshotPath': 'repapertodo/snapshots/snapshot.json'},
        ),
        _operation(
          sequence: 3,
          deviceId: ' Device A ',
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'paper-1',
              type: PaperTypes.todo,
              title: 'Fresh',
            ).toJson(),
          },
        ),
      ],
      deviceSequences: {' Device A ': 1},
    );

    expect(result.appliedCount, 2);
    expect(result.deviceSequences, {'device-a': 3});
    expect(result.state.papers.single.title, 'Fresh');
  });

  test('skips operations outside the remote sequence range', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'Local'),
        ],
      ),
      [
        _operation(
          sequence: maxSyncDeviceSequence + 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'paper-1',
              type: PaperTypes.todo,
              title: 'Too far',
            ).toJson(),
          },
        ),
      ],
      deviceSequences: {'device-a': maxSyncDeviceSequence},
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, {'device-a': maxSyncDeviceSequence});
    expect(result.state.papers.single.title, 'Local');
  });

  test('applies valid operations before skipping out-of-range sequences', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'Local'),
        ],
      ),
      [
        _operation(
          sequence: maxSyncDeviceSequence,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'paper-1',
              type: PaperTypes.todo,
              title: 'Accepted max',
            ).toJson(),
          },
        ),
        _operation(
          sequence: maxSyncDeviceSequence + 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'paper-1',
              type: PaperTypes.todo,
              title: 'Too far',
            ).toJson(),
          },
        ),
      ],
      deviceSequences: {'device-a': maxSyncDeviceSequence - 1},
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': maxSyncDeviceSequence});
    expect(result.state.papers.single.title, 'Accepted max');
  });

  test('stops applying a device after a sequence gap', () {
    final result = applier.apply(
      AppState(),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-a-first',
              type: PaperTypes.note,
              title: 'Device A first',
            ).toJson(),
          },
        ),
        _operation(
          sequence: 3,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-a-third',
              type: PaperTypes.note,
              title: 'Device A third',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-first',
              type: PaperTypes.note,
              title: 'Device B first',
            ).toJson(),
          },
        ),
      ],
    );

    expect(result.appliedCount, 2);
    expect(result.deviceSequences, {'device-a': 1, 'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'device-a-first',
      'device-b-first',
    ]);
  });

  test('applies matching duplicate operation sequences once', () {
    final operation = _operation(
      sequence: 1,
      kind: SyncOperationKind.upsertPaper,
      payload: {
        'paper': PaperData(
          id: 'paper-1',
          type: PaperTypes.note,
          title: 'Remote',
        ).toJson(),
      },
    );
    final result = applier.apply(
      AppState(),
      [
        operation,
        SyncOperation.fromJson(operation.toJson()),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'paper-2',
              type: PaperTypes.note,
              title: 'Next',
            ).toJson(),
          },
        ),
      ],
    );

    expect(result.appliedCount, 2);
    expect(result.deviceSequences, {'device-a': 2});
    expect(result.state.papers.map((paper) => paper.id), [
      'paper-1',
      'paper-2',
    ]);
  });

  test('blocks conflicting duplicate operation sequences per device', () {
    final result = applier.apply(
      AppState(),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-a-first',
              type: PaperTypes.note,
              title: 'First',
            ).toJson(),
          },
        ),
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-a-conflict',
              type: PaperTypes.note,
              title: 'Conflict',
            ).toJson(),
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-a-next',
              type: PaperTypes.note,
              title: 'Blocked',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-first',
              type: PaperTypes.note,
              title: 'Other device',
            ).toJson(),
          },
        ),
      ],
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), ['device-b-first']);
  });
}

SyncOperation _operation({
  required int sequence,
  required SyncOperationKind kind,
  required Map<String, Object?> payload,
  String deviceId = 'device-a',
  DateTime? createdAtUtc,
}) {
  return SyncOperation(
    id: '$deviceId-$sequence',
    deviceId: deviceId,
    sequence: sequence,
    kind: kind,
    createdAtUtc: createdAtUtc ?? DateTime.utc(2026, 7, 1, 9, 0, sequence),
    payload: payload,
  );
}
