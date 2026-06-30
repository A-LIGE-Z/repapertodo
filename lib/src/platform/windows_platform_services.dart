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
  Future<void> capturePaperSurfaceBounds(PaperData paper) async {
    final bounds = await _channel.invokeMapMethod<String, Object?>('getBounds');
    if (bounds == null) {
      return;
    }
    paper
      ..x = _doubleValue(bounds['x'], paper.x)
      ..y = _doubleValue(bounds['y'], paper.y)
      ..width = _doubleValue(bounds['width'], paper.width)
      ..height = _doubleValue(bounds['height'], paper.height);
    paper.normalize();
  }

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
    await _applyBounds(visiblePapers.first);
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
    await _applyBounds(paper);
    await _channel.invokeMethod<void>('show');
    await _channel.invokeMethod<void>('setTitle', _windowTitle(paper));
    await _channel.invokeMethod<void>('setAlwaysOnTop', paper.alwaysOnTop);
  }

  @override
  Future<void> updatePaperSurface(PaperData paper) async {
    if (!paper.isVisible) {
      return;
    }
    await _applyBounds(paper);
    await _channel.invokeMethod<void>('setTitle', _windowTitle(paper));
    await _channel.invokeMethod<void>('setAlwaysOnTop', paper.alwaysOnTop);
  }

  Future<void> _applyBounds(PaperData paper) async {
    await _channel.invokeMethod<void>('setBounds', {
      'x': paper.x,
      'y': paper.y,
      'width': paper.width,
      'height': paper.height,
    });
  }

  String _windowTitle(PaperData paper) {
    final title = paper.title.trim();
    return title.isEmpty ? 'RePaperTodo' : 'RePaperTodo - $title';
  }

  double _doubleValue(Object? value, double fallback) {
    if (value is num && value.isFinite) {
      return value.toDouble();
    }
    return fallback;
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
