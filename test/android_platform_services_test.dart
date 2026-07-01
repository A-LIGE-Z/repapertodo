import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android platform services send method channel calls', () async {
    const channel = MethodChannel('repapertodo/android_test');
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

    final services = AndroidPlatformServices(channel: channel);
    await services.uriOpener.openUri('https://example.com/paper');
    await services.externalFiles.openFile('/tmp/RePaperTodo/paper-1.md');

    expect(calls.map((call) => call.method), [
      'openUri',
      'openExternalFile',
    ]);
    expect(calls[0].arguments, 'https://example.com/paper');
    expect(calls[1].arguments, '/tmp/RePaperTodo/paper-1.md');
  });
}
