import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/app_controller.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/note_canvas_element.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/model/paper_item.dart';
import 'package:repapertodo/src/core/storage/state_store.dart';
import 'package:repapertodo/src/platform/noop_platform_services.dart';
import 'package:repapertodo/src/ui/papertodo_strings.dart';

void main() {
  test('resolves supported system languages and falls back to English', () {
    expect(
      PaperTodoStrings.resolveLocale(
        const Locale('zh', 'CN'),
        PaperTodoStrings.supportedLocales,
      ),
      const Locale('zh'),
    );
    expect(
      PaperTodoStrings.resolveLocale(
        const Locale('ja', 'JP'),
        PaperTodoStrings.supportedLocales,
      ),
      const Locale('ja'),
    );
    expect(
      PaperTodoStrings.resolveLocale(
        const Locale('ko', 'KR'),
        PaperTodoStrings.supportedLocales,
      ),
      const Locale('ko'),
    );
    expect(
      PaperTodoStrings.resolveLocale(
        const Locale('fr', 'FR'),
        PaperTodoStrings.supportedLocales,
      ),
      const Locale('en'),
    );
  });

  test('looks up localized strings and preserves unknown keys', () {
    final zh = PaperTodoStrings.resolve(const Locale('zh'));
    final fr = PaperTodoStrings.resolve(const Locale('fr'));

    expect(zh.get(PaperTodoStringKeys.dialogSyncSettings), '同步设置');
    expect(zh.get(PaperTodoStringKeys.webDavIssueSummary), contains('WebDAV'));
    expect(fr.get(PaperTodoStringKeys.dialogSyncSettings), 'Sync settings');
    expect(fr.format(PaperTodoStringKeys.syncFailed, ['timeout']),
        'Sync failed: timeout');
    expect(zh.get('unknown.key'), 'unknown.key');
  });

  testWidgets('uses Chinese system locale for primary settings UI',
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

    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        papers: [
          PaperData(
            id: 'localized-settings-paper',
            type: PaperTypes.todo,
            title: 'Locale smoke',
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: StateStore(filePath: 'build/test-localized-settings.json'),
      ),
    );

    expect(find.text('RePaperTodo'), findsWidgets);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('同步设置'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('WebDAV 同步'), findsOneWidget);
    expect(find.text('Sync settings'), findsNothing);
  });

  testWidgets('uses Chinese system locale for paper and todo actions',
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

    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        papers: [
          PaperData(
            id: 'localized-todo-paper',
            type: PaperTypes.todo,
            title: '中文待办',
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: StateStore(filePath: 'build/test-localized-actions.json'),
      ),
    );

    expect(find.byTooltip('打开纸片窗口'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '添加事项'), findsOneWidget);
    expect(find.byTooltip('撤销待办更改'), findsOneWidget);
    expect(find.byTooltip('删除纸片'), findsOneWidget);
    expect(find.byTooltip('Open paper surface'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Add item'), findsNothing);

    await tester.tap(find.byTooltip('删除纸片'));
    await tester.pumpAndSettle();

    expect(find.text('删除纸片？'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '删除'), findsOneWidget);
    expect(find.text('Delete paper?'), findsNothing);
  });

  testWidgets('uses Chinese system locale for editor feedback', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
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

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.enhanced,
        theme: 'light',
        papers: [
          PaperData(
            id: 'localized-editor-todo-paper',
            type: PaperTypes.todo,
            title: '中文编辑',
            items: [
              PaperItem(
                id: 'localized-editor-todo-item',
                todoColumnCount: 2,
                todoExtraColumns: [''],
                todoColumnWidths: [1, 1],
              ),
            ],
          ),
          PaperData(
            id: 'localized-editor-note-paper',
            type: PaperTypes.note,
            title: '中文笔记',
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: StateStore(filePath: 'build/test-localized-editor.json'),
      ),
    );

    expect(find.text('第 1 列'), findsOneWidget);
    expect(find.text('第 2 列'), findsOneWidget);
    expect(find.text('新事项'), findsOneWidget);
    expect(find.text('编辑'), findsWidgets);
    expect(find.text('预览'), findsWidgets);
    expect(find.text('分栏'), findsOneWidget);
    expect(find.textContaining('暂无笔记内容'), findsOneWidget);
    expect(find.text('Column 1'), findsNothing);
    expect(find.text('New item'), findsNothing);
    expect(find.text('Edit'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('localized-editor-note-paper-preview')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('localized-editor-note-paper-content')),
        findsOneWidget);
    expect(find.text('写点笔记...'), findsOneWidget);
    expect(find.text('Write a note...'), findsNothing);
  });

  testWidgets('uses Chinese system locale for markdown and canvas tools',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
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

    final controller = RePaperTodoController(
      initialState: AppState(
        markdownRenderMode: MarkdownRenderModes.off,
        theme: 'light',
        papers: [
          PaperData(
            id: 'localized-canvas-note-paper',
            type: PaperTypes.note,
            title: '中文画布',
            content: '画布正文',
            noteCanvasElements: [
              NoteCanvasElement(
                id: 'localized-canvas-code',
                type: NoteCanvasElementTypes.code,
                text: 'Console.WriteLine("PaperTodo");',
                x: 24,
                y: 24,
                width: 220,
                height: 120,
                zIndex: 1,
              ),
              NoteCanvasElement(
                id: 'localized-canvas-text',
                type: NoteCanvasElementTypes.text,
                text: '画布想法',
                x: 280,
                y: 24,
                width: 220,
                height: 120,
                zIndex: 2,
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
        store: StateStore(filePath: 'build/test-localized-canvas.json'),
      ),
    );

    expect(find.byTooltip('加粗 (Ctrl+B)'), findsOneWidget);
    expect(find.byTooltip('斜体 (Ctrl+I)'), findsOneWidget);
    expect(find.byTooltip('插入链接 (Ctrl+K)'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '添加画布块'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '添加文本块'), findsOneWidget);
    expect(find.text('代码'), findsOneWidget);
    expect(find.text('文本'), findsOneWidget);
    expect(find.text('层级 1'), findsOneWidget);
    expect(find.text('顶层 2'), findsOneWidget);
    expect(find.byTooltip('拖动画布块'), findsWidgets);
    expect(find.byTooltip('编辑画布几何参数'), findsWidgets);
    expect(find.byTooltip('复制画布块'), findsWidgets);
    expect(find.byTooltip('画布层级操作'), findsWidgets);
    expect(find.byTooltip('删除画布块'), findsWidgets);
    expect(find.byTooltip('调整画布块大小'), findsWidgets);
    expect(find.byTooltip('Bold (Ctrl+B)'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Add canvas block'), findsNothing);

    await tester.tap(find.byTooltip('编辑画布几何参数').first);
    await tester.pumpAndSettle();

    expect(find.text('画布块几何参数'), findsOneWidget);
    expect(find.text('宽度'), findsOneWidget);
    expect(find.text('高度'), findsOneWidget);
    expect(find.text('层级'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
    expect(find.text('Canvas block geometry'), findsNothing);
  });
}
