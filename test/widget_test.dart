import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
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
import 'package:repapertodo/src/sync/webdav/webdav_client.dart';
import 'package:repapertodo/src/sync/webdav/webdav_payload_codec.dart';
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
    expect(find.text('Due 06-30 00:00'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_outlined));
    await tester.pump();

    expect(controller.state.papers.single.items[1].dueAtLocal, isNull);
    expect(find.text('Due 06-30 00:00'), findsNothing);

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

    expect(controller.state.papers, hasLength(1));
    expect(controller.state.papers.single.id, isNot('welcome-todo'));
    expect(controller.state.papers.single.type, PaperTypes.todo);
    expect(controller.state.papers.single.isVisible, true);
    expect(find.byKey(const ValueKey('welcome-todo-title')), findsNothing);
    expect(controller.state.sync.isPaperDeleted('welcome-todo'), true);
    expect(platform.paperWindows.hiddenTitles, contains('Edited title'));
    expect(platform.paperWindows.shownTitles, contains('Todo1'));

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

    expect(controller.state.papers, hasLength(2));
    expect(find.byKey(const ValueKey('welcome-todo-title')), findsOneWidget);
    expect(controller.state.sync.isPaperDeleted('welcome-todo'), false);

    await tester.tap(find.byIcon(Icons.sync_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Sync is disabled.'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
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
    expect(find.byKey(const ValueKey('note-paper-preview')), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-status-mode')), findsOneWidget);
    expect(find.text('Research note'), findsOneWidget);
    expect(find.text('Extract claims'), findsOneWidget);
  });

  testWidgets('markdown notes default to preview and click into editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'preview-first-note',
            type: PaperTypes.note,
            title: 'Preview first note',
            content: '# Preview first\n\nClick body to edit.',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    expect(find.byKey(const ValueKey('preview-first-note-preview')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('preview-first-note-content')), findsNothing);
    expect(find.text('Preview first'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-status-mode')), findsOneWidget);
    expect(find.text('Preview'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('preview-first-note-preview')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('preview-first-note-content')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('preview-first-note-preview')), findsNothing);
    expect(find.text('Edit'), findsWidgets);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('preview-first-note-preview')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('preview-first-note-content')), findsNothing);
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

  testWidgets('opens editor markdown links only on control click',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'edit-link-note',
            type: PaperTypes.note,
            title: 'Edit link note',
            content: '[Open edit](https://example.com/edit)',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await _enterNoteEditor(tester, 'edit-link-note');
    final field = find.byKey(const ValueKey('edit-link-note-content'));
    final editableFinder =
        find.descendant(of: field, matching: find.byType(EditableText));
    final editable = tester.widget<EditableText>(editableFinder);
    editable.controller.selection = const TextSelection.collapsed(offset: 3);

    await tester.tap(editableFinder);
    await tester.pump();
    await tester.pump();
    expect(platform.uriOpener.openedUris, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final controlPlatform = _RecordingPlatformServices();
    final controlController = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'edit-link-note',
            type: PaperTypes.note,
            title: 'Edit link note',
            content: '[Open edit](https://example.com/edit)',
          ),
        ],
      ),
      platform: controlPlatform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controlController,
        store: _MemoryStateStore(),
      ),
    );

    await _enterNoteEditor(tester, 'edit-link-note');
    final controlField = find.byKey(const ValueKey('edit-link-note-content'));
    final controlEditableFinder =
        find.descendant(of: controlField, matching: find.byType(EditableText));
    final controlEditable = tester.widget<EditableText>(controlEditableFinder);
    controlEditable.controller.selection =
        const TextSelection.collapsed(offset: 3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(controlEditableFinder);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(controlPlatform.uriOpener.openedUris, ['https://example.com/edit']);
  });

  testWidgets('opens supported mailto markdown links', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'mailto-note',
            type: PaperTypes.note,
            title: 'Mail note',
            content: '[Mail author](mailto:paper@example.com)',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Mail author'));
    await tester.pump();

    expect(platform.uriOpener.openedUris, ['mailto:paper@example.com']);
  });

  testWidgets('blocks unsafe markdown preview links before platform open',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'unsafe-link-note',
            type: PaperTypes.note,
            title: 'Unsafe link note',
            content: '[Run script](javascript:alert(1))',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Run script'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(
      find.textContaining('unsupported link target'),
      findsOneWidget,
    );
  });

  testWidgets('blocks credentialed markdown preview links before platform open',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'credentialed-link-note',
            type: PaperTypes.note,
            title: 'Credentialed link note',
            content: '[Open private link](https://user:pass@example.com/path)',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Open private link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsOneWidget);
  });

  testWidgets('blocks encoded credential markdown links before platform open',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'encoded-credential-link-note',
            type: PaperTypes.note,
            title: 'Encoded credential link note',
            content:
                '[Open encoded link](https://example.com%40evil.test/path)',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Open encoded link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsOneWidget);
  });

  testWidgets('blocks encoded authority separator markdown links',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'encoded-authority-separator-link-note',
            type: PaperTypes.note,
            title: 'Encoded authority separator link note',
            content: '[Open encoded separator](https://example.com%3A443/path)',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Open encoded separator'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsOneWidget);
  });

  testWidgets('blocks encoded control markdown links before platform open',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'encoded-control-link-note',
            type: PaperTypes.note,
            title: 'Encoded control link note',
            content: '[Open encoded control link](https://example.com/%0Apath)',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Open encoded control link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsOneWidget);
  });

  testWidgets('blocks hostless markdown preview links before platform open',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'hostless-link-note',
            type: PaperTypes.note,
            title: 'Hostless link note',
            content: '[Open hostless link](https://:443/path)',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Open hostless link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsOneWidget);
  });

  testWidgets('opens markdown preview links with encoded whitespace',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'spaced-link-note',
            type: PaperTypes.note,
            title: 'Spaced link note',
            content: '[Bad link](<https://example.com/a b>)',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Bad link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, ['https://example.com/a%20b']);
    expect(find.textContaining('unsupported link target'), findsNothing);
  });

  testWidgets('reports markdown preview link open failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.uriOpener.error = StateError('No browser available');
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'failed-link-note',
            type: PaperTypes.note,
            title: 'Failed link note',
            content: '[Broken link](https://example.com/missing)',
          ),
        ],
      ),
      platform: platform,
    );
    final store =
        StateStore(filePath: 'build/test-widget-markdown-link-failure.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.text('Broken link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, ['https://example.com/missing']);
    expect(find.textContaining('Open link failed:'), findsOneWidget);
    expect(find.textContaining('No browser available'), findsOneWidget);
  });

  testWidgets('shows readable platform link open failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.uriOpener.error = PlatformException(
      code: 'ACTIVITY_NOT_FOUND',
      message: 'No browser app can open this link.',
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'platform-link-note',
            type: PaperTypes.note,
            title: 'Platform link note',
            content: '[Platform link](https://example.com/platform)',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Platform link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, ['https://example.com/platform']);
    expect(
      find.textContaining('No browser app can open this link.'),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('ACTIVITY_NOT_FOUND'), findsNothing);
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
    expect(find.text('Split'), findsOneWidget);
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

  testWidgets('drags and resizes note canvas elements like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'canvas-gesture-note',
            type: PaperTypes.note,
            title: 'Canvas gesture note',
            content: 'Main note body',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'canvas-gesture',
                text: 'Drag me',
                x: 10,
                y: 10,
                width: 120,
                height: 80,
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    final element = controller.state.papers.single.noteCanvasElements.single;
    await tester.drag(
      find.byKey(const ValueKey('note-canvas-drag-handle-canvas-gesture')),
      const Offset(40, 30),
    );
    await tester.pumpAndSettle();

    expect(element.x, 50);
    expect(element.y, 40);

    await tester.drag(
      find.byKey(const ValueKey('note-canvas-resize-handle-canvas-gesture')),
      const Offset(50, 25),
    );
    await tester.pumpAndSettle();

    expect(element.width, 170);
    expect(element.height, 105);

    await tester.drag(
      find.byKey(const ValueKey('note-canvas-resize-handle-canvas-gesture')),
      const Offset(-400, -400),
    );
    await tester.pumpAndSettle();

    expect(element.width, 72);
    expect(element.height, 48);
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

    await _enterNoteEditor(tester, 'markdown-paste-note');
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

    await _enterNoteEditor(tester, 'markdown-toolbar-note');
    await tester.tap(find.byTooltip('Insert link (Ctrl+K)'));
    await tester.pump();

    expect(controller.state.papers.single.content, 'Body[link](https://)');

    await tester.tap(find.byTooltip('Heading'));
    await tester.pump();

    expect(controller.state.papers.single.content, '# Body[link](https://)');
  });

  testWidgets('uses compact markdown toolbar actions on narrow screens',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'compact-markdown-note',
            type: PaperTypes.note,
            title: 'Compact markdown',
            content: 'Body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(
      filePath: 'build/test-widget-compact-markdown-toolbar.json',
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await _enterNoteEditor(tester, 'compact-markdown-note');
    expect(
      find.byKey(const ValueKey('compact-markdown-toolbar-actions')),
      findsOneWidget,
    );
    expect(find.byTooltip('Insert link (Ctrl+K)'), findsOneWidget);
    expect(find.byTooltip('Heading'), findsNothing);

    await tester.tap(find.byTooltip('Insert link (Ctrl+K)'));
    await tester.pump();

    expect(controller.state.papers.single.content, 'Body[link](https://)');

    await tester.tap(
      find.byKey(const ValueKey('compact-markdown-toolbar-actions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading'));
    await tester.pumpAndSettle();

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

    await _enterNoteEditor(tester, 'markdown-shortcut-note');
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

  testWidgets('saves WebDAV sync encryption passphrase', (tester) async {
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
          ),
        ),
        papers: [
          PaperData(
            id: 'sync-settings-paper',
            type: PaperTypes.todo,
            title: 'Sync settings',
            items: [
              PaperItem(id: 'sync-settings-item', text: 'Tune sync'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-sync-encryption.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sync encryption passphrase'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Sync encryption passphrase'),
      '  shared sync secret  ',
    );
    await tester.scrollUntilVisible(
      find.text('Request timeout seconds'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Request timeout seconds'),
      '4x5',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      controller.state.sync.webDav.encryptionPassphrase,
      'shared sync secret',
    );
    expect(controller.state.sync.webDav.usesEncryptedPayloads, true);
    expect(controller.state.sync.webDav.requestTimeoutSeconds, 45);
  });

  testWidgets('clamps WebDAV sync interval and timeout settings',
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
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
            autoSyncIntervalMinutes: 15,
            requestTimeoutSeconds: 30,
          ),
        ),
        papers: [
          PaperData(
            id: 'sync-numeric-settings-paper',
            type: PaperTypes.todo,
            title: 'Sync numeric settings',
            items: [
              PaperItem(
                id: 'sync-numeric-settings-item',
                text: 'Clamp sync numbers',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Interval minutes'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Interval minutes'),
      '0',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Request timeout seconds'),
      '999',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.sync.webDav.autoSyncIntervalMinutes, 1);
    expect(controller.state.sync.webDav.requestTimeoutSeconds, 300);
  });

  testWidgets('defaults blank WebDAV sync interval and timeout settings',
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
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
            autoSyncIntervalMinutes: 45,
            requestTimeoutSeconds: 90,
          ),
        ),
        papers: [
          PaperData(
            id: 'sync-blank-numeric-settings-paper',
            type: PaperTypes.todo,
            title: 'Sync blank numeric settings',
            items: [
              PaperItem(
                id: 'sync-blank-numeric-settings-item',
                text: 'Default sync numbers',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Interval minutes'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Interval minutes'),
      '',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Request timeout seconds'),
      '',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.sync.webDav.autoSyncIntervalMinutes, 15);
    expect(controller.state.sync.webDav.requestTimeoutSeconds, 30);
  });

  testWidgets('shows inline error when WebDAV passphrase is missing',
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
          ),
        ),
        papers: [
          PaperData(
            id: 'sync-passphrase-error-paper',
            type: PaperTypes.todo,
            title: 'Sync passphrase error',
            items: [
              PaperItem(
                id: 'sync-passphrase-error-item',
                text: 'Require passphrase',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sync encryption passphrase'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.text('Enter a sync encryption passphrase.'), findsOneWidget);
    expect(
      find.textContaining('Complete the WebDAV URL'),
      findsOneWidget,
    );
    expect(controller.state.sync.webDav.encryptionPassphrase, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Sync encryption passphrase'),
      'shared sync secret',
    );
    await tester.pumpAndSettle();

    expect(find.text('Enter a sync encryption passphrase.'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.sync.webDav.encryptionPassphrase,
        'shared sync secret');
  });

  testWidgets('shows inline error for whitespace WebDAV username',
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
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'sync-username-error-paper',
            type: PaperTypes.todo,
            title: 'Sync username error',
            items: [
              PaperItem(
                id: 'sync-username-error-item',
                text: 'Require username',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Username'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Username'),
      '   ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.text('Enter a WebDAV username.'), findsOneWidget);
    expect(
      find.textContaining('Complete the WebDAV URL'),
      findsOneWidget,
    );
    expect(controller.state.sync.webDav.username, 'user');
  });

  testWidgets('shows inline error for whitespace WebDAV password',
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
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'sync-password-error-paper',
            type: PaperTypes.todo,
            title: 'Sync password error',
            items: [
              PaperItem(
                id: 'sync-password-error-item',
                text: 'Require password',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Password'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      '   ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
    expect(
        find.text('Enter a WebDAV password or app password.'), findsOneWidget);
    expect(
      find.textContaining('Complete the WebDAV URL'),
      findsOneWidget,
    );
    expect(controller.state.sync.webDav.password, 'pass');
  });

  testWidgets('trims WebDAV username while preserving password on save',
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
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'sync-basic-auth-save-paper',
            type: PaperTypes.todo,
            title: 'Sync Basic Auth save',
            items: [
              PaperItem(
                id: 'sync-basic-auth-save-item',
                text: 'Keep credentials intentional',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Username'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Username'),
      ' user@example.com ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      ' app:password ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.sync.webDav.username, 'user@example.com');
    expect(controller.state.sync.webDav.password, ' app:password ');
  });

  testWidgets('shows inline error for whitespace sync passphrase',
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
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'sync-passphrase-whitespace-paper',
            type: PaperTypes.todo,
            title: 'Sync passphrase whitespace',
            items: [
              PaperItem(
                id: 'sync-passphrase-whitespace-item',
                text: 'Reject blank passphrase',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Sync encryption passphrase'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Sync encryption passphrase'),
      '   ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.text('Enter a sync encryption passphrase.'), findsOneWidget);
    expect(
      find.textContaining('Complete the WebDAV URL'),
      findsOneWidget,
    );
    expect(
      controller.state.sync.webDav.encryptionPassphrase,
      'shared sync secret',
    );
  });

  testWidgets('shows inline errors for incomplete WebDAV settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const endpointErrorText =
        'Use a full http:// or https:// WebDAV URL without user info, query, '
        'fragment, backslashes, control characters, encoded authority or path '
        'separators, blank path segments, or path segment edge spaces.';
    const rootPathErrorText =
        'Use a remote folder without parent-directory segments, invalid percent '
        'escapes, control characters, or blank path segments.';

    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'sync-field-error-paper',
            type: PaperTypes.todo,
            title: 'Sync field errors',
            items: [
              PaperItem(
                id: 'sync-field-error-item',
                text: 'Fix WebDAV fields',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'WebDAV URL'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'WebDAV URL'),
      'dav.example.test/dav',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Remote folder'),
      'RePaperTodo/%0AOther',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Username'),
      'user:name',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'bad\u007Fpass',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Sync encryption passphrase'),
      '',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.text(endpointErrorText), findsOneWidget);
    expect(find.text(rootPathErrorText), findsOneWidget);
    expect(
      find.text('Username cannot contain colons or control characters.'),
      findsOneWidget,
    );
    expect(
      find.text('Password cannot contain control characters.'),
      findsOneWidget,
    );
    expect(find.text('Enter a sync encryption passphrase.'), findsOneWidget);
    expect(
      find.textContaining('Complete the WebDAV URL'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'WebDAV URL'))
          .focusNode
          ?.hasFocus,
      true,
    );
    expect(controller.state.sync.webDav.endpoint, 'https://dav.example.test/');

    await tester.enterText(
      find.widgetWithText(TextField, 'WebDAV URL'),
      'https://dav.example.test/dav/',
    );
    await tester.pumpAndSettle();

    expect(find.text(endpointErrorText), findsNothing);
    expect(
      find.text('Username cannot contain colons or control characters.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Complete the WebDAV URL'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Remote folder'),
      '',
    );
    await tester.pumpAndSettle();
    expect(find.text(rootPathErrorText), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text(rootPathErrorText), findsOneWidget);
    expect(controller.state.sync.webDav.rootPath, 'repapertodo');
  });

  testWidgets('uses compact WebDAV preset selector on narrow screens',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'compact-webdav-paper',
            type: PaperTypes.todo,
            title: 'Compact WebDAV',
            items: [
              PaperItem(id: 'compact-webdav-item', text: 'Tune sync preset'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('compact-app-bar-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('compact-webdav-preset-selector')),
      480,
      scrollable: find.byType(Scrollable).last,
    );

    expect(
      find.byKey(const ValueKey('compact-webdav-preset-selector')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('compact-webdav-preset-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jianguoyun').last);
    await tester.pumpAndSettle();

    final urlField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'WebDAV URL'),
    );
    expect(urlField.controller?.text, 'https://dav.jianguoyun.com/dav/');
  });

  testWidgets('uses compact settings choice controls on narrow screens',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        papers: [
          PaperData(
            id: 'compact-settings-paper',
            type: PaperTypes.todo,
            title: 'Compact settings',
            items: [
              PaperItem(id: 'compact-settings-item', text: 'Tune settings'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('compact-app-bar-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-theme-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-markdown-mode-selector')),
      findsOneWidget,
    );
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Markdown mode'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-theme-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('settings-markdown-mode-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enhanced').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-reminder-unit-selector')),
      480,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-reminder-unit-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hours').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.theme, 'dark');
    expect(controller.state.markdownRenderMode, MarkdownRenderModes.enhanced);
    expect(
      controller.state.todoReminderIntervalUnit,
      TodoReminderIntervalUnits.hours,
    );
  });

  testWidgets('restores a WebDAV recovery snapshot from the toolbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
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
        pinnedTodoHotKey: 'Ctrl+Alt+L',
      ),
      platform: platform,
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
        pinnedTodoHotKey: 'Ctrl+Alt+S',
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
    expect(platform.paperWindows.restoredTitleSnapshots.last, ['Snap']);
    expect(platform.tray.rebuildTitleSnapshots.last, ['Snap']);
    expect(platform.systemIntegration.registeredHotkeys.last.$1, 'Ctrl+Alt+S');
    expect(find.text('Snapshot restored.'), findsOneWidget);
  });

  testWidgets('recovery snapshot restore failure can retry from snackbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json';
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.note,
            title: 'Local before restore retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      firstRestoreError: StateError('Temporary WebDAV restore failure'),
      snapshots: [
        WebDavSnapshotRecord(
          path: snapshotPath,
          deviceId: 'phone',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
        ),
      ],
      restoredState: AppState(
        papers: [
          PaperData(
            id: 'snapshot-paper',
            type: PaperTypes.note,
            title: 'Restored after retry',
            content: 'Recovered body',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('restore-snapshot-$snapshotPath')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.restoreCalls, 1);
    expect(controller.state.papers.single.title, 'Local before restore retry');
    expect(
      find.textContaining('Temporary WebDAV restore failure'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.restoreCalls, 2);
    expect(syncService.restoredPaths, [snapshotPath]);
    expect(controller.state.papers.single.title, 'Restored after retry');
    expect(find.text('Snapshot restored.'), findsOneWidget);
  });

  testWidgets('recovery WebDAV failure shows a readable retry message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json';
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.note,
            title: 'Local before WebDAV restore retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      firstRestoreError: const WebDavException(
        'WebDAV request failed: offline',
        statusCode: 0,
      ),
      snapshots: [
        WebDavSnapshotRecord(
          path: snapshotPath,
          deviceId: 'phone',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
        ),
      ],
      restoredState: AppState(
        papers: [
          PaperData(
            id: 'snapshot-paper',
            type: PaperTypes.note,
            title: 'Restored after WebDAV retry',
            content: 'Recovered body',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('restore-snapshot-$snapshotPath')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        find.textContaining('WebDAV request failed: offline'), findsOneWidget);
    expect(find.textContaining('WebDavException'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('recovery timeout failure shows a readable retry message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json';
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.note,
            title: 'Local before timeout restore retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      firstRestoreError: TimeoutException('Snapshot restore timed out.'),
      snapshots: [
        WebDavSnapshotRecord(
          path: snapshotPath,
          deviceId: 'phone',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
        ),
      ],
      restoredState: controller.state,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('restore-snapshot-$snapshotPath')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Snapshot restore timed out.'), findsOneWidget);
    expect(find.textContaining('TimeoutException'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('recovery state store failure shows a readable retry message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json';
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'local-paper',
            type: PaperTypes.note,
            title: 'Local before store restore retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      firstRestoreError: const StateStoreException(
        'Unable to save restored PaperTodo state.',
        FormatException('Broken restored JSON.'),
      ),
      snapshots: [
        WebDavSnapshotRecord(
          path: snapshotPath,
          deviceId: 'phone',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
        ),
      ],
      restoredState: controller.state,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('restore-snapshot-$snapshotPath')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.restoreCalls, 1);
    expect(
      find.textContaining('Unable to save restored PaperTodo state.'),
      findsOneWidget,
    );
    expect(find.textContaining('Cause:'), findsNothing);
    expect(find.textContaining('Broken restored JSON'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('recovery snapshots require complete WebDAV settings',
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
          ),
        ),
        papers: [
          PaperData(
            id: 'recovery-config-paper',
            type: PaperTypes.todo,
            title: 'Recovery config',
            items: [
              PaperItem(
                id: 'recovery-config-item',
                text: 'Configure sync first',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Recovery snapshots'), findsNothing);
    expect(
      find.text(
          'Complete WebDAV sync settings and encryption passphrase first.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
  });

  testWidgets('recovery snapshots retry after list failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260701T090000000Z-laptop.json';
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'recovery-retry-paper',
            type: PaperTypes.todo,
            title: 'Recovery retry',
            items: [
              PaperItem(
                id: 'recovery-retry-item',
                text: 'Retry snapshot loading',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      firstListError: StateError('Temporary WebDAV outage'),
      snapshots: [
        WebDavSnapshotRecord(
          path: snapshotPath,
          deviceId: 'laptop',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 10),
          contentLength: 1024,
        ),
      ],
      restoredState: AppState(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();

    expect(syncService.listCalls, 1);
    expect(find.text('Recovery snapshots'), findsOneWidget);
    expect(find.textContaining('Temporary WebDAV outage'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('retry-recovery-snapshots')),
      findsOneWidget,
    );
    expect(find.text(snapshotPath), findsNothing);

    await tester.tap(find.byKey(const ValueKey('retry-recovery-snapshots')));
    await tester.pumpAndSettle();

    expect(syncService.listCalls, 2);
    expect(find.textContaining('Temporary WebDAV outage'), findsNothing);
    expect(find.textContaining(snapshotPath), findsOneWidget);
    expect(find.textContaining('1.0 KiB'), findsOneWidget);
  });

  testWidgets('recovery snapshot WebDAV list failure shows a readable message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260701T110000000Z-tablet.json';
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'recovery-webdav-list-paper',
            type: PaperTypes.todo,
            title: 'Recovery WebDAV list',
            items: [
              PaperItem(
                id: 'recovery-webdav-list-item',
                text: 'Retry readable snapshot loading',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      firstListError: const WebDavException(
        'WebDAV provider is temporarily unavailable. Try again later. Retry after 2026-07-01T09:01:00.000Z.',
        statusCode: 503,
      ),
      snapshots: [
        WebDavSnapshotRecord(
          path: snapshotPath,
          deviceId: 'tablet',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 11),
        ),
      ],
      restoredState: AppState(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();

    expect(syncService.listCalls, 1);
    expect(
      find.textContaining('WebDAV provider is temporarily unavailable.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Retry after 2026-07-01T09:01:00.000Z.'),
      findsOneWidget,
    );
    expect(find.textContaining('WebDavException'), findsNothing);
    expect(
      find.byKey(const ValueKey('retry-recovery-snapshots')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('retry-recovery-snapshots')));
    await tester.pumpAndSettle();

    expect(syncService.listCalls, 2);
    expect(
      find.textContaining('WebDAV provider is temporarily unavailable.'),
      findsNothing,
    );
    expect(find.textContaining(snapshotPath), findsOneWidget);
  });

  testWidgets('recovery snapshot format list failure shows a readable message',
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
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'recovery-format-list-paper',
            type: PaperTypes.todo,
            title: 'Recovery format list',
            items: [
              PaperItem(
                id: 'recovery-format-list-item',
                text: 'Retry malformed snapshot loading',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      firstListError: const FormatException('Malformed snapshot index.'),
      snapshots: const <WebDavSnapshotRecord>[],
      restoredState: AppState(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();

    expect(syncService.listCalls, 1);
    expect(find.textContaining('Malformed snapshot index.'), findsOneWidget);
    expect(find.textContaining('FormatException'), findsNothing);
    expect(
      find.byKey(const ValueKey('retry-recovery-snapshots')),
      findsOneWidget,
    );
  });

  testWidgets('recovery snapshot unreadable payload opens sync settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final localState = AppState(
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings(
          endpoint: 'https://dav.example.test/',
          username: 'user',
          password: 'pass',
          encryptionPassphrase: 'shared sync secret',
          rootPath: 'repapertodo',
        ),
      ),
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
    );
    final controller = RePaperTodoController(
      initialState: localState,
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      snapshots: [
        WebDavSnapshotRecord(
          path: 'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json',
          deviceId: 'phone',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
        ),
      ],
      restoredState: localState,
      restoreStatus: AppSyncStatus.payloadUnreadable,
      restoreMessage:
          'Unable to decrypt WebDAV sync payload. Check the sync encryption passphrase.',
      includeRestoredState: false,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(
        'restore-snapshot-repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.papers.single.title, 'Local');
    expect(
      find.textContaining('Check the sync encryption passphrase'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
  });

  testWidgets('recovery snapshot malformed encrypted payload keeps message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final localState = AppState(
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings(
          endpoint: 'https://dav.example.test/',
          username: 'user',
          password: 'pass',
          encryptionPassphrase: 'shared sync secret',
          rootPath: 'repapertodo',
        ),
      ),
      papers: [
        PaperData(id: 'local-paper', type: PaperTypes.todo, title: 'Local'),
      ],
    );
    final controller = RePaperTodoController(
      initialState: localState,
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      snapshots: [
        WebDavSnapshotRecord(
          path: 'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json',
          deviceId: 'phone',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
        ),
      ],
      restoredState: localState,
      restoreStatus: AppSyncStatus.payloadUnreadable,
      restoreMessage:
          'Encrypted WebDAV sync payload is unsupported or corrupted.',
      includeRestoredState: false,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(
        'restore-snapshot-repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.papers.single.title, 'Local');
    expect(find.textContaining('unsupported or corrupted'), findsOneWidget);
    expect(find.textContaining('Check the sync encryption passphrase'),
        findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);
  });

  testWidgets('uses compact recovery snapshot rows on narrow screens',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json';
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            encryptionPassphrase: 'shared sync secret',
            rootPath: 'repapertodo',
          ),
        ),
        papers: [
          PaperData(
            id: 'compact-recovery-paper',
            type: PaperTypes.todo,
            title: 'Compact recovery',
            items: [
              PaperItem(
                id: 'compact-recovery-item',
                text: 'Open recovery snapshots',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      snapshots: [
        WebDavSnapshotRecord(
          path: snapshotPath,
          deviceId: 'phone',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
          contentLength: 4096,
        ),
      ],
      restoredState: AppState(
        papers: [
          PaperData(
            id: 'compact-recovery-paper',
            type: PaperTypes.todo,
            title: 'Compact recovery',
            items: [
              PaperItem(
                id: 'compact-recovery-item',
                text: 'Open recovery snapshots',
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('compact-app-bar-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recovery snapshots'));
    await tester.pumpAndSettle();

    final restoreButton = find.byKey(
      const ValueKey('restore-snapshot-$snapshotPath'),
    );
    expect(find.text('Recovery snapshots'), findsOneWidget);
    expect(find.text(snapshotPath), findsOneWidget);
    expect(find.text('4.0 KiB'), findsOneWidget);
    expect(tester.getSize(restoreButton).width, greaterThan(200));
    expect(
      tester.getTopLeft(restoreButton).dy,
      greaterThan(tester.getBottomLeft(find.text(snapshotPath)).dy),
    );

    await tester.tap(restoreButton);
    await tester.pumpAndSettle();

    expect(find.text('Restore snapshot?'), findsOneWidget);
  });

  testWidgets('manual sync merges remote operation logs from the toolbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
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
        pinnedTodoHotKey: 'Ctrl+Alt+L',
      ),
      platform: platform,
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
      pinnedTodoHotKey: 'Ctrl+Alt+R',
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
    expect(platform.paperWindows.restoredTitleSnapshots.last, ['Remote']);
    expect(platform.tray.rebuildTitleSnapshots.last, ['Remote']);
    expect(platform.systemIntegration.registeredHotkeys.last.$1, 'Ctrl+Alt+R');
    expect(
      find.text('Remote data downloaded. Merged 1 remote change.'),
      findsOneWidget,
    );
  });

  testWidgets('manual sync reports legacy operation log migration',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final syncedState = AppState(
      papers: [
        PaperData(
          id: 'remote-note',
          type: PaperTypes.note,
          title: 'Remote',
          content: 'Merged legacy op',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'local-note', type: PaperTypes.note, title: 'Local'),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-sync-legacy-ops.json');
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
          deviceSequences: const {'device-a': 1},
          appliedCount: 1,
          legacyPlainOperationLogCount: 1,
          legacyPlainOperationLogMigratedCount: 1,
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

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.content, 'Merged legacy op');
    expect(
      find.textContaining('Migrated 1 legacy WebDAV operation log'),
      findsOneWidget,
    );
    expect(find.textContaining('encrypted payloads'), findsOneWidget);
  });

  testWidgets('manual sync reports unreadable encrypted payloads',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final localState = AppState(
      papers: [
        PaperData(
          id: 'local-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: localState,
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-sync-unreadable.json');
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.payloadUnreadable,
          state: localState,
          message:
              'Unable to decrypt WebDAV sync payload. Check the sync encryption passphrase.',
        ),
        state: localState,
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
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Local');
    expect(
      find.textContaining('Check the sync encryption passphrase'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.textContaining('Sync failed:'), findsNothing);
  });

  testWidgets('manual sync keeps malformed encrypted payload messages',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final localState = AppState(
      papers: [
        PaperData(
          id: 'local-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: localState,
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-sync-malformed-encrypted.json');
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.payloadUnreadable,
          state: localState,
          message: 'Encrypted WebDAV sync payload is unsupported or corrupted.',
        ),
        state: localState,
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
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Local');
    expect(find.textContaining('unsupported or corrupted'), findsOneWidget);
    expect(find.textContaining('Check the sync encryption passphrase'),
        findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);
    expect(find.textContaining('Sync failed:'), findsNothing);
  });

  testWidgets('manual sync failure can retry from snackbar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final syncedState = AppState(
      papers: [
        PaperData(
          id: 'retry-note',
          type: PaperTypes.note,
          title: 'Synced after retry',
          content: 'Retry succeeded',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'retry-note',
            type: PaperTypes.note,
            title: 'Local before retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _ManualSyncService(
      firstSyncError: StateError('Temporary network failure'),
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
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Local before retry');
    expect(find.textContaining('Temporary network failure'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 2);
    expect(controller.state.papers.single.title, 'Synced after retry');
    expect(find.text('Remote data downloaded.'), findsOneWidget);
  });

  testWidgets('manual WebDAV failure shows a readable retry message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'webdav-failure-note',
            type: PaperTypes.note,
            title: 'Local before WebDAV retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _ManualSyncService(
      firstSyncError: const WebDavException(
        'WebDAV provider rate limit reached. Try again later. Retry after 120 seconds.',
        statusCode: 429,
      ),
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          message: 'Local data uploaded.',
        ),
        state: controller.state,
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('WebDAV provider rate limit reached.'),
      findsOneWidget,
    );
    expect(find.textContaining('Retry after 120 seconds.'), findsOneWidget);
    expect(find.textContaining('WebDavException'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('manual format failure shows a readable retry message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'format-failure-note',
            type: PaperTypes.note,
            title: 'Local before format retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _ManualSyncService(
      firstSyncError: const FormatException('Malformed remote sync manifest.'),
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          message: 'Local data uploaded.',
        ),
        state: controller.state,
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('Malformed remote sync manifest.'),
      findsOneWidget,
    );
    expect(find.textContaining('FormatException'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('manual state store failure shows a readable retry message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'store-failure-note',
            type: PaperTypes.note,
            title: 'Local before store retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _ManualSyncService(
      firstSyncError: const StateStoreException(
        'Unable to load PaperTodo state.',
        FormatException('Broken local JSON.'),
      ),
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          message: 'Local data uploaded.',
        ),
        state: controller.state,
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('Unable to load PaperTodo state.'),
      findsOneWidget,
    );
    expect(find.textContaining('Cause:'), findsNothing);
    expect(find.textContaining('Broken local JSON'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('manual timeout failure shows a readable retry message',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'timeout-failure-note',
            type: PaperTypes.note,
            title: 'Local before timeout retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _ManualSyncService(
      firstSyncError: TimeoutException('Remote sync timed out.'),
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          message: 'Local data uploaded.',
        ),
        state: controller.state,
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Remote sync timed out.'), findsOneWidget);
    expect(find.textContaining('TimeoutException'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('manual sync conflict opens recovery snapshots from snackbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const snapshotPath =
        'repapertodo/snapshots/snapshot-20260701T090000000Z-laptop.json';
    final initialState = AppState(
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings(
          endpoint: 'https://dav.example.test/',
          username: 'user',
          password: 'pass',
          encryptionPassphrase: 'shared sync secret',
          rootPath: 'repapertodo',
        ),
      ),
      papers: [
        PaperData(
          id: 'conflict-note',
          type: PaperTypes.note,
          title: 'Local conflict',
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
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: const AppSyncResult(
          status: AppSyncStatus.conflict,
          message:
              'Remote data changed during sync. Local snapshot preserved at repapertodo/snapshots/conflict-local.json.',
          snapshotPath: 'repapertodo/snapshots/conflict-local.json',
        ),
        state: initialState,
      ),
      recoverySnapshots: [
        WebDavSnapshotRecord(
          path: snapshotPath,
          deviceId: 'laptop',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 9),
          contentLength: 4096,
        ),
      ],
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
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 1);
    expect(find.textContaining('Local snapshot preserved'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Recovery'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Recovery'));
    await tester.pumpAndSettle();

    expect(syncService.listRecoveryCalls, 1);
    expect(find.text('Recovery snapshots'), findsOneWidget);
    expect(find.textContaining(snapshotPath), findsOneWidget);
    expect(find.textContaining('4.0 KiB'), findsOneWidget);
  });

  testWidgets('manual sync reports legacy plain WebDAV migration state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final syncedState = AppState(
      papers: [
        PaperData(
          id: 'remote-note',
          type: PaperTypes.note,
          title: 'Remote',
          content: 'Downloaded before migration',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'local-note', type: PaperTypes.note, title: 'Local'),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-sync-legacy-plain.json');
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: syncedState,
          message:
              'Remote data downloaded from legacy plain WebDAV data and migrated to encrypted payloads.',
          legacyPlainPayloadDetected: true,
          legacyPlainPayloadMigrated: true,
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

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Remote');
    expect(find.textContaining('legacy plain WebDAV data'), findsOneWidget);
    expect(find.textContaining('encrypted payloads'), findsOneWidget);
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
        encryptionPassphrase: 'shared sync secret',
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
    final platform = _RecordingPlatformServices();
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
    expect(platform.paperWindows.restoredTitleSnapshots, [
      ['Draft'],
      ['Synced'],
    ]);
    expect(platform.tray.rebuildTitleSnapshots.last, ['Synced']);
    expect(find.text('Remote data downloaded.'), findsOneWidget);
  });

  testWidgets('manual sync keeps malformed local upload payload messages',
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
        encryptionPassphrase: 'shared sync secret',
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
          title: 'Synced after retry',
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
      firstLocalUploadError: const WebDavPayloadDecryptionException(
        'Encrypted WebDAV sync payload is unsupported or corrupted.',
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

    expect(syncService.events, ['upload']);
    expect(syncService.localUploadCalls, 1);
    expect(syncService.calls, 0);
    expect(controller.state.papers.single.title, 'Draft');
    expect(find.textContaining('Sync failed:'), findsOneWidget);
    expect(find.textContaining('unsupported or corrupted'), findsOneWidget);
    expect(find.textContaining('Check the sync encryption passphrase'),
        findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['upload', 'upload', 'sync']);
    expect(syncService.localUploadCalls, 2);
    expect(syncService.calls, 1);
    expect(syncService.localUploadBeforeTitles, ['Local', 'Local']);
    expect(syncService.localUploadAfterTitles, ['Draft', 'Draft']);
    expect(controller.state.papers.single.title, 'Synced after retry');
    expect(find.text('Remote data downloaded.'), findsOneWidget);
  });

  testWidgets('manual sync refreshes state after idempotent local upload',
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
        encryptionPassphrase: 'shared sync secret',
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
    final uploadedState = AppState(
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
    );
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: initialState,
      platform: platform,
    );
    final store = _MemoryStateStore();
    await store.save(initialState);
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: uploadedState,
          message: 'Local data uploaded.',
        ),
        state: uploadedState,
      ),
      localUploadState: uploadedState,
      localUploadUploadedCount: 0,
      localUploadStateChanged: true,
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
    expect(syncService.syncLocalDeviceSequences, [
      {'device-a': 1},
    ]);
    expect(controller.state.sync.operationDeviceSequences, {'device-a': 1});
    expect(platform.paperWindows.restoredTitleSnapshots.first, ['Draft']);
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
            encryptionPassphrase: 'shared sync secret',
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
        encryptionPassphrase: 'shared sync secret',
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
        encryptionPassphrase: 'shared sync secret',
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

  testWidgets('local edits retry after silent upload failure', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final syncSettings = SyncSettings(
      enabled: true,
      provider: SyncProviderIds.webDav,
      webDav: WebDavSyncSettings(
        endpoint: 'https://dav.example.test/',
        username: 'user',
        password: 'pass',
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'retry-note',
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
          id: 'retry-note',
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
      firstLocalUploadError: const WebDavPayloadDecryptionException(
        'Encrypted WebDAV sync payload is unsupported or corrupted.',
      ),
      localUploadState: AppState(
        sync: syncSettings.copy()
          ..operationDeviceSequences = const {'device-a': 1},
        papers: [
          PaperData(
            id: 'retry-note',
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
      find.byKey(const ValueKey('retry-note-title')),
      'One',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(syncService.events, ['upload']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['One']);
    expect(syncService.calls, 0);
    expect(controller.state.papers.single.title, 'One');
    expect(find.textContaining('unsupported or corrupted'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('retry-note-title')),
      'Two',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(syncService.events, ['upload', 'upload', 'sync']);
    expect(syncService.localUploadCalls, 2);
    expect(syncService.localUploadBeforeTitles, ['Local', 'Local']);
    expect(syncService.localUploadAfterTitles, ['One', 'Two']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
    expect(find.text('Local data uploaded.'), findsNothing);
  });

  testWidgets('manual sync retries pending edits after silent upload failure',
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
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'manual-retry-note',
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
          id: 'manual-retry-note',
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
      firstLocalUploadError: const WebDavPayloadDecryptionException(
        'Encrypted WebDAV sync payload is unsupported or corrupted.',
      ),
      localUploadState: AppState(
        sync: syncSettings.copy()
          ..operationDeviceSequences = const {'device-a': 1},
        papers: [
          PaperData(
            id: 'manual-retry-note',
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
      find.byKey(const ValueKey('manual-retry-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(syncService.events, ['upload']);
    expect(syncService.calls, 0);
    expect(controller.state.papers.single.title, 'Draft');
    expect(find.textContaining('unsupported or corrupted'), findsNothing);

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['upload', 'upload', 'sync']);
    expect(syncService.localUploadCalls, 2);
    expect(syncService.calls, 1);
    expect(syncService.localUploadBeforeTitles, ['Local', 'Local']);
    expect(syncService.localUploadAfterTitles, ['Draft', 'Draft']);
    expect(controller.state.papers.single.title, 'Synced');
    expect(find.text('Remote data downloaded.'), findsOneWidget);
    expect(find.textContaining('Sync failed:'), findsNothing);
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
        encryptionPassphrase: 'shared sync secret',
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
        encryptionPassphrase: 'shared sync secret',
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
    expect(platform.systemIntegration.exitApplicationCount, 1);
    expect(platform.tray.disposeCount, 1);
    expect(find.text('Local data uploaded.'), findsNothing);
  });

  testWidgets('exit command continues cleanup when local edit sync fails',
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
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'exit-failure-note',
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
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: initialState,
          message: 'Local data uploaded.',
        ),
        state: initialState,
      ),
      firstLocalUploadError: const WebDavPayloadDecryptionException(
        'Encrypted WebDAV sync payload is unsupported or corrupted.',
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

    expect(syncService.events, ['upload']);
    expect(syncService.localUploadCalls, 1);
    expect(syncService.calls, 0);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect((await store.load()).papers.single.title, 'Draft');
    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.systemIntegration.exitApplicationCount, 1);
    expect(platform.tray.disposeCount, 1);
    expect(find.textContaining('unsupported or corrupted'), findsNothing);
    expect(find.textContaining('Sync failed:'), findsNothing);
  });

  testWidgets('exit command saves local edits without sync when disabled',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final startup = _RecordingStartupHost();
    final platform = _RecordingPlatformServices(startup: startup);
    final initialState = AppState(
      sync: SyncSettings(
        enabled: false,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings(
          endpoint: 'https://dav.example.test/',
          username: 'user',
          password: 'pass',
          encryptionPassphrase: 'shared sync secret',
          rootPath: 'repapertodo',
          autoSyncIntervalMinutes: 15,
        ),
      ),
      papers: [
        PaperData(
          id: 'exit-disabled-note',
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
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: initialState,
          message: 'Local data uploaded.',
        ),
        state: initialState,
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

    expect(syncService.localUploadCalls, 0);
    expect(syncService.calls, 0);
    expect((await store.load()).papers.single.title, 'Draft');
    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.systemIntegration.exitApplicationCount, 1);
    expect(platform.tray.disposeCount, 1);
    expect(find.text('Local data uploaded.'), findsNothing);
    expect(find.textContaining('Sync failed:'), findsNothing);
  });

  testWidgets('disabling sync clears pending local edit uploads',
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
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'disable-sync-note',
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
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: initialState,
          message: 'Local data uploaded.',
        ),
        state: initialState,
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
      find.byKey(const ValueKey('disable-sync-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('WebDAV sync'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('WebDAV sync'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.sync.enabled, false);
    expect(syncService.localUploadCalls, 0);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('WebDAV sync'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('WebDAV sync'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.sync.enabled, true);
    expect(syncService.localUploadCalls, 0);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(syncService.localUploadCalls, 0);
    expect(syncService.calls, 0);
    expect(controller.state.papers.single.title, 'Draft');
    expect(find.text('Local data uploaded.'), findsNothing);
  });

  testWidgets('canceling settings restores pending local edit upload',
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
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'cancel-settings-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'cancel-settings-note',
          type: PaperTypes.note,
          title: 'Synced',
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
            id: 'cancel-settings-note',
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
      find.byKey(const ValueKey('cancel-settings-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(syncService.events, ['upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
    expect(find.text('Local data uploaded.'), findsNothing);
  });

  testWidgets('non-sync settings save restores pending local edit upload',
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
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'non-sync-settings-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final syncedState = AppState(
      sync: syncSettings.copy(),
      customThemeColorHex: '#336699',
      papers: [
        PaperData(
          id: 'non-sync-settings-note',
          type: PaperTypes.note,
          title: 'Synced',
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
        customThemeColorHex: '#336699',
        papers: [
          PaperData(
            id: 'non-sync-settings-note',
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
      find.byKey(const ValueKey('non-sync-settings-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Custom theme color'),
      '336699',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(controller.state.customThemeColorHex, '#336699');
    expect(syncService.events, ['upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
    expect(find.text('Local data uploaded.'), findsNothing);
  });

  testWidgets('unchanged sync settings save restores pending local edit upload',
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
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'unchanged-sync-settings-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'unchanged-sync-settings-note',
          type: PaperTypes.note,
          title: 'Synced',
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
            id: 'unchanged-sync-settings-note',
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
      find.byKey(const ValueKey('unchanged-sync-settings-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(syncService.events, ['upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
    expect(find.text('Local data uploaded.'), findsNothing);
  });

  testWidgets('platform setting failure preserves pending local edit upload',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.systemIntegration.registerGlobalHotkeysError =
        StateError('Hotkey registration failed');
    final syncSettings = SyncSettings(
      enabled: true,
      provider: SyncProviderIds.webDav,
      webDav: WebDavSyncSettings(
        endpoint: 'https://dav.example.test/',
        username: 'user',
        password: 'pass',
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      pinnedTodoHotKey: '',
      papers: [
        PaperData(
          id: 'platform-failure-pending-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final syncedState = AppState(
      sync: syncSettings.copy(),
      pinnedTodoHotKey: 'Ctrl+Alt+T',
      papers: [
        PaperData(
          id: 'platform-failure-pending-note',
          type: PaperTypes.note,
          title: 'Synced',
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
        pinnedTodoHotKey: 'Ctrl+Alt+T',
        papers: [
          PaperData(
            id: 'platform-failure-pending-note',
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
      find.byKey(const ValueKey('platform-failure-pending-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Pinned todo hotkey'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Pinned todo hotkey'),
      'Ctrl+Alt+T',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.pinnedTodoHotKey, 'Ctrl+Alt+T');
    expect(platform.systemIntegration.registeredHotkeys, isEmpty);
    expect(find.textContaining('Platform settings failed:'), findsOneWidget);
    expect(find.textContaining('Hotkey registration failed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(syncService.events, ['upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.calls, 1);
    expect(controller.state.pinnedTodoHotKey, 'Ctrl+Alt+T');
    expect(controller.state.papers.single.title, 'Synced');
    expect(find.text('Local data uploaded.'), findsNothing);
  });

  testWidgets('settings save failure does not block later local edit upload',
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
        encryptionPassphrase: 'shared sync secret',
        rootPath: 'repapertodo',
        autoSyncIntervalMinutes: 15,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      customThemeColorHex: '#112233',
      papers: [
        PaperData(
          id: 'settings-save-failure-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final syncedState = AppState(
      sync: syncSettings.copy(),
      customThemeColorHex: '#336699',
      papers: [
        PaperData(
          id: 'settings-save-failure-note',
          type: PaperTypes.note,
          title: 'Synced',
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
        customThemeColorHex: '#336699',
        papers: [
          PaperData(
            id: 'settings-save-failure-note',
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

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Custom theme color'),
      '336699',
    );
    store.nextSaveError =
        const StateStoreException('settings save failed', 'disk full');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Settings save failed:'), findsOneWidget);
    expect(find.textContaining('settings save failed'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('settings-save-failure-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(syncService.events, ['upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
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
    await tester.pump();
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
        '${Platform.pathSeparator}RePaperTodo${Platform.pathSeparator}exports${Platform.pathSeparator}paper-external-note.txt',
      ),
    );
    expect(openedFile.readAsStringSync(), '# Exported note\n\nMarkdown body.');
    expect(find.textContaining('Opened markdown file:'), findsOneWidget);
  });

  testWidgets('sanitizes long external markdown export names', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longPaperId =
        '${List.filled(90, 'a').join()}/bad:${List.filled(65, 'z').join()}\u007Ftail';
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: longPaperId,
            type: PaperTypes.note,
            title: 'Long export name',
            content: '# Long export',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.file_open_outlined));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.externalFiles.openedPaths, hasLength(1));
    final openedFile = File(platform.externalFiles.openedPaths.single);
    final fileName = openedFile.path.split(Platform.pathSeparator).last;
    expect(fileName.length, lessThanOrEqualTo('paper-'.length + 96 + 3));
    expect(fileName, startsWith('paper-${List.filled(72, 'a').join()}_'));
    expect(fileName, endsWith('.md'));
    expect(fileName, isNot(contains(RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]'))));
    expect(openedFile.readAsStringSync(), '# Long export');
  });

  testWidgets('cleans stale external markdown exports before writing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final exportDirectory = Directory(
      [
        Directory('build/test-widget-storage').absolute.path,
        'RePaperTodo',
        'exports',
      ].join(Platform.pathSeparator),
    );
    if (exportDirectory.existsSync()) {
      exportDirectory.deleteSync(recursive: true);
    }
    exportDirectory.createSync(recursive: true);
    addTearDown(() {
      if (exportDirectory.existsSync()) {
        exportDirectory.deleteSync(recursive: true);
      }
    });

    final staleExport = File(
      '${exportDirectory.path}${Platform.pathSeparator}paper-stale.md',
    )..writeAsStringSync('old');
    final freshExport = File(
      '${exportDirectory.path}${Platform.pathSeparator}paper-fresh.md',
    )..writeAsStringSync('fresh');
    final userFile = File(
      '${exportDirectory.path}${Platform.pathSeparator}manual-stale.md',
    )..writeAsStringSync('keep');
    final oldTimestamp = DateTime.now().subtract(const Duration(days: 9));
    staleExport.setLastModifiedSync(oldTimestamp);
    userFile.setLastModifiedSync(oldTimestamp);

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'cleanup-note',
            type: PaperTypes.note,
            title: 'Cleanup Note',
            content: '# Cleanup',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.file_open_outlined));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(staleExport.existsSync(), false);
    expect(freshExport.existsSync(), true);
    expect(userFile.existsSync(), true);
    expect(platform.externalFiles.openedPaths, hasLength(1));
    expect(File(platform.externalFiles.openedPaths.single).readAsStringSync(),
        '# Cleanup');
  });

  testWidgets('shows readable external markdown open failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.externalFiles.error = PlatformException(
      code: 'NO_VIEWER',
      message: 'No app can open exported markdown.',
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'external-note-failure',
            type: PaperTypes.note,
            title: 'External Note Failure',
            content: '# Exported note',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.file_open_outlined));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.externalFiles.openedPaths, hasLength(1));
    expect(
      find.textContaining('No app can open exported markdown.'),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('NO_VIEWER'), findsNothing);
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

  testWidgets('deleting a todo paper closes its active reminders',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 30,
        papers: [
          PaperData(
            id: 'delete-reminder-paper',
            type: PaperTypes.todo,
            title: 'Reminder paper',
            items: [
              PaperItem(
                id: 'delete-reminder-item',
                text: 'Review before delete',
                dueAtLocal: DateTime.now()
                    .subtract(const Duration(minutes: 1))
                    .toIso8601String(),
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );
    await tester.pump();

    expect(
      find.text('Reminder: Remind - Review before delete'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Delete paper'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Reminder: Remind - Review before delete'), findsNothing);
    expect(controller.state.papers.single.id, isNot('delete-reminder-paper'));
    expect(controller.state.papers.single.type, PaperTypes.todo);
  });

  testWidgets('shows one-shot reminders before todo due time', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: false,
        todoReminderBubbleDurationSeconds: 5,
        papers: [
          PaperData(
            id: 'future-reminder-paper',
            type: PaperTypes.todo,
            title: 'Soon',
            items: [
              PaperItem(
                id: 'future-reminder-item',
                text: 'Submit paper',
                dueAtLocal: DateTime.now()
                    .add(const Duration(minutes: 5))
                    .toIso8601String(),
              ),
              PaperItem(
                id: 'too-far-reminder-item',
                text: 'Too far away',
                dueAtLocal: DateTime.now()
                    .add(const Duration(minutes: 20))
                    .toIso8601String(),
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );
    await tester.pump();

    expect(find.text('Reminder: Soon - Submit paper'), findsOneWidget);
    expect(find.text('Reminder: Soon - Too far away'), findsNothing);
  });

  testWidgets('nearest todo reminder uses absolute due-time distance',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 10,
        todoReminderScope: TodoReminderScopes.nearest,
        todoReminderBubbleDurationSeconds: 5,
        papers: [
          PaperData(
            id: 'nearest-reminder-paper',
            type: PaperTypes.todo,
            title: 'Paper',
            items: [
              PaperItem(
                id: 'far-overdue-reminder-item',
                text: 'Far task',
                dueAtLocal:
                    now.subtract(const Duration(minutes: 9)).toIso8601String(),
              ),
              PaperItem(
                id: 'near-overdue-reminder-item',
                text: 'Near task',
                dueAtLocal:
                    now.subtract(const Duration(minutes: 1)).toIso8601String(),
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );
    await tester.pump();

    expect(find.text('Reminder: Paper - Near task'), findsOneWidget);
    expect(find.text('Reminder: Paper - Far task'), findsNothing);
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

    final now = DateTime.now();
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
                text: 'Due soon',
                dueAtLocal:
                    now.add(const Duration(minutes: 5)).toIso8601String(),
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

    expect(find.text('Due in 5m'), findsOneWidget);
  });

  testWidgets('formats relative todo due durations like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final controller = RePaperTodoController(
      initialState: AppState(
        showTodoDueRelativeTime: true,
        papers: [
          PaperData(
            id: 'relative-duration-paper',
            type: PaperTypes.todo,
            title: 'Relative duration paper',
            items: [
              PaperItem(
                id: 'relative-future',
                text: 'Future',
                dueAtLocal: now
                    .add(const Duration(hours: 2, minutes: 5))
                    .toIso8601String(),
              ),
              PaperItem(
                id: 'relative-past',
                text: 'Past',
                order: 1,
                dueAtLocal: now
                    .subtract(
                      const Duration(hours: 1, minutes: 2, seconds: 1),
                    )
                    .toIso8601String(),
              ),
              PaperItem(
                id: 'relative-soon',
                text: 'Soon',
                order: 2,
                dueAtLocal:
                    now.add(const Duration(seconds: 10)).toIso8601String(),
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-relative-duration-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Due in 2h5m'), findsOneWidget);
    expect(find.text('Due 1h3m overdue'), findsOneWidget);
    expect(find.text('Due in 1m'), findsOneWidget);
  });

  testWidgets('sets todo due date with hour and minute like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'due-time-paper',
            type: PaperTypes.todo,
            title: 'Due time paper',
            items: [
              PaperItem(
                id: 'due-time-item',
                text: 'Timed task',
                dueAtLocal: '2026-06-30T09:15:00',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-due-time-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Due 06-30 09:15'), findsOneWidget);

    await tester.tap(find.byTooltip('Set due date'));
    await tester.pumpAndSettle();

    tester
        .widget<DropdownButtonFormField<int>>(
          find.byKey(const ValueKey('todo-due-hour')),
        )
        .onChanged
        ?.call(10);
    await tester.pump();

    tester
        .widget<DropdownButtonFormField<int>>(
          find.byKey(const ValueKey('todo-due-minute')),
        )
        .onChanged
        ?.call(30);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.dueAtLocal, '2026-06-30T10:30:00');
    expect(find.text('Due 06-30 10:30'), findsOneWidget);
  });

  testWidgets('formats absolute todo due times like PaperTodo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final later = today.add(const Duration(days: 2));
    final laterMonth = later.month.toString().padLeft(2, '0');
    final laterDay = later.day.toString().padLeft(2, '0');
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'due-format-paper',
            type: PaperTypes.todo,
            title: 'Due format paper',
            items: [
              PaperItem(
                id: 'due-today',
                text: 'Due today',
                dueAtLocal: DateTime(
                  today.year,
                  today.month,
                  today.day,
                  10,
                  5,
                ).toIso8601String(),
              ),
              PaperItem(
                id: 'due-tomorrow',
                text: 'Due tomorrow',
                order: 1,
                dueAtLocal: DateTime(
                  tomorrow.year,
                  tomorrow.month,
                  tomorrow.day,
                  11,
                  10,
                ).toIso8601String(),
              ),
              PaperItem(
                id: 'due-later',
                text: 'Due later',
                order: 2,
                dueAtLocal: DateTime(
                  later.year,
                  later.month,
                  later.day,
                  12,
                  15,
                ).toIso8601String(),
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-due-format-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Due 10:05'), findsOneWidget);
    expect(find.text('Due Tomorrow 11:10'), findsOneWidget);
    expect(find.text('Due $laterMonth-$laterDay 12:15'), findsOneWidget);
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

  testWidgets('inserts and deletes todo columns like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'column-shift-paper',
            type: PaperTypes.todo,
            title: 'Column shift paper',
            items: [
              PaperItem(
                id: 'column-shift-item',
                text: 'Title',
                todoColumnCount: 2,
                todoExtraColumns: ['Status'],
                todoColumnWidths: [2, 1],
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-todo-column-shift.json');

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
        (widget) =>
            widget is PopupMenuItem<String> &&
            widget.value == 'insert-before:0',
      ),
    );
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.text, '');
    expect(item.todoColumnCount, 3);
    expect(item.todoExtraColumns, ['Title', 'Status']);
    expect(item.todoColumnWidths, [1, 2, 1]);

    await tester.tap(find.byTooltip('Todo columns'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<String> && widget.value == 'delete:0',
      ),
    );
    await tester.pumpAndSettle();

    expect(item.text, 'Title');
    expect(item.todoColumnCount, 2);
    expect(item.todoExtraColumns, ['Status']);
    expect(item.todoColumnWidths, [2, 1]);

    await tester.tap(find.byTooltip('Todo columns'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<String> &&
            widget.value == 'insert-before:1',
      ),
    );
    await tester.pumpAndSettle();

    expect(item.text, 'Title');
    expect(item.todoColumnCount, 3);
    expect(item.todoExtraColumns, ['', 'Status']);
    expect(item.todoColumnWidths, [2, 1, 1]);

    await tester.tap(find.byTooltip('Todo columns'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<String> && widget.value == 'delete:1',
      ),
    );
    await tester.pumpAndSettle();

    expect(item.text, 'Title');
    expect(item.todoColumnCount, 2);
    expect(item.todoExtraColumns, ['Status']);
    expect(item.todoColumnWidths, [2, 1]);
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

  testWidgets('inserts todo items after the focused row from keyboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'keyboard-paper',
            type: PaperTypes.todo,
            title: 'Keyboard paper',
            items: [
              PaperItem(
                id: 'first-item',
                text: 'First item',
                todoColumnCount: 2,
                todoExtraColumns: [''],
                todoColumnWidths: [2, 1],
              ),
              PaperItem(id: 'second-item', text: 'Second item', order: 1),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-todo-keyboard-insert.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('keyboard-paper-first-item-text')),
        matching: find.byType(EditableText),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final items = controller.state.papers.single.items;
    expect(items.map((item) => item.text), [
      'First item',
      '',
      'Second item',
    ]);
    expect(items[1].todoColumnCount, 2);
    expect(items[1].todoExtraColumns, ['']);
    expect(items[1].todoColumnWidths, [2, 1]);
    expect(items.map((item) => item.order), [0, 1, 2]);
  });

  testWidgets('deletes blank todo items with backspace from keyboard',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'backspace-paper',
            type: PaperTypes.todo,
            title: 'Backspace paper',
            items: [
              PaperItem(id: 'before-item', text: 'Before item'),
              PaperItem(
                id: 'blank-item',
                text: '   ',
                order: 1,
                todoColumnCount: 2,
                todoExtraColumns: ['  '],
                todoColumnWidths: [2, 1],
              ),
              PaperItem(id: 'after-item', text: 'After item', order: 2),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-todo-keyboard-backspace.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('backspace-paper-blank-item-text')),
        matching: find.byType(EditableText),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    final items = controller.state.papers.single.items;
    expect(items.map((item) => item.id), ['before-item', 'after-item']);
    expect(items.map((item) => item.order), [0, 1]);
    expect(
      controller.state.sync.deletedTodoItemTombstones['backspace-paper']
          ?.containsKey('blank-item'),
      true,
    );

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.single.items.map((item) => item.id),
      ['before-item', 'blank-item', 'after-item'],
    );
    expect(
      controller.state.sync.deletedTodoItemTombstones['backspace-paper']
          ?.containsKey('blank-item'),
      isNot(true),
    );
  });

  testWidgets('moves todo items up and down with undoable ordering',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'move-paper',
            type: PaperTypes.todo,
            title: 'Move paper',
            items: [
              PaperItem(id: 'first-item', text: 'First'),
              PaperItem(id: 'second-item', text: 'Second', order: 1),
              PaperItem(id: 'third-item', text: 'Third', order: 2),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-todo-move.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Move item down').first);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'second-item',
      'first-item',
      'third-item',
    ]);
    expect(controller.state.papers.single.items.map((item) => item.order), [
      0,
      1,
      2,
    ]);

    await tester.tap(find.byTooltip('Move item up').at(1));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'first-item',
      'second-item',
      'third-item',
    ]);

    await tester.tap(find.byTooltip('Move item down').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'first-item',
      'second-item',
      'third-item',
    ]);
  });

  testWidgets('drags todo items to reorder like PaperTodo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'drag-paper',
            type: PaperTypes.todo,
            title: 'Drag paper',
            items: [
              PaperItem(id: 'first-item', text: 'First'),
              PaperItem(id: 'second-item', text: 'Second', order: 1),
              PaperItem(id: 'third-item', text: 'Third', order: 2),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-todo-drag.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    final dragHandle =
        find.byKey(const ValueKey('drag-paper-first-item-drag-handle'));
    expect(dragHandle, findsOneWidget);
    await tester.drag(dragHandle, const Offset(0, 170));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'second-item',
      'third-item',
      'first-item',
    ]);
    expect(controller.state.papers.single.items.map((item) => item.order), [
      0,
      1,
      2,
    ]);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'first-item',
      'second-item',
      'third-item',
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
            isCollapsed: true,
            alwaysOnTop: true,
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
    expect(paper.isCollapsed, false);
    expect(controller.state.useCapsuleMode, true);
    expect(controller.state.useDeepCapsuleMode, true);
    expect(controller.state.showDeepCapsuleWhileExpanded, true);
    expect(find.byTooltip('Unpin from desktop'), findsOneWidget);
    expect(platform.paperWindows.updatedTitles, contains('Pin paper'));

    await tester.tap(find.byTooltip('Keep on top'));
    await tester.pumpAndSettle();

    expect(paper.alwaysOnTop, true);
    expect(paper.isPinnedToDesktop, false);
    expect(find.byTooltip('Disable always on top'), findsOneWidget);
    expect(find.byTooltip('Pin to desktop'), findsOneWidget);
  });

  testWidgets('hiding a pinned collapsed paper restores PaperTodo state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'hide-pinned-paper',
            type: PaperTypes.todo,
            title: 'Hide pinned paper',
            isPinnedToDesktop: true,
            items: [
              PaperItem(id: 'hide-pinned-item', text: 'Hide me'),
            ],
          ),
        ],
      ),
      platform: platform,
    );
    final paper = controller.state.papers.single;
    paper.isCollapsed = true;

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Hide paper'));
    await tester.pumpAndSettle();

    expect(paper.isVisible, false);
    expect(paper.isPinnedToDesktop, false);
    expect(paper.isCollapsed, false);
    expect(store.savedState.papers.single.isPinnedToDesktop, false);
    expect(store.savedState.papers.single.isCollapsed, false);
    expect(platform.paperWindows.hiddenTitles, contains('Hide pinned paper'));
    expect(find.text('Hide pinned paper'), findsNothing);
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

  testWidgets('surface top bar creates papers from the current paper',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sourcePaper = PaperData(
      id: 'source-topbar-paper',
      type: PaperTypes.todo,
      title: 'Source top bar',
      x: 220,
      y: 180,
      alwaysOnTop: true,
      capsuleSide: DeepCapsuleSides.left,
      capsuleMonitorDeviceName: 'Source monitor',
      items: [
        PaperItem(id: 'source-topbar-item', text: 'Create nearby'),
      ],
    );
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        papers: [sourcePaper],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Open paper surface'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New note paper'));
    await tester.pumpAndSettle();

    final createdPaper = controller.state.papers.last;
    expect(createdPaper.isNote, true);
    expect(createdPaper.x, 250);
    expect(createdPaper.y, 210);
    expect(createdPaper.alwaysOnTop, true);
    expect(createdPaper.capsuleSide, DeepCapsuleSides.left);
    expect(createdPaper.capsuleMonitorDeviceName, 'Source monitor');
    expect(platform.paperWindows.shownTitles.last, createdPaper.title);
  });

  testWidgets('top bar creation shows cleanup prompt at paper limit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        papers: List.generate(
          PaperLimits.maxPapers,
          (index) => PaperData(
            id: 'limited-paper-$index',
            type: PaperTypes.todo,
            title: 'Limited paper $index',
            isVisible: index == 0,
            items: [
              PaperItem(id: 'limited-item-$index', text: 'Paper $index'),
            ],
          ),
        ),
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('New todo paper'));
    await tester.pumpAndSettle();

    expect(controller.state.papers, hasLength(PaperLimits.maxPapers));
    expect(platform.paperWindows.shownTitles, isEmpty);
    expect(find.textContaining('Paper limit reached'), findsOneWidget);
    expect(find.textContaining('Delete papers you no longer need'),
        findsOneWidget);
  });

  testWidgets('uses compact app bar overflow actions on narrow screens',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'mobile-visible',
            type: PaperTypes.todo,
            title: 'Mobile board',
            items: [
              PaperItem(id: 'mobile-item', text: 'Keep actions reachable'),
            ],
          ),
          PaperData(
            id: 'mobile-hidden',
            type: PaperTypes.note,
            title: 'Hidden mobile note',
            isVisible: false,
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    expect(find.byTooltip('Sync now'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('compact-app-bar-actions')), findsOneWidget);
    expect(find.byTooltip('New todo paper'), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('compact-app-bar-actions')));
    await tester.pumpAndSettle();

    expect(find.text('New todo'), findsOneWidget);
    expect(find.text('New note'), findsOneWidget);
    expect(find.text('Show hidden'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Show hidden'));
    await tester.pumpAndSettle();

    expect(
      controller.state.papers
          .firstWhere((paper) => paper.id == 'mobile-hidden')
          .isVisible,
      true,
    );

    await tester.tap(find.byKey(const ValueKey('compact-app-bar-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New todo'));
    await tester.pumpAndSettle();

    expect(
        controller.state.papers.where((paper) => paper.isTodo), hasLength(2));
  });

  testWidgets('uses compact paper header actions on narrow screens',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'mobile-paper-actions',
            type: PaperTypes.note,
            title: 'Mobile paper actions',
            content: 'Compact paper controls',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    expect(
      find.byKey(const ValueKey('mobile-paper-actions-paper-actions')),
      findsOneWidget,
    );
    expect(find.byTooltip('Collapse paper'), findsOneWidget);
    expect(find.byTooltip('Open paper surface'), findsNothing);
    expect(find.byTooltip('Paper text zoom'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('mobile-paper-actions-paper-actions')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open surface'), findsOneWidget);
    expect(find.text('Open markdown externally'), findsOneWidget);
    expect(find.text('Zoom 125%'), findsOneWidget);
    expect(find.text('Pin to desktop'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'Zoom 125%'),
    );
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.textZoom, 1.25);

    await tester.tap(
      find.byKey(const ValueKey('mobile-paper-actions-paper-actions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(PopupMenuItem<String>, 'Pin to desktop'),
    );
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isPinnedToDesktop, true);
    expect(controller.state.papers.single.alwaysOnTop, false);
  });

  testWidgets('uses compact todo item actions on narrow screens',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final controller = RePaperTodoController(
      initialState: AppState(
        enableTodoNoteLinks: true,
        papers: [
          PaperData(
            id: 'mobile-actions-paper',
            type: PaperTypes.todo,
            title: 'Mobile actions',
            items: [
              PaperItem(
                id: 'mobile-action-item',
                text: 'Edit with one hand',
              ),
              PaperItem(
                id: 'mobile-action-spare',
                text: 'Keep delete enabled',
              ),
            ],
          ),
          PaperData(
            id: 'mobile-note',
            type: PaperTypes.note,
            title: 'Research note',
            content: 'Linked note body.',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    final actionsFinder = find.byKey(
      const ValueKey('mobile-actions-paper-mobile-action-item-actions'),
    );
    expect(actionsFinder, findsOneWidget);
    expect(find.byTooltip('Set due date'), findsNothing);
    expect(find.byTooltip('Delete item'), findsNothing);

    await tester.tap(actionsFinder);
    await tester.pumpAndSettle();

    expect(find.text('Set due date'), findsOneWidget);
    expect(find.text('Set reminder'), findsOneWidget);
    expect(find.text('Add column'), findsOneWidget);
    expect(find.text('Delete item'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<String> && widget.value == 'column:add',
      ),
    );
    await tester.pumpAndSettle();

    final item = controller.state.papers.first.items.first;
    expect(item.todoColumnCount, 2);

    await tester.tap(actionsFinder);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<String> &&
            widget.value == 'link:mobile-note',
      ),
    );
    await tester.pumpAndSettle();

    expect(item.linkedNoteId, 'mobile-note');

    await tester.tap(actionsFinder);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'delete',
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.papers.first.items, hasLength(1));
    expect(
        controller.state.papers.first.items.single.id, 'mobile-action-spare');
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

  testWidgets('surface collapse all targets current deep capsule queue',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleCollapseAll: true,
        papers: [
          PaperData(
            id: 'left-queue-paper',
            type: PaperTypes.todo,
            title: 'Left queue',
            capsuleMonitorDeviceName: 'Primary',
            capsuleSide: DeepCapsuleSides.left,
            items: [
              PaperItem(id: 'left-queue-item', text: 'Left queue task'),
            ],
          ),
          PaperData(
            id: 'right-queue-paper',
            type: PaperTypes.todo,
            title: 'Right queue',
            capsuleMonitorDeviceName: 'Primary',
            capsuleSide: DeepCapsuleSides.right,
            items: [
              PaperItem(id: 'right-queue-item', text: 'Right queue task'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-collapse-queue-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Left queue task'), findsOneWidget);
    expect(find.text('Right queue task'), findsOneWidget);

    await tester.tap(find.byTooltip('Open paper surface').first);
    await tester.pumpAndSettle();

    expect(find.text('Left queue task'), findsOneWidget);
    expect(find.text('Right queue task'), findsNothing);

    await tester.tap(find.byTooltip('Collapse all papers'));
    await tester.pumpAndSettle();

    expect(controller.state.capsuleCollapseAllActive, true);
    expect(controller.state.capsuleCollapseAllActiveQueues, {
      'Primary|left': true,
    });
    expect(find.text('Left queue task'), findsNothing);

    await tester.tap(find.byTooltip('Back to board'));
    await tester.pumpAndSettle();

    expect(find.text('Left queue task'), findsNothing);
    expect(find.text('Right queue task'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand all papers'));
    await tester.pumpAndSettle();

    expect(controller.state.capsuleCollapseAllActive, false);
    expect(controller.state.capsuleCollapseAllActiveQueues, isEmpty);
    expect(find.text('Left queue task'), findsOneWidget);
    expect(find.text('Right queue task'), findsOneWidget);
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

  testWidgets('settings disable capsule mode restores collapsed papers',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: true,
        useDeepCapsuleMode: true,
        useCapsuleCollapseAll: true,
        capsuleCollapseAllActive: true,
        deepCapsuleStartTopMargin: 144,
        papers: [
          PaperData(
            id: 'settings-capsule-paper',
            type: PaperTypes.todo,
            title: 'Settings capsule',
            isCollapsed: true,
            items: [
              PaperItem(
                id: 'settings-capsule-item',
                text: 'Restored from settings',
              ),
            ],
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    expect(find.text('Restored from settings'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Capsule mode'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Capsule mode'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(controller.state.useCapsuleMode, false);
    expect(controller.state.useDeepCapsuleMode, false);
    expect(controller.state.useCapsuleCollapseAll, false);
    expect(controller.state.capsuleCollapseAllActive, false);
    expect(controller.state.deepCapsuleStartTopMargin,
        PaperLayoutDefaults.deepCapsuleStartTopMargin);
    expect(controller.state.papers.single.isCollapsed, false);
    expect(platform.paperWindows.restoredTitleSnapshots, isNotEmpty);
    expect(find.text('Restored from settings'), findsOneWidget);
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

  testWidgets('reports platform setting failures while saving settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.systemIntegration.registerGlobalHotkeysError =
        StateError('Hotkey registration failed');
    final controller = RePaperTodoController(
      initialState: AppState(
        pinnedTodoHotKey: '',
        pinnedNoteHotKey: '',
        papers: [
          PaperData(
            id: 'platform-setting-failure-paper',
            type: PaperTypes.todo,
            title: 'Platform setting failure',
            items: [
              PaperItem(
                id: 'platform-setting-failure-item',
                text: 'Report platform errors',
              ),
            ],
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
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
      'Ctrl+Alt+T',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.pinnedTodoHotKey, 'Ctrl+Alt+T');
    expect(platform.systemIntegration.registeredHotkeys, isEmpty);
    expect(find.textContaining('Platform settings failed:'), findsOneWidget);
    expect(find.textContaining('Hotkey registration failed'), findsOneWidget);
  });

  testWidgets('shows readable platform setting channel failures',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.systemIntegration.setHideFromWindowSwitcherError =
        PlatformException(
      code: 'WINDOW_POLICY_FAILED',
      message: 'Window policy is unavailable.',
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        hidePapersFromWindowSwitcher: false,
        papers: [
          PaperData(
            id: 'platform-channel-failure-paper',
            type: PaperTypes.todo,
            title: 'Platform channel failure',
            items: [
              PaperItem(
                id: 'platform-channel-failure-item',
                text: 'Report readable platform channel errors',
              ),
            ],
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Hide from task switcher'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Hide from task switcher'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.hidePapersFromWindowSwitcher, true);
    expect(platform.systemIntegration.hideFromWindowSwitcherValues, [true]);
    expect(find.textContaining('Platform settings failed:'), findsOneWidget);
    expect(
        find.textContaining('Window policy is unavailable.'), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('WINDOW_POLICY_FAILED'), findsNothing);
  });

  testWidgets('continues platform settings after a platform failure',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.systemIntegration.setStartupAtLoginError =
        StateError('Startup registration failed');
    final controller = RePaperTodoController(
      initialState: AppState(
        pinnedTodoHotKey: '',
        pinnedNoteHotKey: '',
        papers: [
          PaperData(
            id: 'platform-setting-continue-paper',
            type: PaperTypes.todo,
            title: 'Platform setting continuation',
            items: [
              PaperItem(
                id: 'platform-setting-continue-item',
                text: 'Continue platform steps',
              ),
            ],
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
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
      'Ctrl+Alt+T',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.pinnedTodoHotKey, 'Ctrl+Alt+T');
    expect(platform.systemIntegration.startupAtLoginValues, [false]);
    expect(platform.systemIntegration.registeredHotkeys, hasLength(1));
    expect(
      platform.systemIntegration.registeredHotkeys.single,
      ('Ctrl+Alt+T', ''),
    );
    expect(find.textContaining('Platform settings failed:'), findsOneWidget);
    expect(find.textContaining('Startup registration failed'), findsOneWidget);
  });

  testWidgets('hides desktop-only settings on unsupported platforms',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        startAtLogin: true,
        hidePapersFromWindowSwitcher: true,
        fullscreenTopmostMode: FullscreenTopmostModes.stayOnTop,
        pinnedTodoHotKey: 'Ctrl+Alt+T',
        pinnedNoteHotKey: 'Ctrl+Alt+N',
        runLinkedScriptCapsulesOnClick: true,
        papers: [
          PaperData(
            id: 'mobile-settings-paper',
            type: PaperTypes.todo,
            title: 'Mobile settings',
            items: [
              PaperItem(
                id: 'mobile-settings-item',
                text: 'No desktop startup switch',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(
        supportsStartupAtLogin: false,
        supportsDesktopIntegration: false,
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Start at login'), findsNothing);
    expect(find.text('Hide from task switcher'), findsNothing);
    expect(find.text('Avoid fullscreen'), findsNothing);
    expect(find.text('Stay on top'), findsNothing);
    expect(find.text('Pinned todo hotkey'), findsNothing);
    expect(find.text('Pinned note hotkey'), findsNothing);
    expect(find.text('Run linked script capsules on click'), findsNothing);
    expect(find.text('Persistent PowerShell process'), findsNothing);
    expect(find.text('Prefer PowerShell 7'), findsNothing);
    expect(find.text('Hide script run window'), findsNothing);
    expect(controller.supportsStartupAtLogin, false);
    expect(controller.supportsGlobalHotkeys, false);
    expect(controller.supportsScriptCapsules, false);
  });

  testWidgets('skips desktop integration calls on unsupported platforms',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices(
      supportsStartupAtLogin: false,
      supportsDesktopIntegration: false,
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        startAtLogin: true,
        hidePapersFromWindowSwitcher: true,
        fullscreenTopmostMode: FullscreenTopmostModes.stayOnTop,
        pinnedTodoHotKey: 'Ctrl+Alt+T',
        pinnedNoteHotKey: 'Ctrl+Alt+N',
        runLinkedScriptCapsulesOnClick: true,
        usePersistentPowerShellProcess: true,
        papers: [
          PaperData(
            id: 'unsupported-platform-settings',
            type: PaperTypes.todo,
            title: 'Unsupported platform settings',
            items: [
              PaperItem(
                id: 'unsupported-platform-item',
                text: 'Save without desktop calls',
              ),
            ],
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(platform.systemIntegration.startupAtLoginValues, isEmpty);
    expect(platform.systemIntegration.hideFromWindowSwitcherValues, isEmpty);
    expect(platform.systemIntegration.fullscreenTopmostModes, isEmpty);
    expect(platform.systemIntegration.registeredHotkeys, isEmpty);
    expect(platform.scriptCapsules.preparedSettings, isEmpty);
    expect(platform.scriptCapsules.stopCount, 0);
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
    final store = _MemoryStateStore();

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
    expect(store.savedState.papers.map((paper) => paper.id),
        contains('runtime-command-paper'));
    expect(
        store.savedState.papers.map((paper) => paper.title), contains('Todo2'));
    expect(platform.tray.rebuildTitleSnapshots.last,
        containsAll(['Runtime commands', 'Todo2']));
    expect(find.text('Todo2'), findsOneWidget);

    startup.addCommand(const StartupCommand(StartupCommandKind.newNote));
    await tester.pumpAndSettle();

    expect(controller.state.papers, hasLength(3));
    expect(controller.state.papers.last.type, PaperTypes.note);
    expect(platform.paperWindows.shownTitles, contains('Note1'));
    expect(store.savedState.papers.map((paper) => paper.id),
        contains('runtime-command-paper'));
    expect(store.savedState.papers.map((paper) => paper.title),
        containsAll(['Todo2', 'Note1']));
    expect(platform.tray.rebuildTitleSnapshots.last,
        containsAll(['Runtime commands', 'Todo2', 'Note1']));
    expect(find.text('Note1'), findsOneWidget);

    startup.addCommand(const StartupCommand(StartupCommandKind.settings));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
  });

  testWidgets('opens settings requested during initial startup',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'initial-settings-paper',
            type: PaperTypes.todo,
            title: 'Initial settings',
            items: [
              PaperItem(id: 'initial-settings-item', text: 'Open settings'),
            ],
          ),
        ],
      ),
      platform: platform,
    );

    await controller.start(
      startupCommand: const StartupCommand(StartupCommandKind.settings),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
  });

  testWidgets('runtime visibility startup commands are saved', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final startup = _RecordingStartupHost();
    final platform = _RecordingPlatformServices(startup: startup);
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'runtime-visible-a',
            type: PaperTypes.todo,
            title: 'Visible A',
            isVisible: true,
            items: [
              PaperItem(id: 'runtime-visible-a-item', text: 'Alpha'),
            ],
          ),
          PaperData(
            id: 'runtime-visible-b',
            type: PaperTypes.note,
            title: 'Visible B',
            isVisible: true,
            content: 'Beta',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );
    platform.tray.rebuildVisibilitySnapshots.clear();

    startup.addCommand(const StartupCommand(StartupCommandKind.hide));
    await tester.pumpAndSettle();

    expect(controller.state.papers.every((paper) => !paper.isVisible), true);
    expect(store.savedState.papers.every((paper) => !paper.isVisible), true);
    expect(platform.paperWindows.hiddenTitles,
        containsAll(['Visible A', 'Visible B']));
    expect(platform.tray.rebuildVisibilitySnapshots.last, {
      'runtime-visible-a': false,
      'runtime-visible-b': false,
    });

    startup.addCommand(const StartupCommand(StartupCommandKind.toggle));
    await tester.pumpAndSettle();

    expect(controller.state.papers.every((paper) => paper.isVisible), true);
    expect(store.savedState.papers.every((paper) => paper.isVisible), true);
    expect(platform.paperWindows.shownTitles,
        containsAll(['Visible A', 'Visible B']));
    expect(platform.tray.rebuildVisibilitySnapshots.last, {
      'runtime-visible-a': true,
      'runtime-visible-b': true,
    });
  });

  testWidgets('refreshes tray immediately for platform visibility updates',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'surface-visibility-paper',
            type: PaperTypes.todo,
            title: 'Surface visibility',
            items: [
              PaperItem(id: 'surface-visibility-item', text: 'Watch tray'),
            ],
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );
    platform.tray.rebuildVisibilitySnapshots.clear();

    final paper = controller.state.papers.single;
    paper.isVisible = false;
    platform.paperWindows.emitSurfaceUpdate(paper);
    await tester.pump();

    expect(platform.tray.rebuildVisibilitySnapshots, [
      {'surface-visibility-paper': false},
    ]);

    paper.x = 240;
    platform.paperWindows.emitSurfaceUpdate(paper);
    await tester.pump();

    expect(platform.tray.rebuildVisibilitySnapshots, hasLength(1));
  });

  testWidgets('paper open requests show hidden papers and save state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'tray-open-hidden-paper',
            type: PaperTypes.todo,
            title: 'Tray hidden',
            isVisible: false,
            items: [
              PaperItem(id: 'tray-open-hidden-item', text: 'Restore me'),
            ],
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('Tray hidden'), findsNothing);

    platform.paperWindows.emitPaperOpenRequest('tray-open-hidden-paper');
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isVisible, true);
    expect(store.savedState.papers.single.isVisible, true);
    expect(platform.paperWindows.shownTitles, contains('Tray hidden'));
    expect(find.text('Tray hidden'), findsOneWidget);
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

  testWidgets('runs collapsed script capsules and right click opens editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        preferPowerShell7: false,
        papers: [
          PaperData(
            id: 'collapsed-script-note',
            type: PaperTypes.note,
            title: 'Deploy script',
            content: '!p\n  Write-Output deploy',
            isCollapsed: true,
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    final capsule = find.byKey(
      const ValueKey('collapsed-script-note-script-capsule'),
    );
    expect(capsule, findsOneWidget);
    expect(find.text('Run Deploy script'), findsOneWidget);
    expect(find.byKey(const ValueKey('collapsed-script-note-content')),
        findsNothing);

    await tester.tap(capsule);
    await tester.pumpAndSettle();

    expect(platform.scriptCapsules.requests, hasLength(1));
    final request = platform.scriptCapsules.requests.single;
    expect(request.engine, 'auto');
    expect(request.script, 'Write-Output deploy');
    expect(request.usePersistentProcess, false);
    expect(request.preferPowerShell7, false);
    expect(controller.state.papers.single.isCollapsed, true);

    await tester.tapAt(tester.getCenter(capsule),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isCollapsed, false);
    expect(find.byKey(const ValueKey('collapsed-script-note-content')),
        findsOneWidget);
  });

  testWidgets('reports linked script capsule failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.scriptCapsules.runError = StateError('PowerShell failed');
    final controller = RePaperTodoController(
      initialState: AppState(
        maxTitleLength: 20,
        runLinkedScriptCapsulesOnClick: true,
        showLinkedNoteName: true,
        papers: [
          PaperData(
            id: 'todo-script-failure',
            type: PaperTypes.todo,
            title: 'Script failure',
            items: [
              PaperItem(
                id: 'todo-script-failure-item',
                text: 'Run failing automation',
                linkedNoteId: 'failing-script-note',
              ),
            ],
          ),
          PaperData(
            id: 'failing-script-note',
            type: PaperTypes.note,
            title: 'Failing script',
            content: '!pf\n  throw "bad"',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Run Failing script'));
    await tester.pumpAndSettle();

    expect(platform.scriptCapsules.requests, hasLength(1));
    expect(find.textContaining('Script capsule failed:'), findsOneWidget);
    expect(find.textContaining('PowerShell failed'), findsOneWidget);
  });

  testWidgets('shows readable script capsule platform failures',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.scriptCapsules.runError = PlatformException(
      code: 'SCRIPT_HOST_FAILED',
      message: 'PowerShell host is unavailable.',
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        maxTitleLength: 20,
        runLinkedScriptCapsulesOnClick: true,
        showLinkedNoteName: true,
        papers: [
          PaperData(
            id: 'todo-script-platform-failure',
            type: PaperTypes.todo,
            title: 'Script platform failure',
            items: [
              PaperItem(
                id: 'todo-script-platform-failure-item',
                text: 'Run platform failing automation',
                linkedNoteId: 'platform-failing-script-note',
              ),
            ],
          ),
          PaperData(
            id: 'platform-failing-script-note',
            type: PaperTypes.note,
            title: 'Bad script',
            content: '!pf\n  Write-Output "bad host"',
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    await tester.tap(find.text('Run Bad script'));
    await tester.pumpAndSettle();

    expect(platform.scriptCapsules.requests, hasLength(1));
    expect(find.textContaining('Script capsule failed:'), findsOneWidget);
    expect(
        find.textContaining('PowerShell host is unavailable.'), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('SCRIPT_HOST_FAILED'), findsNothing);
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

Future<void> _enterNoteEditor(WidgetTester tester, String paperId) async {
  await tester.tap(find.byKey(ValueKey('$paperId-preview')));
  await tester.pump();
  await tester.pump();
  expect(find.byKey(ValueKey('$paperId-content')), findsOneWidget);
}

class _RecoverySnapshotSyncService extends AppSyncService {
  _RecoverySnapshotSyncService({
    required this.snapshots,
    required this.restoredState,
    this.firstListError,
    this.firstRestoreError,
    this.restoreStatus = AppSyncStatus.downloaded,
    this.restoreMessage = 'Snapshot restored.',
    this.includeRestoredState = true,
  });

  final List<WebDavSnapshotRecord> snapshots;
  final AppState restoredState;
  final Object? firstListError;
  final Object? firstRestoreError;
  final AppSyncStatus restoreStatus;
  final String restoreMessage;
  final bool includeRestoredState;
  final restoredPaths = <String>[];
  var listCalls = 0;
  var restoreCalls = 0;

  @override
  Future<List<WebDavSnapshotRecord>> listRecoverySnapshots({
    required AppState localState,
    required StateStore store,
  }) async {
    listCalls += 1;
    final error = firstListError;
    if (listCalls == 1 && error != null) {
      throw error;
    }
    return snapshots;
  }

  @override
  Future<AppSyncResult> restoreRecoverySnapshot({
    required AppState localState,
    required StateStore store,
    required String snapshotPath,
  }) async {
    restoreCalls += 1;
    final error = firstRestoreError;
    if (restoreCalls == 1 && error != null) {
      throw error;
    }
    restoredPaths.add(snapshotPath);
    return AppSyncResult(
      status: restoreStatus,
      state: includeRestoredState ? restoredState : null,
      message: restoreMessage,
      snapshotPath: snapshotPath,
    );
  }
}

class _ManualSyncService extends AppSyncService {
  _ManualSyncService({
    required this.result,
    this.firstSyncGate,
    this.firstSyncError,
    this.firstLocalUploadError,
    this.localUploadState,
    this.localUploadUploadedCount = 1,
    this.localUploadStateChanged = false,
    this.recoverySnapshots = const <WebDavSnapshotRecord>[],
  });

  final AppSyncRunResult result;
  final Future<void>? firstSyncGate;
  final Object? firstSyncError;
  final Object? firstLocalUploadError;
  final AppState? localUploadState;
  final int localUploadUploadedCount;
  final bool localUploadStateChanged;
  final List<WebDavSnapshotRecord> recoverySnapshots;
  var calls = 0;
  var localUploadCalls = 0;
  var listRecoveryCalls = 0;
  final events = <String>[];
  final localUploadBeforeTitles = <String>[];
  final localUploadAfterTitles = <String>[];
  final syncLocalDeviceSequences = <Map<String, int>>[];

  @override
  Future<AppSyncRunResult> syncAndMergeNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    calls += 1;
    events.add('sync');
    syncLocalDeviceSequences.add(
      Map<String, int>.from(localState.sync.operationDeviceSequences),
    );
    final gate = firstSyncGate;
    if (calls == 1 && gate != null) {
      await gate;
    }
    final error = firstSyncError;
    if (calls == 1 && error != null) {
      throw error;
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
    final error = firstLocalUploadError;
    if (localUploadCalls == 1 && error != null) {
      throw error;
    }
    final state = localUploadState ?? afterState;
    await store.save(state);
    return AppSyncLocalOperationUploadResult(
      state: state,
      deviceSequences: state.sync.operationDeviceSequences,
      generatedCount: 1,
      uploadedCount: localUploadUploadedCount,
      stateChanged: localUploadStateChanged,
    );
  }

  @override
  Future<List<WebDavSnapshotRecord>> listRecoverySnapshots({
    required AppState localState,
    required StateStore store,
  }) async {
    listRecoveryCalls += 1;
    return recoverySnapshots;
  }
}

class _MemoryStateStore extends StateStore {
  _MemoryStateStore() : super(filePath: 'memory-state.json');

  final _codec = const AppStateCodec();
  AppState savedState = AppState();
  Object? nextSaveError;

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
    final error = nextSaveError;
    if (error != null) {
      nextSaveError = null;
      throw error;
    }
    savedState = _codec.decode(_codec.encode(state));
  }
}

class _RecordingPlatformServices implements PlatformServices {
  _RecordingPlatformServices({
    StartupHost? startup,
    bool supportsStartupAtLogin = true,
    bool supportsDesktopIntegration = true,
  })  : startup = startup ?? NoopStartupHost(),
        systemIntegration = _RecordingSystemIntegrationHost(
          supportsStartupAtLogin: supportsStartupAtLogin,
          supportsWindowSwitcherVisibility: supportsDesktopIntegration,
          supportsFullscreenTopmostMode: supportsDesktopIntegration,
          supportsGlobalHotkeys: supportsDesktopIntegration,
        ),
        scriptCapsules = _RecordingScriptCapsuleHost(
          supportsScriptCapsules: supportsDesktopIntegration,
        );

  @override
  final _RecordingPaperWindowHost paperWindows = _RecordingPaperWindowHost();

  @override
  final _RecordingTrayHost tray = _RecordingTrayHost();

  @override
  final StartupHost startup;

  @override
  final _RecordingSystemIntegrationHost systemIntegration;

  @override
  final _RecordingExternalFileHost externalFiles = _RecordingExternalFileHost();

  @override
  final _RecordingUriOpenHost uriOpener = _RecordingUriOpenHost();

  @override
  final _RecordingScriptCapsuleHost scriptCapsules;

  @override
  final AppStorageHost storage = _RecordingAppStorageHost();
}

class _RecordingAppStorageHost implements AppStorageHost {
  @override
  Future<String> documentsDirectoryPath() async {
    return Directory('build/test-widget-storage').absolute.path;
  }
}

class _RecordingTrayHost extends NoopTrayHost {
  var disposeCount = 0;
  final rebuildTitleSnapshots = <List<String>>[];
  final rebuildVisibilitySnapshots = <Map<String, bool>>[];

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }

  @override
  Future<void> rebuildMenu(AppState state) async {
    rebuildTitleSnapshots.add(
      state.papers.map((paper) => paper.title).toList(),
    );
    rebuildVisibilitySnapshots.add({
      for (final paper in state.papers) paper.id: paper.isVisible,
    });
  }
}

class _RecordingPaperWindowHost extends NoopPaperWindowHost {
  final restoredTitleSnapshots = <List<String>>[];
  final updatedTitles = <String>[];
  final shownTitles = <String>[];
  final hiddenTitles = <String>[];
  final _surfaceUpdates = StreamController<PaperData>.broadcast();
  final _paperOpenRequests = StreamController<String>.broadcast();

  @override
  Stream<PaperData> get surfaceUpdates => _surfaceUpdates.stream;

  @override
  Stream<String> get paperOpenRequests => _paperOpenRequests.stream;

  void emitSurfaceUpdate(PaperData paper) {
    _surfaceUpdates.add(paper);
  }

  void emitPaperOpenRequest(String paperId) {
    _paperOpenRequests.add(paperId);
  }

  @override
  Future<void> restoreAll(AppState state) async {
    restoredTitleSnapshots.add(
      state.papers.map((paper) => paper.title).toList(),
    );
  }

  @override
  Future<void> showPaper(PaperData paper) async {
    shownTitles.add(paper.title);
  }

  @override
  Future<void> hidePaper(PaperData paper) async {
    hiddenTitles.add(paper.title);
  }

  @override
  Future<void> updatePaperSurface(PaperData paper) async {
    updatedTitles.add(paper.title);
  }
}

class _RecordingExternalFileHost implements ExternalFileHost {
  final openedPaths = <String>[];
  Object? error;

  @override
  Future<void> openFile(String path) async {
    openedPaths.add(path);
    final error = this.error;
    if (error != null) {
      throw error;
    }
  }
}

class _RecordingUriOpenHost implements UriOpenHost {
  final openedUris = <String>[];
  Object? error;

  @override
  Future<void> openUri(String uri) async {
    openedUris.add(uri);
    final error = this.error;
    if (error != null) {
      throw error;
    }
  }
}

class _RecordingScriptCapsuleHost implements ScriptCapsuleHost {
  _RecordingScriptCapsuleHost({required this.supportsScriptCapsules});

  @override
  final bool supportsScriptCapsules;

  final requests = <ScriptCapsuleRunRequest>[];
  final preparedSettings =
      <({bool preferPowerShell7, bool hideScriptRunWindow})>[];
  Object? runError;
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
    final error = runError;
    if (error != null) {
      throw error;
    }
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
  _RecordingSystemIntegrationHost({
    required this.supportsStartupAtLogin,
    required this.supportsWindowSwitcherVisibility,
    required this.supportsFullscreenTopmostMode,
    required this.supportsGlobalHotkeys,
  });

  @override
  final bool supportsStartupAtLogin;

  @override
  final bool supportsWindowSwitcherVisibility;

  @override
  final bool supportsFullscreenTopmostMode;

  @override
  final bool supportsGlobalHotkeys;

  final registeredHotkeys = <(String todo, String note)>[];
  final startupAtLoginValues = <bool>[];
  final hideFromWindowSwitcherValues = <bool>[];
  final fullscreenTopmostModes = <String>[];
  Object? setStartupAtLoginError;
  Object? setHideFromWindowSwitcherError;
  Object? setFullscreenTopmostModeError;
  Object? registerGlobalHotkeysError;
  var unregisterGlobalHotkeysCount = 0;
  var exitApplicationCount = 0;

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {
    final error = registerGlobalHotkeysError;
    if (error != null) {
      throw error;
    }
    registeredHotkeys.add((state.pinnedTodoHotKey, state.pinnedNoteHotKey));
  }

  @override
  Future<void> setStartupAtLogin(bool enabled) async {
    startupAtLoginValues.add(enabled);
    final error = setStartupAtLoginError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setHideFromWindowSwitcher(bool enabled) async {
    hideFromWindowSwitcherValues.add(enabled);
    final error = setHideFromWindowSwitcherError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setFullscreenTopmostMode(String mode) async {
    fullscreenTopmostModes.add(mode);
    final error = setFullscreenTopmostModeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> unregisterGlobalHotkeys() async {
    unregisterGlobalHotkeysCount += 1;
  }

  @override
  Future<void> exitApplication() async {
    exitApplicationCount += 1;
  }
}
