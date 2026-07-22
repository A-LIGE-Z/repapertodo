import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/model/app_state.dart';
import '../core/model/external_uri_targets.dart';
import '../core/model/paper_constants.dart';
import '../core/model/paper_data.dart';
import '../core/model/paper_titles.dart';
import '../core/script/script_capsule.dart';
import '../core/startup/startup_command.dart';
import 'platform_services.dart';

const _minimizedWindowCoordinate = -30000.0;

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
        storage = WindowsAppStorageHost(channel: channel);

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
  final StreamController<PaperData> _paperEdits =
      StreamController<PaperData>.broadcast();
  final StreamController<PaperWindowActionRequest> _actionRequests =
      StreamController<PaperWindowActionRequest>.broadcast();
  final StreamController<CapsuleDropRequest> _capsuleDrops =
      StreamController<CapsuleDropRequest>.broadcast();
  final StreamController<String> _paperOpenRequests =
      StreamController<String>.broadcast();
  final StreamController<String> _paperDeleteRequests =
      StreamController<String>.broadcast();
  final StreamController<void> _coordinatorCloseRequests =
      StreamController<void>.broadcast();
  final Map<String, PaperData> _knownPapers = <String, PaperData>{};
  final Map<String, _PaperSurfaceBounds> _synchronizedBounds =
      <String, _PaperSurfaceBounds>{};
  PaperData? _activePaper;

  @override
  Stream<PaperData> get surfaceUpdates => _surfaceUpdates.stream;

  @override
  Stream<PaperData> get paperEdits => _paperEdits.stream;

  @override
  Stream<PaperWindowActionRequest> get actionRequests => _actionRequests.stream;

  @override
  Stream<CapsuleDropRequest> get capsuleDrops => _capsuleDrops.stream;

  @override
  Stream<String> get paperOpenRequests => _paperOpenRequests.stream;

  @override
  Stream<String> get paperDeleteRequests => _paperDeleteRequests.stream;

  @override
  Stream<void> get coordinatorCloseRequests => _coordinatorCloseRequests.stream;

  @override
  Future<PaperWorkArea?> workAreaForPaper(PaperData paper) async {
    await _normalizePaperForPlatform(paper);
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
      case 'coordinatorCloseRequested':
        _coordinatorCloseRequests.add(null);
      case 'boundsChanged':
        final paper = _paperFromEventArguments(call.arguments);
        if (paper == null) {
          return;
        }
        if (_shouldIgnoreBoundsEvent(call.arguments)) {
          return;
        }
        final bounds = _boundsFromArguments(call.arguments);
        if (bounds != null) {
          _applyBoundsToPaper(paper, bounds);
          _surfaceUpdates.add(paper);
        }
      case 'capsuleDropped':
        final map = _argumentMap(call.arguments);
        if (map == null) {
          return;
        }
        final paperId = _paperIdFromArguments(call.arguments);
        final side = map['side'];
        final monitor = map['monitorDeviceName'];
        final dropTop = map['dropTop'];
        final workAreaTop = map['workAreaTop'];
        final isMaster = map['isMasterCapsule'];
        if (paperId == null ||
            !_knownPapers.containsKey(paperId) ||
            side is! String ||
            monitor is! String ||
            dropTop is! num ||
            workAreaTop is! num ||
            isMaster is! bool) {
          return;
        }
        _capsuleDrops.add(CapsuleDropRequest(
          paperId: paperId,
          monitorDeviceName: monitor,
          side: DeepCapsuleSides.normalize(side),
          dropTop: dropTop.toDouble(),
          workAreaTop: workAreaTop.toDouble(),
          isMasterCapsule: isMaster,
        ));
      case 'paperSurfaceChanged':
        final map = _argumentMap(call.arguments);
        if (map == null) {
          return;
        }
        final changedPaper = PaperData.fromJson({
          for (final entry in map.entries)
            if (entry.key is String) entry.key as String: entry.value,
        });
        final paperId = normalizeLocalModelId(changedPaper.id);
        if (paperId.isEmpty || !_knownPapers.containsKey(paperId)) {
          return;
        }
        changedPaper.id = paperId;
        final knownPaper = _knownPapers[paperId]!;
        // The child Flutter engine owns paper content, but native Win32 owns
        // the live window geometry.  A child edit can arrive with a stale
        // snapshot of x/y/width/height after the user has just dragged or
        // resized the native window, so never let that snapshot move it back.
        _copyPaperEditData(changedPaper, knownPaper);
        if (normalizeLocalModelId(_activePaper?.id) == paperId) {
          _activePaper = knownPaper;
        }
        _paperEdits.add(knownPaper);
      case 'paperActionRequested':
        final map = _argumentMap(call.arguments);
        final kind = map?['kind'];
        final paperId = map?['paperId'];
        final value = map?['value'];
        if (kind is! String ||
            !PaperWindowActionKinds.values.contains(kind) ||
            paperId is! String) {
          return;
        }
        final normalizedPaperId = _validatedEventPaperId(paperId);
        if (normalizedPaperId == null ||
            !_knownPapers.containsKey(normalizedPaperId)) {
          return;
        }
        _actionRequests.add(PaperWindowActionRequest(
          kind: kind,
          paperId: normalizedPaperId,
          value: value is String ? value : '',
        ));
      case 'closeRequested':
        final paper = _paperFromEventArguments(call.arguments);
        if (paper == null) {
          return;
        }
        paper.isVisible = false;
        _retargetActivePaperForVisibilityEvent(call.arguments, paper);
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
        _retargetActivePaperForVisibilityEvent(call.arguments, paper);
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
    await _normalizePaperForPlatform(paper);
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
    await _normalizePaperForPlatform(paper);
    _rememberPaper(paper);
    _retargetActivePaperAfterLocalHide(paper);
    await _channel.invokeMethod<void>('hide', _paperSurfaceArguments(paper));
  }

  @override
  Future<void> hidePaper(PaperData paper) async {
    paper.isVisible = false;
    await _normalizePaperForPlatform(paper);
    _rememberPaper(paper);
    _retargetActivePaperAfterLocalHide(paper);
    await _channel.invokeMethod<void>('hide', _paperSurfaceArguments(paper));
  }

  @override
  Future<void> hideCoordinatorWindow() async {
    await _channel.invokeMethod<void>('hideCoordinator');
  }

  @override
  Future<void> setCoordinatorBackgroundColor(int argb) async {
    await _channel.invokeMethod<void>('setCoordinatorBackgroundColor', argb);
  }

  @override
  Future<bool> hasVisibleSurfaces(AppState state) async {
    await _normalizeStateForPlatform(state);
    _syncKnownPapers(state);
    final hasNativeVisibleSurface =
        await _channel.invokeMethod<bool>('hasVisibleSurfaces');
    if (hasNativeVisibleSurface == true) {
      return true;
    }
    for (final paper in state.papers) {
      if (!paper.isVisible) {
        continue;
      }
      if (await hasVisibleSurface(paper)) {
        return true;
      }
    }
    return hasNativeVisibleSurface ??
        state.papers.any((paper) {
          return paper.isVisible;
        });
  }

  @override
  Future<bool> hasVisibleSurface(PaperData paper) async {
    await _normalizePaperForPlatform(paper);
    _rememberPaper(paper);
    return await _channel.invokeMethod<bool>(
          'hasVisibleSurface',
          _paperSurfaceArguments(paper),
        ) ??
        paper.isVisible;
  }

  @override
  Future<void> restoreAll(AppState state) async {
    await refreshSurfaceRegistry(state);
    // Capsule collapse/expand only controls the native capsule queue. Paper
    // windows remain visible and unchanged so toggling the master capsule
    // never hides or mutates the underlying cards.
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
  Future<void> refreshSurfaceRegistry(AppState state) async {
    await _normalizeStateForPlatform(state);
    _syncKnownPapers(state);
    await _syncPaperSurfaceRegistry(state);
  }

  @override
  Future<void> showPaper(PaperData paper) async {
    paper.isVisible = true;
    await _normalizePaperForPlatform(paper);
    _rememberPaper(paper);
    _activePaper = paper;
    await _channel.invokeMethod<void>('updatePaperWindow', paper.toJson());
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
  Future<void> revealPinnedPaper(PaperData paper) async {
    paper.isVisible = true;
    await _normalizePaperForPlatform(paper);
    _rememberPaper(paper);
    _activePaper = paper;
    await _channel.invokeMethod<void>('updatePaperWindow', paper.toJson());
    await _applyBounds(paper);
    await _channel.invokeMethod<void>(
      'setPinnedToDesktop',
      _paperSurfaceFlagArguments(paper, paper.isPinnedToDesktop),
    );
    await _channel.invokeMethod<void>(
      'setAlwaysOnTop',
      _paperSurfaceFlagArguments(paper, paper.alwaysOnTop),
    );
    await _channel.invokeMethod<void>(
      'revealPinnedPaper',
      _paperSurfaceArguments(paper),
    );
    await _channel.invokeMethod<void>('setTitle', _paperTitleArguments(paper));
  }

  @override
  Future<void> updatePaperSurface(PaperData paper) async {
    await _normalizePaperForPlatform(paper);
    final shouldApplyBounds = _hasUnsynchronizedBounds(paper);
    _rememberPaper(paper);
    if (!paper.isVisible) {
      _retargetActivePaperAfterLocalHide(paper);
      return;
    }
    await _channel.invokeMethod<void>('updatePaperWindow', paper.toJson());
    // Win32 owns the live position while the user is moving or resizing a
    // paper. Content edits can be delivered before the final boundsChanged
    // event, so replaying unchanged model bounds here would snap the HWND back
    // to its pre-drag position. Only explicit model geometry changes may move
    // an existing window.
    if (shouldApplyBounds) {
      await _applyBounds(paper);
    }
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
      'capsuleSide': paper.capsuleSide,
      'capsuleMonitorDeviceName': paper.capsuleMonitorDeviceName,
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
    _rememberSynchronizedBounds(paper);
  }

  Future<void> _syncPaperSurfaceRegistry(AppState state) async {
    await _channel.invokeMethod<void>('setPaperWindowState', state.toJson());
    await _channel.invokeMethod<void>(
      'setPaperSurfaces',
      _paperSurfaceRegistryEntries(state),
    );
    await _channel.invokeMethod<void>(
      'setNativeCapsuleSurfaces',
      _nativeCapsuleSurfaceEntries(state),
    );
    for (final paper in state.papers) {
      _rememberSynchronizedBounds(paper);
    }
  }

  Future<void> _normalizeStateForPlatform(AppState state) async {
    for (final paper in state.papers) {
      await _normalizePaperForPlatform(paper);
    }
  }

  Future<void> _normalizePaperForPlatform(PaperData paper) async {
    paper.id = normalizeLocalModelId(paper.id);
    if (paper.id.isEmpty) {
      paper.normalize();
    } else {
      paper.capsuleMonitorDeviceName =
          normalizeCapsuleMonitorDeviceName(paper.capsuleMonitorDeviceName);
    }
    await _normalizePaperQueueMonitorDeviceName(paper);
  }

  Future<void> _normalizePaperQueueMonitorDeviceName(PaperData paper) async {
    final monitorDeviceName = paper.capsuleMonitorDeviceName.trim();
    if (monitorDeviceName.isEmpty) {
      paper.capsuleMonitorDeviceName = '';
      return;
    }

    String? normalized;
    try {
      normalized = await _channel.invokeMethod<String>(
        'normalizeQueueMonitorDeviceName',
        {'monitorDeviceName': monitorDeviceName},
      );
    } on MissingPluginException {
      normalized = null;
    }
    paper.capsuleMonitorDeviceName = normalized?.trim() ?? monitorDeviceName;
  }

  void _rememberPaper(PaperData paper) {
    final paperId = normalizeLocalModelId(paper.id);
    if (paperId.isEmpty) {
      return;
    }
    paper.id = paperId;
    _knownPapers[paperId] = paper;
  }

  void _copyPaperEditData(PaperData source, PaperData target) {
    final copy = PaperData.fromJson(source.toJson());
    final x = target.x;
    final y = target.y;
    final width = target.width;
    final height = target.height;
    target
      ..id = copy.id
      ..type = copy.type
      ..title = copy.title
      ..x = x
      ..y = y
      ..width = width
      ..height = height
      ..isVisible = copy.isVisible
      ..alwaysOnTop = copy.alwaysOnTop
      ..isCollapsed = copy.isCollapsed
      ..isPinnedToDesktop = copy.isPinnedToDesktop
      ..textZoom = copy.textZoom
      ..capsuleSide = copy.capsuleSide
      ..capsuleMonitorDeviceName = copy.capsuleMonitorDeviceName
      ..items = copy.items
      ..content = copy.content
      ..noteCanvasElements = copy.noteCanvasElements
      ..extra = copy.extra;
  }

  void _syncKnownPapers(AppState state) {
    _knownPapers.clear();
    for (final paper in state.papers) {
      _rememberPaper(paper);
    }
    _synchronizedBounds.removeWhere(
      (paperId, _) => !_knownPapers.containsKey(paperId),
    );
    final activePaperId = normalizeLocalModelId(_activePaper?.id);
    if (activePaperId.isNotEmpty && _knownPapers.containsKey(activePaperId)) {
      final activePaper = _knownPapers[activePaperId]!;
      if (activePaper.isVisible) {
        _activePaper = activePaper;
        return;
      }
    }
    _activePaper = null;
    for (final paper in state.papers) {
      final paperId = normalizeLocalModelId(paper.id);
      if (paper.isVisible && _knownPapers.containsKey(paperId)) {
        _activePaper = paper;
        return;
      }
    }
  }

  PaperData? _paperFromEventArguments(Object? arguments) {
    final paperId = _paperIdFromArguments(arguments);
    if (paperId != null) {
      return _knownPapers[paperId];
    }
    if (_hasExplicitPaperIdArgument(arguments)) {
      return null;
    }
    return _activePaper;
  }

  void _retargetActivePaperForVisibilityEvent(
    Object? arguments,
    PaperData paper,
  ) {
    if (!_hasExplicitPaperIdArgument(arguments)) {
      _activePaper = paper;
      return;
    }
    if (normalizeLocalModelId(_activePaper?.id) ==
        normalizeLocalModelId(paper.id)) {
      _activePaper = _nextVisibleKnownPaperAfter(paper);
    }
  }

  void _retargetActivePaperAfterLocalHide(PaperData paper) {
    if (normalizeLocalModelId(_activePaper?.id) ==
        normalizeLocalModelId(paper.id)) {
      _activePaper = _nextVisibleKnownPaperAfter(paper);
    }
  }

  PaperData? _nextVisibleKnownPaperAfter(PaperData hiddenPaper) {
    final hiddenPaperId = normalizeLocalModelId(hiddenPaper.id);
    for (final candidate in _knownPapers.values) {
      final candidateId = normalizeLocalModelId(candidate.id);
      if (candidateId.isEmpty || candidateId == hiddenPaperId) {
        continue;
      }
      if (candidate.isVisible) {
        return candidate;
      }
    }
    return null;
  }

  String? _paperIdFromArguments(Object? arguments) {
    if (arguments is String) {
      return _validatedEventPaperId(arguments);
    }
    final map = _argumentMap(arguments);
    final value = map?['paperId'];
    if (value is String) {
      return _validatedEventPaperId(value);
    }
    return null;
  }

  String? _validatedEventPaperId(String value) {
    if (value.isEmpty || value.trim() != value) {
      return null;
    }
    if (_hasUnsafeExternalFilePathCharacter(value)) {
      return null;
    }
    return value;
  }

  bool _hasExplicitPaperIdArgument(Object? arguments) {
    if (arguments is String) {
      return true;
    }
    final map = _argumentMap(arguments);
    return map?.containsKey('paperId') ?? false;
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

  bool _shouldIgnoreBoundsEvent(Object? arguments) {
    final map = _argumentMap(arguments);
    if (map == null) {
      return false;
    }
    if (map['isMinimized'] == true ||
        map['minimized'] == true ||
        map['windowState'] == 'minimized' ||
        map['isCollapsed'] == true) {
      return true;
    }

    final bounds = _boundsFromArguments(arguments);
    return bounds != null && _looksLikeUnusableWindowBounds(bounds);
  }

  bool _looksLikeUnusableWindowBounds(Map<Object?, Object?> bounds) {
    final x = _doubleValue(bounds['x'], double.nan);
    final y = _doubleValue(bounds['y'], double.nan);
    final width = _doubleValue(bounds['width'], double.nan);
    final height = _doubleValue(bounds['height'], double.nan);
    if (!x.isFinite || !y.isFinite || !width.isFinite || !height.isFinite) {
      return true;
    }
    if (x <= _minimizedWindowCoordinate || y <= _minimizedWindowCoordinate) {
      return true;
    }
    return width < PaperLayoutDefaults.minWidth ||
        height < PaperLayoutDefaults.minHeight;
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
    _rememberSynchronizedBounds(paper);
  }

  bool _hasUnsynchronizedBounds(PaperData paper) {
    final paperId = normalizeLocalModelId(paper.id);
    final synchronized = _synchronizedBounds[paperId];
    return synchronized == null ||
        synchronized != _PaperSurfaceBounds.of(paper);
  }

  void _rememberSynchronizedBounds(PaperData paper) {
    final paperId = normalizeLocalModelId(paper.id);
    if (paperId.isEmpty) {
      return;
    }
    _synchronizedBounds[paperId] = _PaperSurfaceBounds.of(paper);
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

class _PaperSurfaceBounds {
  const _PaperSurfaceBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory _PaperSurfaceBounds.of(PaperData paper) => _PaperSurfaceBounds(
        x: paper.x,
        y: paper.y,
        width: paper.width,
        height: paper.height,
      );

  final double x;
  final double y;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) {
    return other is _PaperSurfaceBounds &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);
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
  Future<void> rebuildMenu(AppState state, {TrayMenuLabels? labels}) async {
    await _paperWindows._normalizeStateForPlatform(state);
    _paperWindows._syncKnownPapers(state);
    await _channel.invokeMethod<void>('setPaperWindowState', state.toJson());
    await _channel.invokeMethod<void>(
      'setTrayMenu',
      _trayMenuPayload(state, labels),
    );
  }
}

Object _trayMenuPayload(AppState state, TrayMenuLabels? labels) {
  final paperIds = state.papers.map((paper) => paper.id).toSet();
  final papers = _paperSurfaceRegistryEntries(state, labels: labels)
      .where((surface) => paperIds.contains(surface['id']))
      .toList();
  if (labels == null) {
    return papers;
  }
  return <String, Object?>{
    'labels': labels.toJson(),
    'papers': papers,
  };
}

List<Map<String, Object?>> _paperSurfaceRegistryEntries(
  AppState state, {
  TrayMenuLabels? labels,
}) {
  final typeCounts = <String, int>{};
  final queuePapers = _capsuleQueueOccupants(state);
  final queueSlots = _capsuleQueueSlots(state, queuePapers);
  final surfaces = <Map<String, Object?>>[];

  for (final paper in state.papers) {
    final queueKey = state.capsuleQueueKeyFor(paper);
    final queueY = queueSlots[queueKey]?[paper.id];
    final collapseAllActive = state.isCapsuleCollapseAllActiveFor(paper);
    final fallbackNumber = typeCounts.update(
      PaperTypes.normalize(paper.type),
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    surfaces.add(_paperSurfaceRegistryEntry(
      paper,
      state: state,
      labels: labels,
      fallbackNumber: fallbackNumber,
      collapseAllActive: collapseAllActive,
      capsuleY: paper.isCollapsed ? queueY : null,
    ));
  }
  return surfaces;
}

Map<String, List<PaperData>> _capsuleQueueMembers(AppState state) {
  final linkedNoteIds = state.papers
      .where((paper) => paper.isTodo)
      .expand((paper) => paper.items)
      .map((item) => item.linkedNoteId)
      .whereType<String>()
      .toSet();
  final queuePapers = <String, List<PaperData>>{};
  for (final paper in state.papers) {
    final linkedNoteCapsuleHidden = state.enableTodoNoteLinks &&
        state.hideLinkedNotesFromCapsules &&
        paper.isNote &&
        linkedNoteIds.contains(paper.id);
    final belongsToQueue = paper.isVisible &&
        !linkedNoteCapsuleHidden &&
        state.useCapsuleMode &&
        state.useDeepCapsuleMode &&
        (paper.isCollapsed ||
            paper.isPinnedToDesktop ||
            state.showDeepCapsuleWhileExpanded);
    if (!belongsToQueue) {
      continue;
    }
    final queueKey = state.capsuleQueueKeyFor(paper);
    queuePapers.putIfAbsent(queueKey, () => <PaperData>[]).add(paper);
  }
  return queuePapers;
}

Map<String, List<PaperData>> _capsuleQueueOccupants(AppState state) {
  final members = _capsuleQueueMembers(state);
  return <String, List<PaperData>>{
    for (final entry in members.entries)
      entry.key: entry.value.where((paper) {
        return paper.isVisible;
      }).toList(),
  }..removeWhere((_, papers) => papers.isEmpty);
}

Map<String, Map<String, double>> _capsuleQueueSlots(
  AppState state,
  Map<String, List<PaperData>> queuePapers,
) {
  const slotHeight = 50.0;
  final queueSlots = <String, Map<String, double>>{};
  for (final entry in queuePapers.entries) {
    final startTop = state.deepCapsuleQueueStartTopMargins[entry.key] ??
        state.deepCapsuleStartTopMargin;
    final firstRealSlot = state.useCapsuleCollapseAll ? 1 : 0;
    queueSlots[entry.key] = <String, double>{
      for (var index = 0; index < entry.value.length; index += 1)
        entry.value[index].id:
            startTop + ((index + firstRealSlot) * slotHeight),
    };
  }
  return queueSlots;
}

List<Map<String, Object?>> _nativeCapsuleSurfaceEntries(AppState state) {
  if (!state.useCapsuleMode || !state.useDeepCapsuleMode) {
    return const [];
  }
  final queueMembers = _capsuleQueueMembers(state);
  final queueOccupants = _capsuleQueueOccupants(state);
  final queueSlots = _capsuleQueueSlots(state, queueOccupants);
  final surfaces = <Map<String, Object?>>[];
  for (final entry in queueMembers.entries) {
    if (entry.value.isEmpty) {
      continue;
    }
    final firstPaper = entry.value.first;
    final collapseAllActive = state.isCapsuleCollapseAllActiveFor(firstPaper);
    final startTop = state.deepCapsuleQueueStartTopMargins[entry.key] ??
        state.deepCapsuleStartTopMargin;
    if (state.useCapsuleCollapseAll) {
      surfaces.add(<String, Object?>{
        'surfaceId': 'master:${entry.key}',
        'kind': 'master',
        'paperId': firstPaper.id,
        'title': collapseAllActive ? '${entry.value.length}' : '',
        'labelEn': 'Collapse all',
        'labelZh': '收起全部',
        'countLabelEn': '${entry.value.length} papers',
        'countLabelZh': '${entry.value.length} 张',
        'top': startTop,
        'capsuleSide': firstPaper.capsuleSide,
        'capsuleMonitorDeviceName': firstPaper.capsuleMonitorDeviceName,
        'isVisible': true,
        'isActive': collapseAllActive,
        'count': entry.value.length,
        'hideWhenCovered': state.hideDeepCapsulesWhenCovered,
        'hideWhenFullscreen': state.hideDeepCapsulesWhenFullscreen,
        'theme': state.theme,
        'colorScheme': state.colorScheme,
        'customThemeColorHex': state.customThemeColorHex,
        'fontFamily': _windowsUiFontFamily(state),
        'enableAnimations': state.enableAnimations,
      });
    }
    if (collapseAllActive) {
      continue;
    }
    for (final paper in queueOccupants[entry.key] ?? const <PaperData>[]) {
      if (paper.isCollapsed) {
        continue;
      }
      final top = queueSlots[entry.key]?[paper.id];
      if (top == null) {
        continue;
      }
      surfaces.add(<String, Object?>{
        'surfaceId': 'proxy:${paper.id}',
        'kind': 'proxy',
        'paperId': paper.id,
        'title': PaperTitles.effectiveTitle(
          paperType: paper.type,
          title: paper.title,
          fallbackNumber: 1,
        ),
        'paperType': paper.type,
        'isScriptCapsule':
            paper.isNote && ScriptCapsuleSpec.tryParse(paper.content) != null,
        'top': top,
        'capsuleSide': paper.capsuleSide,
        'capsuleMonitorDeviceName': paper.capsuleMonitorDeviceName,
        'isVisible': paper.isVisible,
        'collapseOnClick': !paper.isPinnedToDesktop,
        'hideWhenCovered': state.hideDeepCapsulesWhenCovered,
        'hideWhenFullscreen': state.hideDeepCapsulesWhenFullscreen,
        'theme': state.theme,
        'colorScheme': state.colorScheme,
        'customThemeColorHex': state.customThemeColorHex,
        'fontFamily': _windowsUiFontFamily(state),
        'enableAnimations': state.enableAnimations,
      });
    }
  }
  return surfaces;
}

Map<String, Object?> _paperSurfaceRegistryEntry(
  PaperData paper, {
  required AppState state,
  TrayMenuLabels? labels,
  required int fallbackNumber,
  required bool collapseAllActive,
  double? capsuleY,
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
    'y': capsuleY ?? paper.y,
    'width': paper.width,
    'height': paper.height,
    'isVisible': paper.isVisible && (!collapseAllActive || !paper.isCollapsed),
    'isCollapsed': paper.isCollapsed,
    'capsuleTopIsWorkAreaRelative': capsuleY != null,
    'useDeepCapsuleMode': state.useCapsuleMode && state.useDeepCapsuleMode,
    'capsuleSide': paper.capsuleSide,
    'capsuleMonitorDeviceName': paper.capsuleMonitorDeviceName,
    'alwaysOnTop': paper.alwaysOnTop,
    'isPinnedToDesktop': paper.isPinnedToDesktop,
    'hideFromWindowSwitcher': state.hidePapersFromWindowSwitcher,
    'hideWhenCovered': state.hideDeepCapsulesWhenCovered,
    'hideWhenFullscreen': state.hideDeepCapsulesWhenFullscreen,
    'enableAnimations': state.enableAnimations,
    'fontFamily': _windowsUiFontFamily(state),
    'isScriptCapsule':
        paper.isNote && ScriptCapsuleSpec.isScriptCapsuleContent(paper.content),
    if (labels != null) 'trayLabel': _trayPaperLabel(paper, title, labels),
  };
}

String _windowsUiFontFamily(AppState state) {
  final systemFamily = normalizeSystemFontFamilyName(
    state.systemFontFamilyName,
  );
  if (systemFamily.isNotEmpty) {
    return systemFamily;
  }
  return switch (UiFontPresets.normalize(state.uiFontPreset)) {
    UiFontPresets.serif => 'Georgia',
    UiFontPresets.mono => 'Consolas',
    _ => 'Segoe UI',
  };
}

String _trayPaperLabel(
  PaperData paper,
  String title,
  TrayMenuLabels labels,
) {
  final status = <String>[
    if (!paper.isVisible) labels.hidden,
    if (paper.isCollapsed) labels.collapsed,
    if (paper.isPinnedToDesktop) labels.desktop,
    if (paper.alwaysOnTop) labels.topmost,
  ];
  if (status.isEmpty) {
    return title;
  }
  return '$title (${status.join(', ')})';
}

class WindowsStartupHost implements StartupHost {
  WindowsStartupHost(this._channel) {
    _commands = StreamController<StartupCommand>.broadcast(
      onListen: _flushPendingCommands,
    );
  }

  final MethodChannel _channel;
  late final StreamController<StartupCommand> _commands;
  final List<StartupCommand> _pendingCommands = <StartupCommand>[];

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
    if (!_commands.hasListener) {
      _pendingCommands.add(command);
      return;
    }
    _commands.add(command);
  }

  void _flushPendingCommands() {
    if (_pendingCommands.isEmpty) {
      return;
    }
    final commands = List<StartupCommand>.of(_pendingCommands);
    _pendingCommands.clear();
    scheduleMicrotask(() {
      for (final command in commands) {
        if (!_commands.isClosed) {
          _commands.add(command);
        }
      }
    });
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
  bool get supportsCustomColorPicker => true;

  @override
  Future<bool> isForegroundFullscreen() async {
    return await _channel.invokeMethod<bool>('isForegroundFullscreen') ?? false;
  }

  @override
  Future<List<String>> installedFontFamilies() async {
    try {
      final values =
          await _channel.invokeListMethod<Object?>('listInstalledFontFamilies');
      return normalizeInstalledFontFamilies(values ?? const <Object?>[]);
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<String?> chooseCustomColor(String initialColorHex) async {
    final selected = await _channel.invokeMethod<String>(
      'chooseCustomColor',
      initialColorHex,
    );
    final normalized = selected?.trim().toUpperCase() ?? '';
    return RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized) ? normalized : null;
  }

  @override
  Future<void> registerGlobalHotkeys(AppState state) async {
    await _channel.invokeMethod<void>('registerGlobalHotkeys', {
      'todo': _normalizeHotKeyForPlatform(state.pinnedTodoHotKey),
      'note': _normalizeHotKeyForPlatform(state.pinnedNoteHotKey),
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
    if (hasRawExternalUriControlCharacter(uri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Windows URI must not contain control characters.',
      );
    }
    if (hasUnsafeExternalUriCharacter(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Windows URI must not contain control characters.',
      );
    }
    if (hasMalformedExternalUriPercentEscape(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Windows URI must not contain malformed percent escapes.',
      );
    }
    if (hasEncodedUnsafeExternalUriCharacter(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Windows URI must not contain encoded control characters.',
      );
    }
    if (hasEncodedExternalUriAuthoritySeparator(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Windows URI must not contain encoded authority separators.',
      );
    }
    if (!isAllowedExternalUriTarget(trimmedUri)) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Windows URI scheme is not supported.',
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
  const WindowsAppStorageHost({
    MethodChannel channel = const MethodChannel('repapertodo/window'),
    String? executablePath,
  })  : _channel = channel,
        _executablePath = executablePath;

  final MethodChannel _channel;
  final String? _executablePath;

  @override
  bool get supportsDataDirectorySelection => true;

  @override
  Future<String> documentsDirectoryPath() async {
    try {
      final selected = await _channel.invokeMethod<String>('getDataDirectory');
      if (selected != null &&
          selected.trim().isNotEmpty &&
          !_hasUnsafeExternalFilePathCharacter(selected)) {
        return selected.trim();
      }
    } on MissingPluginException {
      // Unit tests and non-runner hosts use the executable-directory fallback.
    }
    final rawExecutablePath = _executablePath ?? Platform.resolvedExecutable;
    if (_hasUnsafeExternalFilePathCharacter(rawExecutablePath)) {
      throw StateError(
        'Windows executable path contains unsupported characters.',
      );
    }
    final executablePath = rawExecutablePath.trim();
    if (executablePath.isEmpty) {
      throw StateError('Windows executable path is unavailable.');
    }
    return p.dirname(executablePath);
  }

  @override
  Future<String?> chooseDataDirectory(String currentDirectoryPath) async {
    final selected = await _channel.invokeMethod<String>(
      'chooseDataDirectory',
      currentDirectoryPath,
    );
    final normalized = selected?.trim() ?? '';
    if (normalized.isEmpty || _hasUnsafeExternalFilePathCharacter(normalized)) {
      return null;
    }
    return normalized;
  }

  @override
  Future<void> commitDataDirectory(String directoryPath) async {
    await _channel.invokeMethod<void>('commitDataDirectory', directoryPath);
  }
}

bool _hasUnsafeExternalFilePathCharacter(String value) {
  return value.runes.any(_isControlRune);
}

bool _isControlRune(int rune) {
  return rune < 0x20 || (rune >= 0x7F && rune <= 0x9F);
}

String _normalizeHotKeyForPlatform(String value) {
  final cleaned = StringBuffer();
  for (final unit in value.codeUnits) {
    if (unit <= 0x1F || (unit >= 0x7F && unit <= 0x9F)) {
      continue;
    }
    cleaned.writeCharCode(unit);
  }
  final text = cleaned.toString().trim();
  return text.length > 64 ? text.substring(0, 64) : text;
}

const _allowedScriptCapsuleEngines = {'auto', 'pwsh', 'powershell'};
