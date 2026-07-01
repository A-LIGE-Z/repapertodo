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
