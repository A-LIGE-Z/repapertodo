import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path/path.dart' as p;

import 'app_controller.dart';
import 'core/model/app_state.dart';
import 'core/model/markdown_formatting.dart';
import 'core/model/markdown_links.dart';
import 'core/model/markdown_list_continuation.dart';
import 'core/model/markdown_paste.dart';
import 'core/model/note_canvas_element.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
import 'core/model/paper_item.dart';
import 'core/model/paper_titles.dart';
import 'core/model/sync_settings.dart';
import 'core/model/todo_paste.dart';
import 'core/script/script_capsule.dart';
import 'core/storage/state_store.dart';
import 'core/startup/startup_command.dart';
import 'sync/app_sync_service.dart';
import 'sync/webdav/webdav_client.dart';
import 'sync/webdav/webdav_payload_codec.dart';
import 'sync/webdav/webdav_state_sync_service.dart';
import 'ui/runtime_custom_font.dart';
import 'ui/sync_settings_dialog.dart';

const _externalMarkdownExportRetention = Duration(days: 7);
const _maxExternalMarkdownPaperIdFileNameLength = 96;
const _todoReminderLeadTime = Duration(minutes: 10);
const _todoReminderGraceTime = Duration(minutes: 2);
const _yaHeiFontFamily = 'Microsoft YaHei UI';
const _yaHeiFontFamilyFallback = [
  'Microsoft YaHei',
  'Segoe UI',
  'Microsoft JhengHei UI',
  'Microsoft JhengHei',
  'Yu Gothic UI',
  'Malgun Gothic',
  'Meiryo',
  'Segoe UI Symbol',
  'Segoe UI Emoji',
];
const _dengXianFontFamily = 'DengXian';
const _dengXianFontFamilyFallback = [
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'Segoe UI',
  'Microsoft JhengHei UI',
  'Microsoft JhengHei',
  'Yu Gothic UI',
  'Malgun Gothic',
  'Meiryo',
  'Segoe UI Symbol',
  'Segoe UI Emoji',
];

class RePaperTodoApp extends StatefulWidget {
  const RePaperTodoApp({
    required this.controller,
    required this.store,
    this.syncService,
    this.customFontLoader,
    super.key,
  });

  final RePaperTodoController controller;
  final StateStore store;
  final AppSyncService? syncService;
  final PaperTodoRuntimeCustomFontLoader? customFontLoader;

  @override
  State<RePaperTodoApp> createState() => _RePaperTodoAppState();
}

class _RePaperTodoAppState extends State<RePaperTodoApp> {
  String? _runtimeCustomFontFamily;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRuntimeCustomFont());
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RePaperTodo',
      theme: _appTheme(Brightness.light, state),
      darkTheme: _appTheme(Brightness.dark, state),
      themeMode: _themeMode(state.theme),
      home: PaperBoardScreen(
        controller: widget.controller,
        store: widget.store,
        syncService: widget.syncService ?? AppSyncService(),
        onAppThemeChanged: () => setState(() {}),
      ),
    );
  }

  Future<void> _loadRuntimeCustomFont() async {
    final family =
        await (widget.customFontLoader ?? PaperTodoRuntimeCustomFontLoader())
            .load();
    if (!mounted ||
        family == null ||
        family.trim().isEmpty ||
        family == _runtimeCustomFontFamily) {
      return;
    }
    setState(() => _runtimeCustomFontFamily = family);
  }

  ThemeData _appTheme(Brightness brightness, AppState state) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor(state),
        brightness: brightness,
      ),
      useMaterial3: true,
    );
    final fontFamily = _fontFamily(state);
    final fontFamilyFallback = _fontFamilyFallback(state);
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSizeFactor: state.zoom,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSizeFactor: state.zoom,
      ),
    );
  }

  ThemeMode _themeMode(String theme) {
    return switch (theme.trim().toLowerCase()) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Color _seedColor(AppState state) {
    final customThemeColor = _customThemeColor(state.customThemeColorHex);
    if (customThemeColor != null) {
      return customThemeColor;
    }
    return switch (ColorSchemes.normalize(state.colorScheme)) {
      ColorSchemes.ink => const Color(0xFF4F6D7A),
      ColorSchemes.forest => const Color(0xFF2E7D32),
      ColorSchemes.rose => const Color(0xFFC85A7C),
      _ => const Color(0xFFE07A5F),
    };
  }

  Color? _customThemeColor(String value) {
    final match = RegExp(r'^#?([0-9A-Fa-f]{6})$').firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return Color(int.parse('FF${match.group(1)!}', radix: 16));
  }

  String? _fontFamily(AppState state) {
    return resolveAppFontFamily(
      state,
      runtimeCustomFontFamily: _runtimeCustomFontFamily,
    );
  }

  List<String>? _fontFamilyFallback(AppState state) {
    return resolveAppFontFamilyFallback(
      state,
      runtimeCustomFontFamily: _runtimeCustomFontFamily,
    );
  }
}

String? resolveAppFontFamily(
  AppState state, {
  String? runtimeCustomFontFamily,
}) {
  final systemFontFamilyName = state.systemFontFamilyName.trim();
  if (systemFontFamilyName.isNotEmpty) {
    return systemFontFamilyName;
  }
  final runtimeFamily = runtimeCustomFontFamily?.trim();
  if (runtimeFamily != null && runtimeFamily.isNotEmpty) {
    return runtimeFamily;
  }
  return switch (UiFontPresets.normalize(state.uiFontPreset)) {
    UiFontPresets.yaHei => _yaHeiFontFamily,
    UiFontPresets.dengXian => _dengXianFontFamily,
    UiFontPresets.serif => 'serif',
    UiFontPresets.mono => 'monospace',
    _ => null,
  };
}

List<String>? resolveAppFontFamilyFallback(
  AppState state, {
  String? runtimeCustomFontFamily,
}) {
  if (state.systemFontFamilyName.trim().isNotEmpty) {
    return null;
  }
  final runtimeFamily = runtimeCustomFontFamily?.trim();
  if (runtimeFamily != null && runtimeFamily.isNotEmpty) {
    return null;
  }
  return switch (UiFontPresets.normalize(state.uiFontPreset)) {
    UiFontPresets.yaHei => _yaHeiFontFamilyFallback,
    UiFontPresets.dengXian => _dengXianFontFamilyFallback,
    _ => null,
  };
}

String _shortenTitle(String title, int maxLength) {
  return PaperTitles.shorten(title, maxLength);
}

bool _sameStringSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

String? _tooltipLabel(bool enabled, String label) => enabled ? label : null;

String _readableFailureMessage(Object error) {
  return switch (error) {
    WebDavException(:final message) => message,
    WebDavPayloadDecryptionException(:final message) => message,
    PlatformException(
      :final code,
      :final message,
      :final details,
    ) =>
      _platformFailureMessage(
        code: code,
        message: message,
        details: details,
      ),
    FileSystemException(:final message, :final path) =>
      path == null ? message : '$message: $path',
    StateStoreException(:final message) => message,
    FormatException(:final message) => message,
    TimeoutException(:final message) => message ?? 'The operation timed out.',
    StateError(:final message) => message,
    _ => error.toString(),
  };
}

String _platformFailureMessage({
  required String code,
  required String? message,
  required Object? details,
}) {
  final readableMessage = message?.trim();
  if (readableMessage != null && readableMessage.isNotEmpty) {
    return readableMessage;
  }
  final readableDetails = details?.toString().trim();
  if (readableDetails != null && readableDetails.isNotEmpty) {
    return readableDetails;
  }
  return code;
}

String? _normalizeExternalUri(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (_hasUnsafeExternalUriCharacter(trimmed)) {
    return null;
  }
  if (_hasEncodedUnsafeExternalUriCharacter(trimmed)) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    return uri.host.trim().isEmpty ||
            uri.userInfo.isNotEmpty ||
            _hasEncodedExternalUriAuthoritySeparator(uri.authority)
        ? null
        : trimmed;
  }
  if (scheme == 'mailto') {
    return uri.path.trim().isEmpty ? null : trimmed;
  }
  return null;
}

bool _hasEncodedExternalUriAuthoritySeparator(String authority) {
  final normalized = authority.toLowerCase();
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
    if (normalized.contains(encodedSeparator)) {
      return true;
    }
  }
  return false;
}

bool _hasUnsafeExternalUriCharacter(String value) {
  return value.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7F);
}

bool _hasEncodedUnsafeExternalUriCharacter(String value) {
  for (final match in RegExp(r'%([0-9a-fA-F]{2})').allMatches(value)) {
    final unit = int.parse(match.group(1)!, radix: 16);
    if (unit < 0x20 || unit == 0x7F) {
      return true;
    }
  }
  return false;
}

class _CompactAppBarActions {
  const _CompactAppBarActions._();

  static const openSurface = 'open-surface';
  static const newTodo = 'new-todo';
  static const newNote = 'new-note';
  static const toggleCollapseAll = 'toggle-collapse-all';
  static const recoverySnapshots = 'recovery-snapshots';
  static const showHidden = 'show-hidden';
  static const settings = 'settings';
}

class PaperBoardScreen extends StatefulWidget {
  const PaperBoardScreen({
    required this.controller,
    required this.store,
    required this.syncService,
    this.onAppThemeChanged,
    super.key,
  });

  final RePaperTodoController controller;
  final StateStore store;
  final AppSyncService syncService;
  final VoidCallback? onAppThemeChanged;

  @override
  State<PaperBoardScreen> createState() => _PaperBoardScreenState();
}

class _PaperBoardScreenState extends State<PaperBoardScreen>
    with WidgetsBindingObserver {
  bool _isSyncing = false;
  bool _isSettingsOpen = false;
  Future<void> _saveQueue = Future<void>.value();
  StreamSubscription<PaperData>? _surfaceUpdateSubscription;
  StreamSubscription<String>? _paperOpenSubscription;
  StreamSubscription<StartupCommand>? _startupCommandSubscription;
  Timer? _autoSyncTimer;
  Timer? _localEditSyncDebounce;
  Timer? _surfaceSaveDebounce;
  Timer? _titleSurfaceDebounce;
  Timer? _todoReminderTimer;
  int _localEditSyncGeneration = 0;
  AppState? _pendingLocalEditBaseState;
  AppState? _pendingLocalEditLatestState;
  int? _pendingLocalEditGeneration;
  String? _surfacePaperId;
  final Map<String, bool> _surfaceVisibilityByPaperId = <String, bool>{};
  final Map<String, DateTime> _lastTodoReminderAt = <String, DateTime>{};
  final Set<String> _activeTodoReminderItemIds = <String>{};

  RePaperTodoController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _surfaceUpdateSubscription =
        controller.paperSurfaceUpdates.listen(_handleSurfaceUpdate);
    _paperOpenSubscription = controller.paperOpenRequests.listen((paperId) {
      unawaited(_handlePaperOpenRequest(paperId));
    });
    _startupCommandSubscription = controller.startupCommands.listen((command) {
      unawaited(_handleStartupCommand(command));
    });
    final pendingStartupCommand = controller.takePendingUiStartupCommand();
    if (pendingStartupCommand != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_handleStartupCommand(pendingStartupCommand));
      });
    }
    _refreshSurfaceVisibilitySnapshot();
    _restartAutoSyncTimer();
    _restartTodoReminderTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _localEditSyncDebounce?.cancel();
    _surfaceSaveDebounce?.cancel();
    _titleSurfaceDebounce?.cancel();
    _todoReminderTimer?.cancel();
    unawaited(_surfaceUpdateSubscription?.cancel());
    unawaited(_paperOpenSubscription?.cancel());
    unawaited(_startupCommandSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_syncSilentlyIfConfigured());
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enableToolTips = controller.state.enableToolTips;
    final linkedNoteIds = _linkedNoteIds();
    final visiblePapers = controller.state.papers.where((paper) {
      if (!paper.isVisible) {
        return false;
      }
      return !(controller.state.hideLinkedNotesFromCapsules &&
          paper.isNote &&
          linkedNoteIds.contains(paper.id));
    }).toList();
    final hiddenPapers =
        controller.state.papers.where((paper) => !paper.isVisible).toList();
    final notePapers =
        controller.state.papers.where((paper) => paper.isNote).toList();
    final surfacePaper = _surfacePaper();
    final useCompactAppBar = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        leading: surfacePaper == null
            ? null
            : IconButton(
                tooltip: _tooltipLabel(enableToolTips, 'Back to board'),
                onPressed: () => setState(() => _surfacePaperId = null),
                icon: const Icon(Icons.arrow_back),
              ),
        title: Text(
          surfacePaper == null ? 'RePaperTodo' : _displayTitle(surfacePaper),
        ),
        actions: _appBarActions(
          surfacePaper: surfacePaper,
          hiddenPapers: hiddenPapers,
          enableToolTips: enableToolTips,
          compact: useCompactAppBar,
        ),
      ),
      body: ColoredBox(
        color: colorScheme.surface,
        child: surfacePaper == null
            ? ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: visiblePapers.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return _paperPreview(visiblePapers[index], notePapers);
                },
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _paperPreview(surfacePaper, notePapers),
                ],
              ),
      ),
    );
  }

  List<Widget> _appBarActions({
    required PaperData? surfacePaper,
    required List<PaperData> hiddenPapers,
    required bool enableToolTips,
    required bool compact,
  }) {
    final collapseAllActive = _collapseAllActiveFor(surfacePaper);
    final syncButton = IconButton(
      tooltip: _tooltipLabel(enableToolTips, 'Sync now'),
      onPressed: _isSyncing ? null : () => _syncNow(),
      icon: _isSyncing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_outlined),
    );
    if (compact) {
      return [
        syncButton,
        PopupMenuButton<String>(
          key: const ValueKey('compact-app-bar-actions'),
          tooltip: _tooltipLabel(enableToolTips, 'More actions'),
          icon: const Icon(Icons.more_vert),
          onSelected: (value) =>
              _handleCompactAppBarAction(value, surfacePaper),
          itemBuilder: (context) => [
            if (surfacePaper != null &&
                controller.state.showTopBarExternalOpenButton)
              _compactMenuItem(
                value: _CompactAppBarActions.openSurface,
                icon: Icons.open_in_new,
                label: 'Open surface',
              ),
            if (controller.state.showTopBarNewTodoButton)
              _compactMenuItem(
                value: _CompactAppBarActions.newTodo,
                icon: Icons.add_task,
                label: 'New todo',
              ),
            if (controller.state.showTopBarNewNoteButton)
              _compactMenuItem(
                value: _CompactAppBarActions.newNote,
                icon: Icons.note_add_outlined,
                label: 'New note',
              ),
            if (controller.state.useCapsuleMode &&
                controller.state.useCapsuleCollapseAll)
              _compactMenuItem(
                value: _CompactAppBarActions.toggleCollapseAll,
                icon: collapseAllActive ? Icons.unfold_more : Icons.unfold_less,
                label: collapseAllActive ? 'Expand all' : 'Collapse all',
              ),
            _compactMenuItem(
              value: _CompactAppBarActions.recoverySnapshots,
              icon: Icons.restore_outlined,
              label: 'Recovery snapshots',
              enabled: !_isSyncing,
            ),
            _compactMenuItem(
              value: _CompactAppBarActions.showHidden,
              icon: Icons.visibility_outlined,
              label: 'Show hidden',
              enabled: hiddenPapers.isNotEmpty,
            ),
            _compactMenuItem(
              value: _CompactAppBarActions.settings,
              icon: Icons.settings_outlined,
              label: 'Settings',
            ),
          ],
        ),
      ];
    }
    return [
      if (surfacePaper != null && controller.state.showTopBarExternalOpenButton)
        IconButton(
          tooltip: _tooltipLabel(enableToolTips, 'Open current paper surface'),
          onPressed: () => _openPaper(surfacePaper),
          icon: const Icon(Icons.open_in_new),
        ),
      if (controller.state.showTopBarNewTodoButton)
        IconButton(
          tooltip: _tooltipLabel(enableToolTips, 'New todo paper'),
          onPressed: () =>
              _createPaper(PaperTypes.todo, sourcePaper: surfacePaper),
          icon: const Icon(Icons.add_task),
        ),
      if (controller.state.showTopBarNewNoteButton)
        IconButton(
          tooltip: _tooltipLabel(enableToolTips, 'New note paper'),
          onPressed: () =>
              _createPaper(PaperTypes.note, sourcePaper: surfacePaper),
          icon: const Icon(Icons.note_add_outlined),
        ),
      if (controller.state.useCapsuleMode &&
          controller.state.useCapsuleCollapseAll)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            collapseAllActive ? 'Expand all papers' : 'Collapse all papers',
          ),
          onPressed: () => _toggleCollapseAll(surfacePaper),
          icon: Icon(collapseAllActive ? Icons.unfold_more : Icons.unfold_less),
        ),
      syncButton,
      IconButton(
        tooltip: _tooltipLabel(enableToolTips, 'Recovery snapshots'),
        onPressed: _isSyncing ? null : _openRecoverySnapshots,
        icon: const Icon(Icons.restore_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(enableToolTips, 'Show hidden papers'),
        onPressed: hiddenPapers.isEmpty ? null : _showHiddenPapers,
        icon: const Icon(Icons.visibility_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(enableToolTips, 'Settings'),
        onPressed: _openSettings,
        icon: const Icon(Icons.settings_outlined),
      ),
    ];
  }

  PopupMenuItem<String> _compactMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  void _handleCompactAppBarAction(String value, PaperData? surfacePaper) {
    switch (value) {
      case _CompactAppBarActions.openSurface:
        if (surfacePaper != null) {
          unawaited(_openPaper(surfacePaper));
        }
      case _CompactAppBarActions.newTodo:
        unawaited(_createPaper(PaperTypes.todo, sourcePaper: surfacePaper));
      case _CompactAppBarActions.newNote:
        unawaited(_createPaper(PaperTypes.note, sourcePaper: surfacePaper));
      case _CompactAppBarActions.toggleCollapseAll:
        unawaited(_toggleCollapseAll(surfacePaper));
      case _CompactAppBarActions.recoverySnapshots:
        unawaited(_openRecoverySnapshots());
      case _CompactAppBarActions.showHidden:
        unawaited(_showHiddenPapers());
      case _CompactAppBarActions.settings:
        unawaited(_openSettings());
    }
  }

  Set<String> _linkedNoteIds() {
    final linkedNoteIds = <String>{};
    for (final paper in controller.state.papers) {
      if (!paper.isTodo) {
        continue;
      }
      for (final item in paper.items) {
        final linkedNoteId = item.linkedNoteId;
        if (linkedNoteId != null) {
          linkedNoteIds.add(linkedNoteId);
        }
      }
    }
    return linkedNoteIds;
  }

  PaperData? _surfacePaper() {
    final surfacePaperId = _surfacePaperId;
    if (surfacePaperId == null) {
      return null;
    }
    for (final paper in controller.state.papers) {
      if (paper.id == surfacePaperId && paper.isVisible) {
        return paper;
      }
    }
    return null;
  }

  PaperPreview _paperPreview(PaperData paper, List<PaperData> notePapers) {
    return PaperPreview(
      paper: paper,
      notePapers: notePapers,
      titleText: controller.paperTitleText(paper),
      enableTodoNoteLinks: controller.state.enableTodoNoteLinks,
      showLinkedNoteName: controller.state.showLinkedNoteName,
      allowLongLinkedNoteTitles: controller.state.allowLongLinkedNoteTitles,
      runLinkedScriptCapsulesOnClick:
          controller.state.runLinkedScriptCapsulesOnClick,
      maxTitleLength: controller.state.maxTitleLength,
      enableToolTips: controller.state.enableToolTips,
      enableAnimations: controller.state.enableAnimations,
      markdownRenderMode: controller.state.markdownRenderMode,
      todoVisualSize: controller.state.todoVisualSize,
      todoLineSpacing: controller.state.todoLineSpacing,
      showTodoDueRelativeTime: controller.state.showTodoDueRelativeTime,
      todoDueYearDisplayMode: controller.state.todoDueYearDisplayMode,
      collapseAllActive: controller.state.useCapsuleMode &&
          controller.state.useCapsuleCollapseAll &&
          controller.state.isCapsuleCollapseAllActiveFor(paper),
      noteLineSpacing: controller.state.noteLineSpacing,
      onChanged: _refreshAndSaveState,
      onTitleChanged: _updatePaperTitle,
      onOpen: _openPaper,
      onRunScriptCapsule: _runScriptCapsule,
      onOpenExternalMarkdown: _openNoteMarkdownExternally,
      onOpenUri: _openUri,
      onHide: _hidePaper,
      onDelete: _deletePaper,
      onTodoItemDeleted: _markTodoItemDeleted,
      onTodoItemRestored: _clearTodoItemDeleted,
      onTodoReminderReset: _resetTodoReminder,
      onSetAlwaysOnTop: _setPaperAlwaysOnTop,
      onSetPinnedToDesktop: _setPaperPinnedToDesktop,
      onSurfaceChanged: _updatePaperSurface,
      onCaptureBounds: _capturePaperBounds,
    );
  }

  Future<void> _createPaper(String type, {PaperData? sourcePaper}) async {
    PaperData? paper;
    setState(() {
      paper = controller.tryCreatePaper(type, sourcePaper: sourcePaper);
    });
    final createdPaper = paper;
    if (createdPaper == null) {
      _showPaperLimitSnackBar();
      return;
    }
    await controller.showPaper(createdPaper);
    await _saveState();
  }

  void _showPaperLimitSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Paper limit reached. Delete papers you no longer need before creating more.',
        ),
      ),
    );
  }

  bool _collapseAllActiveFor(PaperData? surfacePaper) {
    if (!controller.state.useCapsuleMode ||
        !controller.state.useCapsuleCollapseAll) {
      return false;
    }
    return surfacePaper == null
        ? controller.state.capsuleCollapseAllActive
        : controller.state.isCapsuleCollapseAllActiveFor(surfacePaper);
  }

  Future<void> _toggleCollapseAll([PaperData? paper]) async {
    setState(() {
      controller.state.toggleCapsuleCollapseAllFor(paper);
    });
    await _saveState();
  }

  Future<void> _saveState({bool scheduleLocalEditSync = true}) async {
    AppState? beforeState;
    final saveLocalEditSyncGeneration = _localEditSyncGeneration;
    _saveQueue = _saveQueue.catchError((_) {}).then((_) async {
      try {
        final loadedState = await widget.store.load();
        beforeState = _stateSnapshot(loadedState);
      } catch (_) {
        beforeState = null;
      }
      await widget.store.save(controller.state);
      await controller.rebuildTrayMenu();
      _refreshSurfaceVisibilitySnapshot();
    });
    await _saveQueue;
    final localBeforeState = beforeState;
    if (scheduleLocalEditSync &&
        localBeforeState != null &&
        saveLocalEditSyncGeneration == _localEditSyncGeneration &&
        !_isSettingsOpen) {
      _scheduleLocalEditSync(
        beforeState: localBeforeState,
        afterState: _stateSnapshot(controller.state),
      );
    }
  }

  Future<void> _refreshAndSaveState() async {
    if (mounted) {
      setState(() {});
    }
    await _saveState();
  }

  Future<void> _updatePaperTitle(PaperData paper) async {
    if (mounted) {
      setState(() {});
    }
    _titleSurfaceDebounce?.cancel();
    _titleSurfaceDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(controller.updatePaperSurface(paper));
    });
    await _saveState();
  }

  Future<void> _deletePaper(PaperData paper) async {
    final confirmed = await _confirmDeletePaper(paper);
    if (!confirmed) {
      return;
    }
    final removedIndex = controller.state.papers.indexWhere(
      (candidate) => candidate.id == paper.id,
    );
    if (removedIndex < 0) {
      return;
    }
    final removedPaper = PaperData.fromJson(paper.toJson());
    final detachedLinks = <_LinkedNoteRestore>[];
    PaperData? defaultPaper;
    if (removedPaper.isTodo) {
      _clearTodoReminderStateForItems(
        removedPaper.items,
        hideActiveSnackBar: true,
      );
    }
    setState(() {
      controller.state.sync
          .markPaperDeleted(removedPaper.id, DateTime.now().toUtc());
      controller.state.papers.removeAt(removedIndex);
      if (_surfacePaperId == removedPaper.id) {
        _surfacePaperId = null;
      }
      if (removedPaper.isNote) {
        for (final todoPaper in controller.state.papers) {
          if (!todoPaper.isTodo) {
            continue;
          }
          for (final item in todoPaper.items) {
            if (item.linkedNoteId == removedPaper.id) {
              detachedLinks.add(
                _LinkedNoteRestore(
                  paperId: todoPaper.id,
                  itemId: item.id,
                  noteId: removedPaper.id,
                ),
              );
              item.linkedNoteId = null;
            }
          }
        }
      }
      if (controller.state.papers.isEmpty) {
        defaultPaper = controller.tryCreatePaper(PaperTypes.todo);
      }
    });
    await controller.hidePaper(paper);
    final createdDefaultPaper = defaultPaper;
    if (createdDefaultPaper != null) {
      await controller.showPaper(createdDefaultPaper);
    }
    unawaited(_saveState());
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_displayTitle(removedPaper)} deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(
            _undoDeletePaper(
              restoredPaper: removedPaper,
              targetIndex: removedIndex,
              detachedLinks: detachedLinks,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _undoDeletePaper({
    required PaperData restoredPaper,
    required int targetIndex,
    required List<_LinkedNoteRestore> detachedLinks,
  }) async {
    if (controller.state.papers.any((paper) => paper.id == restoredPaper.id)) {
      return;
    }
    setState(() {
      final insertIndex = targetIndex
          .clamp(
            0,
            controller.state.papers.length,
          )
          .toInt();
      controller.state.sync.clearPaperDeleted(restoredPaper.id);
      controller.state.papers.insert(insertIndex, restoredPaper);
      for (final link in detachedLinks) {
        _restoreLinkedNote(link);
      }
    });
    if (restoredPaper.isVisible) {
      await controller.showPaper(restoredPaper);
    }
    await _saveState();
  }

  void _markTodoItemDeleted(PaperData paper, PaperItem item) {
    _resetTodoReminder(item);
    controller.state.sync.markTodoItemDeleted(
      paper.id,
      item.id,
      DateTime.now().toUtc(),
    );
  }

  void _resetTodoReminder(PaperItem item) {
    _clearTodoReminderStateForItems([item], hideActiveSnackBar: true);
  }

  void _clearTodoItemDeleted(PaperData paper, PaperItem item) {
    controller.state.sync.clearTodoItemDeleted(paper.id, item.id);
  }

  void _setPaperAlwaysOnTop(PaperData paper, bool enabled) {
    setState(() => controller.setPaperAlwaysOnTop(paper, enabled));
  }

  void _setPaperPinnedToDesktop(PaperData paper, bool pinned) {
    setState(() => controller.setPaperPinnedToDesktop(paper, pinned));
  }

  Future<void> _hidePaper(PaperData paper) async {
    final hideFuture = controller.hidePaper(paper);
    setState(() {
      if (_surfacePaperId == paper.id) {
        _surfacePaperId = null;
      }
    });
    await hideFuture;
    await _saveState();
  }

  Future<void> _openPaper(PaperData paper) async {
    setState(() {
      paper.isVisible = true;
      _surfacePaperId = paper.id;
    });
    await controller.showPaper(paper);
    await _saveState();
  }

  Future<void> _openNoteMarkdownExternally(PaperData paper) async {
    if (!paper.isNote) {
      return;
    }
    try {
      final file = await _writeExternalMarkdownFile(paper);
      await controller.openExternalFile(file.path);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opened markdown file: ${file.path}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'External markdown open failed: ${_readableFailureMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _runScriptCapsule(ScriptCapsuleSpec spec) async {
    try {
      await controller.runScriptCapsule(spec);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Script capsule failed: ${_readableFailureMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _openUri(String uri) async {
    final normalizedUri = _normalizeExternalUri(uri);
    if (normalizedUri == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open link failed: unsupported link target.'),
        ),
      );
      return;
    }
    try {
      await controller.openUri(normalizedUri);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Open link failed: ${_readableFailureMessage(error)}'),
        ),
      );
    }
  }

  Future<File> _writeExternalMarkdownFile(PaperData paper) async {
    final documentsPath = await controller.documentsDirectoryPath();
    final directory = Directory(
      p.join(documentsPath, 'RePaperTodo', 'exports'),
    );
    directory.createSync(recursive: true);
    _cleanupOldExternalMarkdownExports(directory);
    final safePaperId = _safeFilename(paper.id);
    final paperId = safePaperId.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toRadixString(16)
        : safePaperId;
    final file = File(
      p.join(
        directory.path,
        'paper-$paperId${controller.state.externalMarkdownExtension}',
      ),
    );
    file.writeAsStringSync(paper.content);
    return file;
  }

  void _cleanupOldExternalMarkdownExports(Directory directory) {
    final cutoff = DateTime.now().subtract(_externalMarkdownExportRetention);
    try {
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        if (!p.basename(entity.path).startsWith('paper-')) {
          continue;
        }
        if (entity.lastModifiedSync().isBefore(cutoff)) {
          entity.deleteSync();
        }
      }
    } catch (_) {
      // Export cleanup is opportunistic; opening the current note should win.
    }
  }

  String _safeFilename(String value) {
    final safe =
        value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]'), '_').trim();
    if (safe.length <= _maxExternalMarkdownPaperIdFileNameLength) {
      return safe;
    }
    return '${safe.substring(0, 72)}_${safe.substring(safe.length - 23)}';
  }

  Future<void> _showHiddenPapers() async {
    final hiddenPapers =
        controller.state.papers.where((paper) => !paper.isVisible).toList();
    setState(() {
      for (final paper in hiddenPapers) {
        paper.isVisible = true;
      }
    });
    for (final paper in hiddenPapers) {
      await controller.showPaper(paper);
    }
    await _saveState();
  }

  Future<void> _handlePaperOpenRequest(String paperId) async {
    final paperIndex = controller.state.papers.indexWhere(
      (paper) => paper.id == paperId,
    );
    if (paperIndex < 0) {
      return;
    }
    final paper = controller.state.papers[paperIndex];
    await _openPaper(paper);
  }

  Future<void> _handleStartupCommand(StartupCommand command) async {
    if (command.kind == StartupCommandKind.none) {
      return;
    }
    if (command.kind == StartupCommandKind.settings) {
      await _openSettings();
      return;
    }
    if (command.kind == StartupCommandKind.exit) {
      await _saveAndSyncBeforeExit();
      await controller.executeStartupCommand(command);
      if (mounted) {
        setState(() {});
      }
      return;
    }
    await controller.executeStartupCommand(command);
    if (mounted) {
      setState(() {
        _refreshSurfaceVisibilitySnapshot();
      });
    }
    await controller.rebuildTrayMenu();
    await _saveState();
  }

  Future<void> _saveAndSyncBeforeExit() async {
    _surfaceSaveDebounce?.cancel();
    _surfaceSaveDebounce = null;
    await _saveState();
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    if (_isSyncing) {
      return;
    }
    await _uploadLocalEditsThenSync();
  }

  void _handleSurfaceUpdate(PaperData paper) {
    if (!mounted) {
      return;
    }
    final visibilityChanged = _rememberSurfaceVisibility(paper);
    setState(() {});
    if (visibilityChanged) {
      unawaited(controller.rebuildTrayMenu());
    }
    _surfaceSaveDebounce?.cancel();
    _surfaceSaveDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_saveState());
    });
  }

  bool _rememberSurfaceVisibility(PaperData paper) {
    final previous = _surfaceVisibilityByPaperId[paper.id];
    _surfaceVisibilityByPaperId[paper.id] = paper.isVisible;
    return previous != null && previous != paper.isVisible;
  }

  void _refreshSurfaceVisibilitySnapshot() {
    _surfaceVisibilityByPaperId
      ..clear()
      ..addEntries(
        controller.state.papers.map(
          (paper) => MapEntry(paper.id, paper.isVisible),
        ),
      );
  }

  Future<void> _replaceStateAndApplyPlatform(AppState state) async {
    setState(() {
      controller.replaceState(state);
      _refreshSurfaceVisibilitySnapshot();
    });
    await controller.applyCurrentStateToPlatform();
  }

  Future<void> _updatePaperSurface(PaperData paper) async {
    setState(() {});
    await controller.updatePaperSurface(paper);
  }

  Future<void> _capturePaperBounds(PaperData paper) async {
    await controller.capturePaperSurfaceBounds(paper);
    setState(() {});
    await _saveState();
  }

  Future<void> _syncNow({bool showMessage = true}) async {
    if (_isSyncing) {
      return;
    }
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    try {
      if (_canRunAutoSync()) {
        final uploadedPendingEdits = await _uploadPendingLocalEdits(
          reportFailures: showMessage,
        );
        if (!uploadedPendingEdits) {
          return;
        }
      } else {
        _pendingLocalEditBaseState = null;
        _pendingLocalEditLatestState = null;
      }
    } catch (error) {
      if (!mounted || !showMessage) {
        return;
      }
      _showSyncFailureSnackBar(error);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _isSyncing = true);
    try {
      final result = await widget.syncService.syncAndMergeNow(
        localState: controller.state,
        store: widget.store,
      );
      if (!mounted) {
        return;
      }
      await _replaceStateAndApplyPlatform(result.state);
      _restartAutoSyncTimer();
      if (showMessage && mounted) {
        _showSyncSnackBar(
          message: _syncRunMessage(result),
          status: result.syncResult.status,
        );
      }
    } catch (error) {
      if (!mounted || !showMessage) {
        return;
      }
      _showSyncFailureSnackBar(error);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _openRecoverySnapshots() async {
    final sync = controller.state.sync;
    if (!sync.enabled) {
      _showSyncSnackBar(
        message: _syncMessage(
          const AppSyncResult(status: AppSyncStatus.disabled),
        ),
        status: AppSyncStatus.disabled,
      );
      return;
    }
    if (sync.provider != SyncProviderIds.webDav ||
        !sync.webDav.isSecurelyConfigured) {
      _showSyncSnackBar(
        message: _syncMessage(
          const AppSyncResult(status: AppSyncStatus.configurationMissing),
        ),
        status: AppSyncStatus.configurationMissing,
      );
      return;
    }
    final snapshot = await showDialog<WebDavSnapshotRecord>(
      context: context,
      builder: (context) {
        return _RecoverySnapshotsDialog(
          loadSnapshots: () => widget.syncService.listRecoverySnapshots(
            localState: controller.state,
            store: widget.store,
          ),
        );
      },
    );
    if (!mounted || snapshot == null) {
      return;
    }
    final confirmed = await _confirmRestoreSnapshot(snapshot);
    if (!mounted || !confirmed) {
      return;
    }
    await _restoreRecoverySnapshot(snapshot);
  }

  Future<bool> _confirmRestoreSnapshot(WebDavSnapshotRecord snapshot) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Restore snapshot?'),
              content: Text(_snapshotSummary(snapshot)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  key: const ValueKey('confirm-restore-snapshot'),
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('Restore'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _restoreRecoverySnapshot(WebDavSnapshotRecord snapshot) async {
    setState(() => _isSyncing = true);
    try {
      final result = await widget.syncService.restoreRecoverySnapshot(
        localState: controller.state,
        store: widget.store,
        snapshotPath: snapshot.path,
      );
      if (!mounted) {
        return;
      }
      if (result.state != null) {
        await _replaceStateAndApplyPlatform(result.state!);
      }
      if (!mounted) {
        return;
      }
      _showSyncSnackBar(
        message: _syncMessage(result),
        status: result.status,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showRestoreFailureSnackBar(snapshot, error);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _openSettings() async {
    final hadPendingLocalEditSync = _pendingLocalEditBaseState != null &&
        _pendingLocalEditLatestState != null;
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    final previousSyncJson = jsonEncode(controller.state.sync.toJson());
    _isSettingsOpen = true;
    final previousUsePersistentPowerShellProcess =
        controller.state.usePersistentPowerShellProcess;
    final previousPreferPowerShell7 = controller.state.preferPowerShell7;
    final previousHideScriptRunWindow = controller.state.hideScriptRunWindow;
    final previousUseTodoReminderInterval =
        controller.state.useTodoReminderInterval;
    final previousTodoReminderIntervalValue =
        controller.state.todoReminderIntervalValue;
    final previousTodoReminderIntervalUnit =
        controller.state.todoReminderIntervalUnit;
    final previousCapsuleSettings = (
      useCapsuleMode: controller.state.useCapsuleMode,
      useDeepCapsuleMode: controller.state.useDeepCapsuleMode,
      useCapsuleCollapseAll: controller.state.useCapsuleCollapseAll,
      capsuleCollapseAllActive: controller.state.capsuleCollapseAllActive,
      deepCapsuleSide: controller.state.deepCapsuleSide,
      deepCapsuleStartTopMargin: controller.state.deepCapsuleStartTopMargin,
      deepCapsuleMonitorDeviceName:
          controller.state.deepCapsuleMonitorDeviceName,
      showDeepCapsuleWhileExpanded:
          controller.state.showDeepCapsuleWhileExpanded,
      collapseExpandedDeepCapsuleOnClick:
          controller.state.collapseExpandedDeepCapsuleOnClick,
      hideDeepCapsulesWhenCovered: controller.state.hideDeepCapsulesWhenCovered,
    );
    final result = await showSyncSettingsDialog(
      context: context,
      initialSettings: controller.state.sync,
      initialTheme: controller.state.theme,
      initialColorScheme: controller.state.colorScheme,
      initialCustomThemeColorHex: controller.state.customThemeColorHex,
      initialMarkdownRenderMode: controller.state.markdownRenderMode,
      initialTodoVisualSize: controller.state.todoVisualSize,
      initialUiFontPreset: controller.state.uiFontPreset,
      initialSystemFontFamilyName: controller.state.systemFontFamilyName,
      initialExternalMarkdownExtension:
          controller.state.externalMarkdownExtension,
      initialZoom: controller.state.zoom,
      initialMaxTitleLength: controller.state.maxTitleLength,
      initialEnableToolTips: controller.state.enableToolTips,
      initialEnableAnimations: controller.state.enableAnimations,
      initialTodoLineSpacing: controller.state.todoLineSpacing,
      initialNoteLineSpacing: controller.state.noteLineSpacing,
      initialShowTodoDueRelativeTime: controller.state.showTodoDueRelativeTime,
      initialTodoDueYearDisplayMode: controller.state.todoDueYearDisplayMode,
      initialUseTodoReminderInterval: controller.state.useTodoReminderInterval,
      initialTodoReminderIntervalValue:
          controller.state.todoReminderIntervalValue,
      initialTodoReminderIntervalUnit:
          controller.state.todoReminderIntervalUnit,
      initialTodoReminderScope: controller.state.todoReminderScope,
      initialTodoReminderBubbleDurationSeconds:
          controller.state.todoReminderBubbleDurationSeconds,
      initialShowTopBarNewTodoButton: controller.state.showTopBarNewTodoButton,
      initialShowTopBarNewNoteButton: controller.state.showTopBarNewNoteButton,
      initialShowTopBarExternalOpenButton:
          controller.state.showTopBarExternalOpenButton,
      initialUseCapsuleMode: controller.state.useCapsuleMode,
      initialUseDeepCapsuleMode: controller.state.useDeepCapsuleMode,
      initialUseCapsuleCollapseAll: controller.state.useCapsuleCollapseAll,
      initialCapsuleCollapseAllActive:
          controller.state.capsuleCollapseAllActive,
      initialDeepCapsuleSide: controller.state.deepCapsuleSide,
      initialDeepCapsuleStartTopMargin:
          controller.state.deepCapsuleStartTopMargin,
      initialDeepCapsuleMonitorDeviceName:
          controller.state.deepCapsuleMonitorDeviceName,
      initialShowDeepCapsuleWhileExpanded:
          controller.state.showDeepCapsuleWhileExpanded,
      initialCollapseExpandedDeepCapsuleOnClick:
          controller.state.collapseExpandedDeepCapsuleOnClick,
      initialHideDeepCapsulesWhenCovered:
          controller.state.hideDeepCapsulesWhenCovered,
      initialStartAtLogin: controller.state.startAtLogin,
      supportsStartAtLogin: controller.supportsStartupAtLogin,
      supportsHideFromWindowSwitcher:
          controller.supportsWindowSwitcherVisibility,
      supportsFullscreenTopmostMode: controller.supportsFullscreenTopmostMode,
      supportsGlobalHotkeys: controller.supportsGlobalHotkeys,
      supportsScriptCapsules: controller.supportsScriptCapsules,
      initialHideFromWindowSwitcher:
          controller.state.hidePapersFromWindowSwitcher,
      initialFullscreenTopmostMode: controller.state.fullscreenTopmostMode,
      initialPinnedTodoHotKey: controller.state.pinnedTodoHotKey,
      initialPinnedNoteHotKey: controller.state.pinnedNoteHotKey,
      initialRunLinkedScriptCapsulesOnClick:
          controller.state.runLinkedScriptCapsulesOnClick,
      initialUsePersistentPowerShellProcess:
          controller.state.usePersistentPowerShellProcess,
      initialPreferPowerShell7: controller.state.preferPowerShell7,
      initialHideScriptRunWindow: controller.state.hideScriptRunWindow,
      initialEnableTodoNoteLinks: controller.state.enableTodoNoteLinks,
      initialShowLinkedNoteName: controller.state.showLinkedNoteName,
      initialAllowLongLinkedNoteTitles:
          controller.state.allowLongLinkedNoteTitles,
      initialHideLinkedNotesFromCapsules:
          controller.state.hideLinkedNotesFromCapsules,
    );
    if (result == null) {
      _isSettingsOpen = false;
      if (hadPendingLocalEditSync) {
        _reschedulePendingLocalEditSync();
      }
      return;
    }
    final syncSettingsChanged =
        jsonEncode(result.sync.toJson()) != previousSyncJson;
    if (syncSettingsChanged) {
      _localEditSyncGeneration += 1;
      _clearPendingLocalEditSync();
    }
    final reminderCadenceChanged = result.useTodoReminderInterval !=
            previousUseTodoReminderInterval ||
        result.todoReminderIntervalValue != previousTodoReminderIntervalValue ||
        result.todoReminderIntervalUnit != previousTodoReminderIntervalUnit;
    final capsuleSettingsChanged = previousCapsuleSettings !=
        (
          useCapsuleMode: result.useCapsuleMode,
          useDeepCapsuleMode: result.useDeepCapsuleMode,
          useCapsuleCollapseAll: result.useCapsuleCollapseAll,
          capsuleCollapseAllActive: result.capsuleCollapseAllActive,
          deepCapsuleSide: result.deepCapsuleSide,
          deepCapsuleStartTopMargin: result.deepCapsuleStartTopMargin,
          deepCapsuleMonitorDeviceName: result.deepCapsuleMonitorDeviceName,
          showDeepCapsuleWhileExpanded: result.showDeepCapsuleWhileExpanded,
          collapseExpandedDeepCapsuleOnClick:
              result.collapseExpandedDeepCapsuleOnClick,
          hideDeepCapsulesWhenCovered: result.hideDeepCapsulesWhenCovered,
        );
    if (reminderCadenceChanged) {
      _lastTodoReminderAt.clear();
    }
    setState(() {
      controller.state.sync = result.sync;
      controller.state.theme = result.theme;
      controller.state.colorScheme = result.colorScheme;
      controller.state.customThemeColorHex = result.customThemeColorHex;
      controller.state.markdownRenderMode = result.markdownRenderMode;
      controller.state.todoVisualSize = result.todoVisualSize;
      controller.state.uiFontPreset = result.uiFontPreset;
      controller.state.systemFontFamilyName = result.systemFontFamilyName;
      controller.state.externalMarkdownExtension =
          result.externalMarkdownExtension;
      controller.state.zoom = result.zoom;
      controller.state.maxTitleLength = result.maxTitleLength;
      controller.state.enableToolTips = result.enableToolTips;
      controller.state.enableAnimations = result.enableAnimations;
      controller.state.todoLineSpacing = result.todoLineSpacing;
      controller.state.noteLineSpacing = result.noteLineSpacing;
      controller.state.showTodoDueRelativeTime = result.showTodoDueRelativeTime;
      controller.state.todoDueYearDisplayMode = result.todoDueYearDisplayMode;
      controller.state.useTodoReminderInterval = result.useTodoReminderInterval;
      controller.state.todoReminderIntervalValue =
          result.todoReminderIntervalValue;
      controller.state.todoReminderIntervalUnit =
          result.todoReminderIntervalUnit;
      controller.state.todoReminderScope = result.todoReminderScope;
      controller.state.todoReminderBubbleDurationSeconds =
          result.todoReminderBubbleDurationSeconds;
      controller.state.showTopBarNewTodoButton = result.showTopBarNewTodoButton;
      controller.state.showTopBarNewNoteButton = result.showTopBarNewNoteButton;
      controller.state.showTopBarExternalOpenButton =
          result.showTopBarExternalOpenButton;
      controller.applyCapsuleSettings(
        useCapsuleMode: result.useCapsuleMode,
        useDeepCapsuleMode: result.useDeepCapsuleMode,
        useCapsuleCollapseAll: result.useCapsuleCollapseAll,
        capsuleCollapseAllActive: result.capsuleCollapseAllActive,
        deepCapsuleSide: result.deepCapsuleSide,
        deepCapsuleStartTopMargin: result.deepCapsuleStartTopMargin,
        deepCapsuleMonitorDeviceName: result.deepCapsuleMonitorDeviceName,
        showDeepCapsuleWhileExpanded: result.showDeepCapsuleWhileExpanded,
        collapseExpandedDeepCapsuleOnClick:
            result.collapseExpandedDeepCapsuleOnClick,
        hideDeepCapsulesWhenCovered: result.hideDeepCapsulesWhenCovered,
      );
      controller.state.startAtLogin = result.startAtLogin;
      controller.state.hidePapersFromWindowSwitcher =
          result.hideFromWindowSwitcher;
      controller.state.fullscreenTopmostMode = result.fullscreenTopmostMode;
      controller.state.pinnedTodoHotKey = result.pinnedTodoHotKey;
      controller.state.pinnedNoteHotKey = result.pinnedNoteHotKey;
      controller.state.runLinkedScriptCapsulesOnClick =
          result.runLinkedScriptCapsulesOnClick;
      controller.state.usePersistentPowerShellProcess =
          result.usePersistentPowerShellProcess;
      controller.state.preferPowerShell7 = result.preferPowerShell7;
      controller.state.hideScriptRunWindow = result.hideScriptRunWindow;
      controller.state.enableTodoNoteLinks = result.enableTodoNoteLinks;
      controller.state.showLinkedNoteName = result.showLinkedNoteName;
      controller.state.allowLongLinkedNoteTitles =
          result.allowLongLinkedNoteTitles;
      controller.state.hideLinkedNotesFromCapsules =
          result.hideLinkedNotesFromCapsules;
    });
    final platformSettingErrors = <String>[];
    Future<void> applyPlatformSetting(
      String label,
      Future<void> Function() action,
    ) async {
      try {
        await action();
      } catch (error) {
        platformSettingErrors.add('$label: ${_readableFailureMessage(error)}');
      }
    }

    if (controller.supportsStartupAtLogin) {
      await applyPlatformSetting(
        'Startup at login',
        () => controller.setStartupAtLogin(result.startAtLogin),
      );
    }
    await applyPlatformSetting(
      'Window switcher visibility',
      () => controller.setHideFromWindowSwitcher(result.hideFromWindowSwitcher),
    );
    await applyPlatformSetting(
      'Fullscreen/topmost mode',
      () => controller.setFullscreenTopmostMode(result.fullscreenTopmostMode),
    );
    await applyPlatformSetting(
      'Global hotkeys',
      controller.registerGlobalHotkeys,
    );
    if (_shouldStopPersistentScriptCapsules(
      previousUsePersistentPowerShellProcess,
      previousPreferPowerShell7,
      previousHideScriptRunWindow,
      result,
    )) {
      await applyPlatformSetting(
        'Script capsule process',
        controller.stopPersistentScriptCapsules,
      );
    }
    if (_shouldPreparePersistentScriptCapsules(
      previousUsePersistentPowerShellProcess,
      previousPreferPowerShell7,
      previousHideScriptRunWindow,
      result,
    )) {
      await applyPlatformSetting(
        'Script capsule process',
        controller.preparePersistentScriptCapsules,
      );
    }
    if (capsuleSettingsChanged) {
      await applyPlatformSetting(
        'Paper surfaces',
        controller.applyCurrentStateToPlatform,
      );
    }
    if (platformSettingErrors.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Platform settings failed: ${platformSettingErrors.join('; ')}',
          ),
        ),
      );
    }
    widget.onAppThemeChanged?.call();
    _restartAutoSyncTimer();
    if (syncSettingsChanged || !_canRunAutoSync()) {
      _clearPendingLocalEditSync();
    } else if (hadPendingLocalEditSync) {
      _reschedulePendingLocalEditSync();
    }
    _restartTodoReminderTimer();
    try {
      await _saveState(scheduleLocalEditSync: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Settings save failed: ${_readableFailureMessage(error)}',
            ),
          ),
        );
      }
    } finally {
      _isSettingsOpen = false;
    }
  }

  void _showSyncSnackBar({
    required String message,
    required AppSyncStatus status,
  }) {
    final action = switch (status) {
      AppSyncStatus.disabled ||
      AppSyncStatus.configurationMissing ||
      AppSyncStatus.payloadUnreadable =>
        SnackBarAction(
          label: 'Settings',
          onPressed: () {
            if (mounted) {
              unawaited(_openSettings());
            }
          },
        ),
      AppSyncStatus.conflict => SnackBarAction(
          label: 'Recovery',
          onPressed: () {
            if (mounted) {
              unawaited(_openRecoverySnapshots());
            }
          },
        ),
      _ => null,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
      ),
    );
  }

  void _showSyncFailureSnackBar(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sync failed: ${_readableFailureMessage(error)}'),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () {
            if (mounted) {
              unawaited(_syncNow());
            }
          },
        ),
      ),
    );
  }

  void _showRestoreFailureSnackBar(
    WebDavSnapshotRecord snapshot,
    Object error,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Restore failed: ${_readableFailureMessage(error)}'),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () {
            if (mounted) {
              unawaited(_restoreRecoverySnapshot(snapshot));
            }
          },
        ),
      ),
    );
  }

  bool _shouldStopPersistentScriptCapsules(
    bool previousUsePersistentPowerShellProcess,
    bool previousPreferPowerShell7,
    bool previousHideScriptRunWindow,
    SyncSettingsDialogResult result,
  ) {
    if (!previousUsePersistentPowerShellProcess) {
      return false;
    }
    return !result.usePersistentPowerShellProcess ||
        previousPreferPowerShell7 != result.preferPowerShell7 ||
        previousHideScriptRunWindow != result.hideScriptRunWindow;
  }

  bool _shouldPreparePersistentScriptCapsules(
    bool previousUsePersistentPowerShellProcess,
    bool previousPreferPowerShell7,
    bool previousHideScriptRunWindow,
    SyncSettingsDialogResult result,
  ) {
    if (!result.usePersistentPowerShellProcess) {
      return false;
    }
    return !previousUsePersistentPowerShellProcess ||
        previousPreferPowerShell7 != result.preferPowerShell7 ||
        previousHideScriptRunWindow != result.hideScriptRunWindow;
  }

  String _syncMessage(AppSyncResult result) {
    if (result.message.isNotEmpty) {
      return result.message;
    }
    return switch (result.status) {
      AppSyncStatus.disabled => 'Sync is disabled.',
      AppSyncStatus.configurationMissing =>
        'Complete WebDAV sync settings and encryption passphrase first.',
      AppSyncStatus.uploaded => 'Local data uploaded.',
      AppSyncStatus.downloaded => 'Remote data downloaded.',
      AppSyncStatus.conflict =>
        'Remote data changed during sync. Pull again before upload.',
      AppSyncStatus.payloadUnreadable =>
        'Unable to decrypt remote sync data. Check the sync encryption passphrase.',
    };
  }

  String _syncRunMessage(AppSyncRunResult result) {
    final baseMessage = _syncMessage(result.syncResult);
    final appliedCount = result.operationAppliedCount;
    final parts = <String>[baseMessage];
    if (appliedCount > 0) {
      final changeLabel = appliedCount == 1 ? 'change' : 'changes';
      parts.add('Merged $appliedCount remote $changeLabel.');
    }
    final mergeResult = result.operationMergeResult;
    if (mergeResult != null && mergeResult.legacyPlainOperationLogCount > 0) {
      final total = mergeResult.legacyPlainOperationLogCount;
      final migrated = mergeResult.legacyPlainOperationLogMigratedCount;
      final logLabel = total == 1 ? 'operation log' : 'operation logs';
      if (migrated == total) {
        parts.add(
          'Migrated $total legacy WebDAV $logLabel to encrypted payloads.',
        );
      } else if (migrated > 0) {
        parts.add(
          'Migrated $migrated of $total legacy WebDAV $logLabel to encrypted payloads; sync again to retry the rest.',
        );
      } else {
        parts.add(
          'Found $total legacy plain WebDAV $logLabel; sync again after remote ETags are available to retry encryption migration.',
        );
      }
    }
    return parts.join(' ');
  }

  void _restartAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    if (!_canRunAutoSync()) {
      return;
    }
    final interval = Duration(
      minutes: controller.state.sync.webDav.autoSyncIntervalMinutes,
    );
    _autoSyncTimer = Timer.periodic(interval, (_) {
      unawaited(_syncSilentlyIfConfigured());
    });
  }

  Future<void> _syncSilentlyIfConfigured() async {
    if (_isSyncing || !_canRunAutoSync()) {
      return;
    }
    await _syncNow(showMessage: false);
  }

  void _scheduleLocalEditSync({
    required AppState beforeState,
    required AppState afterState,
  }) {
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    if (!_canRunAutoSync()) {
      _clearPendingLocalEditSync();
      return;
    }
    _pendingLocalEditBaseState ??= beforeState;
    _pendingLocalEditLatestState = afterState;
    _pendingLocalEditGeneration = _localEditSyncGeneration;
    _localEditSyncDebounce = Timer(const Duration(seconds: 5), () {
      _localEditSyncDebounce = null;
      unawaited(_uploadLocalEditsThenSync());
    });
  }

  Future<void> _uploadLocalEditsThenSync() async {
    if (!_canRunAutoSync()) {
      _clearPendingLocalEditSync();
      return;
    }
    if (_isSyncing) {
      _reschedulePendingLocalEditSync();
      return;
    }
    final uploadedPendingEdits = await _uploadPendingLocalEdits();
    if (!uploadedPendingEdits) {
      return;
    }
    await _syncSilentlyIfConfigured();
  }

  Future<bool> _uploadPendingLocalEdits({bool reportFailures = false}) async {
    final beforeState = _pendingLocalEditBaseState;
    final afterState = _pendingLocalEditLatestState;
    final generation = _pendingLocalEditGeneration;
    _pendingLocalEditBaseState = null;
    _pendingLocalEditLatestState = null;
    _pendingLocalEditGeneration = null;
    if (beforeState == null || afterState == null) {
      return true;
    }
    if (generation != _localEditSyncGeneration) {
      return true;
    }
    try {
      final uploadResult = await widget.syncService.uploadLocalOperations(
        beforeState: beforeState,
        afterState: afterState,
        store: widget.store,
      );
      if (!mounted) {
        return false;
      }
      if (uploadResult.uploadedCount > 0 || uploadResult.stateChanged) {
        await _replaceStateAndApplyPlatform(uploadResult.state);
      }
      return true;
    } catch (error) {
      _pendingLocalEditBaseState = beforeState;
      _pendingLocalEditLatestState = afterState;
      _pendingLocalEditGeneration = generation;
      if (reportFailures) {
        rethrow;
      }
      return false;
    }
  }

  void _reschedulePendingLocalEditSync() {
    if (_pendingLocalEditBaseState == null ||
        _pendingLocalEditLatestState == null ||
        _localEditSyncDebounce != null) {
      return;
    }
    _localEditSyncDebounce = Timer(const Duration(seconds: 1), () {
      _localEditSyncDebounce = null;
      unawaited(_uploadLocalEditsThenSync());
    });
  }

  void _clearPendingLocalEditSync() {
    _localEditSyncDebounce?.cancel();
    _localEditSyncDebounce = null;
    _pendingLocalEditBaseState = null;
    _pendingLocalEditLatestState = null;
    _pendingLocalEditGeneration = null;
  }

  AppState _stateSnapshot(AppState state) {
    return AppState.fromJson(state.toJson());
  }

  bool _canRunAutoSync() {
    final settings = controller.state.sync;
    return settings.enabled &&
        settings.provider == SyncProviderIds.webDav &&
        settings.webDav.isSecurelyConfigured;
  }

  Future<bool> _confirmDeletePaper(PaperData paper) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Delete paper?'),
              content: Text(_displayTitle(paper)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  String _displayTitle(PaperData paper) {
    final title = controller.paperTitleText(paper);
    return _shortenTitle(
      title,
      controller.state.maxTitleLength,
    );
  }

  void _restoreLinkedNote(_LinkedNoteRestore link) {
    for (final paper in controller.state.papers) {
      if (paper.id != link.paperId) {
        continue;
      }
      for (final item in paper.items) {
        if (item.id == link.itemId) {
          item.linkedNoteId = link.noteId;
          return;
        }
      }
    }
  }

  void _restartTodoReminderTimer() {
    _todoReminderTimer?.cancel();
    _todoReminderTimer = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkTodoReminders();
      }
    });
    _todoReminderTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkTodoReminders(),
    );
  }

  void _checkTodoReminders() {
    if (!mounted) {
      return;
    }
    final now = DateTime.now();
    final candidates = _reminderCandidates(now);
    final shouldRefreshRelativeDueLabels =
        controller.state.showTodoDueRelativeTime && candidates.isNotEmpty;
    final readyCandidates = candidates
        .where((candidate) => _shouldShowReminder(candidate, now))
        .toList();
    if (readyCandidates.isNotEmpty) {
      if (controller.state.todoReminderScope == TodoReminderScopes.nearest &&
          readyCandidates.length > 1) {
        readyCandidates.sort((a, b) {
          final distance = _distanceFromNow(a, now).compareTo(
            _distanceFromNow(b, now),
          );
          return distance == 0 ? a.dueAt.compareTo(b.dueAt) : distance;
        });
        readyCandidates.removeRange(1, readyCandidates.length);
      }
      for (final candidate in readyCandidates) {
        _lastTodoReminderAt[candidate.key] = now;
      }
      _showTodoReminder(readyCandidates);
    }
    if (shouldRefreshRelativeDueLabels) {
      setState(() {});
    }
  }

  List<_TodoReminderCandidate> _reminderCandidates(DateTime now) {
    final candidates = <_TodoReminderCandidate>[];
    for (final paper in controller.state.papers) {
      if (!paper.isTodo) {
        continue;
      }
      for (final item in paper.items) {
        if (item.done) {
          continue;
        }
        final dueAt = DateTime.tryParse(item.dueAtLocal ?? '')?.toLocal();
        if (dueAt == null) {
          continue;
        }
        candidates.add(_TodoReminderCandidate(paper, item, dueAt));
      }
    }
    candidates.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return candidates;
  }

  bool _shouldShowReminder(_TodoReminderCandidate candidate, DateTime now) {
    final lastReminderAt = _lastTodoReminderAt[candidate.key];
    if (controller.state.useTodoReminderInterval) {
      final interval = _reminderInterval(candidate.item);
      if (candidate.dueAt.isAfter(now.add(interval))) {
        return false;
      }
      return lastReminderAt == null ||
          now.difference(lastReminderAt) >= interval;
    }
    if (now.isBefore(candidate.dueAt.subtract(_todoReminderLeadTime)) ||
        now.isAfter(candidate.dueAt.add(_todoReminderGraceTime))) {
      return false;
    }
    return lastReminderAt == null;
  }

  Duration _distanceFromNow(_TodoReminderCandidate candidate, DateTime now) {
    final difference = candidate.dueAt.difference(now);
    return difference.isNegative
        ? Duration(microseconds: -difference.inMicroseconds)
        : difference;
  }

  Duration _reminderInterval(PaperItem item) {
    final value = (item.reminderIntervalValue ??
            controller.state.todoReminderIntervalValue)
        .clamp(1, 240)
        .toInt();
    final unit = TodoReminderIntervalUnits.normalize(
      item.reminderIntervalUnit ?? controller.state.todoReminderIntervalUnit,
    );
    return unit == TodoReminderIntervalUnits.hours
        ? Duration(hours: value)
        : Duration(minutes: value);
  }

  void _showTodoReminder(List<_TodoReminderCandidate> candidates) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final reminderItemIds = candidates
        .map((candidate) => candidate.item.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    _activeTodoReminderItemIds
      ..clear()
      ..addAll(reminderItemIds);
    final first = candidates.first;
    final message = candidates.length == 1
        ? 'Reminder: ${_displayTitle(first.paper)} - ${_displayItemText(first.item)}'
        : 'Reminder: ${candidates.length} todo items are due.';
    final snackBarController = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(
          seconds: controller.state.todoReminderBubbleDurationSeconds,
        ),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => unawaited(_openPaper(first.paper)),
        ),
      ),
    );
    unawaited(snackBarController.closed.then((_) {
      if (_sameStringSet(_activeTodoReminderItemIds, reminderItemIds)) {
        _activeTodoReminderItemIds.clear();
      }
    }));
  }

  void _clearTodoReminderStateForItems(
    Iterable<PaperItem> items, {
    required bool hideActiveSnackBar,
  }) {
    final itemIds = items
        .map((item) => item.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (itemIds.isEmpty) {
      return;
    }
    _lastTodoReminderAt.removeWhere((key, _) {
      return itemIds.any((itemId) => key.startsWith('$itemId|'));
    });
    if (hideActiveSnackBar &&
        _activeTodoReminderItemIds.any(itemIds.contains)) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _activeTodoReminderItemIds.clear();
      return;
    }
    _activeTodoReminderItemIds.removeWhere(itemIds.contains);
  }

  String _displayItemText(PaperItem item) {
    final text = item.text.trim();
    return text.isEmpty ? 'Todo item' : text;
  }
}

class _TodoReminderCandidate {
  const _TodoReminderCandidate(this.paper, this.item, this.dueAt);

  final PaperData paper;
  final PaperItem item;
  final DateTime dueAt;

  String get key => '${item.id}|${item.dueAtLocal ?? ''}';
}

class _ReminderIntervalSelection {
  const _ReminderIntervalSelection.set(this.value, this.unit) : clear = false;

  const _ReminderIntervalSelection.clear()
      : value = null,
        unit = null,
        clear = true;

  final int? value;
  final String? unit;
  final bool clear;
}

class _ReminderIntervalDialog extends StatefulWidget {
  const _ReminderIntervalDialog({
    required this.initialValue,
    required this.initialUnit,
  });

  final int? initialValue;
  final String? initialUnit;

  @override
  State<_ReminderIntervalDialog> createState() =>
      _ReminderIntervalDialogState();
}

class _ReminderIntervalDialogState extends State<_ReminderIntervalDialog> {
  late final TextEditingController _intervalController;
  late String _unit;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: (widget.initialValue ?? 10).clamp(1, 240).toString(),
    );
    _unit = TodoReminderIntervalUnits.normalize(widget.initialUnit);
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reminder interval'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _intervalController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Interval',
                prefixIcon: const Icon(Icons.notifications_active_outlined),
                errorText: _errorText,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: TodoReminderIntervalUnits.minutes,
                  icon: Icon(Icons.timer_outlined),
                  label: Text('Minutes'),
                ),
                ButtonSegment(
                  value: TodoReminderIntervalUnits.hours,
                  icon: Icon(Icons.schedule_outlined),
                  label: Text('Hours'),
                ),
              ],
              selected: {_unit},
              onSelectionChanged: (selection) {
                setState(() => _unit = selection.single);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const _ReminderIntervalSelection.clear(),
          ),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    final value = int.tryParse(_intervalController.text.trim());
    if (value == null || value < 1 || value > 240) {
      setState(() => _errorText = 'Enter a number from 1 to 240.');
      return;
    }
    Navigator.of(context).pop(
      _ReminderIntervalSelection.set(value, _unit),
    );
  }
}

class _LinkedNoteRestore {
  const _LinkedNoteRestore({
    required this.paperId,
    required this.itemId,
    required this.noteId,
  });

  final String paperId;
  final String itemId;
  final String noteId;
}

class _RecoverySnapshotsDialog extends StatefulWidget {
  const _RecoverySnapshotsDialog({
    required this.loadSnapshots,
  });

  final Future<List<WebDavSnapshotRecord>> Function() loadSnapshots;

  @override
  State<_RecoverySnapshotsDialog> createState() =>
      _RecoverySnapshotsDialogState();
}

class _RecoverySnapshotsDialogState extends State<_RecoverySnapshotsDialog> {
  late Future<List<WebDavSnapshotRecord>> _snapshotsFuture;

  @override
  void initState() {
    super.initState();
    _snapshotsFuture = widget.loadSnapshots();
  }

  void _retry() {
    setState(() {
      _snapshotsFuture = widget.loadSnapshots();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recovery snapshots'),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<List<WebDavSnapshotRecord>>(
          future: _snapshotsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 132,
                  maxHeight: 240,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          'Unable to load snapshots: '
                          '${_readableFailureMessage(snapshot.error!)}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: const ValueKey('retry-recovery-snapshots'),
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_outlined),
                        label: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              );
            }
            final snapshots = snapshot.data ?? const <WebDavSnapshotRecord>[];
            if (snapshots.isEmpty) {
              return const SizedBox(
                height: 96,
                child: Center(child: Text('No recovery snapshots found.')),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: snapshots.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final record = snapshots[index];
                  return _RecoverySnapshotListItem(
                    record: record,
                    onRestore: () => Navigator.of(context).pop(record),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _RecoverySnapshotListItem extends StatelessWidget {
  const _RecoverySnapshotListItem({
    required this.record,
    required this.onRestore,
  });

  final WebDavSnapshotRecord record;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.history_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _snapshotSummary(record),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.path,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _snapshotSizeLabel(record),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: ValueKey('restore-snapshot-${record.path}'),
              onPressed: onRestore,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('Restore'),
            ),
          ],
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history_outlined),
      title: Text(_snapshotSummary(record)),
      subtitle: Text(
        '${record.path}\n${_snapshotSizeLabel(record)}',
      ),
      isThreeLine: true,
      trailing: FilledButton.icon(
        key: ValueKey('restore-snapshot-${record.path}'),
        onPressed: onRestore,
        icon: const Icon(Icons.restore_outlined),
        label: const Text('Restore'),
      ),
    );
  }
}

String _snapshotSummary(WebDavSnapshotRecord snapshot) {
  return '${_formatSnapshotTime(snapshot.updatedAtUtc)} - ${snapshot.deviceId}';
}

String _snapshotSizeLabel(WebDavSnapshotRecord snapshot) {
  final parts = <String>[];
  final contentLength = snapshot.contentLength;
  if (contentLength != null) {
    parts.add(_formatByteCount(contentLength));
  }
  final lastModified = snapshot.lastModifiedUtc;
  if (lastModified != null) {
    parts.add('Modified ${_formatSnapshotTime(lastModified)}');
  }
  return parts.isEmpty ? 'Snapshot' : parts.join(' - ');
}

String _formatSnapshotTime(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC';
}

String _formatByteCount(int value) {
  if (value < 1024) {
    return '$value B';
  }
  final kib = value / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)} KiB';
  }
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MiB';
}

class PaperPreview extends StatelessWidget {
  const PaperPreview({
    required this.paper,
    required this.notePapers,
    required this.titleText,
    required this.enableTodoNoteLinks,
    required this.showLinkedNoteName,
    required this.allowLongLinkedNoteTitles,
    required this.runLinkedScriptCapsulesOnClick,
    required this.maxTitleLength,
    required this.enableToolTips,
    required this.enableAnimations,
    required this.markdownRenderMode,
    required this.todoVisualSize,
    required this.todoLineSpacing,
    required this.showTodoDueRelativeTime,
    required this.todoDueYearDisplayMode,
    required this.collapseAllActive,
    required this.noteLineSpacing,
    required this.onChanged,
    required this.onTitleChanged,
    required this.onOpen,
    required this.onRunScriptCapsule,
    required this.onOpenExternalMarkdown,
    required this.onOpenUri,
    required this.onHide,
    required this.onDelete,
    required this.onTodoItemDeleted,
    required this.onTodoItemRestored,
    required this.onTodoReminderReset,
    required this.onSetAlwaysOnTop,
    required this.onSetPinnedToDesktop,
    required this.onSurfaceChanged,
    required this.onCaptureBounds,
    super.key,
  });

  static const _compactPaperActionOpenSurface = 'open-surface';
  static const _compactPaperActionOpenMarkdown = 'open-markdown';
  static const _compactPaperActionToggleAlwaysOnTop = 'toggle-always-on-top';
  static const _compactPaperActionTogglePinned = 'toggle-pinned';
  static const _compactPaperActionCaptureBounds = 'capture-bounds';
  static const _compactPaperActionHide = 'hide';
  static const _compactPaperActionDelete = 'delete';
  static const _compactPaperZoomActionPrefix = 'zoom:';

  final PaperData paper;
  final List<PaperData> notePapers;
  final String titleText;
  final bool enableTodoNoteLinks;
  final bool showLinkedNoteName;
  final bool allowLongLinkedNoteTitles;
  final bool runLinkedScriptCapsulesOnClick;
  final int maxTitleLength;
  final bool enableToolTips;
  final bool enableAnimations;
  final String markdownRenderMode;
  final String todoVisualSize;
  final double todoLineSpacing;
  final bool showTodoDueRelativeTime;
  final String todoDueYearDisplayMode;
  final bool collapseAllActive;
  final double noteLineSpacing;
  final Future<void> Function() onChanged;
  final Future<void> Function(PaperData paper) onTitleChanged;
  final Future<void> Function(PaperData paper) onOpen;
  final Future<void> Function(ScriptCapsuleSpec spec) onRunScriptCapsule;
  final Future<void> Function(PaperData paper) onOpenExternalMarkdown;
  final Future<void> Function(String uri) onOpenUri;
  final Future<void> Function(PaperData paper) onHide;
  final Future<void> Function(PaperData paper) onDelete;
  final void Function(PaperData paper, PaperItem item) onTodoItemDeleted;
  final void Function(PaperData paper, PaperItem item) onTodoItemRestored;
  final void Function(PaperItem item) onTodoReminderReset;
  final void Function(PaperData paper, bool enabled) onSetAlwaysOnTop;
  final void Function(PaperData paper, bool pinned) onSetPinnedToDesktop;
  final Future<void> Function(PaperData paper) onSurfaceChanged;
  final Future<void> Function(PaperData paper) onCaptureBounds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCollapsed = collapseAllActive || paper.isCollapsed;
    final scriptCapsuleSpec =
        paper.isNote ? ScriptCapsuleSpec.tryParse(paper.content) : null;
    final textZoom = paper.textZoom.clamp(0.5, 1.5).toDouble();
    return Semantics(
      label: '$titleText ${paper.type} paper',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    paper.isTodo
                        ? Icons.check_box_outlined
                        : scriptCapsuleSpec != null
                            ? Icons.bolt_outlined
                            : Icons.notes_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  if (paper.isNote && enableTodoNoteLinks) ...[
                    const SizedBox(width: 4),
                    _noteLinkDragHandle(context),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('${paper.id}-title'),
                      initialValue:
                          PaperTitles.cleanCustomTitle(paper.title).isEmpty
                              ? titleText
                              : paper.title,
                      inputFormatters: const [
                        _PaperTitleTextInputFormatter(
                          maxLength: PaperTitles.maxTitleLength,
                        ),
                      ],
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Untitled',
                        isDense: true,
                      ),
                      style: theme.textTheme.titleMedium?.apply(
                        fontSizeFactor: textZoom,
                      ),
                      onChanged: (value) {
                        paper.title = PaperTitles.cleanCustomTitle(value);
                        unawaited(onTitleChanged(paper));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _paperHeaderActions(
                    context: context,
                    isCollapsed: isCollapsed,
                    textZoom: textZoom,
                  ),
                ),
              ),
              _animatedPaperBody(isCollapsed, scriptCapsuleSpec),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteLinkDragHandle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final handle = Semantics(
      label: 'Drag to link note to todo',
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox.square(
          key: ValueKey('${paper.id}-note-link-drag-handle'),
          dimension: 28,
          child: Icon(
            Icons.link_outlined,
            size: 16,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
    return Draggable<String>(
      data: paper.id,
      feedback: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            border: Border.all(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.link_outlined,
                  size: 16,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  'Link ${_displayPaperTitle()}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: handle),
      child: Tooltip(
        message:
            _tooltipLabel(enableToolTips, 'Drag to link note to todo') ?? '',
        child: handle,
      ),
    );
  }

  Widget _animatedPaperBody(
    bool isCollapsed,
    ScriptCapsuleSpec? scriptCapsuleSpec,
  ) {
    final body = isCollapsed
        ? scriptCapsuleSpec == null
            ? const SizedBox.shrink(key: ValueKey('collapsed'))
            : _collapsedScriptCapsule(scriptCapsuleSpec)
        : Column(
            key: const ValueKey('expanded'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              if (paper.isTodo)
                _TodoEditor(
                  paper: paper,
                  notePapers: notePapers,
                  enableTodoNoteLinks: enableTodoNoteLinks,
                  showLinkedNoteName: showLinkedNoteName,
                  allowLongLinkedNoteTitles: allowLongLinkedNoteTitles,
                  runLinkedScriptCapsulesOnClick:
                      runLinkedScriptCapsulesOnClick,
                  maxTitleLength: maxTitleLength,
                  enableToolTips: enableToolTips,
                  visualSize: todoVisualSize,
                  lineSpacing: todoLineSpacing,
                  textZoom: paper.textZoom,
                  showDueRelativeTime: showTodoDueRelativeTime,
                  dueYearDisplayMode: todoDueYearDisplayMode,
                  onOpen: onOpen,
                  onRunScriptCapsule: onRunScriptCapsule,
                  onChanged: onChanged,
                  onItemDeleted: onTodoItemDeleted,
                  onItemRestored: onTodoItemRestored,
                  onReminderReset: onTodoReminderReset,
                )
              else
                _NoteEditor(
                  paper: paper,
                  markdownRenderMode: markdownRenderMode,
                  lineSpacing: noteLineSpacing,
                  textZoom: paper.textZoom,
                  onOpenUri: onOpenUri,
                  onChanged: onChanged,
                ),
            ],
          );
    if (!enableAnimations) {
      return body;
    }
    return AnimatedSwitcher(
      key: ValueKey('${paper.id}-body-animation'),
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          alignment: AlignmentDirectional.topStart,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: body,
    );
  }

  Widget _collapsedScriptCapsule(ScriptCapsuleSpec spec) {
    return Builder(
      key: ValueKey('${paper.id}-script-capsule'),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Tooltip(
            message: _tooltipLabel(
                  enableToolTips,
                  'Run script capsule',
                ) ??
                '',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(onRunScriptCapsule(spec)),
              onSecondaryTap: _openCollapsedScriptCapsuleForEditing,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.primary),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_outlined,
                        size: 18,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Run ${_displayPaperTitle()}',
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _paperHeaderActions({
    required BuildContext context,
    required bool isCollapsed,
    required double textZoom,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return [
        _collapseButton(isCollapsed),
        PopupMenuButton<String>(
          key: ValueKey('${paper.id}-paper-actions'),
          tooltip: _tooltipLabel(enableToolTips, 'Paper actions'),
          icon: const Icon(Icons.more_vert),
          onSelected: _handleCompactPaperAction,
          itemBuilder: (context) => [
            _paperActionMenuItem(
              value: _compactPaperActionOpenSurface,
              icon: Icons.open_in_new,
              label: 'Open surface',
            ),
            if (paper.isNote)
              _paperActionMenuItem(
                value: _compactPaperActionOpenMarkdown,
                icon: Icons.file_open_outlined,
                label: 'Open markdown externally',
              ),
            const PopupMenuDivider(),
            for (final option in _TextZoomOption.values)
              CheckedPopupMenuItem<String>(
                value: '$_compactPaperZoomActionPrefix${option.value}',
                checked: option.value == textZoom,
                child: Text('Zoom ${option.label}'),
              ),
            const PopupMenuDivider(),
            _paperActionMenuItem(
              value: _compactPaperActionToggleAlwaysOnTop,
              icon:
                  paper.alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
              label:
                  paper.alwaysOnTop ? 'Disable always on top' : 'Keep on top',
            ),
            _paperActionMenuItem(
              value: _compactPaperActionTogglePinned,
              icon: paper.isPinnedToDesktop
                  ? Icons.desktop_windows
                  : Icons.desktop_windows_outlined,
              label: paper.isPinnedToDesktop
                  ? 'Unpin from desktop'
                  : 'Pin to desktop',
            ),
            _paperActionMenuItem(
              value: _compactPaperActionCaptureBounds,
              icon: Icons.aspect_ratio_outlined,
              label: 'Save window bounds',
            ),
            const PopupMenuDivider(),
            _paperActionMenuItem(
              value: _compactPaperActionHide,
              icon: Icons.visibility_off_outlined,
              label: 'Hide paper',
            ),
            _paperActionMenuItem(
              value: _compactPaperActionDelete,
              icon: Icons.delete_outline,
              label: 'Delete paper',
            ),
          ],
        ),
      ];
    }
    return [
      IconButton(
        tooltip: _tooltipLabel(enableToolTips, 'Open paper surface'),
        onPressed: () => unawaited(onOpen(paper)),
        icon: const Icon(Icons.open_in_new),
      ),
      if (paper.isNote)
        IconButton(
          tooltip: _tooltipLabel(
            enableToolTips,
            'Open markdown externally',
          ),
          onPressed: () => unawaited(onOpenExternalMarkdown(paper)),
          icon: const Icon(Icons.file_open_outlined),
        ),
      _collapseButton(isCollapsed),
      PopupMenuButton<double>(
        tooltip: _tooltipLabel(enableToolTips, 'Paper text zoom'),
        icon: const Icon(Icons.text_fields),
        initialValue: textZoom,
        onSelected: (value) => _setTextZoom(value),
        itemBuilder: (context) {
          return [
            for (final option in _TextZoomOption.values)
              CheckedPopupMenuItem<double>(
                value: option.value,
                checked: option.value == textZoom,
                child: Text(option.label),
              ),
          ];
        },
      ),
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          paper.alwaysOnTop ? 'Disable always on top' : 'Keep on top',
        ),
        onPressed: _toggleAlwaysOnTop,
        icon:
            Icon(paper.alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(
          enableToolTips,
          paper.isPinnedToDesktop ? 'Unpin from desktop' : 'Pin to desktop',
        ),
        onPressed: _togglePinnedToDesktop,
        icon: Icon(paper.isPinnedToDesktop
            ? Icons.desktop_windows
            : Icons.desktop_windows_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(enableToolTips, 'Save window bounds'),
        onPressed: () => unawaited(onCaptureBounds(paper)),
        icon: const Icon(Icons.aspect_ratio_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(enableToolTips, 'Hide paper'),
        onPressed: () => unawaited(onHide(paper)),
        icon: const Icon(Icons.visibility_off_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(enableToolTips, 'Delete paper'),
        onPressed: () => unawaited(onDelete(paper)),
        icon: const Icon(Icons.delete_outline),
      ),
    ];
  }

  IconButton _collapseButton(bool isCollapsed) {
    return IconButton(
      tooltip: _tooltipLabel(
        enableToolTips,
        collapseAllActive
            ? 'Collapse all is active'
            : paper.isCollapsed
                ? 'Expand paper'
                : 'Collapse paper',
      ),
      onPressed: collapseAllActive ? null : _toggleCollapsed,
      icon: Icon(isCollapsed ? Icons.expand_more : Icons.expand_less),
    );
  }

  PopupMenuItem<String> _paperActionMenuItem({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  void _handleCompactPaperAction(String value) {
    if (value.startsWith(_compactPaperZoomActionPrefix)) {
      _setTextZoom(
        double.parse(value.substring(_compactPaperZoomActionPrefix.length)),
      );
      return;
    }
    switch (value) {
      case _compactPaperActionOpenSurface:
        unawaited(onOpen(paper));
      case _compactPaperActionOpenMarkdown:
        unawaited(onOpenExternalMarkdown(paper));
      case _compactPaperActionToggleAlwaysOnTop:
        _toggleAlwaysOnTop();
      case _compactPaperActionTogglePinned:
        _togglePinnedToDesktop();
      case _compactPaperActionCaptureBounds:
        unawaited(onCaptureBounds(paper));
      case _compactPaperActionHide:
        unawaited(onHide(paper));
      case _compactPaperActionDelete:
        unawaited(onDelete(paper));
    }
  }

  void _toggleCollapsed() {
    paper.isCollapsed = !paper.isCollapsed;
    unawaited(onChanged());
  }

  void _openCollapsedScriptCapsuleForEditing() {
    if (!paper.isCollapsed) {
      return;
    }
    paper.isCollapsed = false;
    unawaited(onChanged());
  }

  void _toggleAlwaysOnTop() {
    onSetAlwaysOnTop(paper, !paper.alwaysOnTop);
    unawaited(onSurfaceChanged(paper));
    unawaited(onChanged());
  }

  void _togglePinnedToDesktop() {
    onSetPinnedToDesktop(paper, !paper.isPinnedToDesktop);
    unawaited(onSurfaceChanged(paper));
    unawaited(onChanged());
  }

  void _setTextZoom(double value) {
    paper.textZoom = value.clamp(0.5, 1.5).toDouble();
    unawaited(onSurfaceChanged(paper));
    unawaited(onChanged());
  }

  String _displayPaperTitle() {
    return titleText;
  }
}

class _TextZoomOption {
  const _TextZoomOption(this.value, this.label);

  final double value;
  final String label;

  static const values = [
    _TextZoomOption(0.75, '75%'),
    _TextZoomOption(1, '100%'),
    _TextZoomOption(1.25, '125%'),
    _TextZoomOption(1.5, '150%'),
  ];
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    required this.paper,
    required this.markdownRenderMode,
    required this.lineSpacing,
    required this.textZoom,
    required this.onOpenUri,
    required this.onChanged,
  });

  final PaperData paper;
  final String markdownRenderMode;
  final double lineSpacing;
  final double textZoom;
  final Future<void> Function(String uri) onOpenUri;
  final Future<void> Function() onChanged;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  static const _viewEdit = 'edit';
  static const _viewPreview = 'preview';
  static const _viewSplit = 'split';
  static const _markdownActionStrikethrough = 'strikethrough';
  static const _markdownActionHeading = 'heading';
  static const _markdownActionQuote = 'quote';
  static const _markdownActionList = 'list';
  static const _markdownActionCodeBlock = 'code-block';

  late final TextEditingController _contentController;
  late final FocusNode _contentFocusNode;
  late String _view = _defaultView(widget.markdownRenderMode, widget.paper);
  bool _toolbarInteractionActive = false;
  String? _selectedCanvasElementId;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.paper.content);
    _contentFocusNode = FocusNode();
    _contentFocusNode.addListener(_handleEditorFocusChange);
  }

  @override
  void didUpdateWidget(covariant _NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdownRenderMode != widget.markdownRenderMode) {
      _view = _defaultView(widget.markdownRenderMode, widget.paper);
    }
    if (oldWidget.paper.id != widget.paper.id ||
        widget.paper.content != _contentController.text) {
      final offset = _contentController.selection.baseOffset
          .clamp(0, widget.paper.content.length)
          .toInt();
      _contentController.value = TextEditingValue(
        text: widget.paper.content,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
    if (_selectedCanvasElementId != null &&
        !widget.paper.noteCanvasElements.any(
          (element) => element.id == _selectedCanvasElementId,
        )) {
      _selectedCanvasElementId = null;
    }
  }

  @override
  void dispose() {
    _contentFocusNode.removeListener(_handleEditorFocusChange);
    _contentFocusNode.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    if (mode == MarkdownRenderModes.off) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _editor(context, minLines: 4, maxLines: 12),
          const SizedBox(height: 12),
          _canvasSection(),
          const SizedBox(height: 8),
          _noteStatusBar(context, _viewEdit),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<String>(
            segments: [
              const ButtonSegment(
                value: _viewEdit,
                icon: Icon(Icons.edit_outlined),
                label: Text('Edit'),
              ),
              const ButtonSegment(
                value: _viewPreview,
                icon: Icon(Icons.visibility_outlined),
                label: Text('Preview'),
              ),
              if (mode == MarkdownRenderModes.enhanced)
                const ButtonSegment(
                  value: _viewSplit,
                  icon: Icon(Icons.vertical_split_outlined),
                  label: Text('Split'),
                ),
            ],
            selected: {_safeView(mode)},
            onSelectionChanged: (selection) =>
                setState(() => _view = selection.single),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final view = _safeView(mode);
            final canSplit = constraints.maxWidth >= 640;
            if (view == _viewPreview) {
              return _preview(context);
            }
            if (view == _viewSplit && canSplit) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _editor(context, minLines: 8, maxLines: 18)),
                  const SizedBox(width: 12),
                  Expanded(child: _preview(context)),
                ],
              );
            }
            return _editor(context, minLines: 4, maxLines: 12);
          },
        ),
        if (widget.paper.noteCanvasElements.isNotEmpty) ...[
          const SizedBox(height: 12),
          _canvasPreview(),
        ],
        const SizedBox(height: 12),
        _addCanvasButton(),
        const SizedBox(height: 8),
        _noteStatusBar(context, _safeView(mode)),
      ],
    );
  }

  Widget _editor(
    BuildContext context, {
    required int minLines,
    required int maxLines,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _markdownToolbar(context),
        const SizedBox(height: 8),
        Focus(
          onKeyEvent: _handleMarkdownKeyEvent,
          child: TextFormField(
            key: ValueKey('${widget.paper.id}-content'),
            controller: _contentController,
            focusNode: _contentFocusNode,
            onTapAlwaysCalled: true,
            onTap: () => _handleEditorTap(context),
            minLines: minLines,
            maxLines: maxLines,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Write a note...',
            ),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.apply(
                  fontSizeFactor: widget.textZoom,
                )
                .copyWith(height: widget.lineSpacing),
            inputFormatters: const [
              _MarkdownPasteTextInputFormatter(),
              _MarkdownListContinuationTextInputFormatter(),
            ],
            onChanged: _commitContent,
          ),
        ),
      ],
    );
  }

  Widget _markdownToolbar(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Listener(
      onPointerDown: (_) => _beginToolbarInteraction(),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _formatButton(
            tooltip: 'Bold (Ctrl+B)',
            icon: Icons.format_bold,
            onPressed: _formatBold,
          ),
          _formatButton(
            tooltip: 'Italic (Ctrl+I)',
            icon: Icons.format_italic,
            onPressed: _formatItalic,
          ),
          if (!compact) ...[
            _formatButton(
              tooltip: 'Strikethrough',
              icon: Icons.strikethrough_s,
              onPressed: _formatStrikethrough,
            ),
            _formatButton(
              tooltip: 'Heading',
              icon: Icons.title,
              onPressed: _formatHeading,
            ),
            _formatButton(
              tooltip: 'Quote',
              icon: Icons.format_quote,
              onPressed: _formatQuote,
            ),
            _formatButton(
              tooltip: 'List',
              icon: Icons.format_list_bulleted,
              onPressed: _formatList,
            ),
            _formatButton(
              tooltip: 'Code block',
              icon: Icons.code,
              onPressed: _formatCodeBlock,
            ),
          ],
          _formatButton(
            tooltip: 'Insert link (Ctrl+K)',
            icon: Icons.link,
            onPressed: _insertMarkdownLink,
          ),
          if (compact) _compactMarkdownActions(),
        ],
      ),
    );
  }

  Widget _formatButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton.outlined(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  Widget _compactMarkdownActions() {
    return PopupMenuButton<String>(
      key: const ValueKey('compact-markdown-toolbar-actions'),
      tooltip: 'More markdown actions',
      icon: const Icon(Icons.more_vert),
      onOpened: _beginToolbarInteraction,
      onCanceled: _endToolbarInteraction,
      onSelected: (value) {
        _handleCompactMarkdownAction(value);
        _endToolbarInteraction();
      },
      itemBuilder: (context) => [
        _markdownMenuItem(
          value: _markdownActionStrikethrough,
          icon: Icons.strikethrough_s,
          label: 'Strikethrough',
        ),
        _markdownMenuItem(
          value: _markdownActionHeading,
          icon: Icons.title,
          label: 'Heading',
        ),
        _markdownMenuItem(
          value: _markdownActionQuote,
          icon: Icons.format_quote,
          label: 'Quote',
        ),
        _markdownMenuItem(
          value: _markdownActionList,
          icon: Icons.format_list_bulleted,
          label: 'List',
        ),
        _markdownMenuItem(
          value: _markdownActionCodeBlock,
          icon: Icons.code,
          label: 'Code block',
        ),
      ],
    );
  }

  PopupMenuItem<String> _markdownMenuItem({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  void _formatBold() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.wrapSelection(value, '**', '**'),
    );
  }

  void _formatItalic() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.wrapSelection(value, '*', '*'),
    );
  }

  void _insertMarkdownLink() {
    _applyMarkdownFormat(MarkdownFormatting.insertMarkdownLink);
  }

  void _formatStrikethrough() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.wrapSelection(value, '~~', '~~'),
    );
  }

  void _formatHeading() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.insertLinePrefix(value, '# '),
    );
  }

  void _formatQuote() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.insertLinePrefix(value, '> '),
    );
  }

  void _formatList() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.insertLinePrefix(value, '- '),
    );
  }

  void _formatCodeBlock() {
    _applyMarkdownFormat(
      (value) => MarkdownFormatting.wrapSelection(
        value,
        '```\n',
        '\n```',
      ),
    );
  }

  void _handleCompactMarkdownAction(String value) {
    switch (value) {
      case _markdownActionStrikethrough:
        _formatStrikethrough();
      case _markdownActionHeading:
        _formatHeading();
      case _markdownActionQuote:
        _formatQuote();
      case _markdownActionList:
        _formatList();
      case _markdownActionCodeBlock:
        _formatCodeBlock();
    }
  }

  void _beginToolbarInteraction() {
    _toolbarInteractionActive = true;
  }

  void _endToolbarInteraction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _toolbarInteractionActive = false;
      _handleEditorFocusChange();
    });
  }

  KeyEventResult _handleMarkdownKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyB) {
      _formatBold();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyI) {
      _formatItalic();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyK) {
      _insertMarkdownLink();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleEditorTap(BuildContext context) {
    if (!HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final selection = _contentController.selection;
      if (!selection.isValid) {
        return;
      }
      final offset = selection.extentOffset;
      final href = MarkdownLinks.hrefAt(_contentController.text, offset);
      if (href == null) {
        return;
      }
      _openMarkdownLink(context, href);
    });
  }

  void _handleEditorFocusChange() {
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    if (_contentFocusNode.hasFocus ||
        _toolbarInteractionActive ||
        mode == MarkdownRenderModes.off ||
        _safeView(mode) != _viewEdit) {
      return;
    }
    setState(() => _view = _viewPreview);
  }

  void _applyMarkdownFormat(
    TextEditingValue Function(TextEditingValue value) format,
  ) {
    _contentController.value = format(_contentController.value);
    _commitContent(_contentController.text);
    _contentFocusNode.requestFocus();
  }

  void _commitContent(String value) {
    if (widget.paper.content == value) {
      return;
    }
    setState(() {
      widget.paper.content = value;
    });
    unawaited(widget.onChanged());
  }

  Widget _noteStatusBar(BuildContext context, String view) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        );
    return DecoratedBox(
      key: const ValueKey('note-status-bar'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  _noteViewLabel(view),
                  key: const ValueKey('note-status-mode'),
                  style: textStyle?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _noteStatsText(),
                key: const ValueKey('note-status-stats'),
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
            Text(
              '${(widget.textZoom * 100).round()}%',
              key: const ValueKey('note-status-zoom'),
              style: textStyle,
            ),
          ],
        ),
      ),
    );
  }

  String _noteStatsText() {
    final characterCount = _countNoteTextCharacters(widget.paper.content);
    final lineCount = _countNoteLines(widget.paper.content);
    final elementCount = widget.paper.noteCanvasElements.length;
    return [
      '$characterCount ${characterCount == 1 ? 'char' : 'chars'}',
      '$lineCount ${lineCount == 1 ? 'line' : 'lines'}',
      '$elementCount ${elementCount == 1 ? 'element' : 'elements'}',
    ].join(' | ');
  }

  int _countNoteTextCharacters(String text) {
    return text.runes.where((rune) {
      final character = String.fromCharCode(rune);
      return rune >= 32 && rune != 127 && character.trim().isNotEmpty;
    }).length;
  }

  int _countNoteLines(String text) {
    if (text.isEmpty) {
      return 1;
    }
    return '\n'.allMatches(text).length + 1;
  }

  String _noteViewLabel(String view) {
    return switch (view) {
      _viewPreview => 'Preview',
      _viewSplit => 'Split',
      _ => 'Edit',
    };
  }

  Widget _preview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey('${widget.paper.id}-preview'),
      behavior: HitTestBehavior.opaque,
      onTap: _enterEditorFromPreview,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 112),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: MarkdownBody(
              data: widget.paper.content.trim().isEmpty
                  ? '_No note content._'
                  : widget.paper.content,
              onTapLink: (text, href, title) =>
                  _openMarkdownLink(context, href),
              styleSheet:
                  MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.apply(
                      fontSizeFactor: widget.textZoom,
                    )
                    .copyWith(height: widget.lineSpacing),
              ),
              selectable: true,
            ),
          ),
        ),
      ),
    );
  }

  void _enterEditorFromPreview() {
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    if (mode == MarkdownRenderModes.off) {
      return;
    }
    setState(() => _view = _viewEdit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _contentFocusNode.requestFocus();
    });
  }

  void _openMarkdownLink(BuildContext context, String? href) {
    final uri = href?.trim();
    if (uri == null || uri.isEmpty) {
      return;
    }
    unawaited(
      widget.onOpenUri(uri).catchError((Object error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Open link failed: ${_readableFailureMessage(error)}',
            ),
          ),
        );
      }),
    );
  }

  String _safeView(String mode) {
    if (_view == _viewSplit && mode != MarkdownRenderModes.enhanced) {
      return _viewEdit;
    }
    return _view;
  }

  String _defaultView(String mode, PaperData paper) {
    if (ScriptCapsuleSpec.tryParse(paper.content) != null) {
      return _viewEdit;
    }
    return MarkdownRenderModes.normalize(mode) == MarkdownRenderModes.off
        ? _viewEdit
        : _viewPreview;
  }

  Widget _canvasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.paper.noteCanvasElements.isNotEmpty) ...[
          _canvasPreview(),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: _addCanvasButton(),
        ),
      ],
    );
  }

  Widget _canvasPreview() {
    return _NoteCanvasPreview(
      elements: widget.paper.noteCanvasElements,
      selectedElementId: _selectedCanvasElementId,
      textZoom: widget.textZoom,
      onChanged: widget.onChanged,
      onGeometryChanging: _refreshCanvasGeometry,
      onSelect: _selectCanvasElement,
      onEdit: _editCanvasElement,
      onDuplicate: _duplicateCanvasElement,
      onLayerAction: _applyCanvasLayerAction,
      onDelete: _deleteCanvasElement,
    );
  }

  void _refreshCanvasGeometry() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Widget _addCanvasButton() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton.icon(
          onPressed: () => _addCanvasElement(NoteCanvasElementTypes.code),
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Add canvas block'),
        ),
        TextButton.icon(
          onPressed: () => _addCanvasElement(NoteCanvasElementTypes.text),
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Add text block'),
        ),
      ],
    );
  }

  void _addCanvasElement(String type) {
    final elements = widget.paper.noteCanvasElements;
    final normalizedType = NoteCanvasElementTypes.normalize(type);
    final nextIndex = elements.length + 1;
    final width = _defaultNoteCanvasElementWidth(normalizedType);
    final height = _defaultNoteCanvasElementHeight(normalizedType);
    final point = _nextNoteCanvasElementPoint(width, height, elements.length);
    final maxLayer = _maxCanvasElementLayer(elements);
    setState(() {
      final elementId = _newCanvasElementId();
      elements.add(
        NoteCanvasElement(
          id: elementId,
          type: normalizedType,
          text: _defaultNoteCanvasElementText(normalizedType, nextIndex),
          x: point.dx,
          y: point.dy,
          width: width,
          height: height,
          zIndex: maxLayer + 10,
        ),
      );
      _selectedCanvasElementId = elementId;
    });
    unawaited(widget.onChanged());
  }

  void _selectCanvasElement(NoteCanvasElement element) {
    if (_selectedCanvasElementId == element.id) {
      return;
    }
    setState(() => _selectedCanvasElementId = element.id);
  }

  void _duplicateCanvasElement(NoteCanvasElement element) {
    final elements = widget.paper.noteCanvasElements;
    final maxLayer = _maxCanvasElementLayer(elements);
    final duplicate = element.copyWith(
      id: _newCanvasElementId(),
      x: element.x + 18,
      y: element.y + 18,
      zIndex: maxLayer + 10,
    )..normalize();
    setState(() {
      elements.add(duplicate);
      _selectedCanvasElementId = duplicate.id;
    });
    unawaited(widget.onChanged());
  }

  void _applyCanvasLayerAction(
    NoteCanvasElement element,
    _CanvasLayerAction action,
  ) {
    final elements = widget.paper.noteCanvasElements;
    final orderedElements = [...elements]..sort((a, b) {
        final byLayer = a.zIndex.compareTo(b.zIndex);
        return byLayer != 0 ? byLayer : a.id.compareTo(b.id);
      });
    final elementIndex = orderedElements.indexWhere(
      (candidate) => candidate.id == element.id,
    );
    if (elementIndex < 0) {
      return;
    }
    final minLayer = _minCanvasElementLayer(elements);
    final maxLayer = _maxCanvasElementLayer(elements);
    var didChange = false;
    setState(() {
      switch (action) {
        case _CanvasLayerAction.bringForward:
          if (elementIndex < orderedElements.length - 1) {
            final nextElement = orderedElements[elementIndex + 1];
            final currentLayer = element.zIndex;
            element.zIndex = nextElement.zIndex;
            nextElement.zIndex = currentLayer;
            didChange = true;
          }
          break;
        case _CanvasLayerAction.sendBackward:
          if (elementIndex > 0) {
            final previousElement = orderedElements[elementIndex - 1];
            final currentLayer = element.zIndex;
            element.zIndex = previousElement.zIndex;
            previousElement.zIndex = currentLayer;
            didChange = true;
          }
          break;
        case _CanvasLayerAction.bringToFront:
          element.zIndex = maxLayer + 10;
          didChange = true;
          break;
        case _CanvasLayerAction.sendToBack:
          element.zIndex = minLayer - 10;
          didChange = true;
          break;
      }
      if (didChange) {
        _selectedCanvasElementId = element.id;
      }
    });
    if (didChange) {
      unawaited(widget.onChanged());
    }
  }

  void _deleteCanvasElement(NoteCanvasElement element) {
    setState(() {
      widget.paper.noteCanvasElements.removeWhere(
        (candidate) => candidate.id == element.id,
      );
      if (_selectedCanvasElementId == element.id) {
        _selectedCanvasElementId = null;
      }
    });
    unawaited(widget.onChanged());
  }

  Future<void> _editCanvasElement(NoteCanvasElement element) async {
    final result = await showDialog<_CanvasGeometry>(
      context: context,
      builder: (context) => _CanvasGeometryDialog(element: element),
    );
    if (result == null) {
      return;
    }
    setState(() {
      element
        ..type = result.type
        ..x = result.x
        ..y = result.y
        ..width = result.width
        ..height = result.height
        ..zIndex = result.zIndex;
      element.normalize();
    });
    await widget.onChanged();
  }

  String _newCanvasElementId() {
    final existingIds =
        widget.paper.noteCanvasElements.map((element) => element.id).toSet();
    var id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    var suffix = 1;
    while (existingIds.contains(id)) {
      id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$suffix';
      suffix += 1;
    }
    return id;
  }

  Offset _nextNoteCanvasElementPoint(
    double width,
    double height,
    int existingCount,
  ) {
    final layerWidth = math.max(220.0, widget.paper.width - 40);
    final layerHeight = math.max(160.0, widget.paper.height - 90);
    final offset = math.min(80.0, existingCount * 12.0);
    final x = math.max(
      10.0,
      math.min(layerWidth - width - 10.0, 28.0 + offset),
    );
    final y = math.max(
      10.0,
      math.min(layerHeight - height - 10.0, 28.0 + offset),
    );
    return Offset(x, y);
  }

  int _maxCanvasElementLayer(List<NoteCanvasElement> elements) {
    if (elements.isEmpty) {
      return 0;
    }
    return elements
        .map((element) => element.zIndex)
        .reduce((max, zIndex) => zIndex > max ? zIndex : max);
  }

  int _minCanvasElementLayer(List<NoteCanvasElement> elements) {
    if (elements.isEmpty) {
      return 0;
    }
    return elements
        .map((element) => element.zIndex)
        .reduce((min, zIndex) => zIndex < min ? zIndex : min);
  }

  double _defaultNoteCanvasElementWidth(String type) {
    return switch (type) {
      NoteCanvasElementTypes.text => 230,
      _ => 230,
    };
  }

  double _defaultNoteCanvasElementHeight(String type) {
    return switch (type) {
      NoteCanvasElementTypes.text => 116,
      _ => 116,
    };
  }

  String _defaultNoteCanvasElementText(String type, int index) {
    if (type == NoteCanvasElementTypes.text) {
      return 'Canvas text $index';
    }
    return 'Console.WriteLine("PaperTodo");';
  }
}

class _NoteCanvasPreview extends StatelessWidget {
  const _NoteCanvasPreview({
    required this.elements,
    required this.selectedElementId,
    required this.textZoom,
    required this.onChanged,
    required this.onGeometryChanging,
    required this.onSelect,
    required this.onEdit,
    required this.onDuplicate,
    required this.onLayerAction,
    required this.onDelete,
  });

  final List<NoteCanvasElement> elements;
  final String? selectedElementId;
  final double textZoom;
  final Future<void> Function() onChanged;
  final VoidCallback onGeometryChanging;
  final void Function(NoteCanvasElement element) onSelect;
  final Future<void> Function(NoteCanvasElement element) onEdit;
  final void Function(NoteCanvasElement element) onDuplicate;
  final void Function(NoteCanvasElement element, _CanvasLayerAction action)
      onLayerAction;
  final void Function(NoteCanvasElement element) onDelete;

  @override
  Widget build(BuildContext context) {
    final sortedElements = [...elements]..sort((a, b) {
        final byLayer = a.zIndex.compareTo(b.zIndex);
        return byLayer != 0 ? byLayer : a.id.compareTo(b.id);
      });
    final contentWidth = _contentWidth(sortedElements);
    final contentHeight = _contentHeight(sortedElements);
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('note-canvas-preview'),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : contentWidth;
          final scale = (maxWidth / contentWidth).clamp(0.2, 1.0).toDouble();
          final visualHeight =
              (contentHeight * scale).clamp(120, 640).toDouble();
          final canvasWidth = maxWidth / scale;
          final canvasHeight = visualHeight / scale;
          return SizedBox(
            height: visualHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: colorScheme.surfaceContainerLowest,
                  ),
                ),
                for (var index = 0; index < sortedElements.length; index++)
                  Positioned(
                    left: sortedElements[index].x * scale,
                    top: sortedElements[index].y * scale,
                    width: sortedElements[index].width * scale,
                    height: sortedElements[index].height * scale,
                    child: _NoteCanvasElementPreview(
                      key: ValueKey(
                        'note-canvas-element-${sortedElements[index].id}',
                      ),
                      element: sortedElements[index],
                      layerRank: index + 1,
                      layerCount: sortedElements.length,
                      isSelected: sortedElements[index].id == selectedElementId,
                      scale: scale,
                      canvasWidth: canvasWidth,
                      canvasHeight: canvasHeight,
                      textZoom: textZoom,
                      onChanged: onChanged,
                      onGeometryChanging: onGeometryChanging,
                      onSelect: onSelect,
                      onEdit: onEdit,
                      onDuplicate: onDuplicate,
                      onLayerAction: onLayerAction,
                      onDelete: onDelete,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  double _contentWidth(List<NoteCanvasElement> elements) {
    return elements
        .map((element) => element.x + element.width)
        .fold<double>(320, (max, value) => value > max ? value : max);
  }

  double _contentHeight(List<NoteCanvasElement> elements) {
    return elements
        .map((element) => element.y + element.height)
        .fold<double>(160, (max, value) => value > max ? value : max);
  }
}

class _NoteCanvasElementPreview extends StatefulWidget {
  const _NoteCanvasElementPreview({
    required this.element,
    required this.layerRank,
    required this.layerCount,
    required this.isSelected,
    required this.scale,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.textZoom,
    required this.onChanged,
    required this.onGeometryChanging,
    required this.onSelect,
    required this.onEdit,
    required this.onDuplicate,
    required this.onLayerAction,
    required this.onDelete,
    super.key,
  });

  final NoteCanvasElement element;
  final int layerRank;
  final int layerCount;
  final bool isSelected;
  final double scale;
  final double canvasWidth;
  final double canvasHeight;
  final double textZoom;
  final Future<void> Function() onChanged;
  final VoidCallback onGeometryChanging;
  final void Function(NoteCanvasElement element) onSelect;
  final Future<void> Function(NoteCanvasElement element) onEdit;
  final void Function(NoteCanvasElement element) onDuplicate;
  final void Function(NoteCanvasElement element, _CanvasLayerAction action)
      onLayerAction;
  final void Function(NoteCanvasElement element) onDelete;

  @override
  State<_NoteCanvasElementPreview> createState() =>
      _NoteCanvasElementPreviewState();
}

class _NoteCanvasElementPreviewState extends State<_NoteCanvasElementPreview> {
  static const _compactCanvasActionEdit = 'edit';
  static const _compactCanvasActionDuplicate = 'duplicate';
  static const _compactCanvasActionBringToFront = 'bring-to-front';
  static const _compactCanvasActionBringForward = 'bring-forward';
  static const _compactCanvasActionSendBackward = 'send-backward';
  static const _compactCanvasActionSendToBack = 'send-to-back';
  static const _compactCanvasActionDelete = 'delete';

  bool _geometryChanged = false;
  int? _geometryPointer;
  _CanvasGeometryDragMode? _geometryDragMode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final element = widget.element;
    final isCode = element.type == NoteCanvasElementTypes.code;
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.apply(fontSizeFactor: widget.textZoom)
        .copyWith(fontFamily: isCode ? 'monospace' : null);
    final typeLabel = _noteCanvasElementTypeLabel(element.type);
    final layerLabel = _noteCanvasLayerLabel(
      widget.layerRank,
      widget.layerCount,
    );
    final showInlineActions = element.width * widget.scale >= 168;
    final compactContent = element.width * widget.scale < 120 ||
        element.height * widget.scale < 72;
    final elementPadding =
        compactContent ? 4.0 : (8 * widget.scale).clamp(4, 8).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border.all(
          color: widget.isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant,
          width: widget.isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: widget.isSelected
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.18),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Padding(
            padding: EdgeInsets.all(elementPadding),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: 'Drag canvas block',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.move,
                          child: Listener(
                            key: ValueKey(
                              'note-canvas-drag-handle-${element.id}',
                            ),
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) => _beginGeometryGesture(
                              event,
                              _CanvasGeometryDragMode.move,
                            ),
                            onPointerMove: _updateGeometryGesture,
                            onPointerUp: _endGeometryGesture,
                            onPointerCancel: _endGeometryGesture,
                            child: compactContent
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: Icon(
                                      Icons.open_with,
                                      size: (16 * widget.scale)
                                          .clamp(12, 16)
                                          .toDouble(),
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : Wrap(
                                    spacing: (6 * widget.scale)
                                        .clamp(3, 6)
                                        .toDouble(),
                                    runSpacing: (4 * widget.scale)
                                        .clamp(2, 4)
                                        .toDouble(),
                                    children: [
                                      _NoteCanvasElementBadge(
                                        label: typeLabel,
                                        scale: widget.scale,
                                        color: colorScheme.primaryContainer,
                                        foregroundColor:
                                            colorScheme.onPrimaryContainer,
                                      ),
                                      _NoteCanvasElementBadge(
                                        label: layerLabel,
                                        scale: widget.scale,
                                        color: colorScheme.secondaryContainer,
                                        foregroundColor:
                                            colorScheme.onSecondaryContainer,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (showInlineActions) ...[
                      SizedBox.square(
                        dimension: (28 * widget.scale).clamp(24, 28).toDouble(),
                        child: IconButton(
                          tooltip: 'Edit canvas geometry',
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: Size.zero,
                          ),
                          onPressed: () {
                            widget.onSelect(element);
                            unawaited(widget.onEdit(element));
                          },
                          iconSize:
                              (18 * widget.scale).clamp(16, 18).toDouble(),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.tune_outlined),
                        ),
                      ),
                      SizedBox.square(
                        dimension: (28 * widget.scale).clamp(24, 28).toDouble(),
                        child: IconButton(
                          tooltip: 'Duplicate canvas block',
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: Size.zero,
                          ),
                          onPressed: () {
                            widget.onSelect(element);
                            widget.onDuplicate(element);
                          },
                          iconSize:
                              (18 * widget.scale).clamp(16, 18).toDouble(),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.content_copy_outlined),
                        ),
                      ),
                      SizedBox.square(
                        dimension: (28 * widget.scale).clamp(24, 28).toDouble(),
                        child: PopupMenuButton<_CanvasLayerAction>(
                          key: ValueKey(
                            'note-canvas-layer-actions-${element.id}',
                          ),
                          tooltip: 'Canvas layer actions',
                          child: Center(
                            child: Icon(
                              Icons.layers_outlined,
                              size:
                                  (18 * widget.scale).clamp(16, 18).toDouble(),
                            ),
                          ),
                          onSelected: (action) {
                            widget.onSelect(element);
                            widget.onLayerAction(element, action);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _CanvasLayerAction.bringToFront,
                              child: Text('Bring to front'),
                            ),
                            PopupMenuItem(
                              value: _CanvasLayerAction.bringForward,
                              child: Text('Bring forward'),
                            ),
                            PopupMenuItem(
                              value: _CanvasLayerAction.sendBackward,
                              child: Text('Send backward'),
                            ),
                            PopupMenuItem(
                              value: _CanvasLayerAction.sendToBack,
                              child: Text('Send to back'),
                            ),
                          ],
                        ),
                      ),
                      SizedBox.square(
                        dimension: (28 * widget.scale).clamp(24, 28).toDouble(),
                        child: IconButton(
                          tooltip: 'Delete canvas block',
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: Size.zero,
                          ),
                          onPressed: () {
                            widget.onSelect(element);
                            widget.onDelete(element);
                          },
                          iconSize:
                              (18 * widget.scale).clamp(16, 18).toDouble(),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close_outlined),
                        ),
                      ),
                    ] else
                      SizedBox.square(
                        dimension: (28 * widget.scale).clamp(24, 28).toDouble(),
                        child: PopupMenuButton<String>(
                          key: ValueKey(
                            'note-canvas-compact-actions-${element.id}',
                          ),
                          tooltip: 'Canvas block actions',
                          child: Center(
                            child: Icon(
                              Icons.more_vert,
                              size:
                                  (18 * widget.scale).clamp(16, 18).toDouble(),
                            ),
                          ),
                          onSelected: _handleCompactCanvasAction,
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _compactCanvasActionEdit,
                              child: Text('Edit geometry'),
                            ),
                            PopupMenuItem(
                              value: _compactCanvasActionDuplicate,
                              child: Text('Duplicate'),
                            ),
                            PopupMenuDivider(),
                            PopupMenuItem(
                              value: _compactCanvasActionBringToFront,
                              child: Text('Bring to front'),
                            ),
                            PopupMenuItem(
                              value: _compactCanvasActionBringForward,
                              child: Text('Bring forward'),
                            ),
                            PopupMenuItem(
                              value: _compactCanvasActionSendBackward,
                              child: Text('Send backward'),
                            ),
                            PopupMenuItem(
                              value: _compactCanvasActionSendToBack,
                              child: Text('Send to back'),
                            ),
                            PopupMenuDivider(),
                            PopupMenuItem(
                              value: _compactCanvasActionDelete,
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: compactContent
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onSelect(element),
                          child: ClipRect(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                element.text,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: style?.copyWith(
                                  color: colorScheme.onSurface,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ),
                        )
                      : TextFormField(
                          key: ValueKey(
                            'note-canvas-element-text-${element.id}',
                          ),
                          initialValue: element.text,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: style?.copyWith(
                            color: colorScheme.onSurface,
                            height: 1.35,
                          ),
                          onTap: () => widget.onSelect(element),
                          onChanged: (value) {
                            element.text = value;
                            unawaited(widget.onChanged());
                          },
                        ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 3,
            bottom: 3,
            child: Tooltip(
              message: 'Resize canvas block',
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: Listener(
                  key: ValueKey('note-canvas-resize-handle-${element.id}'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _beginGeometryGesture(
                    event,
                    _CanvasGeometryDragMode.resize,
                  ),
                  onPointerMove: _updateGeometryGesture,
                  onPointerUp: _endGeometryGesture,
                  onPointerCancel: _endGeometryGesture,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SizedBox.square(
                      dimension: (16 * widget.scale).clamp(14, 18).toDouble(),
                      child: Icon(
                        Icons.open_in_full,
                        size: (11 * widget.scale).clamp(9, 11).toDouble(),
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _beginGeometryGesture(
    PointerDownEvent event,
    _CanvasGeometryDragMode mode,
  ) {
    if (_geometryPointer != null) {
      return;
    }
    _geometryPointer = event.pointer;
    _geometryDragMode = mode;
    _geometryChanged = false;
    widget.onSelect(widget.element);
  }

  void _handleCompactCanvasAction(String action) {
    final element = widget.element;
    widget.onSelect(element);
    switch (action) {
      case _compactCanvasActionEdit:
        unawaited(widget.onEdit(element));
      case _compactCanvasActionDuplicate:
        widget.onDuplicate(element);
      case _compactCanvasActionBringToFront:
        widget.onLayerAction(element, _CanvasLayerAction.bringToFront);
      case _compactCanvasActionBringForward:
        widget.onLayerAction(element, _CanvasLayerAction.bringForward);
      case _compactCanvasActionSendBackward:
        widget.onLayerAction(element, _CanvasLayerAction.sendBackward);
      case _compactCanvasActionSendToBack:
        widget.onLayerAction(element, _CanvasLayerAction.sendToBack);
      case _compactCanvasActionDelete:
        widget.onDelete(element);
    }
  }

  void _updateGeometryGesture(PointerMoveEvent event) {
    if (event.pointer != _geometryPointer) {
      return;
    }
    switch (_geometryDragMode) {
      case _CanvasGeometryDragMode.move:
        _moveElement(event.delta);
      case _CanvasGeometryDragMode.resize:
        _resizeElement(event.delta);
      case null:
        break;
    }
  }

  void _moveElement(Offset delta) {
    final element = widget.element;
    final dx = delta.dx / widget.scale;
    final dy = delta.dy / widget.scale;
    final maxX = (widget.canvasWidth - element.width).clamp(0, double.infinity);
    final maxY =
        (widget.canvasHeight - element.height).clamp(0, double.infinity);
    element.x = _roundCanvasValue((element.x + dx).clamp(0, maxX).toDouble());
    element.y = _roundCanvasValue((element.y + dy).clamp(0, maxY).toDouble());
    _geometryChanged = true;
    widget.onGeometryChanging();
  }

  void _resizeElement(Offset delta) {
    final element = widget.element;
    final dx = delta.dx / widget.scale;
    final dy = delta.dy / widget.scale;
    final maxWidth =
        (widget.canvasWidth - element.x).clamp(72, double.infinity);
    final maxHeight =
        (widget.canvasHeight - element.y).clamp(48, double.infinity);
    element.width =
        _roundCanvasValue((element.width + dx).clamp(72, maxWidth).toDouble());
    element.height = _roundCanvasValue(
        (element.height + dy).clamp(48, maxHeight).toDouble());
    _geometryChanged = true;
    widget.onGeometryChanging();
  }

  void _endGeometryGesture(PointerEvent event) {
    if (event.pointer != _geometryPointer) {
      return;
    }
    _geometryPointer = null;
    _geometryDragMode = null;
    if (!_geometryChanged) {
      return;
    }
    _geometryChanged = false;
    unawaited(widget.onChanged());
  }

  double _roundCanvasValue(double value) => (value * 10).roundToDouble() / 10;
}

enum _CanvasGeometryDragMode {
  move,
  resize,
}

class _NoteCanvasElementBadge extends StatelessWidget {
  const _NoteCanvasElementBadge({
    required this.label,
    required this.scale,
    required this.color,
    required this.foregroundColor,
  });

  final String label;
  final double scale;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: (6 * scale).clamp(4, 6).toDouble(),
          vertical: (3 * scale).clamp(2, 3).toDouble(),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
        ),
      ),
    );
  }
}

String _noteCanvasElementTypeLabel(String type) {
  return switch (type) {
    NoteCanvasElementTypes.text => 'TEXT',
    NoteCanvasElementTypes.code => 'CODE',
    _ => type.trim().isEmpty ? 'BLOCK' : type.trim().toUpperCase(),
  };
}

String _noteCanvasLayerLabel(int layerRank, int layerCount) {
  if (layerCount > 1 && layerRank == layerCount) {
    return 'Top $layerRank';
  }
  return 'Layer $layerRank';
}

enum _CanvasLayerAction {
  bringForward,
  sendBackward,
  bringToFront,
  sendToBack,
}

class _CanvasGeometry {
  const _CanvasGeometry({
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.zIndex,
  });

  final String type;
  final double x;
  final double y;
  final double width;
  final double height;
  final int zIndex;
}

class _CanvasGeometryDialog extends StatefulWidget {
  const _CanvasGeometryDialog({
    required this.element,
  });

  final NoteCanvasElement element;

  @override
  State<_CanvasGeometryDialog> createState() => _CanvasGeometryDialogState();
}

class _CanvasGeometryDialogState extends State<_CanvasGeometryDialog> {
  late final TextEditingController _xController;
  late final TextEditingController _yController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _layerController;
  late String _type;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _type = NoteCanvasElementTypes.normalize(widget.element.type);
    _xController = TextEditingController(text: _format(widget.element.x));
    _yController = TextEditingController(text: _format(widget.element.y));
    _widthController =
        TextEditingController(text: _format(widget.element.width));
    _heightController =
        TextEditingController(text: _format(widget.element.height));
    _layerController =
        TextEditingController(text: widget.element.zIndex.toString());
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _layerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Canvas block geometry'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorText case final errorText?) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  errorText,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: NoteCanvasElementTypes.code,
                    icon: Icon(Icons.code_outlined),
                    label: Text('Code'),
                  ),
                  ButtonSegment(
                    value: NoteCanvasElementTypes.text,
                    icon: Icon(Icons.notes_outlined),
                    label: Text('Text'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) =>
                    setState(() => _type = selection.single),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _numberField(_xController, 'X')),
                const SizedBox(width: 8),
                Expanded(child: _numberField(_yController, 'Y')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _numberField(_widthController, 'Width')),
                const SizedBox(width: 8),
                Expanded(child: _numberField(_heightController, 'Height')),
              ],
            ),
            const SizedBox(height: 12),
            _numberField(_layerController, 'Layer'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
    );
  }

  void _save() {
    final x = double.tryParse(_xController.text.trim());
    final y = double.tryParse(_yController.text.trim());
    final width = double.tryParse(_widthController.text.trim());
    final height = double.tryParse(_heightController.text.trim());
    final layer = int.tryParse(_layerController.text.trim());
    if (x == null ||
        y == null ||
        width == null ||
        height == null ||
        layer == null ||
        !x.isFinite ||
        !y.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      setState(() => _errorText = 'Enter valid numbers for every field.');
      return;
    }
    Navigator.of(context).pop(
      _CanvasGeometry(
        type: _type,
        x: x,
        y: y,
        width: width,
        height: height,
        zIndex: layer,
      ),
    );
  }

  String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

class _TodoEditor extends StatefulWidget {
  const _TodoEditor({
    required this.paper,
    required this.notePapers,
    required this.enableTodoNoteLinks,
    required this.showLinkedNoteName,
    required this.allowLongLinkedNoteTitles,
    required this.runLinkedScriptCapsulesOnClick,
    required this.maxTitleLength,
    required this.enableToolTips,
    required this.visualSize,
    required this.lineSpacing,
    required this.textZoom,
    required this.showDueRelativeTime,
    required this.dueYearDisplayMode,
    required this.onOpen,
    required this.onRunScriptCapsule,
    required this.onChanged,
    required this.onItemDeleted,
    required this.onItemRestored,
    required this.onReminderReset,
  });

  final PaperData paper;
  final List<PaperData> notePapers;
  final bool enableTodoNoteLinks;
  final bool showLinkedNoteName;
  final bool allowLongLinkedNoteTitles;
  final bool runLinkedScriptCapsulesOnClick;
  final int maxTitleLength;
  final bool enableToolTips;
  final String visualSize;
  final double lineSpacing;
  final double textZoom;
  final bool showDueRelativeTime;
  final String dueYearDisplayMode;
  final Future<void> Function(PaperData paper) onOpen;
  final Future<void> Function(ScriptCapsuleSpec spec) onRunScriptCapsule;
  final Future<void> Function() onChanged;
  final void Function(PaperData paper, PaperItem item) onItemDeleted;
  final void Function(PaperData paper, PaperItem item) onItemRestored;
  final void Function(PaperItem item) onReminderReset;

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<_TodoEditor> {
  static const _maxTodoUndoDepth = 100;
  static const _todoColumnSplitterWidth = 8.0;
  static const _minTodoColumnWidth = 0.2;

  final _todoFocusNode = FocusNode(debugLabel: 'todo-editor');
  final _todoMainFieldFocusNodes = <String, FocusNode>{};
  final _todoExtraFieldFocusNodes = <String, FocusNode>{};
  final _undoStack = <List<Map<String, Object?>>>[];
  final _redoStack = <List<Map<String, Object?>>>[];
  var _textFieldRevision = 0;
  var _suppressTodoBackspaceUntilKeyUp = false;
  String? _activeOriginalTodoItemId;
  String? _activeOriginalTodoText;

  @override
  void dispose() {
    _todoFocusNode.dispose();
    for (final focusNode in _todoMainFieldFocusNodes.values) {
      focusNode.dispose();
    }
    for (final focusNode in _todoExtraFieldFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visualSpec = _TodoVisualSpec.from(widget.visualSize);
    final itemTextStyle = theme.textTheme.bodyMedium
        ?.apply(fontSizeFactor: visualSpec.textScale * widget.textZoom)
        .copyWith(
          height: widget.lineSpacing,
        );
    return Focus(
      focusNode: _todoFocusNode,
      autofocus: true,
      onKeyEvent: _handleTodoKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final useCompactItemActions = availableWidth < 600;
          return Column(
            children: [
              ReorderableListView.builder(
                buildDefaultDragHandles: false,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.paper.items.length,
                onReorderItem: _reorderTodoItem,
                itemBuilder: (context, index) {
                  final item = widget.paper.items[index];
                  return _todoRow(
                    context: context,
                    item: item,
                    itemIndex: index,
                    itemTextStyle: itemTextStyle,
                    visualSpec: visualSpec,
                    compactActions: useCompactItemActions,
                  );
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Add item'),
                    ),
                    IconButton(
                      tooltip: _tooltipLabel(
                        widget.enableToolTips,
                        'Undo todo change',
                      ),
                      onPressed: _undoStack.isEmpty ? null : _undoTodoChange,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: _tooltipLabel(
                        widget.enableToolTips,
                        'Redo todo change',
                      ),
                      onPressed: _redoStack.isEmpty ? null : _redoTodoChange,
                      icon: const Icon(Icons.redo),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _todoRow({
    required BuildContext context,
    required PaperItem item,
    required int itemIndex,
    required TextStyle? itemTextStyle,
    required _TodoVisualSpec visualSpec,
    required bool compactActions,
  }) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: visualSpec.controlExtent,
          child: Transform.scale(
            scale: visualSpec.checkboxScale,
            child: Checkbox(
              value: item.done,
              onChanged: (value) {
                _pushTodoUndoSnapshot();
                setState(() => item.done = value ?? false);
                unawaited(widget.onChanged());
              },
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _todoColumnFields(context, item, itemTextStyle),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (_formatDueDate(item.dueAtLocal) case final dueDate?)
                    InputChip(
                      avatar: Icon(
                        Icons.event_outlined,
                        size: visualSpec.chipIconSize,
                      ),
                      label: Text('Due $dueDate'),
                      onDeleted: () => _clearDueDate(item),
                      deleteIcon: Icon(
                        Icons.close_outlined,
                        size: visualSpec.chipIconSize,
                      ),
                      deleteButtonTooltipMessage: _tooltipLabel(
                        widget.enableToolTips,
                        'Clear due date',
                      ),
                    ),
                  if (_formatReminderInterval(item)
                      case final reminderInterval?)
                    InputChip(
                      avatar: Icon(
                        Icons.notifications_active_outlined,
                        size: visualSpec.chipIconSize,
                      ),
                      label: Text(reminderInterval),
                      onDeleted: () => _clearReminderInterval(item),
                      deleteIcon: Icon(
                        Icons.close_outlined,
                        size: visualSpec.chipIconSize,
                      ),
                      deleteButtonTooltipMessage: _tooltipLabel(
                        widget.enableToolTips,
                        'Clear reminder interval',
                      ),
                    ),
                  if (widget.enableTodoNoteLinks)
                    if (_linkedNoteFor(item) case final linkedNote?)
                      _linkedNoteChip(
                        linkedNote,
                        item,
                        visualSpec,
                      ),
                ],
              ),
            ],
          ),
        ),
        ..._todoItemActions(
          context: context,
          item: item,
          itemIndex: itemIndex,
          visualSpec: visualSpec,
          compact: compactActions,
        ),
      ],
    );
    return Padding(
      key: ValueKey('${widget.paper.id}-${item.id}-row'),
      padding: EdgeInsets.only(bottom: visualSpec.itemGap),
      child: widget.enableTodoNoteLinks ? _noteLinkDropTarget(item, row) : row,
    );
  }

  Widget _noteLinkDropTarget(PaperItem item, Widget row) {
    final colorScheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _canAcceptNoteLinkDrop(details.data),
      onAcceptWithDetails: (details) => _linkNote(item, details.data),
      builder: (context, candidateData, rejectedData) {
        final highlighted =
            candidateData.whereType<String>().any(_canAcceptNoteLinkDrop);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: highlighted
                ? colorScheme.primaryContainer.withValues(alpha: 0.38)
                : Colors.transparent,
            border: Border.all(
              color: highlighted ? colorScheme.primary : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: row,
        );
      },
    );
  }

  bool _canAcceptNoteLinkDrop(String noteId) {
    return widget.enableTodoNoteLinks && _notePaperById(noteId) != null;
  }

  static const _columnActionAdd = 'add';
  static const _columnActionRemove = 'remove';
  static const _columnActionEqualWidths = 'equal-widths';
  static const _columnActionWideFirst = 'wide-first';
  static const _columnActionInsertBeforePrefix = 'insert-before:';
  static const _columnActionDeletePrefix = 'delete:';
  static const _compactTodoActionDueDate = 'due-date';
  static const _compactTodoActionClearDueDate = 'clear-due-date';
  static const _compactTodoActionReminder = 'reminder';
  static const _compactTodoActionClearReminder = 'clear-reminder';
  static const _compactTodoActionMoveUp = 'move-up';
  static const _compactTodoActionMoveDown = 'move-down';
  static const _compactTodoActionOpenLinkedNote = 'open-linked-note';
  static const _compactTodoActionUnlinkNote = 'unlink-note';
  static const _compactTodoActionDelete = 'delete';
  static const _compactTodoActionClearDone = 'clear-done';
  static const _compactTodoColumnActionPrefix = 'column:';
  static const _compactTodoLinkActionPrefix = 'link:';
  static const _todoLinkActionUnlink = 'todo-link:unlink';

  List<Widget> _todoItemActions({
    required BuildContext context,
    required PaperItem item,
    required int itemIndex,
    required _TodoVisualSpec visualSpec,
    required bool compact,
  }) {
    final hasLinkedNote = item.linkedNoteId?.trim().isNotEmpty ?? false;
    if (compact) {
      return [
        SizedBox(
          key: ValueKey('${widget.paper.id}-${item.id}-actions'),
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
          child: PopupMenuButton<String>(
            tooltip: _tooltipLabel(widget.enableToolTips, 'Todo item actions'),
            iconSize: visualSpec.iconSize,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleCompactTodoAction(
              context: context,
              item: item,
              value: value,
            ),
            itemBuilder: (context) => [
              _todoActionMenuItem(
                value: _compactTodoActionDueDate,
                icon: Icons.event_outlined,
                label: _hasDueDate(item) ? 'Change due date' : 'Set due date',
              ),
              if (_hasDueDate(item))
                _todoActionMenuItem(
                  value: _compactTodoActionClearDueDate,
                  icon: Icons.event_busy_outlined,
                  label: 'Clear due date',
                ),
              _todoActionMenuItem(
                value: _compactTodoActionReminder,
                icon: Icons.notifications_none_outlined,
                label: _hasReminderInterval(item)
                    ? 'Change reminder'
                    : 'Set reminder',
              ),
              if (_hasReminderInterval(item))
                _todoActionMenuItem(
                  value: _compactTodoActionClearReminder,
                  icon: Icons.notifications_off_outlined,
                  label: 'Clear reminder',
                ),
              if (widget.enableTodoNoteLinks && hasLinkedNote) ...[
                const PopupMenuDivider(),
                if (_linkedNoteFor(item) case final PaperData linkedNote)
                  _todoActionMenuItem(
                    value: _compactTodoActionOpenLinkedNote,
                    icon: Icons.open_in_new,
                    label: widget.runLinkedScriptCapsulesOnClick &&
                            ScriptCapsuleSpec.tryParse(linkedNote.content) !=
                                null
                        ? 'Edit linked script'
                        : 'Open linked note',
                  ),
                _todoActionMenuItem(
                  value: _compactTodoActionUnlinkNote,
                  icon: Icons.link_off_outlined,
                  label: 'Unlink note',
                ),
              ],
              if (widget.enableTodoNoteLinks &&
                  widget.notePapers.isNotEmpty &&
                  !hasLinkedNote) ...[
                const PopupMenuDivider(),
                for (final note in widget.notePapers)
                  _todoActionMenuItem(
                    value: '$_compactTodoLinkActionPrefix${note.id}',
                    icon: item.linkedNoteId == note.id
                        ? Icons.link_outlined
                        : Icons.notes_outlined,
                    label: _displayPaperTitle(note),
                  ),
              ],
              const PopupMenuDivider(),
              _todoActionMenuItem(
                value: _compactTodoActionDelete,
                icon: Icons.delete_outline,
                label: 'Delete item',
                enabled: widget.paper.items.length > 1,
              ),
              _todoActionMenuItem(
                value: _compactTodoActionClearDone,
                icon: Icons.delete_sweep_outlined,
                label: 'Clear completed',
                enabled: _hasDoneTodoItems,
              ),
              const PopupMenuDivider(),
              _todoActionMenuItem(
                value: _compactTodoActionMoveUp,
                icon: Icons.keyboard_arrow_up,
                label: 'Move item up',
                enabled: _canMoveTodoItem(item, -1),
              ),
              _todoActionMenuItem(
                value: _compactTodoActionMoveDown,
                icon: Icons.keyboard_arrow_down,
                label: 'Move item down',
                enabled: _canMoveTodoItem(item, 1),
              ),
              const PopupMenuDivider(),
              _todoActionMenuItem(
                value: '$_compactTodoColumnActionPrefix$_columnActionAdd',
                icon: Icons.add,
                label: 'Add column',
                enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
              ),
              _todoActionMenuItem(
                value: '$_compactTodoColumnActionPrefix$_columnActionRemove',
                icon: Icons.remove,
                label: 'Remove last column',
                enabled: item.todoColumnCount > 1,
              ),
              for (var columnIndex = 0;
                  columnIndex < item.todoColumnCount;
                  columnIndex++)
                _todoActionMenuItem(
                  value:
                      '$_compactTodoColumnActionPrefix$_columnActionInsertBeforePrefix$columnIndex',
                  icon: Icons.add_box_outlined,
                  label: 'Insert before column ${columnIndex + 1}',
                  enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
                ),
              for (var columnIndex = 0;
                  columnIndex < item.todoColumnCount;
                  columnIndex++)
                _todoActionMenuItem(
                  value:
                      '$_compactTodoColumnActionPrefix$_columnActionDeletePrefix$columnIndex',
                  icon: Icons.delete_sweep_outlined,
                  label: 'Delete column ${columnIndex + 1}',
                  enabled: item.todoColumnCount > 1,
                ),
              _todoActionMenuItem(
                value:
                    '$_compactTodoColumnActionPrefix$_columnActionEqualWidths',
                icon: Icons.view_column_outlined,
                label: 'Equal widths',
                enabled: item.todoColumnCount > 1,
              ),
              _todoActionMenuItem(
                value: '$_compactTodoColumnActionPrefix$_columnActionWideFirst',
                icon: Icons.view_week_outlined,
                label: 'Wide first column',
                enabled: item.todoColumnCount > 1,
              ),
              if (widget.enableTodoNoteLinks &&
                  widget.notePapers.isNotEmpty &&
                  hasLinkedNote) ...[
                const PopupMenuDivider(),
                for (final note in widget.notePapers)
                  _todoActionMenuItem(
                    value: '$_compactTodoLinkActionPrefix${note.id}',
                    icon: item.linkedNoteId == note.id
                        ? Icons.link_outlined
                        : Icons.notes_outlined,
                    label: _displayPaperTitle(note),
                  ),
              ],
            ],
          ),
        ),
      ];
    }
    return [
      ReorderableDragStartListener(
        key: ValueKey('${widget.paper.id}-${item.id}-drag-handle'),
        index: itemIndex,
        child: _maybeTooltip(
          enabled: widget.enableToolTips,
          message: 'Drag to reorder',
          child: SizedBox(
            width: visualSpec.controlExtent,
            height: visualSpec.controlExtent,
            child: Icon(Icons.drag_handle, size: visualSpec.iconSize),
          ),
        ),
      ),
      IconButton(
        tooltip: _tooltipLabel(widget.enableToolTips, 'Set due date'),
        onPressed: () => unawaited(_pickDueDate(context, item)),
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.event_outlined),
      ),
      IconButton(
        tooltip: _tooltipLabel(widget.enableToolTips, 'Set reminder interval'),
        onPressed: () => unawaited(_pickReminderInterval(context, item)),
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.notifications_none_outlined),
      ),
      PopupMenuButton<String>(
        tooltip: _tooltipLabel(widget.enableToolTips, 'Todo columns'),
        iconSize: visualSpec.iconSize,
        icon: const Icon(Icons.table_chart_outlined),
        onSelected: (value) => _updateColumns(item, value),
        itemBuilder: (context) {
          return [
            PopupMenuItem(
              value: _columnActionAdd,
              enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
              child: const ListTile(
                leading: Icon(Icons.add),
                title: Text('Add column'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _columnActionRemove,
              enabled: item.todoColumnCount > 1,
              child: const ListTile(
                leading: Icon(Icons.remove),
                title: Text('Remove last column'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuDivider(),
            for (var columnIndex = 0;
                columnIndex < item.todoColumnCount;
                columnIndex++)
              PopupMenuItem(
                value: '$_columnActionInsertBeforePrefix$columnIndex',
                enabled: item.todoColumnCount < TodoColumnLimits.maxCount,
                child: ListTile(
                  leading: const Icon(Icons.add_box_outlined),
                  title: Text('Insert before column ${columnIndex + 1}'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            for (var columnIndex = 0;
                columnIndex < item.todoColumnCount;
                columnIndex++)
              PopupMenuItem(
                value: '$_columnActionDeletePrefix$columnIndex',
                enabled: item.todoColumnCount > 1,
                child: ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text('Delete column ${columnIndex + 1}'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _columnActionEqualWidths,
              enabled: item.todoColumnCount > 1,
              child: const ListTile(
                leading: Icon(Icons.view_column_outlined),
                title: Text('Equal widths'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _columnActionWideFirst,
              enabled: item.todoColumnCount > 1,
              child: const ListTile(
                leading: Icon(Icons.view_week_outlined),
                title: Text('Wide first column'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ];
        },
      ),
      PopupMenuButton<String>(
        tooltip: _tooltipLabel(widget.enableToolTips, 'Link note'),
        enabled: widget.enableTodoNoteLinks &&
            (widget.notePapers.isNotEmpty ||
                (item.linkedNoteId?.trim().isNotEmpty ?? false)),
        iconSize: visualSpec.iconSize,
        icon: Icon(item.linkedNoteId == null
            ? Icons.note_add_outlined
            : Icons.link_outlined),
        onSelected: (value) {
          if (value == _todoLinkActionUnlink) {
            _clearLinkedNote(item);
            return;
          }
          _linkNote(item, value);
        },
        itemBuilder: (context) {
          return [
            if (item.linkedNoteId?.trim().isNotEmpty ?? false) ...[
              _todoActionMenuItem(
                value: _todoLinkActionUnlink,
                icon: Icons.link_off_outlined,
                label: 'Unlink note',
              ),
              if (widget.notePapers.isNotEmpty) const PopupMenuDivider(),
            ],
            for (final note in widget.notePapers)
              _todoActionMenuItem(
                value: note.id,
                icon: item.linkedNoteId == note.id
                    ? Icons.link_outlined
                    : Icons.notes_outlined,
                label: _displayPaperTitle(note),
              ),
          ];
        },
      ),
      IconButton(
        tooltip: _tooltipLabel(widget.enableToolTips, 'Move item up'),
        onPressed:
            _canMoveTodoItem(item, -1) ? () => _moveTodoItem(item, -1) : null,
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.keyboard_arrow_up),
      ),
      IconButton(
        tooltip: _tooltipLabel(widget.enableToolTips, 'Move item down'),
        onPressed:
            _canMoveTodoItem(item, 1) ? () => _moveTodoItem(item, 1) : null,
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.keyboard_arrow_down),
      ),
      IconButton(
        tooltip: _tooltipLabel(widget.enableToolTips, 'Delete item'),
        onPressed: widget.paper.items.length <= 1
            ? null
            : () => _deleteItem(context, item),
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.delete_outline),
      ),
      IconButton(
        tooltip: _tooltipLabel(widget.enableToolTips, 'Clear completed items'),
        onPressed: _hasDoneTodoItems ? _clearDoneItems : null,
        iconSize: visualSpec.iconSize,
        constraints: BoxConstraints.tightFor(
          width: visualSpec.controlExtent,
          height: visualSpec.controlExtent,
        ),
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ];
  }

  PopupMenuItem<String> _todoActionMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  Widget _maybeTooltip({
    required bool enabled,
    required String message,
    required Widget child,
  }) {
    if (!enabled) {
      return child;
    }
    return Tooltip(message: message, child: child);
  }

  void _handleCompactTodoAction({
    required BuildContext context,
    required PaperItem item,
    required String value,
  }) {
    if (value.startsWith(_compactTodoColumnActionPrefix)) {
      _updateColumns(
        item,
        value.substring(_compactTodoColumnActionPrefix.length),
      );
      return;
    }
    if (value.startsWith(_compactTodoLinkActionPrefix)) {
      _linkNote(item, value.substring(_compactTodoLinkActionPrefix.length));
      return;
    }
    switch (value) {
      case _compactTodoActionDueDate:
        unawaited(_pickDueDate(context, item));
      case _compactTodoActionClearDueDate:
        _clearDueDate(item);
      case _compactTodoActionReminder:
        unawaited(_pickReminderInterval(context, item));
      case _compactTodoActionClearReminder:
        _clearReminderInterval(item);
      case _compactTodoActionMoveUp:
        _moveTodoItem(item, -1);
      case _compactTodoActionMoveDown:
        _moveTodoItem(item, 1);
      case _compactTodoActionOpenLinkedNote:
        _openLinkedNote(item);
      case _compactTodoActionUnlinkNote:
        _clearLinkedNote(item);
      case _compactTodoActionDelete:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _deleteItem(context, item);
          }
        });
      case _compactTodoActionClearDone:
        _clearDoneItems();
    }
  }

  List<Map<String, Object?>> _snapshotTodoItems() {
    return [
      for (final item in widget.paper.items)
        Map<String, Object?>.from(item.toJson()),
    ];
  }

  void _pushTodoUndoSnapshot() {
    _commitFocusedTodoTextIfNeeded();
    _undoStack.add(_snapshotTodoItems());
    if (_undoStack.length > _maxTodoUndoDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  bool _commitFocusedTodoTextIfNeeded({bool clearRedo = false}) {
    final itemId = _activeOriginalTodoItemId;
    final originalText = _activeOriginalTodoText;
    if (itemId == null || originalText == null) {
      return false;
    }
    final item = _todoItemById(itemId);
    if (item == null) {
      _activeOriginalTodoItemId = null;
      _activeOriginalTodoText = null;
      return false;
    }
    if (item.text == originalText) {
      return false;
    }

    final currentText = item.text;
    item.text = originalText;
    _undoStack.add(_snapshotTodoItems());
    if (_undoStack.length > _maxTodoUndoDepth) {
      _undoStack.removeAt(0);
    }
    item.text = currentText;
    _activeOriginalTodoText = currentText;
    if (clearRedo) {
      _redoStack.clear();
    }
    return true;
  }

  PaperItem? _todoItemById(String itemId) {
    for (final item in widget.paper.items) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  void _markTodoTextEditCommitted(PaperItem item) {
    if (_activeOriginalTodoItemId == item.id) {
      _activeOriginalTodoText = item.text;
    }
  }

  void _restoreTodoSnapshot(List<Map<String, Object?>> snapshot) {
    final beforeItems = [...widget.paper.items];
    late final List<PaperItem> afterItems;
    setState(() {
      afterItems = [
        for (final itemJson in snapshot)
          PaperItem.fromJson(Map<String, Object?>.from(itemJson)),
      ];
      widget.paper.items = afterItems;
      widget.paper.normalize();
      _textFieldRevision++;
    });
    _reconcileTodoItemTombstones(beforeItems, afterItems);
    _requestTodoFocus();
    unawaited(widget.onChanged());
  }

  void _reconcileTodoItemTombstones(
    List<PaperItem> beforeItems,
    List<PaperItem> afterItems,
  ) {
    final beforeById = {
      for (final item in beforeItems)
        if (item.id.trim().isNotEmpty) item.id: item,
    };
    final afterById = {
      for (final item in afterItems)
        if (item.id.trim().isNotEmpty) item.id: item,
    };
    for (final entry in beforeById.entries) {
      if (!afterById.containsKey(entry.key)) {
        widget.onItemDeleted(widget.paper, entry.value);
      }
    }
    for (final entry in afterById.entries) {
      if (!beforeById.containsKey(entry.key)) {
        widget.onItemRestored(widget.paper, entry.value);
      }
    }
  }

  void _requestTodoFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _todoFocusNode.requestFocus();
      }
    });
  }

  FocusNode _mainTodoFieldFocusNode(PaperItem item) {
    final focusNode = _todoMainFieldFocusNodes.putIfAbsent(
      item.id,
      () {
        final node = FocusNode(debugLabel: 'todo-main-${item.id}');
        node.addListener(
          () => _handleMainTodoFieldFocusChange(item.id, node),
        );
        return node;
      },
    );
    focusNode.onKeyEvent =
        (node, event) => _handleTodoItemKeyEvent(node, item, event);
    return focusNode;
  }

  void _handleMainTodoFieldFocusChange(String itemId, FocusNode focusNode) {
    if (focusNode.hasFocus) {
      _activeOriginalTodoItemId = itemId;
      _activeOriginalTodoText = _todoItemById(itemId)?.text ?? '';
      return;
    }
    if (_activeOriginalTodoItemId != itemId) {
      return;
    }
    if (_commitFocusedTodoTextIfNeeded(clearRedo: true) && mounted) {
      setState(() {});
    }
  }

  FocusNode _extraTodoFieldFocusNode(PaperItem item, int index) {
    final focusKey = '${item.id}:$index';
    final focusNode = _todoExtraFieldFocusNodes.putIfAbsent(
      focusKey,
      () => FocusNode(debugLabel: 'todo-extra-$focusKey'),
    );
    focusNode.onKeyEvent =
        (node, event) => _handleTodoItemKeyEvent(node, item, event);
    return focusNode;
  }

  void _requestTodoItemFocus(String? itemId) {
    if (itemId == null) {
      _requestTodoFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final focusNode = _todoMainFieldFocusNodes[itemId];
      if (focusNode == null) {
        _todoFocusNode.requestFocus();
        return;
      }
      focusNode.requestFocus();
    });
  }

  void _unfocusTodoItem(PaperItem item) {
    _todoMainFieldFocusNodes[item.id]?.unfocus();
    final extraKeyPrefix = '${item.id}:';
    for (final entry in _todoExtraFieldFocusNodes.entries) {
      if (entry.key.startsWith(extraKeyPrefix)) {
        entry.value.unfocus();
      }
    }
  }

  String? _currentFocusedTodoItemId() {
    for (final entry in _todoMainFieldFocusNodes.entries) {
      if (entry.value.hasFocus) {
        return entry.key;
      }
    }
    for (final entry in _todoExtraFieldFocusNodes.entries) {
      if (entry.value.hasFocus) {
        return entry.key.split(':').first;
      }
    }
    return null;
  }

  void _undoTodoChange() {
    if (_undoStack.isEmpty) {
      return;
    }
    _redoStack.add(_snapshotTodoItems());
    _restoreTodoSnapshot(_undoStack.removeLast());
  }

  void _redoTodoChange() {
    if (_redoStack.isEmpty) {
      return;
    }
    _undoStack.add(_snapshotTodoItems());
    _restoreTodoSnapshot(_redoStack.removeLast());
  }

  KeyEventResult _handleTodoKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (_shouldDeferToTodoTextUndo(event)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      _undoTodoChange();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyY) {
      _redoTodoChange();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleTodoItemKeyEvent(
    FocusNode node,
    PaperItem item,
    KeyEvent event,
  ) {
    if (_shouldDeferToTodoTextUndo(event)) {
      return KeyEventResult.ignored;
    }
    final editorShortcutResult = _handleTodoKeyEvent(node, event);
    if (editorShortcutResult == KeyEventResult.handled) {
      return editorShortcutResult;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        event is KeyUpEvent) {
      _suppressTodoBackspaceUntilKeyUp = false;
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _noKeyboardModifiersPressed) {
      _insertItemAfter(item);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_suppressTodoBackspaceUntilKeyUp) {
        return KeyEventResult.handled;
      }
      if (_deleteBlankTodoItemFromKeyboard(item)) {
        _suppressTodoBackspaceUntilKeyUp = true;
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  bool _shouldDeferToTodoTextUndo(KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    if (event.logicalKey != LogicalKeyboardKey.keyZ &&
        event.logicalKey != LogicalKeyboardKey.keyY) {
      return false;
    }
    return _focusedTodoTextHasUncommittedEdit;
  }

  bool get _focusedTodoTextHasUncommittedEdit {
    final itemId = _activeOriginalTodoItemId;
    final originalText = _activeOriginalTodoText;
    if (itemId == null || originalText == null) {
      return false;
    }
    if (_todoMainFieldFocusNodes[itemId]?.hasFocus != true) {
      return false;
    }
    final item = _todoItemById(itemId);
    return item != null && item.text != originalText;
  }

  bool get _noKeyboardModifiersPressed {
    final keyboard = HardwareKeyboard.instance;
    return !keyboard.isControlPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed;
  }

  Widget _todoItemKeyboardScope(PaperItem item, Widget child) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _handleTodoItemKeyEvent(node, item, event),
      child: child,
    );
  }

  Widget _todoColumnFields(
    BuildContext context,
    PaperItem item,
    TextStyle? itemTextStyle,
  ) {
    final fields = [
      _mainColumnField(context, item, itemTextStyle),
      for (var index = 0; index < item.todoExtraColumns.length; index++)
        _extraColumnField(context, item, index, itemTextStyle),
    ];
    if (item.todoColumnCount <= 1) {
      return fields.first;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 640) {
            return Column(
              children: [
                for (var index = 0; index < fields.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == fields.length - 1 ? 0 : 6,
                    ),
                    child: fields[index],
                  ),
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: _columnFlex(item, 0),
                  child: fields.first,
                ),
                for (var index = 1; index < fields.length; index++) ...[
                  _todoColumnSplitter(
                    context: context,
                    item: item,
                    leftColumnIndex: index - 1,
                    availableWidth: constraints.maxWidth,
                  ),
                  Expanded(
                    flex: _columnFlex(item, index),
                    child: fields[index],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _todoColumnSplitter({
    required BuildContext context,
    required PaperItem item,
    required int leftColumnIndex,
    required double availableWidth,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        key: ValueKey(
          '${widget.paper.id}-${item.id}-column-splitter-${leftColumnIndex + 1}',
        ),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => _resizeTodoColumnPair(
          item: item,
          leftColumnIndex: leftColumnIndex,
          delta: details.delta.dx,
          availableWidth: availableWidth,
        ),
        child: SizedBox(
          width: _todoColumnSplitterWidth,
          child: Center(
            child: FractionallySizedBox(
              heightFactor: 0.72,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(1),
                ),
                child: const SizedBox(width: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _resizeTodoColumnPair({
    required PaperItem item,
    required int leftColumnIndex,
    required double delta,
    required double availableWidth,
  }) {
    if (delta.abs() < 0.1) {
      return;
    }
    item.normalize();
    final count = item.todoColumnCount;
    if (leftColumnIndex < 0 || leftColumnIndex >= count - 1) {
      return;
    }
    final widths = _normalizedTodoColumnWidths(item);
    final totalUnits = widths.fold<double>(0, (total, width) => total + width);
    final columnPixels = math.max(
      1.0,
      availableWidth - ((count - 1) * _todoColumnSplitterWidth),
    );
    final unitsPerPixel = totalUnits / columnPixels;
    final requestedDelta = delta * unitsPerPixel;
    final minDelta = _minTodoColumnWidth - widths[leftColumnIndex];
    final maxDelta = widths[leftColumnIndex + 1] - _minTodoColumnWidth;
    final appliedDelta = requestedDelta.clamp(minDelta, maxDelta).toDouble();
    if (appliedDelta.abs() < 0.001) {
      return;
    }

    widths[leftColumnIndex] =
        _roundTodoColumnWidth(widths[leftColumnIndex] + appliedDelta);
    widths[leftColumnIndex + 1] =
        _roundTodoColumnWidth(widths[leftColumnIndex + 1] - appliedDelta);
    setState(() => item.todoColumnWidths = widths);
    unawaited(widget.onChanged());
  }

  List<double> _normalizedTodoColumnWidths(PaperItem item) {
    if (item.todoColumnWidths.length == item.todoColumnCount) {
      return [
        for (final width in item.todoColumnWidths)
          width.isFinite && width >= _minTodoColumnWidth
              ? width
              : _minTodoColumnWidth,
      ];
    }
    return List.filled(item.todoColumnCount, 1);
  }

  double _roundTodoColumnWidth(double value) {
    return (value.clamp(_minTodoColumnWidth, 10000.0) * 1000).roundToDouble() /
        1000;
  }

  Widget _mainColumnField(
    BuildContext context,
    PaperItem item,
    TextStyle? itemTextStyle,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: ValueKey('${widget.paper.id}-${item.id}-text'),
      child: _todoItemKeyboardScope(
        item,
        TextFormField(
          key: ValueKey(
            '${widget.paper.id}-${item.id}-text-field-$_textFieldRevision',
          ),
          focusNode: _mainTodoFieldFocusNode(item),
          initialValue: item.text,
          keyboardType: TextInputType.multiline,
          minLines: 1,
          maxLines: null,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            border: item.todoColumnCount > 1
                ? const OutlineInputBorder()
                : InputBorder.none,
            labelText: item.todoColumnCount > 1 ? 'Column 1' : null,
            hintText: 'New item',
            isDense: true,
          ),
          style: itemTextStyle?.copyWith(
            color: item.done ? colorScheme.outline : colorScheme.onSurface,
            decoration: item.done ? TextDecoration.lineThrough : null,
          ),
          inputFormatters: [
            _TodoPasteTextInputFormatter(
              onPaste: (value) => _handleMultiLinePaste(item, value),
            ),
          ],
          onChanged: (value) {
            if (_handleMultiLinePaste(item, value)) {
              return;
            }
            item.text = value;
            unawaited(widget.onChanged());
          },
          onFieldSubmitted: (_) => _insertItemAfter(item),
        ),
      ),
    );
  }

  bool _handleMultiLinePaste(PaperItem item, String value) {
    if (!value.contains('\n') && !value.contains('\r')) {
      return false;
    }
    final lines = TodoPasteItems.parseLines(value);
    if (lines.length <= 1) {
      return false;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      item.text = lines.first;
      _addItemsAfter(item, lines.skip(1));
      widget.paper.normalize();
      _textFieldRevision++;
    });
    _markTodoTextEditCommitted(item);
    _requestTodoFocus();
    unawaited(widget.onChanged());
    return true;
  }

  Widget _extraColumnField(
    BuildContext context,
    PaperItem item,
    int index,
    TextStyle? itemTextStyle,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return _todoItemKeyboardScope(
      item,
      TextFormField(
        key: ValueKey(
          '${widget.paper.id}-${item.id}-column-${index + 2}',
        ),
        focusNode: _extraTodoFieldFocusNode(item, index),
        initialValue: item.todoExtraColumns[index],
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'Column ${index + 2}',
          isDense: true,
        ),
        style: itemTextStyle?.copyWith(
          color: item.done ? colorScheme.outline : colorScheme.onSurface,
          decoration: item.done ? TextDecoration.lineThrough : null,
        ),
        onChanged: (value) {
          item.todoExtraColumns[index] = value;
          unawaited(widget.onChanged());
        },
        onFieldSubmitted: (_) => _insertItemAfter(item),
      ),
    );
  }

  int _columnFlex(PaperItem item, int index) {
    if (item.todoColumnWidths.length != item.todoColumnCount) {
      return 1;
    }
    final width = item.todoColumnWidths[index];
    if (width <= 0 || !width.isFinite) {
      return 1;
    }
    return (width * 100).round().clamp(1, 10000).toInt();
  }

  void _updateColumns(PaperItem item, String action) {
    _pushTodoUndoSnapshot();
    setState(() {
      if (action == _columnActionAdd &&
          item.todoColumnCount < TodoColumnLimits.maxCount) {
        item.todoColumnCount += 1;
        if (item.todoColumnWidths.isNotEmpty) {
          item.todoColumnWidths = [
            ...item.todoColumnWidths.take(item.todoColumnCount - 1),
            1,
          ];
        }
      } else if (action == _columnActionRemove && item.todoColumnCount > 1) {
        item.todoColumnCount -= 1;
        if (item.todoColumnWidths.isNotEmpty) {
          item.todoColumnWidths =
              item.todoColumnWidths.take(item.todoColumnCount).toList();
        }
      } else if (action.startsWith(_columnActionInsertBeforePrefix)) {
        final columnIndex = int.tryParse(
          action.substring(_columnActionInsertBeforePrefix.length),
        );
        if (columnIndex != null) {
          _insertTodoColumnBefore(item, columnIndex);
        }
      } else if (action.startsWith(_columnActionDeletePrefix)) {
        final columnIndex = int.tryParse(
          action.substring(_columnActionDeletePrefix.length),
        );
        if (columnIndex != null) {
          _deleteTodoColumn(item, columnIndex);
        }
      } else if (action == _columnActionEqualWidths &&
          item.todoColumnCount > 1) {
        item.todoColumnWidths = List.filled(item.todoColumnCount, 1);
      } else if (action == _columnActionWideFirst && item.todoColumnCount > 1) {
        item.todoColumnWidths = [
          2,
          ...List.filled(item.todoColumnCount - 1, 1),
        ];
      }
      item.normalize();
    });
    _markTodoTextEditCommitted(item);
    unawaited(widget.onChanged());
  }

  bool _canMoveTodoItem(PaperItem item, int delta) {
    final index = _todoItemIndex(item);
    if (index < 0) {
      return false;
    }
    final targetIndex = index + delta;
    return targetIndex >= 0 && targetIndex < widget.paper.items.length;
  }

  int _todoItemIndex(PaperItem item) {
    return widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
  }

  void _moveTodoItem(PaperItem item, int delta) {
    final index = _todoItemIndex(item);
    final targetIndex = index + delta;
    if (index < 0 ||
        targetIndex < 0 ||
        targetIndex >= widget.paper.items.length) {
      return;
    }

    _pushTodoUndoSnapshot();
    setState(() {
      final targetItem = widget.paper.items[targetIndex];
      widget.paper.items[targetIndex] = item;
      widget.paper.items[index] = targetItem;
      widget.paper.normalize();
    });
    _requestTodoItemFocus(item.id);
    unawaited(widget.onChanged());
  }

  void _reorderTodoItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= widget.paper.items.length) {
      return;
    }
    final insertIndex =
        newIndex.clamp(0, widget.paper.items.length - 1).toInt();
    if (insertIndex == oldIndex) {
      return;
    }

    _pushTodoUndoSnapshot();
    late final PaperItem movedItem;
    setState(() {
      movedItem = widget.paper.items.removeAt(oldIndex);
      widget.paper.items.insert(insertIndex, movedItem);
      widget.paper.normalize();
    });
    _requestTodoItemFocus(movedItem.id);
    unawaited(widget.onChanged());
  }

  void _insertTodoColumnBefore(PaperItem item, int columnIndex) {
    item.normalize();
    final count = item.todoColumnCount;
    if (count >= TodoColumnLimits.maxCount) {
      return;
    }

    final insertIndex = columnIndex.clamp(0, count).toInt();
    if (insertIndex == 0) {
      item.todoExtraColumns.insert(0, item.text);
      item.text = '';
    } else {
      item.todoExtraColumns.insert(insertIndex - 1, '');
    }
    item.todoColumnCount = count + 1;
    item.todoColumnWidths.insert(insertIndex, 1);
  }

  void _deleteTodoColumn(PaperItem item, int columnIndex) {
    item.normalize();
    final count = item.todoColumnCount;
    if (count <= TodoColumnLimits.minCount) {
      return;
    }

    final deleteIndex = columnIndex.clamp(0, count - 1).toInt();
    if (deleteIndex == 0) {
      if (item.todoExtraColumns.isEmpty) {
        item.text = '';
      } else {
        item.text = item.todoExtraColumns.first;
        item.todoExtraColumns.removeAt(0);
      }
    } else if (deleteIndex - 1 < item.todoExtraColumns.length) {
      item.todoExtraColumns.removeAt(deleteIndex - 1);
    }
    if (deleteIndex < item.todoColumnWidths.length) {
      item.todoColumnWidths.removeAt(deleteIndex);
    }
    item.todoColumnCount = count - 1;
  }

  void _addItem() {
    final inheritedItem =
        widget.paper.items.isEmpty ? null : widget.paper.items.last;
    _insertItemAfter(inheritedItem);
  }

  void _insertItemAfter(PaperItem? item, {String text = ''}) {
    _pushTodoUndoSnapshot();
    final insertIndex = item == null
        ? widget.paper.items.length
        : widget.paper.items.indexWhere(
              (candidate) => candidate.id == item.id,
            ) +
            1;
    final normalizedInsertIndex = insertIndex <= 0
        ? widget.paper.items.length
        : insertIndex.clamp(0, widget.paper.items.length).toInt();
    final inheritedItem =
        item ?? (widget.paper.items.isEmpty ? null : widget.paper.items.last);
    final newItem = _newTodoItem(inheritedItem: inheritedItem, text: text);
    setState(() {
      widget.paper.items.insert(normalizedInsertIndex, newItem);
      widget.paper.normalize();
    });
    _requestTodoItemFocus(newItem.id);
    unawaited(widget.onChanged());
  }

  void _addItemsAfter(PaperItem item, Iterable<String> lines) {
    final insertIndex = widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (insertIndex < 0) {
      return;
    }
    final inheritedColumnCount = item.todoColumnCount;
    final inheritedColumnWidths =
        item.todoColumnWidths.length == inheritedColumnCount
            ? item.todoColumnWidths
            : <double>[];
    final idSeed = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    var lineIndex = 0;
    final newItems = [
      for (final line in lines)
        PaperItem(
          id: '$idSeed-${lineIndex++}',
          text: line,
          todoColumnCount: inheritedColumnCount,
          todoExtraColumns: List.filled(inheritedColumnCount - 1, ''),
          todoColumnWidths: [...inheritedColumnWidths],
        ),
    ];
    widget.paper.items.insertAll(insertIndex + 1, newItems);
  }

  PaperItem _newTodoItem({PaperItem? inheritedItem, String text = ''}) {
    final inheritedColumnCount = inheritedItem?.todoColumnCount ?? 1;
    final inheritedColumnWidths =
        inheritedItem?.todoColumnWidths.length == inheritedColumnCount
            ? inheritedItem!.todoColumnWidths
            : <double>[];
    return PaperItem(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
      text: text,
      todoColumnCount: inheritedColumnCount,
      todoExtraColumns: List.filled(inheritedColumnCount - 1, ''),
      todoColumnWidths: [...inheritedColumnWidths],
    );
  }

  bool _deleteBlankTodoItemFromKeyboard(PaperItem item) {
    final removedIndex = widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (removedIndex < 0 ||
        widget.paper.items.length <= 1 ||
        !_allTodoTextColumnsBlank(item)) {
      return false;
    }

    final previousItem =
        removedIndex > 0 ? widget.paper.items[removedIndex - 1] : null;
    final nextItem = removedIndex + 1 < widget.paper.items.length
        ? widget.paper.items[removedIndex + 1]
        : null;
    final focusTargetId = previousItem?.id ?? nextItem?.id;

    _pushTodoUndoSnapshot();
    _unfocusTodoItem(item);
    setState(() {
      widget.paper.items.removeAt(removedIndex);
      if (widget.paper.items.isEmpty) {
        widget.paper.items.add(_newTodoItem());
      }
      widget.paper.normalize();
    });
    widget.onItemDeleted(widget.paper, item);
    _requestTodoItemFocus(focusTargetId ?? widget.paper.items.first.id);
    unawaited(widget.onChanged());
    return true;
  }

  bool _allTodoTextColumnsBlank(PaperItem item) {
    return item.text.trim().isEmpty &&
        item.todoExtraColumns.every((column) => column.trim().isEmpty);
  }

  bool _isBlankTodoItem(PaperItem item) {
    return _allTodoTextColumnsBlank(item) &&
        (item.dueAtLocal?.trim().isEmpty ?? true) &&
        item.reminderIntervalValue == null &&
        (item.linkedNoteId?.trim().isEmpty ?? true);
  }

  bool _hasDueDate(PaperItem item) {
    return item.dueAtLocal?.trim().isNotEmpty ?? false;
  }

  bool _hasReminderInterval(PaperItem item) {
    return item.reminderIntervalValue != null;
  }

  bool get _hasDoneTodoItems {
    return widget.paper.items.any((item) => item.done);
  }

  void _clearDoneItems() {
    final completedItems =
        widget.paper.items.where((item) => item.done).toList();
    if (completedItems.isEmpty) {
      return;
    }
    final focusedId = _currentFocusedTodoItemId();
    final completedIds = completedItems.map((item) => item.id).toSet();

    _pushTodoUndoSnapshot();
    for (final item in completedItems) {
      _unfocusTodoItem(item);
    }
    String? focusTargetId;
    setState(() {
      final remainingItems = widget.paper.items
          .where((item) => !completedIds.contains(item.id))
          .toList();
      if (remainingItems.isEmpty) {
        remainingItems.add(_newTodoItem());
      }
      widget.paper.items = remainingItems;
      widget.paper.normalize();
      if (widget.paper.items.any((item) => item.id == focusedId)) {
        focusTargetId = focusedId;
      } else {
        for (final item in widget.paper.items) {
          if (!_isBlankTodoItem(item)) {
            focusTargetId = item.id;
            break;
          }
        }
        focusTargetId ??=
            widget.paper.items.isEmpty ? null : widget.paper.items.first.id;
      }
    });
    for (final item in completedItems) {
      widget.onItemDeleted(widget.paper, item);
    }
    _requestTodoItemFocus(focusTargetId);
    unawaited(widget.onChanged());
  }

  void _deleteItem(BuildContext context, PaperItem item) {
    final removedIndex = widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (removedIndex < 0 || widget.paper.items.length <= 1) {
      return;
    }
    _pushTodoUndoSnapshot();
    _unfocusTodoItem(item);
    setState(() {
      widget.paper.items.removeAt(removedIndex);
      widget.paper.normalize();
    });
    widget.onItemDeleted(widget.paper, item);
    unawaited(widget.onChanged());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_displayItemText(item)} deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              final targetIndex = removedIndex
                  .clamp(
                    0,
                    widget.paper.items.length,
                  )
                  .toInt();
              widget.paper.items.insert(targetIndex, item);
              widget.paper.normalize();
            });
            widget.onItemRestored(widget.paper, item);
            unawaited(widget.onChanged());
          },
        ),
      ),
    );
  }

  Future<void> _pickDueDate(BuildContext context, PaperItem item) async {
    final now = DateTime.now();
    final initialDate = DateTime.tryParse(item.dueAtLocal ?? '')?.toLocal() ??
        now.add(const Duration(hours: 1));
    final result = await showDialog<_TodoDueSelection>(
      context: context,
      builder: (context) => _TodoDueSelectionDialog(initialDate: initialDate),
    );
    if (result == null) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      item.dueAtLocal = result.clear
          ? null
          : _formatDueAtLocalValue(result.dueAt ?? initialDate);
    });
    widget.onReminderReset(item);
    unawaited(widget.onChanged());
  }

  void _clearDueDate(PaperItem item) {
    if (!_hasDueDate(item)) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() => item.dueAtLocal = null);
    widget.onReminderReset(item);
    unawaited(widget.onChanged());
  }

  Future<void> _pickReminderInterval(
    BuildContext context,
    PaperItem item,
  ) async {
    final result = await showDialog<_ReminderIntervalSelection>(
      context: context,
      builder: (context) => _ReminderIntervalDialog(
        initialValue: item.reminderIntervalValue,
        initialUnit: item.reminderIntervalUnit,
      ),
    );
    if (result == null) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      if (result.clear) {
        item.reminderIntervalValue = null;
        item.reminderIntervalUnit = null;
      } else {
        item.reminderIntervalValue = result.value;
        item.reminderIntervalUnit = result.unit;
      }
    });
    widget.onReminderReset(item);
    unawaited(widget.onChanged());
  }

  void _clearReminderInterval(PaperItem item) {
    if (!_hasReminderInterval(item)) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      item.reminderIntervalValue = null;
      item.reminderIntervalUnit = null;
    });
    widget.onReminderReset(item);
    unawaited(widget.onChanged());
  }

  void _openLinkedNote(PaperItem item) {
    final noteId = item.linkedNoteId;
    if (noteId == null) {
      return;
    }
    final linkedNote = _notePaperById(noteId);
    if (linkedNote == null) {
      return;
    }
    unawaited(widget.onOpen(linkedNote));
  }

  void _linkNote(PaperItem item, String noteId) {
    if (!widget.enableTodoNoteLinks ||
        _notePaperById(noteId) == null ||
        item.linkedNoteId == noteId) {
      return;
    }
    final focusTargetId = _currentFocusedTodoItemId() ?? item.id;
    _pushTodoUndoSnapshot();
    setState(() => item.linkedNoteId = noteId);
    _requestTodoItemFocus(focusTargetId);
    unawaited(widget.onChanged());
  }

  void _clearLinkedNote(PaperItem item) {
    if (item.linkedNoteId == null || item.linkedNoteId!.trim().isEmpty) {
      return;
    }
    final focusTargetId = _currentFocusedTodoItemId() ?? item.id;
    _pushTodoUndoSnapshot();
    setState(() => item.linkedNoteId = null);
    _requestTodoItemFocus(focusTargetId);
    unawaited(widget.onChanged());
  }

  PaperData? _notePaperById(String noteId) {
    for (final note in widget.notePapers) {
      if (note.id == noteId) {
        return note;
      }
    }
    return null;
  }

  PaperData? _linkedNoteFor(PaperItem item) {
    final noteId = item.linkedNoteId;
    if (noteId == null) {
      return null;
    }
    return _notePaperById(noteId);
  }

  InputChip _linkedNoteChip(
    PaperData linkedNote,
    PaperItem item,
    _TodoVisualSpec visualSpec,
  ) {
    final scriptSpec = widget.runLinkedScriptCapsulesOnClick
        ? ScriptCapsuleSpec.tryParse(linkedNote.content)
        : null;
    final isScriptCapsule = scriptSpec != null;
    return InputChip(
      avatar: Icon(
        isScriptCapsule ? Icons.bolt_outlined : Icons.notes_outlined,
        size: visualSpec.chipIconSize,
      ),
      label: Text(
        isScriptCapsule
            ? _scriptChipLabel(linkedNote)
            : _noteChipLabel(linkedNote),
      ),
      tooltip: _tooltipLabel(
        widget.enableToolTips,
        isScriptCapsule ? 'Run linked script capsule' : 'Open linked note',
      ),
      onPressed: () {
        if (scriptSpec != null) {
          unawaited(widget.onRunScriptCapsule(scriptSpec));
          return;
        }
        unawaited(widget.onOpen(linkedNote));
      },
      onDeleted: () => _clearLinkedNote(item),
      deleteIcon: Icon(Icons.close_outlined, size: visualSpec.chipIconSize),
      deleteButtonTooltipMessage:
          _tooltipLabel(widget.enableToolTips, 'Unlink note'),
    );
  }

  String _noteChipLabel(PaperData note) {
    if (!widget.showLinkedNoteName) {
      return 'Note';
    }
    final title = widget.allowLongLinkedNoteTitles
        ? _displayPaperTitle(note)
        : _shortenTitle(_displayPaperTitle(note), widget.maxTitleLength);
    return 'Note $title';
  }

  String _scriptChipLabel(PaperData note) {
    if (!widget.showLinkedNoteName) {
      return 'Script';
    }
    final title = widget.allowLongLinkedNoteTitles
        ? _displayPaperTitle(note)
        : _shortenTitle(_displayPaperTitle(note), widget.maxTitleLength);
    return 'Run $title';
  }

  String _displayPaperTitle(PaperData paper) {
    final title = PaperTitles.cleanCustomTitle(paper.title);
    if (title.isNotEmpty) {
      return title;
    }
    return PaperTitles.defaultTitle(paper.type, _titleNumberForPaper(paper));
  }

  int _titleNumberForPaper(PaperData paper) {
    final normalizedType = PaperTypes.normalize(paper.type);
    var number = 1;
    for (final existing in widget.notePapers) {
      if (PaperTypes.normalize(existing.type) != normalizedType) {
        continue;
      }
      if (existing.id == paper.id) {
        return number;
      }
      number++;
    }
    return math.max(1, number);
  }

  String _displayItemText(PaperItem item) {
    final text = item.text.trim();
    return text.isEmpty ? 'Todo item' : text;
  }

  String? _formatDueDate(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) {
      return null;
    }
    if (widget.showDueRelativeTime) {
      return _relativeDueDate(date);
    }
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final time = _formatDueTime(date);
    final yearDisplayMode = TodoDueYearDisplayModes.normalize(
      widget.dueYearDisplayMode,
    );
    return switch (yearDisplayMode) {
      TodoDueYearDisplayModes.short =>
        '${(date.year % 100).toString().padLeft(2, '0')}-$month-$day $time',
      TodoDueYearDisplayModes.full => '${date.year}-$month-$day $time',
      _ => _formatCompactAbsoluteDueDate(date, time, month, day),
    };
  }

  String _formatCompactAbsoluteDueDate(
    DateTime date,
    String time,
    String month,
    String day,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(date.year, date.month, date.day);
    if (dueDay == today) {
      return time;
    }
    if (dueDay == today.add(const Duration(days: 1))) {
      return 'Tomorrow $time';
    }
    return '$month-$day $time';
  }

  String _formatDueTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDueAtLocalValue(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    return '$year-$month-${day}T$hour:$minute:$second';
  }

  String? _formatReminderInterval(PaperItem item) {
    final value = item.reminderIntervalValue;
    if (value == null || value < 1) {
      return null;
    }
    final unit = TodoReminderIntervalUnits.normalize(item.reminderIntervalUnit);
    final suffix = unit == TodoReminderIntervalUnits.hours ? 'hr' : 'min';
    return 'Every $value $suffix';
  }

  String _relativeDueDate(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now);
    final isPast = difference.isNegative;
    final absoluteMicroseconds =
        isPast ? -difference.inMicroseconds : difference.inMicroseconds;
    final totalMinutes = (absoluteMicroseconds / Duration.microsecondsPerMinute)
        .ceil()
        .clamp(1, 1 << 31)
        .toInt();
    final days = totalMinutes ~/ (24 * 60);
    final hours = (totalMinutes % (24 * 60)) ~/ 60;
    final minutes = totalMinutes % 60;
    final parts = <String>[
      if (days > 0) '${days}d',
      if (hours > 0) '${hours}h',
      if (minutes > 0 || (days == 0 && hours == 0))
        '${minutes <= 0 ? 1 : minutes}m',
    ];
    final text = parts.join();
    if (isPast) {
      return '$text overdue';
    }
    return 'in $text';
  }
}

class _TodoDueSelection {
  const _TodoDueSelection.set(this.dueAt) : clear = false;

  const _TodoDueSelection.clear()
      : dueAt = null,
        clear = true;

  final DateTime? dueAt;
  final bool clear;
}

class _TodoDueSelectionDialog extends StatefulWidget {
  const _TodoDueSelectionDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_TodoDueSelectionDialog> createState() =>
      _TodoDueSelectionDialogState();
}

class _TodoDueSelectionDialogState extends State<_TodoDueSelectionDialog> {
  late DateTime _selectedDate;
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _hour = widget.initialDate.hour;
    _minute = widget.initialDate.minute;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Due date'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 330,
                child: CalendarDatePicker(
                  initialDate: _selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  onDateChanged: (value) {
                    setState(() {
                      _selectedDate = DateTime(
                        value.year,
                        value.month,
                        value.day,
                      );
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('todo-due-hour'),
                      initialValue: _hour,
                      decoration: const InputDecoration(
                        labelText: 'Hour',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (var value = 0; value < 24; value++)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.toString().padLeft(2, '0')),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _hour = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('todo-due-minute'),
                      initialValue: _minute,
                      decoration: const InputDecoration(
                        labelText: 'Minute',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (var value = 0; value < 60; value++)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.toString().padLeft(2, '0')),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _minute = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const _TodoDueSelection.clear()),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _TodoDueSelection.set(
                DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  _selectedDate.day,
                  _hour,
                  _minute,
                ),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _TodoPasteTextInputFormatter extends TextInputFormatter {
  const _TodoPasteTextInputFormatter({required this.onPaste});

  final void Function(String text) onPaste;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains('\n') && !newValue.text.contains('\r')) {
      return newValue;
    }
    final lines = TodoPasteItems.parseLines(newValue.text);
    if (lines.length <= 1) {
      final text = lines.isEmpty ? oldValue.text : lines.single;
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    scheduleMicrotask(() => onPaste(newValue.text));
    return oldValue;
  }
}

class _MarkdownPasteTextInputFormatter extends TextInputFormatter {
  const _MarkdownPasteTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sanitized = MarkdownPasteText.sanitize(newValue.text);
    if (sanitized == newValue.text) {
      return newValue;
    }
    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(
        offset: sanitized.length,
      ),
    );
  }
}

class _MarkdownListContinuationTextInputFormatter extends TextInputFormatter {
  const _MarkdownListContinuationTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return MarkdownListContinuation.formatEnter(oldValue, newValue);
  }
}

class _PaperTitleTextInputFormatter extends TextInputFormatter {
  const _PaperTitleTextInputFormatter({required this.maxLength});

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = _cleanEditingTitle(newValue.text);
    if (cleaned == newValue.text) {
      return newValue;
    }

    final selection = newValue.selection;
    return newValue.copyWith(
      text: cleaned,
      selection: selection.copyWith(
        baseOffset: _cleanedOffset(newValue.text, selection.baseOffset),
        extentOffset: _cleanedOffset(newValue.text, selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }

  String _cleanEditingTitle(String value) {
    final withoutControls = value.runes
        .where((rune) => !_isControlRune(rune))
        .map(String.fromCharCode)
        .join();
    return PaperTitles.shorten(withoutControls, maxLength);
  }

  int _cleanedOffset(String text, int offset) {
    if (offset < 0) {
      return -1;
    }
    final safeOffset = offset.clamp(0, text.length).toInt();
    return _cleanEditingTitle(text.substring(0, safeOffset)).length;
  }

  bool _isControlRune(int rune) {
    return rune < 0x20 || (rune >= 0x7F && rune <= 0x9F);
  }
}

class _TodoVisualSpec {
  const _TodoVisualSpec({
    required this.textScale,
    required this.checkboxScale,
    required this.iconSize,
    required this.chipIconSize,
    required this.controlExtent,
    required this.itemGap,
  });

  final double textScale;
  final double checkboxScale;
  final double iconSize;
  final double chipIconSize;
  final double controlExtent;
  final double itemGap;

  static _TodoVisualSpec from(String value) {
    return switch (TodoVisualSizes.normalize(value)) {
      TodoVisualSizes.small => const _TodoVisualSpec(
          textScale: 0.94,
          checkboxScale: 0.9,
          iconSize: 20,
          chipIconSize: 16,
          controlExtent: 44,
          itemGap: 4,
        ),
      TodoVisualSizes.large => const _TodoVisualSpec(
          textScale: 1.08,
          checkboxScale: 1.08,
          iconSize: 26,
          chipIconSize: 20,
          controlExtent: 48,
          itemGap: 12,
        ),
      TodoVisualSizes.extraLarge => const _TodoVisualSpec(
          textScale: 1.18,
          checkboxScale: 1.18,
          iconSize: 30,
          chipIconSize: 22,
          controlExtent: 52,
          itemGap: 16,
        ),
      _ => const _TodoVisualSpec(
          textScale: 1,
          checkboxScale: 1,
          iconSize: 24,
          chipIconSize: 18,
          controlExtent: 44,
          itemGap: 8,
        ),
    };
  }
}
