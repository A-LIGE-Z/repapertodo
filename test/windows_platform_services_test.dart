import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
      alwaysOnTop: true,
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
    await services.externalFiles.openFile('C:\\Temp\\note.md');

    expect(
      calls.map((call) => call.method),
      [
        'setBounds',
        'show',
        'setTitle',
        'setAlwaysOnTop',
        'getBounds',
        'hide',
        'setTrayMenu',
        'setStartupAtLogin',
        'setHideFromWindowSwitcher',
        'setFullscreenTopmostMode',
        'registerGlobalHotkeys',
        'unregisterGlobalHotkeys',
        'isForegroundFullscreen',
        'openExternalFile',
      ],
    );
    expect(foregroundFullscreen, true);
    expect((await startupCommand).kind, StartupCommandKind.newTodo);
    expect(calls[0].arguments, {
      'x': 10.0,
      'y': 20.0,
      'width': 320.0,
      'height': 260.0,
    });
    expect(calls[2].arguments, 'RePaperTodo - Inbox');
    expect(calls[3].arguments, true);
    expect(paper.x, 55);
    expect(paper.y, 66);
    expect(paper.width, 520);
    expect(paper.height, 460);
    expect(paper.isVisible, false);
    expect(calls[6].arguments, [
      {
        'id': 'paper-1',
        'title': 'Inbox',
        'type': PaperTypes.todo,
        'isVisible': false,
      },
    ]);
    expect(calls[7].arguments, true);
    expect(calls[8].arguments, true);
    expect(calls[9].arguments, FullscreenTopmostModes.stayOnTop);
    expect(calls[10].arguments, {
      'todo': 'Ctrl+Alt+T',
      'note': 'Ctrl+Alt+N',
    });
    expect(calls[11].arguments, isNull);
    expect(calls[12].arguments, isNull);
    expect(calls.last.arguments, 'C:\\Temp\\note.md');
  });
}
