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

  test('blocks control-character payload ids without tombstones', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'note', type: PaperTypes.note, content: 'Local'),
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'item-1', text: 'Keep me')],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.deletePaper,
          payload: {'paperId': 'note\u0000bad'},
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Blocked'},
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-2', text: 'Other device').toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');
    final todo = result.state.papers.firstWhere((paper) => paper.id == 'todo');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(note.content, 'Local');
    expect(todo.items.map((item) => item.id), ['item-1', 'item-2']);
    expect(result.state.sync.deletedPaperTombstones.keys, isEmpty);
    expect(result.state.sync.deletedTodoItemTombstones.keys, isEmpty);
  });

  test('blocks duplicate nested upsert ids without generated ids', () {
    final result = applier.apply(
      AppState(),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'bad-todo',
              'type': PaperTypes.todo,
              'items': [
                {'id': 'item-1', 'text': 'First'},
                {'id': ' item-1 ', 'text': 'Duplicate'},
              ],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-a-next',
              type: PaperTypes.note,
              title: 'Blocked after duplicate ids',
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

  test('blocks malformed nested upsert lists without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'item-1', text: 'Keep local item')],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'todo',
              'type': PaperTypes.todo,
              'items': [
                {'id': 'item-2', 'text': 'Valid remote item'},
                'not-a-json-object',
              ],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-3', text: 'Blocked').toJson(),
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

    final todo = result.state.papers.firstWhere((paper) => paper.id == 'todo');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(todo.items.map((item) => item.id), ['item-1']);
    expect(result.state.papers.map((paper) => paper.id), [
      'todo',
      'device-b-first',
    ]);
  });

  test('blocks malformed todo item column payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: 'item-1',
                text: 'Keep local item',
                todoColumnCount: 2,
                todoExtraColumns: ['Status'],
                todoColumnWidths: [2, 1],
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'todo',
              'type': PaperTypes.todo,
              'items': [
                {
                  'id': 'item-1',
                  'text': 'Would overwrite local columns',
                  'todoExtraColumns': 'not-a-list',
                },
              ],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': {
              'id': 'item-2',
              'text': 'Blocked behind malformed paper upsert',
              'todoColumnWidths': [1, '2'],
            },
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-3', text: 'Other device').toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.single;
    final localItem = todo.items.firstWhere((item) => item.id == 'item-1');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(todo.items.map((item) => item.id), ['item-1', 'item-3']);
    expect(localItem.text, 'Keep local item');
    expect(localItem.todoColumnCount, 2);
    expect(localItem.todoExtraColumns, ['Status']);
    expect(localItem.todoColumnWidths, [2, 1]);
  });

  test('blocks non-positive todo column counts without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: 'item-1',
                text: 'Keep local columns',
                todoColumnCount: 2,
                todoExtraColumns: ['Status'],
                todoColumnWidths: [2, 1],
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': {
              'id': 'item-1',
              'text': 'Would collapse columns',
              'todoColumnCount': 0,
              'todoExtraColumns': ['Lost'],
              'todoColumnWidths': [1],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(
              id: 'item-2',
              text: 'Blocked behind bad column count',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-3', text: 'Other device').toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.single;
    final localItem = todo.items.firstWhere((item) => item.id == 'item-1');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(todo.items.map((item) => item.id), ['item-1', 'item-3']);
    expect(localItem.text, 'Keep local columns');
    expect(localItem.todoColumnCount, 2);
    expect(localItem.todoExtraColumns, ['Status']);
    expect(localItem.todoColumnWidths, [2, 1]);
  });

  test('blocks negative todo column widths without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: 'item-1',
                text: 'Keep local column widths',
                todoColumnCount: 2,
                todoExtraColumns: ['Status'],
                todoColumnWidths: [2, 1],
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': {
              'id': 'item-1',
              'text': 'Would reset column width',
              'todoColumnWidths': [-1],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(
              id: 'item-2',
              text: 'Blocked behind bad column width',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-3', text: 'Other device').toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.single;
    final localItem = todo.items.firstWhere((item) => item.id == 'item-1');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(todo.items.map((item) => item.id), ['item-1', 'item-3']);
    expect(localItem.text, 'Keep local column widths');
    expect(localItem.todoColumnCount, 2);
    expect(localItem.todoExtraColumns, ['Status']);
    expect(localItem.todoColumnWidths, [2, 1]);
  });

  test('blocks incomplete todo column list payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: 'item-1',
                text: 'Keep local column shape',
                todoColumnCount: 2,
                todoExtraColumns: ['Status'],
                todoColumnWidths: [2, 1],
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': {
              'id': 'item-1',
              'text': 'Would drop columns by defaulting count',
              'todoExtraColumns': ['Lost'],
              'todoColumnWidths': [1, 1],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(
              id: 'item-2',
              text: 'Blocked behind incomplete column lists',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-3', text: 'Other device').toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.single;
    final localItem = todo.items.firstWhere((item) => item.id == 'item-1');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(todo.items.map((item) => item.id), ['item-1', 'item-3']);
    expect(localItem.text, 'Keep local column shape');
    expect(localItem.todoColumnCount, 2);
    expect(localItem.todoExtraColumns, ['Status']);
    expect(localItem.todoColumnWidths, [2, 1]);
  });

  test('blocks malformed todo item scalar payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: 'item-1',
                text: 'Keep local item',
                done: true,
                todoColumnCount: 2,
                todoExtraColumns: ['Status'],
                todoColumnWidths: [2, 1],
                dueAtLocal: '2026-07-03T08:30:00',
                reminderIntervalValue: 30,
                reminderIntervalUnit: TodoReminderIntervalUnits.hours,
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': {
              'id': 'item-1',
              'text': {'not': 'a string'},
              'done': 'false',
              'order': 1.5,
              'todoColumnCount': '1',
              'dueAtLocal': ['2026-07-04T09:00:00'],
              'reminderIntervalValue': 5.5,
              'reminderIntervalUnit': 7,
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(
              id: 'item-2',
              text: 'Blocked behind malformed scalar payload',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-3', text: 'Other device').toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.single;
    final localItem = todo.items.firstWhere((item) => item.id == 'item-1');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(todo.items.map((item) => item.id), ['item-1', 'item-3']);
    expect(localItem.text, 'Keep local item');
    expect(localItem.done, true);
    expect(localItem.todoColumnCount, 2);
    expect(localItem.todoExtraColumns, ['Status']);
    expect(localItem.todoColumnWidths, [2, 1]);
    expect(localItem.dueAtLocal, '2026-07-03T08:30:00');
    expect(localItem.reminderIntervalValue, 30);
    expect(localItem.reminderIntervalUnit, TodoReminderIntervalUnits.hours);
  });

  test('blocks blank linked note ids without unlinking items', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: 'item-1',
                text: 'Keep linked item',
                linkedNoteId: 'note',
              ),
            ],
          ),
          PaperData(id: 'note', type: PaperTypes.note, title: 'Linked note'),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': {
              'id': 'item-1',
              'text': 'Would unlink item',
              'linkedNoteId': '   ',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(
              id: 'item-2',
              text: 'Blocked behind blank linked note ID',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-3', text: 'Other device').toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.firstWhere((paper) => paper.id == 'todo');
    final localItem = todo.items.firstWhere((item) => item.id == 'item-1');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(todo.items.map((item) => item.id), ['item-1', 'item-3']);
    expect(localItem.text, 'Keep linked item');
    expect(localItem.linkedNoteId, 'note');
  });

  test('blocks unparseable todo due dates without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: 'item-1',
                text: 'Keep local item',
                dueAtLocal: '2026-07-03T08:30:00',
                reminderIntervalValue: 30,
                reminderIntervalUnit: TodoReminderIntervalUnits.hours,
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': {
              'id': 'item-1',
              'text': 'Would clear date',
              'dueAtLocal': 'not a date',
              'reminderIntervalValue': 30,
              'reminderIntervalUnit': TodoReminderIntervalUnits.minutes,
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(
              id: 'item-2',
              text: 'Blocked behind bad due date',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-3', text: 'Other device').toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.single;
    final localItem = todo.items.firstWhere((item) => item.id == 'item-1');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(todo.items.map((item) => item.id), ['item-1', 'item-3']);
    expect(localItem.text, 'Keep local item');
    expect(localItem.dueAtLocal, '2026-07-03T08:30:00');
    expect(localItem.reminderIntervalValue, 30);
    expect(localItem.reminderIntervalUnit, TodoReminderIntervalUnits.hours);
  });

  test('blocks unsupported todo reminder units without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: 'item-1',
                text: 'Keep local item',
                dueAtLocal: '2026-07-03T08:30:00',
                reminderIntervalValue: 30,
                reminderIntervalUnit: TodoReminderIntervalUnits.hours,
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': {
              'id': 'item-1',
              'text': 'Would default unit',
              'dueAtLocal': '2026-07-04T09:00:00',
              'reminderIntervalValue': 2,
              'reminderIntervalUnit': 'days',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(
              id: 'item-2',
              text: 'Blocked behind bad reminder unit',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-3', text: 'Other device').toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.single;
    final localItem = todo.items.firstWhere((item) => item.id == 'item-1');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(todo.items.map((item) => item.id), ['item-1', 'item-3']);
    expect(localItem.text, 'Keep local item');
    expect(localItem.dueAtLocal, '2026-07-03T08:30:00');
    expect(localItem.reminderIntervalValue, 30);
    expect(localItem.reminderIntervalUnit, TodoReminderIntervalUnits.hours);
  });

  test('blocks malformed note canvas payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'block-1',
                text: 'Keep local script',
                x: 48,
                y: 64,
                width: 300,
                height: 140,
                zIndex: 20,
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'type': PaperTypes.note,
              'title': 'Would overwrite canvas',
              'noteCanvasElements': [
                {
                  'id': 'block-1',
                  'text': {'not': 'string'},
                  'x': '48',
                  'zIndex': 1.5,
                },
              ],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Blocked behind canvas'},
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other device',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');
    final block = note.noteCanvasElements.single;

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'device-b-note',
    ]);
    expect(note.title, 'Local');
    expect(block.id, 'block-1');
    expect(block.text, 'Keep local script');
    expect(block.x, 48);
    expect(block.y, 64);
    expect(block.width, 300);
    expect(block.height, 140);
    expect(block.zIndex, 20);
  });

  test('blocks unsupported note canvas types without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'block-1',
                type: NoteCanvasElementTypes.code,
                text: 'Keep local script',
                x: 48,
                y: 64,
                width: 300,
                height: 140,
                zIndex: 20,
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'type': PaperTypes.note,
              'title': 'Would normalize type',
              'noteCanvasElements': [
                {
                  'id': 'block-1',
                  'type': 'diagram',
                  'text': 'Would become code',
                  'x': 48,
                  'y': 64,
                  'width': 300,
                  'height': 140,
                  'zIndex': 20,
                },
              ],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {
            'paperId': 'note',
            'content': 'Blocked behind bad canvas type',
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other device',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');
    final block = note.noteCanvasElements.single;

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'device-b-note',
    ]);
    expect(note.title, 'Local');
    expect(note.content, isEmpty);
    expect(block.type, NoteCanvasElementTypes.code);
    expect(block.text, 'Keep local script');
    expect(block.x, 48);
    expect(block.y, 64);
    expect(block.width, 300);
    expect(block.height, 140);
    expect(block.zIndex, 20);
  });

  test('blocks clamped note canvas geometry payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'block-1',
                text: 'Keep local geometry',
                x: 48,
                y: 64,
                width: 300,
                height: 140,
                zIndex: 20,
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'type': PaperTypes.note,
              'title': 'Would clamp canvas',
              'noteCanvasElements': [
                {
                  'id': 'block-1',
                  'text': 'Remote geometry',
                  'x': -2000.1,
                  'y': 8000.1,
                  'width': 12,
                  'height': 1600.1,
                  'zIndex': 20,
                },
              ],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Blocked behind geometry'},
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other device',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');
    final block = note.noteCanvasElements.single;

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'device-b-note',
    ]);
    expect(note.title, 'Local');
    expect(block.id, 'block-1');
    expect(block.text, 'Keep local geometry');
    expect(block.x, 48);
    expect(block.y, 64);
    expect(block.width, 300);
    expect(block.height, 140);
    expect(block.zIndex, 20);
  });

  test('blocks negative note canvas layer payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'block-1',
                text: 'Keep local layer',
                x: 48,
                y: 64,
                width: 300,
                height: 140,
                zIndex: 20,
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'type': PaperTypes.note,
              'title': 'Would rewrite layer',
              'noteCanvasElements': [
                {
                  'id': 'block-1',
                  'text': 'Remote layer',
                  'x': 48,
                  'y': 64,
                  'width': 300,
                  'height': 140,
                  'zIndex': -1,
                },
              ],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Blocked behind layer'},
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other device',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');
    final block = note.noteCanvasElements.single;

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'device-b-note',
    ]);
    expect(note.title, 'Local');
    expect(block.id, 'block-1');
    expect(block.text, 'Keep local layer');
    expect(block.zIndex, 20);
  });

  test('blocks malformed paper top-level payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local',
            content: 'Keep local content',
            x: 48,
            y: 64,
            width: 320,
            height: 240,
            isVisible: true,
            alwaysOnTop: true,
            textZoom: 1.2,
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'type': 'memo',
              'title': {'not': 'a string'},
              'content': ['not', 'a string'],
              'x': '48',
              'isVisible': 'false',
              'textZoom': '1.0',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'note',
              type: PaperTypes.note,
              title: 'Bad',
              content: 'Blocked behind malformed paper',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'device-b-note',
    ]);
    expect(note.title, 'Local');
    expect(note.content, 'Keep local content');
    expect(note.x, 48);
    expect(note.y, 64);
    expect(note.width, 320);
    expect(note.height, 240);
    expect(note.isVisible, true);
    expect(note.alwaysOnTop, true);
    expect(note.textZoom, 1.2);
  });

  test('blocks paper upserts without type instead of defaulting to todo', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local note',
            content: 'Keep local note content',
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'title': 'Would default to todo',
              'content': 'Would overwrite note',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'next-note',
              type: PaperTypes.note,
              title: 'Blocked behind missing type',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'device-b-note',
    ]);
    expect(note.type, PaperTypes.note);
    expect(note.content, 'Keep local note content');
  });

  test('blocks cross-type paper collection payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local note',
            content: 'Keep local note content',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'block-1',
                type: 'text',
                text: 'Keep canvas text',
                zIndex: 20,
              ),
            ],
          ),
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'item-1', text: 'Keep todo item')],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'type': PaperTypes.note,
              'title': 'Would hide todo content',
              'items': [
                {'id': 'remote-item', 'text': 'Wrong collection'},
              ],
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'todo',
              type: PaperTypes.todo,
              title: 'Blocked behind cross-type collection',
              items: [PaperItem(id: 'remote-todo', text: 'Blocked')],
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');
    final todo = result.state.papers.firstWhere((paper) => paper.id == 'todo');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'todo',
      'device-b-note',
    ]);
    expect(note.type, PaperTypes.note);
    expect(note.content, 'Keep local note content');
    expect(note.items, isEmpty);
    expect(note.noteCanvasElements.single.text, 'Keep canvas text');
    expect(todo.items.single.text, 'Keep todo item');
  });

  test('blocks paper titles that would be cleaned during merge', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local',
            content: 'Keep local content',
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'type': PaperTypes.note,
              'title': ' Remote\u0000note ',
              'content': 'Would overwrite note',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Blocked behind bad title'},
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(note.title, 'Local');
    expect(note.content, 'Keep local content');
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'device-b-note',
    ]);
  });

  test('blocks fallback paper geometry payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local',
            width: 420,
            height: 260,
            textZoom: 1.2,
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'type': PaperTypes.note,
              'title': 'Remote',
              'width': 12,
              'height': 12,
              'textZoom': 0,
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'note',
              type: PaperTypes.note,
              title: 'Blocked behind fallback geometry',
              width: 220,
              height: 160,
              textZoom: 1,
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'device-b-note',
    ]);
    expect(note.title, 'Local');
    expect(note.width, 420);
    expect(note.height, 260);
    expect(note.textZoom, 1.2);
  });

  test('blocks malformed paper capsule payloads without data loss', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Local',
            capsuleSide: DeepCapsuleSides.left,
            capsuleMonitorDeviceName: 'Primary',
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': {
              'id': 'note',
              'type': PaperTypes.note,
              'title': 'Remote',
              'capsuleSide': 'center',
              'capsuleMonitorDeviceName': 'Primary\u0000Monitor',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'note',
              type: PaperTypes.note,
              title: 'Blocked behind malformed capsule payload',
              capsuleSide: DeepCapsuleSides.right,
              capsuleMonitorDeviceName: 'Secondary',
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-b-note',
              type: PaperTypes.note,
              title: 'Other',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-b': 1});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'device-b-note',
    ]);
    expect(note.title, 'Local');
    expect(note.capsuleSide, DeepCapsuleSides.left);
    expect(note.capsuleMonitorDeviceName, 'Primary');
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

  test('settings operations cannot replace local sync or startup settings', () {
    final deletedAtUtc = DateTime.utc(2026, 7, 1, 9);
    final result = applier.apply(
      AppState(
        theme: 'light',
        startAtLogin: true,
        extra: {'localExtensionSetting': 'keep-local'},
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
              'futureRemoteOnlySetting': 'ignore-remote',
              'startAtLogin': false,
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
    expect(result.state.startAtLogin, true);
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
    expect(result.state.extra, {'localExtensionSetting': 'keep-local'});
  });

  test('settings operations with only unknown fields block device progress',
      () {
    final result = applier.apply(
      AppState(
        theme: 'light',
        extra: {'localExtensionSetting': 'keep-local'},
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'futureRemoteOnlySetting': 'ignore-remote',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'theme': 'dark'},
          },
        ),
      ],
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.state.theme, 'light');
    expect(result.state.extra, {'localExtensionSetting': 'keep-local'});
  });

  test('settings operations with only malformed retired fields block progress',
      () {
    final result = applier.apply(
      AppState(
        theme: 'light',
        showTopBarNewTodoButton: true,
        showTopBarNewNoteButton: true,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'ShowTopBarNewPaperButtons': 'false',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'theme': 'dark'},
          },
        ),
      ],
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.state.theme, 'light');
    expect(result.state.showTopBarNewTodoButton, true);
    expect(result.state.showTopBarNewNoteButton, true);
  });

  test('settings operations apply parsed boolean strings', () {
    final result = applier.apply(
      AppState(
        enableToolTips: true,
        hideScriptRunWindow: true,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'enableToolTips': 'false',
              'hideScriptRunWindow': 'false',
            },
          },
        ),
      ],
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.enableToolTips, false);
    expect(result.state.hideScriptRunWindow, false);
  });

  test('settings operations with only invalid boolean strings block progress',
      () {
    final result = applier.apply(
      AppState(
        enableToolTips: false,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'enableToolTips': 'maybe'},
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'theme': 'dark'},
          },
        ),
      ],
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.state.enableToolTips, false);
    expect(result.state.theme, 'system');
  });

  test('settings operations apply parsed numeric strings', () {
    final result = applier.apply(
      AppState(
        zoom: 1,
        todoLineSpacing: 1,
        todoReminderIntervalValue: 10,
        maxTitleLength: 6,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'zoom': '9',
              'todoLineSpacing': '1.234',
              'todoReminderIntervalValue': '15',
              'maxTitleLength': '999',
            },
          },
        ),
      ],
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.zoom, 1.5);
    expect(result.state.todoLineSpacing, 1.23);
    expect(result.state.todoReminderIntervalValue, 15);
    expect(result.state.maxTitleLength, 20);
  });

  test('settings operations with only invalid numeric strings block progress',
      () {
    final result = applier.apply(
      AppState(
        theme: 'light',
        zoom: 1.25,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'zoom': 'far'},
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'theme': 'dark'},
          },
        ),
      ],
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.state.theme, 'light');
    expect(result.state.zoom, 1.25);
  });

  test('settings operations with only invalid double strings block progress',
      () {
    final result = applier.apply(
      AppState(
        theme: 'light',
        zoom: 1.25,
        todoLineSpacing: 1.4,
        noteLineSpacing: 1.6,
        useCapsuleMode: true,
        useDeepCapsuleMode: true,
        useCapsuleCollapseAll: true,
        deepCapsuleStartTopMargin: 48,
        deepCapsuleQueueStartTopMargins: {'|left': 32.0},
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'zoom': '+1',
              'todoLineSpacing': ' 1.2 ',
              'noteLineSpacing': '1e0',
              'deepCapsuleStartTopMargin': '-4',
              'deepCapsuleQueueStartTopMargins': {
                'left': '+16',
              },
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'theme': 'dark'},
          },
        ),
      ],
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.state.theme, 'light');
    expect(result.state.zoom, 1.25);
    expect(result.state.todoLineSpacing, 1.4);
    expect(result.state.noteLineSpacing, 1.6);
    expect(result.state.deepCapsuleStartTopMargin, 48);
    expect(result.state.deepCapsuleQueueStartTopMargins, {'|left': 32.0});
  });

  test('settings operations with only fractional integer values block progress',
      () {
    final result = applier.apply(
      AppState(
        theme: 'light',
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 5,
        maxTitleLength: 6,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'todoReminderIntervalValue': 15.0,
              'todoReminderBubbleDurationSeconds': 5.5,
              'maxTitleLength': 6.2,
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'theme': 'dark'},
          },
        ),
      ],
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.state.theme, 'light');
    expect(result.state.todoReminderIntervalValue, 10);
    expect(result.state.todoReminderBubbleDurationSeconds, 5);
    expect(result.state.maxTitleLength, 6);
  });

  test('settings operations with only invalid integer strings block progress',
      () {
    final result = applier.apply(
      AppState(
        theme: 'light',
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 5,
        maxTitleLength: 6,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'todoReminderIntervalValue': '+15',
              'todoReminderBubbleDurationSeconds': ' 5 ',
              'maxTitleLength': '6.0',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'theme': 'dark'},
          },
        ),
      ],
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.state.theme, 'light');
    expect(result.state.todoReminderIntervalValue, 10);
    expect(result.state.todoReminderBubbleDurationSeconds, 5);
    expect(result.state.maxTitleLength, 6);
  });

  test('settings operations with only invalid enum strings block progress', () {
    final result = applier.apply(
      AppState(
        theme: 'light',
        markdownRenderMode: MarkdownRenderModes.basic,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'theme': 'mystery',
              'markdownRenderMode': 'rich',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {'theme': 'dark'},
          },
        ),
      ],
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, isEmpty);
    expect(result.state.theme, 'light');
    expect(result.state.markdownRenderMode, MarkdownRenderModes.basic);
  });

  test('settings operations apply canonical string and queue-map values', () {
    final longHotKey = 'Ctrl+Alt+${List.filled(80, 'A').join()}';
    final result = applier.apply(
      AppState(
        useCapsuleMode: true,
        useDeepCapsuleMode: true,
        useCapsuleCollapseAll: true,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'theme': ' DARK ',
              'colorScheme': ' FOREST ',
              'customThemeColorHex': '336699',
              'markdownRenderMode': 'BASIC',
              'todoVisualSize': 'EXTRALARGE',
              'uiFontPreset': 'MONO',
              'systemFontFamilyName': ' \u0000Paper Font\u007F ',
              'externalMarkdownExtension': '*.MD',
              'todoDueYearDisplayMode': 'FULL',
              'todoReminderIntervalUnit': 'HOURS',
              'todoReminderScope': 'NEAREST',
              'pinnedTodoHotKey': ' Ctrl+\nAlt+\u007FT ',
              'pinnedNoteHotKey': '$longHotKey\n',
              'fullscreenTopmostMode': 'STAYONTOP',
              'deepCapsuleSide': 'LEFT',
              'deepCapsuleMonitorDeviceName': ' Primary ',
              'capsuleCollapseAllActiveQueues': {
                'left': 'true',
                ' Primary | RIGHT ': true,
                'Ghost|left': 'false',
              },
              'deepCapsuleQueueStartTopMargins': {
                'left': '16.25',
                ' Primary | RIGHT ': 2,
              },
            },
          },
        ),
      ],
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.theme, 'dark');
    expect(result.state.colorScheme, ColorSchemes.forest);
    expect(result.state.customThemeColorHex, '#336699');
    expect(result.state.markdownRenderMode, MarkdownRenderModes.basic);
    expect(result.state.todoVisualSize, TodoVisualSizes.extraLarge);
    expect(result.state.uiFontPreset, UiFontPresets.mono);
    expect(result.state.systemFontFamilyName, 'Paper Font');
    expect(result.state.externalMarkdownExtension, '.md');
    expect(result.state.todoDueYearDisplayMode, TodoDueYearDisplayModes.full);
    expect(
        result.state.todoReminderIntervalUnit, TodoReminderIntervalUnits.hours);
    expect(result.state.todoReminderScope, TodoReminderScopes.nearest);
    expect(result.state.pinnedTodoHotKey, 'Ctrl+Alt+T');
    expect(result.state.pinnedNoteHotKey, longHotKey.substring(0, 64));
    expect(
        result.state.fullscreenTopmostMode, FullscreenTopmostModes.stayOnTop);
    expect(result.state.deepCapsuleSide, DeepCapsuleSides.right);
    expect(result.state.deepCapsuleMonitorDeviceName, isEmpty);
    expect(result.state.capsuleCollapseAllActiveQueues, isEmpty);
    expect(result.state.deepCapsuleQueueStartTopMargins, isEmpty);
  });

  test('settings operations apply canonical queue alias precedence', () {
    final result = applier.apply(
      AppState(
        useCapsuleMode: true,
        useDeepCapsuleMode: true,
        useCapsuleCollapseAll: true,
        capsuleCollapseAllActive: true,
        capsuleCollapseAllActiveQueues: {'|left': true},
        deepCapsuleQueueStartTopMargins: {'|left': 32},
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'useCapsuleMode': true,
              'useDeepCapsuleMode': true,
              'useCapsuleCollapseAll': true,
              'capsuleCollapseAllActive': false,
              'capsuleCollapseAllActiveQueues': {
                'left': true,
                '|left': false,
                'Primary | right ': false,
                'Primary|right': true,
              },
              'deepCapsuleQueueStartTopMargins': {
                'right': '32.5',
                '|right': 4,
                'Primary | left ': 12,
                'Primary|left': 12000,
              },
            },
          },
        ),
      ],
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.capsuleCollapseAllActive, true);
    expect(result.state.capsuleCollapseAllActiveQueues, {'|left': true});
    expect(result.state.deepCapsuleQueueStartTopMargins, {'|left': 32.0});
  });

  test('settings operations disabling capsule mode restore collapsed papers',
      () {
    final result = applier.apply(
      AppState(
        useCapsuleMode: true,
        useDeepCapsuleMode: true,
        useCapsuleCollapseAll: true,
        capsuleCollapseAllActive: true,
        capsuleCollapseAllActiveQueues: {'Primary|left': true},
        deepCapsuleStartTopMargin: 96,
        deepCapsuleQueueStartTopMargins: {'Primary|left': 96},
        papers: [
          PaperData(
            id: 'capsule-paper',
            type: PaperTypes.todo,
            title: 'Capsule',
            isVisible: true,
            isCollapsed: true,
            capsuleSide: DeepCapsuleSides.left,
            capsuleMonitorDeviceName: 'Primary',
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'useCapsuleMode': false,
            },
          },
        ),
      ],
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.useCapsuleMode, true);
    expect(result.state.useDeepCapsuleMode, true);
    expect(result.state.useCapsuleCollapseAll, true);
    expect(result.state.capsuleCollapseAllActive, true);
    expect(result.state.capsuleCollapseAllActiveQueues, {'Primary|left': true});
    expect(
        result.state.deepCapsuleQueueStartTopMargins, {'Primary|left': 96.0});
    expect(result.state.papers.single.isCollapsed, true);
  });

  test('settings operations hide linked notes from capsules like PaperTodo',
      () {
    final result = applier.apply(
      AppState(
        enableTodoNoteLinks: true,
        hideLinkedNotesFromCapsules: false,
        papers: [
          PaperData(
            id: 'todo-paper',
            type: PaperTypes.todo,
            title: 'Todo',
            items: [
              PaperItem(
                  id: 'todo-item',
                  text: 'Open note',
                  linkedNoteId: 'note-paper'),
            ],
          ),
          PaperData(
            id: 'note-paper',
            type: PaperTypes.note,
            title: 'Note',
            isVisible: true,
            isCollapsed: true,
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'hideLinkedNotesFromCapsules': true,
            },
          },
        ),
      ],
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.hideLinkedNotesFromCapsules, true);
    expect(result.state.papers.singleWhere((paper) => paper.isNote).isCollapsed,
        false);
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

  test('settings operations apply legacy PaperTodo keys with current semantics',
      () {
    final result = applier.apply(
      AppState(
        showTopBarNewTodoButton: true,
        showTopBarNewNoteButton: true,
        hideDeepCapsulesWhenCovered: true,
        hideDeepCapsulesWhenFullscreen: true,
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'ShowTopBarNewPaperButtons': false,
              'HideDeepCapsulesWhenFullscreen': false,
            },
          },
        ),
      ],
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.showTopBarNewTodoButton, false);
    expect(result.state.showTopBarNewNoteButton, false);
    expect(result.state.hideDeepCapsulesWhenCovered, true);
    expect(result.state.hideDeepCapsulesWhenFullscreen, true);
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

  test('blocks malformed targeted operations without advancing sequence', () {
    final result = applier.apply(
      AppState(),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': <Object?, Object?>{1: 'not-json-object'},
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

  test('blocks malformed snapshot markers without advancing sequence', () {
    final result = applier.apply(
      AppState(),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.stateSnapshot,
          payload: const {},
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-a-next',
              type: PaperTypes.note,
              title: 'Blocked by empty marker',
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

  test('blocks unsafe snapshot marker paths without advancing sequence', () {
    final result = applier.apply(
      AppState(),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.stateSnapshot,
          payload: {'snapshotPath': 'https://example.com/snapshot.json'},
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-a-next',
              type: PaperTypes.note,
              title: 'Blocked by unsafe marker path',
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

  test('blocks malformed note content payloads without clearing notes', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'note', type: PaperTypes.note, content: 'Local'),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          payload: {
            'paperId': 'note',
            'content': {'not': 'a string'},
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Blocked'},
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
    expect(
      result.state.papers.singleWhere((paper) => paper.id == 'note').content,
      'Local',
    );
    expect(
      result.state.papers.map((paper) => paper.id),
      ['note', 'device-b-first'],
    );
  });

  test('blocks oversized text payloads without data loss', () {
    final longMarkdownText =
        List.filled(MarkdownPasteText.maxTextLength + 1, 'n').join();
    final longTodoText =
        List.filled(TodoPasteItems.maxLineLength + 1, 't').join();
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            content: 'Local note',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'block-1',
                type: NoteCanvasElementTypes.code,
                text: 'Local canvas',
              ),
            ],
          ),
          PaperData(
            id: 'todo',
            type: PaperTypes.todo,
            items: [
              PaperItem(
                id: 'item-1',
                text: 'Local todo',
                todoColumnCount: 2,
                todoExtraColumns: ['Local extra'],
              ),
            ],
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': longMarkdownText},
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Blocked note'},
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 1,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-1', text: longTodoText).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-b',
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem(id: 'item-1', text: 'Blocked todo').toJson(),
          },
        ),
        _operation(
          deviceId: 'device-c',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'note',
              type: PaperTypes.note,
              content: 'Blocked canvas paper',
              noteCanvasElements: [
                NoteCanvasElement(
                  id: 'block-1',
                  type: NoteCanvasElementTypes.code,
                  text: longMarkdownText,
                ),
              ],
            ).toJson(),
          },
        ),
        _operation(
          deviceId: 'device-c',
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Blocked canvas follow-up'},
        ),
        _operation(
          deviceId: 'device-d',
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'device-d-first',
              type: PaperTypes.note,
              title: 'Other device',
            ).toJson(),
          },
        ),
      ],
    );

    final note = result.state.papers.firstWhere((paper) => paper.id == 'note');
    final todo = result.state.papers.firstWhere((paper) => paper.id == 'todo');

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-d': 1});
    expect(note.content, 'Local note');
    expect(note.noteCanvasElements.single.text, 'Local canvas');
    expect(todo.items.single.text, 'Local todo');
    expect(todo.items.single.todoExtraColumns, ['Local extra']);
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'todo',
      'device-d-first',
    ]);
  });

  test('keeps consuming well-formed operations that do not change state', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(id: 'note', type: PaperTypes.note, content: 'Local'),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'missing-note', 'content': 'Ignored'},
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'fresh-note',
              type: PaperTypes.note,
              title: 'Fresh',
            ).toJson(),
          },
        ),
      ],
    );

    expect(result.appliedCount, 2);
    expect(result.deviceSequences, {'device-a': 2});
    expect(result.state.papers.map((paper) => paper.id), [
      'note',
      'fresh-note',
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

  test('applies legacy-cased matching duplicate operation sequences once', () {
    final result = applier.apply(
      AppState(
        papers: [
          PaperData(
            id: 'note',
            type: PaperTypes.note,
            title: 'Note',
            content: 'Before',
          ),
        ],
      ),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Remote'},
        ),
        _operation(
          sequence: 1,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'PaperId': 'note', 'Content': 'Remote'},
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.updateNoteContent,
          payload: {'paperId': 'note', 'content': 'Next'},
        ),
      ],
    );

    expect(result.appliedCount, 2);
    expect(result.deviceSequences, {'device-a': 2});
    expect(result.state.papers.single.content, 'Next');
  });

  test('applies model-normalized matching duplicate upserts once', () {
    final result = applier.apply(
      AppState(),
      [
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'Paper': {
              'Id': ' todo ',
              'Type': 'TODO',
              'Title': 'Remote todo',
            },
          },
        ),
        _operation(
          sequence: 1,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData.fromJson({
              'id': ' todo ',
              'type': 'TODO',
              'title': 'Remote todo',
            }).toJson(),
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'PaperId': ' todo ',
            'Item': {
              'Id': ' item ',
              'Text': 'Remote item',
              'TodoColumnCount': 9,
              'TodoExtraColumns': ['A', 'B', 'C', 'D'],
              'TodoColumnWidths': [0, 1.23456, 99],
              'ReminderIntervalValue': 999,
              'ReminderIntervalUnit': 'HOURS',
            },
          },
        ),
        _operation(
          sequence: 2,
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': PaperItem.fromJson({
              'id': ' item ',
              'text': 'Remote item',
              'todoColumnCount': 9,
              'todoExtraColumns': ['A', 'B', 'C', 'D'],
              'todoColumnWidths': [0, 1.23456, 99],
              'reminderIntervalValue': 999,
              'reminderIntervalUnit': 'HOURS',
            }).toJson(),
          },
        ),
        _operation(
          sequence: 3,
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'paper': PaperData(
              id: 'next-note',
              type: PaperTypes.note,
              title: 'Next',
            ).toJson(),
          },
        ),
      ],
    );

    final todo = result.state.papers.firstWhere((paper) => paper.id == 'todo');

    expect(result.appliedCount, 3);
    expect(result.deviceSequences, {'device-a': 3});
    expect(result.state.papers.map((paper) => paper.id), [
      'todo',
      'next-note',
    ]);
    expect(todo.items, hasLength(1));
    expect(todo.items.single.id, 'item');
    expect(todo.items.single.todoColumnCount, 4);
    expect(todo.items.single.todoExtraColumns, ['A', 'B', 'C']);
    expect(todo.items.single.todoColumnWidths, [1.0, 1.235, 8.0, 1.0]);
    expect(todo.items.single.reminderIntervalValue, 240);
    expect(todo.items.single.reminderIntervalUnit,
        TodoReminderIntervalUnits.hours);
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
