import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/model/app_state.dart';
import '../core/model/paper_constants.dart';
import '../core/model/paper_data.dart';
import '../core/model/paper_titles.dart';
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
  ) : this._withPaperHost(
          channel,
          startupHost,
          WindowsPaperWindowHost(channel, startupHost),
        );

  WindowsPlatformServices._withPaperHost(
    MethodChannel channel,
    WindowsStartupHost startupHost,
    WindowsPaperWindowHost paperWindowHost,
  )   : paperWindows = paperWindowHost,
        tray = WindowsTrayHost(channel, paperWindowHost),
        startup = startupHost,
        systemIntegration = WindowsSystemIntegrationHost(channel),
        externalFiles = WindowsExternalFileHost(channel),
        uriOpener = WindowsUriOpenHost(channel),
        scriptCapsules = WindowsScriptCapsuleHost(channel),
        storage = WindowsAppStorageHost();

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
  final UriOpenHost uriOpener;

  @override
  final ScriptCapsuleHost scriptCapsules;

  @override
  final AppStorageHost storage;
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
  final StreamController<String> _paperDeleteRequests =
      StreamController<String>.broadcast();
  final Map<String, PaperData> _knownPapers = <String, PaperData>{};
  PaperData? _activePaper;

  @override
  Stream<PaperData> get surfaceUpdates => _surfaceUpdates.stream;

  @override
  Stream<String> get paperOpenRequests => _paperOpenRequests.stream;

  @override
  Stream<String> get paperDeleteRequests => _paperDeleteRequests.stream;

  @override
  Future<PaperWorkArea?> workAreaForPaper(PaperData paper) async {
    _rememberPaper(paper);
    final workArea = await _channel.invokeMapMethod<String, Object?>(
      'getWorkArea',
      {
        'paperId': paper.id,
        'x': paper.x,
        'y': paper.y,
        'width': paper.width,
        'height': paper.height,
        'monitorDeviceName': paper.capsuleMonitorDeviceName,
      },
    );
    if (workArea == null) {
      return null;
    }
    return _workAreaFromMap(Map<Object?, Object?>.from(workArea));
  }

  Future<void> _handleWindowEvent(MethodCall call) async {
    switch (call.method) {
      case 'paperRequested':
        final paperId = _paperIdFromArguments(call.arguments);
        if (paperId != null) {
          _paperOpenRequests.add(paperId);
        }
      case 'paperDeleteRequested':
        final paperId = _paperIdFromArguments(call.arguments);
        if (paperId != null) {
          _paperDeleteRequests.add(paperId);
        }
      case 'boundsChanged':
        final paper = _paperFromEventArguments(call.arguments);
        if (paper == null) {
          return;
        }
        if (_isMinimizedBoundsEvent(call.arguments)) {
          return;
        }
        final bounds = _boundsFromArguments(call.arguments);
        if (bounds != null) {
          _applyBoundsToPaper(paper, bounds);
          _surfaceUpdates.add(paper);
        }
      case 'closeRequested':
        final paper = _paperFromEventArguments(call.arguments);
        if (paper == null) {
          return;
        }
        paper.isVisible = false;
        _activePaper = paper;
        _surfaceUpdates.add(paper);
      case 'showRequested':
        final paper = _paperFromEventArguments(call.arguments);
        if (paper == null) {
          return;
        }
        paper.isVisible = true;
        _activePaper = paper;
        _surfaceUpdates.add(paper);
      case 'hideRequested':
        final paper = _paperFromEventArguments(call.arguments);
        if (paper == null) {
          return;
        }
        paper.isVisible = false;
        _activePaper = paper;
        _surfaceUpdates.add(paper);
      case 'startupCommandRequested':
        final command = StartupCommand.parse(_startupCommandArgs(
          call.arguments,
        ));
        if (command.kind != StartupCommandKind.none) {
          _startupHost.addCommand(command);
        }
    }
  }

  @override
  Future<void> capturePaperSurfaceBounds(PaperData paper) async {
    _rememberPaper(paper);
    final bounds = await _channel.invokeMapMethod<String, Object?>(
      'getBounds',
      paper.id,
    );
    if (bounds == null) {
      return;
    }
    _applyBoundsToPaper(paper, Map<Object?, Object?>.from(bounds));
  }

  @override
  Future<void> closePaperSurface(PaperData paper) async {
    paper.isVisible = false;
    _rememberPaper(paper);
    await _channel.invokeMethod<void>('hide', _paperSurfaceArguments(paper));
  }

  @override
  Future<void> hidePaper(PaperData paper) async {
    paper.isVisible = false;
    _rememberPaper(paper);
    await _channel.invokeMethod<void>('hide', _paperSurfaceArguments(paper));
  }

  @override
  Future<void> restoreAll(AppState state) async {
    _syncKnownPapers(state);
    await _syncPaperSurfaceRegistry(state);
    final visiblePapers =
        state.papers.where((paper) => paper.isVisible).toList();
    if (visiblePapers.isEmpty) {
      _activePaper = null;
      await _channel.invokeMethod<void>('hide');
      return;
    }
    _activePaper = visiblePapers.first;
    await _applyBounds(visiblePapers.first);
    await _channel.invokeMethod<void>(
      'setPinnedToDesktop',
      _paperSurfaceFlagArguments(
        visiblePapers.first,
        visiblePapers.first.isPinnedToDesktop,
      ),
    );
    await _channel.invokeMethod<void>(
      'show',
      _paperSurfaceArguments(visiblePapers.first),
    );
    await _channel.invokeMethod<void>(
      'setTitle',
      _paperTitleArguments(visiblePapers.first),
    );
    await _channel.invokeMethod<void>(
      'setAlwaysOnTop',
      _paperSurfaceFlagArguments(
        visiblePapers.first,
        visiblePapers.first.alwaysOnTop,
      ),
    );
  }

  @override
  Future<void> showPaper(PaperData paper) async {
    paper.isVisible = true;
    _rememberPaper(paper);
    _activePaper = paper;
    await _applyBounds(paper);
    await _channel.invokeMethod<void>(
      'setPinnedToDesktop',
      _paperSurfaceFlagArguments(paper, paper.isPinnedToDesktop),
    );
    await _channel.invokeMethod<void>('show', _paperSurfaceArguments(paper));
    await _channel.invokeMethod<void>('setTitle', _paperTitleArguments(paper));
    await _channel.invokeMethod<void>(
      'setAlwaysOnTop',
      _paperSurfaceFlagArguments(paper, paper.alwaysOnTop),
    );
  }

  @override
  Future<void> updatePaperSurface(PaperData paper) async {
    _rememberPaper(paper);
    if (!paper.isVisible) {
      return;
    }
    await _applyBounds(paper);
    await _channel.invokeMethod<void>(
      'setPinnedToDesktop',
      _paperSurfaceFlagArguments(paper, paper.isPinnedToDesktop),
    );
    await _channel.invokeMethod<void>('setTitle', _paperTitleArguments(paper));
    await _channel.invokeMethod<void>(
      'setAlwaysOnTop',
      _paperSurfaceFlagArguments(paper, paper.alwaysOnTop),
    );
  }

  Map<String, Object?> _paperSurfaceArguments(PaperData paper) {
    return {
      'paperId': paper.id,
      'isPinnedToDesktop': paper.isPinnedToDesktop,
      'alwaysOnTop': paper.alwaysOnTop,
    };
  }

  Map<String, Object?> _paperTitleArguments(PaperData paper) {
    return {
      'paperId': paper.id,
      'title': _windowTitle(paper),
    };
  }

  Map<String, Object?> _paperSurfaceFlagArguments(
      PaperData paper, bool enabled) {
    return {
      'paperId': paper.id,
      'enabled': enabled,
    };
  }

  Future<void> _applyBounds(PaperData paper) async {
    await _channel.invokeMethod<void>('setBounds', {
      'paperId': paper.id,
      'x': paper.x,
      'y': paper.y,
      'width': paper.width,
      'height': paper.height,
    });
  }

  Future<void> _syncPaperSurfaceRegistry(AppState state) async {
    await _channel.invokeMethod<void>(
      'setTrayMenu',
      _paperSurfaceRegistryEntries(state),
    );
  }

  void _rememberPaper(PaperData paper) {
    final paperId = paper.id.trim();
    if (paperId.isEmpty) {
      return;
    }
    _knownPapers[paperId] = paper;
  }

  void _syncKnownPapers(AppState state) {
    _knownPapers.clear();
    for (final paper in state.papers) {
      _rememberPaper(paper);
    }
    final activePaperId = _activePaper?.id.trim() ?? '';
    if (activePaperId.isNotEmpty && _knownPapers.containsKey(activePaperId)) {
      _activePaper = _knownPapers[activePaperId];
      return;
    }
    _activePaper = null;
    for (final paper in state.papers) {
      if (paper.isVisible && _knownPapers.containsKey(paper.id.trim())) {
        _activePaper = paper;
        return;
      }
    }
  }

  PaperData? _paperFromEventArguments(Object? arguments) {
    final paperId = _paperIdFromArguments(arguments);
    if (paperId == null) {
      return _activePaper;
    }
    return _knownPapers[paperId];
  }

  String? _paperIdFromArguments(Object? arguments) {
    if (arguments is String) {
      final trimmed = arguments.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final map = _argumentMap(arguments);
    final value = map?['paperId'];
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  Map<Object?, Object?>? _boundsFromArguments(Object? arguments) {
    final map = _argumentMap(arguments);
    if (map == null) {
      return null;
    }
    final bounds = map['bounds'];
    if (bounds is Map) {
      return Map<Object?, Object?>.from(bounds);
    }
    return map;
  }

  bool _isMinimizedBoundsEvent(Object? arguments) {
    final map = _argumentMap(arguments);
    if (map == null) {
      return false;
    }
    return map['isMinimized'] == true ||
        map['minimized'] == true ||
        map['windowState'] == 'minimized';
  }

  List<String> _startupCommandArgs(Object? arguments) {
    if (arguments is String) {
      return [arguments];
    }
    if (arguments is List) {
      return [
        for (final argument in arguments)
          if (argument is String) argument,
      ];
    }
    final map = _argumentMap(arguments);
    final command = map?['command'];
    if (command is String) {
      return [command];
    }
    final args = map?['args'];
    if (args is List) {
      return [
        for (final argument in args)
          if (argument is String) argument,
      ];
    }
    return const [];
  }

  Map<Object?, Object?>? _argumentMap(Object? arguments) {
    if (arguments is Map) {
      return Map<Object?, Object?>.from(arguments);
    }
    return null;
  }

  String _windowTitle(PaperData paper) {
    final title = PaperTitles.effectiveTitle(
      paperType: paper.type,
      title: paper.title,
      fallbackNumber: 1,
    );
    return 'RePaperTodo - $title';
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

  PaperWorkArea? _workAreaFromMap(Map<Object?, Object?> map) {
    final workArea = PaperWorkArea(
      x: _doubleValue(map['x'], double.nan),
      y: _doubleValue(map['y'], double.nan),
      width: _doubleValue(map['width'], double.nan),
      height: _doubleValue(map['height'], double.nan),
    );
    return workArea.isUsable ? workArea : null;
  }
}

class WindowsTrayHost implements TrayHost {
  WindowsTrayHost(this._channel, this._paperWindows);

  final MethodChannel _channel;
  final WindowsPaperWindowHost _paperWindows;

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod<void>('setTrayMenu', const <Object?>[]);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> rebuildMenu(AppState state) async {
    _paperWindows._syncKnownPapers(state);
    await _channel.invokeMethod<void>(
      'setTrayMenu',
      _paperSurfaceRegistryEntries(state),
    );
  }
}

List<Map<String, Object?>> _paperSurfaceRegistryEntries(AppState state) {
  final typeCounts = <String, int>{};
  return [
    for (final paper in state.papers)
      _paperSurfaceRegistryEntry(
        paper,
        fallbackNumber: typeCounts.update(
          PaperTypes.normalize(paper.type),
          (value) => value + 1,
          ifAbsent: () => 1,
        ),
      ),
  ];
}

Map<String, Object?> _paperSurfaceRegistryEntry(
  PaperData paper, {
  required int fallbackNumber,
}) {
  final title = PaperTitles.effectiveTitle(
    paperType: paper.type,
    title: paper.title,
    fallbackNumber: fallbackNumber,
  );
  return <String, Object?>{
    'id': paper.id,
    'title': title,
    'type': paper.type,
    'x': paper.x,
    'y': paper.y,
    'width': paper.width,
    'height': paper.height,
    'isVisible': paper.isVisible,
    'isCollapsed': paper.isCollapsed,
    'alwaysOnTop': paper.alwaysOnTop,
    'isPinnedToDesktop': paper.isPinnedToDesktop,
    'isScriptCapsule':
        paper.isNote && ScriptCapsuleSpec.isScriptCapsuleContent(paper.content),
  };
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
  bool get supportsStartupAtLogin => true;

  @override
  bool get supportsWindowSwitcherVisibility => true;

  @override
  bool get supportsFullscreenTopmostMode => true;

  @override
  bool get supportsGlobalHotkeys => true;

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

  @override
  Future<void> exitApplication() async {
    await _channel.invokeMethod<void>('exitApplication');
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
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      throw ArgumentError.value(
        path,
        'path',
        'Windows external file path must not be blank.',
      );
    }
    if (_hasUnsafeExternalFilePathCharacter(path)) {
      throw ArgumentError.value(
        path,
        'path',
        'Windows external file path must not contain control characters.',
      );
    }
    await _channel.invokeMethod<void>('openExternalFile', trimmedPath);
  }
}

class WindowsUriOpenHost implements UriOpenHost {
  WindowsUriOpenHost(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> openUri(String uri) async {
    final trimmedUri = uri.trim();
    if (trimmedUri.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Windows URI must not be blank.');
    }
    if (_hasUnsafeExternalUriCharacter(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Windows URI must not contain control characters.',
      );
    }
    if (_hasEncodedUnsafeExternalUriCharacter(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Windows URI must not contain encoded control characters.',
      );
    }
    if (_hasEncodedExternalUriAuthoritySeparator(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Windows URI must not contain encoded authority separators.',
      );
    }
    await _channel.invokeMethod<void>('openUri', trimmedUri);
  }
}

class WindowsScriptCapsuleHost implements ScriptCapsuleHost {
  WindowsScriptCapsuleHost(this._channel);

  final MethodChannel _channel;

  @override
  bool get supportsScriptCapsules => true;

  @override
  Future<void> preparePersistentProcess({
    required bool preferPowerShell7,
    required bool hideScriptRunWindow,
  }) async {
    await _channel.invokeMethod<void>('preparePersistentScriptCapsule', {
      'preferPowerShell7': preferPowerShell7,
      'hideScriptRunWindow': hideScriptRunWindow,
    });
  }

  @override
  Future<void> runScriptCapsule(ScriptCapsuleRunRequest request) async {
    final engine = request.engine.trim().toLowerCase();
    if (!_allowedScriptCapsuleEngines.contains(engine)) {
      throw ArgumentError.value(
        request.engine,
        'engine',
        'Unsupported Windows script capsule engine.',
      );
    }
    if (request.script.trim().isEmpty) {
      throw ArgumentError.value(
        request.script,
        'script',
        'Windows script capsule must not be blank.',
      );
    }
    await _channel.invokeMethod<void>('runScriptCapsule', {
      ...request.toJson(),
      'engine': engine,
    });
  }

  @override
  Future<void> stopPersistentProcesses() async {
    await _channel.invokeMethod<void>('stopPersistentScriptCapsules');
  }
}

class WindowsAppStorageHost implements AppStorageHost {
  const WindowsAppStorageHost({String? executablePath})
      : _executablePath = executablePath;

  final String? _executablePath;

  @override
  Future<String> documentsDirectoryPath() async {
    final executablePath =
        (_executablePath ?? Platform.resolvedExecutable).trim();
    if (executablePath.isEmpty) {
      throw StateError('Windows executable path is unavailable.');
    }
    return p.dirname(executablePath);
  }
}

bool _hasEncodedUnsafeExternalUriCharacter(String value) {
  try {
    return Uri.decodeFull(value).runes.any(_isControlRune);
  } on FormatException {
    // Malformed escapes should still reject obvious percent-encoded controls.
  }
  for (final match in RegExp(r'%([0-9a-fA-F]{2})').allMatches(value)) {
    final unit = int.parse(match.group(1)!, radix: 16);
    if (unit < 0x20 || (unit >= 0x7F && unit <= 0x9F)) {
      return true;
    }
  }
  return false;
}

bool _hasEncodedExternalUriAuthoritySeparator(String value) {
  final uri = Uri.tryParse(value);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null || (scheme != 'http' && scheme != 'https')) {
    return false;
  }
  final authority = uri.authority.toLowerCase();
  for (final encodedSeparator in const [
    '%23',
    '%2f',
    '%3a',
    '%3f',
    '%40',
    '%5b',
    '%5c',
    '%5d',
  ]) {
    if (authority.contains(encodedSeparator)) {
      return true;
    }
  }
  return false;
}

bool _hasUnsafeExternalUriCharacter(String value) {
  return value.runes.any(
    (rune) => rune <= 0x20 || (rune >= 0x7F && rune <= 0x9F),
  );
}

bool _hasUnsafeExternalFilePathCharacter(String value) {
  return value.runes.any(_isControlRune);
}

bool _isControlRune(int rune) {
  return rune < 0x20 || (rune >= 0x7F && rune <= 0x9F);
}

const _allowedScriptCapsuleEngines = {'auto', 'pwsh', 'powershell'};
