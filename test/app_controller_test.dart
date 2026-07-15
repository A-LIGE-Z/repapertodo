import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('new papers inherit deep capsule defaults', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        deepCapsuleSide: DeepCapsuleSides.left,
        deepCapsuleMonitorDeviceName: '  Primary monitor  ',
        deepCapsuleStartTopMargin: 72,
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(PaperTypes.note);

    expect(paper.capsuleSide, DeepCapsuleSides.left);
    expect(paper.capsuleMonitorDeviceName, 'Primary monitor');
    expect(paper.y, 72);
  });

  test('new papers skip deep capsule defaults when disabled', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        deepCapsuleSide: DeepCapsuleSides.left,
        useDeepCapsuleMode: false,
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(PaperTypes.note);

    expect(paper.capsuleSide, isEmpty);
    expect(paper.capsuleMonitorDeviceName, isEmpty);
    expect(paper.x, 140);
    expect(paper.y, 140);
  });

  test('new papers cascade from the PaperTodo desktop origin', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        papers: [
          PaperData(id: 'existing-1', type: PaperTypes.todo, title: 'First'),
          PaperData(id: 'existing-2', type: PaperTypes.note, title: 'Second'),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(PaperTypes.todo);

    expect(paper.x, 188);
    expect(paper.y, 188);
  });

  test('new paper titles use the first unused PaperTodo number', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'todo-1', type: PaperTypes.todo, title: 'Todo1'),
          PaperData(id: 'todo-custom', type: PaperTypes.todo, title: 'Inbox'),
          PaperData(id: 'todo-3', type: PaperTypes.todo, title: 'Todo3'),
          PaperData(id: 'note-1', type: PaperTypes.note, title: 'Note1'),
          PaperData(id: 'note-3', type: PaperTypes.note, title: 'Note03'),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    final todo = controller.createPaper(PaperTypes.todo);
    final note = controller.createPaper(PaperTypes.note);

    expect(todo.title, 'Todo2');
    expect(note.title, 'Note2');
  });

  test('new papers nudge away from near-overlapping paper positions', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        papers: [
          PaperData(
            id: 'near-cascade',
            type: PaperTypes.todo,
            title: 'Near cascade',
            x: 164,
            y: 164,
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(PaperTypes.note);

    expect(paper.x, 194);
    expect(paper.y, 194);
  });

  test('new papers can be spawned from a source paper like PaperTodo', () {
    final sourcePaper = PaperData(
      id: 'source',
      type: PaperTypes.todo,
      title: 'Source',
      x: 260,
      y: 210,
      alwaysOnTop: true,
      capsuleSide: DeepCapsuleSides.left,
      capsuleMonitorDeviceName: 'Secondary monitor',
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        deepCapsuleSide: DeepCapsuleSides.right,
        deepCapsuleMonitorDeviceName: 'Primary monitor',
        deepCapsuleStartTopMargin: 72,
        papers: [sourcePaper],
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(
      PaperTypes.note,
      sourcePaper: sourcePaper,
    );

    expect(paper.x, 290);
    expect(paper.y, 240);
    expect(paper.alwaysOnTop, true);
    expect(paper.capsuleSide, DeepCapsuleSides.left);
    expect(paper.capsuleMonitorDeviceName, 'Secondary monitor');
  });

  test('source papers use PaperTodo collision nudging', () {
    final sourcePaper = PaperData(
      id: 'source',
      type: PaperTypes.todo,
      title: 'Source',
      x: 200,
      y: 180,
    );
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        papers: [
          sourcePaper,
          PaperData(
            id: 'near-source-offset',
            type: PaperTypes.note,
            title: 'Near source offset',
            x: 230,
            y: 210,
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(
      PaperTypes.todo,
      sourcePaper: sourcePaper,
    );

    expect(paper.x, 260);
    expect(paper.y, 240);
  });

  test('paper creation stops at PaperTodo paper limit', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: List.generate(
          PaperLimits.maxPapers,
          (index) => PaperData(
            id: 'paper-$index',
            type: PaperTypes.todo,
            title: 'Paper $index',
          ),
        ),
      ),
      platform: NoopPlatformServices(),
    );

    expect(controller.canCreatePaper, false);
    expect(controller.tryCreatePaper(PaperTypes.note), isNull);
    expect(() => controller.createPaper(PaperTypes.note), throwsStateError);
    expect(controller.state.papers, hasLength(PaperLimits.maxPapers));
  });

  test('disabling capsule mode restores collapsed papers like PaperTodo', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: true,
        useDeepCapsuleMode: true,
        useCapsuleCollapseAll: true,
        capsuleCollapseAllActive: true,
        capsuleCollapseAllActiveQueues: {'Primary|left': true},
        deepCapsuleSide: DeepCapsuleSides.left,
        deepCapsuleStartTopMargin: 160,
        deepCapsuleQueueStartTopMargins: {'Primary|left': 160},
        papers: [
          PaperData(
            id: 'collapsed-paper',
            type: PaperTypes.todo,
            title: 'Collapsed',
            isCollapsed: true,
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    controller.applyCapsuleSettings(
      useCapsuleMode: false,
      useDeepCapsuleMode: true,
      useCapsuleCollapseAll: true,
      capsuleCollapseAllActive: true,
      deepCapsuleSide: DeepCapsuleSides.left,
      deepCapsuleStartTopMargin: 160,
      deepCapsuleMonitorDeviceName: 'Primary',
      showDeepCapsuleWhileExpanded: true,
      collapseExpandedDeepCapsuleOnClick: true,
      hideDeepCapsulesWhenCovered: true,
      hideDeepCapsulesWhenFullscreen: true,
    );

    expect(controller.state.useCapsuleMode, false);
    expect(controller.state.useDeepCapsuleMode, false);
    expect(controller.state.useCapsuleCollapseAll, false);
    expect(controller.state.capsuleCollapseAllActive, false);
    expect(controller.state.capsuleCollapseAllActiveQueues, isEmpty);
    expect(controller.state.hideDeepCapsulesWhenCovered, false);
    expect(controller.state.hideDeepCapsulesWhenFullscreen, false);
    expect(controller.state.deepCapsuleStartTopMargin,
        PaperLayoutDefaults.deepCapsuleStartTopMargin);
    expect(controller.state.deepCapsuleQueueStartTopMargins, isEmpty);
    expect(controller.state.papers.single.isCollapsed, false);
  });

  test('disabling deep capsule mode keeps ordinary capsules collapsed', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: true,
        useDeepCapsuleMode: true,
        useCapsuleCollapseAll: true,
        capsuleCollapseAllActive: true,
        capsuleCollapseAllActiveQueues: {'Primary|left': true},
        deepCapsuleStartTopMargin: 160,
        deepCapsuleQueueStartTopMargins: {'Primary|left': 160},
        papers: [
          PaperData(
            id: 'ordinary-capsule-paper',
            type: PaperTypes.note,
            title: 'Ordinary capsule',
            isCollapsed: true,
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );

    controller.applyCapsuleSettings(
      useCapsuleMode: true,
      useDeepCapsuleMode: false,
      useCapsuleCollapseAll: true,
      capsuleCollapseAllActive: true,
      deepCapsuleSide: DeepCapsuleSides.right,
      deepCapsuleStartTopMargin: 160,
      deepCapsuleMonitorDeviceName: 'Primary',
      showDeepCapsuleWhileExpanded: true,
      collapseExpandedDeepCapsuleOnClick: true,
      hideDeepCapsulesWhenCovered: true,
      hideDeepCapsulesWhenFullscreen: true,
    );

    expect(controller.state.useCapsuleMode, true);
    expect(controller.state.useDeepCapsuleMode, false);
    expect(controller.state.useCapsuleCollapseAll, false);
    expect(controller.state.capsuleCollapseAllActive, false);
    expect(controller.state.capsuleCollapseAllActiveQueues, isEmpty);
    expect(controller.state.hideDeepCapsulesWhenCovered, false);
    expect(controller.state.hideDeepCapsulesWhenFullscreen, false);
    expect(controller.state.deepCapsuleStartTopMargin,
        PaperLayoutDefaults.deepCapsuleStartTopMargin);
    expect(controller.state.papers.single.isCollapsed, true);
  });

  test('pinning to desktop applies PaperTodo surface mode rules', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        useDeepCapsuleMode: false,
        showDeepCapsuleWhileExpanded: false,
        deepCapsuleSide: DeepCapsuleSides.left,
        deepCapsuleMonitorDeviceName: 'Primary',
        papers: [
          PaperData(
            id: 'pin-paper',
            type: PaperTypes.todo,
            title: 'Pin me',
            isVisible: false,
            alwaysOnTop: true,
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );
    final paper = controller.state.papers.single;
    paper.isCollapsed = true;

    controller.setPaperPinnedToDesktop(paper, true);

    expect(paper.isPinnedToDesktop, true);
    expect(paper.isVisible, true);
    expect(paper.isCollapsed, false);
    expect(paper.alwaysOnTop, false);
    expect(paper.capsuleSide, DeepCapsuleSides.left);
    expect(paper.capsuleMonitorDeviceName, 'Primary');
    expect(controller.state.useCapsuleMode, true);
    expect(controller.state.useDeepCapsuleMode, true);
    expect(controller.state.showDeepCapsuleWhileExpanded, true);
  });

  test('pinned hotkey commands reveal existing pinned papers', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'pinned-todo',
            type: PaperTypes.todo,
            title: 'Pinned todo',
            isPinnedToDesktop: true,
          ),
          PaperData(
            id: 'plain-todo',
            type: PaperTypes.todo,
            title: 'Plain todo',
          ),
          PaperData(
            id: 'plain-note',
            type: PaperTypes.note,
            title: 'Plain note',
          ),
        ],
      ),
      platform: platform,
    );

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.revealPinnedTodo),
    );
    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.revealPinnedNote),
    );

    expect(platform.paperWindows.revealedPinnedIds, ['pinned-todo']);
    expect(platform.paperWindows.shownIds, isEmpty);
    expect(controller.state.papers.map((paper) => paper.id), [
      'pinned-todo',
      'plain-todo',
      'plain-note',
    ]);
  });

  test('unpinning from desktop expands collapsed pinned papers', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'pinned-paper',
            type: PaperTypes.note,
            title: 'Pinned',
            isPinnedToDesktop: true,
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );
    final paper = controller.state.papers.single;
    paper.isCollapsed = true;

    controller.setPaperPinnedToDesktop(paper, false);

    expect(paper.isPinnedToDesktop, false);
    expect(paper.isCollapsed, false);
  });

  test('hiding a paper clears desktop pin and collapsed state like PaperTodo',
      () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'hide-paper',
            type: PaperTypes.todo,
            title: 'Hide me',
            isPinnedToDesktop: true,
          ),
        ],
      ),
      platform: platform,
    );
    final paper = controller.state.papers.single;
    paper.isCollapsed = true;

    await controller.hidePaper(paper);

    expect(paper.isPinnedToDesktop, false);
    expect(paper.isVisible, false);
    expect(paper.isCollapsed, false);
    expect(platform.paperWindows.hiddenIds, ['hide-paper']);
    expect(platform.tray.rebuildMenuCount, 1);
  });

  test('showing a hidden paper refreshes the Windows tray menu', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'show-paper',
            type: PaperTypes.note,
            title: 'Show me',
            isVisible: false,
          ),
        ],
      ),
      platform: platform,
    );
    final paper = controller.state.papers.single;

    await controller.showPaper(paper);

    expect(paper.isVisible, true);
    expect(platform.paperWindows.shownIds, ['show-paper']);
    expect(platform.tray.rebuildMenuCount, 1);
  });

  test('startup show and hide commands batch tray menu refreshes', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleCollapseAll: true,
        capsuleCollapseAllActive: true,
        capsuleCollapseAllActiveQueues: {'Primary|right': true},
        papers: [
          PaperData(
            id: 'paper-a',
            type: PaperTypes.todo,
            title: 'A',
            isVisible: false,
            isCollapsed: true,
          ),
          PaperData(
            id: 'paper-b',
            type: PaperTypes.note,
            title: 'B',
            isVisible: false,
          ),
        ],
      ),
      platform: platform,
    );

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.show),
    );

    expect(platform.paperWindows.restoreAllCount, 1);
    expect(controller.state.papers.every((paper) => paper.isVisible), true);
    expect(controller.state.papers.every((paper) => !paper.isCollapsed), true);
    expect(controller.state.capsuleCollapseAllActive, false);
    expect(controller.state.capsuleCollapseAllActiveQueues, isEmpty);
    expect(platform.tray.rebuildMenuCount, 1);

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.hide),
    );

    expect(platform.paperWindows.hiddenIds, ['paper-a', 'paper-b']);
    expect(platform.paperWindows.refreshSurfaceRegistryCount, 1);
    expect(platform.tray.rebuildMenuCount, 2);
  });

  test('surface updates and bounds capture do not rebuild the tray menu',
      () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'paper-surface',
            type: PaperTypes.todo,
            title: 'Surface',
          ),
        ],
      ),
      platform: platform,
    );
    final paper = controller.state.papers.single;

    await controller.updatePaperSurface(paper);
    await controller.capturePaperSurfaceBounds(paper);

    expect(platform.paperWindows.updatedSurfaceIds, ['paper-surface']);
    expect(platform.paperWindows.capturedBoundsIds, ['paper-surface']);
    expect(platform.tray.rebuildMenuCount, 0);
  });

  test('new papers are rescued into the Windows work area before showing',
      () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 0, y: 0, width: 360, height: 320);
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        papers: List.generate(
          20,
          (index) => PaperData(
            id: 'existing-$index',
            type: PaperTypes.todo,
            title: 'Existing $index',
          ),
        ),
      ),
      platform: platform,
    );

    final paper = controller.createPaper(PaperTypes.todo);
    await controller.showPaper(paper);

    expect(platform.paperWindows.workAreaRequestIds, [paper.id]);
    expect(paper.width, 280);
    expect(paper.height, 240);
    expect(paper.x, 72);
    expect(paper.y, 72);
    expect(platform.paperWindows.shownIds, [paper.id]);
  });

  test('new right-edge deep capsule papers avoid the reserved strip', () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 0, y: 0, width: 480, height: 420);
    final controller = RePaperTodoController(
      initialState: AppState(
        deepCapsuleSide: DeepCapsuleSides.right,
        deepCapsuleStartTopMargin: 48,
      ),
      platform: platform,
    );

    final paper = controller.createPaper(PaperTypes.todo);
    await controller.showPaper(paper);

    expect(platform.paperWindows.workAreaRequestIds, [paper.id]);
    expect(paper.x, 104);
    expect(paper.y, 48);
    expect(platform.paperWindows.shownIds, [paper.id]);
  });

  test('new left-edge deep capsule papers avoid the reserved strip', () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 80, y: 0, width: 800, height: 500);
    final controller = RePaperTodoController(
      initialState: AppState(
        deepCapsuleSide: DeepCapsuleSides.left,
        deepCapsuleStartTopMargin: 72,
      ),
      platform: platform,
    );

    final paper = controller.createPaper(PaperTypes.todo);
    await controller.showPaper(paper);

    expect(platform.paperWindows.workAreaRequestIds, [paper.id]);
    expect(paper.x, 176);
    expect(paper.y, 72);
  });

  test('new papers do not shift when expanded deep capsule strip is hidden',
      () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 0, y: 0, width: 480, height: 420);
    final controller = RePaperTodoController(
      initialState: AppState(showDeepCapsuleWhileExpanded: false),
      platform: platform,
    );

    final paper = controller.createPaper(PaperTypes.todo);
    await controller.showPaper(paper);

    expect(platform.paperWindows.workAreaRequestIds, [paper.id]);
    expect(paper.x, 140);
    expect(paper.y, 48);
  });

  test('new papers still show when deep capsule work area lookup fails',
      () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workAreaError = StateError('work area unavailable');
    final controller = RePaperTodoController(
      initialState: AppState(deepCapsuleSide: DeepCapsuleSides.right),
      platform: platform,
    );

    final paper = controller.createPaper(PaperTypes.todo);
    await controller.showPaper(paper);

    expect(platform.paperWindows.workAreaRequestIds, [paper.id]);
    expect(platform.paperWindows.shownIds, [paper.id]);
    expect(paper.x, 140);
    expect(paper.y, 48);
  });

  test('startup new-paper commands use deep capsule strip avoidance', () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 0, y: 0, width: 480, height: 420);
    final controller = RePaperTodoController(
      initialState: AppState(deepCapsuleSide: DeepCapsuleSides.right),
      platform: platform,
    );

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.newTodo),
    );

    final paper = controller.state.papers.single;
    expect(platform.paperWindows.workAreaRequestIds, [paper.id]);
    expect(platform.paperWindows.shownIds, [paper.id]);
    expect(paper.x, 104);
  });

  test('startup new-paper commands no-op at the PaperTodo paper limit',
      () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: List.generate(
          PaperLimits.maxPapers,
          (index) => PaperData(
            id: 'paper-$index',
            type: PaperTypes.todo,
            title: 'Paper $index',
          ),
        ),
      ),
      platform: platform,
    );

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.newNote),
    );

    expect(controller.state.papers, hasLength(PaperLimits.maxPapers));
    expect(platform.paperWindows.shownIds, isEmpty);
  });

  test('showing a non-capsule-eligible paper expands it like PaperTodo',
      () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        papers: [
          PaperData(
            id: 'collapsed-paper',
            type: PaperTypes.todo,
            title: 'Collapsed',
          ),
        ],
      ),
      platform: platform,
    );
    final paper = controller.state.papers.single;
    paper.isCollapsed = true;

    await controller.showPaper(paper);

    expect(paper.isCollapsed, false);
    expect(platform.paperWindows.shownIds, [paper.id]);
  });

  test('startup show expands linked notes hidden from capsules', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        hideLinkedNotesFromCapsules: true,
        papers: [
          PaperData(
            id: 'todo-paper',
            type: PaperTypes.todo,
            title: 'Todo',
            items: [
              PaperItem(id: 'todo-item', linkedNoteId: 'linked-note'),
            ],
          ),
          PaperData(
            id: 'linked-note',
            type: PaperTypes.note,
            title: 'Linked note',
            isVisible: false,
          ),
        ],
      ),
      platform: platform,
    );
    final note = controller.state.papers.last;
    note.isCollapsed = true;

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.show),
    );

    expect(note.isVisible, true);
    expect(note.isCollapsed, false);
    expect(platform.paperWindows.restoreAllCount, 1);
    expect(platform.paperWindows.restoredVisibilitySnapshots.single, [
      true,
      true,
    ]);
  });

  test('opening linked notes places them beside the source paper', () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 0, y: 0, width: 1000, height: 800);
    final source = PaperData(
      id: 'todo-source',
      type: PaperTypes.todo,
      title: 'Source',
      x: 100,
      y: 120,
      width: 280,
      height: 340,
    );
    final note = PaperData(
      id: 'linked-note',
      type: PaperTypes.note,
      title: 'Linked',
      isVisible: false,
      isCollapsed: true,
      width: 320,
      height: 360,
    );
    final controller = RePaperTodoController(
      initialState: AppState(papers: [source, note]),
      platform: platform,
    );

    await controller.openLinkedNote(note, anchorPaper: source);

    expect(platform.paperWindows.workAreaRequestIds, ['todo-source']);
    expect(note.isVisible, true);
    expect(note.isCollapsed, false);
    expect(note.x, 390);
    expect(note.y, 120);
    expect(platform.paperWindows.shownIds, ['linked-note']);
  });

  test('opening linked notes falls back to the left side near screen edge',
      () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 0, y: 0, width: 1000, height: 800);
    final source = PaperData(
      id: 'right-edge-source',
      type: PaperTypes.todo,
      title: 'Right edge source',
      x: 760,
      y: 700,
      width: 220,
      height: 340,
    );
    final note = PaperData(
      id: 'left-note',
      type: PaperTypes.note,
      title: 'Left note',
      width: 320,
      height: 360,
    );
    final controller = RePaperTodoController(
      initialState: AppState(papers: [source, note]),
      platform: platform,
    );

    await controller.openLinkedNote(note, anchorPaper: source);

    expect(note.x, 430);
    expect(note.y, 432);
    expect(platform.paperWindows.shownIds, ['left-note']);
  });

  test('opening reminder papers expands collapsed todo papers', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'reminder-paper',
            type: PaperTypes.todo,
            title: 'Reminder',
            isCollapsed: true,
          ),
        ],
      ),
      platform: platform,
    );
    final paper = controller.state.papers.single;

    await controller.openReminderPaper(paper);

    expect(paper.isVisible, true);
    expect(paper.isCollapsed, false);
    expect(platform.paperWindows.shownIds, ['reminder-paper']);
    expect(platform.paperWindows.revealedPinnedIds, isEmpty);
  });

  test('opening pinned reminder papers reveals the desktop surface', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'pinned-reminder-paper',
            type: PaperTypes.todo,
            title: 'Pinned reminder',
            isCollapsed: true,
            isPinnedToDesktop: true,
          ),
        ],
      ),
      platform: platform,
    );
    final paper = controller.state.papers.single;

    await controller.openReminderPaper(paper);

    expect(paper.isVisible, true);
    expect(paper.isCollapsed, false);
    expect(platform.paperWindows.shownIds, isEmpty);
    expect(platform.paperWindows.revealedPinnedIds, ['pinned-reminder-paper']);
  });

  test('startup show and hide commands apply every paper', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'First'),
          PaperData(
            id: 'paper-2',
            type: PaperTypes.note,
            title: 'Second',
            isVisible: false,
          ),
        ],
      ),
      platform: platform,
    );

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.hide),
    );

    expect(controller.state.papers.map((paper) => paper.isVisible), [
      false,
      false,
    ]);
    expect(platform.paperWindows.hiddenIds, ['paper-1', 'paper-2']);

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.show),
    );

    expect(controller.state.papers.map((paper) => paper.isVisible), [
      true,
      true,
    ]);
    expect(platform.paperWindows.restoreAllCount, 1);
    expect(platform.paperWindows.restoredVisibilitySnapshots.single, [
      true,
      true,
    ]);
  });

  test('startup toggle follows visible native surfaces like PaperTodo',
      () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.visibleSurfaces = false;
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'First'),
          PaperData(id: 'paper-2', type: PaperTypes.note, title: 'Second'),
        ],
      ),
      platform: platform,
    );

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.toggle),
    );

    expect(platform.paperWindows.visibleSurfaceSnapshots, [
      ['paper-1', 'paper-2'],
    ]);
    expect(platform.paperWindows.hiddenIds, isEmpty);
    expect(platform.paperWindows.restoreAllCount, 1);
    expect(platform.paperWindows.restoredVisibilitySnapshots.single, [
      true,
      true,
    ]);
  });

  test('startup settings command is retained for the UI layer', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'paper-1',
            type: PaperTypes.todo,
            title: 'Todo',
          ),
        ],
      ),
      platform: platform,
    );

    await controller.start(
      startupCommand: const StartupCommand(StartupCommandKind.settings),
    );

    expect(
      controller.takePendingUiStartupCommand()?.kind,
      StartupCommandKind.settings,
    );
    expect(controller.takePendingUiStartupCommand(), isNull);
  });

  test('startup rescues restored papers into the Windows work area', () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 0, y: 0, width: 360, height: 320);
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'paper-1',
            type: PaperTypes.note,
            title: 'Offscreen',
            x: 640,
            y: 520,
            width: 640,
            height: 480,
          ),
        ],
      ),
      platform: platform,
    );

    await controller.start();

    final paper = controller.state.papers.single;
    expect(platform.paperWindows.workAreaRequestIds, [paper.id]);
    expect(paper.width, 280);
    expect(paper.height, 240);
    expect(paper.x, 72);
    expect(paper.y, 72);
    expect(platform.paperWindows.restoreAllCount, 1);
  });

  test('startup separates visible papers restored at the same origin',
      () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.workArea =
        const PaperWorkArea(x: 0, y: 0, width: 1200, height: 800);
    final controller = RePaperTodoController(
      initialState: AppState(
        useCapsuleMode: false,
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, x: 120, y: 120),
          PaperData(id: 'paper-2', type: PaperTypes.note, x: 120, y: 120),
        ],
      ),
      platform: platform,
    );

    await controller.start();

    expect(controller.state.papers[0].x, 120);
    expect(controller.state.papers[0].y, 120);
    expect(controller.state.papers[1].x, 150);
    expect(controller.state.papers[1].y, 150);
  });

  test('platform apply restores visible papers whose native surface is missing',
      () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.visibleSurfaceByPaper.addAll({
      'surface-ok': true,
      'surface-missing': false,
    });
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'surface-ok',
            type: PaperTypes.todo,
            title: 'Still visible',
          ),
          PaperData(
            id: 'surface-hidden',
            type: PaperTypes.note,
            title: 'Hidden',
            isVisible: false,
          ),
          PaperData(
            id: 'surface-missing',
            type: PaperTypes.todo,
            title: 'Missing surface',
          ),
        ],
      ),
      platform: platform,
    );

    await controller.applyCurrentStateToPlatform();

    expect(platform.paperWindows.restoreAllCount, 1);
    expect(platform.paperWindows.visibleSurfacePaperIds, [
      'surface-ok',
      'surface-missing',
    ]);
    expect(platform.paperWindows.shownIds, ['surface-missing']);
  });

  test('startup restores visible papers whose native surface is missing',
      () async {
    final platform = _RecordingPlatformServices();
    platform.paperWindows.visibleSurfaceByPaper.addAll({
      'surface-ok': true,
      'surface-missing': false,
    });
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'surface-ok',
            type: PaperTypes.todo,
            title: 'Still visible',
          ),
          PaperData(
            id: 'surface-missing',
            type: PaperTypes.note,
            title: 'Missing surface',
          ),
        ],
      ),
      platform: platform,
    );

    await controller.start();

    expect(platform.paperWindows.restoreAllCount, 1);
    expect(platform.paperWindows.visibleSurfacePaperIds, [
      'surface-ok',
      'surface-missing',
    ]);
    expect(platform.paperWindows.shownIds, ['surface-missing']);
    expect(platform.tray.rebuildMenuCount, 1);
  });

  test('startup restores hidden papers for the current session', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'hidden-startup-paper',
            type: PaperTypes.note,
            title: 'Hidden on exit',
            isVisible: false,
          ),
        ],
      ),
      platform: platform,
    );

    await controller.start();

    expect(controller.state.papers.single.isVisible, true);
    expect(platform.paperWindows.restoredVisibilitySnapshots, [
      [true],
    ]);
  });

  test('startup exit command cleans up platform integrations then exits',
      () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'First'),
        ],
      ),
      platform: platform,
    );

    await controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.exit),
    );

    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.tray.disposeCount, 1);
    expect(platform.systemIntegration.exitApplicationCount, 1);
  });

  test('startup exit command is one-shot while cleanup is running', () async {
    final platform = _RecordingPlatformServices();
    final unregisterGate = Completer<void>();
    platform.systemIntegration.unregisterGlobalHotkeysGate =
        unregisterGate.future;
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'First'),
        ],
      ),
      platform: platform,
    );

    final firstExit = controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.exit),
    );
    await Future<void>.delayed(Duration.zero);

    final secondExit = controller.executeStartupCommand(
      const StartupCommand(StartupCommandKind.exit),
    );
    await Future<void>.delayed(Duration.zero);

    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.tray.disposeCount, 0);
    expect(platform.systemIntegration.exitApplicationCount, 0);

    unregisterGate.complete();
    await Future.wait([firstExit, secondExit]);

    expect(platform.systemIntegration.unregisterGlobalHotkeysCount, 1);
    expect(platform.tray.disposeCount, 1);
    expect(platform.systemIntegration.exitApplicationCount, 1);
  });

  test('startup exit command does not create a default paper', () async {
    final platform = _RecordingPlatformServices();
    final controller = RePaperTodoController(
      initialState: AppState(papers: const []),
      platform: platform,
    );

    await controller.start(
      startupCommand: const StartupCommand(StartupCommandKind.exit),
    );

    expect(controller.state.papers, isEmpty);
    expect(platform.paperWindows.restoreAllCount, 0);
    expect(platform.paperWindows.workAreaRequestIds, isEmpty);
    expect(platform.tray.rebuildMenuCount, 0);
    expect(platform.systemIntegration.exitApplicationCount, 1);
  });

  test('start continues when a platform setting fails', () async {
    final platform = _RecordingPlatformServices();
    platform.systemIntegration.registerGlobalHotkeysError =
        StateError('Hotkeys unavailable');
    platform.paperWindows.workAreaError = StateError('Work area unavailable');
    final controller = RePaperTodoController(
      initialState: AppState(
        startAtLogin: true,
        hidePapersFromWindowSwitcher: true,
        fullscreenTopmostMode: FullscreenTopmostModes.stayOnTop,
        usePersistentPowerShellProcess: true,
        papers: [
          PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'First'),
        ],
      ),
      platform: platform,
    );

    await controller.start();

    expect(platform.paperWindows.workAreaRequestIds, ['paper-1']);
    expect(platform.systemIntegration.registerGlobalHotkeysCalls, 1);
    expect(platform.systemIntegration.startupAtLoginValues, [true]);
    expect(platform.systemIntegration.hideFromWindowSwitcherValues, [true]);
    expect(platform.systemIntegration.fullscreenTopmostModes, [
      FullscreenTopmostModes.stayOnTop,
    ]);
    expect(platform.scriptCapsules.prepareCount, 1);
    expect(platform.paperWindows.restoreAllCount, 1);
    expect(platform.tray.rebuildMenuCount, 1);
  });
}

class _RecordingPlatformServices implements PlatformServices {
  @override
  final _RecordingPaperWindowHost paperWindows = _RecordingPaperWindowHost();

  @override
  final _RecordingTrayHost tray = _RecordingTrayHost();

  @override
  final StartupHost startup = NoopStartupHost();

  @override
  final _RecordingSystemIntegrationHost systemIntegration =
      _RecordingSystemIntegrationHost();

  @override
  final ExternalFileHost externalFiles = NoopExternalFileHost();

  @override
  final UriOpenHost uriOpener = NoopUriOpenHost();

  @override
  final _RecordingScriptCapsuleHost scriptCapsules =
      _RecordingScriptCapsuleHost();

  @override
  final AppStorageHost storage = NoopAppStorageHost();
}

class _RecordingTrayHost extends NoopTrayHost {
  var disposeCount = 0;
  var rebuildMenuCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }

  @override
  Future<void> rebuildMenu(AppState state, {TrayMenuLabels? labels}) async {
    rebuildMenuCount += 1;
  }
}

class _RecordingPaperWindowHost extends NoopPaperWindowHost {
  final shownIds = <String>[];
  final revealedPinnedIds = <String>[];
  final hiddenIds = <String>[];
  final updatedSurfaceIds = <String>[];
  final capturedBoundsIds = <String>[];
  final workAreaRequestIds = <String>[];
  final restoredVisibilitySnapshots = <List<bool>>[];
  final visibleSurfaceSnapshots = <List<String>>[];
  final visibleSurfacePaperIds = <String>[];
  final visibleSurfaceByPaper = <String, bool>{};
  PaperWorkArea? workArea;
  Object? workAreaError;
  bool? visibleSurfaces;
  var restoreAllCount = 0;
  var refreshSurfaceRegistryCount = 0;

  @override
  Future<PaperWorkArea?> workAreaForPaper(PaperData paper) async {
    workAreaRequestIds.add(paper.id);
    final error = workAreaError;
    if (error != null) {
      throw error;
    }
    return workArea;
  }

  @override
  Future<void> restoreAll(AppState state) async {
    restoreAllCount += 1;
    restoredVisibilitySnapshots.add(
      state.papers.map((paper) => paper.isVisible).toList(),
    );
  }

  @override
  Future<void> refreshSurfaceRegistry(AppState state) async {
    refreshSurfaceRegistryCount += 1;
  }

  @override
  Future<bool> hasVisibleSurfaces(AppState state) async {
    visibleSurfaceSnapshots.add(
      state.papers
          .where((paper) => paper.isVisible)
          .map((paper) => paper.id)
          .toList(),
    );
    return visibleSurfaces ?? super.hasVisibleSurfaces(state);
  }

  @override
  Future<bool> hasVisibleSurface(PaperData paper) async {
    visibleSurfacePaperIds.add(paper.id);
    return visibleSurfaceByPaper[paper.id] ?? super.hasVisibleSurface(paper);
  }

  @override
  Future<void> showPaper(PaperData paper) async {
    shownIds.add(paper.id);
  }

  @override
  Future<void> revealPinnedPaper(PaperData paper) async {
    revealedPinnedIds.add(paper.id);
  }

  @override
  Future<void> hidePaper(PaperData paper) async {
    hiddenIds.add(paper.id);
  }

  @override
  Future<void> updatePaperSurface(PaperData paper) async {
    updatedSurfaceIds.add(paper.id);
  }

  @override
  Future<void> capturePaperSurfaceBounds(PaperData paper) async {
    capturedBoundsIds.add(paper.id);
  }
}

class _RecordingSystemIntegrationHost extends NoopSystemIntegrationHost {
  @override
  bool get supportsStartupAtLogin => true;

  @override
  bool get supportsWindowSwitcherVisibility => true;

  @override
  bool get supportsFullscreenTopmostMode => true;

  @override
  bool get supportsGlobalHotkeys => true;

  final startupAtLoginValues = <bool>[];
  final hideFromWindowSwitcherValues = <bool>[];
  final fullscreenTopmostModes = <String>[];
  Object? registerGlobalHotkeysError;
  Future<void>? unregisterGlobalHotkeysGate;
  var registerGlobalHotkeysCalls = 0;
  var unregisterGlobalHotkeysCount = 0;
  var exitApplicationCount = 0;

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {
    registerGlobalHotkeysCalls += 1;
    final error = registerGlobalHotkeysError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setStartupAtLogin(bool enabled) async {
    startupAtLoginValues.add(enabled);
  }

  @override
  Future<void> setHideFromWindowSwitcher(bool enabled) async {
    hideFromWindowSwitcherValues.add(enabled);
  }

  @override
  Future<void> setFullscreenTopmostMode(String mode) async {
    fullscreenTopmostModes.add(mode);
  }

  @override
  Future<void> unregisterGlobalHotkeys() async {
    unregisterGlobalHotkeysCount += 1;
    await unregisterGlobalHotkeysGate;
  }

  @override
  Future<void> exitApplication() async {
    exitApplicationCount += 1;
  }
}

class _RecordingScriptCapsuleHost extends NoopScriptCapsuleHost {
  @override
  bool get supportsScriptCapsules => true;

  var prepareCount = 0;

  @override
  Future<void> preparePersistentProcess({
    required bool preferPowerShell7,
    required bool hideScriptRunWindow,
  }) async {
    prepareCount += 1;
  }
}
