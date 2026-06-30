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
      alwaysOnTop: true,
    );

    await services.paperWindows.showPaper(paper);
    await services.paperWindows.hidePaper(paper);

    expect(
      calls.map((call) => call.method),
      ['show', 'setTitle', 'setAlwaysOnTop', 'hide'],
    );
    expect(calls[1].arguments, 'RePaperTodo - Inbox');
    expect(calls[2].arguments, true);
    expect(paper.isVisible, false);
  });
}
