import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/repapertodo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paper host sends window method channel calls', () async {
    const channel = MethodChannel('repapertodo/window_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getBounds') {
        return {
          'x': 33,
          'y': 44,
          'width': 420,
          'height': 360,
        };
      }
      if (call.method == 'isForegroundFullscreen') {
        return true;
      }
      if (call.method == 'acquireSingleInstance') {
        return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    expect(services.systemIntegration.supportsStartupAtLogin, true);
    expect(services.systemIntegration.supportsWindowSwitcherVisibility, true);
    expect(services.systemIntegration.supportsFullscreenTopmostMode, true);
    expect(services.systemIntegration.supportsGlobalHotkeys, true);
    expect(services.scriptCapsules.supportsScriptCapsules, true);

    final paper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'Inbox',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
      isPinnedToDesktop: true,
      capsuleSide: DeepCapsuleSides.left,
      capsuleMonitorDeviceName: r'\\.\DISPLAY2',
    );

    await services.paperWindows.showPaper(paper);
    await services.paperWindows.capturePaperSurfaceBounds(paper);
    final surfaceUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('boundsChanged', {
          'x': 55,
          'y': 66,
          'width': 520,
          'height': 460,
        }),
      ),
      (_) {},
    );
    await surfaceUpdate;
    final closeUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('closeRequested'),
      ),
      (_) {},
    );
    await closeUpdate;
    final showUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('showRequested'),
      ),
      (_) {},
    );
    await showUpdate;
    expect(paper.isVisible, true);
    final openRequest = services.paperWindows.paperOpenRequests.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('paperRequested', 'paper-1'),
      ),
      (_) {},
    );
    expect(await openRequest, 'paper-1');
    final hideUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('hideRequested'),
      ),
      (_) {},
    );
    await hideUpdate;
    await services.paperWindows.hidePaper(paper);
    await services.tray.rebuildMenu(AppState(papers: [paper]));
    final acquiredSingleInstance =
        await services.startup.acquireSingleInstance();
    await services.startup.forwardToPrimary(['--new-note']);
    await services.systemIntegration.setStartupAtLogin(true);
    await services.systemIntegration.setHideFromWindowSwitcher(true);
    await services.systemIntegration
        .setFullscreenTopmostMode(FullscreenTopmostModes.stayOnTop);
    await services.systemIntegration.registerGlobalHotkeys(
      AppState(
        pinnedTodoHotKey: 'Ctrl+Alt+T',
        pinnedNoteHotKey: 'Ctrl+Alt+N',
      ),
    );
    await services.systemIntegration.unregisterGlobalHotkeys();
    await services.systemIntegration.exitApplication();
    final startupCommand = services.startup.commands.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('startupCommandRequested', 'new-todo'),
      ),
      (_) {},
    );
    final foregroundFullscreen =
        await services.systemIntegration.isForegroundFullscreen();
    await services.externalFiles.openFile(' C:\\Temp\\note.md ');
    await services.uriOpener.openUri(' https://example.com/paper ');
    await services.scriptCapsules.runScriptCapsule(
      const ScriptCapsuleRunRequest(
        engine: 'pwsh',
        script: 'Write-Output ok',
        usePersistentProcess: true,
        usePersistentPowerShellProcess: true,
        preferPowerShell7: true,
        hideScriptRunWindow: true,
      ),
    );
    await services.scriptCapsules.preparePersistentProcess(
      preferPowerShell7: false,
      hideScriptRunWindow: false,
    );
    await services.scriptCapsules.stopPersistentProcesses();

    final platformCalls = _withoutQueueMonitorNormalization(calls);
    expect(
      platformCalls.map((call) => call.method),
      [
        'setBounds',
        'setPinnedToDesktop',
        'show',
        'setTitle',
        'setAlwaysOnTop',
        'getBounds',
        'hide',
        'setTrayMenu',
        'acquireSingleInstance',
        'forwardToPrimary',
        'setStartupAtLogin',
        'setHideFromWindowSwitcher',
        'setFullscreenTopmostMode',
        'registerGlobalHotkeys',
        'unregisterGlobalHotkeys',
        'exitApplication',
        'isForegroundFullscreen',
        'openExternalFile',
        'openUri',
        'runScriptCapsule',
        'preparePersistentScriptCapsule',
        'stopPersistentScriptCapsules',
      ],
    );
    expect(foregroundFullscreen, true);
    expect((await startupCommand).kind, StartupCommandKind.newTodo);
    expect(platformCalls[0].arguments, {
      'paperId': 'paper-1',
      'x': 10.0,
      'y': 20.0,
      'width': 320.0,
      'height': 260.0,
    });
    expect(platformCalls[1].arguments, {
      'paperId': 'paper-1',
      'enabled': true,
    });
    expect(platformCalls[2].arguments, {
      'paperId': 'paper-1',
      'isPinnedToDesktop': true,
      'alwaysOnTop': false,
      'capsuleSide': DeepCapsuleSides.left,
      'capsuleMonitorDeviceName': r'\\.\DISPLAY2',
    });
    expect(platformCalls[3].arguments, {
      'paperId': 'paper-1',
      'title': 'RePaperTodo - Inbox',
    });
    expect(platformCalls[4].arguments, {
      'paperId': 'paper-1',
      'enabled': false,
    });
    expect(platformCalls[5].arguments, 'paper-1');
    expect(platformCalls[6].arguments, {
      'paperId': 'paper-1',
      'isPinnedToDesktop': true,
      'alwaysOnTop': false,
      'capsuleSide': DeepCapsuleSides.left,
      'capsuleMonitorDeviceName': r'\\.\DISPLAY2',
    });
    expect(paper.x, 55);
    expect(paper.y, 66);
    expect(paper.width, 520);
    expect(paper.height, 460);
    expect(paper.isVisible, false);
    expect(platformCalls[7].arguments, [
      {
        'id': 'paper-1',
        'title': 'Inbox',
        'type': PaperTypes.todo,
        'x': 55.0,
        'y': 66.0,
        'width': 520.0,
        'height': 460.0,
        'isVisible': false,
        'isCollapsed': false,
        'capsuleSide': DeepCapsuleSides.left,
        'capsuleMonitorDeviceName': r'\\.\DISPLAY2',
        'alwaysOnTop': false,
        'isPinnedToDesktop': true,
        'isScriptCapsule': false,
      },
    ]);
    expect(acquiredSingleInstance, true);
    expect(platformCalls[8].arguments, isNull);
    expect(platformCalls[9].arguments, ['--new-note']);
    expect(platformCalls[10].arguments, true);
    expect(platformCalls[11].arguments, true);
    expect(platformCalls[12].arguments, FullscreenTopmostModes.stayOnTop);
    expect(platformCalls[13].arguments, {
      'todo': 'Ctrl+Alt+T',
      'note': 'Ctrl+Alt+N',
    });
    expect(platformCalls[14].arguments, isNull);
    expect(platformCalls[15].arguments, isNull);
    expect(platformCalls[16].arguments, isNull);
    expect(platformCalls[17].arguments, 'C:\\Temp\\note.md');
    expect(platformCalls[18].arguments, 'https://example.com/paper');
    expect(platformCalls[19].arguments, {
      'engine': 'pwsh',
      'script': 'Write-Output ok',
      'usePersistentProcess': true,
      'usePersistentPowerShellProcess': true,
      'preferPowerShell7': true,
      'hideScriptRunWindow': true,
    });
    expect(platformCalls[20].arguments, {
      'preferPowerShell7': false,
      'hideScriptRunWindow': false,
    });
    expect(platformCalls.last.arguments, isNull);
  });

  test('paper host reveals pinned papers without ordinary show', () async {
    const channel = MethodChannel('repapertodo/window_reveal_pinned_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final paper = PaperData(
      id: 'pinned-paper',
      type: PaperTypes.todo,
      title: 'Pinned',
      x: 12,
      y: 24,
      width: 320,
      height: 240,
      isVisible: true,
      isPinnedToDesktop: true,
    );

    await services.paperWindows.revealPinnedPaper(paper);

    expect(
      calls.map((call) => call.method),
      [
        'setBounds',
        'setPinnedToDesktop',
        'setAlwaysOnTop',
        'revealPinnedPaper',
        'setTitle',
      ],
    );
    expect(calls[0].arguments, {
      'paperId': 'pinned-paper',
      'x': 12.0,
      'y': 24.0,
      'width': 320.0,
      'height': 240.0,
    });
    expect(calls[1].arguments, {
      'paperId': 'pinned-paper',
      'enabled': true,
    });
    expect(calls[2].arguments, {
      'paperId': 'pinned-paper',
      'enabled': false,
    });
    expect(calls[3].arguments, {
      'paperId': 'pinned-paper',
      'isPinnedToDesktop': true,
      'alwaysOnTop': false,
      'capsuleSide': '',
      'capsuleMonitorDeviceName': '',
    });
    expect(calls[4].arguments, {
      'paperId': 'pinned-paper',
      'title': 'RePaperTodo - Pinned',
    });
    expect(calls.map((call) => call.method), isNot(contains('show')));
  });

  test('Windows global hotkeys are normalized before channel registration',
      () async {
    const channel = MethodChannel('repapertodo/window_hotkey_boundary_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final longHotKey = 'Ctrl+Alt+${List.filled(80, 'N').join()}';

    await services.systemIntegration.registerGlobalHotkeys(
      AppState(
        pinnedTodoHotKey: '  Ctrl+\nAlt+\u007FT  ',
        pinnedNoteHotKey: '$longHotKey\u0085',
      ),
    );

    expect(calls.single.method, 'registerGlobalHotkeys');
    expect(calls.single.arguments, {
      'todo': 'Ctrl+Alt+T',
      'note': longHotKey.substring(0, 64),
    });
  });

  test('Windows platform services normalize installed font families', () async {
    const channel = MethodChannel('repapertodo/window_fonts_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'listInstalledFontFamilies') {
        return [
          'Paper Sans',
          'paper sans',
          ' \u0000Beta Font\u007F ',
          '',
          7,
          'Alpha',
        ];
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final services = WindowsPlatformServices(channel: channel);

    expect(
      await services.systemIntegration.installedFontFamilies(),
      ['Alpha', 'Beta Font', 'Paper Sans'],
    );
    expect(calls.map((call) => call.method), ['listInstalledFontFamilies']);
  });

  test('Windows platform services reject blank channel arguments locally',
      () async {
    const channel = MethodChannel('repapertodo/window_blank_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final services = WindowsPlatformServices(channel: channel);

    await expectLater(
      services.uriOpener.openUri('   '),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      services.uriOpener.openUri('https://example.com/%0Apath'),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      services.uriOpener.openUri('https://example.com%3A443/path'),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      services.uriOpener.openUri('https://example.com/\npath'),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      services.uriOpener.openUri('\nhttps://example.com/paper'),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      services.uriOpener.openUri('https://example.com/paper\t'),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      services.externalFiles.openFile('   '),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      services.externalFiles.openFile('C:\\Temp\\bad\nnote.md'),
      throwsA(isA<ArgumentError>()),
    );

    expect(calls, isEmpty);
  });

  test('paper host requests Windows work area for deep capsule placement',
      () async {
    const channel = MethodChannel('repapertodo/window_work_area_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getWorkArea') {
        return {
          'x': 0,
          'y': 0,
          'width': 1440,
          'height': 860,
        };
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final paper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'Inbox',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
      capsuleMonitorDeviceName: r'\\.\DISPLAY2',
    );

    final workArea = await services.paperWindows.workAreaForPaper(paper);

    expect(workArea?.x, 0);
    expect(workArea?.y, 0);
    expect(workArea?.width, 1440);
    expect(workArea?.height, 860);
    final platformCalls = _withoutQueueMonitorNormalization(calls);
    expect(platformCalls.single.method, 'getWorkArea');
    expect(platformCalls.single.arguments, {
      'paperId': 'paper-1',
      'x': 10.0,
      'y': 20.0,
      'width': 320.0,
      'height': 260.0,
      'monitorDeviceName': r'\\.\DISPLAY2',
    });
  });

  test('paper host normalizes primary monitor queue names like PaperTodo',
      () async {
    const channel = MethodChannel('repapertodo/window_monitor_queue_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'normalizeQueueMonitorDeviceName') {
        final arguments = call.arguments as Map<Object?, Object?>;
        final monitor = arguments['monitorDeviceName'];
        return monitor == r'\\.\DISPLAY1' ? '' : monitor;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final primaryPaper = PaperData(
      id: 'primary-paper',
      type: PaperTypes.todo,
      title: 'Primary',
      capsuleSide: DeepCapsuleSides.left,
      capsuleMonitorDeviceName: r'\\.\DISPLAY1',
    );
    final secondaryPaper = PaperData(
      id: 'secondary-paper',
      type: PaperTypes.note,
      title: 'Secondary',
      isVisible: false,
      capsuleSide: DeepCapsuleSides.right,
      capsuleMonitorDeviceName: r'\\.\DISPLAY2',
    );

    await services.paperWindows.restoreAll(
      AppState(papers: [primaryPaper, secondaryPaper]),
    );

    expect(primaryPaper.capsuleMonitorDeviceName, '');
    expect(secondaryPaper.capsuleMonitorDeviceName, r'\\.\DISPLAY2');
    final restoreSurfacesCall =
        calls.firstWhere((call) => call.method == 'setPaperSurfaces');
    final restorePapers = restoreSurfacesCall.arguments as List<Object?>;
    expect(
      (restorePapers[0] as Map<Object?, Object?>)['capsuleMonitorDeviceName'],
      '',
    );
    expect(
      (restorePapers[1] as Map<Object?, Object?>)['capsuleMonitorDeviceName'],
      r'\\.\DISPLAY2',
    );

    primaryPaper.capsuleMonitorDeviceName = r'\\.\DISPLAY1';
    await services.tray.rebuildMenu(AppState(papers: [primaryPaper]));

    expect(primaryPaper.capsuleMonitorDeviceName, '');
    final rebuildTrayMenuCall =
        calls.lastWhere((call) => call.method == 'setTrayMenu');
    final rebuildPapers = rebuildTrayMenuCall.arguments as List<Object?>;
    expect(
      (rebuildPapers.single
          as Map<Object?, Object?>)['capsuleMonitorDeviceName'],
      '',
    );

    primaryPaper.capsuleMonitorDeviceName = r'\\.\DISPLAY1';
    await services.paperWindows.showPaper(primaryPaper);

    expect(primaryPaper.capsuleMonitorDeviceName, '');
    final showCall = calls.lastWhere((call) => call.method == 'show');
    expect(
      (showCall.arguments as Map<Object?, Object?>)['capsuleMonitorDeviceName'],
      '',
    );
  });

  test('paper host asks Windows for actual visible surfaces', () async {
    const channel = MethodChannel('repapertodo/window_visible_surface_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'hasVisibleSurfaces') {
        return false;
      }
      if (call.method == 'hasVisibleSurface') {
        return false;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final state = AppState(
      papers: [
        PaperData(id: 'paper-1', type: PaperTypes.todo, title: 'First'),
      ],
    );

    expect(await services.paperWindows.hasVisibleSurfaces(state), false);

    final platformCalls = _withoutQueueMonitorNormalization(calls);
    expect(platformCalls.map((call) => call.method), [
      'hasVisibleSurfaces',
      'hasVisibleSurface',
    ]);
    expect(platformCalls[0].arguments, isNull);
    expect(platformCalls[1].arguments, {
      'paperId': 'paper-1',
      'isPinnedToDesktop': false,
      'alwaysOnTop': false,
      'capsuleSide': '',
      'capsuleMonitorDeviceName': '',
    });
  });

  test('paper host checks individual surfaces when aggregate is hidden',
      () async {
    const channel = MethodChannel('repapertodo/window_visible_any_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'hasVisibleSurfaces') {
        return false;
      }
      if (call.method == 'hasVisibleSurface') {
        final arguments = call.arguments as Map<Object?, Object?>;
        return arguments['paperId'] == 'paper-2';
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final state = AppState(
      papers: [
        PaperData(
          id: 'paper-1',
          type: PaperTypes.todo,
          title: 'Hidden',
          isVisible: false,
        ),
        PaperData(id: 'paper-2', type: PaperTypes.note, title: 'Visible'),
      ],
    );

    expect(await services.paperWindows.hasVisibleSurfaces(state), true);

    final platformCalls = _withoutQueueMonitorNormalization(calls);
    expect(platformCalls.map((call) => call.method), [
      'hasVisibleSurfaces',
      'hasVisibleSurface',
    ]);
    expect(platformCalls[1].arguments, {
      'paperId': 'paper-2',
      'isPinnedToDesktop': false,
      'alwaysOnTop': false,
      'capsuleSide': '',
      'capsuleMonitorDeviceName': '',
    });
  });

  test('paper host asks Windows for a specific visible surface', () async {
    const channel = MethodChannel('repapertodo/window_visible_paper_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'hasVisibleSurface') {
        return false;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final paper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'First',
      isPinnedToDesktop: true,
      alwaysOnTop: true,
      capsuleSide: DeepCapsuleSides.left,
      capsuleMonitorDeviceName: r'\\.\DISPLAY2',
    );

    expect(await services.paperWindows.hasVisibleSurface(paper), false);

    final platformCalls = _withoutQueueMonitorNormalization(calls);
    expect(platformCalls.single.method, 'hasVisibleSurface');
    expect(platformCalls.single.arguments, {
      'paperId': 'paper-1',
      'isPinnedToDesktop': true,
      'alwaysOnTop': true,
      'capsuleSide': DeepCapsuleSides.left,
      'capsuleMonitorDeviceName': r'\\.\DISPLAY2',
    });
  });

  test('Windows script capsule host rejects invalid requests locally',
      () async {
    const channel = MethodChannel('repapertodo/window_script_invalid_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final services = WindowsPlatformServices(channel: channel);

    await expectLater(
      services.scriptCapsules.runScriptCapsule(
        const ScriptCapsuleRunRequest(
          engine: 'auto',
          script: '   ',
          usePersistentProcess: false,
          usePersistentPowerShellProcess: false,
          preferPowerShell7: true,
          hideScriptRunWindow: true,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      services.scriptCapsules.runScriptCapsule(
        const ScriptCapsuleRunRequest(
          engine: 'cmd',
          script: 'Write-Output ok',
          usePersistentProcess: false,
          usePersistentPowerShellProcess: false,
          preferPowerShell7: true,
          hideScriptRunWindow: true,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(calls, isEmpty);
  });

  test('paper host routes paper-id events to known window surfaces', () async {
    const channel = MethodChannel('repapertodo/window_event_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final firstPaper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'First',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );
    final secondPaper = PaperData(
      id: 'paper-2',
      type: PaperTypes.note,
      title: 'Second',
      content: '!p\nWrite-Output tray',
      x: 30,
      y: 40,
      width: 420,
      height: 360,
      alwaysOnTop: true,
      isCollapsed: true,
      capsuleSide: DeepCapsuleSides.left,
      capsuleMonitorDeviceName: r'\\.\DISPLAY2',
    );

    await services.paperWindows.restoreAll(
      AppState(papers: [firstPaper, secondPaper]),
    );
    final platformCalls = _withoutQueueMonitorNormalization(calls);
    expect(
      platformCalls.map((call) => call.method),
      [
        'setPaperSurfaces',
        'setBounds',
        'setPinnedToDesktop',
        'show',
        'setTitle',
        'setAlwaysOnTop',
      ],
    );
    final initialSurfacesCall =
        platformCalls.firstWhere((call) => call.method == 'setPaperSurfaces');
    expect(initialSurfacesCall.arguments, [
      {
        'id': 'paper-1',
        'title': 'First',
        'type': PaperTypes.todo,
        'x': 10.0,
        'y': 20.0,
        'width': 320.0,
        'height': 260.0,
        'isVisible': true,
        'isCollapsed': false,
        'capsuleSide': '',
        'capsuleMonitorDeviceName': '',
        'alwaysOnTop': false,
        'isPinnedToDesktop': false,
        'isScriptCapsule': false,
      },
      {
        'id': 'paper-2',
        'title': 'Second',
        'type': PaperTypes.note,
        'x': 30.0,
        'y': 40.0,
        'width': 420.0,
        'height': 360.0,
        'isVisible': true,
        'isCollapsed': true,
        'capsuleSide': DeepCapsuleSides.left,
        'capsuleMonitorDeviceName': r'\\.\DISPLAY2',
        'alwaysOnTop': true,
        'isPinnedToDesktop': false,
        'isScriptCapsule': true,
      },
    ]);
    expect(platformCalls[1].arguments, {
      'paperId': 'paper-1',
      'x': 10.0,
      'y': 20.0,
      'width': 320.0,
      'height': 260.0,
    });
    expect(platformCalls[2].arguments, {
      'paperId': 'paper-1',
      'enabled': false,
    });
    expect(platformCalls[3].arguments, {
      'paperId': 'paper-1',
      'isPinnedToDesktop': false,
      'alwaysOnTop': false,
      'capsuleSide': '',
      'capsuleMonitorDeviceName': '',
    });
    expect(platformCalls[4].arguments, {
      'paperId': 'paper-1',
      'title': 'RePaperTodo - First',
    });
    expect(platformCalls[5].arguments, {
      'paperId': 'paper-1',
      'enabled': false,
    });

    final boundsUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('boundsChanged', {
          'paperId': 'paper-2',
          'bounds': {
            'x': 70,
            'y': 80,
            'width': 520,
            'height': 480,
          },
        }),
      ),
      (_) {},
    );
    expect((await boundsUpdate).id, 'paper-2');
    expect(firstPaper.x, 10);
    expect(secondPaper.x, 70);
    expect(secondPaper.y, 80);
    expect(secondPaper.width, 520);
    expect(secondPaper.height, 480);

    final closeUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('closeRequested', {'paperId': 'paper-2'}),
      ),
      (_) {},
    );
    expect((await closeUpdate).id, 'paper-2');
    expect(firstPaper.isVisible, true);
    expect(secondPaper.isVisible, false);

    final openRequest = services.paperWindows.paperOpenRequests.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('paperRequested', {'paperId': 'paper-2'}),
      ),
      (_) {},
    );
    expect(await openRequest, 'paper-2');

    final deleteRequest = services.paperWindows.paperDeleteRequests.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('paperDeleteRequested', {'paperId': 'paper-2'}),
      ),
      (_) {},
    );
    expect(await deleteRequest, 'paper-2');

    await services.tray
        .rebuildMenu(AppState(papers: [firstPaper, secondPaper]));
    final trayMenuCall =
        calls.lastWhere((call) => call.method == 'setTrayMenu');
    expect(trayMenuCall.arguments, [
      {
        'id': 'paper-1',
        'title': 'First',
        'type': PaperTypes.todo,
        'x': 10.0,
        'y': 20.0,
        'width': 320.0,
        'height': 260.0,
        'isVisible': true,
        'isCollapsed': false,
        'capsuleSide': '',
        'capsuleMonitorDeviceName': '',
        'alwaysOnTop': false,
        'isPinnedToDesktop': false,
        'isScriptCapsule': false,
      },
      {
        'id': 'paper-2',
        'title': 'Second',
        'type': PaperTypes.note,
        'x': 70.0,
        'y': 80.0,
        'width': 520.0,
        'height': 480.0,
        'isVisible': false,
        'isCollapsed': true,
        'capsuleSide': DeepCapsuleSides.left,
        'capsuleMonitorDeviceName': r'\\.\DISPLAY2',
        'alwaysOnTop': true,
        'isPinnedToDesktop': false,
        'isScriptCapsule': true,
      },
    ]);
  });

  test('paper host keeps active routing for non-active hide and close events',
      () async {
    const channel = MethodChannel('repapertodo/window_non_active_hide_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final firstPaper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'First',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );
    final secondPaper = PaperData(
      id: 'paper-2',
      type: PaperTypes.note,
      title: 'Second',
      x: 30,
      y: 40,
      width: 420,
      height: 360,
    );

    await services.paperWindows.restoreAll(
      AppState(papers: [firstPaper, secondPaper]),
    );

    Future<void> send(MethodCall call) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(call),
        (_) {},
      );
    }

    final explicitHideUpdate = services.paperWindows.surfaceUpdates.first;
    await send(
      const MethodCall('hideRequested', {'paperId': 'paper-2'}),
    );
    expect((await explicitHideUpdate).id, 'paper-2');
    expect(firstPaper.isVisible, true);
    expect(secondPaper.isVisible, false);

    final legacyBoundsUpdate = services.paperWindows.surfaceUpdates.first;
    await send(
      const MethodCall('boundsChanged', {
        'x': 111,
        'y': 222,
        'width': 333,
        'height': 444,
      }),
    );
    expect((await legacyBoundsUpdate).id, 'paper-1');
    expect(firstPaper.x, 111);
    expect(firstPaper.y, 222);
    expect(secondPaper.x, 30);
    expect(secondPaper.y, 40);

    secondPaper.isVisible = true;
    final explicitCloseUpdate = services.paperWindows.surfaceUpdates.first;
    await send(
      const MethodCall('closeRequested', {'paperId': 'paper-2'}),
    );
    expect((await explicitCloseUpdate).id, 'paper-2');
    expect(firstPaper.isVisible, true);
    expect(secondPaper.isVisible, false);

    final legacyCloseUpdate = services.paperWindows.surfaceUpdates.first;
    await send(const MethodCall('closeRequested'));
    expect((await legacyCloseUpdate).id, 'paper-1');
    expect(firstPaper.isVisible, false);
  });

  test('paper host retargets active routing after active paper is hidden',
      () async {
    const channel = MethodChannel('repapertodo/window_active_retarget_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final firstPaper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'First',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );
    final secondPaper = PaperData(
      id: 'paper-2',
      type: PaperTypes.note,
      title: 'Second',
      x: 30,
      y: 40,
      width: 420,
      height: 360,
    );

    await services.paperWindows.restoreAll(
      AppState(papers: [firstPaper, secondPaper]),
    );
    await services.paperWindows.showPaper(secondPaper);

    Future<void> send(MethodCall call) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(call),
        (_) {},
      );
    }

    final explicitCloseUpdate = services.paperWindows.surfaceUpdates.first;
    await send(
      const MethodCall('closeRequested', {'paperId': 'paper-2'}),
    );
    expect((await explicitCloseUpdate).id, 'paper-2');
    expect(firstPaper.isVisible, true);
    expect(secondPaper.isVisible, false);

    final legacyBoundsUpdate = services.paperWindows.surfaceUpdates.first;
    await send(
      const MethodCall('boundsChanged', {
        'x': 111,
        'y': 222,
        'width': 333,
        'height': 444,
      }),
    );
    expect((await legacyBoundsUpdate).id, 'paper-1');
    expect(firstPaper.x, 111);
    expect(firstPaper.y, 222);
    expect(firstPaper.width, 333);
    expect(firstPaper.height, 444);
    expect(secondPaper.x, 30);
    expect(secondPaper.y, 40);
    expect(secondPaper.width, 420);
    expect(secondPaper.height, 360);
  });

  test('paper host retargets active routing after local active hide', () async {
    const channel =
        MethodChannel('repapertodo/window_local_hide_retarget_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final firstPaper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'First',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );
    final secondPaper = PaperData(
      id: 'paper-2',
      type: PaperTypes.note,
      title: 'Second',
      x: 30,
      y: 40,
      width: 420,
      height: 360,
    );

    await services.paperWindows.restoreAll(
      AppState(papers: [firstPaper, secondPaper]),
    );
    await services.paperWindows.showPaper(secondPaper);
    await services.paperWindows.hidePaper(secondPaper);

    final legacyBoundsUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('boundsChanged', {
          'x': 111,
          'y': 222,
          'width': 333,
          'height': 444,
        }),
      ),
      (_) {},
    );

    expect(secondPaper.isVisible, false);
    expect((await legacyBoundsUpdate).id, 'paper-1');
    expect(firstPaper.x, 111);
    expect(firstPaper.y, 222);
    expect(firstPaper.width, 333);
    expect(firstPaper.height, 444);
    expect(secondPaper.x, 30);
    expect(secondPaper.y, 40);
    expect(secondPaper.width, 420);
    expect(secondPaper.height, 360);
  });

  test('paper host retargets active routing after hidden surface update',
      () async {
    const channel =
        MethodChannel('repapertodo/window_hidden_update_retarget_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final firstPaper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'First',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );
    final secondPaper = PaperData(
      id: 'paper-2',
      type: PaperTypes.note,
      title: 'Second',
      x: 30,
      y: 40,
      width: 420,
      height: 360,
    );

    await services.paperWindows.restoreAll(
      AppState(papers: [firstPaper, secondPaper]),
    );
    await services.paperWindows.showPaper(secondPaper);
    secondPaper.isVisible = false;
    await services.paperWindows.updatePaperSurface(secondPaper);

    final legacyBoundsUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('boundsChanged', {
          'x': 111,
          'y': 222,
          'width': 333,
          'height': 444,
        }),
      ),
      (_) {},
    );

    expect((await legacyBoundsUpdate).id, 'paper-1');
    expect(firstPaper.x, 111);
    expect(firstPaper.y, 222);
    expect(firstPaper.width, 333);
    expect(firstPaper.height, 444);
    expect(secondPaper.x, 30);
    expect(secondPaper.y, 40);
    expect(secondPaper.width, 420);
    expect(secondPaper.height, 360);
  });

  test('paper host retargets active routing after state refresh hides active',
      () async {
    const channel =
        MethodChannel('repapertodo/window_state_refresh_retarget_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final firstPaper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'First',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );
    final secondPaper = PaperData(
      id: 'paper-2',
      type: PaperTypes.note,
      title: 'Second',
      x: 30,
      y: 40,
      width: 420,
      height: 360,
    );

    await services.paperWindows.restoreAll(
      AppState(papers: [firstPaper, secondPaper]),
    );
    await services.paperWindows.showPaper(secondPaper);
    secondPaper.isVisible = false;
    await services.tray
        .rebuildMenu(AppState(papers: [firstPaper, secondPaper]));

    final legacyBoundsUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('boundsChanged', {
          'x': 111,
          'y': 222,
          'width': 333,
          'height': 444,
        }),
      ),
      (_) {},
    );

    expect((await legacyBoundsUpdate).id, 'paper-1');
    expect(firstPaper.x, 111);
    expect(firstPaper.y, 222);
    expect(firstPaper.width, 333);
    expect(firstPaper.height, 444);
    expect(secondPaper.x, 30);
    expect(secondPaper.y, 40);
    expect(secondPaper.width, 420);
    expect(secondPaper.height, 360);
  });

  test('tray rebuild can send localized labels with paper menu text', () async {
    const channel = MethodChannel('repapertodo/window_tray_labels_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final todoPaper = PaperData(
      id: 'localized-todo',
      type: PaperTypes.todo,
      title: 'First',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );
    final scriptPaper = PaperData(
      id: 'localized-script',
      type: PaperTypes.note,
      title: 'Second',
      content: '!p\nWrite-Output tray',
      isVisible: false,
      isCollapsed: true,
      isPinnedToDesktop: true,
      alwaysOnTop: true,
    );

    await services.tray.rebuildMenu(
      AppState(papers: [todoPaper, scriptPaper]),
      labels: _localizedTrayLabels,
    );

    final trayMenuCall =
        calls.lastWhere((call) => call.method == 'setTrayMenu');
    final payload = trayMenuCall.arguments as Map<Object?, Object?>;
    expect(payload['labels'], _localizedTrayLabels.toJson());
    final papers = payload['papers'] as List<Object?>;
    expect((papers[0] as Map<Object?, Object?>)['trayLabel'], 'Task - First');
    expect(
      (papers[1] as Map<Object?, Object?>)['trayLabel'],
      'ScriptLocal - Second (hidden-l10n, collapsed-l10n, desktop-l10n, topmost-l10n)',
    );
  });

  test('paper host ignores unknown paper-id surface events', () async {
    const channel = MethodChannel('repapertodo/window_unknown_event_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final activePaper = PaperData(
      id: 'active-paper',
      type: PaperTypes.todo,
      title: 'Active',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );

    await services.paperWindows.showPaper(activePaper);
    var updateEmitted = false;
    final subscription = services.paperWindows.surfaceUpdates.listen((_) {
      updateEmitted = true;
    });
    addTearDown(subscription.cancel);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('boundsChanged', {
          'paperId': 'unknown-paper',
          'bounds': {
            'x': 700,
            'y': 800,
            'width': 900,
            'height': 1000,
          },
        }),
      ),
      (_) {},
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('closeRequested', {'paperId': 'unknown-paper'}),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(updateEmitted, false);
    expect(activePaper.x, 10);
    expect(activePaper.y, 20);
    expect(activePaper.width, 320);
    expect(activePaper.height, 260);
    expect(activePaper.isVisible, true);

    final legacyCloseUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('closeRequested'),
      ),
      (_) {},
    );

    expect((await legacyCloseUpdate).id, 'active-paper');
    expect(activePaper.isVisible, false);
  });

  test('paper host ignores blank explicit paper-id surface events', () async {
    const channel = MethodChannel('repapertodo/window_blank_event_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final activePaper = PaperData(
      id: 'active-paper',
      type: PaperTypes.todo,
      title: 'Active',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );

    await services.paperWindows.showPaper(activePaper);
    var updateEmitted = false;
    final subscription = services.paperWindows.surfaceUpdates.listen((_) {
      updateEmitted = true;
    });
    addTearDown(subscription.cancel);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('boundsChanged', {
          'paperId': '   ',
          'bounds': {
            'x': 700,
            'y': 800,
            'width': 900,
            'height': 1000,
          },
        }),
      ),
      (_) {},
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('closeRequested', {'paperId': ''}),
      ),
      (_) {},
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('hideRequested', {'paperId': null}),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(updateEmitted, false);
    expect(activePaper.x, 10);
    expect(activePaper.y, 20);
    expect(activePaper.width, 320);
    expect(activePaper.height, 260);
    expect(activePaper.isVisible, true);

    final legacyCloseUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('closeRequested'),
      ),
      (_) {},
    );

    expect((await legacyCloseUpdate).id, 'active-paper');
    expect(activePaper.isVisible, false);
  });

  test('paper host rejects unnormalized explicit paper-id events', () async {
    const channel = MethodChannel('repapertodo/window_unsafe_event_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final activePaper = PaperData(
      id: 'active-paper',
      type: PaperTypes.todo,
      title: 'Active',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );

    await services.paperWindows.showPaper(activePaper);
    var updateEmitted = false;
    var openRequestEmitted = false;
    var deleteRequestEmitted = false;
    final updateSubscription = services.paperWindows.surfaceUpdates.listen((_) {
      updateEmitted = true;
    });
    final openSubscription =
        services.paperWindows.paperOpenRequests.listen((_) {
      openRequestEmitted = true;
    });
    final deleteSubscription =
        services.paperWindows.paperDeleteRequests.listen((_) {
      deleteRequestEmitted = true;
    });
    addTearDown(updateSubscription.cancel);
    addTearDown(openSubscription.cancel);
    addTearDown(deleteSubscription.cancel);

    Future<void> send(MethodCall call) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(call),
        (_) {},
      );
    }

    await send(
      const MethodCall('paperRequested', {'paperId': ' active-paper'}),
    );
    await send(
      const MethodCall('paperDeleteRequested', {'paperId': 'active-paper '}),
    );
    await send(
      const MethodCall('boundsChanged', {
        'paperId': 'active-paper\n',
        'bounds': {
          'x': 700,
          'y': 800,
          'width': 900,
          'height': 1000,
        },
      }),
    );
    await send(
      const MethodCall('closeRequested', {'paperId': 'active-paper\u0000'}),
    );
    await send(
      const MethodCall('hideRequested', ' active-paper'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(updateEmitted, false);
    expect(openRequestEmitted, false);
    expect(deleteRequestEmitted, false);
    expect(activePaper.x, 10);
    expect(activePaper.y, 20);
    expect(activePaper.width, 320);
    expect(activePaper.height, 260);
    expect(activePaper.isVisible, true);
  });

  test('tray rebuild prunes stale paper-id event targets', () async {
    const channel = MethodChannel('repapertodo/window_pruned_event_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final remainingPaper = PaperData(
      id: 'remaining-paper',
      type: PaperTypes.todo,
      title: 'Remaining',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );
    final prunedPaper = PaperData(
      id: 'pruned-paper',
      type: PaperTypes.note,
      title: 'Pruned',
      x: 30,
      y: 40,
      width: 420,
      height: 360,
    );

    await services.paperWindows.restoreAll(
      AppState(papers: [remainingPaper, prunedPaper]),
    );
    await services.paperWindows.showPaper(prunedPaper);
    await services.tray.rebuildMenu(AppState(papers: [remainingPaper]));

    var updateEmitted = false;
    final subscription = services.paperWindows.surfaceUpdates.listen((_) {
      updateEmitted = true;
    });
    addTearDown(subscription.cancel);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('boundsChanged', {
          'paperId': 'pruned-paper',
          'bounds': {
            'x': 700,
            'y': 800,
            'width': 900,
            'height': 1000,
          },
        }),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(updateEmitted, false);
    expect(prunedPaper.x, 30);
    expect(prunedPaper.y, 40);
    expect(prunedPaper.width, 420);
    expect(prunedPaper.height, 360);

    final legacyCloseUpdate = services.paperWindows.surfaceUpdates.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('closeRequested'),
      ),
      (_) {},
    );

    expect((await legacyCloseUpdate).id, 'remaining-paper');
    expect(remainingPaper.isVisible, false);
    expect(prunedPaper.isVisible, true);
  });

  test('tray menu uses PaperTodo default titles for blank paper titles',
      () async {
    const channel = MethodChannel('repapertodo/window_blank_title_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final services = WindowsPlatformServices(channel: channel);
    await services.tray.rebuildMenu(
      AppState(
        papers: [
          PaperData(id: 'blank-todo', type: PaperTypes.todo, title: '   '),
          PaperData(id: 'blank-note-1', type: PaperTypes.note),
          PaperData(id: 'blank-note-2', type: PaperTypes.note, title: '\u0000'),
        ],
      ),
    );

    final trayMenuCall =
        calls.lastWhere((call) => call.method == 'setTrayMenu');
    final papers = trayMenuCall.arguments as List<Object?>;
    expect((papers[0] as Map<Object?, Object?>)['title'], 'Todo1');
    expect((papers[1] as Map<Object?, Object?>)['title'], 'Note1');
    expect((papers[2] as Map<Object?, Object?>)['title'], 'Note2');
  });

  test('startup command events accept string, list, and map arguments',
      () async {
    const channel = MethodChannel('repapertodo/window_startup_event_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final commands = <StartupCommandKind>[];
    final subscription = services.startup.commands.listen(
      (command) => commands.add(command.kind),
    );
    addTearDown(subscription.cancel);

    Future<void> send(Object? arguments) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('startupCommandRequested', arguments),
        ),
        (_) {},
      );
    }

    await send('settings');
    await send(['--unknown', '--new---todo']);
    await send({'command': '/add___note'});
    await send({
      'args': ['--preferences=true'],
    });
    await send({'command': 'unknown'});
    await pumpEventQueue();

    expect(commands, [
      StartupCommandKind.settings,
      StartupCommandKind.newTodo,
      StartupCommandKind.newNote,
      StartupCommandKind.settings,
    ]);
  });

  test('startup command events are buffered until the app subscribes',
      () async {
    const channel = MethodChannel('repapertodo/window_startup_buffer_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('startupCommandRequested', '--new-note'),
      ),
      (_) {},
    );
    await pumpEventQueue();

    final commands = <StartupCommandKind>[];
    final subscription = services.startup.commands.listen(
      (command) => commands.add(command.kind),
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    expect(commands, [StartupCommandKind.newNote]);
  });

  test('paper host ignores minimized bounds events', () async {
    const channel = MethodChannel('repapertodo/window_minimized_bounds_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final paper = PaperData(
      id: 'paper-1',
      type: PaperTypes.todo,
      title: 'Pinned position',
      x: 10,
      y: 20,
      width: 320,
      height: 260,
    );

    await services.paperWindows.showPaper(paper);
    var updateEmitted = false;
    final subscription = services.paperWindows.surfaceUpdates.listen((_) {
      updateEmitted = true;
    });
    addTearDown(subscription.cancel);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('boundsChanged', {
          'paperId': 'paper-1',
          'isMinimized': true,
          'bounds': {
            'x': -32000,
            'y': -32000,
            'width': 160,
            'height': 32,
          },
        }),
      ),
      (_) {},
    );

    expect(paper.x, 10);
    expect(paper.y, 20);
    expect(paper.width, 320);
    expect(paper.height, 260);
    await Future<void>.delayed(Duration.zero);
    expect(updateEmitted, false);
  });

  test('paper host ignores unusable native bounds events', () async {
    const channel = MethodChannel('repapertodo/window_unusable_bounds_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final services = WindowsPlatformServices(channel: channel);
    final paper = PaperData(
      id: 'paper-1',
      type: PaperTypes.note,
      title: 'Stable bounds',
      x: 10,
      y: 20,
      width: 320,
      height: 360,
    );

    await services.paperWindows.showPaper(paper);
    var updateCount = 0;
    final subscription = services.paperWindows.surfaceUpdates.listen((_) {
      updateCount++;
    });
    addTearDown(subscription.cancel);

    Future<void> sendBounds(Map<String, Object?> bounds) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('boundsChanged', {
            'paperId': 'paper-1',
            'bounds': bounds,
          }),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
    }

    await sendBounds({
      'x': -32000,
      'y': -32000,
      'width': 320,
      'height': 360,
    });
    await sendBounds({
      'x': 40,
      'y': 50,
      'width': PaperLayoutDefaults.capsuleWidth,
      'height': PaperLayoutDefaults.capsuleHeight,
    });
    await sendBounds({
      'x': 40,
      'y': 50,
      'width': 0,
      'height': 0,
    });

    expect(updateCount, 0);
    expect(paper.x, 10);
    expect(paper.y, 20);
    expect(paper.width, 320);
    expect(paper.height, 360);
  });

  test('Windows storage host uses the executable directory', () async {
    final host = WindowsAppStorageHost(
      executablePath:
          ' ${p.join('C:\\Tools', 'RePaperTodo', 'repapertodo.exe')} ',
    );

    expect(
      await host.documentsDirectoryPath(),
      p.join('C:\\Tools', 'RePaperTodo'),
    );

    await expectLater(
      const WindowsAppStorageHost(executablePath: '   ')
          .documentsDirectoryPath(),
      throwsA(isA<StateError>()),
    );

    await expectLater(
      const WindowsAppStorageHost(
        executablePath: 'C:\\Tools\\RePaperTodo\\bad\u0000name.exe',
      ).documentsDirectoryPath(),
      throwsA(isA<StateError>()),
    );
  });
}

List<MethodCall> _withoutQueueMonitorNormalization(List<MethodCall> calls) {
  return [
    for (final call in calls)
      if (call.method != 'normalizeQueueMonitorDeviceName') call,
  ];
}

const _localizedTrayLabels = TrayMenuLabels(
  newTodo: '+ Local todo',
  newNote: '+ Local note',
  settings: 'Local settings',
  showAll: 'Show local papers',
  hideAll: 'Hide local papers',
  toggleAll: 'Toggle local papers',
  papers: 'Local papers',
  deletePaper: 'Delete local paper...',
  deleteConfirmTitle: 'Delete local paper?',
  deleteConfirmMessage: 'Delete local "{0}"?',
  inlineConfirmDelete: 'Remove local',
  inlineConfirmAction: 'Confirm local',
  cancel: 'Cancel local',
  exit: 'Local exit',
  todoPaper: 'Task',
  notePaper: 'Memo',
  scriptPaper: 'ScriptLocal',
  hidden: 'hidden-l10n',
  collapsed: 'collapsed-l10n',
  desktop: 'desktop-l10n',
  topmost: 'topmost-l10n',
);
