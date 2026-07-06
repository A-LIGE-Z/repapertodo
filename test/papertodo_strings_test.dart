import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/app_controller.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
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
}
