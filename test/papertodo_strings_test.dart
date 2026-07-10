import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/app_controller.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/note_canvas_element.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/model/paper_item.dart';
import 'package:repapertodo/src/core/model/sync_settings.dart';
import 'package:repapertodo/src/core/storage/state_store.dart';
import 'package:repapertodo/src/platform/noop_platform_services.dart';
import 'package:repapertodo/src/sync/app_sync_service.dart';
import 'package:repapertodo/src/sync/webdav/webdav_state_sync_service.dart';
import 'package:repapertodo/src/ui/papertodo_strings.dart';

void main() {
  test('exposes Chinese and English and falls back to English', () {
    expect(
      PaperTodoStrings.supportedLocales,
      const [Locale('zh'), Locale('en')],
    );
    expect(
      PaperTodoStrings.resolveLocale(
        const Locale('zh', 'CN'),
        PaperTodoStrings.supportedLocales,
      ),
      const Locale('zh'),
    );
    expect(
      PaperTodoStrings.resolveLocale(
        const Locale('en', 'US'),
        PaperTodoStrings.supportedLocales,
      ),
      const Locale('en'),
    );
    expect(
      PaperTodoStrings.resolveLocale(
        const Locale('zz', 'TEST'),
        PaperTodoStrings.supportedLocales,
      ),
      const Locale('en'),
    );
    expect(
      PaperTodoStrings.resolveLocale(
        const Locale('zz', 'TEST'),
        const [Locale('zz'), Locale('zh'), Locale('en')],
      ),
      const Locale('en'),
    );
    expect(
      PaperTodoStrings.resolveLocale(
        const Locale('zh', 'CN'),
        const [Locale('zz'), Locale('zh', 'CN'), Locale('en')],
      ),
      const Locale('zh'),
    );
    expect(
      PaperTodoStrings.resolveLocale(
        null,
        PaperTodoStrings.supportedLocales,
      ),
      const Locale('en'),
    );
  });

  test('looks up localized strings and preserves unknown keys', () {
    final zh = PaperTodoStrings.resolve(const Locale('zh'));
    final unsupported = PaperTodoStrings.resolve(const Locale('zz'));

    expect(zh.get(PaperTodoStringKeys.dialogSyncSettings), '同步设置');
    expect(zh.get(PaperTodoStringKeys.webDavIssueSummary), contains('WebDAV'));
    expect(zh.get(PaperTodoStringKeys.menuFormat), '格式');
    expect(zh.get(PaperTodoStringKeys.menuText), '文本');
    expect(zh.get(PaperTodoStringKeys.menuTodoItem), '事项');
    expect(zh.get(PaperTodoStringKeys.actionCollapseToCapsule), '折叠为胶囊');
    expect(zh.get(PaperTodoStringKeys.actionRestoreWindow), '恢复窗口');
    expect(zh.get(PaperTodoStringKeys.actionResetTextZoom), '点击恢复为 100%');
    expect(zh.get(PaperTodoStringKeys.actionEditTitle), '点击编辑标题');
    expect(zh.get(PaperTodoStringKeys.actionHideThisPaper), '隐藏这张纸');
    expect(
      zh.format(
        PaperTodoStringKeys.actionOpenMarkdownInDefaultEditor,
        ['.md'],
      ),
      '用默认 .md 编辑器打开',
    );
    expect(unsupported.get(PaperTodoStringKeys.menuDesktopPin), 'Desktop pin');
    expect(unsupported.get(PaperTodoStringKeys.actionCollapseToCapsule),
        'Collapse to capsule');
    expect(unsupported.get(PaperTodoStringKeys.actionRestoreWindow),
        'Restore window');
    expect(unsupported.get(PaperTodoStringKeys.actionResetTextZoom),
        'Click to reset to 100%');
    expect(unsupported.get(PaperTodoStringKeys.actionEditTitle),
        'Click to edit title');
    expect(unsupported.get(PaperTodoStringKeys.actionHideThisPaper),
        'Hide this paper');
    expect(
      unsupported.format(
        PaperTodoStringKeys.actionOpenMarkdownInDefaultEditor,
        ['.md'],
      ),
      'Open in default .md editor',
    );
    expect(
      zh.get(PaperTodoStringKeys.syncSnapshotRestoredLegacyPlainNextUpload),
      contains('旧版明文 WebDAV 数据'),
    );
    expect(unsupported.get(PaperTodoStringKeys.dialogSyncSettings),
        'Sync settings');
    expect(unsupported.format(PaperTodoStringKeys.syncFailed, ['timeout']),
        'Sync failed: timeout');
    expect(
      unsupported
          .get(PaperTodoStringKeys.syncSnapshotRestoredLegacyPlainNextUpload),
      contains('legacy plain WebDAV data'),
    );
    expect(
      zh.get(PaperTodoStringKeys.platformOpenUriFailed),
      '无法打开链接。',
    );
    expect(
      zh.get(PaperTodoStringKeys.platformOpenExternalFileFailed),
      '无法打开外部文件。',
    );
    expect(
      unsupported.get(PaperTodoStringKeys.platformOpenUriFailed),
      'Unable to open the URI.',
    );
    expect(
      unsupported.get(PaperTodoStringKeys.platformInvalidPath),
      'The file path is invalid or outside the RePaperTodo share folders.',
    );
    expect(zh.get('unknown.key'), 'unknown.key');
  });

  test('looks up localized Windows tray menu strings', () {
    final en = PaperTodoStrings.resolve(const Locale('en'));
    final zh = PaperTodoStrings.resolve(const Locale('zh'));
    final unsupported = PaperTodoStrings.resolve(const Locale('zz'));

    expect(en.get(PaperTodoStringKeys.trayNewTodo), '+ New todo paper');
    expect(en.get(PaperTodoStringKeys.trayHideAll), 'Hide all papers');
    expect(en.get(PaperTodoStringKeys.trayInlineConfirmDelete), '⚠ Delete');
    expect(en.get(PaperTodoStringKeys.trayInlineConfirmAction), 'Confirm');
    expect(
        zh.get(PaperTodoStringKeys.trayInlineConfirmDelete), startsWith('⚠ '));
    expect(zh.get(PaperTodoStringKeys.trayInlineConfirmAction), isNotEmpty);
    expect(unsupported.get(PaperTodoStringKeys.trayInlineConfirmDelete),
        startsWith('⚠ '));
    expect(unsupported.get(PaperTodoStringKeys.trayInlineConfirmAction),
        'Confirm');
    expect(zh.get(PaperTodoStringKeys.trayNewTodo), '＋ 新建待办纸');
    expect(zh.get(PaperTodoStringKeys.trayPapers), '纸片');
    expect(
        unsupported.get(PaperTodoStringKeys.trayNewTodo), '+ New todo paper');
    expect(unsupported.get(PaperTodoStringKeys.trayHideAll), 'Hide all papers');
    expect(unsupported.get(PaperTodoStringKeys.trayPapers), 'Papers');
    expect(
      zh.format(PaperTodoStringKeys.trayDeleteConfirmMessage, ['X']),
      '删除“X”？',
    );
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
                type: 'text',
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
    expect(find.widgetWithText(TextButton, '添加文本块'), findsNothing);
    expect(find.text('代码'), findsNWidgets(2));
    expect(find.text('文本'), findsNothing);
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

  testWidgets('uses Chinese system locale for recovery snapshots',
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
            id: 'localized-recovery-paper',
            type: PaperTypes.todo,
            title: '本地待办',
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );
    final syncService = _LocalizedRecoverySnapshotSyncService(
      firstRestoreError: TimeoutException('Snapshot restore timed out.'),
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
            id: 'localized-restored-paper',
            type: PaperTypes.note,
            title: '远端快照',
            content: '恢复后的内容',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: StateStore(filePath: 'build/test-localized-recovery.json'),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('恢复快照'));
    await tester.pumpAndSettle();

    expect(find.text('恢复快照'), findsOneWidget);
    expect(find.textContaining('phone'), findsWidgets);
    expect(find.textContaining('2.0 KiB'), findsOneWidget);
    expect(find.textContaining('修改于'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '恢复'), findsOneWidget);
    expect(find.text('Recovery snapshots'), findsNothing);

    await tester.tap(find.byKey(const ValueKey(
      'restore-snapshot-repapertodo/snapshots/snapshot-20260701T090000000Z-phone.json',
    )));
    await tester.pumpAndSettle();

    expect(find.text('恢复快照？'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '恢复'), findsOneWidget);
    expect(find.text('Restore snapshot?'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('confirm-restore-snapshot')));
    await tester.pumpAndSettle();

    expect(find.textContaining('恢复失败：Snapshot restore timed out.'),
        findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(syncService.restoreCalls, 1);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.title, '远端快照');
    expect(syncService.restoreCalls, 2);
  });

  testWidgets('uses Chinese system locale for sync feedback', (tester) async {
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

    final syncedState = AppState(
      theme: 'light',
      papers: [
        PaperData(
          id: 'localized-sync-paper',
          type: PaperTypes.note,
          title: '远端笔记',
          content: '合并后的内容',
        ),
      ],
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        theme: 'light',
        papers: [
          PaperData(
            id: 'localized-sync-paper',
            type: PaperTypes.note,
            title: '本地笔记',
            content: '本地内容',
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );
    final syncService = _LocalizedManualSyncService(
      result: AppSyncRunResult(
        syncResult: AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: syncedState,
          message: 'Remote data downloaded.',
        ),
        state: syncedState,
        operationMergeResult: AppSyncOperationMergeResult(
          state: syncedState,
          deviceSequences: const {'phone': 1},
          appliedCount: 1,
          legacyPlainOperationLogCount: 1,
          legacyPlainOperationLogMigratedCount: 1,
        ),
      ),
    );

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: StateStore(filePath: 'build/test-localized-sync.json'),
        syncService: syncService,
      ),
    );

    await tester.tap(find.byTooltip('立即同步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(syncService.calls, 1);
    expect(controller.state.papers.single.title, '远端笔记');
    expect(find.textContaining('已下载远端数据。'), findsOneWidget);
    expect(find.textContaining('已合并 1 个远端变更。'), findsOneWidget);
    expect(find.textContaining('旧版 WebDAV 操作日志'), findsOneWidget);
    expect(find.textContaining('Remote data downloaded'), findsNothing);
    expect(find.textContaining('remote change'), findsNothing);
    expect(find.textContaining('operation log'), findsNothing);
  });
}

class _LocalizedManualSyncService extends AppSyncService {
  _LocalizedManualSyncService({required this.result});

  final AppSyncRunResult result;
  var calls = 0;

  @override
  Future<AppSyncRunResult> syncAndMergeNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    calls += 1;
    return result;
  }
}

class _LocalizedRecoverySnapshotSyncService extends AppSyncService {
  _LocalizedRecoverySnapshotSyncService({
    required this.snapshots,
    required this.restoredState,
    this.firstRestoreError,
  });

  final List<WebDavSnapshotRecord> snapshots;
  final AppState restoredState;
  final Object? firstRestoreError;
  var restoreCalls = 0;

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
    restoreCalls += 1;
    final error = firstRestoreError;
    if (restoreCalls == 1 && error != null) {
      throw error;
    }
    return AppSyncResult(
      status: AppSyncStatus.downloaded,
      state: restoredState,
      snapshotPath: snapshotPath,
    );
  }
}
