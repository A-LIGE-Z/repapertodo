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
}
