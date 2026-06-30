import 'dart:async';

import 'package:flutter/services.dart';

import '../core/model/app_state.dart';
import '../core/model/paper_data.dart';
import '../core/startup/startup_command.dart';
import 'platform_services.dart';

class WindowsPlatformServices implements PlatformServices {
  WindowsPlatformServices({
    MethodChannel channel = const MethodChannel('repapertodo/window'),
  })  : paperWindows = WindowsPaperWindowHost(channel),
        tray = WindowsTrayHost(),
        startup = WindowsStartupHost(),
        systemIntegration = WindowsSystemIntegrationHost(channel);

  @override
  final PaperWindowHost paperWindows;

  @override
  final TrayHost tray;

  @override
  final StartupHost startup;

  @override
  final SystemIntegrationHost systemIntegration;
}

class WindowsPaperWindowHost implements PaperWindowHost {
  WindowsPaperWindowHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> closePaperSurface(PaperData paper) async {
    paper.isVisible = false;
    await _channel.invokeMethod<void>('hide');
  }

  @override
  Future<void> hidePaper(PaperData paper) async {
    paper.isVisible = false;
    await _channel.invokeMethod<void>('hide');
  }

  @override
  Future<void> restoreAll(AppState state) async {
    final visiblePapers =
        state.papers.where((paper) => paper.isVisible).toList();
    if (visiblePapers.isEmpty) {
      await _channel.invokeMethod<void>('hide');
      return;
    }
    await _channel.invokeMethod<void>('show');
    await _channel.invokeMethod<void>(
        'setTitle', _windowTitle(visiblePapers.first));
    await _channel.invokeMethod<void>(
      'setAlwaysOnTop',
      visiblePapers.any((paper) => paper.alwaysOnTop),
    );
  }

  @override
  Future<void> showPaper(PaperData paper) async {
    paper.isVisible = true;
    await _channel.invokeMethod<void>('show');
    await _channel.invokeMethod<void>('setTitle', _windowTitle(paper));
    await _channel.invokeMethod<void>('setAlwaysOnTop', paper.alwaysOnTop);
  }

  String _windowTitle(PaperData paper) {
    final title = paper.title.trim();
    return title.isEmpty ? 'RePaperTodo' : 'RePaperTodo - $title';
  }
}

class WindowsTrayHost implements TrayHost {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> rebuildMenu(AppState state) async {}
}

class WindowsStartupHost implements StartupHost {
  @override
  Future<bool> acquireSingleInstance() async => true;

  @override
  Stream<StartupCommand> get commands => const Stream.empty();

  @override
  Future<void> forwardToPrimary(List<String> args) async {}
}

class WindowsSystemIntegrationHost implements SystemIntegrationHost {
  WindowsSystemIntegrationHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<bool> isForegroundFullscreen() async => false;

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {}

  @override
  Future<void> setStartupAtLogin(bool enabled) async {}

  @override
  Future<void> unregisterGlobalHotkeys() async {}

  Future<void> setAlwaysOnTop(bool enabled) async {
    await _channel.invokeMethod<void>('setAlwaysOnTop', enabled);
  }
}
