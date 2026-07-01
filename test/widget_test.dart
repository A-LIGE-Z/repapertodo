import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/app_controller.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/note_canvas_element.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/model/paper_item.dart';
import 'package:repapertodo/src/core/model/sync_settings.dart';
import 'package:repapertodo/src/core/script/script_capsule.dart';
import 'package:repapertodo/src/core/storage/state_store.dart';
import 'package:repapertodo/src/core/state/app_state_codec.dart';
import 'package:repapertodo/src/core/startup/startup_command.dart';
import 'package:repapertodo/src/platform/noop_platform_services.dart';
import 'package:repapertodo/src/platform/platform_services.dart';
import 'package:repapertodo/src/sync/app_sync_service.dart';
import 'package:repapertodo/src/sync/webdav/webdav_state_sync_service.dart';

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
    expect(
      controller.state.sync.deletedTodoItemTombstones['welcome-todo']
          ?.containsKey('todo-1'),
      true,
    );

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
    expect(
      controller.state.sync.deletedTodoItemTombstones['welcome-todo']
          ?.containsKey('todo-1'),
      isNot(true),
    );

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
    expect(controller.state.sync.isPaperDeleted('welcome-todo'), true);

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
    expect(controller.state.sync.isPaperDeleted('welcome-todo'), false);

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
    expect(find.text('Split'), findsWidgets);
    expect(find.text('Research note'), findsOneWidget);
    expect(find.text('Extract claims'), findsOneWidget);
  });

  testWidgets('opens markdown preview links', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'link-note',
            type: PaperTypes.note,
            title: 'Link note',
            content: '[Open site](https://example.com/paper)',
          ),
        ],
      ),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-markdown-link.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.text('Open site'));
    await tester.pump();

    expect(platform.uriOpener.openedUris, ['https://example.com/paper']);
  });

  testWidgets('renders note canvas elements', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'canvas-note',
            type: PaperTypes.note,
            title: 'Canvas note',
            content: 'Main note body',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'canvas-top',
                text: 'Top layer code',
                x: 72,
                y: 48,
                width: 220,
                height: 96,
                zIndex: 2,
              ),
              NoteCanvasElement(
                id: 'canvas-bottom',
                text: 'Background idea',
                x: 24,
                y: 24,
                width: 180,
                height: 80,
                zIndex: 1,
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-note-canvas.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.byKey(const ValueKey('note-status-bar')), findsOneWidget);
    expect(find.text('Split'), findsNWidgets(2));
    expect(find.text('12 chars | 1 line | 2 elements'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-status-zoom')), findsOneWidget);

    expect(find.byKey(const ValueKey('note-canvas-preview')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('note-canvas-element-canvas-bottom')),
        matching: find.byKey(
          const ValueKey('note-canvas-element-text-canvas-bottom'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('note-canvas-element-canvas-bottom')),
        matching: find.text('CODE'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('note-canvas-element-canvas-bottom')),
        matching: find.text('Layer 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('note-canvas-element-canvas-top')),
        matching: find.byKey(
          const ValueKey('note-canvas-element-text-canvas-top'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('note-canvas-element-canvas-top')),
        matching: find.text('CODE'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('note-canvas-element-canvas-top')),
        matching: find.text('Top 2'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('note-canvas-element-text-canvas-top')),
      'Updated canvas code',
    );
    await tester.pump();

    expect(
      controller.state.papers.single.noteCanvasElements
          .firstWhere((element) => element.id == 'canvas-top')
          .text,
      'Updated canvas code',
    );

    await tester.tap(find.byTooltip('Edit canvas geometry').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'X'), '96');
    await tester.enterText(find.widgetWithText(TextField, 'Y'), '64');
    await tester.enterText(find.widgetWithText(TextField, 'Width'), '260');
    await tester.enterText(find.widgetWithText(TextField, 'Height'), '128');
    await tester.enterText(find.widgetWithText(TextField, 'Layer'), '5');
    await tester.tap(find.text('Text'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final updatedTop = controller.state.papers.single.noteCanvasElements
        .firstWhere((element) => element.id == 'canvas-top');
    expect(updatedTop.type, NoteCanvasElementTypes.text);
    expect(updatedTop.x, 96);
    expect(updatedTop.y, 64);
    expect(updatedTop.width, 260);
    expect(updatedTop.height, 128);
    expect(updatedTop.zIndex, 5);

    await tester.tap(find.byTooltip('Duplicate canvas block').last);
    await tester.pumpAndSettle();

    final duplicatedTop = controller.state.papers.single.noteCanvasElements
        .where((element) =>
            element.id != 'canvas-top' &&
            element.id != 'canvas-bottom' &&
            element.text == 'Updated canvas code')
        .single;
    expect(duplicatedTop.x, 114);
    expect(duplicatedTop.y, 82);
    expect(duplicatedTop.width, 260);
    expect(duplicatedTop.height, 128);
    expect(duplicatedTop.type, NoteCanvasElementTypes.text);
    expect(duplicatedTop.zIndex, 15);

    await tester.tap(find.byTooltip('Canvas layer actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bring to front'));
    await tester.pumpAndSettle();

    expect(duplicatedTop.zIndex, 25);

    await tester.tap(find.byTooltip('Canvas layer actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to back'));
    await tester.pumpAndSettle();

    expect(duplicatedTop.zIndex, -9);

    await tester.tap(find.widgetWithText(TextButton, 'Add canvas block'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.noteCanvasElements, hasLength(4));
    final addedCodeBlock =
        controller.state.papers.single.noteCanvasElements.last;
    expect(addedCodeBlock.type, NoteCanvasElementTypes.code);
    expect(addedCodeBlock.text, 'Console.WriteLine("PaperTodo");');
    expect(addedCodeBlock.width, 230);
    expect(addedCodeBlock.height, 116);
    expect(addedCodeBlock.zIndex, 15);

    await tester.tap(find.widgetWithText(TextButton, 'Add text block'));
    await tester.pumpAndSettle();

    final addedTextBlock =
        controller.state.papers.single.noteCanvasElements.last;
    expect(addedTextBlock.type, NoteCanvasElementTypes.text);
    expect(addedTextBlock.text, 'Canvas text 5');
    expect(find.text('12 chars | 1 line | 5 elements'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete canvas block').last);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.noteCanvasElements, hasLength(4));
    expect(find.text('12 chars | 1 line | 4 elements'), findsOneWidget);
  });

  testWidgets('clips oversized markdown note input', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'markdown-paste-note',
            type: PaperTypes.note,
            title: 'Markdown paste',
            content: 'Old body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-markdown-paste.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('markdown-paste-note-content')),
      '${List.filled(6500, 'x').join()}\r\n'
      '${List.filled(24000, 'y').join()}',
    );
    await tester.pump();

    final content = controller.state.papers.single.content;
    expect(content.length, lessThanOrEqualTo(30000));
    expect(content.split('\n').first, hasLength(6000));
    expect(content.contains('\r'), isFalse);
  });

  testWidgets('uses markdown toolbar actions in note editor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'markdown-toolbar-note',
            type: PaperTypes.note,
            title: 'Markdown toolbar',
            content: 'Body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-markdown-toolbar.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Insert link (Ctrl+K)'));
    await tester.pump();

    expect(controller.state.papers.single.content, 'Body[link](https://)');

    await tester.tap(find.byTooltip('Heading'));
    await tester.pump();

    expect(controller.state.papers.single.content, '# Body[link](https://)');
  });

  testWidgets('uses markdown keyboard shortcuts in note editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'markdown-shortcut-note',
            type: PaperTypes.note,
            title: 'Markdown shortcuts',
            content: 'Body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-markdown-shortcuts.json');
    final field = find.byKey(const ValueKey('markdown-shortcut-note-content'));

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.enterText(field, 'Body');
    await tester.pump();
    await _pressControlShortcut(tester, LogicalKeyboardKey.keyB);
    await tester.pump();

    expect(controller.state.papers.single.content, 'Body****');

    await tester.enterText(field, 'Body');
    await tester.pump();
    await _pressControlShortcut(tester, LogicalKeyboardKey.keyK);
    await tester.pump();

    expect(controller.state.papers.single.content, 'Body[link](https://)');
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

  testWidgets('restores a WebDAV recovery snapshot from the toolbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.todo,
            title: 'Local',
            items: [
              PaperItem(id: 'local-item', text: 'Local item'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-recovery-snapshot.json');
    final syncService = _RecoverySnapshotSyncService(
      snapshots: [
        WebDavSnapshotRecord(
          path: 'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json',
          deviceId: 'phone',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
          contentLength: 2048,
          lastModifiedUtc: DateTime.utc(2026, 7, 1, 9, 1),
        ),
      ],
      restoredState: AppState(
        papers: [
          PaperData(
            id: 'snapshot-paper',
            type: PaperTypes.note,
            title: 'Snap',
            content: 'Recovered body',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();

    expect(find.text('Recovery snapshots'), findsOneWidget);
    expect(find.textContaining('phone'), findsWidgets);
    expect(find.textContaining('2.0 KiB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(
        'restore-snapshot-repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json')));
    await tester.pumpAndSettle();

    expect(find.text('Restore snapshot?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 20; attempt++) {
        if (controller.state.papers.single.title == 'Snap') {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.restoredPaths, [
      'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json',
    ]);
    expect(find.textContaining('Restore failed:'), findsNothing);
    expect(controller.state.papers.single.title, 'Snap');
    expect(controller.state.papers.single.content, 'Recovered body');
    expect(find.text('Snapshot restored.'), findsOneWidget);
  });

  testWidgets('manual sync merges remote operation logs from the toolbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'local-note',
            type: PaperTypes.note,
            title: 'Local',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-manual-sync.json');
    final snapshotState = AppState(
      papers: [
        PaperData(
          id: 'remote-note',
          type: PaperTypes.note,
          title: 'Remote',
          content: 'Snapshot body',
        ),
      ],
    );
    final mergedState = AppState(
      papers: [
        PaperData(
          id: 'remote-note',
          type: PaperTypes.note,
          title: 'Remote',
          content: 'Merged body',
        ),
      ],
    );
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: snapshotState,
          message: 'Remote data downloaded.',
        ),
        state: mergedState,
        operationMergeResult: AppSyncOperationMergeResult(
          state: mergedState,
          deviceSequences: const {'device-a': 1},
          appliedCount: 1,
        ),
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    expect(controller.state.papers.single.title, 'Local');

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Remote');
    expect(controller.state.papers.single.content, 'Merged body');
    expect(
      find.text('Remote data downloaded. Merged 1 remote change.'),
      findsOneWidget,
    );
  });

  testWidgets('manual sync uploads pending local edits before merging',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final syncSettings = SyncSettings(
      enabled: true,
      provider: SyncProviderIds.webDav,
      webDav: WebDavSyncSettings(
        endpoint: 'https://dav.example.test/',
        username: 'user',
        password: 'pass',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'manual-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: initialState,
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(initialState);
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'manual-note',
          type: PaperTypes.note,
          title: 'Synced',
          content: 'Local body',
        ),
      ],
    );
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: syncedState,
          message: 'Remote data downloaded.',
        ),
        state: syncedState,
      ),
      localUploadState: AppState(
        sync: syncSettings.copy()
          ..operationDeviceSequences = const {'device-a': 1},
        papers: [
          PaperData(
            id: 'manual-note',
            type: PaperTypes.note,
            title: 'Draft',
            content: 'Local body',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('manual-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
    expect(find.text('Remote data downloaded.'), findsOneWidget);
  });

  testWidgets('auto sync runs silently on the configured interval',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            rootPath: 'repapertodo',
            autoSyncIntervalMinutes: 1,
          ),
        ),
        papers: [
          PaperData(
            id: 'local-note',
            type: PaperTypes.note,
            title: 'Local',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-auto-sync.json');
    final syncedState = AppState(
      papers: [
        PaperData(
          id: 'auto-note',
          type: PaperTypes.note,
          title: 'Auto synced',
          content: 'Merged on timer',
        ),
      ],
    );
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: syncedState,
          message: 'Remote data downloaded.',
        ),
        state: syncedState,
        operationMergeResult: AppSyncOperationMergeResult(
          state: syncedState,
          deviceSequences: const {'device-a': 2},
          appliedCount: 2,
        ),
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.pump(const Duration(seconds: 59));

    expect(syncService.calls, 0);
    expect(controller.state.papers.single.title, 'Local');

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Auto synced');
    expect(controller.state.papers.single.content, 'Merged on timer');
    expect(find.textContaining('Merged 2 remote changes.'), findsNothing);
  });

  testWidgets('auto sync runs silently on foreground and background changes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final syncSettings = SyncSettings(
      enabled: true,
      provider: SyncProviderIds.webDav,
      webDav: WebDavSyncSettings(
        endpoint: 'https://dav.example.test/',
        username: 'user',
        password: 'pass',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: syncSettings.copy(),
        papers: [
          PaperData(
            id: 'lifecycle-note',
            type: PaperTypes.note,
            title: 'Lifecycle local',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-lifecycle-sync.json');
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'lifecycle-note',
          type: PaperTypes.note,
          title: 'Lifecycle synced',
          content: 'Synced on lifecycle',
        ),
      ],
    );
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: syncedState,
          message: 'Remote data downloaded.',
        ),
        state: syncedState,
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Lifecycle synced');
    expect(find.text('Remote data downloaded.'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    expect(syncService.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(syncService.calls, 2);
    expect(find.text('Remote data downloaded.'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();

    expect(syncService.calls, 3);
    expect(find.text('Remote data downloaded.'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(syncService.calls, 4);
    expect(find.text('Remote data downloaded.'), findsNothing);
  });

  testWidgets('local edits schedule one debounced silent sync', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final syncSettings = SyncSettings(
      enabled: true,
      provider: SyncProviderIds.webDav,
      webDav: WebDavSyncSettings(
        endpoint: 'https://dav.example.test/',
        username: 'user',
        password: 'pass',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'debounce-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: initialState,
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(initialState);
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'debounce-note',
          type: PaperTypes.note,
          title: 'Synced',
          content: 'Local body',
        ),
      ],
    );
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: syncedState,
          message: 'Local data uploaded.',
        ),
        state: syncedState,
      ),
      localUploadState: AppState(
        sync: syncSettings.copy()
          ..operationDeviceSequences = const {'device-a': 1},
        papers: [
          PaperData(
            id: 'debounce-note',
            type: PaperTypes.note,
            title: 'Two',
            content: 'Local body',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('debounce-note-title')),
      'One',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 3));

    expect(syncService.calls, 0);

    await tester.enterText(
      find.byKey(const ValueKey('debounce-note-title')),
      'Two',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 4));

    expect(syncService.calls, 0);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(syncService.localUploadCalls, 1);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Two']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
    expect(find.text('Local data uploaded.'), findsNothing);
  });

  testWidgets('local edits retry upload when sync is busy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final syncSettings = SyncSettings(
      enabled: true,
      provider: SyncProviderIds.webDav,
      webDav: WebDavSyncSettings(
        endpoint: 'https://dav.example.test/',
        username: 'user',
        password: 'pass',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'busy-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: initialState,
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(initialState);
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'busy-note',
          type: PaperTypes.note,
          title: 'Synced',
          content: 'Local body',
        ),
      ],
    );
    final firstSyncGate = Completer<void>();
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: syncedState,
          message: 'Local data uploaded.',
        ),
        state: syncedState,
      ),
      firstSyncGate: firstSyncGate.future,
      localUploadState: AppState(
        sync: syncSettings.copy()
          ..operationDeviceSequences = const {'device-a': 1},
        papers: [
          PaperData(
            id: 'busy-note',
            type: PaperTypes.note,
            title: 'Two',
            content: 'Local body',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    expect(syncService.calls, 1);

    await tester.enterText(
        find.byKey(const ValueKey('busy-note-title')), 'Two');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(syncService.localUploadCalls, 0);

    firstSyncGate.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(syncService.localUploadCalls, 1);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Two']);
    expect(syncService.calls, 2);
  });

  testWidgets('exit command flushes local edits before platform cleanup',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final startup = _RecordingStartupHost();
    final platform = _RecordingPlatformServices(startup: startup);
    final syncSettings = SyncSettings(
      enabled: true,
      provider: SyncProviderIds.webDav,
      webDav: WebDavSyncSettings(
        endpoint: 'https://dav.example.test/',
        username: 'user',
        password: 'pass',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'exit-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: initialState,
      platform: platform,
    );
    final store = _MemoryStateStore();
    await store.save(initialState);
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'exit-note',
          type: PaperTypes.note,
          title: 'Synced',
          content: 'Local body',
        ),
      ],
    );
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: syncedState,
          message: 'Local data uploaded.',
        ),
        state: syncedState,
      ),
      localUploadState: AppState(
        sync: syncSettings.copy()
          ..operationDeviceSequences = const {'device-a': 1},
        papers: [
          PaperData(
            id: 'exit-note',
            type: PaperTypes.note,
            title: 'Draft',
            content: 'Local body',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    controller.state.papers.single.title = 'Draft';
    startup.addCommand(const StartupCommand(StartupCommandKind.exit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.localUploadCalls, 1);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.tray.disposeCount, 1);
    expect(find.text('Local data uploaded.'), findsNothing);
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
    expect(
      openedFile.path,
      contains(
        '${Platform.pathSeparator}RePaperTodo${Platform.pathSeparator}paper-external-note.txt',
      ),
    );
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
      find.text('Reminder: Remind - Review deadline'),
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

  testWidgets('adjusts per-paper text zoom', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'zoom-paper',
            type: PaperTypes.todo,
            title: 'Zoom paper',
            items: [
              PaperItem(id: 'zoom-item', text: 'Readable task'),
            ],
          ),
        ],
      ),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-paper-zoom.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    final itemFinder = find.byKey(const ValueKey('zoom-paper-zoom-item-text'));
    final beforeText = tester.widget<EditableText>(
      find.descendant(of: itemFinder, matching: find.byType(EditableText)),
    );
    final beforeFontSize = beforeText.style.fontSize ?? 0;

    await tester.tap(find.byTooltip('Paper text zoom'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<double> && widget.value == 1.25,
      ),
    );
    await tester.pumpAndSettle();

    final afterText = tester.widget<EditableText>(
      find.descendant(of: itemFinder, matching: find.byType(EditableText)),
    );
    expect(controller.state.papers.single.textZoom, 1.25);
    expect(afterText.style.fontSize, greaterThan(beforeFontSize));
    expect(platform.paperWindows.updatedTitles, contains('Zoom paper'));
  });

  testWidgets('edits todo extra columns', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'columns-paper',
            type: PaperTypes.todo,
            title: 'Columns paper',
            items: [
              PaperItem(id: 'columns-item', text: 'Track reading'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-columns.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Todo columns'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'add',
      ),
    );
    await tester.pumpAndSettle();

    final firstItem = controller.state.papers.single.items.first;
    expect(firstItem.todoColumnCount, 2);
    expect(firstItem.todoExtraColumns, ['']);
    expect(find.text('Column 1'), findsOneWidget);
    expect(find.text('Column 2'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('columns-paper-columns-item-column-2')),
      'Status: reading',
    );
    await tester.pump();

    expect(firstItem.todoExtraColumns.single, 'Status: reading');

    await tester.tap(find.byTooltip('Todo columns'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<String> && widget.value == 'wide-first',
      ),
    );
    await tester.pumpAndSettle();

    expect(firstItem.todoColumnWidths, [2, 1]);

    await tester.tap(find.widgetWithText(TextButton, 'Add item'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(2));
    expect(controller.state.papers.single.items.last.todoColumnCount, 2);
    expect(controller.state.papers.single.items.last.todoExtraColumns, ['']);
    expect(controller.state.papers.single.items.last.todoColumnWidths, [2, 1]);

    await tester.tap(find.byTooltip('Todo columns').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'remove',
      ),
    );
    await tester.pumpAndSettle();

    expect(firstItem.todoColumnCount, 1);
    expect(firstItem.todoExtraColumns, isEmpty);
  });

  testWidgets('splits pasted todo lists into cleaned items', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'paste-paper',
            type: PaperTypes.todo,
            title: 'Paste paper',
            items: [
              PaperItem(
                id: 'paste-item',
                text: 'Old value',
                todoColumnCount: 2,
                todoExtraColumns: [''],
                todoColumnWidths: [2, 1],
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-todo-paste.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('paste-paper-paste-item-text')),
        matching: find.byType(EditableText),
      ),
      '- [ ] Read paper\n2) Compare notes\n☑ Ship build',
    );
    await tester.pumpAndSettle();

    final items = controller.state.papers.single.items;
    expect(items.map((item) => item.text), [
      'Read paper',
      'Compare notes',
      'Ship build',
    ]);
    expect(items.map((item) => item.todoColumnCount), [2, 2, 2]);
    expect(items.map((item) => item.todoColumnWidths), [
      [2, 1],
      [2, 1],
      [2, 1],
    ]);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.text), [
      'Old value',
    ]);

    await tester.tap(find.byTooltip('Redo todo change'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.text), [
      'Read paper',
      'Compare notes',
      'Ship build',
    ]);
  });

  testWidgets('toggles desktop pin and always-on-top as exclusive modes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'pin-paper',
            type: PaperTypes.todo,
            title: 'Pin paper',
            items: [
              PaperItem(id: 'pin-item', text: 'Choose a surface mode'),
            ],
          ),
        ],
      ),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-pin-mode.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Pin to desktop'));
    await tester.pumpAndSettle();

    final paper = controller.state.papers.single;
    expect(paper.isPinnedToDesktop, true);
    expect(paper.alwaysOnTop, false);
    expect(find.byTooltip('Unpin from desktop'), findsOneWidget);
    expect(platform.paperWindows.updatedTitles, contains('Pin paper'));

    await tester.tap(find.byTooltip('Keep on top'));
    await tester.pumpAndSettle();

    expect(paper.alwaysOnTop, true);
    expect(paper.isPinnedToDesktop, false);
    expect(find.byTooltip('Disable always on top'), findsOneWidget);
    expect(find.byTooltip('Pin to desktop'), findsOneWidget);
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

  testWidgets('stops persistent script process when script settings change',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        runLinkedScriptCapsulesOnClick: true,
        usePersistentPowerShellProcess: true,
        preferPowerShell7: true,
        hideScriptRunWindow: true,
        papers: [
          PaperData(
            id: 'script-reset-paper',
            type: PaperTypes.todo,
            title: 'Script reset',
            items: [
              PaperItem(id: 'script-reset-item', text: 'Tune scripts'),
            ],
          ),
        ],
      ),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-script-reset.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Prefer PowerShell 7'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Prefer PowerShell 7'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.preferPowerShell7, false);
    expect(platform.scriptCapsules.stopCount, 1);
    expect(platform.scriptCapsules.preparedSettings, [
      (preferPowerShell7: false, hideScriptRunWindow: true),
    ]);
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

    startup.addCommand(const StartupCommand(StartupCommandKind.settings));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
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
    expect(find.text('Note Resear'), findsOneWidget);

    await tester.tap(find.text('Note Resear'));
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
    expect(find.text('Note Resear'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_outlined));
    await tester.pump();

    expect(controller.state.papers.first.items.single.linkedNoteId, isNull);
    expect(find.text('Note Resear'), findsNothing);
  });

  testWidgets('runs linked script capsules from todo note chips',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        maxTitleLength: 20,
        runLinkedScriptCapsulesOnClick: true,
        showLinkedNoteName: true,
        papers: [
          PaperData(
            id: 'todo-paper',
            type: PaperTypes.todo,
            title: 'Scripts',
            items: [
              PaperItem(
                id: 'todo-1',
                text: 'Run automation',
                linkedNoteId: 'script-note',
              ),
            ],
          ),
          PaperData(
            id: 'script-note',
            type: PaperTypes.note,
            title: 'Build script',
            content: '!pf\n  Write-Output ok',
          ),
        ],
      ),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-script-chip.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.text('Run Build script'));
    await tester.pumpAndSettle();

    expect(platform.paperWindows.shownTitles, isNot(contains('Build script')));
    expect(platform.scriptCapsules.requests, hasLength(1));
    final request = platform.scriptCapsules.requests.single;
    expect(request.engine, 'auto');
    expect(request.script, 'Write-Output ok');
    expect(request.usePersistentProcess, true);
    expect(request.preferPowerShell7, true);
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

    expect(find.text('Note Very long '), findsOneWidget);
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

Future<void> _pressControlShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

class _RecoverySnapshotSyncService extends AppSyncService {
  _RecoverySnapshotSyncService({
    required this.snapshots,
    required this.restoredState,
  });

  final List<WebDavSnapshotRecord> snapshots;
  final AppState restoredState;
  final restoredPaths = <String>[];

  @override
  Future<List<WebDavSnapshotRecord>> listRecoverySnapshots({
    required AppState localState,
    required StateStore store,
  }) async {
    return snapshots;
  }

  @override
  Future<AppSyncResult> restoreRecoverySnapshot({
    required AppState localState,
    required StateStore store,
    required String snapshotPath,
  }) async {
    restoredPaths.add(snapshotPath);
    return AppSyncResult(
      status: AppSyncStatus.downloaded,
      state: restoredState,
      message: 'Snapshot restored.',
      snapshotPath: snapshotPath,
    );
  }
}

class _ManualSyncService extends AppSyncService {
  _ManualSyncService({
    required this.result,
    this.firstSyncGate,
    this.localUploadState,
  });

  final AppSyncRunResult result;
  final Future<void>? firstSyncGate;
  final AppState? localUploadState;
  var calls = 0;
  var localUploadCalls = 0;
  final events = <String>[];
  final localUploadBeforeTitles = <String>[];
  final localUploadAfterTitles = <String>[];

  @override
  Future<AppSyncRunResult> syncAndMergeNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    calls += 1;
    events.add('sync');
    final gate = firstSyncGate;
    if (calls == 1 && gate != null) {
      await gate;
    }
    return result;
  }

  @override
  Future<AppSyncLocalOperationUploadResult> uploadLocalOperations({
    required AppState beforeState,
    required AppState afterState,
    required StateStore store,
    DateTime? createdAtUtc,
  }) async {
    localUploadCalls += 1;
    events.add('upload');
    localUploadBeforeTitles.add(beforeState.papers.single.title);
    localUploadAfterTitles.add(afterState.papers.single.title);
    final state = localUploadState ?? afterState;
    await store.save(state);
    return AppSyncLocalOperationUploadResult(
      state: state,
      deviceSequences: state.sync.operationDeviceSequences,
      generatedCount: 1,
      uploadedCount: 1,
    );
  }
}

class _MemoryStateStore extends StateStore {
  _MemoryStateStore() : super(filePath: 'memory-state.json');

  final _codec = const AppStateCodec();
  AppState savedState = AppState();

  @override
  Future<DateTime?> lastModifiedUtc() async {
    return null;
  }

  @override
  Future<AppState> load() async {
    return savedState;
  }

  @override
  Future<void> save(AppState state) async {
    savedState = _codec.decode(_codec.encode(state));
  }
}

class _RecordingPlatformServices implements PlatformServices {
  _RecordingPlatformServices({StartupHost? startup})
      : startup = startup ?? NoopStartupHost();

  @override
  final _RecordingPaperWindowHost paperWindows = _RecordingPaperWindowHost();

  @override
  final _RecordingTrayHost tray = _RecordingTrayHost();

  @override
  final StartupHost startup;

  @override
  final _RecordingSystemIntegrationHost systemIntegration =
      _RecordingSystemIntegrationHost();

  @override
  final _RecordingExternalFileHost externalFiles = _RecordingExternalFileHost();

  @override
  final _RecordingUriOpenHost uriOpener = _RecordingUriOpenHost();

  @override
  final _RecordingScriptCapsuleHost scriptCapsules =
      _RecordingScriptCapsuleHost();
}

class _RecordingTrayHost extends NoopTrayHost {
  var disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
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

class _RecordingUriOpenHost implements UriOpenHost {
  final openedUris = <String>[];

  @override
  Future<void> openUri(String uri) async {
    openedUris.add(uri);
  }
}

class _RecordingScriptCapsuleHost implements ScriptCapsuleHost {
  final requests = <ScriptCapsuleRunRequest>[];
  final preparedSettings =
      <({bool preferPowerShell7, bool hideScriptRunWindow})>[];
  var stopCount = 0;

  @override
  Future<void> preparePersistentProcess({
    required bool preferPowerShell7,
    required bool hideScriptRunWindow,
  }) async {
    preparedSettings.add((
      preferPowerShell7: preferPowerShell7,
      hideScriptRunWindow: hideScriptRunWindow,
    ));
  }

  @override
  Future<void> runScriptCapsule(ScriptCapsuleRunRequest request) async {
    requests.add(request);
  }

  @override
  Future<void> stopPersistentProcesses() async {
    stopCount += 1;
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
  var unregisterGlobalHotkeysCount = 0;

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {
    registeredHotkeys.add((state.pinnedTodoHotKey, state.pinnedNoteHotKey));
  }

  @override
  Future<void> unregisterGlobalHotkeys() async {
    unregisterGlobalHotkeysCount += 1;
  }
}
