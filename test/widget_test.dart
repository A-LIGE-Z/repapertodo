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

    expect(controller.state.papers.single.items, hasLength(2));

    await tester.tap(find.byTooltip('Delete item').first);
    await tester.pump();

    expect(controller.state.papers.single.items, hasLength(1));

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

    expect(controller.state.papers.single.items, hasLength(2));

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
    expect(find.text('WebDAV sync'), findsOneWidget);
    expect(find.text('Jianguoyun'), findsOneWidget);
    expect(find.text('Generic'), findsOneWidget);
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
