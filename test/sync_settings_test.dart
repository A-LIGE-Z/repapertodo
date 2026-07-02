import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('keeps latest tombstones when marking deleted records', () {
    final ten = DateTime.utc(2026, 7, 1, 10);
    final tenThirty = DateTime.utc(2026, 7, 1, 10, 30);
    final settings = SyncSettings(
      deletedPaperTombstones: {'paper': ten.toIso8601String()},
      deletedTodoItemTombstones: {
        'paper': {'item': tenThirty.toIso8601String()},
        'todo': {'item': ten.toIso8601String()},
      },
    );

    settings
      ..markPaperDeleted(' paper ', DateTime.utc(2026, 7, 1, 9))
      ..markTodoItemDeleted(' todo ', ' item ', DateTime.utc(2026, 7, 1, 9));

    expect(settings.deletedPaperTombstones['paper'], ten.toIso8601String());
    expect(
      settings.deletedTodoItemTombstones['paper']?['item'],
      tenThirty.toIso8601String(),
    );
    expect(
      settings.deletedTodoItemTombstones['todo']?['item'],
      ten.toIso8601String(),
    );

    settings
      ..markTodoItemDeleted('todo', 'item', DateTime.utc(2026, 7, 1, 11))
      ..markPaperDeleted('paper', DateTime.utc(2026, 7, 1, 11));

    expect(
      settings.deletedPaperTombstones['paper'],
      DateTime.utc(2026, 7, 1, 11).toIso8601String(),
    );
    expect(settings.deletedTodoItemTombstones.containsKey('paper'), false);
    expect(
      settings.deletedTodoItemTombstones['todo']?['item'],
      DateTime.utc(2026, 7, 1, 11).toIso8601String(),
    );
  });
}
