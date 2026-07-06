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
    await services.uriOpener.openUri(' https://example.com/paper ');
    await services.externalFiles.openFile(' /tmp/RePaperTodo/paper-1.md ');

    expect(calls.map((call) => call.method), [
      'getFilesDirectory',
      'openUri',
      'openExternalFile',
    ]);
    expect(documentsPath, '/data/user/0/com.aligez.repapertodo/files');
    expect(calls[1].arguments, 'https://example.com/paper');
    expect(calls[2].arguments, '/tmp/RePaperTodo/paper-1.md');
  });

  test('Android platform services reject blank channel arguments locally',
      () async {
    const channel = MethodChannel('repapertodo/android_blank_test');
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
      services.externalFiles.openFile('/tmp/RePaperTodo/bad\nnote.md'),
      throwsA(isA<ArgumentError>()),
    );

    expect(calls, isEmpty);
  });

  test('platform services reject C1 controls without blocking UTF-8 escapes',
      () async {
    const androidChannel = MethodChannel('repapertodo/android_c1_test');
    const windowsChannel = MethodChannel('repapertodo/windows_c1_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, (call) async {
      calls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowsChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowsChannel, null);
    });

    final hosts = [
      (
        uriOpener: AndroidPlatformServices(channel: androidChannel).uriOpener,
        externalFiles:
            AndroidPlatformServices(channel: androidChannel).externalFiles,
      ),
      (
        uriOpener: WindowsPlatformServices(channel: windowsChannel).uriOpener,
        externalFiles:
            WindowsPlatformServices(channel: windowsChannel).externalFiles,
      ),
    ];

    for (final host in hosts) {
      await expectLater(
        host.uriOpener.openUri('https://example.com/\u0085path'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        host.uriOpener.openUri('https://example.com/%C2%85path'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        host.uriOpener.openUri('https://example.com/%85path'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        host.externalFiles.openFile('/tmp/RePaperTodo/bad\u0085note.md'),
        throwsA(isA<ArgumentError>()),
      );

      await host.uriOpener.openUri('https://example.com/%E2%82%ACpath');
    }

    expect(calls.map((call) => call.arguments), [
      'https://example.com/%E2%82%ACpath',
      'https://example.com/%E2%82%ACpath',
    ]);
  });

  test('platform services reject unsupported URI schemes locally', () async {
    const androidChannel = MethodChannel('repapertodo/android_scheme_test');
    const windowsChannel = MethodChannel('repapertodo/windows_scheme_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, (call) async {
      calls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowsChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowsChannel, null);
    });

    final openers = [
      AndroidPlatformServices(channel: androidChannel).uriOpener,
      WindowsPlatformServices(channel: windowsChannel).uriOpener,
    ];

    for (final opener in openers) {
      await expectLater(
        opener.openUri('ftp://example.com/file'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        opener.openUri('javascript:alert(1)'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        opener.openUri('https:///missing-host'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        opener.openUri('mailto:?subject=paper'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        opener.openUri('mailto://paper@example.com'),
        throwsA(isA<ArgumentError>()),
      );

      await opener.openUri('mailto:paper@example.com');
    }

    expect(calls.map((call) => call.arguments), [
      'mailto:paper@example.com',
      'mailto:paper@example.com',
    ]);
  });
}
