import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/app_controller.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/note_canvas_element.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/model/paper_item.dart';
import 'package:repapertodo/src/core/model/paper_titles.dart';
import 'package:repapertodo/src/core/model/sync_settings.dart';
import 'package:repapertodo/src/core/model/todo_paste.dart';
import 'package:repapertodo/src/core/script/script_capsule.dart';
import 'package:repapertodo/src/core/storage/state_store.dart';
import 'package:repapertodo/src/core/state/app_state_codec.dart';
import 'package:repapertodo/src/core/startup/startup_command.dart';
import 'package:repapertodo/src/platform/noop_platform_services.dart';
import 'package:repapertodo/src/platform/platform_services.dart';
import 'package:repapertodo/src/sync/app_sync_service.dart';
import 'package:repapertodo/src/sync/sync_device_id_store.dart';
import 'package:repapertodo/src/sync/webdav/webdav_client.dart';
import 'package:repapertodo/src/sync/webdav/webdav_payload_codec.dart';
import 'package:repapertodo/src/sync/webdav/webdav_state_sync_service.dart';
import 'package:repapertodo/src/ui/papertodo_markdown_source.dart';
import 'package:repapertodo/src/ui/papertodo_theme.dart';

void _ignoreMarkdownLink(String _) {}

bool _primaryFocusIsWithin(Finder finder) {
  final target = finder.evaluate().single;
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (focusedContext is! Element) {
    return false;
  }
  if (identical(focusedContext, target)) {
    return true;
  }
  var found = false;
  focusedContext.visitAncestorElements((ancestor) {
    found = identical(ancestor, target);
    return !found;
  });
  return found;
}

Future<void> _commitVisibleDialog(WidgetTester tester) async {
  for (final label in const ['Save', 'OK']) {
    final primaryButton = find.widgetWithText(FilledButton, label);
    if (primaryButton.evaluate().isNotEmpty) {
      await tester.tap(primaryButton.last);
      return;
    }
  }
  await tester.tap(find.byTooltip('Close'));
}

Finder _reminderIntervalValueField() {
  return find.byKey(const ValueKey('todo-reminder-interval-value'));
}

Finder _snackBarTextContaining(String text) {
  return find.descendant(
    of: find.byType(SnackBar),
    matching: find.textContaining(text),
  );
}

Finder _popupMenuItemWithText(String text) {
  return find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<String>,
    ),
  );
}

Future<void> _selectReminderIntervalUnit(
  WidgetTester tester,
  String unit,
) async {
  tester
      .widget<DropdownButton<String>>(
        find.byKey(const ValueKey('todo-reminder-interval-unit')),
      )
      .onChanged
      ?.call(unit);
  await tester.pump();
}

Future<void> _dismissVisibleDialog(WidgetTester tester) async {
  final dialog = find.byType(Dialog).last;
  Navigator.of(tester.element(dialog), rootNavigator: true).pop();
  await tester.pump();
}

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

    final boardContext = tester.element(find.byType(Scaffold).first);
    final boardTheme = Theme.of(boardContext);
    final boardColors = PaperTodoThemeColors.of(boardContext);
    expect(boardTheme.snackBarTheme.backgroundColor, boardColors.paper);
    expect(boardTheme.snackBarTheme.contentTextStyle?.color, boardColors.text);
    expect(boardTheme.snackBarTheme.actionTextColor, boardColors.active);
    final feedbackShape =
        boardTheme.snackBarTheme.shape as RoundedRectangleBorder;
    expect(feedbackShape.borderRadius, BorderRadius.circular(14));
    expect(feedbackShape.side.color, boardColors.paperBorder);

    expect(find.text('RePaperTodo'), findsWidgets);
    expect(find.text('Windows parity'), findsOneWidget);
    expect(find.text('Build compatible data core'), findsOneWidget);
    expect(find.text('6/30 00:00'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('welcome-todo-todo-2-due-absolute')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items[1].dueAtLocal, isNull);
    expect(find.text('6/30 00:00'), findsNothing);

    final titleField = find.byKey(const ValueKey('welcome-todo-title'));
    await tester.tap(titleField);
    await tester.pump();
    await tester.enterText(titleField, 'Edited title');
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

    await tester.tap(find.byTooltip('Delete this item').first);
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
    expect(
      find.text(
        'This paper will be permanently removed and cannot be restored from the tray.',
      ),
      findsOneWidget,
    );
    final deleteButton = find.widgetWithText(FilledButton, 'Delete');
    final cancelButton = find.widgetWithText(TextButton, 'Cancel');
    expect(tester.getSize(deleteButton), const Size(72, 34));
    expect(tester.getSize(cancelButton), const Size(72, 34));
    expect(
      tester.getCenter(deleteButton).dx,
      lessThan(tester.getCenter(cancelButton).dx),
    );
    expect(
      find.descendant(of: deleteButton, matching: find.byType(Icon)),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusIsWithin(deleteButton), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusIsWithin(cancelButton), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_primaryFocusIsWithin(deleteButton), isTrue);

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
    final fallbackPaperId = controller.state.papers.single.id;
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

    expect(controller.state.papers, hasLength(1));
    expect(find.byKey(const ValueKey('welcome-todo-title')), findsOneWidget);
    expect(controller.state.sync.isPaperDeleted('welcome-todo'), false);
    expect(controller.state.sync.isPaperDeleted(fallbackPaperId), true);

    await tester.tap(find.byIcon(Icons.sync_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Sync is disabled.'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    final selectedSettingsCategory =
        find.byKey(const ValueKey('settings-category-display'));
    final selectedSettingsColors =
        PaperTodoThemeColors.of(tester.element(selectedSettingsCategory));
    final selectedSettingsMaterial = tester
        .element(selectedSettingsCategory)
        .findAncestorWidgetOfExactType<Material>();
    expect(
      selectedSettingsMaterial?.color,
      selectedSettingsColors.tint.withValues(alpha: 24 / 255),
    );
    expect(
      tester.widget<InkWell>(selectedSettingsCategory).hoverColor,
      selectedSettingsColors.tint.withValues(alpha: 32 / 255),
    );
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Warm'), findsNothing);
    expect(find.text('Ink'), findsNothing);
    expect(find.text('Forest'), findsNothing);
    expect(find.text('Rose'), findsNothing);
    expect(find.text('Global theme color'), findsOneWidget);
    expect(find.text('Display'), findsWidgets);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('XL'), findsOneWidget);
    expect(find.text('Font preset'), findsNothing);
    expect(find.text('Default'), findsNWidgets(2));
    expect(find.text('System font'), findsOneWidget);
    expect(find.text('Language default'), findsOneWidget);
    expect(find.text('External open file type'), findsNothing);
    expect(find.text('Zoom'), findsNothing);
    expect(find.text('Title length limit'), findsNothing);
    expect(find.text('Show hover hints'), findsNothing);
    expect(find.text('Enable animations'), findsNothing);
    expect(find.text('Todo spacing'), findsOneWidget);
    expect(find.text('Note spacing'), findsOneWidget);
    expect(find.text('Show relative todo time'), findsNothing);
    expect(find.text('None'), findsNothing);
    expect(find.text('26'), findsNothing);
    expect(find.text('2026'), findsNothing);
    expect(find.text('Avoid'), findsOneWidget);
    expect(find.text('Stay on top'), findsOneWidget);
    expect(find.text('Top bar new todo'), findsOneWidget);
    expect(find.text('Top bar new note'), findsOneWidget);
    expect(find.text('Show external open button'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-sync-section-divider')),
      findsOneWidget,
    );
    await _selectSettingsCategory(tester, 'capsules');
    expect(find.text('Capsule mode'), findsOneWidget);
    expect(find.text('Edge capsule mode'), findsOneWidget);
    expect(find.text('Show main capsule'), findsOneWidget);
    expect(find.text('Collapse all active'), findsNothing);
    expect(find.text('Deep capsule top margin'), findsNothing);
    expect(find.text('Deep capsule monitor'), findsNothing);
    expect(find.text('Show deep capsule while expanded'), findsOneWidget);
    expect(
        find.text('Click edge capsule again to retract paper'), findsOneWidget);
    expect(find.text('Hide edge capsules when covered'), findsOneWidget);
    expect(find.text('Title length limit'), findsOneWidget);
    await _selectSettingsCategory(tester, 'todoAndNotes');
    expect(find.text('Show relative todo time'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('26'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('Use interval reminder bubbles'), findsOneWidget);
    expect(find.text('Reminder interval'), findsOneWidget);
    expect(find.text('Minutes'), findsOneWidget);
    expect(find.text('Hours'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Nearest'), findsOneWidget);
    expect(find.text('Bubble duration (seconds)'), findsOneWidget);
    await _selectSettingsCategory(tester, 'general');
    expect(find.text('Start with Windows'), findsOneWidget);
    expect(find.text('Hide papers from window switching'), findsOneWidget);
    expect(find.text('Show hover hints'), findsOneWidget);
    expect(find.text('Enable animations'), findsOneWidget);
    expect(find.text('External open file type'), findsOneWidget);
    expect(find.text('Pinned todo hotkey'), findsOneWidget);
    expect(find.text('Pinned note hotkey'), findsOneWidget);
    expect(find.text('Run linked scripts directly'), findsNothing);
    expect(find.text('Persistent PowerShell process'), findsOneWidget);
    expect(find.text('Prefer PowerShell 7'), findsOneWidget);
    expect(find.text('Hide script window'), findsOneWidget);
    await _selectSettingsCategory(tester, 'todoAndNotes');
    expect(find.text('Enable todo-note links'), findsOneWidget);
    expect(find.text('Show linked note title'), findsOneWidget);
    expect(find.text('Long linked note titles'), findsOneWidget);
    expect(find.text('Linked notes not shown as capsules'), findsOneWidget);
    expect(find.text('Run linked scripts directly'), findsOneWidget);
    await _selectSettingsCategory(tester, 'sync');
    expect(find.text('WebDAV sync'), findsWidgets);
    expect(find.text('坚果云'), findsOneWidget);
    expect(find.text('Generic'), findsOneWidget);
  });

  testWidgets('paper window mode renders only its independent paper surface',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(
      maxTitleLength: 64,
      papers: [
        PaperData(
          id: 'independent-paper',
          type: PaperTypes.note,
          title: 'Independent paper',
          content: 'Rendered in its own Flutter engine.',
        ),
        PaperData(
          id: 'other-paper',
          type: PaperTypes.note,
          title: 'Other paper',
          content: 'Must stay in another HWND.',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: state,
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(state);

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        initialSurfacePaperId: 'independent-paper',
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.papers.map((paper) => paper.id),
        ['independent-paper', 'other-paper']);
    expect(controller.state.papers.first.isVisible, true);
    expect(controller.state.papers.first.isCollapsed, false);
    final paperBoard = tester.widget<PaperBoardScreen>(
      find.byType(PaperBoardScreen),
    );
    expect(paperBoard.paperWindowMode, true);
    expect(paperBoard.initialSurfacePaperId, 'independent-paper');
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText &&
            widget.controller.text == 'Independent paper',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is PaperTodoMarkdownSourcePreview &&
            widget.data == 'Rendered in its own Flutter engine.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.controller.text == 'Other paper',
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(find.byTooltip('Sync now'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(
      tester
          .widget<Padding>(
            find.byKey(
              const ValueKey('independent-paper-standalone-note-body'),
            ),
          )
          .padding,
      const EdgeInsets.only(top: 2),
    );
  });

  testWidgets('paper window chrome and todo dragging match PaperTodo defaults',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'paper-window-parity',
      type: PaperTypes.todo,
      title: 'Todo1',
      items: [
        PaperItem(id: 'paper-window-first', text: 'First'),
        PaperItem(id: 'paper-window-second', text: 'Second', order: 1),
        PaperItem(id: 'paper-window-third', text: 'Third', order: 2),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        papers: [paper],
      ),
      platform: _RecordingPlatformServices(),
    );
    var windowDragStarts = 0;

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
        paperWindowDragStarter: () async {
          windowDragStarts += 1;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('paper-window-parity-new-todo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('paper-window-parity-new-note')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('paper-window-parity-desktop-pin')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('paper-window-parity-sync-now')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('paper-window-parity-close')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.text('Add item'), findsNothing);

    final chromeMargin = find.byKey(
      const ValueKey('paper-window-parity-paper-window-chrome-margin'),
    );
    expect(chromeMargin, findsOneWidget);
    expect(tester.getTopLeft(chromeMargin), Offset.zero);
    final previewRect = tester.getRect(find.byType(PaperPreview));
    expect(previewRect.left, 8);
    expect(previewRect.top, 8);
    expect(previewRect.right, 272);
    expect(previewRect.bottom, 332);
    expect(
      tester.getRect(
        find.byKey(
          const ValueKey('paper-window-transparency-guard-left'),
        ),
      ),
      const Rect.fromLTWH(7, 0, 1, 340),
    );
    expect(
      tester.getRect(
        find.byKey(
          const ValueKey('paper-window-transparency-guard-right'),
        ),
      ),
      const Rect.fromLTWH(272, 0, 1, 340),
    );
    expect(
      tester.getRect(
        find.byKey(
          const ValueKey('paper-window-transparency-guard-top'),
        ),
      ),
      const Rect.fromLTWH(0, 7, 280, 1),
    );
    expect(
      tester.getRect(
        find.byKey(
          const ValueKey('paper-window-transparency-guard-bottom'),
        ),
      ),
      const Rect.fromLTWH(0, 332, 280, 1),
    );
    final paperSurfaceFinder =
        find.byKey(const ValueKey('paper-window-parity-paper-surface'));
    final paperSurface = tester.widget<DecoratedBox>(paperSurfaceFinder);
    final paperDecoration = paperSurface.decoration as BoxDecoration;
    expect(paperDecoration.color, isNotNull);
    expect(paperDecoration.gradient, isNull);
    expect(paperDecoration.borderRadius, BorderRadius.circular(18));
    expect(
      (paperDecoration.border! as Border).top.color,
      PaperTodoThemeColors.of(tester.element(paperSurfaceFinder)).paperBorder,
    );
    expect(paperDecoration.boxShadow, isEmpty);
    final paperClip = tester.widget<ClipRRect>(
      find
          .ancestor(
            of: paperSurfaceFinder,
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    expect(paperClip.clipBehavior, Clip.hardEdge);

    final paperHeader = find.byKey(
      const ValueKey('paper-window-parity-paper-header'),
    );
    expect(tester.getSize(paperHeader).height, 31);
    final headerColors = PaperTodoThemeColors.of(tester.element(paperHeader));
    final headerDecoration =
        tester.widget<Container>(paperHeader).decoration as BoxDecoration;
    expect(
      tester.widget<Container>(paperHeader).padding,
      const EdgeInsets.fromLTRB(6, 5, 8, 1),
    );
    expect(
      headerDecoration.color,
      headerColors.tint.withValues(alpha: 12 / 255),
    );
    expect(
      (headerDecoration.border! as Border).bottom.color,
      Color.alphaBlend(
        headerColors.tint.withValues(alpha: 28 / 255),
        headerColors.paper,
      ),
    );
    await tester.timedDragFrom(
      tester.getCenter(paperHeader),
      const Offset(24, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(windowDragStarts, 1);

    final topmostButton =
        find.byKey(const ValueKey('paper-window-parity-topmost'));
    expect(topmostButton, findsOneWidget);
    expect(tester.getSize(topmostButton), const Size(23, 24));
    final topmostIconButton = find.descendant(
      of: topmostButton,
      matching: find.byType(IconButton),
    );
    expect(topmostIconButton, findsOneWidget);
    final topmostOpacity = tester.widget<Opacity>(
      find.descendant(
        of: topmostButton,
        matching: find.byKey(
          const ValueKey('paper-window-topmost-glyph-opacity'),
        ),
      ),
    );
    expect(topmostOpacity.opacity, 0.58);
    final topmostGlyph = tester.widget<Text>(
      find.descendant(of: topmostButton, matching: find.text('\u2611')),
    );
    expect(topmostGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(topmostGlyph.style?.fontSize, 13);
    expect(topmostGlyph.style?.fontWeight, FontWeight.normal);
    expect(topmostGlyph.style?.color, headerColors.weakText);
    final topmostMetrics = tester.widget<Transform>(
      find.descendant(
        of: topmostButton,
        matching: find.byKey(
          const ValueKey('paper-window-topmost-glyph-metrics'),
        ),
      ),
    );
    expect(topmostMetrics.transform.getTranslation().x, 1);
    expect(topmostMetrics.transform.getTranslation().y, 1);
    final topmostMouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await topmostMouse.addPointer(location: const Offset(1, 1));
    await topmostMouse.moveTo(tester.getCenter(topmostButton));
    await tester.pump();
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: topmostButton,
              matching: find.byKey(
                const ValueKey('paper-window-topmost-glyph-opacity'),
              ),
            ),
          )
          .opacity,
      1,
    );
    await topmostMouse.removePointer();
    await tester.pump();

    final titleHost = find.byKey(
      const ValueKey('paper-window-parity-title-host'),
    );
    expect(tester.getSize(titleHost).height, 24);
    expect(tester.getSize(titleHost).width, inInclusiveRange(38, 86));
    final titleDecoration = tester
        .widget<AnimatedContainer>(titleHost)
        .decoration! as BoxDecoration;
    expect(
      tester.widget<AnimatedContainer>(titleHost).duration,
      Duration.zero,
    );
    final titleBorder = titleDecoration.border! as Border;
    expect(
      titleBorder.bottom.color,
      headerColors.tint.withValues(alpha: 28 / 255),
    );
    final titleMetricsTransform = tester.widget<Transform>(
      find.byKey(
        const ValueKey('paper-window-parity-title-wpf-metrics'),
      ),
    );
    expect(titleMetricsTransform.transform.getTranslation().x, 1);
    expect(titleMetricsTransform.transform.getTranslation().y, 1);
    final titleDisplay = tester.widget<RichText>(
      find.byKey(const ValueKey('paper-window-parity-title-display')),
    );
    expect((titleDisplay.text as TextSpan).style?.letterSpacing, -0.1);
    final titleMouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await titleMouse.addPointer(location: const Offset(1, 1));
    await titleMouse.moveTo(tester.getCenter(titleHost));
    await tester.pump();
    expect(
      (tester.widget<AnimatedContainer>(titleHost).decoration! as BoxDecoration)
          .color,
      headerColors.hover,
    );
    await titleMouse.removePointer();

    await tester.tap(titleHost);
    await tester.pump();
    final titleDisplayLayer = tester.widget<Visibility>(
      find.byKey(
        const ValueKey('paper-window-parity-title-display-layer'),
      ),
    );
    final titleEditor = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('paper-window-parity-title')),
        matching: find.byType(EditableText),
      ),
    );
    expect(titleDisplayLayer.visible, false);
    expect(titleEditor.focusNode.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      tester
          .widget<Visibility>(
            find.byKey(
              const ValueKey('paper-window-parity-title-display-layer'),
            ),
          )
          .visible,
      true,
    );

    final actionOrder = [
      'paper-window-parity-desktop-pin',
      'paper-window-parity-new-todo',
      'paper-window-parity-new-note',
      'paper-window-parity-close',
    ].map((key) => tester.getCenter(find.byKey(ValueKey(key))).dx).toList();
    expect(actionOrder, orderedEquals(actionOrder.toList()..sort()));
    final newTodoAction = find.byKey(
      const ValueKey('paper-window-parity-new-todo'),
    );
    final newNoteAction = find.byKey(
      const ValueKey('paper-window-parity-new-note'),
    );
    final newTodoGlyph = tester.widget<Text>(
      find.descendant(
        of: newTodoAction,
        matching: find.text('\uFF0B\u2713'),
      ),
    );
    final newNoteGlyph = tester.widget<Text>(
      find.descendant(
        of: newNoteAction,
        matching: find.text('\uFF0B\u270E'),
      ),
    );
    expect(newTodoGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(newNoteGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(newTodoGlyph.style?.fontSize, 13);
    expect(newNoteGlyph.style?.fontSize, 13);
    expect(newTodoGlyph.style?.letterSpacing, -0.5);
    expect(newNoteGlyph.style?.letterSpacing, -0.75);
    final newTodoMetrics = tester.widget<Transform>(
      find.byKey(const ValueKey('paper-window-new-todo-glyph-metrics')),
    );
    final newNoteMetrics = tester.widget<Transform>(
      find.byKey(const ValueKey('paper-window-new-note-glyph-metrics')),
    );
    expect(newTodoMetrics.transform.getTranslation().x, -1);
    expect(newTodoMetrics.transform.getTranslation().y, 1);
    expect(newNoteMetrics.transform.getTranslation().x, -1);
    expect(newNoteMetrics.transform.getTranslation().y, 1);
    final closeGlyph = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('paper-window-parity-close')),
        matching: find.text('\u2500'),
      ),
    );
    expect(closeGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(closeGlyph.style?.fontSize, 16);
    final closeMetrics = tester.widget<Transform>(
      find.byKey(const ValueKey('paper-window-close-glyph-metrics')),
    );
    expect(closeMetrics.transform.getTranslation().x, -1);
    expect(closeMetrics.transform.getTranslation().y, 1);
    final desktopPinImage = tester.widget<Image>(
      find.descendant(
        of: find.byKey(
          const ValueKey('paper-window-parity-desktop-pin'),
        ),
        matching: find.byType(Image),
      ),
    );
    expect(
      (desktopPinImage.image as AssetImage).assetName,
      'assets/icons/pin.png',
    );
    expect(desktopPinImage.width, 15);
    expect(desktopPinImage.height, 15);
    expect(desktopPinImage.filterQuality, FilterQuality.low);
    final desktopPinMetrics = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(
          const ValueKey('paper-window-parity-desktop-pin'),
        ),
        matching: find.byKey(
          const ValueKey('paper-window-desktop-pin-glyph-metrics'),
        ),
      ),
    );
    expect(desktopPinMetrics.transform.getTranslation().x, -2);
    expect(desktopPinMetrics.transform.getTranslation().y, 0);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(
                const ValueKey('paper-window-parity-desktop-pin'),
              ),
              matching: find.byKey(
                const ValueKey('paper-window-desktop-pin-glyph-opacity'),
              ),
            ),
          )
          .opacity,
      0.72,
    );
    final newTodoIconButton = tester.widget<IconButton>(
      find.descendant(of: newTodoAction, matching: find.byType(IconButton)),
    );
    expect(
      newTodoIconButton.style?.overlayColor?.resolve(
        const <WidgetState>{WidgetState.hovered},
      ),
      headerColors.hover,
    );
    expect(
      newTodoIconButton.style?.overlayColor?.resolve(
        const <WidgetState>{WidgetState.pressed},
      ),
      headerColors.hover,
    );
    expect(
      newTodoIconButton.style?.foregroundColor?.resolve(
        const <WidgetState>{},
      ),
      headerColors.weakText,
    );
    expect(
      newTodoIconButton.style?.foregroundColor?.resolve(
        const <WidgetState>{WidgetState.hovered},
      ),
      headerColors.text,
    );
    expect(newTodoIconButton.style?.splashFactory, NoSplash.splashFactory);
    final newTodoPressedOpacity = find.ancestor(
      of: find.descendant(
        of: newTodoAction,
        matching: find.byType(IconButton),
      ),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(newTodoPressedOpacity).opacity, 1);
    final newTodoPress = await tester.startGesture(
      tester.getCenter(newTodoAction),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(tester.widget<Opacity>(newTodoPressedOpacity).opacity, 0.7);
    await newTodoPress.cancel();
    await newTodoPress.removePointer();
    await tester.pump();
    expect(tester.widget<Opacity>(newTodoPressedOpacity).opacity, 1);

    final dragHandle = find.byKey(
      const ValueKey('paper-window-parity-paper-window-first-drag-handle'),
    );
    final dragHandleSlot = find.byKey(
      const ValueKey(
        'paper-window-parity-paper-window-first-drag-handle-slot',
      ),
    );
    final thirdRow = find.byKey(
      const ValueKey('paper-window-parity-paper-window-third-row'),
    );
    final firstRow = find.byKey(
      const ValueKey('paper-window-parity-paper-window-first-row'),
    );
    expect(dragHandle, findsOneWidget);
    expect(thirdRow, findsOneWidget);
    expect(tester.getSize(firstRow).height, 34);
    expect(tester.getRect(firstRow).left, 15);
    expect(tester.getRect(firstRow).right, 265);
    expect(tester.getSize(dragHandleSlot), const Size(18, 24));
    expect(tester.getSize(dragHandle), const Size(14, 24));
    final dragGlyph = tester.widget<Text>(
      find.descendant(of: dragHandle, matching: find.text('\u2261')),
    );
    expect(dragGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(dragGlyph.style?.fontSize, 12);
    expect(dragGlyph.style?.height, 1);
    expect(dragGlyph.style?.color, headerColors.weakText);
    final dragGlyphOpacity = find.descendant(
      of: dragHandle,
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(dragGlyphOpacity).opacity, 0.48);
    final dragHandleMouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await dragHandleMouse.addPointer(location: const Offset(1, 1));
    await dragHandleMouse.moveTo(tester.getCenter(dragHandle));
    await tester.pump();
    expect(tester.widget<Opacity>(dragGlyphOpacity).opacity, 0.78);
    await dragHandleMouse.removePointer();
    await tester.pump();

    final firstCheckbox = find.byKey(
      const ValueKey(
        'paper-window-parity-paper-window-first-checkbox',
      ),
    );
    expect(firstCheckbox, findsOneWidget);
    expect(tester.getSize(firstCheckbox), const Size.square(16));
    final checkboxPaint = find.descendant(
      of: firstCheckbox,
      matching: find.byType(CustomPaint),
    );
    dynamic checkboxPainter() =>
        tester.widget<CustomPaint>(checkboxPaint).painter;
    expect(checkboxPainter().value, false);
    expect(checkboxPainter().hovered, false);
    expect(checkboxPainter().effectiveBorderRadius, 4.75);
    final checkboxMouse = await tester.createGesture(
      pointer: 41,
      kind: PointerDeviceKind.mouse,
    );
    await checkboxMouse.addPointer(location: const Offset(1, 1));
    await checkboxMouse.moveTo(tester.getCenter(firstCheckbox));
    await tester.pump();
    expect(checkboxPainter().hovered, true);
    await checkboxMouse.removePointer();
    await tester.pump();
    await tester.tap(firstCheckbox);
    await tester.pump();
    expect(paper.items.first.done, true);
    expect(checkboxPainter().value, true);
    expect(
      tester
          .getSize(find.byKey(
            const ValueKey('paper-window-parity-todo-delete-drop-target'),
          ))
          .height,
      38,
    );
    final appendArea = find.byKey(
      const ValueKey('paper-window-parity-todo-append-area'),
    );
    expect(appendArea, findsOneWidget);
    final appendContainer = tester.widget<Container>(appendArea);
    expect(
      appendContainer.margin,
      const EdgeInsets.only(top: 6, bottom: 2),
    );
    final appendDecoration = appendContainer.decoration! as BoxDecoration;
    expect(
      appendDecoration.color,
      headerColors.tint.withValues(alpha: 12 / 255),
    );
    expect(
      (appendDecoration.border! as Border).top.color,
      headerColors.tint.withValues(alpha: 45 / 255),
    );
    final appendOpacity = find.descendant(
      of: appendArea,
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(appendOpacity).opacity, 0.42);
    final appendGlyph = tester.widget<Text>(
      find.descendant(of: appendArea, matching: find.text('\uFF0B')),
    );
    expect(appendGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(appendGlyph.style?.fontSize, 14);
    expect(appendGlyph.style?.color, headerColors.weakText);
    final appendMouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await appendMouse.addPointer(location: const Offset(1, 1));
    await appendMouse.moveTo(tester.getCenter(appendArea));
    await tester.pump();
    expect(
      (tester.widget<Container>(appendArea).decoration! as BoxDecoration).color,
      headerColors.tint.withValues(alpha: 26 / 255),
    );
    expect(tester.widget<Opacity>(appendOpacity).opacity, 0.7);
    await appendMouse.removePointer();
    final reorderGesture = await tester.startGesture(
      tester.getCenter(dragHandle),
    );
    await reorderGesture.moveBy(const Offset(20, 0));
    await tester.pump();
    final draggingOpacity = find.descendant(
      of: firstRow,
      matching: find.byWidgetPredicate(
        (widget) => widget is AnimatedOpacity && widget.opacity == 0.25,
      ),
    );
    expect(draggingOpacity, findsOneWidget);
    await reorderGesture.moveTo(tester.getCenter(thirdRow));
    await tester.pump();
    await reorderGesture.up();
    await tester.pumpAndSettle();

    expect(paper.items.map((item) => item.id), [
      'paper-window-second',
      'paper-window-third',
      'paper-window-first',
    ]);

    final topmostAction =
        tester.widget<IconButton>(topmostIconButton).onPressed;
    expect(topmostAction, isNotNull);
    topmostAction!();
    await tester.pumpAndSettle();
    expect(paper.alwaysOnTop, true);
    expect(
      find.byKey(const ValueKey('paper-window-parity-topmost')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(
                const ValueKey('paper-window-parity-topmost'),
              ),
              matching: find.byKey(
                const ValueKey('paper-window-topmost-glyph-opacity'),
              ),
            ),
          )
          .opacity,
      1,
    );
  });

  testWidgets('independent note header keeps the PaperTodo link drag action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'paper-window-note-link',
      type: PaperTypes.note,
      title: 'Linked note',
      content: 'Drag this note from the title bar.',
      width: 360,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(
            enableTodoNoteLinks: true,
            papers: [paper],
          ),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(
      const ValueKey('paper-window-note-link-note-link-drag-action'),
    );
    final handle = find.byKey(
      const ValueKey('paper-window-note-link-note-link-drag-handle'),
    );
    expect(action, findsOneWidget);
    expect(tester.getSize(action), const Size(24, 24));
    expect(tester.getSize(handle), const Size(24, 24));
    final glyph = tester.widget<Text>(
      find.descendant(of: handle, matching: find.text('\u2316')),
    );
    expect(glyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(glyph.style?.fontSize, 13);
    expect(
      tester.getCenter(action).dx,
      lessThan(
        tester
            .getCenter(
              find.byKey(
                const ValueKey('paper-window-note-link-open-markdown'),
              ),
            )
            .dx,
      ),
    );
  });

  testWidgets('all Todo visual size metrics match PaperTodo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const cases = [
      (
        size: TodoVisualSizes.small,
        textSize: 12.0,
        textPadding: 2.5,
        rowHeight: 33.0,
        handleSlotWidth: 18.0,
        handleWidth: 14.0,
        handleHeight: 23.0,
        handleGlyph: 11.0,
        appendGlyph: 13.0,
      ),
      (
        size: TodoVisualSizes.medium,
        textSize: 13.0,
        textPadding: 3.0,
        rowHeight: 34.0,
        handleSlotWidth: 18.0,
        handleWidth: 14.0,
        handleHeight: 24.0,
        handleGlyph: 12.0,
        appendGlyph: 14.0,
      ),
      (
        size: TodoVisualSizes.large,
        textSize: 14.0,
        textPadding: 3.5,
        rowHeight: 36.0,
        handleSlotWidth: 20.0,
        handleWidth: 16.0,
        handleHeight: 26.0,
        handleGlyph: 13.0,
        appendGlyph: 15.0,
      ),
      (
        size: TodoVisualSizes.extraLarge,
        textSize: 15.5,
        textPadding: 4.5,
        rowHeight: 40.0,
        handleSlotWidth: 23.0,
        handleWidth: 19.0,
        handleHeight: 30.0,
        handleGlyph: 14.5,
        appendGlyph: 16.5,
      ),
    ];

    for (final visualCase in cases) {
      final suffix = visualCase.size;
      final paper = PaperData(
        id: 'todo-visual-$suffix',
        type: PaperTypes.todo,
        title: 'Todo1',
        items: [
          PaperItem(id: 'todo-visual-item-$suffix', text: 'Task'),
        ],
      );
      await tester.pumpWidget(
        RePaperTodoApp(
          key: ValueKey('todo-visual-app-$suffix'),
          controller: RePaperTodoController(
            initialState: AppState(
              theme: 'light',
              todoVisualSize: visualCase.size,
              papers: [paper],
            ),
            platform: _RecordingPlatformServices(),
          ),
          store: _MemoryStateStore(),
          initialSurfacePaperId: paper.id,
          paperWindowMode: true,
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(
        ValueKey('${paper.id}-${paper.items.single.id}-row'),
      );
      final textHost = find.byKey(
        ValueKey('${paper.id}-${paper.items.single.id}-text'),
      );
      final editable = tester.widget<EditableText>(
        find.descendant(of: textHost, matching: find.byType(EditableText)),
      );
      final textField = tester.widget<TextField>(
        find.descendant(of: textHost, matching: find.byType(TextField)),
      );
      expect(editable.style.fontSize, visualCase.textSize);
      expect(editable.style.letterSpacing, -0.0625);
      expect(
        textField.decoration?.contentPadding,
        EdgeInsets.fromLTRB(
          4,
          visualCase.textPadding + 1,
          0,
          visualCase.textPadding - 1,
        ),
      );
      expect(
        tester.getSize(row).height,
        visualCase.rowHeight,
        reason: visualCase.size,
      );

      final handle = find.byKey(
        ValueKey('${paper.id}-${paper.items.single.id}-drag-handle'),
      );
      final handleSlot = find.byKey(
        ValueKey('${paper.id}-${paper.items.single.id}-drag-handle-slot'),
      );
      expect(
        tester.getSize(handleSlot),
        Size(visualCase.handleSlotWidth, visualCase.handleHeight),
      );
      expect(
        tester.getSize(handle),
        Size(visualCase.handleWidth, visualCase.handleHeight),
      );
      final handleText = tester.widget<Text>(
        find.descendant(of: handle, matching: find.text('\u2261')),
      );
      expect(handleText.style?.fontFamily, 'Segoe UI Symbol');
      expect(handleText.style?.fontSize, visualCase.handleGlyph);
      expect(handleText.style?.height, 1);

      final appendArea = find.byKey(
        ValueKey('${paper.id}-todo-append-area'),
      );
      final appendGlyph = tester.widget<Text>(
        find.descendant(
          of: appendArea,
          matching: find.text('\uFF0B'),
        ),
      );
      expect(appendGlyph.style?.fontFamily, 'Segoe UI Symbol');
      expect(appendGlyph.style?.fontSize, visualCase.appendGlyph);
    }
  });

  testWidgets('DengXian Todo text keeps PaperTodo display advances',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final paper = PaperData(
      id: 'dengxian-metrics-paper',
      type: PaperTypes.todo,
      items: [
        PaperItem(
          id: 'dengxian-metrics-item',
          text: '中文待办用于校准等线字体的字形宽度和行高。',
        ),
      ],
    );
    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(
            theme: 'light',
            uiFontPreset: UiFontPresets.dengXian,
            papers: [paper],
          ),
          platform: _RecordingPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'dengxian-metrics-paper-dengxian-metrics-item-text',
          ),
        ),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.style.fontFamily, 'DengXian');
    expect(editable.style.fontSize, closeTo(12.5, 0.001));
    expect(editable.style.height, closeTo(13 / 12.5, 0.001));
  });

  testWidgets('todo and note paper windows resize from every native edge',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const directions = [
      'left',
      'right',
      'top',
      'bottom',
      'topLeft',
      'topRight',
      'bottomLeft',
      'bottomRight',
    ];

    for (final type in [PaperTypes.todo, PaperTypes.note]) {
      final paper = PaperData(
        id: 'resize-$type',
        type: type,
        title: 'Resizable $type',
        content: type == PaperTypes.note ? 'Resizable note body' : '',
        items: type == PaperTypes.todo
            ? [PaperItem(id: 'resize-todo-item', text: 'Resizable todo')]
            : [],
      );
      final started = <String>[];
      await tester.pumpWidget(
        RePaperTodoApp(
          key: ValueKey('resize-app-$type'),
          controller: RePaperTodoController(
            initialState: AppState(papers: [paper]),
            platform: NoopPlatformServices(),
          ),
          store: _MemoryStateStore(),
          initialSurfacePaperId: paper.id,
          paperWindowMode: true,
          paperWindowResizeStarter: (direction) async {
            started.add(direction);
          },
        ),
      );
      await tester.pumpAndSettle();

      for (final direction in directions) {
        final handle = find.byKey(
          ValueKey('paper-window-resize-$direction'),
        );
        expect(handle, findsOneWidget);
        await tester.tap(handle);
        await tester.pump();
      }
      expect(started, directions, reason: '$type must expose all HWND edges');

      final grip = find.descendant(
        of: find.byKey(const ValueKey('paper-window-resize-bottomRight')),
        matching: find.byType(CustomPaint),
      );
      expect(grip, findsOneWidget);
      final gripPainter = tester.widget<CustomPaint>(grip).painter as dynamic;
      expect(gripPainter.shouldRepaint(gripPainter), false);
      expect(
        gripPainter.topLeftColor,
        const Color(0xFFFAFBFB),
      );
      expect(
        gripPainter.topRightColor,
        const Color(0xFFC7CFDE),
      );
      expect(
        gripPainter.bottomLeftColor,
        const Color(0xFFE4E8EF),
      );
      expect(
        gripPainter.bottomRightColor,
        const Color(0xFFAAB7CD),
      );
      expect(gripPainter.dotCountsByBottomRow, const [4, 3, 2, 1]);
    }
  });

  testWidgets('desktop-pinned paper windows do not expose resize handles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'pinned-no-resize',
      title: 'Pinned paper',
      isPinnedToDesktop: true,
      items: [PaperItem(id: 'pinned-item', text: 'Desktop locked')],
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
        paperWindowResizeStarter: (_) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('paper-window-resize-bottomRight')),
      findsNothing,
    );
    expect(find.byTooltip('Unpin from desktop'), findsOneWidget);
  });

  testWidgets('desktop-pinned paper window only exposes unpin interaction',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'pinned-window-lock',
      title: 'Pinned window lock',
      isPinnedToDesktop: true,
      items: [PaperItem(id: 'pinned-lock-item', text: 'Locked')],
    );
    var dragStarts = 0;

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
        paperWindowDragStarter: () async => dragStarts += 1,
      ),
    );
    await tester.pumpAndSettle();

    final typeButton = find.descendant(
      of: find.byKey(const ValueKey('pinned-window-lock-topmost')),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(typeButton).onPressed, isNull);

    final header = find.byKey(
      const ValueKey('pinned-window-lock-paper-header'),
    );
    await tester.drag(header, const Offset(50, 20));
    await tester.pump();
    expect(dragStarts, 0);
    expect(paper.isPinnedToDesktop, true);

    final unpinImage = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('pinned-window-lock-desktop-pin')),
        matching: find.byType(Image),
      ),
    );
    expect(
      (unpinImage.image as AssetImage).assetName,
      'assets/icons/unpin.png',
    );

    await tester.tap(find.byTooltip('Unpin from desktop'));
    await tester.pumpAndSettle();
    expect(paper.isPinnedToDesktop, false);
  });

  testWidgets('paper window chrome honors PaperTodo top bar preferences',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'paper-window-hidden-actions',
      type: PaperTypes.todo,
      title: 'Focused paper',
      items: [PaperItem(id: 'focused-item', text: 'Only paper controls')],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        showTopBarNewTodoButton: false,
        showTopBarNewNoteButton: false,
        showTopBarExternalOpenButton: false,
        papers: [paper],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('paper-window-hidden-actions-new-todo')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('paper-window-hidden-actions-new-note')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('paper-window-hidden-actions-topmost')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('paper-window-hidden-actions-desktop-pin')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('paper-window-hidden-actions-close')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('paper-window-hidden-actions-sync-now')),
      findsNothing,
    );
  });

  testWidgets('paper window manual sync delegates to the coordinator',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'paper-window-sync',
      title: 'Sync paper',
      items: [PaperItem(id: 'sync-item', text: 'Sync')],
    );
    final actions = <String>[];

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
        paperWindowActionSender: (kind, {value = ''}) async {
          actions.add(kind);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('paper-window-sync-sync-now')),
    );
    await tester.pump();

    expect(actions, [PaperWindowActionKinds.syncNow]);
  });

  testWidgets('paper window actions remain anchored to the resized right edge',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'right-edge-actions',
      title: 'Right edge actions',
      items: [PaperItem(id: 'right-edge-item', text: 'Resize')],
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final close = find.byKey(const ValueKey('right-edge-actions-close'));
    final narrowRight = tester.getTopRight(close).dx;

    await tester.binding.setSurfaceSize(const Size(520, 420));
    await tester.pumpAndSettle();
    final wideRight = tester.getTopRight(close).dx;

    expect(wideRight - narrowRight, closeTo(160, 1));
    expect(wideRight, closeTo(503, 1));
  });

  testWidgets('minimum paper width keeps only the essential trailing action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(190, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'minimum-paper-actions',
      title: 'Small paper',
      width: 190,
      items: [PaperItem(id: 'minimum-paper-item', text: 'One task')],
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('minimum-paper-actions-close')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('minimum-paper-actions-desktop-pin')),
        findsNothing);
    expect(find.byKey(const ValueKey('minimum-paper-actions-sync-now')),
        findsNothing);
    expect(find.byKey(const ValueKey('minimum-paper-actions-new-todo')),
        findsNothing);
    expect(find.byKey(const ValueKey('minimum-paper-actions-new-note')),
        findsNothing);
  });

  testWidgets('PaperTodo base header actions survive at 220 logical pixels',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(220, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'paper-window-actions-220',
      title: 'Todo1',
      width: 220,
      items: [PaperItem(id: 'paper-window-actions-220-item', text: 'One task')],
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final suffix in [
      'desktop-pin',
      'new-todo',
      'new-note',
      'close',
    ]) {
      expect(
        find.byKey(ValueKey('paper-window-actions-220-$suffix')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('paper-window-actions-220-sync-now')),
      findsNothing,
    );
    final baseActionCenters = [
      'desktop-pin',
      'new-todo',
      'new-note',
      'close',
    ]
        .map(
          (suffix) => tester
              .getCenter(
                find.byKey(ValueKey('paper-window-actions-220-$suffix')),
              )
              .dx,
        )
        .toList();
    expect(
        baseActionCenters, orderedEquals(baseActionCenters.toList()..sort()));
    expect(
      tester
          .getTopRight(
            find.byKey(const ValueKey('paper-window-actions-220-close')),
          )
          .dx,
      closeTo(203, 1),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('paper-window-actions-220-title-host')),
          )
          .width,
      inInclusiveRange(38, 46),
    );
  });

  testWidgets('narrow Todo widths keep source titles before showing sync',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in <double>[280, 320]) {
      await tester.binding.setSurfaceSize(Size(width, 340));
      final suffix = width.toInt();
      final paper = PaperData(
        id: 'paper-window-actions-$suffix-no-sync',
        title: 'Todo1',
        width: width,
        height: 340,
        items: [
          PaperItem(
            id: 'paper-window-actions-$suffix-no-sync-item',
            text: 'One task',
          ),
        ],
      );
      await tester.pumpWidget(
        RePaperTodoApp(
          key: ValueKey('paper-window-actions-$suffix-no-sync-app'),
          controller: RePaperTodoController(
            initialState: AppState(papers: [paper]),
            platform: NoopPlatformServices(),
          ),
          store: _MemoryStateStore(),
          initialSurfacePaperId: paper.id,
          paperWindowMode: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('paper-window-actions-$suffix-no-sync-sync-now')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('paper-window-actions-$suffix-no-sync-title')),
        findsOneWidget,
      );
    }
  });

  testWidgets('sync extends wider headers without moving base actions',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final trailingOffsets = <double>[];

    for (final width in <double>[440, 560]) {
      await tester.binding.setSurfaceSize(Size(width, 320));
      final paper = PaperData(
        id: 'paper-window-actions-${width.toInt()}',
        title: 'Todo1',
        width: width,
        items: [
          PaperItem(
            id: 'paper-window-actions-${width.toInt()}-item',
            text: 'One task',
          ),
        ],
      );

      await tester.pumpWidget(
        RePaperTodoApp(
          key: ValueKey('paper-window-actions-app-${width.toInt()}'),
          controller: RePaperTodoController(
            initialState: AppState(papers: [paper]),
            platform: NoopPlatformServices(),
          ),
          store: _MemoryStateStore(),
          initialSurfacePaperId: paper.id,
          paperWindowMode: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'width $width overflowed');
      final prefix = 'paper-window-actions-${width.toInt()}';
      final order = [
        'sync-now',
        'desktop-pin',
        'new-todo',
        'new-note',
        'close',
      ].map((suffix) {
        final finder = find.byKey(ValueKey('$prefix-$suffix'));
        expect(finder, findsOneWidget);
        return tester.getCenter(finder).dx;
      }).toList();
      expect(order, orderedEquals(order.toList()..sort()));
      trailingOffsets.add(
        width - tester.getTopRight(find.byKey(ValueKey('$prefix-close'))).dx,
      );
    }

    for (final offset in trailingOffsets) {
      expect(offset, closeTo(17, 1));
    }
  });

  testWidgets('default note width reveals the PaperTodo base actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'default-note-actions',
      type: PaperTypes.note,
      title: 'A deliberately long note title for the header',
      width: 320,
      content: 'Note body',
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final suffix in [
      'open-markdown',
      'desktop-pin',
      'new-todo',
      'new-note',
      'close',
    ]) {
      expect(
        find.byKey(ValueKey('default-note-actions-$suffix')),
        findsOneWidget,
      );
    }
    final titleHost =
        find.byKey(const ValueKey('default-note-actions-title-host'));
    expect(tester.getSize(titleHost).width, inInclusiveRange(38, 86));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('default-note-actions-topmost')),
        matching: find.text('\u270E'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('narrow notes keep their title clear before showing sync',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'narrow-note-actions',
      type: PaperTypes.note,
      title: 'Note1',
      width: 280,
      height: 420,
      content: 'Note body',
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('narrow-note-actions-sync-now')),
        findsNothing);
    for (final suffix in [
      'note-link-drag-action',
      'open-markdown',
      'desktop-pin',
      'new-todo',
      'new-note',
      'close',
    ]) {
      expect(
        find.byKey(ValueKey('narrow-note-actions-$suffix')),
        findsOneWidget,
      );
    }
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('narrow-note-actions-title-host')),
          )
          .width,
      inInclusiveRange(38, 86),
    );
  });

  testWidgets('fractional DPI keeps PaperTodo paper geometry in logical pixels',
      (tester) async {
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    for (final devicePixelRatio in <double>[1.25, 1.5]) {
      tester.view
        ..devicePixelRatio = devicePixelRatio
        ..physicalSize = Size(
          280 * devicePixelRatio,
          420 * devicePixelRatio,
        );
      final suffix = devicePixelRatio.toString().replaceAll('.', '-');
      final paper = PaperData(
        id: 'fractional-dpi-note-$suffix',
        type: PaperTypes.note,
        title: 'Note1',
        width: 280,
        height: 420,
        content: '# Fractional DPI\n\nPaper geometry',
      );

      await tester.pumpWidget(
        RePaperTodoApp(
          key: ValueKey('fractional-dpi-app-$suffix'),
          controller: RePaperTodoController(
            initialState: AppState(papers: [paper]),
            platform: NoopPlatformServices(),
          ),
          store: _MemoryStateStore(),
          initialSurfacePaperId: paper.id,
          paperWindowMode: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '$devicePixelRatio DPR overflowed',
      );
      expect(
        tester.getRect(find.byType(PaperPreview)),
        const Rect.fromLTWH(8, 8, 264, 404),
      );
      expect(
        tester.getSize(
          find.byKey(ValueKey('${paper.id}-paper-header')),
        ),
        const Size(264, 31),
      );
      expect(
        tester.getTopRight(find.byKey(ValueKey('${paper.id}-close'))).dx,
        closeTo(263, 0.01),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('note-status-bar'))).height,
        26,
      );
      expect(
        tester.getBottomRight(find.byKey(const ValueKey('note-status-bar'))),
        const Offset(272, 412),
      );
    }
  });

  testWidgets(
      'multi-column due rows stay readable across PaperTodo paper widths',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in <double>[220, 280, 320, 440, 560]) {
      await tester.binding.setSurfaceSize(Size(width, 380));
      final paper = PaperData(
        id: 'responsive-due-${width.toInt()}',
        title: 'Responsive due row',
        width: width,
        height: 380,
        items: [
          PaperItem(
            id: 'responsive-due-item-${width.toInt()}',
            text: 'Finish the Windows visual parity review',
            todoColumnCount: 2,
            todoExtraColumns: const ['High priority'],
            todoColumnWidths: const [2.1, 1],
            dueAtLocal: '2099-07-18T18:30:00',
          ),
        ],
      );
      await tester.pumpWidget(
        RePaperTodoApp(
          key: ValueKey('responsive-due-app-${width.toInt()}'),
          controller: RePaperTodoController(
            initialState: AppState(
              showTodoDueRelativeTime: true,
              papers: [paper],
            ),
            platform: NoopPlatformServices(),
          ),
          store: _MemoryStateStore(),
          initialSurfacePaperId: paper.id,
          paperWindowMode: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'width $width overflowed');
      expect(
        find.byKey(
          ValueKey('${paper.id}-${paper.items.single.id}-due-absolute'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey('${paper.id}-${paper.items.single.id}-due-relative'),
        ),
        findsOneWidget,
      );
      if (width == 220) {
        expect(
          tester
              .getSize(
                find.byKey(
                  ValueKey(
                    '${paper.id}-${paper.items.single.id}-due-relative-surface',
                  ),
                ),
              )
              .width,
          greaterThan(100),
        );
      }
      if (width == 220 || width == 560) {
        expect(
          find.byKey(ValueKey('${paper.id}-${paper.items.single.id}-text')),
          width == 220 ? findsNothing : findsOneWidget,
        );
      }
    }
  });

  testWidgets('settings can choose an installed system font family',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices(
      installedFontFamilies: const ['Microsoft YaHei UI', 'Paper Sans'],
    );
    final controller = RePaperTodoController(
      initialState: AppState(theme: 'light'),
      platform: platform,
    );
    final store = StateStore(filePath: 'build/test-widget-custom-font.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    final compactActions = find.byKey(
      const ValueKey('compact-app-bar-actions'),
    );
    if (compactActions.evaluate().isNotEmpty) {
      await tester.tap(compactActions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
    } else {
      await tester.tap(find.byIcon(Icons.settings_outlined).last);
    }
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-category-navigation')),
      findsOneWidget,
    );
    expect(find.text('Font preset'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('settings-category-capsules')),
    );
    await tester.pumpAndSettle();
    expect(
      _settingsToggleTile('Capsule mode'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-category-display')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('settings-custom-font-family-field')),
      'Paper',
    );
    await tester.pumpAndSettle();
    expect(find.text('Paper Sans'), findsOneWidget);

    await tester.tap(find.text('Paper Sans'));
    await tester.pumpAndSettle();
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.uiFontPreset, UiFontPresets.defaultPreset);
    expect(controller.state.systemFontFamilyName, 'Paper Sans');
  });

  testWidgets('settings toggles and close button match PaperTodo chrome',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        useCapsuleMode: false,
        papers: [
          PaperData(
            id: 'settings-chrome-paper',
            title: 'Settings chrome',
            items: [PaperItem(id: 'settings-chrome-item')],
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

    final themeSelectorRoot =
        find.byKey(const ValueKey('settings-theme-selector'));
    final sourceSegmentSelector = find.descendant(
      of: themeSelectorRoot,
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SettingsSegmentSelector',
      ),
    );
    expect(sourceSegmentSelector, findsOneWidget);
    expect(tester.getSize(sourceSegmentSelector).height, 28);
    expect(
      find.descendant(
        of: themeSelectorRoot,
        matching: find.byType(SegmentedButton<String>),
      ),
      findsNothing,
    );
    final settingsColors =
        PaperTodoThemeColors.of(tester.element(sourceSegmentSelector));
    Text segmentText(String label) => tester.widget<Text>(
          find.descendant(
            of: themeSelectorRoot,
            matching: find.text(label),
          ),
        );
    expect(segmentText('System').style?.fontSize, 12);
    expect(segmentText('System').style?.fontWeight, FontWeight.w400);
    expect(segmentText('System').style?.color, settingsColors.text);
    expect(segmentText('Light').style?.fontWeight, FontWeight.w600);
    expect(segmentText('Light').style?.color, settingsColors.paper);
    final darkSegment = find.ancestor(
      of: find.descendant(
        of: themeSelectorRoot,
        matching: find.text('Dark'),
      ),
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SettingsSegmentButton',
      ),
    );
    final darkSurface = find.descendant(
      of: darkSegment,
      matching: find.byType(DecoratedBox),
    );
    BoxDecoration darkDecoration() =>
        tester.widget<DecoratedBox>(darkSurface).decoration as BoxDecoration;
    expect(darkDecoration().color, Colors.transparent);
    final segmentMouse = await tester.createGesture(
      pointer: 60,
      kind: PointerDeviceKind.mouse,
    );
    await segmentMouse.addPointer(location: const Offset(1, 1));
    await segmentMouse.moveTo(tester.getCenter(darkSegment));
    await tester.pump();
    expect(darkDecoration().color, settingsColors.hover);
    await segmentMouse.removePointer();
    await tester.pump();

    await _selectSettingsCategory(tester, 'capsules');

    final capsuleToggle = _settingsToggleTile('Capsule mode');
    final deepCapsuleToggle = _settingsToggleTile('Edge capsule mode');
    await tester.ensureVisible(capsuleToggle);
    await tester.pump();
    expect(tester.getSize(capsuleToggle).height, 22);
    final dynamic capsuleTile = tester.widget(capsuleToggle);
    final dynamic deepCapsuleTile = tester.widget(deepCapsuleToggle);
    expect(capsuleTile.value, false);
    expect(capsuleTile.onChanged, isNotNull);
    expect(deepCapsuleTile.onChanged, isNull);
    final disabledOpacity = tester.widget<Opacity>(
      find.descendant(
        of: deepCapsuleToggle,
        matching: find.byType(Opacity),
      ),
    );
    expect(disabledOpacity.opacity, 0.55);

    final markPaint = find.descendant(
      of: capsuleToggle,
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(markPaint), const Size.square(16));
    dynamic markPainter() => tester.widget<CustomPaint>(markPaint).painter;
    expect(markPainter().value, false);
    expect(markPainter().hovered, false);

    final capsuleHelp = find.byTooltip(
      'Allow papers to collapse into small capsules to save desktop space. '
      'Edge capsule features require this first.',
    );
    expect(capsuleHelp, findsOneWidget);
    expect(tester.getSize(capsuleHelp), const Size.square(18));
    final capsuleHelpGlyph = tester.widget<Text>(
      find.descendant(of: capsuleHelp, matching: find.text('\u24D8')),
    );
    expect(capsuleHelpGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(capsuleHelpGlyph.style?.fontSize, 12);
    await tester.tap(capsuleHelp);
    await tester.pump();
    expect((tester.widget(capsuleToggle) as dynamic).value, false);

    final toggleMouse = await tester.createGesture(
      pointer: 61,
      kind: PointerDeviceKind.mouse,
    );
    await toggleMouse.addPointer(location: const Offset(1, 1));
    await toggleMouse.moveTo(tester.getCenter(capsuleToggle));
    await tester.pump();
    expect(markPainter().hovered, true);
    await toggleMouse.removePointer();
    await tester.pump();

    await tester.tap(capsuleToggle);
    await tester.pump();
    expect((tester.widget(capsuleToggle) as dynamic).value, true);
    expect(markPainter().value, true);
    expect((tester.widget(deepCapsuleToggle) as dynamic).onChanged, isNotNull);

    final closeSurface = find.byKey(
      const ValueKey('settings-close-button-surface'),
    );
    expect(tester.getSize(closeSurface), const Size(28, 24));
    final closeGlyph = tester.widget<Text>(
      find.descendant(of: closeSurface, matching: find.text('\u00D7')),
    );
    final closeColors = PaperTodoThemeColors.of(tester.element(closeSurface));
    BoxDecoration closeDecoration() =>
        tester.widget<Container>(closeSurface).decoration! as BoxDecoration;
    expect(closeGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(closeGlyph.style?.fontSize, 16);
    expect(closeGlyph.style?.color, closeColors.weakText);
    expect(closeDecoration().color, Colors.transparent);

    final closeMouse = await tester.createGesture(
      pointer: 62,
      kind: PointerDeviceKind.mouse,
    );
    await closeMouse.addPointer(location: const Offset(1, 1));
    await closeMouse.moveTo(tester.getCenter(closeSurface));
    await tester.pump();
    expect(closeDecoration().color, closeColors.hover);
    expect(
      tester
          .widget<Text>(
            find.descendant(of: closeSurface, matching: find.text('\u00D7')),
          )
          .style
          ?.color,
      closeColors.text,
    );
    await closeMouse.removePointer();
    await tester.pump();

    final closePress = await tester.startGesture(
      tester.getCenter(closeSurface),
      pointer: 63,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(closeDecoration().color, closeColors.active);
    expect(
      tester
          .widget<Text>(
            find.descendant(of: closeSurface, matching: find.text('\u00D7')),
          )
          .style
          ?.color,
      closeColors.paper,
    );
    await closePress.cancel();
    await closePress.removePointer();
    await tester.pump();

    const authorUrl = 'https://github.com/snownico0722';
    final authorLink = find.byTooltip(authorUrl);
    expect(authorLink, findsOneWidget);
    final authorText = find.descendant(
      of: authorLink,
      matching: find.text('Designed by trigger'),
    );
    expect(tester.widget<Text>(authorText).style?.fontSize, 11);
    final authorMouse = await tester.createGesture(
      pointer: 64,
      kind: PointerDeviceKind.mouse,
    );
    await authorMouse.addPointer(location: const Offset(1, 1));
    await authorMouse.moveTo(tester.getCenter(authorLink));
    await tester.pump();
    expect(tester.widget<Text>(authorText).style?.color, closeColors.text);
    await authorMouse.removePointer();
    await tester.pump();
    await tester.tap(authorLink);
    await tester.pump();
    expect(platform.uriOpener.openedUris, [authorUrl]);
  });

  testWidgets('cleans paper title edits with PaperTodo hard title rules',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        maxTitleLength: 20,
        papers: [
          PaperData(
            id: 'title-clean-paper',
            type: PaperTypes.note,
            title: 'Title clean',
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

    final longTitle =
        '${List.filled(PaperTitles.maxTitleLength + 5, 'A').join()}\u0000B';
    await tester.enterText(
      find.byKey(const ValueKey('title-clean-paper-title')),
      longTitle,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final expected = List.filled(PaperTitles.maxTitleLength, 'A').join();
    expect(controller.state.papers.single.title, expected);
    expect(controller.state.papers.single.title, isNot(contains('\u0000')));
    expect(platform.paperWindows.updatedTitles, contains(expected));
  });

  testWidgets('paper title click enters edit mode and Escape cancels',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'title-escape-paper',
            type: PaperTypes.note,
            title: 'Original title',
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

    final titleFinder = find.byKey(const ValueKey('title-escape-paper-title'));
    TextField titleTextField() => tester.widget<TextField>(
          find.descendant(of: titleFinder, matching: find.byType(TextField)),
        );

    expect(titleTextField().readOnly, true);

    await tester.tap(titleFinder);
    await tester.pump();

    expect(titleTextField().readOnly, false);

    await tester.enterText(titleFinder, 'Temporary title');
    await tester.pump();
    expect(controller.state.papers.single.title, 'Temporary title');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(titleTextField().readOnly, true);
    expect(controller.state.papers.single.title, 'Original title');
    expect(find.text('Original title'), findsOneWidget);
    expect(platform.paperWindows.updatedTitles, contains('Original title'));
  });

  testWidgets('paper title Enter ends edit mode and keeps the edited title',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'title-enter-paper',
            type: PaperTypes.todo,
            title: 'Before enter',
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

    final titleFinder = find.byKey(const ValueKey('title-enter-paper-title'));
    TextField titleTextField() => tester.widget<TextField>(
          find.descendant(of: titleFinder, matching: find.byType(TextField)),
        );

    await tester.tap(titleFinder);
    await tester.pump();
    await tester.enterText(titleFinder, 'After enter');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(titleTextField().readOnly, true);
    expect(controller.state.papers.single.title, 'After enter');
    expect(find.text('After enter'), findsOneWidget);
  });

  testWidgets('blank paper titles fall back to PaperTodo default titles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        enableTodoNoteLinks: true,
        showLinkedNoteName: true,
        papers: [
          PaperData(
            id: 'blank-title-todo',
            type: PaperTypes.todo,
            title: '   ',
            items: [
              PaperItem(
                id: 'blank-title-item',
                text: 'Use fallback note title',
                linkedNoteId: 'blank-title-note-2',
              ),
            ],
          ),
          PaperData(
            id: 'blank-title-note-1',
            type: PaperTypes.note,
            title: '',
            content: 'First blank note',
          ),
          PaperData(
            id: 'blank-title-note-2',
            type: PaperTypes.note,
            title: '\u0000',
            content: 'Second blank note',
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

    expect(find.text('Todo1'), findsOneWidget);
    expect(find.text('Note1'), findsOneWidget);
    expect(find.text('Note2'), findsOneWidget);
    expect(find.text('Not…'), findsOneWidget);
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
            content: '# Research note\n\n'
                '- Extract claims\n'
                '> Quote\n'
                '**Strong** and `code`\n'
                '[Link](https://example.com/paper)',
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

    expect(find.text('Edit'), findsNothing);
    expect(find.byKey(const ValueKey('note-paper-preview')), findsOneWidget);
    expect(find.text('Split'), findsNothing);
    expect(find.byKey(const ValueKey('note-status-mode')), findsOneWidget);
    final source = find.byType(PaperTodoMarkdownSourcePreview);
    expect(source, findsOneWidget);
    expect(
      tester.widget<PaperTodoMarkdownSourcePreview>(source).enhanced,
      isTrue,
    );
    final paperColors = PaperTodoThemeColors.of(tester.element(source));
    final syntaxColor = paperColors.text.withValues(
      alpha: paperColors.isDark ? 78 / 255 : 72 / 255,
    );
    final headingMarker = _sourceMarkdownTextSpan(tester, source, '# ');
    final heading = _sourceMarkdownTextSpan(tester, source, 'Research note');
    final listMarker = _sourceMarkdownTextSpan(tester, source, '-');
    final quoteMarker = _sourceMarkdownTextSpan(tester, source, '> ');
    final quote = _sourceMarkdownTextSpan(tester, source, 'Quote');
    final strong = _sourceMarkdownTextSpan(tester, source, 'Strong');
    final code = _sourceMarkdownTextSpan(tester, source, 'code');
    final link = _sourceMarkdownTextSpan(tester, source, 'Link');
    final rawUrl =
        _sourceMarkdownTextSpan(tester, source, 'https://example.com/paper');

    expect(headingMarker.style?.color, syntaxColor);
    expect(headingMarker.style?.fontSize, 19);
    expect(heading.style?.fontSize, 19);
    expect(heading.style?.fontWeight, FontWeight.w600);
    expect(heading.style?.fontFamily, 'Microsoft YaHei UI');
    expect(heading.style?.fontFamilyFallback, contains('Segoe UI'));
    expect(listMarker.style?.color, Colors.transparent);
    expect(
      find.byKey(const ValueKey('papertodo-markdown-list-marker-2')),
      findsOneWidget,
    );
    expect(quoteMarker.style?.color, Colors.transparent);
    expect(quote.style?.color, paperColors.weakText);
    expect(quote.style?.height, 1.26);
    expect(strong.style?.fontWeight, FontWeight.w600);
    expect(code.style?.fontFamily, 'Cascadia Mono');
    expect(code.style?.fontSize, 13);
    expect(code.style?.color, paperColors.active);
    expect(link.style?.color, paperColors.link);
    expect(link.style?.decoration, TextDecoration.underline);
    expect(rawUrl.style?.color, syntaxColor);
    final headingBackground = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('papertodo-markdown-background-0')),
    );
    expect(headingBackground.painter, isNotNull);
  });

  testWidgets('empty PaperTodo note windows open directly in the editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'empty-note-window',
      type: PaperTypes.note,
      title: 'Empty note',
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(
            markdownRenderMode: MarkdownRenderModes.enhanced,
            papers: [paper],
          ),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('empty-note-window-preview')), findsNothing);
    final editorHost = find.byKey(
      const ValueKey('empty-note-window-content'),
    );
    expect(editorHost, findsOneWidget);
    final editor = tester.widget<TextField>(
      find.descendant(of: editorHost, matching: find.byType(TextField)),
    );
    expect(editor.decoration?.hintText, isNull);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('_No note content._'), findsNothing);
  });

  testWidgets(
      'independent note windows preserve the Markdown viewport while editing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'scroll-preserving-note-window',
      type: PaperTypes.note,
      title: 'Long note',
      content: List.generate(120, (index) => 'Line $index').join('\n'),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(
            markdownRenderMode: MarkdownRenderModes.enhanced,
            papers: [paper],
          ),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final previewScroll = find.byKey(const ValueKey('note-preview-scroll'));
    final sharedController =
        tester.widget<SingleChildScrollView>(previewScroll).controller!;
    final previewScrollbar = tester.widget<Scrollbar>(
      find.byKey(const ValueKey('note-preview-scrollbar')),
    );
    expect(previewScrollbar.controller, same(sharedController));
    expect(previewScrollbar.thumbVisibility, true);
    await tester.drag(previewScroll, const Offset(0, -220));
    await tester.pumpAndSettle();
    final previewOffset = sharedController.offset;
    expect(previewOffset, greaterThan(0));

    await _enterNoteEditor(tester, paper.id);
    await tester.pump();

    final editor = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey('${paper.id}-content')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editor.scrollController, isNot(same(sharedController)));
    expect(editor.scrollController!.offset, closeTo(previewOffset, 1));
    final editorScrollbar = tester.widget<Scrollbar>(
      find.byKey(const ValueKey('note-editor-scrollbar')),
    );
    expect(editorScrollbar.controller, same(editor.scrollController));
    expect(editorScrollbar.thumbVisibility, true);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();

    final restoredPreview = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('note-preview-scroll')),
    );
    expect(restoredPreview.controller, same(sharedController));
    expect(restoredPreview.controller!.offset, closeTo(previewOffset, 1));
  });

  testWidgets(
      'independent note windows use the compact PaperTodo Markdown menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'desktop-markdown-menu-note',
      type: PaperTypes.note,
      title: 'Markdown menu',
      content: 'Body',
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();
    await _enterNoteEditor(tester, paper.id);

    final field = find.byKey(ValueKey('${paper.id}-content'));
    await tester.tapAt(
      tester.getCenter(field),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    final formatHeader = _popupMenuItemWithText('Format');
    final boldItem = _popupMenuItemWithText('Bold');
    expect(tester.widget<PopupMenuItem<String>>(formatHeader).height, 17);
    expect(tester.widget<PopupMenuItem<String>>(boldItem).height, 21);
    expect(
      find.descendant(of: boldItem, matching: find.byType(Icon)),
      findsNothing,
    );
  });

  testWidgets('renders PaperTodo Basic markdown as styled source',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.basic,
        papers: [
          PaperData(
            id: 'basic-source-note',
            type: PaperTypes.note,
            title: 'Basic source note',
            content: '# Heading\n'
                '**Bold** and `code`\n'
                '[Link](https://example.com/basic)\n'
                '> Quote\n'
                '---\n'
                '```\n'
                'block code\n'
                '```',
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

    final source = find.byType(PaperTodoMarkdownSourcePreview);
    expect(source, findsOneWidget);
    expect(find.text('# Heading'), findsOneWidget);
    expect(find.text('**Bold** and `code`'), findsOneWidget);
    expect(find.text('[Link](https://example.com/basic)'), findsOneWidget);

    final colors = PaperTodoThemeColors.of(tester.element(source));
    final headingMarker = _sourceMarkdownTextSpan(tester, source, '# ');
    final headingText = _sourceMarkdownTextSpan(tester, source, 'Heading');
    final boldText = _sourceMarkdownTextSpan(tester, source, 'Bold');
    final inlineCode = _sourceMarkdownTextSpan(tester, source, 'code');
    final fencedCode = _sourceMarkdownTextSpan(tester, source, 'block code');
    final quoteText = _sourceMarkdownTextSpan(tester, source, 'Quote');
    final linkLabel = _sourceMarkdownTextSpan(tester, source, 'Link');
    final linkUrl =
        _sourceMarkdownTextSpan(tester, source, 'https://example.com/basic');

    expect(headingMarker.style?.fontSize, 19);
    expect(headingMarker.style?.fontWeight, FontWeight.w600);
    expect(headingMarker.style?.color, colors.active);
    expect(headingText.style?.fontSize, 19);
    expect(headingText.style?.fontWeight, FontWeight.w600);
    expect(boldText.style?.fontWeight, FontWeight.w600);
    expect(boldText.style?.letterSpacing, -0.09);
    expect(quoteText.style?.letterSpacing, 0.05);
    expect(inlineCode.style?.fontFamily, 'Cascadia Mono');
    expect(inlineCode.style?.fontSize, 13);
    expect(inlineCode.style?.color, colors.active);
    expect(fencedCode.style?.fontFamily, 'Cascadia Mono');
    expect(fencedCode.style?.fontSize, 13);
    expect(fencedCode.style?.color, colors.text);
    expect(fencedCode.style?.letterSpacing, 0.4);
    expect(linkLabel.style?.color, colors.link);
    expect(linkLabel.style?.decoration, TextDecoration.underline);
    expect(linkUrl.style?.color, colors.weakText);
    expect(linkLabel.recognizer, isA<TapGestureRecognizer>());
    expect(linkUrl.recognizer, same(linkLabel.recognizer));

    final headingBackground = find.byKey(
      const ValueKey('papertodo-markdown-background-0'),
    );
    expect(tester.widget<CustomPaint>(headingBackground).painter, isNotNull);
    expect(
      tester
          .widget<Positioned>(find.ancestor(
            of: headingBackground,
            matching: find.byType(Positioned),
          ))
          .right,
      0,
    );

    final quoteBackground = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('papertodo-markdown-background-3')),
    );
    expect(quoteBackground.painter, isNotNull);
    final headingPainter =
        tester.widget<CustomPaint>(headingBackground).painter as dynamic;
    final quotePainter = quoteBackground.painter as dynamic;
    expect(headingPainter.leftInset, 1);
    expect(headingPainter.rightInset, 8);
    expect(headingPainter.cornerRadius, 5);
    expect(quotePainter.leftInset, 1);
    expect(quotePainter.rightInset, 8);
    expect(quotePainter.cornerRadius, 4);
    Offset markdownPaintOffset(int index) {
      final translation = tester
          .widget<Transform>(
            find.byKey(ValueKey('papertodo-markdown-line-metrics-$index')),
          )
          .transform
          .getTranslation();
      return Offset(translation.x, translation.y);
    }

    expect(markdownPaintOffset(0), const Offset(-1, 2));
    expect(
      find.byKey(const ValueKey('papertodo-markdown-line-metrics-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('papertodo-markdown-line-metrics-2')),
      findsNothing,
    );
    expect(markdownPaintOffset(3), const Offset(-1, 0));
    expect(markdownPaintOffset(5), const Offset(0, -2));
    expect(markdownPaintOffset(6), const Offset(0, -2));
    expect(markdownPaintOffset(7), const Offset(0, -2));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('papertodo-markdown-line-4')),
        matching: find.byType(Divider),
      ),
      findsOneWidget,
    );
    final codeBackground = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('papertodo-markdown-background-6')),
    );
    expect(codeBackground.painter, isNotNull);
    final openingCodePainter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('papertodo-markdown-background-5')),
        )
        .painter as dynamic;
    final codePainter = codeBackground.painter as dynamic;
    final closingCodePainter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('papertodo-markdown-background-7')),
        )
        .painter as dynamic;
    expect(codePainter.leftInset, 4);
    expect(codePainter.rightInset, 11);
    expect(codePainter.cornerRadius, 6);
    expect(openingCodePainter.codeContinuesAbove, isFalse);
    expect(openingCodePainter.codeContinuesBelow, isTrue);
    expect(codePainter.codeContinuesAbove, isTrue);
    expect(codePainter.codeContinuesBelow, isTrue);
    expect(closingCodePainter.codeContinuesAbove, isTrue);
    expect(closingCodePainter.codeContinuesBelow, isFalse);
  });

  testWidgets('enhanced Markdown list markers keep PaperTodo wrap metrics',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 351,
              child: PaperTodoMarkdownSourcePreview(
                data: '- First list item with enough words to wrap naturally '
                    'inside a narrow paper window.',
                textZoom: 1,
                lineSpacing: 1,
                enhanced: true,
                onTapLink: _ignoreMarkdownLink,
              ),
            ),
          ),
        ),
      ),
    );

    final source = find.byType(PaperTodoMarkdownSourcePreview);
    final firstListMetrics = tester.widget<Transform>(
      find.byKey(const ValueKey('papertodo-markdown-line-metrics-0')),
    );
    expect(firstListMetrics.transform.getTranslation().x, 0);
    expect(firstListMetrics.transform.getTranslation().y, -2);
    final hiddenMarkers = tester
        .widgetList<Text>(
          find.descendant(of: source, matching: find.byType(Text)),
        )
        .expand(
          (widget) => widget.textSpan == null
              ? const <TextSpan>[]
              : _allTextSpans(widget.textSpan!),
        )
        .where((span) => span.style?.color == Colors.transparent);
    expect(hiddenMarkers, isNotEmpty);
    expect(hiddenMarkers.any((span) => span.style?.fontSize == 12), isTrue);
    expect(
      find.byKey(const ValueKey('papertodo-markdown-list-marker-0')),
      findsOneWidget,
    );
  });

  testWidgets('Basic markdown links open without entering the editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.basic,
        papers: [
          PaperData(
            id: 'basic-link-note',
            type: PaperTypes.note,
            title: 'Basic link note',
            content: '[Open Basic](https://example.com/basic)\nPlain body',
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

    final source = find.byType(PaperTodoMarkdownSourcePreview);
    final link = _sourceMarkdownTextSpan(tester, source, 'Open Basic');
    (link.recognizer! as TapGestureRecognizer).onTap?.call();
    await tester.pump();

    expect(platform.uriOpener.openedUris, ['https://example.com/basic']);
    expect(
        find.byKey(const ValueKey('basic-link-note-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('basic-link-note-content')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('basic-link-note-preview')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump();

    expect(
        find.byKey(const ValueKey('basic-link-note-content')), findsOneWidget);
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
    expect(
      _sourceMarkdownTextSpan(
        tester,
        find.byType(PaperTodoMarkdownSourcePreview),
        'Preview first',
      ),
      isNotNull,
    );
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

    await _activateSourceMarkdownLink(tester, 'Open site');

    expect(platform.uriOpener.openedUris, ['https://example.com/paper']);
    expect(find.byKey(const ValueKey('link-note-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('link-note-content')), findsNothing);
  });

  testWidgets('renders PaperTodo inline HTML markdown preview tags',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'html-tags-note',
            type: PaperTypes.note,
            title: 'HTML tags note',
            content: '<b>Bold</b> <strong>Strong</strong> '
                '<i>Italic</i> <em>Em</em> '
                '<s>Strike</s> <del>Del</del> '
                '<u>Under</u> <code>Code</code>\n\n'
                '<mark>Raw</mark>\n\n'
                '<b class=x>Raw bold</b>',
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

    final bold = _markdownTextSpan(tester, 'Bold');
    final strong = _markdownTextSpan(tester, 'Strong');
    final italic = _markdownTextSpan(tester, 'Italic');
    final em = _markdownTextSpan(tester, 'Em');
    final strike = _markdownTextSpan(tester, 'Strike');
    final del = _markdownTextSpan(tester, 'Del');
    final under = _markdownTextSpan(tester, 'Under');
    final code = _markdownTextSpan(tester, 'Code');
    expect(find.text('<mark>Raw</mark>'), findsOneWidget);
    expect(find.text('<b class=x>Raw bold</b>'), findsOneWidget);

    expect(bold.style?.fontWeight, FontWeight.w600);
    expect(strong.style?.fontWeight, FontWeight.w600);
    expect(italic.style?.fontStyle, FontStyle.italic);
    expect(em.style?.fontStyle, FontStyle.italic);
    expect(strike.style?.decoration, TextDecoration.lineThrough);
    expect(del.style?.decoration, TextDecoration.lineThrough);
    expect(under.style?.decoration, TextDecoration.underline);
    expect(code.style?.fontFamily, 'Cascadia Mono');
  });

  testWidgets('opens PaperTodo inline HTML markdown preview links',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'html-link-note',
            type: PaperTypes.note,
            title: 'HTML link note',
            content: '<a href="https://example.com/html">HTML link</a>\n\n'
                '<a href=www.example.com/bare>Bare HTML link</a>\n\n'
                '<a title="2 > 1" data-id=paper '
                'href="https://example.com/quoted">Quoted HTML link</a>',
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

    await _activateSourceMarkdownLink(tester, 'HTML link');
    await _activateSourceMarkdownLink(tester, 'Bare HTML link');
    await _activateSourceMarkdownLink(tester, 'Quoted HTML link');

    expect(platform.uriOpener.openedUris, [
      'https://example.com/html',
      'https://www.example.com/bare',
      'https://example.com/quoted',
    ]);
  });

  testWidgets('keeps markdown images and tables source-like like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'source-like-markdown-note',
            type: PaperTypes.note,
            title: 'Source-like markdown note',
            content: '![Alt text](https://example.com/image.png)\n\n'
                '| A | B |\n'
                '| - | - |\n'
                '| 1 | 2 |\n\n'
                '~~Done~~',
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

    final preview =
        find.byKey(const ValueKey('source-like-markdown-note-preview'));
    expect(
      find.descendant(of: preview, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: preview, matching: find.byType(Table)),
      findsNothing,
    );
    expect(
      find.text('![Alt text](https://example.com/image.png)'),
      findsOneWidget,
    );
    expect(_markdownTextSpan(tester, '| A | B |'), isNotNull);
    expect(_markdownTextSpan(tester, '| 1 | 2 |'), isNotNull);
    expect(_markdownTextSpan(tester, 'Done').style?.decoration,
        TextDecoration.lineThrough);
  });

  testWidgets('styles Markdown source while editing like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'styled-editor-note',
            type: PaperTypes.note,
            title: 'Styled editor note',
            content: '# Heading\n'
                '> Quote\n'
                '**Bold** and `code`\n'
                '[Link](https://example.com/edit)\n'
                '<b>HTML bold</b>\n'
                '```\n'
                'block code\n'
                '```',
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
    await _enterNoteEditor(tester, 'styled-editor-note');

    final field = find.byKey(const ValueKey('styled-editor-note-content'));
    final editableFinder =
        find.descendant(of: field, matching: find.byType(EditableText));
    final editable = tester.widget<EditableText>(editableFinder);
    final textController =
        editable.controller as PaperTodoMarkdownTextEditingController;
    final editableContext = tester.element(editableFinder);
    final colors = PaperTodoThemeColors.of(editableContext);
    final span = textController.buildTextSpan(
      context: editableContext,
      style: editable.style,
      withComposing: true,
    );

    expect(_findTextSpan(span, '# ')?.style?.color, colors.active);
    expect(_findTextSpan(span, '# ')?.style?.fontSize, 19);
    expect(_findTextSpan(span, 'Heading')?.style?.fontSize, 19);
    expect(_findTextSpan(span, 'Heading')?.style?.fontWeight, FontWeight.w600);
    expect(_findTextSpan(span, '> ')?.style?.color, colors.active);
    expect(_findTextSpan(span, 'Quote')?.style?.color, colors.weakText);
    expect(_findTextSpan(span, 'Bold')?.style?.fontWeight, FontWeight.w600);
    expect(_findTextSpan(span, 'code')?.style?.fontFamily, 'Cascadia Mono');
    expect(_findTextSpan(span, 'code')?.style?.fontSize, 13);
    expect(_findTextSpan(span, 'code')?.style?.color, colors.active);
    expect(_findTextSpan(span, 'Link')?.style?.color, colors.text);
    expect(
      _findTextSpan(span, 'https://example.com/edit')?.style?.color,
      colors.weakText,
    );
    expect(
        _findTextSpan(span, 'HTML bold')?.style?.fontWeight, FontWeight.w600);
    expect(
        _findTextSpan(span, 'block code')?.style?.fontFamily, 'Cascadia Mono');
    expect(_findTextSpan(span, 'block code')?.style?.color, colors.text);
    expect(_findTextSpan(span, 'block code')?.style?.backgroundColor, isNull);
    expect(
      find.byKey(const ValueKey('markdown-editor-block-background')),
      findsOneWidget,
    );
  });

  testWidgets('falls back to native text spans during Markdown IME composing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.basic,
        papers: [
          PaperData(
            id: 'markdown-ime-note',
            type: PaperTypes.note,
            title: 'Markdown IME note',
            content: '**输入**',
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
    await _enterNoteEditor(tester, 'markdown-ime-note');

    final field = find.byKey(const ValueKey('markdown-ime-note-content'));
    final editableFinder =
        find.descendant(of: field, matching: find.byType(EditableText));
    final editable = tester.widget<EditableText>(editableFinder);
    final textController =
        editable.controller as PaperTodoMarkdownTextEditingController;
    final editableContext = tester.element(editableFinder);
    final colors = PaperTodoThemeColors.of(editableContext);
    textController.value = const TextEditingValue(
      text: '**输入**',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 2, end: 4),
    );

    final composingSpan = textController.buildTextSpan(
      context: editableContext,
      style: editable.style,
      withComposing: true,
    );
    expect(composingSpan.toPlainText(), '**输入**');
    expect(
      _allTextSpans(composingSpan).any(
        (child) => child.style?.color == colors.active,
      ),
      isFalse,
    );

    textController.value = const TextEditingValue(
      text: '**输入**',
      selection: TextSelection.collapsed(offset: 6),
    );
    final styledSpan = textController.buildTextSpan(
      context: editableContext,
      style: editable.style,
      withComposing: true,
    );
    expect(_findTextSpan(styledSpan, '**')?.style?.color, colors.active);
    expect(_findTextSpan(styledSpan, '输入')?.style?.fontWeight, FontWeight.w600);
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

    await _activateSourceMarkdownLink(tester, 'Mail author');

    expect(platform.uriOpener.openedUris, ['mailto:paper@example.com']);
  });

  testWidgets('normalizes bare www markdown preview links like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'bare-www-note',
            type: PaperTypes.note,
            title: 'Bare www note',
            content: '[Open site](www.example.com/paper)',
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

    await _activateSourceMarkdownLink(tester, 'Open site');

    expect(platform.uriOpener.openedUris, ['https://www.example.com/paper']);
  });

  testWidgets('opens local markdown links through external file host',
      (tester) async {
    if (!Platform.isWindows) {
      return;
    }
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const markdownPath = 'C:/PaperTodo/local-link.txt';

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'local-link-note',
            type: PaperTypes.note,
            title: 'Local link note',
            content: '[Open file]($markdownPath)',
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

    await _activateSourceMarkdownLink(tester, 'Open file');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(
      platform.externalFiles.openedPaths.single.replaceAll('\\', '/'),
      markdownPath,
    );
  });

  testWidgets('opens file URI markdown links through external file host',
      (tester) async {
    if (!Platform.isWindows) {
      return;
    }
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fileUriPath = 'C:/PaperTodo/file-uri-link.txt';
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'file-uri-link-note',
            type: PaperTypes.note,
            title: 'File URI link note',
            content: '[Open file URI](file:///$fileUriPath)',
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

    await _activateSourceMarkdownLink(tester, 'Open file URI');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(
      platform.externalFiles.openedPaths.single.replaceAll('\\', '/'),
      fileUriPath,
    );
  });

  testWidgets('blocks encoded-control file URI markdown links before open',
      (tester) async {
    if (!Platform.isWindows) {
      return;
    }
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'encoded-control-file-uri-note',
            type: PaperTypes.note,
            title: 'Encoded control file URI note',
            content:
                '[Open encoded file URI](file:///C:/PaperTodo/bad%0Apath.txt)',
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

    _expectSourceMarkdownLinkDisabled(tester, 'Open encoded file URI');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(platform.externalFiles.openedPaths, isEmpty);
    expect(find.textContaining('unsupported link target'), findsNothing);
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

    _expectSourceMarkdownLinkDisabled(tester, 'Run script');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(
      find.textContaining('unsupported link target'),
      findsNothing,
    );
  });

  testWidgets('blocks unsafe inline HTML markdown preview links',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'unsafe-html-link-note',
            type: PaperTypes.note,
            title: 'Unsafe HTML link note',
            content: '<a href="javascript:alert(1)">Run script</a>',
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

    _expectSourceMarkdownLinkDisabled(tester, 'Run script');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsNothing);
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

    _expectSourceMarkdownLinkDisabled(tester, 'Open private link');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsNothing);
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

    _expectSourceMarkdownLinkDisabled(tester, 'Open encoded link');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsNothing);
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

    _expectSourceMarkdownLinkDisabled(tester, 'Open encoded separator');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsNothing);
  });

  testWidgets(
      'blocks UTF-8 encoded control markdown links before platform open',
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
            content:
                '[Open encoded control link](https://example.com/%C2%85path)',
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

    _expectSourceMarkdownLinkDisabled(tester, 'Open encoded control link');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsNothing);
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

    _expectSourceMarkdownLinkDisabled(tester, 'Open hostless link');

    expect(platform.uriOpener.openedUris, isEmpty);
    expect(find.textContaining('unsupported link target'), findsNothing);
  });

  testWidgets('keeps angle-bracket markdown destinations inert like PaperTodo',
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

    _expectSourceMarkdownLinkDisabled(tester, 'Bad link');

    expect(platform.uriOpener.openedUris, isEmpty);
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

    await _activateSourceMarkdownLink(tester, 'Broken link');
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

    await _activateSourceMarkdownLink(tester, 'Platform link');
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, ['https://example.com/platform']);
    expect(
      find.textContaining('No browser app can open this link.'),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('ACTIVITY_NOT_FOUND'), findsNothing);
  });

  testWidgets('localizes generic platform link open failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    tester.binding.platformDispatcher.localeTestValue =
        const Locale('zh', 'CN');
    tester.binding.platformDispatcher.localesTestValue = [
      const Locale('zh', 'CN'),
    ];
    addTearDown(() {
      tester.binding.platformDispatcher.clearLocaleTestValue();
      tester.binding.platformDispatcher.clearLocalesTestValue();
      tester.binding.setSurfaceSize(null);
    });

    final platform = _RecordingPlatformServices();
    platform.uriOpener.error = PlatformException(
      code: 'open_uri_failed',
      message: 'Unable to open the URI.',
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'localized-platform-link-note',
            type: PaperTypes.note,
            title: '平台链接纸片',
            content: '[平台链接](https://example.com/platform)',
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

    await _activateSourceMarkdownLink(tester, '平台链接');
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.uriOpener.openedUris, ['https://example.com/platform']);
    expect(find.textContaining('打开链接失败：无法打开链接。'), findsOneWidget);
    expect(find.textContaining('Unable to open the URI.'), findsNothing);
    expect(find.textContaining('open_uri_failed'), findsNothing);
    expect(find.textContaining('PlatformException'), findsNothing);
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

    final noteStatusBar = find.byKey(const ValueKey('note-status-bar'));
    expect(noteStatusBar, findsOneWidget);
    final noteStatusColors =
        PaperTodoThemeColors.of(tester.element(noteStatusBar));
    final noteStatusDecoration =
        tester.widget<DecoratedBox>(noteStatusBar).decoration as BoxDecoration;
    expect(
      noteStatusDecoration.color,
      noteStatusColors.tint.withValues(alpha: 10 / 255),
    );
    expect(
      noteStatusDecoration.border?.top.color,
      noteStatusColors.tint.withValues(alpha: 25 / 255),
    );
    expect(tester.getSize(noteStatusBar).height, 26);
    final noteToolbar = find.byKey(const ValueKey('note-canvas-toolbar'));
    final addCanvasButton = find.byKey(const ValueKey('note-add-canvas-block'));
    final addCanvasSurface =
        find.byKey(const ValueKey('note-add-canvas-block-surface'));
    final addCanvasLabel = tester.widget<Text>(
      find.descendant(of: addCanvasButton, matching: find.text('{}')),
    );
    expect(tester.getSize(noteToolbar).height, 32);
    expect(
      tester.widget<Container>(noteToolbar).padding,
      const EdgeInsets.fromLTRB(9, 3, 9, 4),
    );
    expect(tester.getSize(addCanvasButton), const Size(28, 24));
    expect(addCanvasLabel.style?.fontSize, 13);
    expect(addCanvasLabel.style?.fontWeight, isNull);
    expect(addCanvasLabel.style?.color, noteStatusColors.weakText);
    final canvasCount = tester.widget<Text>(
      find.byKey(const ValueKey('note-canvas-element-count')),
    );
    expect(canvasCount.style?.fontSize, 11);
    expect(canvasCount.style?.color, noteStatusColors.weakText);
    expect(
      tester
          .getTopRight(find.byKey(
            const ValueKey('note-canvas-element-count'),
          ))
          .dx,
      closeTo(
        tester.getTopRight(noteToolbar).dx - 9,
        1,
      ),
    );
    BoxDecoration addCanvasDecoration() =>
        tester.widget<DecoratedBox>(addCanvasSurface).decoration
            as BoxDecoration;
    final addCanvasOpacity = tester
        .element(addCanvasButton)
        .findAncestorWidgetOfExactType<Opacity>()!;
    expect(addCanvasDecoration().color, Colors.transparent);
    expect(addCanvasOpacity.opacity, 1);

    final addCanvasMouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await addCanvasMouse.addPointer(location: const Offset(1, 1));
    await addCanvasMouse.moveTo(tester.getCenter(addCanvasButton));
    await tester.pump();
    expect(addCanvasDecoration().color, noteStatusColors.hover);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: addCanvasButton,
              matching: find.text('{}'),
            ),
          )
          .style
          ?.color,
      noteStatusColors.text,
    );
    await addCanvasMouse.removePointer();
    await tester.pump();

    final addCanvasPress = await tester.startGesture(
      tester.getCenter(addCanvasButton),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      tester
          .element(addCanvasButton)
          .findAncestorWidgetOfExactType<Opacity>()!
          .opacity,
      0.7,
    );
    await addCanvasPress.cancel();
    await tester.pump();
    expect(find.text('Split'), findsNothing);
    expect(find.text('12 chars | 1 line | 2 elements'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-status-zoom')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('note-status-mode-pill'))).width,
      greaterThanOrEqualTo(42),
    );
    final noteModeText = tester.widget<Text>(
      find.byKey(const ValueKey('note-status-mode')),
    );
    expect(noteModeText.style?.letterSpacing, 0.7);
    final noteStatsMetrics = tester.widget<Transform>(
      find.byKey(const ValueKey('note-status-stats-metrics')),
    );
    expect(noteStatsMetrics.transform.getTranslation().x, 2);
    expect(noteStatsMetrics.transform.getTranslation().y, -2);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('note-status-stats')))
          .style
          ?.letterSpacing,
      0.05,
    );
    final noteZoomMetrics = tester.widget<Transform>(
      find.byKey(const ValueKey('note-status-zoom-metrics')),
    );
    expect(noteZoomMetrics.transform.getTranslation().y, -1);
    expect(
      find.byKey(const ValueKey('note-text-zoom-overlay')),
      findsNothing,
    );
    expect(
      tester
          .widget<Padding>(
            find.byKey(const ValueKey('note-paper-content-padding')),
          )
          .padding,
      const EdgeInsets.fromLTRB(26, 12, 14, 12),
    );
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('note-preview-scroll')),
          )
          .padding,
      EdgeInsets.zero,
    );
    final noteCanvasDecoration = tester
        .widget<Container>(find.byKey(const ValueKey('note-paper-canvas')))
        .decoration as BoxDecoration;
    final noteCanvasSize =
        tester.getSize(find.byKey(const ValueKey('note-paper-canvas')));
    final noteGridSize =
        tester.getSize(find.byKey(const ValueKey('note-paper-grid')));
    expect(noteCanvasSize.width - noteGridSize.width, 18);
    expect(noteCanvasSize.height - noteGridSize.height, 8);
    final noteGridPainter = tester
        .widget<CustomPaint>(find.byKey(const ValueKey('note-paper-grid')))
        .painter as dynamic;
    expect(noteGridPainter.spacing, 24);
    expect(noteGridPainter.verticalLineOffset, 1);
    expect(noteGridPainter.horizontalLineOffset, -1);
    expect(noteGridPainter.color.a, closeTo(18 / 255, 0.001));
    expect(
      ((noteCanvasDecoration.border as Border).top.color).a,
      closeTo(28 / 255, 0.001),
    );
    final bindingDecoration = tester
        .widget<Container>(
          find.byKey(const ValueKey('note-paper-binding-line')),
        )
        .decoration as BoxDecoration;
    expect(bindingDecoration.color!.a, closeTo(104 / 255, 0.001));

    expect(find.byKey(const ValueKey('note-canvas-preview')), findsOneWidget);
    final canvasPreview = find.byKey(const ValueKey('note-canvas-preview'));
    final bottomCanvasBlock =
        find.byKey(const ValueKey('note-canvas-element-canvas-bottom'));
    expect(
      tester.getTopLeft(bottomCanvasBlock) - tester.getTopLeft(canvasPreview),
      const Offset(26, 25),
    );
    expect(
      find.descendant(
        of: bottomCanvasBlock,
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
        matching: find.text('层 1'),
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
        matching: find.text('顶层 2'),
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

    final updatedTop = controller.state.papers.single.noteCanvasElements
        .firstWhere((element) => element.id == 'canvas-top');
    expect(updatedTop.type, NoteCanvasElementTypes.code);
    expect(updatedTop.x, 72);
    expect(updatedTop.y, 48);
    expect(updatedTop.width, 220);
    expect(updatedTop.height, 96);
    expect(updatedTop.zIndex, 2);

    final topBlock =
        find.byKey(const ValueKey('note-canvas-element-canvas-top'));
    await tester.tapAt(
      tester.getTopLeft(topBlock) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate canvas block'));
    await tester.pumpAndSettle();

    final duplicatedTop = controller.state.papers.single.noteCanvasElements
        .where((element) =>
            element.id != 'canvas-top' &&
            element.id != 'canvas-bottom' &&
            element.text == 'Updated canvas code')
        .single;
    expect(duplicatedTop.x, 90);
    expect(duplicatedTop.y, 66);
    expect(duplicatedTop.width, 220);
    expect(duplicatedTop.height, 96);
    expect(duplicatedTop.type, NoteCanvasElementTypes.code);
    expect(duplicatedTop.zIndex, 12);

    final duplicateBlock = find.byKey(
      ValueKey('note-canvas-element-${duplicatedTop.id}'),
    );
    await tester.tapAt(
      tester.getTopLeft(duplicateBlock) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bring to front'));
    await tester.pumpAndSettle();

    expect(duplicatedTop.zIndex, 22);

    await tester.tapAt(
      tester.getTopLeft(duplicateBlock) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to back'));
    await tester.pumpAndSettle();

    expect(duplicatedTop.zIndex, -9);

    await tester.tap(
      find.byKey(const ValueKey('note-add-canvas-block')),
    );
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.noteCanvasElements, hasLength(4));
    final addedCodeBlock =
        controller.state.papers.single.noteCanvasElements.last;
    expect(addedCodeBlock.type, NoteCanvasElementTypes.code);
    expect(addedCodeBlock.text, 'Console.WriteLine("PaperTodo");');
    expect(addedCodeBlock.x, 40);
    expect(addedCodeBlock.y, 64);
    expect(addedCodeBlock.width, 230);
    expect(addedCodeBlock.height, 116);
    expect(addedCodeBlock.zIndex, 12);
    expect(find.widgetWithText(TextButton, 'Add text block'), findsNothing);
    expect(find.text('12 chars | 1 line | 4 elements'), findsOneWidget);

    final addedBlock = find.byKey(
      ValueKey('note-canvas-element-${addedCodeBlock.id}'),
    );
    await tester.tapAt(
      tester.getTopLeft(addedBlock) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.noteCanvasElements, hasLength(3));
    expect(find.text('12 chars | 1 line | 3 elements'), findsOneWidget);
  });

  testWidgets('note canvas chrome keeps PaperTodo fixed editor metrics',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        papers: [
          PaperData(
            id: 'canvas-metrics-note',
            type: PaperTypes.note,
            textZoom: 1.5,
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'canvas-metrics-block',
                text: 'small editable code',
                width: 72,
                height: 48,
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

    final chrome = find.byKey(
      const ValueKey('note-canvas-element-chrome-canvas-metrics-block'),
    );
    final dragHandle = find.byKey(
      const ValueKey('note-canvas-drag-handle-canvas-metrics-block'),
    );
    final resizeHandle = find.byKey(
      const ValueKey('note-canvas-resize-handle-canvas-metrics-block'),
    );
    final editor = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(
          const ValueKey('note-canvas-element-text-canvas-metrics-block'),
        ),
        matching: find.byType(TextField),
      ),
    );
    final badge = find.byKey(
      const ValueKey('note-canvas-layer-badge-canvas-metrics-block'),
    );

    expect(chrome, findsOneWidget);
    expect(editor.expands, true);
    expect(editor.style?.fontSize, 13);
    expect(editor.style?.fontFamily, 'Cascadia Mono');
    expect(editor.style?.fontFamilyFallback, contains('Consolas'));
    expect(tester.getSize(dragHandle).height, 22);
    expect(tester.getSize(resizeHandle), const Size.square(15));
    expect(tester.getSize(badge).width, greaterThanOrEqualTo(32));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('note-status-mode-pill')))
            .width,
        greaterThanOrEqualTo(42));

    BoxDecoration chromeDecoration() =>
        tester.widget<DecoratedBox>(chrome).decoration as BoxDecoration;
    expect(chromeDecoration().borderRadius, BorderRadius.circular(12));
    expect(chromeDecoration().boxShadow, isEmpty);

    await tester.tap(dragHandle);
    await tester.pump();

    final selectedDecoration = chromeDecoration();
    expect(
      (selectedDecoration.border as Border).top.width,
      2,
    );
    final selectedShadow = selectedDecoration.boxShadow!.single;
    expect(selectedShadow.color.a, closeTo(0.13, 0.001));
    expect(selectedShadow.blurRadius, 6);
    expect(selectedShadow.offset.dx, closeTo(2 / math.sqrt(2), 0.001));
    expect(selectedShadow.offset.dy, closeTo(2 / math.sqrt(2), 0.001));
  });

  testWidgets('note canvas one-step layer moves break equal z-index ties',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'equal-layer-note',
            type: PaperTypes.note,
            title: 'Equal layer note',
            content: 'Main note body',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'equal-layer-a',
                type: NoteCanvasElementTypes.code,
                text: 'Layer A',
                x: 24,
                y: 24,
                width: 230,
                height: 116,
                zIndex: 5,
              ),
              NoteCanvasElement(
                id: 'equal-layer-b',
                type: NoteCanvasElementTypes.code,
                text: 'Layer B',
                x: 300,
                y: 48,
                width: 230,
                height: 116,
                zIndex: 5,
              ),
              NoteCanvasElement(
                id: 'equal-layer-c',
                type: NoteCanvasElementTypes.code,
                text: 'Layer C',
                x: 576,
                y: 72,
                width: 230,
                height: 116,
                zIndex: 5,
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(
      filePath: 'build/test-widget-note-canvas-layer-ties.json',
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    NoteCanvasElement canvasElement(String id) =>
        controller.state.papers.single.noteCanvasElements
            .firstWhere((element) => element.id == id);

    final firstBlock =
        find.byKey(const ValueKey('note-canvas-element-equal-layer-a'));
    await tester.tapAt(
      tester.getTopLeft(firstBlock) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bring forward'));
    await tester.pumpAndSettle();

    expect(canvasElement('equal-layer-a').zIndex, 6);
    expect(canvasElement('equal-layer-b').zIndex, 5);
    expect(canvasElement('equal-layer-c').zIndex, 7);

    await tester.tapAt(
      tester.getTopLeft(firstBlock) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send backward'));
    await tester.pumpAndSettle();

    expect(canvasElement('equal-layer-a').zIndex, 5);
    expect(canvasElement('equal-layer-b').zIndex, 6);
    expect(canvasElement('equal-layer-c').zIndex, 7);
  });

  testWidgets(
      'opens note canvas block context menu on right click like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.off,
        papers: [
          PaperData(
            id: 'canvas-context-note',
            type: PaperTypes.note,
            title: 'Canvas context note',
            content: 'Main note body',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'canvas-context-bottom',
                type: NoteCanvasElementTypes.code,
                text: 'Bottom layer',
                x: 24,
                y: 24,
                width: 230,
                height: 116,
                zIndex: 1,
              ),
              NoteCanvasElement(
                id: 'canvas-context-top',
                type: NoteCanvasElementTypes.code,
                text: 'Top layer',
                x: 300,
                y: 48,
                width: 230,
                height: 116,
                zIndex: 2,
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

    final block =
        find.byKey(const ValueKey('note-canvas-element-canvas-context-top'));
    expect(block, findsOneWidget);

    await tester.tapAt(
      tester.getTopLeft(block) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('CODE · 层 2'), findsOneWidget);
    expect(find.text('Bring forward'), findsOneWidget);
    expect(find.text('Send backward'), findsOneWidget);
    expect(find.text('Bring to front'), findsOneWidget);
    expect(find.text('Send to back'), findsOneWidget);
    expect(find.text('Duplicate canvas block'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Edit canvas geometry'), findsNothing);
    expect(find.byType(PopupMenuDivider), findsOneWidget);

    await tester.tap(find.text('Duplicate canvas block'));
    await tester.pumpAndSettle();

    final duplicatedTop = controller.state.papers.single.noteCanvasElements
        .where((element) =>
            element.id != 'canvas-context-top' &&
            element.id != 'canvas-context-bottom' &&
            element.text == 'Top layer')
        .single;
    expect(duplicatedTop.x, 318);
    expect(duplicatedTop.y, 66);
    expect(duplicatedTop.zIndex, 12);
  });

  testWidgets('counts note status characters like PaperTodo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'status-count-note',
            type: PaperTypes.note,
            title: 'Status count note',
            content: 'A\tB\nC\u0085D😀',
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

    expect(find.text('6 chars | 2 lines | 0 elements'), findsOneWidget);
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

  testWidgets('pinned note canvas ignores geometry drags like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'pinned-canvas-note',
            type: PaperTypes.note,
            title: 'Pinned canvas note',
            content: 'Pinned note body',
            isPinnedToDesktop: true,
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'pinned-canvas-element',
                text: 'Stay put',
                x: 16,
                y: 24,
                width: 130,
                height: 90,
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
      find.byKey(
        const ValueKey('note-canvas-drag-handle-pinned-canvas-element'),
      ),
      const Offset(40, 30),
      warnIfMissed: false,
    );
    await tester.pump();

    await tester.drag(
      find.byKey(
        const ValueKey('note-canvas-resize-handle-pinned-canvas-element'),
      ),
      const Offset(50, 25),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(element.x, 16);
    expect(element.y, 24);
    expect(element.width, 130);
    expect(element.height, 90);

    final addBlockButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('note-add-canvas-block')),
    );

    expect(addBlockButton.onPressed, isNull);
    expect(controller.state.papers.single.noteCanvasElements, hasLength(1));
  });

  testWidgets('pinned note canvas ignores editing actions like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'pinned-canvas-actions-note',
            type: PaperTypes.note,
            title: 'Pinned canvas actions',
            content: 'Pinned action body',
            isPinnedToDesktop: true,
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'pinned-canvas-action-primary',
                type: NoteCanvasElementTypes.code,
                text: 'Locked text',
                x: 16,
                y: 24,
                width: 220,
                height: 120,
                zIndex: 1,
              ),
              NoteCanvasElement(
                id: 'pinned-canvas-action-secondary',
                type: NoteCanvasElementTypes.code,
                text: 'Upper text',
                x: 300,
                y: 24,
                width: 220,
                height: 120,
                zIndex: 2,
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

    final elements = controller.state.papers.single.noteCanvasElements;
    final primary =
        elements.firstWhere((element) => element.id.endsWith('primary'));
    final primaryElement = find.byKey(
      const ValueKey('note-canvas-element-pinned-canvas-action-primary'),
    );
    final field = find.byKey(
      const ValueKey('note-canvas-element-text-pinned-canvas-action-primary'),
    );

    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .readOnly,
      true,
    );

    await tester.enterText(field, 'Changed text');
    await tester.pump();

    expect(primary.text, 'Locked text');
    expect(
      tester
          .widget<AbsorbPointer>(
            find
                .ancestor(of: field, matching: find.byType(AbsorbPointer))
                .first,
          )
          .absorbing,
      true,
    );
    expect(find.text('Canvas block geometry'), findsNothing);
    expect(
      find.descendant(of: primaryElement, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: primaryElement,
        matching: find.byType(PopupMenuButton<dynamic>),
      ),
      findsNothing,
    );
    await tester.tapAt(
      tester.getTopLeft(primaryElement) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Bring to front'), findsNothing);
    expect(primary.x, 16);
    expect(primary.width, 220);
    expect(primary.zIndex, 1);
    expect(elements.map((element) => element.id), [
      'pinned-canvas-action-primary',
      'pinned-canvas-action-secondary',
    ]);

    expect(find.widgetWithText(TextButton, 'Add text block'), findsNothing);

    final addBlockButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('note-add-canvas-block')),
    );

    expect(addBlockButton.onPressed, isNull);
    expect(elements, hasLength(2));
  });

  testWidgets('note canvas code accepts tab indentation like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'canvas-tab-note',
            type: PaperTypes.note,
            title: 'Canvas tab note',
            content: 'Canvas body',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'canvas-tab-element',
                type: NoteCanvasElementTypes.code,
                text: 'Line',
                x: 16,
                y: 24,
                width: 220,
                height: 110,
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

    final field = find.byKey(
      const ValueKey('note-canvas-element-text-canvas-tab-element'),
    );
    final element = controller.state.papers.single.noteCanvasElements.single;

    await tester.tap(field);
    await tester.enterText(field, 'Line');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(element.text, 'Line\t');

    await tester.enterText(field, '\tLine');
    await tester.pump();
    await _pressShiftShortcut(tester, LogicalKeyboardKey.tab);
    await tester.pump();

    expect(element.text, 'Line');
  });

  testWidgets('note canvas code accepts tab indentation like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'canvas-code-tab-note',
            type: PaperTypes.note,
            title: 'Canvas code tab note',
            content: 'Canvas body',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'canvas-code-tab-element',
                type: NoteCanvasElementTypes.code,
                text: 'Console.WriteLine("PaperTodo");',
                x: 16,
                y: 24,
                width: 240,
                height: 116,
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

    final field = find.byKey(
      const ValueKey('note-canvas-element-text-canvas-code-tab-element'),
    );
    final element = controller.state.papers.single.noteCanvasElements.single;

    await tester.tap(field);
    await tester.enterText(field, 'return value;');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(element.text, 'return value;\t');

    await tester.enterText(field, '\treturn value;');
    await tester.pump();
    await _pressShiftShortcut(tester, LogicalKeyboardKey.tab);
    await tester.pump();

    expect(element.text, 'return value;');
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
    expect(content, List.filled(6000, 'x').join());
    expect(content.contains('y'), isFalse);
  });

  testWidgets('keeps long markdown notes editable up to PaperTodo limit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longBody = List.filled(35000, 'n').join();
    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.off,
        papers: [
          PaperData(
            id: 'markdown-long-note',
            type: PaperTypes.note,
            title: 'Markdown long note',
            content: longBody,
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-markdown-long.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(
      find.byKey(const ValueKey('markdown-long-note-content')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('markdown-long-note-content')),
      '$longBody!',
    );
    await tester.pump();

    expect(controller.state.papers.single.content, '$longBody!');
  });

  testWidgets('keeps Markdown formatting in the PaperTodo context menu',
      (tester) async {
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
    expect(find.byTooltip('Insert link (Ctrl+K)'), findsNothing);
    expect(find.byTooltip('Heading'), findsNothing);
    expect(
      find.byKey(const ValueKey('compact-markdown-toolbar-actions')),
      findsNothing,
    );

    final field = find.byKey(const ValueKey('markdown-toolbar-note-content'));
    await tester.tapAt(
      tester.getCenter(field),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Insert link'), findsOneWidget);
    expect(find.text('Heading'), findsOneWidget);
    await tester.tap(find.text('Heading'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.content, '# Body');
  });

  testWidgets('keeps narrow note pages free of a second Markdown toolbar',
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
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('note-add-canvas-block')),
      findsOneWidget,
    );
    expect(find.byTooltip('Insert link (Ctrl+K)'), findsNothing);
    expect(find.byTooltip('Heading'), findsNothing);
  });

  testWidgets(
      'opens markdown editor context menu on right click like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'markdown-context-note',
            type: PaperTypes.note,
            title: 'Markdown context',
            content: 'Body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store =
        StateStore(filePath: 'build/test-widget-markdown-context-menu.json');
    final field = find.byKey(const ValueKey('markdown-context-note-content'));
    Future<void> pumpMenuFrames() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
    }

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await _enterNoteEditor(tester, 'markdown-context-note');
    await tester.enterText(field, 'Body');

    await tester.tapAt(
      tester.getCenter(field),
      buttons: kSecondaryMouseButton,
    );
    await pumpMenuFrames();

    expect(field, findsOneWidget);
    expect(
      find.byKey(const ValueKey('markdown-context-note-preview')),
      findsNothing,
    );
    expect(
      _popupMenuItemWithText('Format'),
      findsOneWidget,
    );
    expect(
      _popupMenuItemWithText('Text'),
      findsOneWidget,
    );
    expect(
      _popupMenuItemWithText('Bold'),
      findsOneWidget,
    );
    expect(
      _popupMenuItemWithText('Insert link'),
      findsOneWidget,
    );
    expect(
      _popupMenuItemWithText('Copy'),
      findsOneWidget,
    );
    expect(
      _popupMenuItemWithText('Select all'),
      findsOneWidget,
    );

    await tester.tap(_popupMenuItemWithText('Bold'));
    await pumpMenuFrames();

    expect(field, findsOneWidget);
    expect(
      find.byKey(const ValueKey('markdown-context-note-preview')),
      findsNothing,
    );
    expect(controller.state.papers.single.content, 'Body****');
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

    expect(controller.state.papers.single.content, 'Body[Link](https://)');

    await tester.enterText(field, 'Body');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.state.papers.single.content, 'Body\t');

    await tester.enterText(field, '\tBody');
    await tester.pump();
    await _pressShiftShortcut(tester, LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.state.papers.single.content, 'Body');
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

    final swatch = find.byKey(const ValueKey('settings-theme-color-swatch'));
    final pickButton = find.byKey(const ValueKey('settings-theme-color-pick'));
    final clearButton =
        find.byKey(const ValueKey('settings-theme-color-clear'));
    expect(tester.getSize(swatch), const Size(58, 42));
    final swatchMaterial = tester.widget<Material>(
      find.ancestor(of: swatch, matching: find.byType(Material)).first,
    );
    final swatchShape = swatchMaterial.shape! as RoundedRectangleBorder;
    expect(swatchShape.borderRadius, BorderRadius.zero);
    expect(swatchMaterial.clipBehavior, Clip.hardEdge);
    expect(tester.getSize(pickButton).height, 27);
    expect(tester.getSize(pickButton).width, greaterThanOrEqualTo(76));
    expect(tester.getSize(clearButton).height, 27);
    expect(tester.getSize(clearButton).width, greaterThanOrEqualTo(82));
    final pickLabelMetrics = tester.widget<Transform>(
      find.byKey(const ValueKey('settings-theme-color-pick-label-metrics')),
    );
    final pickLabelTranslation = pickLabelMetrics.transform.getTranslation();
    expect(
      Offset(pickLabelTranslation.x, pickLabelTranslation.y),
      const Offset(0, -0.5),
    );
    final pickLabelScale = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(
          const ValueKey('settings-theme-color-pick-label-metrics'),
        ),
        matching: find.byType(Transform),
      ),
    );
    expect(pickLabelScale.transform.entry(1, 1), closeTo(12 / 11, 0.0001));
    final themeColorLabelMetrics = tester.widget<Transform>(
      find.byKey(
        const ValueKey('settings-theme-color-current-label-metrics'),
      ),
    );
    final themeColorLabelTranslation =
        themeColorLabelMetrics.transform.getTranslation();
    expect(
      Offset(themeColorLabelTranslation.x, themeColorLabelTranslation.y),
      const Offset(-1, 0),
    );
    final topBarTodoLabel = tester.widget<Transform>(
      find.byKey(
        const ValueKey('settings-topBarNewTodo-wpf-label'),
      ),
    );
    final topBarTodoTranslation = topBarTodoLabel.transform.getTranslation();
    expect(
      Offset(topBarTodoTranslation.x, topBarTodoTranslation.y),
      const Offset(0.5, -1),
    );
    final topBarTodoText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(
          const ValueKey('settings-topBarNewTodo-wpf-label'),
        ),
        matching: find.byType(Text),
      ),
    );
    expect(topBarTodoText.style?.letterSpacing, -0.075);
    final settingsScrollbarTheme = tester.widget<ScrollbarTheme>(
      find.byKey(const ValueKey('settings-scrollbar-theme')),
    );
    final settingsWindowPadding = tester.widget<Padding>(
      find.byKey(const ValueKey('settings-window-padding')),
    );
    expect(
      settingsWindowPadding.padding,
      const EdgeInsets.fromLTRB(16, 14, 16, 16),
    );
    Offset transformOffset(String key) {
      final translation = tester
          .widget<Transform>(find.byKey(ValueKey(key)))
          .transform
          .getTranslation();
      return Offset(translation.x, translation.y);
    }

    expect(
      transformOffset('settings-navigation-metrics'),
      const Offset(1, -1),
    );
    expect(
      transformOffset('settings-navigation-divider'),
      const Offset(1, -1),
    );
    expect(
      transformOffset('settings-theme-color-label-metrics'),
      const Offset(0, 2),
    );
    final themeColorFieldLabel = tester.widget<Text>(
      find
          .descendant(
            of: find
                .byKey(const ValueKey('settings-theme-color-label-metrics')),
            matching: find.text('Global theme color'),
          )
          .first,
    );
    expect(themeColorFieldLabel.style?.fontSize, 11);
    expect(themeColorFieldLabel.style?.letterSpacing, -0.01);
    final systemFontLabel = tester.widget<Text>(find.text('System font'));
    expect(systemFontLabel.style?.fontSize, 11);
    expect(systemFontLabel.style?.letterSpacing, -0.005);
    final customFontField = tester.widget<TextField>(
      find.byKey(const ValueKey('settings-custom-font-family-field')),
    );
    expect(customFontField.textAlignVertical, const TextAlignVertical(y: -0.4));
    final markdownDisplayLabel = tester.widget<Text>(
      find.text('Markdown display'),
    );
    expect(markdownDisplayLabel.style?.letterSpacing, -0.02);
    final markdownDisplayMetrics = tester.widget<Transform>(
      find.byKey(const ValueKey('settings-markdown-label-metrics')),
    );
    final markdownDisplayTranslation =
        markdownDisplayMetrics.transform.getTranslation();
    expect(
      Offset(markdownDisplayTranslation.x, markdownDisplayTranslation.y),
      const Offset(0.5, 0.5),
    );
    final fullscreenHandlingLabel = tester.widget<Text>(
      find.text('Fullscreen handling'),
    );
    expect(fullscreenHandlingLabel.style?.letterSpacing, -0.003);
    final todoSizeLabel = tester.widget<Text>(find.text('Todo size'));
    expect(todoSizeLabel.style?.letterSpacing, -0.001);
    final todoSpacingLabel = tester.widget<Text>(find.text('Todo spacing'));
    final noteSpacingLabel = tester.widget<Text>(find.text('Note spacing'));
    expect(todoSpacingLabel.style?.letterSpacing, -0.001);
    expect(noteSpacingLabel.style?.letterSpacing, -0.001);
    expect(transformOffset('settings-title-metrics'), const Offset(0, 1.5));
    expect(
      transformOffset('settings-close-glyph-metrics'),
      const Offset(-2, 1),
    );
    expect(settingsScrollbarTheme.data.mainAxisMargin, 9);
    expect(settingsScrollbarTheme.data.crossAxisMargin, 3);
    final settingsContentScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('settings-content-scroll')),
    );
    expect(
      settingsContentScroll.padding,
      const EdgeInsets.fromLTRB(3, 6, 13, 2),
    );
    expect(
      settingsScrollbarTheme.data.thumbColor!.resolve(<WidgetState>{}),
      const Color(0xFFB39B74).withValues(alpha: 0.34),
    );
    expect(
      settingsScrollbarTheme.data.thumbColor!
          .resolve(<WidgetState>{WidgetState.hovered}),
      const Color(0xFF96784F).withValues(alpha: 0.54),
    );
    final authorSignature = tester.widget<Text>(
      find.byKey(const ValueKey('settings-author-signature')),
    );
    expect(authorSignature.style?.fontFamily, 'Segoe UI');
    expect(authorSignature.style?.fontSize, 11);
    expect(authorSignature.style?.fontWeight, FontWeight.w500);
    expect(authorSignature.style?.letterSpacing, isNull);
    final authorSignatureMetrics = tester.widget<Transform>(
      find.byKey(const ValueKey('settings-author-signature-metrics')),
    );
    expect(
      authorSignatureMetrics.transform.entry(0, 0),
      closeTo(99 / 103, 0.0001),
    );
    final settingsCheckPainter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .where((painter) =>
            painter.runtimeType.toString() == '_SettingsCheckMarkPainter')
        .first as dynamic;
    expect(settingsCheckPainter.checkedInset, 2);
    final checkboxTitleTransforms = tester.widgetList<Transform>(
      find.byKey(const ValueKey('settings-checkbox-title-metrics')),
    );
    expect(checkboxTitleTransforms, isNotEmpty);
    for (final transform in checkboxTitleTransforms) {
      final translation = transform.transform.getTranslation();
      expect(
        Offset(translation.x, translation.y),
        const Offset(-0.5, 0),
      );
    }
    for (final key in const <String>[
      'settings-group-label-metrics',
      'settings-field-label-metrics',
    ]) {
      final transforms =
          tester.widgetList<Transform>(find.byKey(ValueKey(key)));
      expect(transforms, isNotEmpty);
      for (final transform in transforms) {
        final translation = transform.transform.getTranslation();
        expect(
          Offset(translation.x, translation.y),
          const Offset(-0.5, 0.5),
        );
      }
    }
    final defaultPaletteText = tester.widget<Text>(
      find.text('Use default palette'),
    );
    expect(defaultPaletteText.style?.fontSize, 12.5);
    expect(defaultPaletteText.style?.fontWeight, FontWeight.w600);

    final pickedColor = Theme.of(
      tester.element(swatch),
    ).colorScheme.primary;
    await tester.tap(pickButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-color-apply')));
    await tester.pumpAndSettle();
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.customThemeColorHex, _testColorHex(pickedColor));
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.colorScheme.primary, pickedColor);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-color-clear')));
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();
    expect(controller.state.customThemeColorHex, isEmpty);
  });

  testWidgets('settings title length uses PaperTodo compact stepper',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        maxTitleLength: 6,
        papers: [
          PaperData(
            id: 'title-stepper-paper',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'title-stepper-item')],
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
    await _selectSettingsCategory(tester, 'capsules');

    final stepper = find.byKey(const ValueKey('settings-max-title-length'));
    await tester.scrollUntilVisible(
      stepper,
      320,
      scrollable: find.byType(Scrollable).last,
    );
    expect(stepper, findsOneWidget);
    expect(tester.getSize(stepper).height, 28);
    final decreaseButton = find.ancestor(
      of: find.descendant(of: stepper, matching: find.text('−')),
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SettingsStepperButton',
      ),
    );
    expect(tester.getSize(decreaseButton), const Size(34, 26));
    expect(
        find.descendant(of: stepper, matching: find.text('6')), findsOneWidget);

    await tester.tap(find.descendant(of: stepper, matching: find.text('＋')));
    await tester.pump();
    expect(
        find.descendant(of: stepper, matching: find.text('7')), findsOneWidget);

    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();
    expect(controller.state.maxTitleLength, 7);
  });

  testWidgets('line spacing settings accept keyboard input and clamp',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'spacing-settings-paper', type: PaperTypes.todo),
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
      find.byKey(const ValueKey('settings-todo-line-spacing')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    final todoSpacingField = find.byKey(
      const ValueKey('settings-todo-line-spacing'),
    );
    expect(tester.getSize(todoSpacingField).height, 28);
    expect(
      tester.widget<TextField>(todoSpacingField).controller?.text,
      '1',
    );
    await tester.tap(todoSpacingField);
    await tester.pump();
    final todoSpacingSurface = tester.widget<DecoratedBox>(
      find.byKey(
        const ValueKey('settings-todo-line-spacing-surface'),
      ),
    );
    final todoSpacingBorder =
        (todoSpacingSurface.decoration as BoxDecoration).border as Border;
    expect(
      todoSpacingBorder.top.color,
      PaperTodoThemeColors.of(tester.element(todoSpacingField)).active,
    );
    await tester.enterText(
      todoSpacingField,
      '9',
    );
    await tester.enterText(
      find.byKey(const ValueKey('settings-note-line-spacing')),
      '0.1',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.todoLineSpacing, 5);
    expect(controller.state.noteLineSpacing, 0.8);
  });

  testWidgets('inactive reminder mode keeps timing editors available',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = RePaperTodoController(
      initialState: AppState(
        showTodoDueRelativeTime: true,
        useTodoReminderInterval: false,
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 30,
        papers: [
          PaperData(id: 'inactive-reminder-settings', type: PaperTypes.todo),
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
    await _selectSettingsCategory(tester, 'todoAndNotes');

    final yearSelector =
        find.byKey(const ValueKey('settings-due-year-selector'));
    final yearControl = find.descendant(
      of: yearSelector,
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SettingsSegmentSelector',
      ),
    );
    expect((tester.widget(yearControl) as dynamic).onChanged, isNotNull);
    await tester.tap(
      find.descendant(of: yearSelector, matching: find.text('2026')),
    );
    await tester.pump();

    final intervalField =
        find.byKey(const ValueKey('settings-reminder-interval'));
    await tester.scrollUntilVisible(
      intervalField,
      320,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.widget<TextField>(intervalField).enabled, isNot(false));
    await tester.enterText(intervalField, '45');

    final unitSelector =
        find.byKey(const ValueKey('settings-reminder-unit-selector'));
    await tester.tap(
      find.descendant(of: unitSelector, matching: find.text('Hours')),
    );
    await tester.pump();
    final scopeSelector =
        find.byKey(const ValueKey('settings-reminder-scope-selector'));
    await tester.tap(
      find.descendant(of: scopeSelector, matching: find.text('All')),
    );
    await tester.pump();

    final durationField =
        find.byKey(const ValueKey('settings-reminder-duration'));
    await tester.ensureVisible(durationField);
    await tester.enterText(durationField, '9');
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.showTodoDueRelativeTime, true);
    expect(
      controller.state.todoDueYearDisplayMode,
      TodoDueYearDisplayModes.full,
    );
    expect(controller.state.useTodoReminderInterval, false);
    expect(controller.state.todoReminderIntervalValue, 45);
    expect(
      controller.state.todoReminderIntervalUnit,
      TodoReminderIntervalUnits.hours,
    );
    expect(controller.state.todoReminderScope, TodoReminderScopes.all);
    expect(controller.state.todoReminderBubbleDurationSeconds, 9);
  });

  testWidgets('rejects invalid external markdown extensions in settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        externalMarkdownExtension: '.md',
        papers: [
          PaperData(
            id: 'extension-paper',
            type: PaperTypes.todo,
            title: 'Extension settings',
            items: [
              PaperItem(id: 'extension-item', text: 'Tune export extension'),
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
    await _selectSettingsCategory(tester, 'general');

    final extensionField = find.byKey(
      const ValueKey('settings-external-markdown-extension'),
    );
    await tester.enterText(extensionField, 'md?bad');
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.textContaining('Use an extension such as .md, .txt, or .todo.md'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(extensionField).focusNode?.hasFocus,
      true,
    );
    expect(controller.state.externalMarkdownExtension, '.md');

    await tester.enterText(extensionField, '.txt');
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(controller.state.externalMarkdownExtension, '.txt');
  });

  testWidgets('allows file-name-safe external markdown suffixes in settings',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        externalMarkdownExtension: '.md',
        papers: [
          PaperData(
            id: 'extension-safe-paper',
            type: PaperTypes.note,
            title: 'Extension safe',
            content: 'Tune export extension',
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
    await _selectSettingsCategory(tester, 'general');

    await tester.enterText(
      find.byKey(
        const ValueKey('settings-external-markdown-extension'),
      ),
      'notes.todo.md',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(controller.state.externalMarkdownExtension, '.notes.todo.md');
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
    await _selectSettingsCategory(tester, 'sync');
    final endpointField = find.widgetWithText(TextField, 'WebDAV URL');
    final endpointWidget = tester.widget<TextField>(endpointField);
    expect(tester.getSize(endpointField).height, 28);
    expect(endpointWidget.decoration?.prefixIcon, isNull);
    expect(endpointWidget.decoration?.suffixIcon, isNull);
    expect(tester.getSize(find.byTooltip('Show password')), const Size(34, 26));
    expect(
      tester.getSize(find.byTooltip('Show passphrase')),
      const Size(34, 26),
    );
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
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(
      controller.state.sync.webDav.encryptionPassphrase,
      'shared sync secret',
    );
    expect(controller.state.sync.webDav.usesEncryptedPayloads, true);
    expect(controller.state.sync.webDav.requestTimeoutSeconds, 45);
  });

  testWidgets('settings save refreshes Android background WebDAV sync',
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
            id: 'background-sync-settings-paper',
            type: PaperTypes.todo,
            title: 'Background sync',
            items: [
              PaperItem(
                id: 'background-sync-settings-item',
                text: 'Tune background sync',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    final configuredSyncs = <SyncSettings>[];
    final configuredStateFilePaths = <String>[];

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        configureAndroidBackgroundSync: ({
          required sync,
          required stateFilePath,
        }) async {
          configuredSyncs.add(sync.copy());
          configuredStateFilePaths.add(stateFilePath);
        },
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _selectSettingsCategory(tester, 'sync');
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
      '30',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(configuredStateFilePaths, [store.filePath]);
    expect(configuredSyncs.single.enabled, true);
    expect(configuredSyncs.single.provider, SyncProviderIds.webDav);
    expect(
      configuredSyncs.single.webDav.encryptionPassphrase,
      'shared sync secret',
    );
    expect(configuredSyncs.single.webDav.isSecurelyConfigured, true);
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
    await _selectSettingsCategory(tester, 'sync');
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
    await _commitVisibleDialog(tester);
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
    await _selectSettingsCategory(tester, 'sync');
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
    await _commitVisibleDialog(tester);
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
    await _selectSettingsCategory(tester, 'sync');
    await tester.scrollUntilVisible(
      find.text('Sync encryption passphrase'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
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

    await _commitVisibleDialog(tester);
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
    await _selectSettingsCategory(tester, 'sync');
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Username'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Username'),
      '   ',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
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
    await _selectSettingsCategory(tester, 'sync');
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Password'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      '   ',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
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
    await _selectSettingsCategory(tester, 'sync');
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
    await _commitVisibleDialog(tester);
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
    await _selectSettingsCategory(tester, 'sync');
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Sync encryption passphrase'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Sync encryption passphrase'),
      '   ',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
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
    await _selectSettingsCategory(tester, 'sync');
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
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
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

    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text(rootPathErrorText), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Remote folder'))
          .focusNode
          ?.hasFocus,
      true,
    );
    expect(controller.state.sync.webDav.rootPath, 'repapertodo');

    await tester.enterText(
      find.widgetWithText(TextField, 'Remote folder'),
      'RePaperTodo',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text(rootPathErrorText), findsNothing);
    expect(
      find.text('Username cannot contain colons or control characters.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Username'))
          .focusNode
          ?.hasFocus,
      true,
    );
    expect(controller.state.sync.webDav.username, 'user');

    await tester.enterText(
      find.widgetWithText(TextField, 'Username'),
      'user',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Username cannot contain colons or control characters.'),
      findsNothing,
    );
    expect(
      find.text('Password cannot contain control characters.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Password'))
          .focusNode
          ?.hasFocus,
      true,
    );
    expect(controller.state.sync.webDav.password, 'pass');

    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'clean-pass',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Password cannot contain control characters.'),
      findsNothing,
    );
    expect(find.text('Enter a sync encryption passphrase.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Sync encryption passphrase'),
          )
          .focusNode
          ?.hasFocus,
      true,
    );
    expect(
      controller.state.sync.webDav.encryptionPassphrase,
      'shared sync secret',
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Sync encryption passphrase'),
      'shared sync secret 2',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(
      controller.state.sync.webDav.endpoint,
      'https://dav.example.test/dav/',
    );
    expect(controller.state.sync.webDav.rootPath, 'RePaperTodo');
    expect(controller.state.sync.webDav.username, 'user');
    expect(controller.state.sync.webDav.password, 'clean-pass');
    expect(
      controller.state.sync.webDav.encryptionPassphrase,
      'shared sync secret 2',
    );
  });

  testWidgets('rejects overlong Jianguoyun sandbox names inline',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings.jianguoyun(
            username: 'user@example.com',
            password: 'app-password',
            encryptionPassphrase: 'shared sync secret',
          ),
        ),
        papers: [
          PaperData(
            id: 'jianguoyun-root-limit-paper',
            type: PaperTypes.todo,
            title: 'Jianguoyun root limit',
            items: [
              PaperItem(
                id: 'jianguoyun-root-limit-item',
                text: 'Validate before upload',
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
    await _selectSettingsCategory(tester, 'sync');
    expect(
      find.widgetWithText(TextField, 'WebDAV app password'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Jianguoyun requires an app password'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Remote folder'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Remote folder'),
      List.filled(31, 'a').join(),
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.text(
        'Jianguoyun requires the first remote-folder segment to be at most 30 characters.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Remote folder'))
          .focusNode
          ?.hasFocus,
      true,
    );
    expect(controller.state.sync.webDav.rootPath, 'RePaperTodo');
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
    await _selectSettingsCategory(tester, 'sync');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('compact-webdav-preset-selector')),
      480,
      scrollable: find.byType(Scrollable).last,
    );

    expect(
      find.byKey(const ValueKey('compact-webdav-preset-selector')),
      findsOneWidget,
    );
    final compactWebDavSelector = find.byKey(
      const ValueKey('compact-webdav-preset-selector'),
    );
    expect(
      tester.widget(compactWebDavSelector),
      isA<DropdownButton<String>>(),
    );
    expect(tester.getSize(compactWebDavSelector).height, 28);

    await tester.tap(
      find.byKey(const ValueKey('compact-webdav-preset-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('坚果云').last);
    await tester.pumpAndSettle();

    final urlField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'WebDAV URL'),
    );
    expect(urlField.controller?.text, 'https://dav.jianguoyun.com/dav/');

    final rootField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Remote folder'),
    );
    expect(rootField.controller?.text, 'RePaperTodo');

    await tester.tap(
      find.byKey(const ValueKey('compact-webdav-preset-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generic').last);
    await tester.pumpAndSettle();

    final genericUrlField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'WebDAV URL'),
    );
    final genericRootField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Remote folder'),
    );
    expect(genericUrlField.controller?.text, 'https://dav.jianguoyun.com/dav/');
    expect(genericRootField.controller?.text, 'RePaperTodo');
  });

  testWidgets('system back returns from paper surface to board',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'system-back-note',
            type: PaperTypes.note,
            title: 'System back note',
            content: 'Return through Android back.',
          ),
          PaperData(
            id: 'system-back-todo',
            type: PaperTypes.todo,
            title: 'Board still visible',
            items: [
              PaperItem(id: 'system-back-item', text: 'Stay on board'),
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

    await tester.tap(find.byTooltip('Open paper surface').first);
    await tester.pump();

    expect(find.byTooltip('Back to board'), findsOneWidget);
    expect(find.text('Board still visible'), findsNothing);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, true);
    expect(find.byTooltip('Back to board'), findsNothing);
    expect(find.text('System back note'), findsOneWidget);
    expect(find.text('Board still visible'), findsOneWidget);
    expect(controller.state.papers.every((paper) => paper.isVisible), true);
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
    final compactThemeSelector =
        find.byKey(const ValueKey('settings-theme-selector'));
    expect(
      tester.widget(compactThemeSelector),
      isA<DropdownButton<String>>(),
    );
    expect(tester.getSize(compactThemeSelector).height, 28);
    expect(find.text('Theme mode'), findsOneWidget);
    expect(find.text('Markdown display'), findsOneWidget);
    final settingsDropChevrons = find.byKey(
      const ValueKey('settings-drop-chevron'),
    );
    expect(settingsDropChevrons, findsWidgets);
    expect(tester.getSize(settingsDropChevrons.first), const Size(18, 18));
    expect(
      tester
          .widget<CustomPaint>(settingsDropChevrons.first)
          .painter
          .runtimeType
          .toString(),
      '_SettingsDropChevronPainter',
    );

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

    await _selectSettingsCategory(tester, 'todoAndNotes');
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

    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.theme, 'dark');
    expect(controller.state.markdownRenderMode, MarkdownRenderModes.enhanced);
    expect(
      controller.state.todoReminderIntervalUnit,
      TodoReminderIntervalUnits.hours,
    );
  });

  testWidgets('settings fit the minimum Windows window size', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(560, 360);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'minimum-settings-paper',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'minimum-settings-item')],
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
    final compactActions = find.byKey(
      const ValueKey('compact-app-bar-actions'),
    );
    if (compactActions.evaluate().isNotEmpty) {
      await tester.tap(compactActions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
    } else {
      await tester.tap(find.byIcon(Icons.settings_outlined).last);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final settingsPaperDialog = find.byKey(
      const ValueKey('windows-settings-paper-dialog'),
    );
    expect(settingsPaperDialog, findsOneWidget);
    expect(
      tester.widget<Dialog>(settingsPaperDialog).insetPadding,
      EdgeInsets.zero,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('windows-settings-paper-fill')),
      ),
      const Size(560, 360),
    );

    for (final section in [
      'todoAndNotes',
      'capsules',
      'general',
      'sync',
      'display',
    ]) {
      await _selectSettingsCategory(tester, section);
      expect(
        tester.takeException(),
        isNull,
        reason: '$section overflowed at the minimum Windows settings size',
      );
    }
  });

  testWidgets('Chinese settings fit the minimum Windows window size',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(560, 360);
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearLocaleTestValue();
    });

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'minimum-zh-settings-paper',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'minimum-zh-settings-item')],
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
    final compactMenu = tester.widget<PopupMenuButton<String>>(
      find
          .descendant(
            of: find.byKey(const ValueKey('compact-app-bar-actions')),
            matching: find.byWidgetPredicate(
              (widget) => widget is PopupMenuButton<String>,
            ),
          )
          .first,
    );
    compactMenu.onSelected!('settings');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final section in [
      'todoAndNotes',
      'capsules',
      'general',
      'sync',
      'display',
    ]) {
      await _selectSettingsCategory(tester, section);
      expect(
        tester.takeException(),
        isNull,
        reason: '$section overflowed in Chinese at minimum size',
      );
    }
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

    final restoreSnapshotButton = find.byKey(const ValueKey(
        'restore-snapshot-repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json'));
    final closeSnapshotsButton = find.widgetWithText(TextButton, 'Close');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusIsWithin(restoreSnapshotButton), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusIsWithin(closeSnapshotsButton), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusIsWithin(restoreSnapshotButton), isTrue);

    await tester.tap(restoreSnapshotButton);
    await tester.pumpAndSettle();

    expect(find.text('Restore snapshot?'), findsOneWidget);

    final cancelRestoreButton = find.widgetWithText(TextButton, 'Cancel');
    final confirmRestoreButton =
        find.byKey(const ValueKey('confirm-restore-snapshot'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusIsWithin(cancelRestoreButton), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusIsWithin(confirmRestoreButton), isTrue);

    await tester.tap(confirmRestoreButton);
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

  testWidgets('recovery snapshot restore clears stale todo reminders',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 30,
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
            id: 'local-reminder-paper',
            type: PaperTypes.todo,
            title: 'Remind me',
            items: [
              PaperItem(
                id: 'local-reminder-item',
                text: 'Replace me',
                dueAtLocal: DateTime.now()
                    .subtract(const Duration(minutes: 11))
                    .toIso8601String(),
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
          path:
              'repapertodo/snapshots/snapshot-20260701T100000000Z-laptop.json',
          deviceId: 'laptop',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 10),
        ),
      ],
      restoredState: AppState(
        papers: [
          PaperData(
            id: 'restored-note',
            type: PaperTypes.note,
            title: 'Restored note',
            content: 'No stale reminders here.',
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
    await tester.pump();

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(_snackBarTextContaining('Replace me'), findsOneWidget);

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(
        'restore-snapshot-repapertodo/snapshots/snapshot-20260701T100000000Z-laptop.json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.title, 'Restored note');
    expect(_snackBarTextContaining('Replace me'), findsNothing);
    expect(find.text('Snapshot restored.'), findsOneWidget);
  });

  testWidgets('recovery snapshot restore reapplies reminder cadence',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dueAtLocal =
        DateTime.now().subtract(const Duration(minutes: 11)).toIso8601String();
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 30,
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
            id: 'cadence-reminder-paper',
            type: PaperTypes.todo,
            title: 'Cadence',
            items: [
              PaperItem(
                id: 'cadence-reminder-item',
                text: 'Apply restored cadence',
                dueAtLocal: dueAtLocal,
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
          path:
              'repapertodo/snapshots/snapshot-20260701T103000000Z-laptop.json',
          deviceId: 'laptop',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 10, 30),
        ),
      ],
      restoredState: AppState(
        useTodoReminderInterval: false,
        todoReminderBubbleDurationSeconds: 30,
        papers: [
          PaperData(
            id: 'cadence-reminder-paper',
            type: PaperTypes.todo,
            title: 'Cadence',
            items: [
              PaperItem(
                id: 'cadence-reminder-item',
                text: 'Apply restored cadence',
                dueAtLocal: dueAtLocal,
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
    await tester.pump();

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(
      _snackBarTextContaining('Apply restored cadence'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(
        'restore-snapshot-repapertodo/snapshots/snapshot-20260701T103000000Z-laptop.json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pumpAndSettle();

    expect(controller.state.useTodoReminderInterval, false);
    expect(_snackBarTextContaining('Apply restored cadence'), findsNothing);
    expect(find.text('Snapshot restored.'), findsOneWidget);
  });

  testWidgets('recovery snapshot restore exits stale surface view',
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
            id: 'opened-local-paper',
            type: PaperTypes.note,
            title: 'Opened local',
            content: 'This paper will be replaced.',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      snapshots: [
        WebDavSnapshotRecord(
          path:
              'repapertodo/snapshots/snapshot-20260701T110000000Z-laptop.json',
          deviceId: 'laptop',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 11),
        ),
      ],
      restoredState: AppState(
        papers: [
          PaperData(
            id: 'restored-paper',
            type: PaperTypes.note,
            title: 'Restored board paper',
            content: 'Back on the board.',
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

    await tester.tap(find.byTooltip('Open paper surface'));
    await tester.pump();

    expect(find.byTooltip('Back to board'), findsOneWidget);
    expect(find.text('This paper will be replaced.'), findsWidgets);

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(
        'restore-snapshot-repapertodo/snapshots/snapshot-20260701T110000000Z-laptop.json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back to board'), findsNothing);
    expect(find.text('This paper will be replaced.'), findsNothing);
    expect(find.text('Restored board paper'), findsOneWidget);
    expect(find.text('Back on the board.'), findsWidgets);
    expect(find.text('Snapshot restored.'), findsOneWidget);
  });

  testWidgets('recovery snapshot restore clears pending local edit upload',
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
          id: 'pending-restore-note',
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
    final syncService = _RecoverySnapshotSyncService(
      snapshots: [
        WebDavSnapshotRecord(
          path:
              'repapertodo/snapshots/snapshot-20260701T113000000Z-laptop.json',
          deviceId: 'laptop',
          updatedAtUtc: DateTime.utc(2026, 7, 1, 11, 30),
        ),
      ],
      restoredState: AppState(
        sync: syncSettings.copy()
          ..operationDeviceSequences = const {'laptop': 8},
        papers: [
          PaperData(
            id: 'snapshot-note',
            type: PaperTypes.note,
            title: 'Snapshot',
            content: 'Restored body',
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
      find.byKey(const ValueKey('pending-restore-note-title')),
      'Draft before restore',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Recovery snapshots'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(
        'restore-snapshot-repapertodo/snapshots/snapshot-20260701T113000000Z-laptop.json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.title, 'Snapshot');
    expect(syncService.localUploadCalls, 0);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(syncService.localUploadCalls, 0);
    expect(syncService.localUploadBeforeTitles, isEmpty);
    expect(syncService.localUploadAfterTitles, isEmpty);
    expect(controller.state.papers.single.title, 'Snapshot');
    expect(find.text('Draft before restore'), findsNothing);
    expect(find.text('Snapshot restored.'), findsOneWidget);
  });

  testWidgets('recovery snapshot restore failure can retry from snackbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const snapshotPath = 'repapertodo/snapshots/a-very-long-device-directory/'
        'snapshot-20260701T090000000Z-phone-with-an-extraordinarily-long-device-name.json';
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
        responseBody: '恢复失败\u0001\n请\u0085稍后重试 '
            'provider diagnostic 01 provider diagnostic 02 '
            'provider diagnostic 03 provider diagnostic 04 '
            'provider diagnostic 05 provider diagnostic 06 '
            'provider diagnostic 07 provider diagnostic 08 '
            'provider diagnostic 09 provider diagnostic 10 '
            'provider diagnostic 11 provider diagnostic 12',
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
      find.textContaining('WebDAV request failed: offline'),
      findsOneWidget,
    );
    final failureText = tester.widget<Text>(
      find.textContaining('Provider details:'),
    );
    final failureMessage = failureText.data!;
    expect(failureMessage, contains('Provider details: 恢复失败 请 稍后重试'));
    expect(failureMessage, isNot(contains('\u0001')));
    expect(failureMessage, isNot(contains('\u0085')));
    expect(failureMessage, endsWith('...'));
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

    expect(find.text('Settings'), findsOneWidget);
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
        responseBody: '服务暂时不可用\u0001\n请\u0085稍后重试 '
            'provider diagnostic 01 provider diagnostic 02 '
            'provider diagnostic 03 provider diagnostic 04 '
            'provider diagnostic 05 provider diagnostic 06 '
            'provider diagnostic 07 provider diagnostic 08 '
            'provider diagnostic 09 provider diagnostic 10 '
            'provider diagnostic 11 provider diagnostic 12',
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
    final failureText = tester.widget<Text>(
      find.textContaining('Provider details:'),
    );
    final failureMessage = failureText.data!;
    expect(failureMessage, contains('Provider details: 服务暂时不可用 请 稍后重试'));
    expect(failureMessage, isNot(contains('\u0001')));
    expect(failureMessage, isNot(contains('\u0085')));
    expect(failureMessage, endsWith('...'));
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

  testWidgets('recovery snapshot list failure can open sync settings',
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
            id: 'recovery-settings-paper',
            type: PaperTypes.todo,
            title: 'Recovery settings',
            items: [
              PaperItem(
                id: 'recovery-settings-item',
                text: 'Open sync settings from list failure',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _RecoverySnapshotSyncService(
      firstListError: const WebDavException(
        'WebDAV credentials were rejected.',
        statusCode: 401,
        responseBody: 'Unauthorized',
      ),
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
    expect(find.textContaining('WebDAV credentials were rejected.'),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-recovery-snapshots')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('settings-recovery-snapshots')));
    await tester.pumpAndSettle();

    expect(find.text('Recovery snapshots'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
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

    expect(find.text('Settings'), findsOneWidget);
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
    final compactPathText = tester.widget<Text>(find.text(snapshotPath));
    expect(compactPathText.maxLines, 3);
    expect(compactPathText.overflow, TextOverflow.ellipsis);
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

    expect(find.text('Settings'), findsOneWidget);
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
      firstSyncError: WebDavException(
        'WebDAV provider rate limit reached. Try again later. Retry after 120 seconds.',
        statusCode: 429,
        responseBody:
            '请求过于频繁\u0001 请\u0085稍后再试 ${List.filled(280, 'x').join()}',
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
    final failureText = tester.widget<Text>(
      find.textContaining('Provider details:'),
    );
    final failureMessage = failureText.data!;
    expect(failureMessage, contains('Provider details: 请求过于频繁 请 稍后再试'));
    expect(failureMessage, isNot(contains('\u0001')));
    expect(failureMessage, isNot(contains('\u0085')));
    expect(failureMessage, endsWith('...'));
    expect(find.textContaining('WebDavException'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('manual WebDAV failure omits duplicate provider details',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const failureMessage =
        'WebDAV provider rate limit reached. Try again later.';
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'webdav-duplicate-failure-note',
            type: PaperTypes.note,
            title: 'Local before duplicate WebDAV retry',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final syncService = _ManualSyncService(
      firstSyncError: const WebDavException(
        failureMessage,
        statusCode: 429,
        responseBody:
            ' \u0001\nWebDAV provider rate limit reached. Try again later.\u0085 ',
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

    expect(find.textContaining(failureMessage), findsOneWidget);
    expect(find.textContaining('Provider details:'), findsNothing);
    expect(find.textContaining('WebDavException'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('Jianguoyun HTTP 401 explains the required app password',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final initialState = AppState(
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings.jianguoyun(
          username: 'user@example.test',
          password: 'provider-app-password',
          encryptionPassphrase: 'independent-sync-passphrase',
        ),
      ),
      papers: [
        PaperData(
          id: 'jianguoyun-auth-failure-note',
          type: PaperTypes.note,
          title: 'Local before authentication retry',
          content: 'Local body',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: initialState,
      platform: _RecordingPlatformServices(),
    );
    final syncService = _ManualSyncService(
      firstSyncError: const WebDavException(
        'WebDAV authentication failed. Check the username and app password.',
        statusCode: HttpStatus.unauthorized,
      ),
      result: AppSyncRunResult(
        syncResult: const AppSyncResult(
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

    await tester.tap(find.byTooltip('Sync now').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining(
        'Enter the email address and the app password generated under Third-party app management.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Do not enter the account login password or the sync encryption passphrase here.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });

  testWidgets('localized sync failures stay inside narrow paper feedback',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    tester.binding.platformDispatcher.localeTestValue =
        const Locale('zh', 'CN');
    tester.binding.platformDispatcher.localesTestValue = [
      const Locale('zh', 'CN'),
    ];
    addTearDown(() {
      tester.binding.platformDispatcher.clearLocaleTestValue();
      tester.binding.platformDispatcher.clearLocalesTestValue();
      tester.binding.setSurfaceSize(null);
    });

    final initialState = AppState(
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings.jianguoyun(
          username: 'user@example.test',
          password: 'provider-app-password',
          encryptionPassphrase: 'independent-sync-passphrase',
        ),
      ),
      papers: [
        PaperData(
          id: 'narrow-sync-error-note',
          type: PaperTypes.note,
          title: 'Narrow sync error',
          content: 'Keep localized failure feedback readable.',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: initialState,
      platform: _RecordingPlatformServices(),
    );
    final syncService = _ManualSyncService(
      firstSyncError: const WebDavException(
        'WebDAV authentication failed. Check the username and app password.',
        statusCode: HttpStatus.unauthorized,
      ),
      result: AppSyncRunResult(
        syncResult: const AppSyncResult(
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
        initialSurfacePaperId: 'narrow-sync-error-note',
        paperWindowMode: true,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('narrow-sync-error-note-sync-now')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.binding.setSurfaceSize(const Size(220, 800));
    await tester.pump();

    final snackBar = find.byType(SnackBar);
    final message = find.descendant(
      of: snackBar,
      matching: find.textContaining('同步失败'),
    );
    final retry = find.widgetWithText(SnackBarAction, '重试');
    expect(snackBar, findsOneWidget);
    expect(message, findsOneWidget);
    expect(retry, findsOneWidget);
    expect(tester.takeException(), isNull);

    final screen = const Rect.fromLTWH(0, 0, 220, 800);
    final snackRect = tester.getRect(snackBar);
    final messageRect = tester.getRect(message);
    final retryRect = tester.getRect(retry);
    void expectInside(Rect outer, Rect inner) {
      expect(inner.left, greaterThanOrEqualTo(outer.left));
      expect(inner.top, greaterThanOrEqualTo(outer.top));
      expect(inner.right, lessThanOrEqualTo(outer.right));
      expect(inner.bottom, lessThanOrEqualTo(outer.bottom));
    }

    expectInside(screen, snackRect);
    expectInside(snackRect, messageRect);
    expectInside(snackRect, retryRect);
    expect(retryRect.top, greaterThan(messageRect.top));
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

  testWidgets('manual sync flushes a durable batch without legacy upload',
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
      maxTitleLength: 64,
      papers: [
        PaperData(
          id: 'manual-durable-note',
          type: PaperTypes.note,
          title: 'Local',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: initialState,
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(initialState);
    final syncedState = AppState.fromJson(initialState.toJson())
      ..papers.single.title = 'Synced';
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: syncedState,
          message: 'Local data uploaded.',
        ),
        state: syncedState,
      ),
      prepareDurableBatch: true,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-durable-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync']);
    expect(syncService.localUploadCalls, 0);
    expect(syncService.syncPendingBatchDeviceIds, ['device-widget-test']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
  });

  testWidgets(
      'idempotent local edit upload reapplies platform before silent sync',
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
      pinnedTodoHotKey: 'Ctrl+Alt+L',
      papers: [
        PaperData(
          id: 'idempotent-upload-note',
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
    final uploadedState = AppState(
      sync: syncSettings.copy()
        ..operationDeviceSequences = const {'device-a': 1},
      pinnedTodoHotKey: 'Ctrl+Alt+U',
      papers: [
        PaperData(
          id: 'idempotent-upload-note',
          type: PaperTypes.note,
          title: 'Canonical upload',
          content: 'Local body',
        ),
      ],
    );
    final syncedState = AppState(
      sync: syncSettings.copy()
        ..operationDeviceSequences = const {'device-a': 2},
      pinnedTodoHotKey: 'Ctrl+Alt+S',
      papers: [
        PaperData(
          id: 'idempotent-upload-note',
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
      find.byKey(const ValueKey('idempotent-upload-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['upload', 'sync']);
    expect(syncService.localUploadCalls, 1);
    expect(syncService.calls, 1);
    expect(syncService.syncLocalDeviceSequences, [
      {'device-a': 1},
    ]);
    expect(platform.paperWindows.restoredTitleSnapshots, [
      ['Canonical upload'],
      ['Synced'],
    ]);
    expect(platform.tray.rebuildTitleSnapshots.last, ['Synced']);
    expect(platform.systemIntegration.registeredHotkeys, [
      ('Ctrl+Alt+U', ''),
      ('Ctrl+Alt+S', ''),
    ]);
    expect(controller.state.papers.single.title, 'Synced');
  });

  testWidgets('sync stays busy while pending local upload is running',
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
          id: 'overlap-note',
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
    final uploadedState = AppState(
      sync: syncSettings.copy()
        ..operationDeviceSequences = const {'device-a': 1},
      papers: [
        PaperData(
          id: 'overlap-note',
          type: PaperTypes.note,
          title: 'Draft',
          content: 'Local body',
        ),
      ],
    );
    final syncedState = AppState(
      sync: syncSettings.copy()
        ..operationDeviceSequences = const {'device-a': 2},
      papers: [
        PaperData(
          id: 'overlap-note',
          type: PaperTypes.note,
          title: 'Synced',
          content: 'Local body',
        ),
      ],
    );
    final localUploadGate = Completer<void>();
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: syncedState,
          message: 'Remote data downloaded.',
        ),
        state: syncedState,
      ),
      firstLocalUploadGate: localUploadGate.future,
      localUploadState: uploadedState,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('overlap-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();

    expect(syncService.events, ['upload']);
    expect(syncService.calls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(syncService.events, ['upload']);
    expect(syncService.calls, 0);

    localUploadGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['upload', 'sync', 'sync']);
    expect(syncService.localUploadCalls, 1);
    expect(syncService.calls, 2);
    expect(controller.state.papers.single.title, 'Synced');
    expect(platform.paperWindows.restoredTitleSnapshots, [
      ['Draft'],
      ['Synced'],
      ['Synced'],
    ]);
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

  testWidgets('auto sync timer waits while settings dialog is open',
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
        autoSyncIntervalMinutes: 1,
      ),
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        sync: syncSettings,
        papers: [
          PaperData(
            id: 'settings-auto-sync-note',
            type: PaperTypes.note,
            title: 'Local before settings',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(
      filePath: 'build/test-widget-settings-auto-sync.json',
    );
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'settings-auto-sync-note',
          type: PaperTypes.note,
          title: 'Synced after settings',
          content: 'Synced after timer',
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

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Settings'), findsOneWidget);
    expect(syncService.calls, 0);

    await tester.pump(const Duration(minutes: 1));
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 0);
    expect(controller.state.papers.single.title, 'Local before settings');
    expect(find.text('Remote data downloaded.'), findsNothing);

    await _dismissVisibleDialog(tester);
    await tester.pumpAndSettle();
    await tester.pump();

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced after settings');
    expect(find.text('Remote data downloaded.'), findsNothing);
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

    expect(syncService.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    expect(syncService.calls, 2);
    expect(find.text('Remote data downloaded.'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(syncService.calls, 3);
    expect(find.text('Remote data downloaded.'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();

    expect(syncService.calls, 4);
    expect(find.text('Remote data downloaded.'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(syncService.calls, 5);
    expect(find.text('Remote data downloaded.'), findsNothing);
  });

  testWidgets('lifecycle sync queues behind an active WebDAV sync',
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
            id: 'queued-lifecycle-note',
            type: PaperTypes.note,
            title: 'Queued lifecycle local',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(
      filePath: 'build/test-widget-queued-lifecycle-sync.json',
    );
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'queued-lifecycle-note',
          type: PaperTypes.note,
          title: 'Queued lifecycle synced',
          content: 'Synced after queued lifecycle request',
        ),
      ],
    );
    final firstSyncGate = Completer<void>();
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: syncedState,
          message: 'Remote data downloaded.',
        ),
        state: syncedState,
      ),
      firstSyncGate: firstSyncGate.future,
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

    expect(syncService.events, ['sync']);
    expect(syncService.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(syncService.events, ['sync']);
    expect(syncService.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    expect(syncService.events, ['sync']);
    expect(syncService.calls, 1);

    firstSyncGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync', 'sync']);
    expect(syncService.calls, 2);
    expect(controller.state.papers.single.title, 'Queued lifecycle synced');
    expect(find.text('Remote data downloaded.'), findsNothing);
  });

  testWidgets('lifecycle sync waits while settings dialog is open',
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
            id: 'settings-lifecycle-note',
            type: PaperTypes.note,
            title: 'Local before settings',
            content: 'Local body',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = StateStore(
      filePath: 'build/test-widget-settings-lifecycle-sync.json',
    );
    final syncedState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'settings-lifecycle-note',
          type: PaperTypes.note,
          title: 'Synced after settings closes',
          content: 'Synced body',
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

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 0);
    expect(controller.state.papers.single.title, 'Local before settings');
    expect(find.text('Remote data downloaded.'), findsNothing);

    await _dismissVisibleDialog(tester);
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 1);
    expect(
        controller.state.papers.single.title, 'Synced after settings closes');
    expect(find.text('Remote data downloaded.'), findsNothing);
  });

  testWidgets('lifecycle sync flushes pending local edits before debounce',
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
          id: 'lifecycle-pending-note',
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
    final uploadedState = AppState(
      sync: syncSettings.copy()
        ..operationDeviceSequences = const {'device-a': 1},
      papers: [
        PaperData(
          id: 'lifecycle-pending-note',
          type: PaperTypes.note,
          title: 'Draft',
          content: 'Local body',
        ),
      ],
    );
    final syncedState = AppState(
      sync: syncSettings.copy()
        ..operationDeviceSequences = const {'device-a': 2},
      papers: [
        PaperData(
          id: 'lifecycle-pending-note',
          type: PaperTypes.note,
          title: 'Synced after lifecycle',
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
      localUploadState: uploadedState,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('lifecycle-pending-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));

    expect(syncService.events, isEmpty);
    expect(syncService.localUploadCalls, 0);
    expect(syncService.calls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.localUploadCalls, 1);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced after lifecycle');
    expect(find.text('Remote data downloaded.'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(syncService.events, ['upload', 'sync']);
  });

  testWidgets('local save durably persists content and pending sync batch',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final testDirectory =
        Directory('build/test-widget-durable-sync-outbox-create');
    if (testDirectory.existsSync()) {
      testDirectory.deleteSync(recursive: true);
    }
    testDirectory.createSync(recursive: true);
    addTearDown(() {
      if (testDirectory.existsSync()) {
        testDirectory.deleteSync(recursive: true);
      }
    });
    final statePath = '${testDirectory.path}/state.json';
    final deviceIdPath = '${testDirectory.path}/sync-device-id';
    const deviceId = 'device-widget-durable-outbox';
    File(deviceIdPath).writeAsStringSync(deviceId);

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
      sync: syncSettings,
      maxTitleLength: 64,
      papers: [
        PaperData(
          id: 'durable-outbox-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState.fromJson(initialState.toJson()),
      platform: platform,
    );
    final store = StateStore(filePath: statePath);
    await tester.runAsync(() => store.save(initialState));
    final syncService = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(filePath: deviceIdPath),
      webDavFactory: (_, {deviceId}) {
        throw StateError('WebDAV must not run before the debounce expires.');
      },
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('durable-outbox-note-title')),
      'Durable draft',
    );
    await _waitForSavedTrayTitle(tester, platform, 'Durable draft');

    final reloaded = (await tester.runAsync(
      () => StateStore(filePath: statePath).load(),
    ))!;
    final pendingBatch = reloaded.sync.pendingOperationBatch;
    expect(reloaded.papers.single.title, 'Durable draft');
    expect(pendingBatch, isNotNull);
    expect(pendingBatch!.deviceId, deviceId);
    expect(
      AppState.fromJson(pendingBatch.baseState).papers.single.title,
      'Local',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('local save preserves disk batch when pending preparation fails',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final testDirectory =
        Directory('build/test-widget-durable-sync-outbox-prepare-failure');
    if (testDirectory.existsSync()) {
      testDirectory.deleteSync(recursive: true);
    }
    testDirectory.createSync(recursive: true);
    addTearDown(() {
      if (testDirectory.existsSync()) {
        testDirectory.deleteSync(recursive: true);
      }
    });
    final statePath = '${testDirectory.path}/state.json';
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
    final batchBaseState = AppState(
      sync: syncSettings.copy(),
      maxTitleLength: 64,
      papers: [
        PaperData(
          id: 'durable-outbox-failure-note',
          type: PaperTypes.note,
          title: 'Batch base',
          content: 'Local body',
        ),
      ],
    );
    final existingBatch = PendingSyncOperationBatch(
      baseState: batchBaseState.toJson(),
      deviceId: 'device-existing-batch',
      startSequence: 7,
      createdAtUtc: DateTime.utc(2026, 7, 11, 8, 30),
    );
    final diskState = AppState(
      sync: syncSettings.copy()..pendingOperationBatch = existingBatch,
      maxTitleLength: 64,
      papers: [
        PaperData(
          id: 'durable-outbox-failure-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controllerState = AppState.fromJson(diskState.toJson());
    controllerState.sync.pendingOperationBatch = null;
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: controllerState,
      platform: platform,
    );
    final store = StateStore(filePath: statePath);
    await tester.runAsync(() => store.save(diskState));
    final syncService = _ThrowingPendingPreparationSyncService();

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('durable-outbox-failure-note-title')),
      'Saved after failure',
    );
    await _waitForSavedTrayTitle(
      tester,
      platform,
      'Saved after failure',
    );

    final reloaded = (await tester.runAsync(
      () => StateStore(filePath: statePath).load(),
    ))!;
    final pendingBatch = reloaded.sync.pendingOperationBatch;
    expect(syncService.prepareCalls, 1);
    expect(reloaded.papers.single.title, 'Saved after failure');
    expect(pendingBatch, isNotNull);
    expect(pendingBatch!.deviceId, existingBatch.deviceId);
    expect(pendingBatch.startSequence, existingBatch.startSequence);
    expect(pendingBatch.createdAtUtc, existingBatch.createdAtUtc);
    expect(pendingBatch.baseState, existingBatch.baseState);
    expect(identical(pendingBatch, existingBatch), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('local save keeps the disk batch when sync is not configured',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final diskBatch = _pendingSyncBatchForTest(
      deviceId: 'device-disk-authoritative',
      title: 'Disk base',
      startSequence: 11,
    );
    final memoryBatch = _pendingSyncBatchForTest(
      deviceId: 'device-memory-stale',
      title: 'Memory base',
      startSequence: 3,
    );
    final diskState = AppState(
      sync: SyncSettings(pendingOperationBatch: diskBatch),
      maxTitleLength: 20,
      papers: [
        PaperData(
          id: 'unconfigured-disk-batch-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controllerState = AppState.fromJson(diskState.toJson());
    controllerState.sync.pendingOperationBatch = memoryBatch;
    final controller = RePaperTodoController(
      initialState: controllerState,
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(diskState);

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('unconfigured-disk-batch-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    final controllerBatch = controller.state.sync.pendingOperationBatch;
    final savedBatch = store.savedState.sync.pendingOperationBatch;
    expect(controller.state.papers.single.title, 'Draft');
    expect(store.savedState.papers.single.title, 'Draft');
    expect(controllerBatch, isNotNull);
    expect(savedBatch, isNotNull);
    expect(controllerBatch!.deviceId, diskBatch.deviceId);
    expect(savedBatch!.deviceId, diskBatch.deviceId);
    expect(controllerBatch.startSequence, diskBatch.startSequence);
    expect(savedBatch.startSequence, diskBatch.startSequence);
    expect(identical(controllerBatch, diskBatch), isFalse);
  });

  testWidgets('local save treats a null disk batch as authoritative',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final staleMemoryBatch = _pendingSyncBatchForTest(
      deviceId: 'device-memory-stale-null-disk',
      title: 'Stale memory base',
      startSequence: 3,
    );
    final diskState = AppState(
      maxTitleLength: 20,
      papers: [
        PaperData(
          id: 'null-disk-batch-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controllerState = AppState.fromJson(diskState.toJson());
    controllerState.sync.pendingOperationBatch = staleMemoryBatch;
    final controller = RePaperTodoController(
      initialState: controllerState,
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(diskState);

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('null-disk-batch-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.state.papers.single.title, 'Draft');
    expect(store.savedState.papers.single.title, 'Draft');
    expect(controller.state.sync.pendingOperationBatch, isNull);
    expect(store.savedState.sync.pendingOperationBatch, isNull);
  });

  testWidgets('failed pending preparation does not revive a stale memory batch',
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
      ),
    );
    final diskState = AppState(
      sync: syncSettings,
      papers: [
        PaperData(
          id: 'null-disk-prepare-failure-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controllerState = AppState.fromJson(diskState.toJson());
    controllerState.sync.pendingOperationBatch = _pendingSyncBatchForTest(
      deviceId: 'device-memory-stale-prepare-failure',
      title: 'Stale memory base',
      startSequence: 4,
    );
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: controllerState,
      platform: platform,
    );
    final store = _MemoryStateStore();
    await store.save(diskState);
    final syncService = _ThrowingPendingPreparationSyncService();

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('null-disk-prepare-failure-note-title')),
      'Saved after failure',
    );
    await _waitForSavedTrayTitle(tester, platform, 'Saved after failure');

    expect(syncService.prepareCalls, 1);
    expect(controller.state.sync.pendingOperationBatch, isNull);
    expect(store.savedState.sync.pendingOperationBatch, isNull);
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

  testWidgets('debounced durable batch sync skips legacy operation upload',
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
      maxTitleLength: 64,
      papers: [
        PaperData(
          id: 'debounce-durable-note',
          type: PaperTypes.note,
          title: 'Local',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: initialState,
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(initialState);
    final syncedState = AppState.fromJson(initialState.toJson())
      ..papers.single.title = 'Synced';
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: syncedState,
          message: 'Local data uploaded.',
        ),
        state: syncedState,
      ),
      prepareDurableBatch: true,
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
        syncService: syncService,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('debounce-durable-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 4));
    expect(syncService.events, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(syncService.events, ['sync']);
    expect(syncService.localUploadCalls, 0);
    expect(syncService.syncPendingBatchDeviceIds, ['device-widget-test']);
    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, 'Synced');
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

  testWidgets('auto sync retries pending edits after silent upload failure',
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
        autoSyncIntervalMinutes: 1,
      ),
    );
    final initialState = AppState(
      sync: syncSettings.copy(),
      papers: [
        PaperData(
          id: 'auto-retry-note',
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
          id: 'auto-retry-note',
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
            id: 'auto-retry-note',
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
      find.byKey(const ValueKey('auto-retry-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(syncService.events, ['upload']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.calls, 0);
    expect(controller.state.papers.single.title, 'Draft');
    expect(find.textContaining('unsupported or corrupted'), findsNothing);

    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(syncService.events, ['upload', 'upload', 'sync']);
    expect(syncService.localUploadCalls, 2);
    expect(syncService.localUploadBeforeTitles, ['Local', 'Local']);
    expect(syncService.localUploadAfterTitles, ['Draft', 'Draft']);
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

  testWidgets('exit command waits for active sync before flushing local edits',
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
          id: 'exit-active-sync-note',
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
          id: 'exit-active-sync-note',
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
            id: 'exit-active-sync-note',
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

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    expect(syncService.events, ['sync']);

    await tester.enterText(
      find.byKey(const ValueKey('exit-active-sync-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    startup.addCommand(const StartupCommand(StartupCommandKind.exit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync']);
    expect(syncService.localUploadCalls, 0);
    expect(platform.systemIntegration.exitApplicationCount, 0);
    expect(platform.tray.disposeCount, 0);

    firstSyncGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync', 'upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.syncLocalDeviceSequences, [
      {},
      {'device-a': 1},
    ]);
    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.systemIntegration.exitApplicationCount, 1);
    expect(platform.tray.disposeCount, 1);
    expect(find.text('Local data uploaded.'), findsOneWidget);
  });

  testWidgets('duplicate exit commands share the same save and sync flow',
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
          id: 'duplicate-exit-note',
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
          id: 'duplicate-exit-note',
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
            id: 'duplicate-exit-note',
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

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    expect(syncService.events, ['sync']);

    await tester.enterText(
      find.byKey(const ValueKey('duplicate-exit-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    startup
      ..addCommand(const StartupCommand(StartupCommandKind.exit))
      ..addCommand(const StartupCommand(StartupCommandKind.exit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync']);
    expect(syncService.localUploadCalls, 0);
    expect(platform.systemIntegration.exitApplicationCount, 0);
    expect(platform.tray.disposeCount, 0);

    firstSyncGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync', 'upload', 'sync']);
    expect(syncService.localUploadCalls, 1);
    expect(syncService.calls, 2);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.systemIntegration.exitApplicationCount, 1);
    expect(platform.tray.disposeCount, 1);
  });

  testWidgets('exit command ignores late native requests while syncing',
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
          id: 'late-exit-event-note',
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
          id: 'late-exit-event-note',
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
            id: 'late-exit-event-note',
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

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    expect(syncService.events, ['sync']);

    await tester.enterText(
      find.byKey(const ValueKey('late-exit-event-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    startup.addCommand(const StartupCommand(StartupCommandKind.exit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    platform.paperWindows.emitSurfaceUpdate(
      PaperData(
        id: 'late-exit-event-note',
        type: PaperTypes.note,
        title: 'Late hidden note',
        content: 'Local body',
        x: 480,
        y: 360,
        isVisible: false,
      ),
    );
    platform.paperWindows.emitPaperOpenRequest('late-exit-event-note');
    platform.paperWindows.emitPaperDeleteRequest('late-exit-event-note');
    startup
      ..addCommand(const StartupCommand(StartupCommandKind.settings))
      ..addCommand(const StartupCommand(StartupCommandKind.newNote));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync']);
    expect(controller.state.papers.map((paper) => paper.id), [
      'late-exit-event-note',
    ]);
    expect(controller.state.papers.single.isVisible, true);
    expect(controller.state.papers.single.x, isNot(480));
    expect(controller.state.sync.isPaperDeleted('late-exit-event-note'), false);
    expect(platform.paperWindows.hiddenTitles, isEmpty);
    expect(platform.paperWindows.shownTitles, isEmpty);
    expect(platform.systemIntegration.exitApplicationCount, 0);
    expect(platform.tray.disposeCount, 0);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Note1'), findsNothing);

    firstSyncGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync', 'upload', 'sync']);
    expect(syncService.localUploadCalls, 1);
    expect(syncService.calls, 2);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(controller.state.papers.map((paper) => paper.id), [
      'late-exit-event-note',
    ]);
    expect(controller.state.papers.single.title, 'Synced');
    expect(controller.state.papers.single.isVisible, true);
    expect(controller.state.sync.isPaperDeleted('late-exit-event-note'), false);
    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.systemIntegration.exitApplicationCount, 1);
    expect(platform.tray.disposeCount, 1);
  });

  testWidgets('exit command continues after a failing active sync',
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
          id: 'exit-failing-active-sync-note',
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
          id: 'exit-failing-active-sync-note',
          type: PaperTypes.note,
          title: 'Synced after exit',
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
      firstSyncError: StateError('Temporary active sync failure'),
      localUploadState: AppState(
        sync: syncSettings.copy()
          ..operationDeviceSequences = const {'device-a': 1},
        papers: [
          PaperData(
            id: 'exit-failing-active-sync-note',
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

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    expect(syncService.events, ['sync']);

    await tester.enterText(
      find.byKey(const ValueKey('exit-failing-active-sync-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    startup.addCommand(const StartupCommand(StartupCommandKind.exit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync']);
    expect(platform.systemIntegration.exitApplicationCount, 0);
    expect(platform.tray.disposeCount, 0);

    firstSyncGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.events, ['sync', 'upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.syncLocalDeviceSequences, [
      {},
      {'device-a': 1},
    ]);
    expect(controller.state.papers.single.title, 'Synced after exit');
    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.systemIntegration.exitApplicationCount, 1);
    expect(platform.tray.disposeCount, 1);
    expect(
        find.textContaining('Temporary active sync failure'), findsOneWidget);
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
    await _selectSettingsCategory(tester, 'sync');
    await tester.scrollUntilVisible(
      _settingsToggleTile('Enable WebDAV sync'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(_settingsToggleTile('Enable WebDAV sync'));
    await tester.pumpAndSettle();
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.sync.enabled, false);
    expect(syncService.localUploadCalls, 0);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _selectSettingsCategory(tester, 'sync');
    await tester.scrollUntilVisible(
      _settingsToggleTile('Enable WebDAV sync'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(_settingsToggleTile('Enable WebDAV sync'));
    await tester.pumpAndSettle();
    await _commitVisibleDialog(tester);
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
    await _dismissVisibleDialog(tester);
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
    await _commitVisibleDialog(tester);
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

  testWidgets(
      'settings save preserves runtime sync metadata and latest disk batch',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final initialDiskBatch = _pendingSyncBatchForTest(
      deviceId: 'device-settings-disk-initial',
      title: 'Initial disk base',
      startSequence: 5,
    );
    final staleMemoryBatch = _pendingSyncBatchForTest(
      deviceId: 'device-settings-memory-stale',
      title: 'Stale memory base',
      startSequence: 2,
    );
    final latestDiskBatch = _pendingSyncBatchForTest(
      deviceId: 'device-settings-disk-latest',
      title: 'Latest disk base',
      startSequence: 9,
    );
    final runtimeExtra = <String, Object?>{
      'runtimeUnknown': <String, Object?>{
        'nested': <Object?>[
          'keep',
          <String, Object?>{'value': 7},
        ],
      },
    };
    final webDavExtra = <String, Object?>{
      'forwardCompatible': <String, Object?>{
        'nested': <Object?>[
          'keep',
          <String, Object?>{'value': 11},
        ],
      },
    };
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
        extra: webDavExtra,
      ),
    );
    final diskState = AppState(
      sync: syncSettings.copy()..pendingOperationBatch = initialDiskBatch,
      papers: [
        PaperData(
          id: 'settings-runtime-metadata-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Local body',
        ),
      ],
    );
    final controllerState = AppState.fromJson(diskState.toJson());
    controllerState.sync
      ..operationDeviceSequences = const {'device-runtime': 4}
      ..pendingOperationBatch = staleMemoryBatch
      ..deletedPaperTombstones = const {
        'deleted-paper': '2026-07-11T08:00:00.000Z',
      }
      ..deletedTodoItemTombstones = const {
        'todo-paper': {
          'deleted-item': '2026-07-11T08:05:00.000Z',
        },
      }
      ..extra = runtimeExtra;
    final controller = RePaperTodoController(
      initialState: controllerState,
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(diskState);
    final syncedState = AppState.fromJson(controllerState.toJson());
    syncedState.papers.single.title = 'Synced';
    final syncService = _ManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.uploaded,
          state: syncedState,
          message: 'Local data uploaded.',
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

    await tester.enterText(
      find.byKey(const ValueKey('settings-runtime-metadata-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      controller.state.sync.pendingOperationBatch!.deviceId,
      initialDiskBatch.deviceId,
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    store.savedState.sync.pendingOperationBatch = latestDiskBatch.copy();
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    final savedSync = store.savedState.sync;
    expect(controller.state.sync.operationDeviceSequences,
        const {'device-runtime': 4});
    expect(savedSync.operationDeviceSequences, const {'device-runtime': 4});
    expect(controller.state.sync.pendingOperationBatch!.deviceId,
        latestDiskBatch.deviceId);
    expect(savedSync.pendingOperationBatch!.deviceId, latestDiskBatch.deviceId);
    expect(controller.state.sync.deletedPaperTombstones, const {
      'deleted-paper': '2026-07-11T08:00:00.000Z',
    });
    expect(savedSync.deletedPaperTombstones, const {
      'deleted-paper': '2026-07-11T08:00:00.000Z',
    });
    expect(controller.state.sync.deletedTodoItemTombstones, const {
      'todo-paper': {
        'deleted-item': '2026-07-11T08:05:00.000Z',
      },
    });
    expect(savedSync.deletedTodoItemTombstones, const {
      'todo-paper': {
        'deleted-item': '2026-07-11T08:05:00.000Z',
      },
    });
    expect(controller.state.sync.extra, runtimeExtra);
    expect(savedSync.extra, runtimeExtra);
    expect(
      identical(
        controller.state.sync.extra['runtimeUnknown'],
        runtimeExtra['runtimeUnknown'],
      ),
      isFalse,
    );
    expect(controller.state.sync.webDav.extra, webDavExtra);
    expect(savedSync.webDav.extra, webDavExtra);
    expect(
      identical(
        controller.state.sync.webDav.extra['forwardCompatible'],
        webDavExtra['forwardCompatible'],
      ),
      isFalse,
    );
    expect(
      identical(
        savedSync.webDav.extra['forwardCompatible'],
        controller.state.sync.webDav.extra['forwardCompatible'],
      ),
      isFalse,
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(syncService.events, ['sync']);
    expect(syncService.localUploadBeforeTitles, isEmpty);
    expect(syncService.localUploadAfterTitles, isEmpty);
    expect(
      syncService.syncPendingBatchDeviceIds,
      [latestDiskBatch.deviceId],
    );
  });

  testWidgets('changing WebDAV target clears stale durable remote progress',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final pendingBatch = _pendingSyncBatchForTest(
      deviceId: 'device-old-root',
      title: 'Old root base',
      startSequence: 7,
    );
    final initialState = AppState(
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings(
          endpoint: 'https://dav.example.test/',
          username: 'user',
          password: 'pass',
          encryptionPassphrase: 'shared sync secret',
          rootPath: 'old-root',
        ),
      )
        ..operationDeviceSequences = const {'device-old-root': 7}
        ..pendingOperationBatch = pendingBatch
        ..deletedPaperTombstones = const {
          'deleted-paper': '2026-07-11T08:00:00.000Z',
        },
      papers: [
        PaperData(
          id: 'sync-target-change-note',
          type: PaperTypes.note,
          title: 'Local',
          content: 'Keep local content',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState.fromJson(initialState.toJson()),
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();
    await store.save(initialState);

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _selectSettingsCategory(tester, 'sync');
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Remote folder'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Remote folder'),
      'new-root',
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    for (final sync in [controller.state.sync, store.savedState.sync]) {
      expect(sync.webDav.rootPath, 'new-root');
      expect(sync.operationDeviceSequences, isEmpty);
      expect(sync.pendingOperationBatch, isNull);
      expect(sync.deletedPaperTombstones, const {
        'deleted-paper': '2026-07-11T08:00:00.000Z',
      });
    }
    expect(controller.state.papers.single.content, 'Keep local content');
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
    await _commitVisibleDialog(tester);
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
    await _selectSettingsCategory(tester, 'general');
    await tester.scrollUntilVisible(
      find.text('Pinned todo hotkey'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await _captureSettingsHotKey(
      tester,
      'Pinned todo hotkey',
      LogicalKeyboardKey.keyT,
    );
    await _commitVisibleDialog(tester);
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

  testWidgets('settings save failure restores paused pending local edit upload',
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
          id: 'settings-save-paused-note',
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
          id: 'settings-save-paused-note',
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
            id: 'settings-save-paused-note',
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
      find.byKey(const ValueKey('settings-save-paused-note-title')),
      'Draft',
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    store.nextSaveError =
        const StateStoreException('settings save failed', 'disk full');
    await _commitVisibleDialog(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Settings save failed:'), findsOneWidget);
    expect(syncService.events, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(syncService.events, ['upload', 'sync']);
    expect(syncService.localUploadBeforeTitles, ['Local']);
    expect(syncService.localUploadAfterTitles, ['Draft']);
    expect(syncService.calls, 1);
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
    store.nextSaveError =
        const StateStoreException('settings save failed', 'disk full');
    await _commitVisibleDialog(tester);
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

    expect(find.byTooltip('Open in default .txt editor'), findsOneWidget);

    await tester.tap(find.byTooltip('Open in default .txt editor'));
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

  testWidgets('surface top bar opens note markdown with PaperTodo label',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        externalMarkdownExtension: '.txt',
        papers: [
          PaperData(
            id: 'surface-external-note',
            type: PaperTypes.note,
            title: 'Surface external Note',
            content: '# Surface export',
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

    expect(find.text('TX'), findsNothing);

    await tester.tap(find.byTooltip('Open paper surface'));
    await tester.pumpAndSettle();

    expect(find.text('TX'), findsOneWidget);
    expect(find.byTooltip('Open in default .txt editor'), findsWidgets);

    await tester.tap(find.text('TX'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.externalFiles.openedPaths, hasLength(1));
    final openedFile = File(platform.externalFiles.openedPaths.single);
    expect(openedFile.path.endsWith('.txt'), true);
    expect(openedFile.readAsStringSync(), '# Surface export');
  });

  testWidgets('external markdown export uses current note editor text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        externalMarkdownExtension: '.md',
        papers: [
          PaperData(
            id: 'external-current-editor-note',
            type: PaperTypes.note,
            title: 'Current editor note',
            content: '# Old note',
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
    await tester.tap(find.byTooltip('Open paper surface'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('external-current-editor-note-preview')),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('external-current-editor-note-content')),
      '# Draft note\n\nThis text is not waiting for save debounce.',
    );
    await tester.pump();

    await tester.tap(find.text('MD'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(platform.externalFiles.openedPaths, hasLength(1));
    final openedFile = File(platform.externalFiles.openedPaths.single);
    expect(openedFile.path.endsWith('.md'), true);
    expect(
      openedFile.readAsStringSync(),
      '# Draft note\n\nThis text is not waiting for save debounce.',
    );
  });

  testWidgets('paper window MD action uses PaperTodo header typography',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        externalMarkdownExtension: '.md',
        papers: [
          PaperData(
            id: 'md-header-note',
            type: PaperTypes.note,
            title: 'MD header note',
            content: '# Header parity',
            width: 440,
            height: 420,
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: 'md-header-note',
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final actionFinder =
        find.byKey(const ValueKey('md-header-note-open-markdown'));
    expect(actionFinder, findsOneWidget);
    final mdFinder = find.descendant(
      of: actionFinder,
      matching: find.text('MD'),
    );
    expect(mdFinder, findsOneWidget);

    final mdText = tester.widget<Text>(mdFinder);
    expect(mdText.style?.fontSize, 10.5);
    expect(mdText.style?.fontWeight, FontWeight.w400);

    final inheritedStyle = DefaultTextStyle.of(
      tester.element(mdFinder),
    ).style;
    final paperColors = PaperTodoThemeColors.resolve(
      brightness: Brightness.light,
      colorScheme: ColorSchemes.warm,
      customThemeColorHex: '',
    );
    expect(inheritedStyle.color, paperColors.weakText);

    final focusGuard = tester.widget<ExcludeFocus>(
      find.descendant(
        of: actionFinder,
        matching: find.byType(ExcludeFocus),
      ),
    );
    expect(focusGuard.excluding, true);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(actionFinder));
    await tester.pump();
    expect(
      DefaultTextStyle.of(tester.element(mdFinder)).style.color,
      paperColors.text,
    );

    await mouse.down(tester.getCenter(actionFinder));
    await tester.pump();
    final pressedOpacity = tester.widget<Opacity>(
      find.descendant(
        of: actionFinder,
        matching: find.byType(Opacity),
      ),
    );
    expect(pressedOpacity.opacity, 0.7);
    await mouse.up();
    await tester.pump();
  });

  testWidgets('sanitizes long external markdown export names', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longPaperId =
        '${List.filled(90, 'a').join()}/bad:${List.filled(65, 'z').join()}\u007F\u0085tail';
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
    expect(
      fileName,
      isNot(contains(RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F-\x9F]'))),
    );
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

  testWidgets('Windows coordinator leaves reminders to paper windows',
      (tester) async {
    final dueAt = DateTime.now().subtract(const Duration(minutes: 5));
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        papers: [
          PaperData(
            id: 'coordinator-reminder-paper',
            title: 'Coordinator reminder',
            items: [
              PaperItem(
                id: 'coordinator-reminder-item',
                text: 'Must stay on its paper',
                dueAtLocal: dueAt.toIso8601String(),
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
        coordinatorWindowMode: true,
      ),
    );
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byKey(const ValueKey('windows-settings-window-surface')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Scaffold>(
            find.byKey(const ValueKey('windows-settings-window-surface')),
          )
          .backgroundColor,
      const Color(0xFF010203),
    );
    final settingsUnderlay = find.byKey(
      const ValueKey('windows-settings-paper-underlay'),
    );
    expect(settingsUnderlay, findsOneWidget);
    final settingsUnderlayDecoration = tester
        .widget<DecoratedBox>(settingsUnderlay)
        .decoration as BoxDecoration;
    expect(
      settingsUnderlayDecoration.color,
      Theme.of(tester.element(settingsUnderlay)).colorScheme.surface,
    );
    expect(
      settingsUnderlayDecoration.borderRadius,
      BorderRadius.circular(18),
    );
    expect(find.text('Must stay on its paper'), findsNothing);
  });

  testWidgets('Windows settings browses for a data directory', (tester) async {
    final selectedDirectory = Directory(
      p.join('build', 'test-widget-selected-data-directory'),
    ).absolute.path;
    final storage = _SelectableAppStorageHost(selectedDirectory);
    final platform = _RecordingPlatformServices(storage: storage);
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'data-directory-paper',
            title: 'Data directory',
            items: [PaperItem(id: 'data-directory-item', text: 'Preserve me')],
          ),
        ],
      ),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(controller: controller, store: _MemoryStateStore()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _selectSettingsCategory(tester, 'general');
    await tester.tap(
      find.byKey(const ValueKey('settings-data-directory-browse')),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('settings-data-directory')),
          )
          .controller
          ?.text,
      selectedDirectory,
    );
    expect(storage.committedDirectories, isEmpty);
    await _dismissVisibleDialog(tester);
    await tester.pump();
  });

  testWidgets('independent paper reminders stay on their owning paper',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dueAt = DateTime.now().subtract(const Duration(minutes: 5));
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderBubbleDurationSeconds: 5,
        papers: [
          PaperData(
            id: 'owning-reminder-paper',
            title: 'Owning paper',
            items: [
              PaperItem(
                id: 'owning-reminder-item',
                text: 'Visible reminder',
                dueAtLocal: dueAt.toIso8601String(),
              ),
            ],
          ),
          PaperData(
            id: 'other-reminder-paper',
            title: 'Other paper',
            items: [
              PaperItem(
                id: 'other-reminder-item',
                text: 'Duplicate reminder must stay hidden',
                dueAtLocal: dueAt.toIso8601String(),
              ),
            ],
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: 'owning-reminder-paper',
        paperWindowMode: true,
      ),
    );
    await tester.pump();

    expect(find.text('Visible reminder'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('Visible reminder'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Duplicate reminder must stay hidden'),
      findsNothing,
    );
  });

  testWidgets('Windows paper reminders use a native adjacent bubble',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dueAt = DateTime.now().subtract(const Duration(minutes: 5));
    final presented = <Map<String, Object?>>[];
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderBubbleDurationSeconds: 7,
        papers: [
          PaperData(
            id: 'native-reminder-paper',
            title: 'Native reminder',
            isCollapsed: true,
            items: [
              PaperItem(
                id: 'native-reminder-item',
                text: 'Show beside the capsule',
                dueAtLocal: dueAt.toIso8601String(),
              ),
            ],
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: 'native-reminder-paper',
        paperWindowMode: true,
        paperWindowReminderPresenter: (reminder) async {
          presented.add(Map<String, Object?>.from(reminder));
        },
      ),
    );
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(presented, hasLength(1));
    expect(presented.single['visible'], true);
    expect(presented.single['title'], 'Todo due soon');
    expect(presented.single['message'], contains('Show beside the capsule'));
    expect(presented.single['message'], contains('overdue'));
    expect(presented.single['durationSeconds'], 7);
    expect(presented.single['backgroundColor'], isA<int>());
    expect(presented.single['borderColor'], isA<int>());
    expect(presented.single['borderAlpha'], 150);
    expect(presented.single['iconBackgroundColor'], isA<int>());
    expect(presented.single['accentColor'], isA<int>());
    expect(
      presented.single['iconBackgroundColor'],
      isNot(presented.single['accentColor']),
    );
  });

  testWidgets('shows due todo reminders', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final dueAt = DateTime.now().subtract(const Duration(minutes: 5));
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
            isCollapsed: true,
            items: [
              PaperItem(
                id: 'reminder-item',
                text: 'Review deadline',
                dueAtLocal: dueAt.toIso8601String(),
              ),
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
    await tester.pump();

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(_snackBarTextContaining('Review deadline'), findsOneWidget);
    expect(
      _snackBarTextContaining(_formatReminderTimestamp(dueAt)),
      findsOneWidget,
    );
    expect(_snackBarTextContaining('overdue'), findsOneWidget);

    final openAction = tester.widget<SnackBarAction>(
      find.byWidgetPredicate(
        (widget) => widget is SnackBarAction && widget.label == 'Open',
      ),
    );
    openAction.onPressed();
    await tester.pump();

    expect(platform.paperWindows.shownTitles, contains('Reminder paper'));
    expect(controller.state.papers.single.isCollapsed, false);
    expect(store.savedState.papers.single.isCollapsed, false);
    expect(find.byTooltip('Back to board'), findsOneWidget);
  });

  testWidgets('todo reminder auto close pauses while hovered like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dueAt = DateTime.now().subtract(const Duration(minutes: 5));
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 1,
        todoReminderBubbleDurationSeconds: 1,
        papers: [
          PaperData(
            id: 'hover-reminder-paper',
            type: PaperTypes.todo,
            title: 'Hover',
            items: [
              PaperItem(
                id: 'hover-reminder-item',
                text: 'Stay visible',
                dueAtLocal: dueAt.toIso8601String(),
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

    final reminder = find.text('Todo due soon');
    expect(reminder, findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(tester.getCenter(reminder));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(reminder, findsOneWidget);

    await gesture.moveTo(const Offset(10, 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));

    expect(reminder, findsNothing);

    await gesture.removePointer();
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

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(_snackBarTextContaining('Review before delete'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete paper'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Todo due soon'), findsNothing);
    expect(controller.state.papers.single.id, isNot('delete-reminder-paper'));
    expect(controller.state.papers.single.type, PaperTypes.todo);
  });

  testWidgets('clearing a due date closes that item reminder', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final item = PaperItem(
      id: 'clear-due-reminder-item',
      text: 'Clear due reminder',
      dueAtLocal:
          DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 30,
        papers: [
          PaperData(
            id: 'clear-due-reminder-paper',
            type: PaperTypes.todo,
            title: 'Reminder paper',
            items: [item],
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

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(_snackBarTextContaining('Clear due reminder'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'clear-due-reminder-paper-clear-due-reminder-item-due-absolute',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(item.dueAtLocal, isNull);
    expect(find.text('Todo due soon'), findsNothing);
  });

  testWidgets('changing item reminder interval resets shown reminder cadence',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dueAt = DateTime.now().subtract(const Duration(minutes: 1));
    final item = PaperItem(
      id: 'reset-reminder-item',
      text: 'Recheck cadence',
      dueAtLocal: dueAt.toIso8601String(),
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 30,
        papers: [
          PaperData(
            id: 'reset-reminder-paper',
            type: PaperTypes.todo,
            title: 'Reset',
            items: [item],
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

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(_snackBarTextContaining('Recheck cadence'), findsOneWidget);

    await tester.tap(find.byTooltip('Set reminder interval'));
    await tester.pumpAndSettle();
    await tester.enterText(_reminderIntervalValueField(), '1');
    await _selectReminderIntervalUnit(
      tester,
      TodoReminderIntervalUnits.minutes,
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(item.reminderIntervalValue, 1);
    expect(item.reminderIntervalUnit, TodoReminderIntervalUnits.minutes);
    expect(find.text('Todo due soon'), findsNothing);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(_snackBarTextContaining('Recheck cadence'), findsOneWidget);
  });

  testWidgets('shows one-shot reminders before todo due time', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final soonDueAt = DateTime.now().add(const Duration(minutes: 5));
    final farDueAt = DateTime.now().add(const Duration(minutes: 20));
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
                dueAtLocal: soonDueAt.toIso8601String(),
              ),
              PaperItem(
                id: 'too-far-reminder-item',
                text: 'Too far away',
                dueAtLocal: farDueAt.toIso8601String(),
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

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(_snackBarTextContaining('Submit paper'), findsOneWidget);
    expect(
      _snackBarTextContaining(_formatReminderTimestamp(soonDueAt)),
      findsOneWidget,
    );
    expect(_snackBarTextContaining('in '), findsOneWidget);
    expect(_snackBarTextContaining('Too far away'), findsNothing);
  });

  testWidgets('shows item details for multiple due todo reminders',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final firstDueAt = DateTime.now().subtract(const Duration(minutes: 4));
    final secondDueAt = DateTime.now().subtract(const Duration(minutes: 2));
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 5,
        papers: [
          PaperData(
            id: 'multi-reminder-paper',
            type: PaperTypes.todo,
            title: 'Multi reminder',
            items: [
              PaperItem(
                id: 'multi-reminder-first',
                text: 'First task',
                dueAtLocal: firstDueAt.toIso8601String(),
              ),
              PaperItem(
                id: 'multi-reminder-second',
                text: 'Second task',
                dueAtLocal: secondDueAt.toIso8601String(),
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

    expect(find.text('Reminder: 2 todo items are due.'), findsOneWidget);
    expect(
      find.textContaining(
        'First task - Due ${_formatReminderTimestamp(firstDueAt)}',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Second task - Due ${_formatReminderTimestamp(secondDueAt)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Chinese fallback reminders fit narrow screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    tester.binding.platformDispatcher.localeTestValue =
        const Locale('zh', 'CN');
    tester.binding.platformDispatcher.localesTestValue = [
      const Locale('zh', 'CN'),
    ];
    addTearDown(() {
      tester.binding.platformDispatcher.clearLocaleTestValue();
      tester.binding.platformDispatcher.clearLocalesTestValue();
      tester.binding.setSurfaceSize(null);
    });

    final dueAt = DateTime.now().subtract(const Duration(minutes: 3));
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 10,
        todoReminderBubbleDurationSeconds: 5,
        papers: [
          PaperData(
            id: 'narrow-chinese-reminder-paper',
            type: PaperTypes.todo,
            title: '窄屏提醒',
            items: [
              for (var index = 0; index < 4; index++)
                PaperItem(
                  id: 'narrow-chinese-reminder-$index',
                  text: '第${index + 1}个需要在窄屏中完整换行显示的较长待办事项',
                  dueAtLocal: dueAt.toIso8601String(),
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

    final snackBar = find.byType(SnackBar);
    final title = find.descendant(
      of: snackBar,
      matching: find.text('提醒：4 个待办事项已到期。'),
    );
    final open = find.widgetWithText(SnackBarAction, '打开');
    expect(snackBar, findsOneWidget);
    expect(title, findsOneWidget);
    expect(open, findsOneWidget);
    expect(tester.takeException(), isNull);

    final screen = const Rect.fromLTWH(0, 0, 320, 640);
    final snackRect = tester.getRect(snackBar);
    final titleRect = tester.getRect(title);
    final openRect = tester.getRect(open);
    for (final inner in [snackRect, titleRect, openRect]) {
      expect(inner.left, greaterThanOrEqualTo(screen.left));
      expect(inner.top, greaterThanOrEqualTo(screen.top));
      expect(inner.right, lessThanOrEqualTo(screen.right));
      expect(inner.bottom, lessThanOrEqualTo(screen.bottom));
    }
    expect(
      _snackBarTextContaining('第4个需要在窄屏中完整换行显示的较长待办事项'),
      findsOneWidget,
    );
  });

  testWidgets('todo reminder item text matches PaperTodo fallback and trim',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fallbackDueAt = DateTime.now().subtract(const Duration(seconds: 1));
    final longDueAt = DateTime.now().subtract(const Duration(minutes: 1));
    final longText = List.filled(85, 'A').join();
    final controller = RePaperTodoController(
      initialState: AppState(
        useTodoReminderInterval: true,
        todoReminderIntervalValue: 10,
        todoReminderScope: TodoReminderScopes.nearest,
        todoReminderBubbleDurationSeconds: 5,
        papers: [
          PaperData(
            id: 'fallback-reminder-paper',
            type: PaperTypes.todo,
            title: 'Fallback reminder',
            items: [
              PaperItem(
                id: 'fallback-reminder-item',
                text: '   ',
                dueAtLocal: fallbackDueAt.toIso8601String(),
              ),
            ],
          ),
          PaperData(
            id: 'long-reminder-paper',
            type: PaperTypes.todo,
            title: 'Long reminder',
            items: [
              PaperItem(
                id: 'long-reminder-item',
                text: longText,
                dueAtLocal: longDueAt.toIso8601String(),
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

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(_snackBarTextContaining('Fallback reminder'), findsOneWidget);

    controller.state.todoReminderScope = TodoReminderScopes.all;
    controller.state.papers.first.items.first.done = true;
    await tester.pump(const Duration(seconds: 31));

    expect(
      _snackBarTextContaining('${longText.substring(0, 80)}...'),
      findsOneWidget,
    );
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

    expect(find.text('Todo due soon'), findsOneWidget);
    expect(_snackBarTextContaining('Near task'), findsOneWidget);
    expect(_snackBarTextContaining('Far task'), findsNothing);
  });

  testWidgets('sets item reminder intervals', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        todoReminderIntervalValue: 3,
        todoReminderIntervalUnit: TodoReminderIntervalUnits.hours,
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

    expect(
      tester.getSize(
        find.byKey(const ValueKey('todo-reminder-dialog-surface')),
      ),
      const Size(326, 216),
    );
    final intervalFieldFinder = _reminderIntervalValueField();
    final intervalField = tester.widget<TextField>(intervalFieldFinder);
    expect(intervalField.controller?.text, '3');
    final intervalEditable = tester.widget<EditableText>(
      find.descendant(
        of: intervalFieldFinder,
        matching: find.byType(EditableText),
      ),
    );
    expect(intervalEditable.focusNode.hasFocus, true);
    expect(
      intervalEditable.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
    final unitSelector = tester.widget<DropdownButton<String>>(
      find.byKey(const ValueKey('todo-reminder-interval-unit')),
    );
    expect(unitSelector.value, TodoReminderIntervalUnits.hours);

    await tester.enterText(_reminderIntervalValueField(), '2');
    await _selectReminderIntervalUnit(
      tester,
      TodoReminderIntervalUnits.hours,
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.reminderIntervalValue, 2);
    expect(item.reminderIntervalUnit, TodoReminderIntervalUnits.hours);
    expect(find.text('Every 2 hr'), findsNothing);

    final reminderRow = find.byKey(
      const ValueKey('item-reminder-paper-item-reminder-row'),
    );
    await tester.tapAt(
      tester.getCenter(reminderRow),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use global reminder interval').last);
    await tester.pumpAndSettle();

    expect(item.reminderIntervalValue, isNull);
    expect(item.reminderIntervalUnit, isNull);
    expect(find.text('Every 2 hr'), findsNothing);

    await tester.tap(find.byTooltip('Set reminder interval'));
    await tester.pumpAndSettle();
    await tester.enterText(_reminderIntervalValueField(), 'bad');
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(item.reminderIntervalValue, 3);
    expect(item.reminderIntervalUnit, TodoReminderIntervalUnits.hours);

    await tester.tap(find.byTooltip('Set reminder interval'));
    await tester.pumpAndSettle();
    await tester.enterText(_reminderIntervalValueField(), '999');
    await _selectReminderIntervalUnit(
      tester,
      TodoReminderIntervalUnits.minutes,
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(item.reminderIntervalValue, 240);
    expect(item.reminderIntervalUnit, TodoReminderIntervalUnits.minutes);
  });

  testWidgets('opens todo reminder editor from the row action', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'reminder-chip-paper',
            type: PaperTypes.todo,
            title: 'Reminder chip',
            items: [
              PaperItem(
                id: 'reminder-chip-item',
                text: 'Tune reminders',
                reminderIntervalValue: 2,
                reminderIntervalUnit: TodoReminderIntervalUnits.hours,
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

    expect(find.byType(InputChip), findsNothing);
    await tester.tap(find.byTooltip('Set reminder interval'));
    await tester.pumpAndSettle();

    await tester.enterText(_reminderIntervalValueField(), '15');
    await _selectReminderIntervalUnit(
      tester,
      TodoReminderIntervalUnits.minutes,
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.reminderIntervalValue, 15);
    expect(item.reminderIntervalUnit, TodoReminderIntervalUnits.minutes);
    expect(find.text('Every 15 min'), findsNothing);
  });

  testWidgets('Windows paper reminder interval uses the native paper dialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const channel = MethodChannel('repapertodo/paper_window');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pickReminderInterval') {
        return <String, Object?>{
          'value': 15,
          'unit': TodoReminderIntervalUnits.minutes,
        };
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final item = PaperItem(
      id: 'native-reminder-item',
      text: 'Use the native interval picker',
      reminderIntervalValue: 2,
      reminderIntervalUnit: TodoReminderIntervalUnits.hours,
    );
    final paper = PaperData(
      id: 'native-reminder-paper',
      title: 'Native reminder',
      width: 360,
      height: 420,
      items: [item],
    );
    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(
      const ValueKey('native-reminder-paper-native-reminder-item-row'),
    );
    await tester.tapAt(tester.getCenter(row), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change reminder interval'));
    await tester.pumpAndSettle();

    final nativeCall = calls.singleWhere(
      (call) => call.method == 'pickReminderInterval',
    );
    final arguments = nativeCall.arguments! as Map<Object?, Object?>;
    expect(arguments['value'], 2);
    expect(arguments['unit'], TodoReminderIntervalUnits.hours);
    expect(arguments['message'], isNotEmpty);
    expect(arguments['globalLabel'], 'Global');
    expect(arguments['inputBackgroundColor'], 0xFFF9F1E1);
    expect(arguments['secondaryButtonColor'], 0xFFEEE6D3);
    expect(arguments['fontFamily'], isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(item.reminderIntervalValue, 15);
    expect(item.reminderIntervalUnit, TodoReminderIntervalUnits.minutes);
  });

  testWidgets('todo reminder dialog keyboard shortcuts match PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        todoReminderIntervalValue: 3,
        todoReminderIntervalUnit: TodoReminderIntervalUnits.hours,
        papers: [
          PaperData(
            id: 'reminder-shortcut-paper',
            type: PaperTypes.todo,
            title: 'Reminder shortcuts',
            items: [
              PaperItem(id: 'reminder-shortcut-item', text: 'Tune reminders'),
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

    await tester.tap(find.byTooltip('Set reminder interval'));
    await tester.pumpAndSettle();
    await tester.enterText(_reminderIntervalValueField(), '9');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.reminderIntervalValue, isNull);
    expect(item.reminderIntervalUnit, isNull);
    expect(find.text('Every 9 hr'), findsNothing);

    await tester.tap(find.byTooltip('Set reminder interval'));
    await tester.pumpAndSettle();
    await tester.enterText(_reminderIntervalValueField(), '7');
    await _selectReminderIntervalUnit(
      tester,
      TodoReminderIntervalUnits.minutes,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(item.reminderIntervalValue, 7);
    expect(item.reminderIntervalUnit, TodoReminderIntervalUnits.minutes);
    expect(find.text('Every 7 min'), findsNothing);
  });

  testWidgets('renders relative todo due dates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final dueAt = now.add(const Duration(minutes: 5));
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
                dueAtLocal: dueAt.toIso8601String(),
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

    expect(find.text('in 5m'), findsOneWidget);
    expect(find.text(_formatAbsoluteDueLabelForTest(dueAt)), findsOneWidget);
  });

  testWidgets('refreshes relative due labels on the reminder timer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dueAt = DateTime.now().add(
      const Duration(minutes: 20, seconds: 5),
    );
    final item = PaperItem(
      id: 'relative-refresh-item',
      text: 'Watch relative time',
      dueAtLocal: dueAt.toIso8601String(),
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        showTodoDueRelativeTime: true,
        useTodoReminderInterval: false,
        papers: [
          PaperData(
            id: 'relative-refresh-paper',
            type: PaperTypes.todo,
            title: 'Relative refresh',
            items: [
              item,
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

    expect(find.text('in 21m'), findsOneWidget);

    item.dueAtLocal = DateTime.now()
        .add(const Duration(minutes: 19, seconds: 5))
        .toIso8601String();
    await tester.pump(const Duration(seconds: 31));

    expect(find.text('in 21m'), findsNothing);
    expect(find.text('in 20m'), findsOneWidget);
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

    expect(find.text('in 2h5m'), findsOneWidget);
    expect(find.text('1h3m overdue'), findsOneWidget);
    expect(find.text('in 1m'), findsOneWidget);
  });

  testWidgets(
      'Chinese relative due badge uses PaperTodo units and natural width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 340));
    tester.binding.platformDispatcher.localeTestValue =
        const Locale('zh', 'CN');
    tester.binding.platformDispatcher.localesTestValue = [
      const Locale('zh', 'CN'),
    ];
    addTearDown(() {
      tester.binding.platformDispatcher.clearLocaleTestValue();
      tester.binding.platformDispatcher.clearLocalesTestValue();
      tester.binding.setSurfaceSize(null);
    });

    final now = DateTime.now();
    final paper = PaperData(
      id: 'localized-relative-paper',
      type: PaperTypes.todo,
      title: 'Localized relative due',
      width: 440,
      height: 340,
      items: [
        PaperItem(
          id: 'localized-relative-item',
          text: 'Due tomorrow',
          dueAtLocal: now
              .add(const Duration(hours: 2, minutes: 4, seconds: 10))
              .toIso8601String(),
        ),
      ],
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(
            showTodoDueRelativeTime: true,
            papers: [paper],
          ),
          platform: _RecordingPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pump();

    expect(find.text('2\u5c0f\u65f65\u5206\u540e'), findsOneWidget);
    final surface = find.byKey(
      const ValueKey(
        'localized-relative-paper-localized-relative-item-due-relative-surface',
      ),
    );
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface).width, lessThan(90));

    final absoluteSurface = find.byKey(
      const ValueKey(
        'localized-relative-paper-localized-relative-item-due-absolute-surface',
      ),
    );
    expect(absoluteSurface, findsOneWidget);
    expect(
      tester.widget<Material>(absoluteSurface).color,
      const Color(0x12785C30),
    );

    final absoluteButton = find.byKey(
      const ValueKey(
        'localized-relative-paper-localized-relative-item-due-absolute',
      ),
    );
    final absoluteOpacity = find.byKey(
      const ValueKey(
        'localized-relative-paper-localized-relative-item-due-absolute-opacity',
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(absoluteButton));
    await tester.pump();
    expect(tester.widget<Opacity>(absoluteOpacity).opacity, 0.72);
    await gesture.cancel();
    await tester.pump();
    expect(tester.widget<Opacity>(absoluteOpacity).opacity, 1);
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

    expect(find.text('6/30 09:15'), findsOneWidget);

    await tester.tap(find.byTooltip('Set time'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('todo-due-dialog-surface'))),
      const Size(354, 242),
    );
    expect(find.text('Set time'), findsOneWidget);
    expect(find.text('6/30/2026'), findsOneWidget);
    final cancelButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancel'),
    );
    final cancelShape = cancelButton.style?.shape?.resolve({});
    expect(cancelShape, isA<RoundedRectangleBorder>());
    expect(
      (cancelShape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.zero,
    );
    expect(find.byKey(const ValueKey('todo-due-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-due-year')), findsNothing);
    expect(find.byKey(const ValueKey('todo-due-month')), findsNothing);
    expect(find.byKey(const ValueKey('todo-due-day')), findsNothing);
    final dateCenter = tester.getCenter(
      find.byKey(const ValueKey('todo-due-date')),
    );
    final hourCenter = tester.getCenter(
      find.byKey(const ValueKey('todo-due-hour')),
    );
    final minuteCenter = tester.getCenter(
      find.byKey(const ValueKey('todo-due-minute')),
    );
    expect(hourCenter.dy, closeTo(dateCenter.dy, 0.01));
    expect(minuteCenter.dy, closeTo(dateCenter.dy, 0.01));

    tester
        .widget<DropdownButton<int>>(
          find.byKey(const ValueKey('todo-due-hour')),
        )
        .onChanged
        ?.call(10);
    await tester.pump();

    tester
        .widget<DropdownButton<int>>(
          find.byKey(const ValueKey('todo-due-minute')),
        )
        .onChanged
        ?.call(30);
    await tester.pump();

    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.dueAtLocal, '2026-06-30T10:30:00');
    expect(find.text('6/30 10:30'), findsOneWidget);
  });

  testWidgets('todo due year labels match PaperTodo date formats',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final entry in <(String, String)>[
      (TodoDueYearDisplayModes.none, '7/18 18:30'),
      (TodoDueYearDisplayModes.short, '99年7/18 18:30'),
      (TodoDueYearDisplayModes.full, '2099年7/18 18:30'),
    ]) {
      final paper = PaperData(
        id: 'due-year-${entry.$1}',
        type: PaperTypes.todo,
        title: 'Due year ${entry.$1}',
        items: [
          PaperItem(
            id: 'due-year-item-${entry.$1}',
            text: 'Date format',
            dueAtLocal: '2099-07-18T18:30:00',
          ),
        ],
      );
      await tester.pumpWidget(
        RePaperTodoApp(
          key: ValueKey('due-year-app-${entry.$1}'),
          controller: RePaperTodoController(
            initialState: AppState(
              todoDueYearDisplayMode: entry.$1,
              papers: [paper],
            ),
            platform: _RecordingPlatformServices(),
          ),
          store: _MemoryStateStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(entry.$2), findsOneWidget);
    }
  });

  testWidgets('opens todo due editor from due chip like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'due-chip-paper',
            type: PaperTypes.todo,
            title: 'Due chip paper',
            items: [
              PaperItem(
                id: 'due-chip-item',
                text: 'Timed task',
                dueAtLocal: '2026-06-30T09:15:42',
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

    await tester.tap(
      find.byKey(const ValueKey('due-chip-paper-due-chip-item-due-absolute')),
    );
    await tester.pumpAndSettle();

    tester
        .widget<DropdownButton<int>>(
          find.byKey(const ValueKey('todo-due-minute')),
        )
        .onChanged
        ?.call(45);
    await tester.pump();

    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.dueAtLocal, '2026-06-30T09:45:00');
    expect(find.text('6/30 09:45'), findsOneWidget);
  });

  testWidgets('todo due dialog keyboard shortcuts match PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'due-shortcut-paper',
            type: PaperTypes.todo,
            title: 'Due shortcuts',
            items: [
              PaperItem(
                id: 'due-shortcut-item',
                text: 'Timed task',
                dueAtLocal: '2026-06-30T09:15:00',
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

    await tester.tap(
      find.byKey(
        const ValueKey('due-shortcut-paper-due-shortcut-item-due-absolute'),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButton<int>>(
          find.byKey(const ValueKey('todo-due-minute')),
        )
        .onChanged
        ?.call(45);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.dueAtLocal, '2026-06-30T09:15:00');
    expect(find.text('6/30 09:15'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('due-shortcut-paper-due-shortcut-item-due-absolute'),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButton<int>>(
          find.byKey(const ValueKey('todo-due-hour')),
        )
        .onChanged
        ?.call(10);
    tester
        .widget<DropdownButton<int>>(
          find.byKey(const ValueKey('todo-due-minute')),
        )
        .onChanged
        ?.call(30);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(item.dueAtLocal, '2026-06-30T10:30:00');
    expect(find.text('6/30 10:30'), findsOneWidget);
  });

  testWidgets('formats absolute todo due times like PaperTodo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final later = today.add(const Duration(days: 2));
    final laterMonth = later.month.toString();
    final laterDay = later.day.toString();
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

    expect(find.text('10:05'), findsOneWidget);
    expect(find.text('Tomorrow 11:10'), findsOneWidget);
    expect(find.text('$laterMonth/$laterDay 12:15'), findsOneWidget);
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
    expect(dueButton.iconSize, 27);
    expect(dueButton.constraints?.minWidth, 36);
    expect(dueButton.constraints?.minHeight, 36);

    final itemFinder = find.byKey(const ValueKey('large-todo-large-item-text'));
    final todoText = tester.widget<EditableText>(
      find.descendant(of: itemFinder, matching: find.byType(EditableText)),
    );
    expect(todoText.style.fontSize, closeTo(15.5, 0.001));

    final textField = tester.widget<TextField>(
      find.descendant(of: itemFinder, matching: find.byType(TextField)),
    );
    expect(
      textField.decoration?.contentPadding,
      const EdgeInsets.fromLTRB(4, 5.5, 0, 3.5),
    );
    expect(todoText.style.letterSpacing, -0.0625);
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

  testWidgets('ctrl mouse wheel adjusts note text zoom like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'wheel-zoom-note',
            type: PaperTypes.note,
            title: 'Wheel zoom note',
            content: 'Zoom with the mouse wheel.',
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

    final paper = controller.state.papers.single;
    final position = tester.getCenter(find.byType(PaperPreview));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(paper.textZoom, 1.1);
    expect(platform.paperWindows.updatedTitles, contains('Wheel zoom note'));
  });

  testWidgets('clicking note zoom overlay resets text zoom like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'status-reset-zoom-note',
            type: PaperTypes.note,
            title: 'Status reset zoom',
            content: 'Reset zoom from the status indicator.',
            textZoom: 1.3,
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

    expect(find.text('130%'), findsNWidgets(2));
    expect(
      tester.getSize(find.byKey(const ValueKey('note-status-zoom'))).width,
      38,
    );
    expect(
      find.byKey(const ValueKey('note-text-zoom-overlay')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('note-text-zoom-overlay')));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.textZoom, 1.0);
    expect(find.text('100%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('note-text-zoom-overlay')),
      findsNothing,
    );
    expect(platform.paperWindows.updatedTitles, contains('Status reset zoom'));
  });

  testWidgets('ctrl mouse wheel note zoom respects PaperTodo bounds',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'wheel-zoom-bounds-note',
            type: PaperTypes.note,
            title: 'Wheel zoom bounds',
            content: 'Keep wheel zoom inside the supported range.',
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

    final paper = controller.state.papers.single;
    final position = tester.getCenter(find.byType(PaperPreview));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pump();
    expect(paper.textZoom, 1.0);
    expect(platform.paperWindows.updatedTitles, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    for (var i = 0; i < 8; i += 1) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, -120),
        ),
      );
    }
    await tester.pump();
    expect(paper.textZoom, 1.5);

    for (var i = 0; i < 12; i += 1) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 120),
        ),
      );
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(paper.textZoom, 0.5);
    expect(
      platform.paperWindows.updatedTitles,
      everyElement(equals('Wheel zoom bounds')),
    );
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
    expect(find.text('Column 1'), findsNothing);
    expect(find.text('Column 2'), findsNothing);
    final firstColumnBox = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('columns-paper-columns-item-text')),
    );
    final secondColumnBox = tester.renderObject<RenderBox>(
      find.byKey(
        const ValueKey('columns-paper-columns-item-column-2'),
      ),
    );
    expect(
      (firstColumnBox.localToGlobal(Offset.zero).dy -
              secondColumnBox.localToGlobal(Offset.zero).dy)
          .abs(),
      lessThan(2),
    );

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
    expect(controller.state.papers.single.items.last.todoColumnCount, 1);
    expect(controller.state.papers.single.items.last.todoExtraColumns, isEmpty);
    expect(controller.state.papers.single.items.last.todoColumnWidths, [1]);

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

  testWidgets('drags todo column splitters like PaperTodo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'column-width-paper',
            type: PaperTypes.todo,
            title: 'Column width paper',
            width: 900,
            items: [
              PaperItem(
                id: 'width-item',
                text: 'Title',
                todoColumnCount: 2,
                todoExtraColumns: ['Status'],
                todoColumnWidths: [1, 1],
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

    final splitter = find.byKey(
      const ValueKey('column-width-paper-width-item-column-splitter-1'),
    );
    expect(splitter, findsOneWidget);
    final separatorPaint = find.descendant(
      of: splitter,
      matching: find.byType(CustomPaint),
    );
    expect(separatorPaint, findsOneWidget);
    final dynamic separatorPainter =
        tester.widget<CustomPaint>(separatorPaint).painter;
    expect(
      separatorPainter.runtimeType.toString(),
      '_TodoColumnSeparatorPainter',
    );
    expect(
      separatorPainter.color,
      PaperTodoThemeColors.of(tester.element(splitter))
          .paperBorder
          .withValues(alpha: 0.9),
    );

    await tester.drag(splitter, const Offset(120, 0));
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.todoColumnWidths[0], greaterThan(1));
    expect(item.todoColumnWidths[1], lessThan(1));
    expect(item.todoColumnWidths[1], greaterThanOrEqualTo(0.2));

    await tester.drag(splitter, const Offset(-2000, 0));
    await tester.pumpAndSettle();

    expect(item.todoColumnWidths[0], 0.2);
    expect(item.todoColumnWidths[1], greaterThan(1));
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
    expect(items.map((item) => item.todoColumnCount), [2, 1, 1]);
    expect(items.map((item) => item.todoColumnWidths), [
      [2, 1],
      [1],
      [1],
    ]);
    final lastPastedField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey('paste-paper-${items.last.id}-text')),
        matching: find.byType(EditableText),
      ),
    );
    expect(lastPastedField.focusNode.hasFocus, true);
    expect(
      lastPastedField.controller.selection,
      TextSelection.collapsed(offset: items.last.text.length),
    );

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

  testWidgets('new and pasted todo rows use PaperTodo entrance timing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        enableAnimations: true,
        papers: [
          PaperData(
            id: 'entrance-paper',
            type: PaperTypes.todo,
            items: [PaperItem(id: 'entrance-item', text: 'Start')],
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

    await tester.tap(find.widgetWithText(TextButton, 'Add item'));
    await tester.pump();
    final addedItem = controller.state.papers.single.items.last;
    final addedEntrance = find.byKey(
      ValueKey('entrance-paper-${addedItem.id}-entrance'),
    );
    expect(addedEntrance, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 125));
    expect(
      tester
          .widgetList<Opacity>(
            find.descendant(
              of: addedEntrance,
              matching: find.byType(Opacity),
            ),
          )
          .any((opacity) => opacity.opacity > 0 && opacity.opacity < 1),
      true,
    );
    await tester.pumpAndSettle();
    expect(addedEntrance, findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('entrance-paper-entrance-item-text')),
        matching: find.byType(EditableText),
      ),
      'First\nSecond\nThird',
    );
    await tester.pump();

    final pastedItems = controller.state.papers.single.items.take(3).toList();
    final firstPastedEntrance = find.byKey(
      ValueKey('entrance-paper-${pastedItems[1].id}-entrance'),
    );
    final secondPastedEntrance = find.byKey(
      ValueKey('entrance-paper-${pastedItems[2].id}-entrance'),
    );
    expect(firstPastedEntrance, findsOneWidget);
    expect(secondPastedEntrance, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 80));
    double entranceOpacity(Finder entrance) => tester
        .widgetList<Opacity>(
          find.descendant(of: entrance, matching: find.byType(Opacity)),
        )
        .map((opacity) => opacity.opacity)
        .reduce(math.min);
    expect(
      entranceOpacity(firstPastedEntrance),
      greaterThan(entranceOpacity(secondPastedEntrance)),
    );

    await tester.pumpAndSettle();
    expect(firstPastedEntrance, findsNothing);
    expect(secondPastedEntrance, findsNothing);
  });

  testWidgets('splits pasted todo lists from extra columns like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'extra-paste-paper',
            type: PaperTypes.todo,
            title: 'Extra paste paper',
            items: [
              PaperItem(
                id: 'extra-paste-item',
                text: 'Title',
                todoColumnCount: 2,
                todoExtraColumns: ['Old status'],
                todoColumnWidths: [2, 1],
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

    final extraField = find.descendant(
      of: find.byKey(
        const ValueKey('extra-paste-paper-extra-paste-item-column-2'),
      ),
      matching: find.byType(EditableText),
    );

    await tester.tap(extraField);
    await tester.enterText(
      extraField,
      '- [ ] Reading\n2) Draft notes\n+ Publish',
    );
    await tester.pumpAndSettle();

    final items = controller.state.papers.single.items;
    expect(items.map((item) => item.text), [
      'Title',
      'Draft notes',
      'Publish',
    ]);
    expect(items.first.todoExtraColumns, ['Reading']);
    expect(items.map((item) => item.todoColumnCount), [2, 1, 1]);
    expect(items.map((item) => item.todoColumnWidths), [
      [2, 1],
      [1],
      [1],
    ]);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    final restored = controller.state.papers.single.items.single;
    expect(restored.text, 'Title');
    expect(restored.todoExtraColumns, ['Old status']);
  });

  testWidgets('replaces todo paste selection like PaperTodo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'selection-paste-paper',
            type: PaperTypes.todo,
            title: 'Selection paste paper',
            items: [
              PaperItem(id: 'selection-paste-item', text: 'Read  today'),
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

    final field = find.descendant(
      of: find.byKey(
        const ValueKey('selection-paste-paper-selection-paste-item-text'),
      ),
      matching: find.byType(EditableText),
    );
    await tester.tap(field);
    final editable = tester.widget<EditableText>(field);
    editable.controller.selection = const TextSelection.collapsed(offset: 5);

    await tester.enterText(field, 'Read - [ ] paper\n2) notes today');
    await tester.pumpAndSettle();

    final items = controller.state.papers.single.items;
    expect(items.map((item) => item.text), [
      'Read paper today',
      'notes',
    ]);
    final lastPastedField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(
          ValueKey('selection-paste-paper-${items.last.id}-text'),
        ),
        matching: find.byType(EditableText),
      ),
    );
    expect(lastPastedField.focusNode.hasFocus, true);
  });

  testWidgets('limits todo text columns to PaperTodo max length',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'todo-length-paper',
            type: PaperTypes.todo,
            title: 'Todo length paper',
            items: [
              PaperItem(
                id: 'todo-length-item',
                text: '',
                todoColumnCount: 2,
                todoExtraColumns: [''],
                todoColumnWidths: [1, 1],
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

    final mainField = find.descendant(
      of: find.byKey(const ValueKey('todo-length-paper-todo-length-item-text')),
      matching: find.byType(EditableText),
    );
    final extraField = find.descendant(
      of: find.byKey(
        const ValueKey('todo-length-paper-todo-length-item-column-2'),
      ),
      matching: find.byType(EditableText),
    );
    final oversizedText =
        List.filled(TodoPasteItems.maxLineLength + 25, 'x').join();
    final oversizedExtra =
        List.filled(TodoPasteItems.maxLineLength + 10, 'y').join();

    await tester.enterText(mainField, oversizedText);
    await tester.enterText(extraField, oversizedExtra);
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.text, hasLength(TodoPasteItems.maxLineLength));
    expect(
        item.todoExtraColumns.single, hasLength(TodoPasteItems.maxLineLength));
    expect(tester.widget<EditableText>(mainField).controller.text,
        hasLength(TodoPasteItems.maxLineLength));
    expect(tester.widget<EditableText>(extraField).controller.text,
        hasLength(TodoPasteItems.maxLineLength));
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
    expect(items[1].todoColumnCount, 1);
    expect(items[1].todoExtraColumns, isEmpty);
    expect(items[1].todoColumnWidths, [1]);
    expect(items.map((item) => item.order), [0, 1, 2]);
  });

  testWidgets('commits todo text edits to undo on focus loss like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'text-undo-paper',
            type: PaperTypes.todo,
            title: 'Text undo paper',
            items: [
              PaperItem(id: 'first-item', text: 'First item'),
              PaperItem(id: 'second-item', text: 'Second item', order: 1),
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

    final firstField = find.descendant(
      of: find.byKey(const ValueKey('text-undo-paper-first-item-text')),
      matching: find.byType(EditableText),
    );
    final secondField = find.descendant(
      of: find.byKey(const ValueKey('text-undo-paper-second-item-text')),
      matching: find.byType(EditableText),
    );

    await tester.tap(firstField);
    await tester.enterText(firstField, 'Edited first item');
    await tester.pump();

    expect(
        controller.state.papers.single.items.first.text, 'Edited first item');

    await tester.tap(secondField);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.first.text, 'First item');

    await tester.tap(find.byTooltip('Redo todo change'));
    await tester.pumpAndSettle();

    expect(
        controller.state.papers.single.items.first.text, 'Edited first item');
  });

  testWidgets('todo text redo stays in the focused editor like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'text-redo-paper',
            type: PaperTypes.todo,
            title: 'Text redo paper',
            items: [
              PaperItem(id: 'redo-item', text: 'Read'),
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

    final field = find.descendant(
      of: find.byKey(const ValueKey('text-redo-paper-redo-item-text')),
      matching: find.byType(EditableText),
    );

    await tester.tap(field);
    await tester.enterText(field, 'Read draft');
    await tester.pump();

    expect(controller.state.papers.single.items.single.text, 'Read draft');

    await _pressControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.single.text, 'Read');

    await _pressControlShortcut(tester, LogicalKeyboardKey.keyY);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.single.text, 'Read draft');
  });

  testWidgets('uncommitted todo text does not block structural redo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'redo-structure-paper',
            type: PaperTypes.todo,
            title: 'Redo structure paper',
            items: [
              PaperItem(id: 'redo-structure-item', text: 'Read'),
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

    final field = find.descendant(
      of: find.byKey(
        const ValueKey('redo-structure-paper-redo-structure-item-text'),
      ),
      matching: find.byType(EditableText),
    );

    await tester.tap(field);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(2));

    await _pressControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(1));

    await tester.tap(field);
    await tester.enterText(field, 'Read draft');
    await tester.pump();

    expect(controller.state.papers.single.items.single.text, 'Read draft');

    await _pressControlShortcut(tester, LogicalKeyboardKey.keyY);
    await tester.pumpAndSettle();

    final items = controller.state.papers.single.items;
    expect(items, hasLength(2));
    expect(items.first.text, 'Read');
    expect(items.last.text, '');
  });

  testWidgets(
      'todo extra column undo stays in the focused editor like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'extra-text-redo-paper',
            type: PaperTypes.todo,
            title: 'Extra text redo paper',
            items: [
              PaperItem(
                id: 'extra-redo-item',
                text: 'Read',
                todoColumnCount: 2,
                todoExtraColumns: ['Plan'],
                todoColumnWidths: [1, 1],
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

    final mainField = find.descendant(
      of: find.byKey(
        const ValueKey('extra-text-redo-paper-extra-redo-item-text'),
      ),
      matching: find.byType(EditableText),
    );
    final extraField = find.descendant(
      of: find.byKey(
        const ValueKey('extra-text-redo-paper-extra-redo-item-column-2'),
      ),
      matching: find.byType(EditableText),
    );

    await tester.tap(mainField);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(2));

    await tester.tap(extraField);
    await tester.enterText(extraField, 'Plan review');
    await tester.pump();

    expect(
      controller.state.papers.single.items.first.todoExtraColumns.single,
      'Plan review',
    );

    await _pressControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(2));
    expect(
      controller.state.papers.single.items.first.todoExtraColumns.single,
      'Plan',
    );

    await _pressControlShortcut(tester, LogicalKeyboardKey.keyY);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(2));
    expect(
      controller.state.papers.single.items.first.todoExtraColumns.single,
      'Plan review',
    );
  });

  testWidgets('todo snapshot restore clears stale text redo like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'text-restore-paper',
            type: PaperTypes.todo,
            title: 'Text restore paper',
            items: [
              PaperItem(id: 'restore-item', text: 'Read'),
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

    final field = find.descendant(
      of: find.byKey(const ValueKey('text-restore-paper-restore-item-text')),
      matching: find.byType(EditableText),
    );

    await tester.tap(field);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(2));

    await tester.tap(field);
    await tester.enterText(field, 'Read draft');
    await tester.pump();

    await _pressControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.first.text, 'Read');
    expect(controller.state.papers.single.items, hasLength(2));

    await _pressControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(1));
    expect(controller.state.papers.single.items.single.text, 'Read');

    await _pressControlShortcut(tester, LogicalKeyboardKey.keyY);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items, hasLength(2));
    expect(controller.state.papers.single.items.first.text, 'Read');
  });

  testWidgets('commits focused todo text before structural undo snapshots',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'text-before-insert-paper',
            type: PaperTypes.todo,
            title: 'Text before insert',
            items: [
              PaperItem(id: 'first-item', text: 'First item'),
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

    final firstField = find.descendant(
      of: find.byKey(
        const ValueKey('text-before-insert-paper-first-item-text'),
      ),
      matching: find.byType(EditableText),
    );

    await tester.tap(firstField);
    await tester.enterText(firstField, 'Edited first item');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.text), [
      'Edited first item',
      '',
    ]);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.text), [
      'Edited first item',
    ]);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.text), [
      'First item',
    ]);
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
    final beforeField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('backspace-paper-before-item-text')),
        matching: find.byType(EditableText),
      ),
    );
    expect(beforeField.focusNode.hasFocus, true);
    expect(
      beforeField.controller.selection,
      const TextSelection.collapsed(offset: 11),
    );
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

  testWidgets('focuses next todo start after deleting first blank row',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'backspace-first-paper',
            type: PaperTypes.todo,
            title: 'Backspace first paper',
            items: [
              PaperItem(id: 'blank-item', text: ' '),
              PaperItem(id: 'after-item', text: 'After item', order: 1),
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

    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey('backspace-first-paper-blank-item-text'),
        ),
        matching: find.byType(EditableText),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'after-item',
    ]);
    final afterField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(
          const ValueKey('backspace-first-paper-after-item-text'),
        ),
        matching: find.byType(EditableText),
      ),
    );
    expect(afterField.focusNode.hasFocus, true);
    expect(
      afterField.controller.selection,
      const TextSelection.collapsed(offset: 0),
    );
  });

  testWidgets('clears completed todo items like PaperTodo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'clear-done-paper',
            type: PaperTypes.todo,
            title: 'Clear done paper',
            items: [
              PaperItem(id: 'done-one', text: 'Done one', done: true),
              PaperItem(id: 'keep-one', text: 'Keep one', order: 1),
              PaperItem(id: 'done-two', text: 'Done two', done: true, order: 2),
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

    await tester.tap(find.byTooltip('Clear completed items').first);
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.single.items.map((item) => item.id),
      ['keep-one'],
    );
    expect(
      controller.state.sync.deletedTodoItemTombstones['clear-done-paper']
          ?.containsKey('done-one'),
      true,
    );
    expect(
      controller.state.sync.deletedTodoItemTombstones['clear-done-paper']
          ?.containsKey('done-two'),
      true,
    );

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.single.items.map((item) => item.id),
      ['done-one', 'keep-one', 'done-two'],
    );
    expect(
      controller.state.sync.deletedTodoItemTombstones['clear-done-paper']
          ?.containsKey('done-one'),
      isNot(true),
    );
    expect(
      controller.state.sync.deletedTodoItemTombstones['clear-done-paper']
          ?.containsKey('done-two'),
      isNot(true),
    );
  });

  testWidgets('clearing all completed todo items leaves a fallback row',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'clear-all-done-paper',
            type: PaperTypes.todo,
            title: 'Clear all done paper',
            items: [
              PaperItem(id: 'done-one', text: 'Done one', done: true),
              PaperItem(id: 'done-two', text: 'Done two', done: true, order: 1),
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

    await tester.tap(find.byTooltip('Clear completed items').first);
    await tester.pumpAndSettle();

    final fallback = controller.state.papers.single.items.single;
    expect(fallback.id, isNot(anyOf('done-one', 'done-two')));
    expect(fallback.text, '');
    expect(fallback.done, false);
    expect(fallback.order, 0);
    expect(
      controller.state.sync.deletedTodoItemTombstones['clear-all-done-paper']
          ?.containsKey('done-one'),
      true,
    );
    expect(
      controller.state.sync.deletedTodoItemTombstones['clear-all-done-paper']
          ?.containsKey('done-two'),
      true,
    );
  });

  testWidgets('todo deletion animations match PaperTodo slide timing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        enableAnimations: true,
        papers: [
          PaperData(
            id: 'animated-delete-paper',
            type: PaperTypes.todo,
            items: [
              PaperItem(id: 'animated-delete-item', text: 'Slide away'),
              PaperItem(id: 'animated-keep-item', text: 'Stay', order: 1),
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

    await tester.tap(find.byTooltip('Delete this item').first);
    await tester.pump();

    final departure = find.byKey(
      const ValueKey(
        'animated-delete-paper-animated-delete-item-departure',
      ),
    );
    expect(
      controller.state.papers.single.items.map((item) => item.id),
      ['animated-keep-item'],
    );
    expect(departure, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(departure, findsOneWidget);
    expect(
      tester
          .widgetList<Opacity>(
            find.descendant(of: departure, matching: find.byType(Opacity)),
          )
          .any((opacity) => opacity.opacity > 0 && opacity.opacity < 1),
      true,
    );

    await tester.pump(const Duration(milliseconds: 110));
    expect(departure, findsNothing);
  });

  testWidgets('clearing completed items keeps PaperTodo staggered departures',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        enableAnimations: true,
        papers: [
          PaperData(
            id: 'animated-clear-paper',
            type: PaperTypes.todo,
            items: [
              PaperItem(id: 'animated-done-one', text: 'Done one', done: true),
              PaperItem(id: 'animated-keep', text: 'Keep', order: 1),
              PaperItem(
                id: 'animated-done-two',
                text: 'Done two',
                done: true,
                order: 2,
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

    await tester.tap(find.byTooltip('Clear completed items').first);
    await tester.pump();

    final firstDeparture = find.byKey(
      const ValueKey('animated-clear-paper-animated-done-one-departure'),
    );
    final secondDeparture = find.byKey(
      const ValueKey('animated-clear-paper-animated-done-two-departure'),
    );
    expect(
      controller.state.papers.single.items.map((item) => item.id),
      ['animated-keep'],
    );
    expect(firstDeparture, findsOneWidget);
    expect(secondDeparture, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 150));
    expect(firstDeparture, findsOneWidget);
    expect(secondDeparture, findsOneWidget);

    await tester.pumpAndSettle();
    expect(firstDeparture, findsNothing);
    expect(secondDeparture, findsNothing);
  });

  testWidgets('deleting only todo item leaves fallback row like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'delete-only-paper',
            type: PaperTypes.todo,
            title: 'Delete only paper',
            items: [
              PaperItem(id: 'only-item', text: 'Only item'),
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

    await tester.tap(find.byTooltip('Delete this item'));
    await tester.pumpAndSettle();

    final deletionSnackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(deletionSnackBar.duration, const Duration(seconds: 10));

    final fallback = controller.state.papers.single.items.single;
    expect(fallback.id, isNot('only-item'));
    expect(fallback.text, '');
    expect(fallback.order, 0);
    expect(
      controller.state.sync.deletedTodoItemTombstones['delete-only-paper']
          ?.containsKey('only-item'),
      true,
    );
    final fallbackField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey('delete-only-paper-${fallback.id}-text')),
        matching: find.byType(EditableText),
      ),
    );
    expect(fallbackField.focusNode.hasFocus, true);

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

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'only-item',
    ]);
    expect(
      controller.state.sync.deletedTodoItemTombstones['delete-only-paper']
          ?.containsKey('only-item'),
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
    final thirdRow = find.byKey(const ValueKey('drag-paper-third-item-row'));
    expect(thirdRow, findsOneWidget);
    await tester.timedDragFrom(
      tester.getCenter(dragHandle),
      tester.getCenter(thirdRow) - tester.getCenter(dragHandle),
      const Duration(milliseconds: 300),
    );
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

  testWidgets('drags todo items before the target row like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'drag-before-paper',
            type: PaperTypes.todo,
            title: 'Drag before paper',
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

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
      ),
    );

    final dragHandle =
        find.byKey(const ValueKey('drag-before-paper-third-item-drag-handle'));
    final secondRow =
        find.byKey(const ValueKey('drag-before-paper-second-item-row'));
    expect(dragHandle, findsOneWidget);
    expect(secondRow, findsOneWidget);

    final secondRowTop = tester.getTopLeft(secondRow);
    await tester.timedDragFrom(
      tester.getCenter(dragHandle),
      secondRowTop + const Offset(80, 4) - tester.getCenter(dragHandle),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'first-item',
      'third-item',
      'second-item',
    ]);
    expect(controller.state.papers.single.items.map((item) => item.order), [
      0,
      1,
      2,
    ]);
  });

  testWidgets('drags todo items to the bottom delete area like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'drag-delete-paper',
            type: PaperTypes.todo,
            title: 'Drag delete paper',
            items: [
              PaperItem(id: 'first-item', text: 'First'),
              PaperItem(id: 'delete-item', text: 'Drag me away', order: 1),
              PaperItem(id: 'third-item', text: 'Third', order: 2),
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

    final dragHandle =
        find.byKey(const ValueKey('drag-delete-paper-delete-item-drag-handle'));
    expect(dragHandle, findsOneWidget);

    final deleteTarget = find.byKey(
      const ValueKey('drag-delete-paper-todo-delete-drop-target'),
    );
    expect(deleteTarget, findsOneWidget);
    expect(tester.getSize(deleteTarget).height, greaterThan(0));

    final dragGesture = await tester.startGesture(
      tester.getCenter(dragHandle),
    );
    await dragGesture.moveBy(const Offset(24, 0));
    await tester.pump();

    final trashArea = find.byKey(
      const ValueKey('drag-delete-paper-todo-trash-area'),
    );
    expect(trashArea, findsOneWidget);
    final trashColors = PaperTodoThemeColors.of(tester.element(trashArea));
    BoxDecoration trashDecoration() =>
        tester.widget<Container>(trashArea).decoration! as BoxDecoration;
    Finder trashOpacity() =>
        find.descendant(of: trashArea, matching: find.byType(Opacity));
    expect(
      trashDecoration().color,
      trashColors.danger.withValues(alpha: 12 / 255),
    );
    expect(
      (trashDecoration().border! as Border).top.color,
      trashColors.danger.withValues(alpha: 50 / 255),
    );
    expect((trashDecoration().border! as Border).top.width, 1);
    expect(tester.widget<Opacity>(trashOpacity()).opacity, 0.65);
    final trashGlyph = tester.widget<Text>(
      find.descendant(
        of: trashArea,
        matching: find.text('\u{1F5D1}'),
      ),
    );
    expect(trashGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(trashGlyph.style?.fontSize, 13);
    expect(trashGlyph.style?.color, trashColors.danger);

    await dragGesture.moveTo(tester.getCenter(deleteTarget));
    await tester.pump();
    expect(trashDecoration().color,
        trashColors.danger.withValues(alpha: 26 / 255));
    expect(
      (trashDecoration().border! as Border).top.color,
      trashColors.danger,
    );
    expect((trashDecoration().border! as Border).top.width, 1.5);
    expect(tester.widget<Opacity>(trashOpacity()).opacity, 1);

    await dragGesture.up();
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'first-item',
      'third-item',
    ]);
    expect(
      controller.state.sync.deletedTodoItemTombstones['drag-delete-paper']
          ?.containsKey('delete-item'),
      true,
    );

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

    expect(controller.state.papers.single.items.map((item) => item.id), [
      'first-item',
      'delete-item',
      'third-item',
    ]);
    expect(
      controller.state.sync.deletedTodoItemTombstones['drag-delete-paper']
          ?.containsKey('delete-item'),
      isNot(true),
    );
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
    final store = _MemoryStateStore();

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    Future<void> waitForSurfaceMode({
      required bool pinned,
      required bool topmost,
    }) async {
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 20; attempt++) {
          final latest = platform.tray.rebuildSurfaceModeSnapshots.isEmpty
              ? null
              : platform.tray.rebuildSurfaceModeSnapshots.last['pin-paper'];
          if (latest?['pinned'] == pinned && latest?['topmost'] == topmost) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();
    }

    await tester.tap(find.byTooltip('Pin to desktop'));
    await tester.pump();
    await waitForSurfaceMode(pinned: true, topmost: false);

    final paper = controller.state.papers.single;
    expect(paper.isPinnedToDesktop, true);
    expect(paper.alwaysOnTop, false);
    expect(paper.isCollapsed, false);
    expect(controller.state.useCapsuleMode, true);
    expect(controller.state.useDeepCapsuleMode, true);
    expect(controller.state.showDeepCapsuleWhileExpanded, true);
    expect(find.byTooltip('Unpin from desktop'), findsOneWidget);
    expect(platform.paperWindows.updatedTitles, contains('Pin paper'));
    expect(store.savedState.papers.single.isPinnedToDesktop, true);
    expect(platform.tray.rebuildSurfaceModeSnapshots.last, {
      'pin-paper': {'pinned': true, 'topmost': false},
    });
    expect(find.byTooltip('Keep on top'), findsNothing);
    expect(find.byTooltip('Hide this paper'), findsNothing);

    await tester.tap(find.byTooltip('Unpin from desktop'));
    await tester.pump();
    await waitForSurfaceMode(pinned: false, topmost: false);

    expect(paper.alwaysOnTop, false);
    expect(paper.isPinnedToDesktop, false);
    expect(find.byTooltip('Keep on top'), findsOneWidget);
    expect(find.byTooltip('Pin to desktop'), findsOneWidget);
    expect(store.savedState.papers.single.isPinnedToDesktop, false);
    expect(platform.tray.rebuildSurfaceModeSnapshots.last, {
      'pin-paper': {'pinned': false, 'topmost': false},
    });

    await tester.tap(find.byTooltip('Keep on top'));
    await tester.pump();
    await waitForSurfaceMode(pinned: false, topmost: true);

    expect(paper.alwaysOnTop, true);
    expect(paper.isPinnedToDesktop, false);
    expect(find.byTooltip('Disable always on top'), findsOneWidget);
    expect(find.byTooltip('Pin to desktop'), findsOneWidget);
    expect(store.savedState.papers.single.alwaysOnTop, true);
    expect(store.savedState.papers.single.isPinnedToDesktop, false);
    expect(platform.tray.rebuildSurfaceModeSnapshots.last, {
      'pin-paper': {'pinned': false, 'topmost': true},
    });
  });

  testWidgets('pinned desktop papers lock title body and chrome actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'locked-pinned-paper',
            type: PaperTypes.todo,
            title: 'Locked pinned paper',
            isPinnedToDesktop: true,
            items: [
              PaperItem(id: 'locked-item', text: 'Do not change'),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );
    final store = _MemoryStateStore();

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    final paper = controller.state.papers.single;
    final titleField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('locked-pinned-paper-title')),
    );
    expect(titleField.enabled, false);
    expect(find.byTooltip('Unpin from desktop'), findsOneWidget);
    expect(find.byTooltip('Keep on top'), findsNothing);
    expect(find.byTooltip('Hide this paper'), findsNothing);
    expect(find.byTooltip('Delete paper'), findsNothing);

    await tester.tap(find.byType(Checkbox).first, warnIfMissed: false);
    await tester.tap(
      find.widgetWithText(TextButton, 'Add item'),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(paper.items.single.done, false);
    expect(paper.items, hasLength(1));

    await tester.tap(find.byTooltip('Unpin from desktop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(paper.isPinnedToDesktop, false);
    expect(store.savedState.papers.single.isPinnedToDesktop, false);
    expect(find.byTooltip('Keep on top'), findsOneWidget);
    expect(find.byTooltip('Hide this paper'), findsOneWidget);
  });

  testWidgets('expanding a pinned collapsed paper unpins like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'collapsed-pinned-paper',
            type: PaperTypes.todo,
            title: 'Collapsed pinned paper',
            isPinnedToDesktop: true,
            items: [
              PaperItem(id: 'collapsed-pinned-item', text: 'Restore me'),
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

    await tester.tap(find.byTooltip('Expand paper'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(paper.isPinnedToDesktop, false);
    expect(paper.isCollapsed, false);
    expect(store.savedState.papers.single.isPinnedToDesktop, false);
    expect(store.savedState.papers.single.isCollapsed, false);
    expect(platform.paperWindows.updatedTitles,
        contains('Collapsed pinned paper'));
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

    await tester.tap(find.byTooltip('Hide this paper'));
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
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Paper limit reached'), findsOneWidget);
    expect(
      find.text(
        'You have reached the 100-paper limit.\n'
        'Delete papers you no longer need before creating more.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'OK'), findsOneWidget);
    final paperLimitSurface = find.byWidgetPredicate(
      (widget) =>
          widget is ConstrainedBox &&
          widget.constraints.minWidth == 340 &&
          widget.constraints.minHeight == 176 &&
          widget.constraints.maxWidth == 340 &&
          widget.constraints.maxHeight == 176,
    );
    expect(paperLimitSurface, findsOneWidget);
    expect(tester.getSize(paperLimitSurface), const Size(340, 176));
    final okButton = find.widgetWithText(TextButton, 'OK');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_primaryFocusIsWithin(okButton), isTrue);
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
    expect(find.text('Open in default .md editor'), findsOneWidget);
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
      _popupMenuItemWithText('Pin to desktop'),
    );
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isPinnedToDesktop, true);
    expect(controller.state.papers.single.alwaysOnTop, false);
  });

  testWidgets(
      'mobile paper board stays single-layer and touch-safe in both orientations',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'mobile-layout',
            type: PaperTypes.todo,
            title: 'PaperTodo mobile',
            items: [
              PaperItem(
                id: 'mobile-layout-item',
                text: 'One paper, one visual surface',
              ),
            ],
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    Future<void> verifyAt(Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        RePaperTodoApp(
          controller: controller,
          store: _MemoryStateStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 52);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('mobile-layout-paper-header')),
            )
            .height,
        56,
      );

      final surface = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('mobile-layout-paper-surface')),
      );
      final decoration = surface.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(18));
      expect(decoration.boxShadow, hasLength(1));
      expect(decoration.boxShadow!.single.blurRadius, 16);

      expect(
        tester.getSize(
          find.byKey(const ValueKey('mobile-layout-paper-actions')),
        ),
        const Size(48, 48),
      );
      expect(
        tester.getSize(
          find.byKey(
            const ValueKey('mobile-layout-mobile-layout-item-actions'),
          ),
        ),
        const Size(48, 48),
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('mobile-layout-mobile-add-item')),
            )
            .height,
        greaterThanOrEqualTo(44),
      );

      final screen = Offset.zero & size;
      for (final finder in [
        find.byKey(const ValueKey('mobile-layout-paper-surface')),
        find.byKey(const ValueKey('mobile-layout-paper-actions')),
        find.byKey(
          const ValueKey('mobile-layout-mobile-layout-item-actions'),
        ),
        find.byKey(const ValueKey('mobile-layout-mobile-add-item')),
      ]) {
        expect(screen.contains(tester.getRect(finder).topLeft), true);
        expect(screen.contains(tester.getRect(finder).bottomRight), true);
      }
    }

    await verifyAt(const Size(375, 667));
    await verifyAt(const Size(667, 375));
  });

  testWidgets('opens paper context menu from header right click like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'paper-context-note',
            type: PaperTypes.note,
            title: 'Paper context',
            content: 'Right click the paper chrome.',
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

    final header =
        find.byKey(const ValueKey('paper-context-note-paper-header'));
    expect(header, findsOneWidget);

    await tester.tapAt(
      tester.getTopLeft(header) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(_popupMenuItemWithText('New'), findsOneWidget);
    expect(
      _popupMenuItemWithText('Canvas'),
      findsOneWidget,
    );
    expect(
      _popupMenuItemWithText('Paper context'),
      findsOneWidget,
    );
    expect(
      _popupMenuItemWithText('Desktop pin'),
      findsOneWidget,
    );
    expect(find.text('New todo paper'), findsOneWidget);
    expect(find.text('New note paper'), findsOneWidget);
    expect(find.text('Collapse to capsule'), findsOneWidget);
    expect(find.text('Pin to desktop'), findsOneWidget);

    await tester.tap(find.text('New note paper'));
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.where((paper) => paper.isNote),
      hasLength(2),
    );
  });

  testWidgets('independent paper windows use the compact PaperTodo menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'desktop-menu-note',
            type: PaperTypes.note,
            title: 'Desktop menu',
            content: 'Right click the desktop paper.',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: 'desktop-menu-note',
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('desktop-menu-note-paper-header'));
    await tester.tapAt(
      tester.getTopLeft(header) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('+ Todo paper'), findsOneWidget);
    expect(find.text('+ Note paper'), findsOneWidget);
    expect(find.text('Add code block'), findsOneWidget);
    expect(find.text('Pin to desktop'), findsOneWidget);
    expect(find.text('Collapse to capsule'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Open surface'), findsNothing);
    expect(find.text('Keep on top'), findsNothing);
    expect(find.text('Save window bounds'), findsNothing);
    expect(find.text('75%'), findsNothing);

    final newTodo = _popupMenuItemWithText('+ Todo paper');
    expect(
      find.descendant(of: newTodo, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(tester.widget<PopupMenuItem<String>>(newTodo).height, 21);
    final newTodoInk = find.descendant(
      of: newTodo,
      matching: find.byType(InkWell),
    );
    expect(newTodoInk, findsOneWidget);
    final menuHeader = _popupMenuItemWithText('New');
    final menuHeaderLabel = find.descendant(
      of: menuHeader,
      matching: find.text('New'),
    );
    final menuHeaderText = tester.widget<Text>(menuHeaderLabel);
    final menuColors = PaperTodoThemeColors.of(tester.element(menuHeaderLabel));
    final newTodoInkWidget = tester.widget<InkWell>(newTodoInk);
    expect(newTodoInkWidget.borderRadius, BorderRadius.circular(8));
    expect(newTodoInkWidget.hoverColor, menuColors.hover);
    expect(newTodoInkWidget.highlightColor, Colors.transparent);
    expect(
      menuHeaderText.style?.color,
      menuColors.weakText.withValues(alpha: 0.72),
    );
  });

  testWidgets('independent todo windows use the source compact item menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final item = PaperItem(
      id: 'desktop-item-menu-row',
      text: 'Review compact menu',
      todoColumnCount: 2,
      todoExtraColumns: ['Owner'],
    );
    final paper = PaperData(
      id: 'desktop-item-menu-paper',
      type: PaperTypes.todo,
      title: 'Todo menu',
      width: 360,
      items: [item],
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(
            papers: [
              paper,
              PaperData(
                id: 'desktop-item-menu-note',
                type: PaperTypes.note,
                title: 'Available note',
              ),
            ],
          ),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(
      const ValueKey('desktop-item-menu-paper-desktop-item-menu-row-row'),
    );
    await tester.tapAt(
      tester.getCenter(row),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    final header = _popupMenuItemWithText('Item');
    final due = _popupMenuItemWithText('Set time');
    expect(tester.widget<PopupMenuItem<String>>(header).height, 17);
    expect(tester.widget<PopupMenuItem<String>>(due).height, 21);
    final menuTheme = Theme.of(tester.element(due));
    final menuColors = PaperTodoThemeColors.of(tester.element(due));
    final dueInk = find.descendant(of: due, matching: find.byType(InkWell));
    expect(dueInk, findsOneWidget);
    final dueInkWidget = tester.widget<InkWell>(dueInk);
    expect(dueInkWidget.borderRadius, BorderRadius.circular(8));
    expect(dueInkWidget.hoverColor, menuColors.hover);
    expect(dueInkWidget.highlightColor, Colors.transparent);
    expect(menuTheme.highlightColor, menuColors.hover);
    expect(
      menuTheme.popupMenuTheme.labelTextStyle
          ?.resolve({WidgetState.disabled})?.color,
      menuColors.text.withValues(alpha: 0.72),
    );
    expect(find.descendant(of: due, matching: find.byType(Icon)), findsNothing);
    expect(find.text('Insert column before this one'), findsOneWidget);
    expect(find.text('Delete this column'), findsOneWidget);
    expect(find.text('Add column to this todo'), findsOneWidget);
    expect(find.text('Remove column from this todo'), findsOneWidget);
    expect(find.text('Equal widths'), findsNothing);
    expect(find.text('Wide first column'), findsNothing);
    expect(find.text('Move item up'), findsNothing);
    expect(find.text('Move item down'), findsNothing);
    expect(find.text('Available note'), findsNothing);
  });

  testWidgets('independent todo linked-note menu includes the source title',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'linked-menu-paper',
      type: PaperTypes.todo,
      title: 'Linked menu',
      items: [
        PaperItem(
          id: 'linked-menu-item',
          text: 'Open plan',
          linkedNoteId: 'linked-menu-note',
        ),
      ],
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(
            papers: [
              paper,
              PaperData(
                id: 'linked-menu-note',
                type: PaperTypes.note,
                title: 'Build plan',
              ),
            ],
          ),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(
      const ValueKey('linked-menu-paper-linked-menu-item-row'),
    );
    await tester.tapAt(
      tester.getCenter(row),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Open linked note: Build plan'), findsOneWidget);
    expect(find.text('Open linked note'), findsNothing);
    expect(find.text('Unlink note'), findsOneWidget);
  });

  testWidgets('paper context menu restores a collapsed paper like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'paper-menu-restore-window',
            type: PaperTypes.todo,
            title: 'Restore window menu',
            isCollapsed: true,
            items: [
              PaperItem(id: 'restore-window-item', text: 'Restore me'),
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

    final header =
        find.byKey(const ValueKey('paper-menu-restore-window-paper-header'));
    await tester.tapAt(
      tester.getTopLeft(header) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Restore window'), findsOneWidget);

    await tester.tap(find.text('Restore window'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isCollapsed, false);
    expect(find.text('Restore me'), findsOneWidget);
  });

  testWidgets('paper context menu clears completed todo items like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'paper-menu-clear-done',
            type: PaperTypes.todo,
            title: 'Paper menu clear done',
            items: [
              PaperItem(id: 'done-one', text: 'Done one', done: true),
              PaperItem(id: 'done-two', text: 'Done two', done: true, order: 1),
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

    final header =
        find.byKey(const ValueKey('paper-menu-clear-done-paper-header'));
    await tester.tapAt(
      tester.getTopLeft(header) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(_popupMenuItemWithText('Todo'), findsOneWidget);
    await tester.tap(
      _popupMenuItemWithText('Clear completed'),
    );
    await tester.pumpAndSettle();

    final fallback = controller.state.papers.single.items.single;
    expect(fallback.id, isNot(anyOf('done-one', 'done-two')));
    expect(fallback.text, '');
    expect(fallback.done, false);
    expect(
      controller.state.sync.deletedTodoItemTombstones['paper-menu-clear-done']
          ?.containsKey('done-one'),
      true,
    );
    expect(
      controller.state.sync.deletedTodoItemTombstones['paper-menu-clear-done']
          ?.containsKey('done-two'),
      true,
    );
  });

  testWidgets('paper context menu adds a note canvas code block like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'paper-menu-note-canvas',
            type: PaperTypes.note,
            title: 'Paper menu note canvas',
            content: 'Add a code block from the paper menu.',
            width: 520,
            height: 360,
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

    final header =
        find.byKey(const ValueKey('paper-menu-note-canvas-paper-header'));
    await tester.tapAt(
      tester.getTopLeft(header) + const Offset(12, 12),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(_popupMenuItemWithText('Canvas'), findsOneWidget);
    await tester.tap(
      _popupMenuItemWithText('Add canvas block'),
    );
    await tester.pumpAndSettle();

    final element = controller.state.papers.single.noteCanvasElements.single;
    expect(element.type, NoteCanvasElementTypes.code);
    expect(element.text, 'Console.WriteLine("PaperTodo");');
    expect(element.x, 28);
    expect(element.y, 28);
    expect(element.width, 230);
    expect(element.height, 116);
    expect(element.zIndex, 10);
  });

  testWidgets('opens paper context menu from note preview right click',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        papers: [
          PaperData(
            id: 'preview-context-note',
            type: PaperTypes.note,
            title: 'Preview context',
            content: 'Right click the note preview.',
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

    final preview = find.byKey(const ValueKey('preview-context-note-preview'));
    expect(preview, findsOneWidget);

    await tester.tapAt(
      tester.getCenter(preview),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('New todo paper'), findsOneWidget);
    expect(find.text('Open surface'), findsOneWidget);
    expect(find.text('Insert link'), findsNothing);

    await tester.tap(find.text('New todo paper'));
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.where((paper) => paper.isTodo),
      hasLength(1),
    );
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
    expect(find.byTooltip('Set time'), findsNothing);
    expect(find.byTooltip('Delete this item'), findsNothing);

    await tester.tap(actionsFinder);
    await tester.pumpAndSettle();

    expect(find.text('Set time'), findsOneWidget);
    expect(find.text('Set reminder interval'), findsOneWidget);
    expect(find.text('Add column'), findsOneWidget);
    expect(find.text('Delete this item'), findsOneWidget);

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

    final spareActionsFinder = find.byKey(
      const ValueKey('mobile-actions-paper-mobile-action-spare-actions'),
    );

    await tester.tap(spareActionsFinder);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<String> && widget.value == 'delete',
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.papers.first.items, hasLength(1));
    expect(controller.state.papers.first.items.single.id, 'mobile-action-item');
  });

  testWidgets('opens todo item context menu on right click like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'context-menu-paper',
            type: PaperTypes.todo,
            title: 'Context menu paper',
            items: [
              PaperItem(id: 'context-item', text: 'Right click me'),
              PaperItem(id: 'spare-context-item', text: 'Keep a neighbor'),
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
    final row =
        find.byKey(const ValueKey('context-menu-paper-context-item-row'));
    expect(row, findsOneWidget);

    await tester.tapAt(tester.getCenter(row), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(_popupMenuItemWithText('Item'), findsOneWidget);
    expect(find.text('Set time'), findsOneWidget);
    expect(find.text('Add column'), findsOneWidget);
    expect(find.text('Delete this item'), findsOneWidget);
    expect(find.text('Paste'), findsNothing);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<String> && widget.value == 'column:add',
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.items.first.todoColumnCount, 2);
  });

  testWidgets('todo due indicator precedes the right-edge move controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'todo-action-order-paper',
            type: PaperTypes.todo,
            title: 'Action order',
            items: [
              PaperItem(id: 'order-first', text: 'First'),
              PaperItem(
                id: 'order-second',
                text: 'Second',
                dueAtLocal: '2099-07-16T10:00:00',
              ),
              PaperItem(id: 'order-third', text: 'Third'),
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

    final row = find.byKey(
      const ValueKey('todo-action-order-paper-order-second-row'),
    );
    final due = find.descendant(
      of: row,
      matching: find.byKey(
        const ValueKey(
          'todo-action-order-paper-order-second-due-absolute',
        ),
      ),
    );
    final delete = find.descendant(
      of: row,
      matching: find.byTooltip('Delete this item'),
    );
    final moveUp = find.descendant(
      of: row,
      matching: find.byTooltip('Move item up'),
    );
    final moveDown = find.descendant(
      of: row,
      matching: find.byTooltip('Move item down'),
    );

    expect(tester.getCenter(due).dx, lessThan(tester.getCenter(delete).dx));
    expect(tester.getCenter(delete).dx, lessThan(tester.getCenter(moveUp).dx));
    expect(
        tester.getCenter(moveUp).dx, lessThan(tester.getCenter(moveDown).dx));
  });

  testWidgets('todo rows use immediate hover and source completion transitions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        enableAnimations: true,
        papers: [
          PaperData(
            id: 'todo-row-motion-paper',
            type: PaperTypes.todo,
            title: 'Row motion',
            items: [
              PaperItem(id: 'todo-row-motion-item', text: 'Hover me'),
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

    final row = find.byKey(
      const ValueKey('todo-row-motion-paper-todo-row-motion-item-row'),
    );
    final hoverSurface = find.descendant(
      of: row,
      matching: find.byType(AnimatedContainer),
    );
    final completionSurface = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedOpacity &&
            widget.duration == const Duration(milliseconds: 150),
      ),
    );
    expect(hoverSurface, findsOneWidget);
    expect(completionSurface, findsOneWidget);
    expect(
      tester.widget<AnimatedContainer>(hoverSurface).duration,
      Duration.zero,
    );
    expect(
      tester.widget<AnimatedOpacity>(completionSurface).duration,
      const Duration(milliseconds: 150),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump();

    final hoveredDecoration = tester
        .widget<AnimatedContainer>(hoverSurface)
        .decoration as BoxDecoration;
    final rowColors = PaperTodoThemeColors.of(tester.element(row));
    expect(hoveredDecoration.color, rowColors.hover);

    await tester.tap(
      find.descendant(of: row, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    final completedSurface = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedOpacity &&
            widget.duration == const Duration(milliseconds: 200),
      ),
    );
    expect(completedSurface, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(completedSurface).opacity, 0.75);
    expect(
      tester.widget<AnimatedOpacity>(completedSurface).duration,
      const Duration(milliseconds: 200),
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: row, matching: find.byType(EditableText)),
          )
          .style
          .color,
      rowColors.brightWeakText,
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: row, matching: find.byType(EditableText)),
          )
          .style
          .decoration,
      TextDecoration.none,
    );
    final completionLine = find.byKey(
      const ValueKey(
        'todo-row-motion-paper-todo-row-motion-item-completion-line-main',
      ),
    );
    expect(completionLine, findsOneWidget);
    final dynamic completionPainter =
        tester.widget<CustomPaint>(completionLine).painter;
    expect(completionPainter.strokeWidth, 1.35);
    expect(
      completionPainter.color,
      rowColors.brightWeakText.withValues(alpha: 205 / 255),
    );

    await mouse.removePointer();
  });

  testWidgets('todo due badges match PaperTodo timing and visual metrics',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now();
    final controller = RePaperTodoController(
      initialState: AppState(
        showTodoDueRelativeTime: true,
        papers: [
          PaperData(
            id: 'todo-due-visual-paper',
            type: PaperTypes.todo,
            title: 'Due visuals',
            width: 700,
            items: [
              PaperItem(
                id: 'normal-due-item',
                text: 'Normal due',
                dueAtLocal:
                    now.add(const Duration(minutes: 30)).toIso8601String(),
              ),
              PaperItem(
                id: 'soon-due-item',
                text: 'Soon due',
                dueAtLocal:
                    now.add(const Duration(minutes: 5)).toIso8601String(),
              ),
              PaperItem(
                id: 'past-due-item',
                text: 'Past due',
                dueAtLocal:
                    now.subtract(const Duration(minutes: 5)).toIso8601String(),
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

    const normalSurfaceKey =
        ValueKey('todo-due-visual-paper-normal-due-item-due-absolute-surface');
    const soonSurfaceKey =
        ValueKey('todo-due-visual-paper-soon-due-item-due-absolute-surface');
    const pastSurfaceKey =
        ValueKey('todo-due-visual-paper-past-due-item-due-absolute-surface');
    final normalSurface = find.byKey(normalSurfaceKey);
    final soonSurface = find.byKey(soonSurfaceKey);
    final pastSurface = find.byKey(pastSurfaceKey);
    final colors = PaperTodoThemeColors.of(tester.element(normalSurface));
    Material material(Finder finder) => tester.widget<Material>(finder);
    TextStyle badgeStyle(Finder finder) => tester
        .widget<Text>(find.descendant(of: finder, matching: find.byType(Text)))
        .style!;

    expect(material(normalSurface).shape, isNull);
    expect(material(normalSurface).borderRadius, BorderRadius.circular(8));
    expect(
      material(normalSurface).color,
      colors.tint.withValues(alpha: 18 / 255),
    );
    expect(badgeStyle(normalSurface).color, colors.weakText);
    expect(
      material(soonSurface).color,
      colors.tint.withValues(alpha: 28 / 255),
    );
    expect(badgeStyle(soonSurface).color, colors.active);
    expect(
      material(pastSurface).color,
      colors.danger.withValues(alpha: 18 / 255),
    );
    expect(badgeStyle(pastSurface).color, colors.danger);
    expect(tester.getSize(normalSurface).height, 22);
    expect(tester.getSize(normalSurface).width, greaterThanOrEqualTo(38));
    expect(
      find.descendant(
        of: normalSurface,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Padding &&
              widget.padding ==
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        ),
      ),
      findsOneWidget,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(normalSurface));
    await tester.pump();
    expect(material(normalSurface).color, colors.hover);
    expect(badgeStyle(normalSurface).color, colors.text);
    await mouse.removePointer();
  });

  testWidgets('linked note button matches PaperTodo metrics and pointer states',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final todo = PaperData(
      id: 'linked-note-visual-paper',
      type: PaperTypes.todo,
      title: 'Todo1',
      items: [
        PaperItem(
          id: 'linked-note-visual-item',
          text: 'Review',
          linkedNoteId: 'linked-note-visual-note',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        showLinkedNoteName: true,
        papers: [
          todo,
          PaperData(
            id: 'linked-note-visual-note',
            type: PaperTypes.note,
            title: 'Plan',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: todo.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(
      const ValueKey(
        'linked-note-visual-paper-linked-note-visual-item-linked-note-button',
      ),
    );
    expect(button, findsOneWidget);
    expect(tester.getSize(button), const Size(50, 22));
    final colors = PaperTodoThemeColors.of(tester.element(button));
    Material material() => tester.widget<Material>(button);
    final labelFinder =
        find.descendant(of: button, matching: find.byType(Text));
    Text label() => tester.widget<Text>(labelFinder);
    Opacity pressOpacity() =>
        tester.element(button).findAncestorWidgetOfExactType<Opacity>()!;

    expect(
      material().color,
      colors.tint.withValues(alpha: 18 / 255),
    );
    expect(
      label().style?.color,
      colors.weakText.withValues(alpha: 0.72),
    );
    expect(label().data, 'Pla…');
    expect(pressOpacity().opacity, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump();
    expect(
      material().color,
      colors.tint.withValues(alpha: 34 / 255),
    );
    expect(label().style?.color, colors.text);

    await mouse.down(tester.getCenter(button));
    await tester.pump();
    expect(pressOpacity().opacity, 0.72);
    await mouse.cancel();
    await tester.pump();
    expect(pressOpacity().opacity, 1);
  });

  testWidgets('Windows linked note buttons use PaperTodo source glyphs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final todo = PaperData(
      id: 'linked-note-glyph-paper',
      type: PaperTypes.todo,
      title: 'Todo1',
      items: [
        PaperItem(
          id: 'linked-note-glyph-item',
          text: 'Open note',
          linkedNoteId: 'linked-note-glyph-note',
        ),
        PaperItem(
          id: 'linked-script-glyph-item',
          text: 'Run script',
          linkedNoteId: 'linked-script-glyph-note',
          order: 1,
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        showLinkedNoteName: false,
        runLinkedScriptCapsulesOnClick: true,
        papers: [
          todo,
          PaperData(
            id: 'linked-note-glyph-note',
            type: PaperTypes.note,
            title: 'Plan',
          ),
          PaperData(
            id: 'linked-script-glyph-note',
            type: PaperTypes.note,
            title: 'Build',
            content: '!p\nWrite-Output ok',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: todo.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final noteButton = find.byKey(
      const ValueKey(
        'linked-note-glyph-paper-linked-note-glyph-item-linked-note-button',
      ),
    );
    final scriptButton = find.byKey(
      const ValueKey(
        'linked-note-glyph-paper-linked-script-glyph-item-linked-note-button',
      ),
    );
    final noteGlyph = tester.widget<Text>(
      find.descendant(of: noteButton, matching: find.text('\uE71B')),
    );
    final scriptGlyph = tester.widget<Text>(
      find.descendant(of: scriptButton, matching: find.text('⚡')),
    );

    expect(noteGlyph.style?.fontFamily, 'Segoe MDL2 Assets');
    expect(scriptGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(noteGlyph.style?.fontSize, 12.5);
    expect(scriptGlyph.style?.fontSize, 13.5);
  });

  testWidgets('auto-wrapped todo text switches linked note multiline metrics',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final item = PaperItem(
      id: 'auto-wrap-linked-item',
      text: 'This todo sentence is deliberately long enough to wrap inside '
          'the narrow paper without containing a newline.',
      linkedNoteId: 'auto-wrap-linked-note',
    );
    final todo = PaperData(
      id: 'auto-wrap-linked-paper',
      type: PaperTypes.todo,
      title: 'Todo1',
      items: [item],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        showLinkedNoteName: true,
        papers: [
          todo,
          PaperData(
            id: 'auto-wrap-linked-note',
            type: PaperTypes.note,
            title: 'Planning document',
          ),
        ],
      ),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: todo.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(
      const ValueKey('auto-wrap-linked-paper-auto-wrap-linked-item-row'),
    );
    final button = find.byKey(
      const ValueKey(
        'auto-wrap-linked-paper-auto-wrap-linked-item-linked-note-button',
      ),
    );
    expect(item.text, isNot(contains('\n')));
    expect(tester.getSize(row).height, greaterThan(34));
    expect(tester.getSize(button), const Size(44, 22));
    expect(
      find.descendant(of: button, matching: find.text('Plann…')),
      findsOneWidget,
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(
          const ValueKey('auto-wrap-linked-paper-auto-wrap-linked-item-text'),
        ),
        matching: find.byType(EditableText),
      ),
      'Short',
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(row).height, 34);
    expect(tester.getSize(button), const Size(50, 22));
    expect(
      find.descendant(of: button, matching: find.text('Pla…')),
      findsOneWidget,
    );
  });

  testWidgets(
      'long multi-column todo centers each column and trailing chrome like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final item = PaperItem(
      id: 'long-column-item',
      text: 'A short first column.',
      todoColumnCount: 3,
      todoExtraColumns: [
        'The middle column deliberately wraps across many rendered lines so '
            'it establishes the height of the complete todo row.',
        'A short final column.',
      ],
      todoColumnWidths: [2.1, 1, 1],
    );
    final paper = PaperData(
      id: 'long-column-paper',
      type: PaperTypes.todo,
      title: 'Todo1',
      width: 440,
      height: 340,
      items: [item],
    );
    final controller = RePaperTodoController(
      initialState: AppState(theme: 'light', papers: [paper]),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(
      const ValueKey('long-column-paper-long-column-item-row'),
    );
    final firstField = find.byKey(
      const ValueKey('long-column-paper-long-column-item-text-field-0'),
    );
    final middleField = find.byKey(
      const ValueKey('long-column-paper-long-column-item-column-2'),
    );
    final finalField = find.byKey(
      const ValueKey('long-column-paper-long-column-item-column-3'),
    );
    final checkBox = find.byKey(
      const ValueKey('long-column-paper-long-column-item-checkbox'),
    );
    final dragHandle = find.byKey(
      const ValueKey('long-column-paper-long-column-item-drag-handle'),
    );
    final firstSplitter = find.byKey(
      const ValueKey('long-column-paper-long-column-item-column-splitter-1'),
    );
    final secondSplitter = find.byKey(
      const ValueKey('long-column-paper-long-column-item-column-splitter-2'),
    );

    final rowRect = tester.getRect(row);
    final middleInputDecorator = tester.widget<InputDecorator>(
      find.descendant(of: middleField, matching: find.byType(InputDecorator)),
    );
    final firstRect = tester.getRect(firstField);
    final middleRect = tester.getRect(middleField);
    final finalRect = tester.getRect(finalField);
    final firstSplitterRect = tester.getRect(firstSplitter);
    final secondSplitterRect = tester.getRect(secondSplitter);
    expect(middleRect.height, greaterThan(firstRect.height + 20));
    expect(middleInputDecorator.decoration.filled, false);
    expect(middleRect.height, greaterThan(finalRect.height + 20));
    expect(firstSplitterRect.left - firstRect.right, closeTo(3, 0.01));
    expect(middleRect.left - firstSplitterRect.right, closeTo(6, 0.01));
    expect(secondSplitterRect.left - middleRect.right, closeTo(3, 0.01));
    expect(finalRect.left - secondSplitterRect.right, closeTo(6, 0.01));
    expect(firstRect.center.dy, closeTo(rowRect.center.dy, 1));
    expect(finalRect.center.dy, closeTo(rowRect.center.dy, 1));
    expect(tester.getRect(checkBox).center.dy, closeTo(rowRect.center.dy, 1));
    expect(tester.getRect(dragHandle).center.dy, closeTo(rowRect.center.dy, 1));
  });

  testWidgets('long standalone todo exposes PaperTodo auto scrollbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final paper = PaperData(
      id: 'long-scroll-todo',
      type: PaperTypes.todo,
      title: 'Todo1',
      width: 280,
      height: 340,
      items: [
        for (var index = 0; index < 24; index++)
          PaperItem(
            id: 'long-scroll-item-$index',
            text: 'Long scrolling item $index',
            order: index,
          ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(theme: 'light', papers: [paper]),
      platform: _RecordingPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final scroll = find.byKey(const ValueKey('todo-paper-scroll'));
    final scrollView = tester.widget<SingleChildScrollView>(scroll);
    final scrollbarFinder = find.byKey(const ValueKey('todo-paper-scrollbar'));
    final scrollbar = tester.widget<Scrollbar>(scrollbarFinder);
    final scrollbarTheme =
        Theme.of(tester.element(scrollbarFinder)).scrollbarTheme;
    expect(scrollbar.controller, same(scrollView.controller));
    expect(scrollbar.thumbVisibility, true);
    expect(scrollbarTheme.mainAxisMargin, 7);
    expect(scrollbarTheme.crossAxisMargin, 0);
    expect(
      scrollbarTheme.thumbColor!.resolve(<WidgetState>{}),
      const Color(0xFFB39B74).withValues(alpha: 0.34),
    );
    expect(
      scrollbarTheme.thumbColor!.resolve(<WidgetState>{WidgetState.hovered}),
      const Color(0xFF96784F).withValues(alpha: 0.54),
    );
    expect(scrollView.controller!.position.maxScrollExtent, greaterThan(0));

    await tester.drag(scroll, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(scrollView.controller!.offset, greaterThan(0));
  });

  testWidgets('todo context menu column actions target the clicked column',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'context-column-paper',
            type: PaperTypes.todo,
            title: 'Context column paper',
            items: [
              PaperItem(
                id: 'context-column-item',
                text: 'Column one',
                todoColumnCount: 3,
                todoExtraColumns: ['Column two', 'Column three'],
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

    final thirdColumn = find.byKey(
      const ValueKey('context-column-paper-context-column-item-column-3'),
    );
    expect(thirdColumn, findsOneWidget);

    await tester.tapAt(
      tester.getCenter(thirdColumn),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Insert before column 3'), findsOneWidget);
    expect(find.text('Delete column 3'), findsOneWidget);
    expect(find.text('Delete column 1'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final thirdColumnEditable = tester.widget<EditableText>(
      find.descendant(of: thirdColumn, matching: find.byType(EditableText)),
    );
    expect(thirdColumnEditable.focusNode.hasFocus, true);

    await tester.tapAt(
      tester.getCenter(thirdColumn),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete column 3'));
    await tester.pumpAndSettle();

    final item = controller.state.papers.single.items.single;
    expect(item.todoColumnCount, 2);
    expect(item.text, 'Column one');
    expect(item.todoExtraColumns, ['Column two']);
  });

  testWidgets('clears todo due and reminder from compact menu like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'compact-due-paper',
            type: PaperTypes.todo,
            title: 'Compact due',
            items: [
              PaperItem(
                id: 'compact-due-item',
                text: 'Clear compact metadata',
                dueAtLocal: '2026-06-30T09:15:00',
                reminderIntervalValue: 30,
                reminderIntervalUnit: TodoReminderIntervalUnits.minutes,
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

    final actionsFinder = find.byKey(
      const ValueKey('compact-due-paper-compact-due-item-actions'),
    );
    final item = controller.state.papers.single.items.single;

    await tester.tap(actionsFinder);
    await tester.pumpAndSettle();

    expect(find.text('Change time'), findsOneWidget);
    expect(find.text('Clear time'), findsOneWidget);
    expect(find.text('Change reminder interval'), findsOneWidget);
    expect(find.text('Use global reminder interval'), findsOneWidget);

    await tester.tap(find.text('Clear time'));
    await tester.pumpAndSettle();

    expect(item.dueAtLocal, isNull);
    expect(item.reminderIntervalValue, 30);

    await tester.tap(actionsFinder);
    await tester.pumpAndSettle();
    expect(find.text('Set time'), findsOneWidget);
    expect(find.text('Clear time'), findsNothing);
    await tester.tap(find.text('Use global reminder interval'));
    await tester.pumpAndSettle();

    expect(item.reminderIntervalValue, isNull);
    expect(item.reminderIntervalUnit, isNull);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    var restoredItem = controller.state.papers.single.items.single;
    expect(restoredItem.reminderIntervalValue, 30);
    expect(
        restoredItem.reminderIntervalUnit, TodoReminderIntervalUnits.minutes);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    restoredItem = controller.state.papers.single.items.single;
    expect(restoredItem.dueAtLocal, '2026-06-30T09:15:00');
  });

  testWidgets('disables interactive tooltips', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        enableToolTips: false,
        pinnedTodoHotKey: 'Ctrl+Alt+T',
        papers: [
          PaperData(
            id: 'no-tooltip-paper',
            type: PaperTypes.todo,
            title: 'No tooltips',
            items: [
              PaperItem(id: 'no-tooltip-item', text: 'Quiet controls'),
            ],
          ),
          PaperData(
            id: 'no-tooltip-note',
            type: PaperTypes.note,
            title: 'No tooltip note',
            content: 'Body',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'no-tooltip-canvas',
                type: NoteCanvasElementTypes.code,
                text: 'Code',
                x: 16,
                y: 24,
                width: 230,
                height: 116,
                zIndex: 1,
              ),
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
    expect(find.byTooltip('Set time'), findsNothing);
    expect(find.byTooltip('Delete this item'), findsNothing);

    await _enterNoteEditor(tester, 'no-tooltip-note');

    expect(find.byTooltip('Bold (Ctrl+B)'), findsNothing);
    expect(find.byTooltip('Italic (Ctrl+I)'), findsNothing);
    expect(find.byTooltip('Insert link (Ctrl+K)'), findsNothing);
    expect(find.byTooltip('Drag canvas block'), findsNothing);
    expect(find.byTooltip('Edit canvas geometry'), findsNothing);
    expect(find.byTooltip('Duplicate canvas block'), findsNothing);
    expect(find.byTooltip('Canvas layer actions'), findsNothing);
    expect(find.byTooltip('Delete canvas block'), findsNothing);
    expect(find.byTooltip('Resize canvas block'), findsNothing);
    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((tooltip) => tooltip.message),
      isNot(contains('')),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await _selectSettingsCategory(tester, 'general');

    expect(find.text('Show hover hints'), findsOneWidget);
    expect(
      find.byTooltip(
        'Show brief hints when the pointer rests on buttons or interactive '
        'areas. Setting info icons stay available either way.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Pinned todo hotkey'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byTooltip('Clear'), findsNothing);
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
    expect(find.text('Visible task'), findsOneWidget);
    expect(find.text('Visible note'), findsWidgets);
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
    expect(find.text('Left queue task'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to board'));
    await tester.pumpAndSettle();

    expect(find.text('Left queue task'), findsOneWidget);
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
    await _selectSettingsCategory(tester, 'capsules');
    final capsuleModeToggle = _settingsToggleTile('Capsule mode');
    await tester.scrollUntilVisible(
      capsuleModeToggle,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(capsuleModeToggle);
    await _commitVisibleDialog(tester);
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

  testWidgets('saves exposed deep capsule visibility settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        showDeepCapsuleWhileExpanded: true,
        collapseExpandedDeepCapsuleOnClick: false,
        hideDeepCapsulesWhenCovered: false,
        hideDeepCapsulesWhenFullscreen: false,
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
    await _selectSettingsCategory(tester, 'capsules');

    await tester.scrollUntilVisible(
      find.text('Show deep capsule while expanded'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Click edge capsule again to retract paper'));
    await tester.tap(find.text('Hide edge capsules when covered'));
    await tester.tap(find.text('Show deep capsule while expanded'));
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.showDeepCapsuleWhileExpanded, false);
    expect(controller.state.collapseExpandedDeepCapsuleOnClick, true);
    expect(controller.state.hideDeepCapsulesWhenCovered, true);
    expect(controller.state.hideDeepCapsulesWhenFullscreen, false);
  });

  testWidgets('saves script capsule runtime settings independently',
      (tester) async {
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
    await _selectSettingsCategory(tester, 'general');

    await tester.scrollUntilVisible(
      find.text('Persistent PowerShell process'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Persistent PowerShell process'));
    await tester.tap(find.text('Prefer PowerShell 7'));
    await tester.tap(find.text('Hide script window'));
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.runLinkedScriptCapsulesOnClick, false);
    expect(controller.state.usePersistentPowerShellProcess, true);
    expect(controller.state.preferPowerShell7, false);
    expect(controller.state.hideScriptRunWindow, false);
  });

  testWidgets('linked script capsule click setting follows todo-note links',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        enableTodoNoteLinks: false,
        runLinkedScriptCapsulesOnClick: false,
        papers: [
          PaperData(
            id: 'linked-script-disabled-paper',
            type: PaperTypes.todo,
            title: 'Linked script disabled',
            items: [
              PaperItem(
                id: 'linked-script-disabled-item',
                text: 'Tune script link settings',
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

    await _selectSettingsCategory(tester, 'todoAndNotes');
    await tester.scrollUntilVisible(
      find.text('Run linked scripts directly'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    final dynamic runLinkedTile =
        tester.widget(_settingsToggleTile('Run linked scripts directly'));
    expect(runLinkedTile.onChanged, isNull);

    await tester.tap(find.text('Run linked scripts directly'));
    await tester.pump();
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.enableTodoNoteLinks, false);
    expect(controller.state.runLinkedScriptCapsulesOnClick, false);
  });

  testWidgets('disabling todo-note links preserves capsule hiding preference',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        enableTodoNoteLinks: true,
        hideLinkedNotesFromCapsules: true,
        papers: [
          PaperData(
            id: 'preserve-linked-note-capsules-paper',
            type: PaperTypes.todo,
            title: 'Preserve linked note capsules',
            items: [
              PaperItem(
                id: 'preserve-linked-note-capsules-item',
                text: 'Tune linked note capsules',
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

    await _selectSettingsCategory(tester, 'todoAndNotes');
    await tester.scrollUntilVisible(
      find.text('Enable todo-note links'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Enable todo-note links'));
    await tester.pump();

    final dynamic hideLinkedNotesTile = tester
        .widget(_settingsToggleTile('Linked notes not shown as capsules'));
    expect(hideLinkedNotesTile.value, true);
    expect(hideLinkedNotesTile.onChanged, isNull);

    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.enableTodoNoteLinks, false);
    expect(controller.state.hideLinkedNotesFromCapsules, true);
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
    await _selectSettingsCategory(tester, 'todoAndNotes');
    await _selectSettingsCategory(tester, 'general');
    await _selectSettingsCategory(tester, 'general');

    await tester.scrollUntilVisible(
      find.text('Prefer PowerShell 7'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Prefer PowerShell 7'));
    await _commitVisibleDialog(tester);
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

    await _selectSettingsCategory(tester, 'general');
    await tester.scrollUntilVisible(
      find.text('Pinned todo hotkey'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await _captureSettingsHotKey(
      tester,
      'Pinned todo hotkey',
      LogicalKeyboardKey.keyT,
    );
    await _captureSettingsHotKey(
      tester,
      'Pinned note hotkey',
      LogicalKeyboardKey.keyN,
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.pinnedTodoHotKey, 'Ctrl+Alt+T');
    expect(controller.state.pinnedNoteHotKey, 'Ctrl+Alt+N');
    expect(platform.systemIntegration.registeredHotkeys, hasLength(1));
    expect(
      platform.systemIntegration.registeredHotkeys.single,
      ('Ctrl+Alt+T', 'Ctrl+Alt+N'),
    );
  });

  testWidgets('captures and clears pinned hotkeys like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        pinnedTodoHotKey: 'Ctrl+Alt+T',
        pinnedNoteHotKey: '',
        papers: [
          PaperData(
            id: 'hotkey-clear-paper',
            type: PaperTypes.todo,
            title: 'Hotkey clear',
            items: [
              PaperItem(id: 'hotkey-clear-item', text: 'Clear hotkeys'),
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

    await _selectSettingsCategory(tester, 'general');
    await tester.scrollUntilVisible(
      find.text('Pinned todo hotkey'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-pinned-todo-hotkey')),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    await _captureSettingsHotKey(
      tester,
      'Pinned note hotkey',
      LogicalKeyboardKey.pageUp,
      modifiers: const [LogicalKeyboardKey.controlLeft],
    );
    await _commitVisibleDialog(tester);
    await tester.pumpAndSettle();

    expect(controller.state.pinnedTodoHotKey, '');
    expect(controller.state.pinnedNoteHotKey, 'Ctrl+PageUp');
    expect(platform.systemIntegration.registeredHotkeys, [
      ('', 'Ctrl+PageUp'),
    ]);
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
    await _selectSettingsCategory(tester, 'general');
    await _selectSettingsCategory(tester, 'general');
    await _selectSettingsCategory(tester, 'general');
    await tester.scrollUntilVisible(
      find.text('Pinned todo hotkey'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await _captureSettingsHotKey(
      tester,
      'Pinned todo hotkey',
      LogicalKeyboardKey.keyT,
    );
    await _commitVisibleDialog(tester);
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
    await _selectSettingsCategory(tester, 'general');
    await tester.scrollUntilVisible(
      find.text('Hide papers from window switching'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Hide papers from window switching'));
    await _commitVisibleDialog(tester);
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
    await _selectSettingsCategory(tester, 'general');
    await _selectSettingsCategory(tester, 'general');
    await tester.scrollUntilVisible(
      find.text('Pinned todo hotkey'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await _captureSettingsHotKey(
      tester,
      'Pinned todo hotkey',
      LogicalKeyboardKey.keyT,
    );
    await _commitVisibleDialog(tester);
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
    await _selectSettingsCategory(tester, 'general');

    expect(find.text('Start with Windows'), findsNothing);
    expect(find.text('Hide papers from window switching'), findsNothing);
    expect(find.text('Avoid'), findsNothing);
    expect(find.text('Stay on top'), findsNothing);
    expect(find.text('Pinned todo hotkey'), findsNothing);
    expect(find.text('Pinned note hotkey'), findsNothing);
    expect(find.text('Run linked scripts directly'), findsNothing);
    expect(find.text('Persistent PowerShell process'), findsNothing);
    expect(find.text('Prefer PowerShell 7'), findsNothing);
    expect(find.text('Hide script window'), findsNothing);
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
    await _commitVisibleDialog(tester);
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
    expect(platform.paperWindows.shownTitles, contains('Todo1'));
    expect(store.savedState.papers.map((paper) => paper.id),
        contains('runtime-command-paper'));
    expect(
        store.savedState.papers.map((paper) => paper.title), contains('Todo1'));
    expect(platform.tray.rebuildTitleSnapshots.last,
        containsAll(['Runtime commands', 'Todo1']));
    expect(find.text('Todo1'), findsOneWidget);

    startup.addCommand(const StartupCommand(StartupCommandKind.newNote));
    await tester.pumpAndSettle();

    expect(controller.state.papers, hasLength(3));
    expect(controller.state.papers.last.type, PaperTypes.note);
    expect(platform.paperWindows.shownTitles, contains('Note1'));
    expect(store.savedState.papers.map((paper) => paper.id),
        contains('runtime-command-paper'));
    expect(store.savedState.papers.map((paper) => paper.title),
        containsAll(['Todo1', 'Note1']));
    expect(platform.tray.rebuildTitleSnapshots.last,
        containsAll(['Runtime commands', 'Todo1', 'Note1']));
    expect(find.text('Note1'), findsOneWidget);

    startup.addCommand(const StartupCommand(StartupCommandKind.settings));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
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

    expect(find.text('Settings'), findsOneWidget);
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
    expect(platform.paperWindows.restoredTitleSnapshots.last,
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
    final store = _MemoryStateStore();
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
        store: store,
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

    paper
      ..x = 240
      ..y = 180;
    platform.paperWindows.emitSurfaceUpdate(paper);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(platform.tray.rebuildVisibilitySnapshots, hasLength(1));
    expect(store.savedState.papers.single.x, 240);
    expect(store.savedState.papers.single.y, 180);
  });

  testWidgets('merges copied platform surface updates into state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final savedPaper = PaperData(
      id: 'copied-surface-paper',
      type: PaperTypes.todo,
      title: 'Copied surface',
      x: 20,
      y: 30,
      width: 320,
      height: 260,
      items: [
        PaperItem(id: 'copied-surface-item', text: 'Move me'),
      ],
    );
    store.savedState = AppState(
      papers: [
        PaperData.fromJson(savedPaper.toJson()),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData.fromJson(savedPaper.toJson()),
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

    platform.paperWindows.emitSurfaceUpdate(
      PaperData(
        id: 'copied-surface-paper',
        type: PaperTypes.todo,
        title: 'Copied surface',
        x: 240,
        y: 180,
        width: 420,
        height: 360,
        isVisible: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final paper = controller.state.papers.single;
    expect(paper.x, 240);
    expect(paper.y, 180);
    expect(paper.width, 420);
    expect(paper.height, 360);
    expect(paper.isVisible, false);
    expect(store.savedState.papers.single.x, 240);
    expect(store.savedState.papers.single.isVisible, false);
    expect(platform.tray.rebuildVisibilitySnapshots.first, {
      'copied-surface-paper': false,
    });
  });

  testWidgets('persists independent paper engine edits through coordinator',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final initialState = AppState(
      maxTitleLength: 64,
      papers: [
        PaperData(
          id: 'independent-edit-note',
          type: PaperTypes.note,
          title: 'Before',
          content: 'Before body',
        ),
      ],
    );
    await store.save(initialState);
    final controller = RePaperTodoController(
      initialState: AppState.fromJson(initialState.toJson()),
      platform: platform,
    );

    await tester.pumpWidget(
      RePaperTodoApp(controller: controller, store: store),
    );
    platform.paperWindows.emitPaperEdit(
      PaperData(
        id: 'independent-edit-note',
        type: PaperTypes.note,
        title: 'After',
        content: 'Edited in child engine',
        isCollapsed: true,
      ),
    );
    await _waitForSavedTrayTitle(tester, platform, 'After');

    expect(controller.state.papers.single.title, 'After');
    expect(controller.state.papers.single.content, 'Edited in child engine');
    expect(controller.state.papers.single.isCollapsed, true);
    expect(store.savedState.papers.single.title, 'After');
    expect(store.savedState.papers.single.content, 'Edited in child engine');
    expect(platform.paperWindows.updatedTitles, contains('After'));
  });

  testWidgets('routes independent paper actions through primary services',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final state = AppState(papers: [
      PaperData(
        id: 'independent-action-note',
        type: PaperTypes.note,
        title: 'Action note',
      ),
    ]);
    await store.save(state);
    final controller = RePaperTodoController(
      initialState: state,
      platform: platform,
    );
    await tester.pumpWidget(
      RePaperTodoApp(controller: controller, store: store),
    );

    platform.paperWindows.emitAction(
      const PaperWindowActionRequest(
        kind: PaperWindowActionKinds.openUri,
        paperId: 'independent-action-note',
        value: 'https://example.com/from-independent-paper',
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);

    expect(platform.uriOpener.openedUris,
        ['https://example.com/from-independent-paper']);
  });

  testWidgets('routes native reminder bubble clicks to the owning paper',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final state = AppState(
      useCapsuleCollapseAll: true,
      capsuleCollapseAllActive: true,
      papers: [
        PaperData(
          id: 'native-reminder-action-paper',
          type: PaperTypes.todo,
          title: 'Reminder action',
          isCollapsed: true,
        ),
      ],
    );
    await store.save(state);
    final controller = RePaperTodoController(
      initialState: state,
      platform: platform,
    );
    await tester.pumpWidget(
      RePaperTodoApp(controller: controller, store: store),
    );

    platform.paperWindows.emitAction(
      const PaperWindowActionRequest(
        kind: PaperWindowActionKinds.openReminderPaper,
        paperId: 'native-reminder-action-paper',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.state.papers.single.isCollapsed, false);
    expect(controller.state.capsuleCollapseAllActive, false);
    expect(platform.paperWindows.shownTitles, contains('Reminder action'));
    expect(store.savedState.papers.single.isCollapsed, false);
  });

  testWidgets('expanded native proxy can collapse its owning paper',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final state = AppState(
      collapseExpandedDeepCapsuleOnClick: true,
      papers: [
        PaperData(
          id: 'expanded-proxy-paper',
          type: PaperTypes.todo,
          title: 'Expanded proxy',
        ),
      ],
    );
    await store.save(state);
    final controller = RePaperTodoController(
      initialState: state,
      platform: platform,
    );
    await tester.pumpWidget(
      RePaperTodoApp(controller: controller, store: store),
    );
    await tester.pumpAndSettle();

    platform.paperWindows.emitAction(
      const PaperWindowActionRequest(
        kind: PaperWindowActionKinds.collapsePaper,
        paperId: 'expanded-proxy-paper',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.state.papers.single.isCollapsed, true);
    expect(store.savedState.papers.single.isCollapsed, true);
    expect(platform.paperWindows.restoredTitleSnapshots, isNotEmpty);
  });

  testWidgets('stale collapse proxy click unpins and activates pinned paper',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final paper = PaperData(
      id: 'stale-pinned-proxy-paper',
      type: PaperTypes.todo,
      title: 'Pinned proxy',
      isPinnedToDesktop: true,
      x: 123,
      y: 234,
      width: 456,
      height: 345,
    );
    final state = AppState(papers: [paper]);
    await store.save(state);
    final controller = RePaperTodoController(
      initialState: state,
      platform: platform,
    );
    await tester.pumpWidget(
      RePaperTodoApp(controller: controller, store: store),
    );
    await tester.pumpAndSettle();

    platform.paperWindows.emitAction(
      const PaperWindowActionRequest(
        kind: PaperWindowActionKinds.collapsePaper,
        paperId: 'stale-pinned-proxy-paper',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(paper.isPinnedToDesktop, false);
    expect(paper.isCollapsed, false);
    expect([paper.x, paper.y, paper.width, paper.height], [123, 234, 456, 345]);
    expect(platform.paperWindows.shownTitles, contains('Pinned proxy'));
    expect(store.savedState.papers.single.isPinnedToDesktop, false);
  });

  testWidgets(
      'coordinator expands a collapse-all queue from its master capsule',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final state = AppState(
      useCapsuleCollapseAll: true,
      capsuleCollapseAllActive: true,
      papers: [
        PaperData(
          id: 'collapse-all-master',
          title: 'Master',
          capsuleSide: DeepCapsuleSides.right,
        ),
        PaperData(
          id: 'collapse-all-peer',
          title: 'Peer',
          capsuleSide: DeepCapsuleSides.right,
        ),
      ],
    );
    await store.save(state);
    final controller = RePaperTodoController(
      initialState: state,
      platform: platform,
    );
    final queueKey = controller.state.capsuleQueueKeyFor(
      controller.state.papers.first,
    );
    await tester.pumpWidget(
      RePaperTodoApp(controller: controller, store: store),
    );
    await tester.pumpAndSettle();
    final restoreCount = platform.paperWindows.restoredTitleSnapshots.length;
    final before = controller.state.papers
        .map((paper) => <Object?>[
              paper.isVisible,
              paper.isCollapsed,
              paper.isPinnedToDesktop,
              paper.x,
              paper.y,
              paper.width,
              paper.height,
            ])
        .toList();

    platform.paperWindows.emitAction(
      PaperWindowActionRequest(
        kind: PaperWindowActionKinds.toggleCollapseAll,
        paperId: 'collapse-all-master',
        value: queueKey,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.state.capsuleCollapseAllActive, false);
    expect(
      platform.paperWindows.restoredTitleSnapshots.length,
      greaterThan(restoreCount),
    );
    expect(store.savedState.capsuleCollapseAllActive, false);
    expect(
      controller.state.papers
          .map((paper) => <Object?>[
                paper.isVisible,
                paper.isCollapsed,
                paper.isPinnedToDesktop,
                paper.x,
                paper.y,
                paper.width,
                paper.height,
              ])
          .toList(),
      before,
    );

    controller.state.papers.last.isCollapsed = true;
    platform.paperWindows.emitAction(
      const PaperWindowActionRequest(
        kind: PaperWindowActionKinds.openPaper,
        paperId: 'collapse-all-peer',
        value: 'collapse-all-peer',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.state.papers.last.isCollapsed, false);
    expect(platform.paperWindows.shownTitles, contains('Peer'));
  });

  testWidgets('dragging a master capsule changes its queue start height',
      (tester) async {
    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final paper = PaperData(
      id: 'master-drag-paper',
      title: 'Master drag',
      isCollapsed: true,
      capsuleSide: DeepCapsuleSides.right,
    );
    final state = AppState(
      useCapsuleCollapseAll: true,
      papers: [paper],
    );
    final queueKey = state.capsuleQueueKeyFor(paper);
    final controller = RePaperTodoController(
      initialState: state,
      platform: platform,
    );
    await tester.pumpWidget(
      RePaperTodoApp(controller: controller, store: store),
    );

    platform.paperWindows.emitCapsuleDrop(
      const CapsuleDropRequest(
        paperId: 'master-drag-paper',
        monitorDeviceName: r'\\.\DISPLAY2',
        side: DeepCapsuleSides.left,
        dropTop: 220,
        workAreaTop: 40,
        isMasterCapsule: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.state.deepCapsuleQueueStartTopMargins[queueKey], 180);
    expect(paper.capsuleSide, DeepCapsuleSides.right);
    expect(store.savedState.deepCapsuleQueueStartTopMargins[queueKey], 180);
  });

  testWidgets('dragging edge capsules reassigns and reorders their queue',
      (tester) async {
    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleCollapseAll: true,
        papers: [
          PaperData(id: 'queue-first', title: 'First', isCollapsed: true),
          PaperData(id: 'queue-second', title: 'Second', isCollapsed: true),
          PaperData(id: 'queue-third', title: 'Third', isCollapsed: true),
        ],
      ),
      platform: platform,
    );
    await tester.pumpWidget(
      RePaperTodoApp(controller: controller, store: store),
    );

    platform.paperWindows.emitCapsuleDrop(
      const CapsuleDropRequest(
        paperId: 'queue-third',
        monitorDeviceName: '',
        side: DeepCapsuleSides.right,
        dropTop: 98,
        workAreaTop: 0,
        isMasterCapsule: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      controller.state.papers.map((paper) => paper.id),
      ['queue-third', 'queue-first', 'queue-second'],
    );
    expect(
      store.savedState.papers.map((paper) => paper.id),
      ['queue-third', 'queue-first', 'queue-second'],
    );
  });

  testWidgets('keeps local geometry when copied platform surface is invalid',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'invalid-surface-paper',
            type: PaperTypes.note,
            title: 'Invalid surface',
            x: 200,
            y: 220,
            width: 340,
            height: 380,
            content: 'Keep normalized geometry local.',
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

    platform.paperWindows.emitSurfaceUpdate(
      PaperData(
        id: 'invalid-surface-paper',
        type: PaperTypes.todo,
        title: 'Wrong surface type',
        x: double.nan,
        y: double.infinity,
        width: 12,
        height: 8,
        isVisible: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final paper = controller.state.papers.single;
    expect(paper.type, PaperTypes.note);
    expect(paper.title, 'Invalid surface');
    expect(paper.content, 'Keep normalized geometry local.');
    expect(paper.x, 200);
    expect(paper.y, 220);
    expect(paper.width, 340);
    expect(paper.height, 380);
    expect(paper.isVisible, false);
    expect(store.savedState.papers.single.x, 200);
    expect(store.savedState.papers.single.width, 340);
  });

  testWidgets('ignores stale platform surface updates for removed papers',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final savedPaper = PaperData(
      id: 'active-surface-paper',
      type: PaperTypes.todo,
      title: 'Active surface',
      items: [
        PaperItem(id: 'active-surface-item', text: 'Keep me'),
      ],
    );
    store.savedState = AppState(
      papers: [
        PaperData.fromJson(savedPaper.toJson()),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          savedPaper,
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
    final saveCountBeforeStaleUpdate = store.saveCount;

    platform.paperWindows.emitSurfaceUpdate(
      PaperData(
        id: 'stale-surface-paper',
        type: PaperTypes.note,
        title: 'Stale surface',
        isVisible: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.state.papers.map((paper) => paper.id), [
      'active-surface-paper',
    ]);
    expect(store.savedState.papers.map((paper) => paper.id), [
      'active-surface-paper',
    ]);
    expect(store.saveCount, saveCountBeforeStaleUpdate);
    expect(platform.tray.rebuildVisibilitySnapshots, isEmpty);
  });

  testWidgets('paper open requests toggle paper visibility like PaperTodo',
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

    platform.paperWindows.emitPaperOpenRequest('tray-open-hidden-paper');
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isVisible, false);
    expect(store.savedState.papers.single.isVisible, false);
    expect(platform.paperWindows.hiddenTitles, contains('Tray hidden'));
    expect(find.text('Tray hidden'), findsNothing);
  });

  testWidgets('ignores stale paper open and delete requests', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final savedPaper = PaperData(
      id: 'active-request-paper',
      type: PaperTypes.todo,
      title: 'Active request',
      items: [
        PaperItem(id: 'active-request-item', text: 'Stay put'),
      ],
    );
    store.savedState = AppState(
      papers: [
        PaperData.fromJson(savedPaper.toJson()),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          savedPaper,
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
    final saveCountBeforeRequests = store.saveCount;

    platform.paperWindows.emitPaperOpenRequest('stale-request-paper');
    platform.paperWindows.emitPaperDeleteRequest('stale-request-paper');
    await tester.pumpAndSettle();

    expect(controller.state.papers.map((paper) => paper.id), [
      'active-request-paper',
    ]);
    expect(controller.state.papers.single.isVisible, true);
    expect(controller.state.sync.isPaperDeleted('stale-request-paper'), false);
    expect(store.savedState.papers.map((paper) => paper.id), [
      'active-request-paper',
    ]);
    expect(store.saveCount, saveCountBeforeRequests);
    expect(platform.paperWindows.shownTitles, isEmpty);
    expect(platform.paperWindows.hiddenTitles, isEmpty);
    expect(platform.tray.rebuildVisibilitySnapshots, isEmpty);
    expect(find.textContaining('deleted.'), findsNothing);
  });

  testWidgets('paper delete requests delete with PaperTodo tray semantics',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        enableTodoNoteLinks: true,
        showLinkedNoteName: true,
        papers: [
          PaperData(
            id: 'tray-delete-todo',
            type: PaperTypes.todo,
            title: 'Tray todo',
            items: [
              PaperItem(
                id: 'tray-delete-item',
                text: 'Linked from tray',
                linkedNoteId: 'tray-delete-note',
              ),
            ],
          ),
          PaperData(
            id: 'tray-delete-note',
            type: PaperTypes.note,
            title: 'Tray note',
            content: 'Delete from tray.',
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

    platform.paperWindows.emitPaperDeleteRequest('tray-delete-note');
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Delete paper?'), findsNothing);
    expect(controller.state.papers.map((paper) => paper.id), [
      'tray-delete-todo',
    ]);
    expect(controller.state.papers.single.items.single.linkedNoteId, isNull);
    expect(controller.state.sync.isPaperDeleted('tray-delete-note'), true);
    expect(platform.paperWindows.hiddenTitles, contains('Tray note'));
    expect(find.text('Tray n deleted.'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(store.savedState.papers.map((paper) => paper.id), [
      'tray-delete-todo',
    ]);
  });

  testWidgets('deleting the last paper creates a visible default todo paper',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    final store = _MemoryStateStore();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'last-paper-delete',
            type: PaperTypes.note,
            title: 'Only note',
            content: 'The board must not become empty.',
            isCollapsed: true,
            isPinnedToDesktop: true,
            alwaysOnTop: true,
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

    platform.paperWindows.emitPaperDeleteRequest('last-paper-delete');
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump(const Duration(seconds: 1));

    final fallbackPaper = controller.state.papers.single;
    expect(fallbackPaper.id, isNot('last-paper-delete'));
    expect(fallbackPaper.type, PaperTypes.todo);
    expect(fallbackPaper.isVisible, true);
    expect(fallbackPaper.isCollapsed, false);
    expect(fallbackPaper.isPinnedToDesktop, false);
    expect(fallbackPaper.alwaysOnTop, false);
    expect(fallbackPaper.items, hasLength(1));
    expect(fallbackPaper.items.single.text, '');
    expect(fallbackPaper.items.single.done, false);
    expect(controller.state.sync.isPaperDeleted('last-paper-delete'), true);
    expect(controller.state.sync.isPaperDeleted(fallbackPaper.id), false);
    final fallbackPaperId = fallbackPaper.id;
    final fallbackPaperTitle = fallbackPaper.title;
    expect(platform.paperWindows.hiddenTitles, contains('Only note'));
    expect(platform.paperWindows.shownTitles, contains(fallbackPaperTitle));
    expect(find.textContaining('deleted.'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(store.savedState.papers, hasLength(1));
    expect(store.savedState.papers.single.id, fallbackPaperId);
    expect(store.savedState.papers.single.type, PaperTypes.todo);
    expect(store.savedState.papers.single.isVisible, true);

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

    expect(controller.state.papers, hasLength(1));
    expect(controller.state.papers.single.id, 'last-paper-delete');
    expect(controller.state.papers.single.type, PaperTypes.note);
    expect(controller.state.papers.single.content,
        'The board must not become empty.');
    expect(controller.state.sync.isPaperDeleted('last-paper-delete'), false);
    expect(controller.state.sync.isPaperDeleted(fallbackPaperId), true);
    expect(platform.paperWindows.hiddenTitles, contains(fallbackPaperTitle));
    expect(platform.paperWindows.shownTitles, contains('Only note'));
    expect(store.savedState.papers, hasLength(1));
    expect(store.savedState.papers.single.id, 'last-paper-delete');
    expect(store.savedState.sync.isPaperDeleted('last-paper-delete'), false);
    expect(store.savedState.sync.isPaperDeleted(fallbackPaperId), true);
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
    expect(find.text('Res…'), findsOneWidget);

    await tester.tap(find.text('Res…'));
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
    expect(find.text('Res…'), findsOneWidget);

    final todoRow = find.byKey(const ValueKey('todo-paper-todo-1-row'));
    await tester.tapAt(
      tester.getCenter(todoRow),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlink note').last);
    await tester.pumpAndSettle();

    expect(controller.state.papers.first.items.single.linkedNoteId, isNull);
    expect(find.text('Res…'), findsNothing);
  });

  testWidgets('links todo notes with PaperTodo undo and no-op semantics',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          PaperData(
            id: 'second-note',
            type: PaperTypes.note,
            title: 'Second note',
            content: 'More notes.',
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

    final todoField = find.descendant(
      of: find.byKey(const ValueKey('todo-paper-todo-1-text')),
      matching: find.byType(EditableText),
    );

    await tester.tap(todoField);
    await tester.pump();

    await tester.tap(find.byTooltip('Link note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Research note').last);
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.first.items.single.linkedNoteId,
      'note-paper',
    );
    expect(tester.widget<EditableText>(todoField).focusNode.hasFocus, true);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.first.items.single.linkedNoteId, isNull);

    await tester.tap(find.byTooltip('Redo todo change'));
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.first.items.single.linkedNoteId,
      'note-paper',
    );

    await tester.tap(find.byTooltip('Link note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Research note').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.first.items.single.linkedNoteId, isNull);

    await tester.tap(find.byTooltip('Redo todo change'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Link note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second note').last);
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.first.items.single.linkedNoteId,
      'second-note',
    );

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.first.items.single.linkedNoteId,
      'note-paper',
    );

    await tester.tap(find.byTooltip('Redo todo change'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Link note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlink note').last);
    await tester.pumpAndSettle();

    expect(controller.state.papers.first.items.single.linkedNoteId, isNull);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.first.items.single.linkedNoteId,
      'second-note',
    );
  });

  testWidgets('opens and unlinks linked notes from compact todo menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 0, y: 0, width: 900, height: 700);
    final controller = RePaperTodoController(
      initialState: AppState(
        showLinkedNoteName: true,
        papers: [
          PaperData(
            id: 'compact-todo',
            type: PaperTypes.todo,
            title: 'Compact reading',
            x: 100,
            y: 150,
            width: 280,
            items: [
              PaperItem(
                id: 'compact-item',
                text: 'Use compact linked menu',
                linkedNoteId: 'compact-note',
              ),
            ],
          ),
          PaperData(
            id: 'compact-note',
            type: PaperTypes.note,
            title: 'Compact note',
            content: 'Compact note content.',
            isVisible: false,
            isCollapsed: true,
            width: 320,
            height: 360,
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

    await tester.tap(find.byTooltip('Todo item actions'));
    await tester.pumpAndSettle();

    expect(find.text('Open linked note: Compact note'), findsOneWidget);
    expect(find.text('Unlink note'), findsOneWidget);

    await tester.tap(find.text('Unlink note').last);
    await tester.pumpAndSettle();

    expect(controller.state.papers.first.items.single.linkedNoteId, isNull);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(
      controller.state.papers.first.items.single.linkedNoteId,
      'compact-note',
    );

    await tester.tap(find.byTooltip('Todo item actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open linked note: Compact note').last);
    await tester.pumpAndSettle();

    final compactNote = controller.state.papers
        .firstWhere((paper) => paper.id == 'compact-note');
    expect(platform.paperWindows.shownTitles, contains('Compact note'));
    expect(platform.paperWindows.workAreaRequestIds, contains('compact-todo'));
    expect(compactNote.isVisible, true);
    expect(compactNote.isCollapsed, false);
    expect(compactNote.x, 390);
    expect(compactNote.y, 150);
  });

  testWidgets('drags note handles onto todo rows to link like PaperTodo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        showLinkedNoteName: true,
        papers: [
          PaperData(
            id: 'drag-note',
            type: PaperTypes.note,
            title: 'Drag source',
            content: 'Drag me to the todo row.',
          ),
          PaperData(
            id: 'drag-todo',
            type: PaperTypes.todo,
            title: 'Drag target',
            items: [
              PaperItem(id: 'drag-target-item', text: 'Receive note link'),
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

    final handle =
        find.byKey(const ValueKey('drag-note-note-link-drag-handle'));
    final row = find.byKey(const ValueKey('drag-todo-drag-target-item-row'));

    expect(handle, findsOneWidget);
    expect(row, findsOneWidget);

    await tester.dragFrom(
      tester.getCenter(handle),
      tester.getCenter(row) - tester.getCenter(handle),
    );
    await tester.pumpAndSettle();

    PaperItem linkedItem() => controller.state.papers
        .firstWhere((paper) => paper.id == 'drag-todo')
        .items
        .single;

    expect(linkedItem().linkedNoteId, 'drag-note');
    expect(find.text('Dra…'), findsOneWidget);

    await tester.tap(find.byTooltip('Undo todo change'));
    await tester.pumpAndSettle();

    expect(linkedItem().linkedNoteId, isNull);
    expect(find.text('Dra…'), findsNothing);
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

    await tester.tap(find.text('⚡Bui…'));
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
    await tester.pumpAndSettle();

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

  testWidgets('independent paper capsule routes script clicks to coordinator',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = RePaperTodoController(
      initialState: AppState(
        maxTitleLength: 20,
        papers: [
          PaperData(
            id: 'independent-script-note',
            type: PaperTypes.note,
            title: 'Deploy script',
            content: '!pf\n  Start-Sleep -Seconds 20',
            isCollapsed: true,
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );
    final actions = <String>[];

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: 'independent-script-note',
        paperWindowMode: true,
        paperWindowActionSender: (kind, {value = ''}) async {
          actions.add(kind);
        },
      ),
    );
    await tester.pumpAndSettle();

    final capsule = find.byKey(
      const ValueKey('independent-script-note-paper-window-capsule'),
    );
    expect(capsule, findsOneWidget);

    tester.widget<InkWell>(capsule).onTap!.call();
    await tester.pump();

    expect(actions, [PaperWindowActionKinds.runScriptCapsule]);
    expect(controller.state.papers.single.isCollapsed, true);

    tester.widget<InkWell>(capsule).onSecondaryTap!.call();
    await tester.pumpAndSettle();

    expect(actions, [
      PaperWindowActionKinds.runScriptCapsule,
      PaperWindowActionKinds.expandPaper,
    ]);
    expect(controller.state.papers.single.isCollapsed, true,
        reason: 'the child engine must wait for coordinator state');
  });

  testWidgets('independent paper capsule has a dedicated hide area',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(92, 46));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final paper = PaperData(
      id: 'independent-hide-capsule',
      type: PaperTypes.todo,
      title: 'Hide',
      isCollapsed: true,
      items: [PaperItem(id: 'hide-item', text: 'Hide this paper')],
    );
    final controller = RePaperTodoController(
      initialState: AppState(papers: [paper]),
      platform: NoopPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
      ),
    );
    await tester.pumpAndSettle();

    final capsuleSurface = find.byKey(
      const ValueKey(
        'independent-hide-capsule-paper-window-capsule-surface',
      ),
    );
    expect(tester.getRect(capsuleSurface), const Rect.fromLTWH(8, 8, 76, 30));
    final capsuleDecoration =
        tester.widget<DecoratedBox>(capsuleSurface).decoration as BoxDecoration;
    expect(capsuleDecoration.borderRadius, BorderRadius.circular(12));
    expect(capsuleDecoration.boxShadow, hasLength(1));
    expect(capsuleDecoration.boxShadow!.single.blurRadius, 8);
    expect(capsuleDecoration.boxShadow!.single.color.a, closeTo(0.08, 0.001));
    final capsuleIcon = tester.widget<Text>(
      find.descendant(of: capsuleSurface, matching: find.text('\u2713')),
    );
    expect(capsuleIcon.style?.fontFamily, 'Segoe UI Symbol');
    expect(capsuleIcon.style?.fontSize, 13);
    expect(find.text('Hide'), findsOneWidget,
        reason: 'source capsule metrics preserve a short title in full');

    final dragHandle = find.byKey(
      const ValueKey('independent-hide-capsule-capsule-drag-handle'),
    );
    expect(tester.getSize(dragHandle).width, 26,
        reason: 'visual glyph metrics must not shrink the drag target');

    final close = find.byKey(
      const ValueKey('independent-hide-capsule-paper-window-capsule-close'),
    );
    expect(close, findsOneWidget);
    expect(tester.getSize(close).width, 21);
    final closeGlyph = tester.widget<Text>(
      find.descendant(of: close, matching: find.text('\u00D7')),
    );
    expect(closeGlyph.style?.fontFamily, 'Segoe UI Symbol');
    expect(closeGlyph.style?.fontSize, 18);
    final closeOffset = tester.widget<Transform>(
      find.ancestor(of: find.text('\u00D7'), matching: find.byType(Transform)),
    );
    expect(closeOffset.transform.getTranslation().x, -1);
    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(paper.isVisible, false);
  });

  testWidgets('independent todo capsule delegates one expand and starts drag',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(126, 46));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final paper = PaperData(
      id: 'delegated-expand-capsule',
      title: 'Expand once',
      isCollapsed: true,
      items: [PaperItem(id: 'delegated-item', text: 'Open once')],
    );
    final actions = <String>[];
    var dragStarts = 0;

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: RePaperTodoController(
          initialState: AppState(papers: [paper]),
          platform: NoopPlatformServices(),
        ),
        store: _MemoryStateStore(),
        initialSurfacePaperId: paper.id,
        paperWindowMode: true,
        paperWindowActionSender: (kind, {value = ''}) async {
          actions.add(kind);
        },
        paperWindowDragStarter: () async => dragStarts += 1,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
      const ValueKey('delegated-expand-capsule-paper-window-capsule'),
    ));
    await tester.pump();
    expect(actions, [PaperWindowActionKinds.expandPaper]);
    expect(paper.isCollapsed, true,
        reason: 'the child engine must wait for coordinator state');

    final gesture = await tester.press(find.byKey(
      const ValueKey('delegated-expand-capsule-capsule-drag-handle'),
    ));
    await tester.pump();
    await gesture.up();
    expect(dragStarts, 1);
  });

  testWidgets('collapse-all master never replaces a real paper surface',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleCollapseAll: true,
        capsuleCollapseAllActive: true,
        papers: [
          PaperData(
            id: 'master-capsule-paper',
            title: 'Master source',
            capsuleSide: DeepCapsuleSides.right,
          ),
          PaperData(
            id: 'retracted-capsule-paper',
            title: 'Retracted source',
            capsuleSide: DeepCapsuleSides.right,
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );
    final actions = <String>[];

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: _MemoryStateStore(),
        initialSurfacePaperId: 'master-capsule-paper',
        paperWindowMode: true,
        paperWindowActionSender: (kind, {value = ''}) async {
          actions.add(kind);
        },
      ),
    );
    await tester.pumpAndSettle();

    final legacyMaster = find.byKey(
      const ValueKey('master-capsule-paper-paper-window-master-capsule'),
    );
    expect(legacyMaster, findsNothing);
    expect(find.byType(PaperPreview), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.controller.text == 'Master source',
      ),
      findsOneWidget,
    );
    expect(actions, isEmpty);
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

    await tester.tap(find.text('⚡Fai…'));
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

    await tester.tap(find.text('⚡Bad…'));
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

    expect(find.text('Ver…'), findsOneWidget);
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

Future<void> _pressShiftShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

Future<void> _selectSettingsCategory(
  WidgetTester tester,
  String category,
) async {
  await tester.tap(
    find.byKey(ValueKey('settings-category-$category')),
  );
  await tester.pumpAndSettle();
}

Finder _settingsToggleTile(String label) {
  return find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_SettingsCheckboxTile',
        ),
      )
      .first;
}

String _testColorHex(Color color) {
  String channel(double value) =>
      (value * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}'
      .toUpperCase();
}

Future<void> _captureSettingsHotKey(
  WidgetTester tester,
  String fieldLabel,
  LogicalKeyboardKey key, {
  List<LogicalKeyboardKey> modifiers = const [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.altLeft,
  ],
}) async {
  final fieldKey = switch (fieldLabel) {
    'Pinned todo hotkey' => 'settings-pinned-todo-hotkey',
    'Pinned note hotkey' => 'settings-pinned-note-hotkey',
    _ => throw ArgumentError.value(fieldLabel, 'fieldLabel'),
  };
  await tester.tap(find.byKey(ValueKey(fieldKey)));
  await tester.pump();
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

Future<void> _enterNoteEditor(WidgetTester tester, String paperId) async {
  final preview = find.byKey(ValueKey('$paperId-preview'));
  await tester.ensureVisible(preview);
  await tester.pump();
  tester.widget<GestureDetector>(preview).onTap?.call();
  await tester.pump();
  await tester.pump();
  expect(find.byKey(ValueKey('$paperId-content')), findsOneWidget);
}

TextSpan _markdownTextSpan(WidgetTester tester, String text) {
  for (final selectable
      in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
    final textSpan = selectable.textSpan;
    if (textSpan == null) {
      continue;
    }
    final match = _findTextSpan(textSpan, text);
    if (match != null) {
      return match;
    }
  }
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final textSpan = widget.textSpan;
    if (textSpan == null) {
      continue;
    }
    final match = _findTextSpan(textSpan, text);
    if (match != null) {
      return match;
    }
  }
  throw TestFailure('Could not find markdown text span "$text".');
}

Future<void> _activateSourceMarkdownLink(
  WidgetTester tester,
  String label,
) async {
  final source = find.byType(PaperTodoMarkdownSourcePreview);
  final span = _sourceMarkdownTextSpan(tester, source, label);
  expect(span.recognizer, isA<TapGestureRecognizer>());
  (span.recognizer! as TapGestureRecognizer).onTap?.call();
  await tester.pump();
}

void _expectSourceMarkdownLinkDisabled(
  WidgetTester tester,
  String label,
) {
  final source = find.byType(PaperTodoMarkdownSourcePreview);
  final span = _sourceMarkdownTextSpan(tester, source, label);
  expect(span.recognizer, isNull);
}

TextSpan _sourceMarkdownTextSpan(
  WidgetTester tester,
  Finder source,
  String text,
) {
  for (final widget in tester.widgetList<Text>(
    find.descendant(of: source, matching: find.byType(Text)),
  )) {
    final textSpan = widget.textSpan;
    if (textSpan == null) {
      continue;
    }
    final match = _findTextSpan(textSpan, text);
    if (match != null) {
      return match;
    }
  }
  throw TestFailure('Could not find source markdown text span "$text".');
}

TextSpan? _findTextSpan(InlineSpan span, String text) {
  if (span is! TextSpan) {
    return null;
  }
  final spanText = span.text;
  if (spanText == text || (spanText?.contains(text) ?? false)) {
    return span;
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    final match = _findTextSpan(child, text);
    if (match != null) {
      return match;
    }
  }
  return null;
}

Iterable<TextSpan> _allTextSpans(InlineSpan span) sync* {
  if (span is! TextSpan) {
    return;
  }
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _allTextSpans(child);
  }
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
  }) : super(deviceIdStore: const _FixedSyncDeviceIdStore());

  final List<WebDavSnapshotRecord> snapshots;
  final AppState restoredState;
  final Object? firstListError;
  final Object? firstRestoreError;
  final AppSyncStatus restoreStatus;
  final String restoreMessage;
  final bool includeRestoredState;
  final restoredPaths = <String>[];
  final localUploadBeforeTitles = <String>[];
  final localUploadAfterTitles = <String>[];
  var listCalls = 0;
  var restoreCalls = 0;
  var localUploadCalls = 0;

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

  @override
  Future<AppSyncLocalOperationUploadResult> uploadLocalOperations({
    required AppState beforeState,
    required AppState afterState,
    required StateStore store,
    DateTime? createdAtUtc,
  }) async {
    localUploadCalls += 1;
    localUploadBeforeTitles.add(beforeState.papers.single.title);
    localUploadAfterTitles.add(afterState.papers.single.title);
    await store.save(afterState);
    return AppSyncLocalOperationUploadResult(
      state: afterState,
      deviceSequences: afterState.sync.operationDeviceSequences,
      generatedCount: 1,
      uploadedCount: 1,
      stateChanged: false,
    );
  }
}

class _ManualSyncService extends AppSyncService {
  _ManualSyncService({
    required this.result,
    this.firstSyncGate,
    this.firstLocalUploadGate,
    this.firstSyncError,
    this.firstLocalUploadError,
    this.localUploadState,
    this.localUploadUploadedCount = 1,
    this.localUploadStateChanged = false,
    this.recoverySnapshots = const <WebDavSnapshotRecord>[],
    this.prepareDurableBatch = false,
  }) : super(deviceIdStore: const _FixedSyncDeviceIdStore());

  final AppSyncRunResult result;
  final Future<void>? firstSyncGate;
  final Future<void>? firstLocalUploadGate;
  final Object? firstSyncError;
  final Object? firstLocalUploadError;
  final AppState? localUploadState;
  final int localUploadUploadedCount;
  final bool localUploadStateChanged;
  final List<WebDavSnapshotRecord> recoverySnapshots;
  final bool prepareDurableBatch;
  var calls = 0;
  var localUploadCalls = 0;
  var listRecoveryCalls = 0;
  final events = <String>[];
  final localUploadBeforeTitles = <String>[];
  final localUploadAfterTitles = <String>[];
  final syncLocalDeviceSequences = <Map<String, int>>[];
  final syncPendingBatchDeviceIds = <String?>[];

  @override
  Future<AppState> preparePendingLocalOperationBatch({
    required AppState beforeState,
    required AppState afterState,
    required StateStore store,
    DateTime? createdAtUtc,
  }) {
    if (!prepareDurableBatch) {
      return Future.value(AppState.fromJson(afterState.toJson()));
    }
    return super.preparePendingLocalOperationBatch(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: createdAtUtc,
    );
  }

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
    syncPendingBatchDeviceIds.add(
      localState.sync.pendingOperationBatch?.deviceId,
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
    final gate = firstLocalUploadGate;
    if (localUploadCalls == 1 && gate != null) {
      await gate;
    }
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

class _ThrowingPendingPreparationSyncService extends AppSyncService {
  var prepareCalls = 0;

  @override
  Future<AppState> preparePendingLocalOperationBatch({
    required AppState beforeState,
    required AppState afterState,
    required StateStore store,
    DateTime? createdAtUtc,
  }) async {
    prepareCalls += 1;
    throw StateError('Unable to prepare the pending operation batch.');
  }
}

PendingSyncOperationBatch _pendingSyncBatchForTest({
  required String deviceId,
  required String title,
  required int startSequence,
}) {
  return PendingSyncOperationBatch(
    baseState: AppState(
      papers: [
        PaperData(
          id: 'pending-batch-base-note',
          type: PaperTypes.note,
          title: title,
          content: 'Batch base body',
        ),
      ],
    ).toJson(),
    deviceId: deviceId,
    startSequence: startSequence,
    createdAtUtc: DateTime.utc(2026, 7, 11, 8, startSequence),
  );
}

class _FixedSyncDeviceIdStore extends SyncDeviceIdStore {
  const _FixedSyncDeviceIdStore()
      : super(filePath: 'build/test-widget-fixed-sync-device-id');

  @override
  Future<String> loadOrCreate() async => 'device-widget-test';
}

Future<void> _waitForSavedTrayTitle(
  WidgetTester tester,
  _RecordingPlatformServices platform,
  String title,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump();
    if (platform.tray.rebuildTitleSnapshots.isNotEmpty &&
        platform.tray.rebuildTitleSnapshots.last.single == title) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Timed out waiting for the local state save to finish.');
}

class _MemoryStateStore extends StateStore {
  _MemoryStateStore() : super(filePath: 'memory-state.json');

  final _codec = const AppStateCodec();
  AppState savedState = AppState();
  var saveCount = 0;
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
    saveCount += 1;
    savedState = _codec.decode(_codec.encode(state));
  }
}

class _RecordingPlatformServices implements PlatformServices {
  _RecordingPlatformServices({
    StartupHost? startup,
    AppStorageHost? storage,
    bool supportsStartupAtLogin = true,
    bool supportsDesktopIntegration = true,
    List<String> installedFontFamilies = const [],
  })  : startup = startup ?? NoopStartupHost(),
        storage = storage ?? _RecordingAppStorageHost(),
        systemIntegration = _RecordingSystemIntegrationHost(
          supportsStartupAtLogin: supportsStartupAtLogin,
          supportsWindowSwitcherVisibility: supportsDesktopIntegration,
          supportsFullscreenTopmostMode: supportsDesktopIntegration,
          supportsGlobalHotkeys: supportsDesktopIntegration,
          installedFontFamilies: installedFontFamilies,
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
  final AppStorageHost storage;
}

class _RecordingAppStorageHost implements AppStorageHost {
  @override
  bool get supportsDataDirectorySelection => false;

  @override
  Future<String> documentsDirectoryPath() async {
    return Directory('build/test-widget-storage').absolute.path;
  }

  @override
  Future<String?> chooseDataDirectory(String currentDirectoryPath) async =>
      null;

  @override
  Future<void> commitDataDirectory(String directoryPath) async {}
}

class _SelectableAppStorageHost implements AppStorageHost {
  _SelectableAppStorageHost(this.selectedDirectory);

  final String selectedDirectory;
  final committedDirectories = <String>[];

  @override
  bool get supportsDataDirectorySelection => true;

  @override
  Future<String> documentsDirectoryPath() async => selectedDirectory;

  @override
  Future<String?> chooseDataDirectory(String currentDirectoryPath) async =>
      selectedDirectory;

  @override
  Future<void> commitDataDirectory(String directoryPath) async {
    committedDirectories.add(directoryPath);
  }
}

class _RecordingTrayHost extends NoopTrayHost {
  var disposeCount = 0;
  final rebuildTitleSnapshots = <List<String>>[];
  final rebuildVisibilitySnapshots = <Map<String, bool>>[];
  final rebuildSurfaceModeSnapshots = <Map<String, Map<String, bool>>>[];

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }

  @override
  Future<void> rebuildMenu(AppState state, {TrayMenuLabels? labels}) async {
    rebuildTitleSnapshots.add(
      state.papers.map((paper) => paper.title).toList(),
    );
    rebuildVisibilitySnapshots.add({
      for (final paper in state.papers) paper.id: paper.isVisible,
    });
    rebuildSurfaceModeSnapshots.add({
      for (final paper in state.papers)
        paper.id: {
          'pinned': paper.isPinnedToDesktop,
          'topmost': paper.alwaysOnTop,
        },
    });
  }
}

class _RecordingPaperWindowHost extends NoopPaperWindowHost {
  final restoredTitleSnapshots = <List<String>>[];
  final updatedTitles = <String>[];
  final shownTitles = <String>[];
  final hiddenTitles = <String>[];
  final workAreaRequestIds = <String>[];
  final _surfaceUpdates = StreamController<PaperData>.broadcast();
  final _paperEdits = StreamController<PaperData>.broadcast();
  final _actionRequests =
      StreamController<PaperWindowActionRequest>.broadcast();
  final _capsuleDrops = StreamController<CapsuleDropRequest>.broadcast();
  final _paperOpenRequests = StreamController<String>.broadcast();
  final _paperDeleteRequests = StreamController<String>.broadcast();
  PaperWorkArea? workArea;

  @override
  Stream<PaperData> get surfaceUpdates => _surfaceUpdates.stream;

  @override
  Stream<PaperData> get paperEdits => _paperEdits.stream;

  @override
  Stream<PaperWindowActionRequest> get actionRequests => _actionRequests.stream;

  @override
  Stream<CapsuleDropRequest> get capsuleDrops => _capsuleDrops.stream;

  @override
  Stream<String> get paperOpenRequests => _paperOpenRequests.stream;

  @override
  Stream<String> get paperDeleteRequests => _paperDeleteRequests.stream;

  void emitSurfaceUpdate(PaperData paper) {
    _surfaceUpdates.add(paper);
  }

  void emitPaperEdit(PaperData paper) {
    _paperEdits.add(paper);
  }

  void emitAction(PaperWindowActionRequest request) {
    _actionRequests.add(request);
  }

  void emitCapsuleDrop(CapsuleDropRequest request) {
    _capsuleDrops.add(request);
  }

  void emitPaperOpenRequest(String paperId) {
    _paperOpenRequests.add(paperId);
  }

  void emitPaperDeleteRequest(String paperId) {
    _paperDeleteRequests.add(paperId);
  }

  @override
  Future<void> restoreAll(AppState state) async {
    restoredTitleSnapshots.add(
      state.papers.map((paper) => paper.title).toList(),
    );
  }

  @override
  Future<PaperWorkArea?> workAreaForPaper(PaperData paper) async {
    workAreaRequestIds.add(paper.id);
    return workArea;
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

String _formatReminderTimestamp(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

String _formatAbsoluteDueLabelForTest(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(local.year, local.month, local.day);
  final time = '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  if (dueDay == today) {
    return time;
  }
  if (dueDay == today.add(const Duration(days: 1))) {
    return 'Tomorrow $time';
  }
  return '${local.month}/${local.day} $time';
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
    required List<String> installedFontFamilies,
  }) : _installedFontFamilies = installedFontFamilies;

  @override
  final bool supportsStartupAtLogin;

  @override
  final bool supportsWindowSwitcherVisibility;

  @override
  final bool supportsFullscreenTopmostMode;

  @override
  final bool supportsGlobalHotkeys;

  final List<String> _installedFontFamilies;

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
  Future<List<String>> installedFontFamilies() async {
    return _installedFontFamilies;
  }

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
