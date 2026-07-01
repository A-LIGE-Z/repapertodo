import 'dart:async';

import 'package:flutter/services.dart';

import '../core/model/app_state.dart';
import '../core/model/paper_constants.dart';
import '../core/model/paper_data.dart';
import '../core/script/script_capsule.dart';
import '../core/startup/startup_command.dart';
import 'platform_services.dart';

class WindowsPlatformServices implements PlatformServices {
  WindowsPlatformServices({
    MethodChannel channel = const MethodChannel('repapertodo/window'),
  }) : this._(channel, WindowsStartupHost(channel));

  WindowsPlatformServices._(
    MethodChannel channel,
    WindowsStartupHost startupHost,
  )   : paperWindows = WindowsPaperWindowHost(channel, startupHost),
        tray = WindowsTrayHost(channel),
        startup = startupHost,
        systemIntegration = WindowsSystemIntegrationHost(channel),
        externalFiles = WindowsExternalFileHost(channel),
        scriptCapsules = WindowsScriptCapsuleHost(channel);

  @override
  final PaperWindowHost paperWindows;

  @override
  final TrayHost tray;

  @override
  final StartupHost startup;

  @override
  final SystemIntegrationHost systemIntegration;

  @override
  final ExternalFileHost externalFiles;

  @override
  final ScriptCapsuleHost scriptCapsules;
}

class WindowsPaperWindowHost implements PaperWindowHost {
  WindowsPaperWindowHost(this._channel, this._startupHost) {
    _channel.setMethodCallHandler(_handleWindowEvent);
  }

  final MethodChannel _channel;
  final WindowsStartupHost _startupHost;
  final StreamController<PaperData> _surfaceUpdates =
      StreamController<PaperData>.broadcast();
  final StreamController<String> _paperOpenRequests =
      StreamController<String>.broadcast();
  PaperData? _activePaper;

  @override
  Stream<PaperData> get surfaceUpdates => _surfaceUpdates.stream;

  @override
  Stream<String> get paperOpenRequests => _paperOpenRequests.stream;

  Future<void> _handleWindowEvent(MethodCall call) async {
    final paper = _activePaper;
    switch (call.method) {
      case 'paperRequested':
        final paperId = call.arguments;
        if (paperId is String && paperId.trim().isNotEmpty) {
          _paperOpenRequests.add(paperId);
        }
      case 'boundsChanged':
        if (paper == null) {
          return;
        }
        final arguments = call.arguments;
        if (arguments is Map) {
          _applyBoundsToPaper(paper, arguments);
          _surfaceUpdates.add(paper);
        }
      case 'closeRequested':
        if (paper == null) {
          return;
        }
        paper.isVisible = false;
        _surfaceUpdates.add(paper);
      case 'showRequested':
        if (paper == null) {
          return;
        }
        paper.isVisible = true;
        _surfaceUpdates.add(paper);
      case 'hideRequested':
        if (paper == null) {
          return;
        }
        paper.isVisible = false;
        _surfaceUpdates.add(paper);
      case 'startupCommandRequested':
        final command = StartupCommand.parse([
          if (call.arguments is String) call.arguments as String,
        ]);
        if (command.kind != StartupCommandKind.none) {
          _startupHost.addCommand(command);
        }
    }
  }

  @override
  Future<void> capturePaperSurfaceBounds(PaperData paper) async {
    final bounds = await _channel.invokeMapMethod<String, Object?>('getBounds');
    if (bounds == null) {
      return;
    }
    _applyBoundsToPaper(paper, Map<Object?, Object?>.from(bounds));
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
    _activePaper = visiblePapers.first;
    await _applyBounds(visiblePapers.first);
    await _channel.invokeMethod<void>(
      'setPinnedToDesktop',
      visiblePapers.first.isPinnedToDesktop,
    );
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
    _activePaper = paper;
    await _applyBounds(paper);
    await _channel.invokeMethod<void>(
      'setPinnedToDesktop',
      paper.isPinnedToDesktop,
    );
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
    await _channel.invokeMethod<void>(
      'setPinnedToDesktop',
      paper.isPinnedToDesktop,
    );
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

  void _applyBoundsToPaper(PaperData paper, Map<Object?, Object?> bounds) {
    paper
      ..x = _doubleValue(bounds['x'], paper.x)
      ..y = _doubleValue(bounds['y'], paper.y)
      ..width = _doubleValue(bounds['width'], paper.width)
      ..height = _doubleValue(bounds['height'], paper.height);
    paper.normalize();
  }
}

class WindowsTrayHost implements TrayHost {
  WindowsTrayHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod<void>('setTrayMenu', const <Object?>[]);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> rebuildMenu(AppState state) async {
    await _channel.invokeMethod<void>(
      'setTrayMenu',
      state.papers.map((paper) {
        final title = paper.title.trim();
        return <String, Object?>{
          'id': paper.id,
          'title': title.isEmpty ? 'Untitled' : title,
          'type': paper.type,
          'isVisible': paper.isVisible,
        };
      }).toList(),
    );
  }
}

class WindowsStartupHost implements StartupHost {
  WindowsStartupHost(this._channel);

  final MethodChannel _channel;
  final StreamController<StartupCommand> _commands =
      StreamController<StartupCommand>.broadcast();

  @override
  Future<bool> acquireSingleInstance() async {
    return await _channel.invokeMethod<bool>('acquireSingleInstance') ?? true;
  }

  @override
  Stream<StartupCommand> get commands => _commands.stream;

  @override
  Future<void> forwardToPrimary(List<String> args) async {
    await _channel.invokeMethod<void>('forwardToPrimary', args);
  }

  void addCommand(StartupCommand command) {
    _commands.add(command);
  }
}

class WindowsSystemIntegrationHost implements SystemIntegrationHost {
  WindowsSystemIntegrationHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<bool> isForegroundFullscreen() async {
    return await _channel.invokeMethod<bool>('isForegroundFullscreen') ?? false;
  }

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {
    await _channel.invokeMethod<void>('registerGlobalHotkeys', {
      'todo': state.pinnedTodoHotKey,
      'note': state.pinnedNoteHotKey,
    });
  }

  @override
  Future<void> setStartupAtLogin(bool enabled) async {
    await _channel.invokeMethod<void>('setStartupAtLogin', enabled);
  }

  @override
  Future<void> setHideFromWindowSwitcher(bool enabled) async {
    await _channel.invokeMethod<void>('setHideFromWindowSwitcher', enabled);
  }

  @override
  Future<void> setFullscreenTopmostMode(String mode) async {
    await _channel.invokeMethod<void>(
      'setFullscreenTopmostMode',
      FullscreenTopmostModes.normalize(mode),
    );
  }

  @override
  Future<void> unregisterGlobalHotkeys() async {
    await _channel.invokeMethod<void>('unregisterGlobalHotkeys');
  }

  Future<void> setAlwaysOnTop(bool enabled) async {
    await _channel.invokeMethod<void>('setAlwaysOnTop', enabled);
  }
}

class WindowsExternalFileHost implements ExternalFileHost {
  WindowsExternalFileHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> openFile(String path) async {
    await _channel.invokeMethod<void>('openExternalFile', path);
  }
}

class WindowsScriptCapsuleHost implements ScriptCapsuleHost {
  WindowsScriptCapsuleHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> runScriptCapsule(ScriptCapsuleRunRequest request) async {
    await _channel.invokeMethod<void>('runScriptCapsule', request.toJson());
  }
}
