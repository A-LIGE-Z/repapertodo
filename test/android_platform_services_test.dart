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
      if (call.method == 'getFilesDirectory') {
        return ' /data/user/0/com.aligez.repapertodo/files ';
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final services = AndroidPlatformServices(channel: channel);
    expect(services.systemIntegration.supportsStartupAtLogin, false);
    expect(services.systemIntegration.supportsWindowSwitcherVisibility, false);
    expect(services.systemIntegration.supportsFullscreenTopmostMode, false);
    expect(services.systemIntegration.supportsGlobalHotkeys, false);
    expect(services.scriptCapsules.supportsScriptCapsules, false);

    final documentsPath = await services.storage.documentsDirectoryPath();
    await services.uriOpener.openUri('https://example.com/paper');
    await services.externalFiles.openFile('/tmp/RePaperTodo/paper-1.md');

    expect(calls.map((call) => call.method), [
      'getFilesDirectory',
      'openUri',
      'openExternalFile',
    ]);
    expect(documentsPath, '/data/user/0/com.aligez.repapertodo/files');
    expect(calls[1].arguments, 'https://example.com/paper');
    expect(calls[2].arguments, '/tmp/RePaperTodo/paper-1.md');
  });
}
