import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/app_controller.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/model/paper_item.dart';
import 'package:repapertodo/src/core/storage/state_store.dart';
import 'package:repapertodo/src/core/startup/startup_command.dart';
import 'package:repapertodo/src/platform/noop_platform_services.dart';
import 'package:repapertodo/src/platform/platform_services.dart';

void main() {
  testWidgets('renders the initial paper board', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
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
    expect(find.text('Due 06-30'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_outlined));
    await tester.pump();

    expect(controller.state.papers.single.items[1].dueAtLocal, isNull);
    expect(find.text('Due 06-30'), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('welcome-todo-title')), 'Edited title');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.papers.single.title, 'Edited title');
    expect(platform.paperWindows.updatedTitles, contains('Edited title'));

    await tester.tap(find.byTooltip('Open paper surface'));
    await tester.pump();

    expect(platform.paperWindows.shownTitles, contains('Edited title'));
    expect(find.byTooltip('Back to board'), findsOneWidget);

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
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Warm'), findsOneWidget);
    expect(find.text('Ink'), findsOneWidget);
    expect(find.text('Forest'), findsOneWidget);
    expect(find.text('Rose'), findsOneWidget);
    expect(find.text('Custom theme color'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Markdown off'), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('XL'), findsOneWidget);
    expect(find.text('Font preset'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Custom font family'), findsOneWidget);
    expect(find.text('External markdown extension'), findsOneWidget);
    expect(find.text('Zoom'), findsOneWidget);
    expect(find.text('Max title length'), findsOneWidget);
    expect(find.text('Tooltips'), findsOneWidget);
    expect(find.text('Animations'), findsOneWidget);
    expect(find.text('Todo spacing'), findsOneWidget);
    expect(find.text('Note spacing'), findsOneWidget);
    expect(find.text('Relative due dates'), findsOneWidget);
    expect(find.text('No year'), findsOneWidget);
    expect(find.text('YY'), findsOneWidget);
    expect(find.text('YYYY'), findsOneWidget);
    expect(find.text('Top bar new todo'), findsOneWidget);
    expect(find.text('Top bar new note'), findsOneWidget);
    expect(find.text('Top bar open surface'), findsOneWidget);
    expect(find.text('Capsule mode'), findsOneWidget);
    expect(find.text('Deep capsule mode'), findsOneWidget);
    expect(find.text('Collapse all control'), findsOneWidget);
    expect(find.text('Collapse all active'), findsOneWidget);
    expect(find.text('Deep capsule top margin'), findsOneWidget);
    expect(find.text('Deep capsule monitor'), findsOneWidget);
    expect(find.text('Show deep capsule while expanded'), findsOneWidget);
    expect(
        find.text('Collapse expanded deep capsule on click'), findsOneWidget);
    expect(find.text('Hide covered deep capsules'), findsOneWidget);
    expect(find.text('Todo reminders'), findsOneWidget);
    expect(find.text('Reminder interval'), findsOneWidget);
    expect(find.text('Minutes'), findsOneWidget);
    expect(find.text('Hours'), findsOneWidget);
    expect(find.text('All due'), findsOneWidget);
    expect(find.text('Nearest'), findsOneWidget);
    expect(find.text('Reminder display seconds'), findsOneWidget);
    expect(find.text('Start at login'), findsOneWidget);
    expect(find.text('Hide from task switcher'), findsOneWidget);
    expect(find.text('Avoid fullscreen'), findsOneWidget);
    expect(find.text('Stay on top'), findsOneWidget);
    expect(find.text('Pinned todo hotkey'), findsOneWidget);
    expect(find.text('Pinned note hotkey'), findsOneWidget);
    expect(find.text('Run linked script capsules on click'), findsOneWidget);
    expect(find.text('Persistent PowerShell process'), findsOneWidget);
    expect(find.text('Prefer PowerShell 7'), findsOneWidget);
    expect(find.text('Hide script run window'), findsOneWidget);
    expect(find.text('Todo-note links'), findsOneWidget);
    expect(find.text('Show linked note name'), findsOneWidget);
    expect(find.text('Allow long linked note titles'), findsOneWidget);
    expect(find.text('Hide linked note capsules'), findsOneWidget);
    expect(find.text('WebDAV sync'), findsOneWidget);
    expect(find.text('Jianguoyun'), findsOneWidget);
    expect(find.text('Generic'), findsOneWidget);
  });

  testWidgets('renders markdown note preview controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'note-paper',
            type: PaperTypes.note,
            title: 'Markdown note',
            content: '# Research note\n\n- Extract claims',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-markdown-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Research note'), findsOneWidget);
    expect(find.text('Extract claims'), findsOneWidget);
  });

  testWidgets('saves custom theme color', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'theme-paper',
            type: PaperTypes.todo,
            title: 'Theme color',
            items: [
              PaperItem(id: 'theme-item', text: 'Tune color'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-custom-theme.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Custom theme color'),
      '336699',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.customThemeColorHex, '#336699');
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(
      theme.colorScheme.primary,
      ColorScheme.fromSeed(seedColor: const Color(0xFF336699)).primary,
    );
  });

  testWidgets('opens note markdown externally', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        externalMarkdownExtension: '.txt',
        papers: [
          PaperData(
            id: 'external-note',
            type: PaperTypes.note,
            title: 'External Note',
            content: '# Exported note\n\nMarkdown body.',
          ),
        ],
      ),
      platform: platform,
    );
    final store =
        StateStore(filePath: 'build/test-widget-external-note-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byIcon(Icons.file_open_outlined));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.externalFiles.openedPaths, hasLength(1));
    final openedFile = File(platform.externalFiles.openedPaths.single);
    expect(openedFile.path.endsWith('.txt'), true);
    expect(openedFile.readAsStringSync(), '# Exported note\n\nMarkdown body.');
    expect(find.textContaining('Opened markdown file:'), findsOneWidget);
  });

  testWidgets('shows due todo reminders', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 1,
        todoReminderBubbleDurationSeconds: 5,
        papers: [
          PaperData(
            id: 'reminder-paper',
            type: PaperTypes.todo,
            title: 'Reminder paper',
            items: [
              PaperItem(
                id: 'reminder-item',
                text: 'Review deadline',
                dueAtLocal: DateTime.now()
                    .subtract(const Duration(minutes: 5))
                    .toIso8601String(),
              ),
            ],
          ),
        ],
      ),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-reminder-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );
    await tester.pump();

    expect(
      find.text('Reminder: Reminder paper - Review deadline'),
      findsOneWidget,
    );

    final openAction = tester.widget<SnackBarAction>(
      find.byWidgetPredicate(
        (widget) => widget is SnackBarAction && widget.label == 'Open',
      ),
    );
    openAction.onPressed();
    await tester.pump();

    expect(platform.paperWindows.shownTitles, contains('Reminder paper'));
    expect(find.byTooltip('Back to board'), findsOneWidget);
  });

  testWidgets('sets item reminder intervals', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'item-reminder-paper',
            type: PaperTypes.todo,
            title: 'Item reminders',
            items: [
              PaperItem(id: 'item-reminder', text: 'Tune reminders'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-item-reminder-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Set reminder interval'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Interval'), '2');
    await tester.tap(find.text('Hours'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.reminderIntervalValue, 2);
    expect(item.reminderIntervalUnit, TodoReminderIntervalUnits.hours);
    expect(find.text('Every 2 hr'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear reminder interval'));
    await tester.pumpAndSettle();

    expect(item.reminderIntervalValue, isNull);
    expect(item.reminderIntervalUnit, isNull);
    expect(find.text('Every 2 hr'), findsNothing);
  });

  testWidgets('renders relative todo due dates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final today = DateTime.now();
    final controller = RePaperTodoController(
      initialState: AppState(
        showTodoDueRelativeTime: true,
        papers: [
          PaperData(
            id: 'relative-paper',
            type: PaperTypes.todo,
            title: 'Relative dates',
            items: [
              PaperItem(
                id: 'relative-item',
                text: 'Due today',
                dueAtLocal: DateTime(today.year, today.month, today.day)
                    .toIso8601String(),
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-relative-date-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Due Today'), findsOneWidget);
  });

  testWidgets('applies extra large todo visual size', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        todoVisualSize: TodoVisualSizes.extraLarge,
        papers: [
          PaperData(
            id: 'large-todo',
            type: PaperTypes.todo,
            title: 'Large todo',
            items: [
              PaperItem(id: 'large-item', text: 'Readable task'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-todo-visual-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    final dueButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.event_outlined).first,
    );
    expect(dueButton.iconSize, 30);
    expect(dueButton.constraints?.minWidth, 52);
    expect(dueButton.constraints?.minHeight, 52);
  });

  testWidgets('hides disabled top bar creation buttons', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        showTopBarNewTodoButton: false,
        showTopBarNewNoteButton: false,
        papers: [
          PaperData(
            id: 'topbar-paper',
            type: PaperTypes.todo,
            title: 'Top bar',
            items: [
              PaperItem(id: 'topbar-item', text: 'Keep surface controls'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-topbar-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.byTooltip('New todo paper'), findsNothing);
    expect(find.byTooltip('New note paper'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('disables interactive tooltips', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        enableToolTips: false,
        papers: [
          PaperData(
            id: 'no-tooltip-paper',
            type: PaperTypes.todo,
            title: 'No tooltips',
            items: [
              PaperItem(id: 'no-tooltip-item', text: 'Quiet controls'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-no-tooltips-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.byTooltip('Open paper surface'), findsNothing);
    expect(find.byTooltip('Set due date'), findsNothing);
    expect(find.byTooltip('Delete item'), findsNothing);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Tooltips'), findsOneWidget);
  });

  testWidgets('toggles paper body animations', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final animatedController = RePaperTodoController(
      initialState: AppState(
        enableAnimations: true,
        papers: [
          PaperData(
            id: 'animated-paper',
            type: PaperTypes.todo,
            title: 'Animated paper',
            items: [
              PaperItem(id: 'animated-item', text: 'Animated content'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: animatedController,
        store: StateStore(filePath: 'build/test-widget-animated-data.json'),
      ),
    );

    expect(
      find.byKey(const ValueKey('animated-paper-body-animation')),
      findsOneWidget,
    );

    final stillController = RePaperTodoController(
      initialState: AppState(
        enableAnimations: false,
        papers: [
          PaperData(
            id: 'still-paper',
            type: PaperTypes.todo,
            title: 'Still paper',
            items: [
              PaperItem(id: 'still-item', text: 'Still content'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: stillController,
        store: StateStore(filePath: 'build/test-widget-still-data.json'),
      ),
    );

    expect(
      find.byKey(const ValueKey('still-paper-body-animation')),
      findsNothing,
    );
  });

  testWidgets('toggles collapse all control', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleCollapseAll: true,
        papers: [
          PaperData(
            id: 'collapse-a',
            type: PaperTypes.todo,
            title: 'Collapse A',
            items: [
              PaperItem(id: 'collapse-item-a', text: 'Visible task'),
            ],
          ),
          PaperData(
            id: 'collapse-b',
            type: PaperTypes.note,
            title: 'Collapse B',
            content: 'Visible note',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-collapse-all-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Visible task'), findsOneWidget);
    expect(find.text('Visible note'), findsWidgets);

    await tester.tap(find.byTooltip('Collapse all papers'));
    await tester.pumpAndSettle();

    expect(controller.state.capsuleCollapseAllActive, true);
    expect(find.text('Visible task'), findsNothing);
    expect(find.text('Visible note'), findsNothing);
    expect(find.byTooltip('Expand all papers'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand all papers'));
    await tester.pumpAndSettle();

    expect(controller.state.capsuleCollapseAllActive, false);
    expect(find.text('Visible task'), findsOneWidget);
    expect(find.text('Visible note'), findsWidgets);
  });

  testWidgets('hides collapse all when capsule mode is disabled',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        useCapsuleCollapseAll: true,
        capsuleCollapseAllActive: true,
        papers: [
          PaperData(
            id: 'no-capsule-paper',
            type: PaperTypes.todo,
            title: 'No capsule',
            items: [
              PaperItem(id: 'no-capsule-item', text: 'Still expanded'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-no-capsule-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.byTooltip('Expand all papers'), findsNothing);
    expect(find.byTooltip('Collapse all papers'), findsNothing);
    expect(find.text('Still expanded'), findsOneWidget);
  });

  testWidgets('saves deep capsule visibility settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        showDeepCapsuleWhileExpanded: true,
        collapseExpandedDeepCapsuleOnClick: false,
        hideDeepCapsulesWhenCovered: false,
        papers: [
          PaperData(
            id: 'deep-capsule-settings-paper',
            type: PaperTypes.todo,
            title: 'Deep capsule settings',
            items: [
              PaperItem(id: 'deep-capsule-settings-item', text: 'Tune'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-deep-capsule-settings.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Show deep capsule while expanded'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Show deep capsule while expanded'));
    await tester.tap(find.text('Collapse expanded deep capsule on click'));
    await tester.tap(find.text('Hide covered deep capsules'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.showDeepCapsuleWhileExpanded, false);
    expect(controller.state.collapseExpandedDeepCapsuleOnClick, true);
    expect(controller.state.hideDeepCapsulesWhenCovered, true);
  });

  testWidgets('saves linked script capsule settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        runLinkedScriptCapsulesOnClick: false,
        usePersistentPowerShellProcess: false,
        preferPowerShell7: true,
        hideScriptRunWindow: true,
        papers: [
          PaperData(
            id: 'script-settings-paper',
            type: PaperTypes.todo,
            title: 'Script settings',
            items: [
              PaperItem(id: 'script-settings-item', text: 'Tune scripts'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-script-settings.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Run linked script capsules on click'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Run linked script capsules on click'));
    await tester.pump();
    await tester.tap(find.text('Persistent PowerShell process'));
    await tester.tap(find.text('Prefer PowerShell 7'));
    await tester.tap(find.text('Hide script run window'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.runLinkedScriptCapsulesOnClick, true);
    expect(controller.state.usePersistentPowerShellProcess, true);
    expect(controller.state.preferPowerShell7, false);
    expect(controller.state.hideScriptRunWindow, false);
  });

  testWidgets('saves pinned hotkeys and re-registers global hotkeys',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        pinnedTodoHotKey: '',
        pinnedNoteHotKey: '',
        papers: [
          PaperData(
            id: 'hotkey-settings-paper',
            type: PaperTypes.todo,
            title: 'Hotkey settings',
            items: [
              PaperItem(id: 'hotkey-settings-item', text: 'Tune hotkeys'),
            ],
          ),
        ],
      ),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-hotkeys.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Pinned todo hotkey'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Pinned todo hotkey'),
      '  Ctrl+Alt+T  ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Pinned note hotkey'),
      '  Ctrl+Alt+N  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.pinnedTodoHotKey, 'Ctrl+Alt+T');
    expect(controller.state.pinnedNoteHotKey, 'Ctrl+Alt+N');
    expect(platform.systemIntegration.registeredHotkeys, hasLength(1));
    expect(
      platform.systemIntegration.registeredHotkeys.single,
      ('Ctrl+Alt+T', 'Ctrl+Alt+N'),
    );
  });

  testWidgets('executes platform startup commands while running',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final startup = _RecordingStartupHost();
    final platform = _RecordingPlatformServices(startup: startup);
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'runtime-command-paper',
            type: PaperTypes.todo,
            title: 'Runtime commands',
            items: [
              PaperItem(id: 'runtime-command-item', text: 'Waiting'),
            ],
          ),
        ],
      ),
      platform: platform,
    );
    final store =
        StateStore(filePath: 'build/test-widget-runtime-command.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    startup.addCommand(const StartupCommand(StartupCommandKind.newTodo));
    await tester.pumpAndSettle();

    expect(controller.state.papers, hasLength(2));
    expect(controller.state.papers.last.type, PaperTypes.todo);
    expect(platform.paperWindows.shownTitles, contains('Todo2'));
    expect(find.text('Todo2'), findsOneWidget);
  });

  testWidgets('links todo items to note papers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        showLinkedNoteName: true,
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

  testWidgets('shortens linked note titles with max title length',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        maxTitleLength: 10,
        showLinkedNoteName: true,
        papers: [
          PaperData(
            id: 'todo-paper',
            type: PaperTypes.todo,
            title: 'Reading',
            items: [
              PaperItem(
                id: 'todo-1',
                text: 'Summarize paper',
                linkedNoteId: 'note-paper',
              ),
            ],
          ),
          PaperData(
            id: 'note-paper',
            type: PaperTypes.note,
            title: 'Very long research note',
            content: 'Notes live here.',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-title-length-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Note Very lo...'), findsOneWidget);
    expect(find.text('Note Very long research note'), findsNothing);
  });

  testWidgets('hides linked note capsules from the board', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        hideLinkedNotesFromCapsules: true,
        papers: [
          PaperData(
            id: 'todo-paper',
            type: PaperTypes.todo,
            title: 'Reading todo',
            items: [
              PaperItem(
                id: 'todo-1',
                text: 'Read linked note',
                linkedNoteId: 'linked-note',
              ),
            ],
          ),
          PaperData(
            id: 'linked-note',
            type: PaperTypes.note,
            title: 'Linked research note',
            content: 'Hidden as a capsule.',
          ),
          PaperData(
            id: 'loose-note',
            type: PaperTypes.note,
            title: 'Loose note',
            content: 'Still visible on the board.',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-hide-linked-note-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Reading todo'), findsOneWidget);
    expect(find.text('Read linked note'), findsOneWidget);
    expect(find.text('Linked research note'), findsNothing);
    expect(find.text('Hidden as a capsule.'), findsNothing);
    expect(find.text('Loose note'), findsOneWidget);
    expect(find.text('Still visible on the board.'), findsWidgets);
  });
}

class _RecordingPlatformServices implements PlatformServices {
  _RecordingPlatformServices({StartupHost? startup})
      : startup = startup ?? NoopStartupHost();

  @override
  final _RecordingPaperWindowHost paperWindows = _RecordingPaperWindowHost();

  @override
  final TrayHost tray = NoopTrayHost();

  @override
  final StartupHost startup;

  @override
  @override
  final _RecordingSystemIntegrationHost systemIntegration =
      _RecordingSystemIntegrationHost();

  @override
  final _RecordingExternalFileHost externalFiles = _RecordingExternalFileHost();
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

class _RecordingExternalFileHost implements ExternalFileHost {
  final openedPaths = <String>[];

  @override
  Future<void> openFile(String path) async {
    openedPaths.add(path);
  }
}

class _RecordingStartupHost extends NoopStartupHost {
  final _commands = StreamController<StartupCommand>.broadcast();

  @override
  Stream<StartupCommand> get commands => _commands.stream;

  void addCommand(StartupCommand command) {
    _commands.add(command);
  }
}

class _RecordingSystemIntegrationHost extends NoopSystemIntegrationHost {
  final registeredHotkeys = <(String todo, String note)>[];

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {
    registeredHotkeys.add((state.pinnedTodoHotKey, state.pinnedNoteHotKey));
  }
}
