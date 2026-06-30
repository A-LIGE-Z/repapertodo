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
    await services.paperWindows.hidePaper(paper);

    expect(
      calls.map((call) => call.method),
      ['setBounds', 'show', 'setTitle', 'setAlwaysOnTop', 'getBounds', 'hide'],
    );
    expect(calls[0].arguments, {
      'x': 10.0,
      'y': 20.0,
      'width': 320.0,
      'height': 260.0,
    });
    expect(calls[2].arguments, 'RePaperTodo - Inbox');
    expect(calls[3].arguments, true);
    expect(paper.x, 33);
    expect(paper.y, 44);
    expect(paper.width, 420);
    expect(paper.height, 360);
    expect(paper.isVisible, false);
  });
}
