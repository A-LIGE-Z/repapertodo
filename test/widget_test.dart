import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/app_controller.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/model/paper_item.dart';
import 'package:repapertodo/src/core/storage/state_store.dart';
import 'package:repapertodo/src/platform/noop_platform_services.dart';
import 'package:repapertodo/src/platform/platform_services.dart';

void main() {
  testWidgets('renders the initial paper board', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'welcome-todo',
            type: PaperTypes.todo,
            title: 'Windows parity',
            items: [
              PaperItem(id: 'todo-1', text: 'Build compatible data core'),
              PaperItem(
                id: 'todo-2',
                text: 'Check due date',
                dueAtLocal: '2026-06-30T00:00:00',
                order: 1,
              ),
            ],
          ),
        ],
      ),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('RePaperTodo'), findsWidgets);
    expect(find.text('Windows parity'), findsOneWidget);
    expect(find.text('Build compatible data core'), findsOneWidget);
    expect(find.text('Due 2026-06-30'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_outlined));
    await tester.pump();

    expect(controller.state.papers.single.items[1].dueAtLocal, isNull);
    expect(find.text('Due 2026-06-30'), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('welcome-todo-title')), 'Edited title');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.papers.single.title, 'Edited title');
    expect(platform.paperWindows.updatedTitles, contains('Edited title'));

    await tester.tap(find.byTooltip('Open paper surface'));
    await tester.pump();

    expect(platform.paperWindows.shownTitles, contains('Edited title'));

    await tester.tap(find.byKey(const ValueKey('welcome-todo-todo-1-text')));
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(controller.state.papers.single.items, hasLength(3));

    await tester.tap(find.byTooltip('Delete item').first);
    await tester.pump();

    expect(controller.state.papers.single.items, hasLength(2));

    final itemUndoAction = tester.widget<SnackBarAction>(
      find.byWidgetPredicate(
        (widget) => widget is SnackBarAction && widget.label == 'Undo',
      ),
    );
    itemUndoAction.onPressed();
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(3));

    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isCollapsed, true);
    expect(find.text('Build compatible data core'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isCollapsed, false);
    expect(find.text('Build compatible data core'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isVisible, false);
    expect(find.text('Edited title'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isVisible, true);
    expect(find.text('Edited title'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete paper'));
    await tester.pumpAndSettle();

    expect(find.text('Delete paper?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(controller.state.papers, hasLength(1));
    expect(find.text('Edited title'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete paper'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump(const Duration(seconds: 1));

    expect(controller.state.papers, isEmpty);
    expect(find.byKey(const ValueKey('welcome-todo-title')), findsNothing);

    final undoAction = tester.widget<SnackBarAction>(
      find.byWidgetPredicate(
        (widget) => widget is SnackBarAction && widget.label == 'Undo',
      ),
    );
    undoAction.onPressed();
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    expect(controller.state.papers, hasLength(1));
    expect(find.byKey(const ValueKey('welcome-todo-title')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.sync_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Sync is disabled.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.text('Start at login'), findsOneWidget);
    expect(find.text('Hide from task switcher'), findsOneWidget);
    expect(find.text('Avoid fullscreen'), findsOneWidget);
    expect(find.text('Stay on top'), findsOneWidget);
    expect(find.text('WebDAV sync'), findsOneWidget);
    expect(find.text('Jianguoyun'), findsOneWidget);
    expect(find.text('Generic'), findsOneWidget);
  });

  testWidgets('links todo items to note papers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'todo-paper',
            type: PaperTypes.todo,
            title: 'Reading',
            items: [
              PaperItem(id: 'todo-1', text: 'Summarize paper'),
            ],
          ),
          PaperData(
            id: 'note-paper',
            type: PaperTypes.note,
            title: 'Research note',
            content: 'Notes live here.',
          ),
        ],
      ),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-link-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Link note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Research note').last);
    await tester.pumpAndSettle();

    expect(
        controller.state.papers.first.items.single.linkedNoteId, 'note-paper');
    expect(find.text('Note Research note'), findsOneWidget);

    await tester.tap(find.text('Note Research note'));
    await tester.pump();

    expect(platform.paperWindows.shownTitles, contains('Research note'));

    await tester.tap(find.byTooltip('Delete paper').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump(const Duration(seconds: 1));

    expect(controller.state.papers.first.items.single.linkedNoteId, isNull);
    expect(find.text('Note Research note'), findsNothing);

    final undoDeleteAction = tester.widget<SnackBarAction>(
      find.byWidgetPredicate(
        (widget) => widget is SnackBarAction && widget.label == 'Undo',
      ),
    );
    undoDeleteAction.onPressed();
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    expect(
        controller.state.papers.first.items.single.linkedNoteId, 'note-paper');
    expect(find.text('Note Research note'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_outlined));
    await tester.pump();

    expect(controller.state.papers.first.items.single.linkedNoteId, isNull);
    expect(find.text('Note Research note'), findsNothing);
  });
}

class _RecordingPlatformServices implements PlatformServices {
  @override
  final _RecordingPaperWindowHost paperWindows = _RecordingPaperWindowHost();

  @override
  final TrayHost tray = NoopTrayHost();

  @override
  final StartupHost startup = NoopStartupHost();

  @override
  final SystemIntegrationHost systemIntegration = NoopSystemIntegrationHost();
}

class _RecordingPaperWindowHost extends NoopPaperWindowHost {
  final updatedTitles = <String>[];
  final shownTitles = <String>[];

  @override
  Future<void> showPaper(PaperData paper) async {
    shownTitles.add(paper.title);
  }

  @override
  Future<void> updatePaperSurface(PaperData paper) async {
    updatedTitles.add(paper.title);
  }
}
