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

    expect(
      calls.map((call) => call.method),
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
    expect(calls[0].arguments, {
      'paperId': 'paper-1',
      'x': 10.0,
      'y': 20.0,
      'width': 320.0,
      'height': 260.0,
    });
    expect(calls[1].arguments, {
      'paperId': 'paper-1',
      'enabled': true,
    });
    expect(calls[2].arguments, {
      'paperId': 'paper-1',
      'isPinnedToDesktop': true,
      'alwaysOnTop': false,
    });
    expect(calls[3].arguments, 'RePaperTodo - Inbox');
    expect(calls[4].arguments, {
      'paperId': 'paper-1',
      'enabled': false,
    });
    expect(calls[5].arguments, 'paper-1');
    expect(calls[6].arguments, {
      'paperId': 'paper-1',
      'isPinnedToDesktop': true,
      'alwaysOnTop': false,
    });
    expect(paper.x, 55);
    expect(paper.y, 66);
    expect(paper.width, 520);
    expect(paper.height, 460);
    expect(paper.isVisible, false);
    expect(calls[7].arguments, [
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
        'alwaysOnTop': false,
        'isPinnedToDesktop': true,
        'isScriptCapsule': false,
      },
    ]);
    expect(acquiredSingleInstance, true);
    expect(calls[8].arguments, isNull);
    expect(calls[9].arguments, ['--new-note']);
    expect(calls[10].arguments, true);
    expect(calls[11].arguments, true);
    expect(calls[12].arguments, FullscreenTopmostModes.stayOnTop);
    expect(calls[13].arguments, {
      'todo': 'Ctrl+Alt+T',
      'note': 'Ctrl+Alt+N',
    });
    expect(calls[14].arguments, isNull);
    expect(calls[15].arguments, isNull);
    expect(calls[16].arguments, isNull);
    expect(calls[17].arguments, 'C:\\Temp\\note.md');
    expect(calls[18].arguments, 'https://example.com/paper');
    expect(calls[19].arguments, {
      'engine': 'pwsh',
      'script': 'Write-Output ok',
      'usePersistentProcess': true,
      'usePersistentPowerShellProcess': true,
      'preferPowerShell7': true,
      'hideScriptRunWindow': true,
    });
    expect(calls[20].arguments, {
      'preferPowerShell7': false,
      'hideScriptRunWindow': false,
    });
    expect(calls.last.arguments, isNull);
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
    expect(calls.single.method, 'getWorkArea');
    expect(calls.single.arguments, {
      'paperId': 'paper-1',
      'x': 10.0,
      'y': 20.0,
      'width': 320.0,
      'height': 260.0,
      'monitorDeviceName': r'\\.\DISPLAY2',
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
    );

    await services.paperWindows.restoreAll(
      AppState(papers: [firstPaper, secondPaper]),
    );
    expect(
      calls.map((call) => call.method),
      [
        'setTrayMenu',
        'setBounds',
        'setPinnedToDesktop',
        'show',
        'setTitle',
        'setAlwaysOnTop',
      ],
    );
    final initialTrayMenuCall =
        calls.firstWhere((call) => call.method == 'setTrayMenu');
    expect(initialTrayMenuCall.arguments, [
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
        'alwaysOnTop': true,
        'isPinnedToDesktop': false,
        'isScriptCapsule': true,
      },
    ]);
    expect(calls[1].arguments, {
      'paperId': 'paper-1',
      'x': 10.0,
      'y': 20.0,
      'width': 320.0,
      'height': 260.0,
    });
    expect(calls[2].arguments, {
      'paperId': 'paper-1',
      'enabled': false,
    });
    expect(calls[3].arguments, {
      'paperId': 'paper-1',
      'isPinnedToDesktop': false,
      'alwaysOnTop': false,
    });
    expect(calls[4].arguments, 'RePaperTodo - First');
    expect(calls[5].arguments, {
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
        'alwaysOnTop': true,
        'isPinnedToDesktop': false,
        'isScriptCapsule': true,
      },
    ]);
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
  });
}
