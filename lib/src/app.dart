import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path/path.dart' as p;

import 'app_controller.dart';
import 'core/model/app_state.dart';
import 'core/model/markdown_paste.dart';
import 'core/model/note_canvas_element.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
import 'core/model/paper_item.dart';
import 'core/model/paper_titles.dart';
import 'core/model/todo_paste.dart';
import 'core/script/script_capsule.dart';
import 'core/storage/state_store.dart';
import 'core/startup/startup_command.dart';
import 'sync/app_sync_service.dart';
import 'ui/sync_settings_dialog.dart';

class RePaperTodoApp extends StatefulWidget {
  const RePaperTodoApp({
    required this.controller,
    required this.store,
    this.syncService,
    super.key,
  });

  final RePaperTodoController controller;
  final StateStore store;
  final AppSyncService? syncService;

  @override
  State<RePaperTodoApp> createState() => _RePaperTodoAppState();
}

class _RePaperTodoAppState extends State<RePaperTodoApp> {
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

  ThemeData _appTheme(Brightness brightness, AppState state) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor(state),
        brightness: brightness,
      ),
      useMaterial3: true,
    );
    final fontFamily = _fontFamily(state);
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        fontSizeFactor: state.zoom,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: fontFamily,
        fontSizeFactor: state.zoom,
      ),
    );
  }

  ThemeMode _themeMode(String theme) {
    return switch (theme) {
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
    return switch (UiFontPresets.normalize(state.uiFontPreset)) {
      UiFontPresets.serif => 'serif',
      UiFontPresets.mono => 'monospace',
      UiFontPresets.custom when state.systemFontFamilyName.isNotEmpty =>
        state.systemFontFamilyName,
      _ => null,
    };
  }
}

String _shortenTitle(String title, int maxLength) {
  return PaperTitles.shorten(title, maxLength);
}

String? _tooltipLabel(bool enabled, String label) => enabled ? label : null;

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

class _PaperBoardScreenState extends State<PaperBoardScreen> {
  bool _isSyncing = false;
  Future<void> _saveQueue = Future<void>.value();
  StreamSubscription<PaperData>? _surfaceUpdateSubscription;
  StreamSubscription<String>? _paperOpenSubscription;
  StreamSubscription<StartupCommand>? _startupCommandSubscription;
  Timer? _surfaceSaveDebounce;
  Timer? _titleSurfaceDebounce;
  Timer? _todoReminderTimer;
  String? _surfacePaperId;
  final Map<String, DateTime> _lastTodoReminderAt = <String, DateTime>{};

  RePaperTodoController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _surfaceUpdateSubscription =
        controller.paperSurfaceUpdates.listen(_handleSurfaceUpdate);
    _paperOpenSubscription = controller.paperOpenRequests.listen((paperId) {
      unawaited(_handlePaperOpenRequest(paperId));
    });
    _startupCommandSubscription = controller.startupCommands.listen((command) {
      unawaited(_handleStartupCommand(command));
    });
    _restartTodoReminderTimer();
  }

  @override
  void dispose() {
    _surfaceSaveDebounce?.cancel();
    _titleSurfaceDebounce?.cancel();
    _todoReminderTimer?.cancel();
    unawaited(_surfaceUpdateSubscription?.cancel());
    unawaited(_paperOpenSubscription?.cancel());
    unawaited(_startupCommandSubscription?.cancel());
    super.dispose();
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
        actions: [
          if (surfacePaper != null &&
              controller.state.showTopBarExternalOpenButton)
            IconButton(
              tooltip:
                  _tooltipLabel(enableToolTips, 'Open current paper surface'),
              onPressed: () => _openPaper(surfacePaper),
              icon: const Icon(Icons.open_in_new),
            ),
          if (controller.state.showTopBarNewTodoButton)
            IconButton(
              tooltip: _tooltipLabel(enableToolTips, 'New todo paper'),
              onPressed: () => _createPaper(PaperTypes.todo),
              icon: const Icon(Icons.add_task),
            ),
          if (controller.state.showTopBarNewNoteButton)
            IconButton(
              tooltip: _tooltipLabel(enableToolTips, 'New note paper'),
              onPressed: () => _createPaper(PaperTypes.note),
              icon: const Icon(Icons.note_add_outlined),
            ),
          if (controller.state.useCapsuleMode &&
              controller.state.useCapsuleCollapseAll)
            IconButton(
              tooltip: _tooltipLabel(
                enableToolTips,
                controller.state.capsuleCollapseAllActive
                    ? 'Expand all papers'
                    : 'Collapse all papers',
              ),
              onPressed: _toggleCollapseAll,
              icon: Icon(controller.state.capsuleCollapseAllActive
                  ? Icons.unfold_more
                  : Icons.unfold_less),
            ),
          IconButton(
            tooltip: _tooltipLabel(enableToolTips, 'Sync now'),
            onPressed: _isSyncing ? null : _syncNow,
            icon: _isSyncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_outlined),
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
        ],
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
          controller.state.capsuleCollapseAllActive,
      noteLineSpacing: controller.state.noteLineSpacing,
      onChanged: _refreshAndSaveState,
      onTitleChanged: _updatePaperTitle,
      onOpen: _openPaper,
      onRunScriptCapsule: _runScriptCapsule,
      onOpenExternalMarkdown: _openNoteMarkdownExternally,
      onHide: _hidePaper,
      onDelete: _deletePaper,
      onSurfaceChanged: _updatePaperSurface,
      onCaptureBounds: _capturePaperBounds,
    );
  }

  Future<void> _createPaper(String type) async {
    late final PaperData paper;
    setState(() {
      paper = controller.createPaper(type);
    });
    await controller.showPaper(paper);
    await _saveState();
  }

  Future<void> _toggleCollapseAll() async {
    setState(() {
      controller.state.capsuleCollapseAllActive =
          !controller.state.capsuleCollapseAllActive;
    });
    await _saveState();
  }

  Future<void> _saveState() async {
    _saveQueue = _saveQueue.catchError((_) {}).then((_) {
      return widget.store.save(controller.state).then((_) {
        return controller.rebuildTrayMenu();
      });
    });
    await _saveQueue;
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
    final detachedLinks = <_LinkedNoteRestore>[];
    setState(() {
      controller.state.papers.removeAt(removedIndex);
      if (_surfacePaperId == paper.id) {
        _surfacePaperId = null;
      }
      if (paper.isNote) {
        for (final todoPaper in controller.state.papers) {
          if (!todoPaper.isTodo) {
            continue;
          }
          for (final item in todoPaper.items) {
            if (item.linkedNoteId == paper.id) {
              detachedLinks.add(
                _LinkedNoteRestore(
                  paperId: todoPaper.id,
                  itemId: item.id,
                  noteId: paper.id,
                ),
              );
              item.linkedNoteId = null;
            }
          }
        }
      }
    });
    unawaited(_saveState());
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_displayTitle(paper)} deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              final targetIndex = removedIndex
                  .clamp(
                    0,
                    controller.state.papers.length,
                  )
                  .toInt();
              controller.state.papers.insert(targetIndex, paper);
              for (final link in detachedLinks) {
                _restoreLinkedNote(link);
              }
            });
            unawaited(_saveState());
          },
        ),
      ),
    );
  }

  Future<void> _hidePaper(PaperData paper) async {
    setState(() {
      paper.isVisible = false;
      if (_surfacePaperId == paper.id) {
        _surfacePaperId = null;
      }
    });
    await controller.hidePaper(paper);
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
      final file = _writeExternalMarkdownFile(paper);
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
        SnackBar(content: Text('External markdown open failed: $error')),
      );
    }
  }

  Future<void> _runScriptCapsule(ScriptCapsuleSpec spec) async {
    await controller.runScriptCapsule(spec);
  }

  File _writeExternalMarkdownFile(PaperData paper) {
    final directory =
        Directory(p.join(Directory.systemTemp.path, 'RePaperTodo'))
          ..createSync(recursive: true);
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

  String _safeFilename(String value) {
    return value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
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
    await controller.executeStartupCommand(command);
    if (mounted) {
      setState(() {});
    }
    await _saveState();
  }

  void _handleSurfaceUpdate(PaperData paper) {
    if (!mounted) {
      return;
    }
    setState(() {});
    _surfaceSaveDebounce?.cancel();
    _surfaceSaveDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_saveState());
    });
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

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    try {
      final result = await widget.syncService.syncNow(
        localState: controller.state,
        store: widget.store,
      );
      if (result.state != null) {
        setState(() {
          controller.replaceState(result.state!);
        });
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_syncMessage(result))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _openSettings() async {
    final previousUsePersistentPowerShellProcess =
        controller.state.usePersistentPowerShellProcess;
    final previousPreferPowerShell7 = controller.state.preferPowerShell7;
    final previousHideScriptRunWindow = controller.state.hideScriptRunWindow;
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
      return;
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
      controller.state.useCapsuleMode = result.useCapsuleMode;
      controller.state.useDeepCapsuleMode = result.useDeepCapsuleMode;
      controller.state.useCapsuleCollapseAll = result.useCapsuleCollapseAll;
      controller.state.capsuleCollapseAllActive =
          result.capsuleCollapseAllActive;
      controller.state.deepCapsuleSide = result.deepCapsuleSide;
      controller.state.deepCapsuleStartTopMargin =
          result.deepCapsuleStartTopMargin;
      controller.state.deepCapsuleMonitorDeviceName =
          result.deepCapsuleMonitorDeviceName;
      controller.state.showDeepCapsuleWhileExpanded =
          result.showDeepCapsuleWhileExpanded;
      controller.state.collapseExpandedDeepCapsuleOnClick =
          result.collapseExpandedDeepCapsuleOnClick;
      controller.state.hideDeepCapsulesWhenCovered =
          result.hideDeepCapsulesWhenCovered;
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
    await controller.setStartupAtLogin(result.startAtLogin);
    await controller.setHideFromWindowSwitcher(result.hideFromWindowSwitcher);
    await controller.setFullscreenTopmostMode(result.fullscreenTopmostMode);
    await controller.registerGlobalHotkeys();
    if (_shouldStopPersistentScriptCapsules(
      previousUsePersistentPowerShellProcess,
      previousPreferPowerShell7,
      previousHideScriptRunWindow,
      result,
    )) {
      await controller.stopPersistentScriptCapsules();
    }
    if (_shouldPreparePersistentScriptCapsules(
      previousUsePersistentPowerShellProcess,
      previousPreferPowerShell7,
      previousHideScriptRunWindow,
      result,
    )) {
      await controller.preparePersistentScriptCapsules();
    }
    widget.onAppThemeChanged?.call();
    _restartTodoReminderTimer();
    await _saveState();
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
        'Complete WebDAV sync settings first.',
      AppSyncStatus.uploaded => 'Local data uploaded.',
      AppSyncStatus.downloaded => 'Remote data downloaded.',
    };
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
    final title = paper.title.trim();
    return _shortenTitle(
      title.isEmpty ? 'Untitled' : title,
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
    if (!controller.state.useTodoReminderInterval) {
      return;
    }
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
    if (!mounted || !controller.state.useTodoReminderInterval) {
      return;
    }
    final now = DateTime.now();
    final dueItems = _dueReminderCandidates(now);
    if (dueItems.isEmpty) {
      return;
    }
    final candidates =
        controller.state.todoReminderScope == TodoReminderScopes.nearest
            ? [dueItems.first]
            : dueItems;
    final readyCandidates = candidates
        .where((candidate) => _shouldShowReminder(candidate, now))
        .toList();
    if (readyCandidates.isEmpty) {
      return;
    }
    for (final candidate in readyCandidates) {
      _lastTodoReminderAt[candidate.key] = now;
    }
    _showTodoReminder(readyCandidates);
  }

  List<_TodoReminderCandidate> _dueReminderCandidates(DateTime now) {
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
        if (dueAt == null || dueAt.isAfter(now)) {
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
    if (lastReminderAt == null) {
      return true;
    }
    return now.difference(lastReminderAt) >= _reminderInterval(candidate.item);
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
    final first = candidates.first;
    final message = candidates.length == 1
        ? 'Reminder: ${_displayTitle(first.paper)} - ${_displayItemText(first.item)}'
        : 'Reminder: ${candidates.length} todo items are due.';
    messenger.showSnackBar(
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

  String get key => '${paper.id}:${item.id}';
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

class PaperPreview extends StatelessWidget {
  const PaperPreview({
    required this.paper,
    required this.notePapers,
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
    required this.onHide,
    required this.onDelete,
    required this.onSurfaceChanged,
    required this.onCaptureBounds,
    super.key,
  });

  final PaperData paper;
  final List<PaperData> notePapers;
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
  final Future<void> Function(PaperData paper) onHide;
  final Future<void> Function(PaperData paper) onDelete;
  final Future<void> Function(PaperData paper) onSurfaceChanged;
  final Future<void> Function(PaperData paper) onCaptureBounds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCollapsed = collapseAllActive || paper.isCollapsed;
    final textZoom = paper.textZoom.clamp(0.5, 1.5).toDouble();
    return Semantics(
      label: '${paper.title} ${paper.type} paper',
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
                        : Icons.notes_outlined,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('${paper.id}-title'),
                      initialValue: paper.title,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Untitled',
                        isDense: true,
                      ),
                      style: theme.textTheme.titleMedium?.apply(
                        fontSizeFactor: textZoom,
                      ),
                      onChanged: (value) {
                        paper.title = value;
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
                  children: [
                    IconButton(
                      tooltip:
                          _tooltipLabel(enableToolTips, 'Open paper surface'),
                      onPressed: () => unawaited(onOpen(paper)),
                      icon: const Icon(Icons.open_in_new),
                    ),
                    if (paper.isNote)
                      IconButton(
                        tooltip: _tooltipLabel(
                          enableToolTips,
                          'Open markdown externally',
                        ),
                        onPressed: () =>
                            unawaited(onOpenExternalMarkdown(paper)),
                        icon: const Icon(Icons.file_open_outlined),
                      ),
                    IconButton(
                      tooltip: _tooltipLabel(
                        enableToolTips,
                        collapseAllActive
                            ? 'Collapse all is active'
                            : paper.isCollapsed
                                ? 'Expand paper'
                                : 'Collapse paper',
                      ),
                      onPressed: collapseAllActive
                          ? null
                          : () {
                              paper.isCollapsed = !paper.isCollapsed;
                              unawaited(onChanged());
                            },
                      icon: Icon(
                          isCollapsed ? Icons.expand_more : Icons.expand_less),
                    ),
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
                        paper.alwaysOnTop
                            ? 'Disable always on top'
                            : 'Keep on top',
                      ),
                      onPressed: () {
                        paper.alwaysOnTop = !paper.alwaysOnTop;
                        if (paper.alwaysOnTop) {
                          paper.isPinnedToDesktop = false;
                        }
                        unawaited(onSurfaceChanged(paper));
                        unawaited(onChanged());
                      },
                      icon: Icon(paper.alwaysOnTop
                          ? Icons.push_pin
                          : Icons.push_pin_outlined),
                    ),
                    IconButton(
                      tooltip: _tooltipLabel(
                        enableToolTips,
                        paper.isPinnedToDesktop
                            ? 'Unpin from desktop'
                            : 'Pin to desktop',
                      ),
                      onPressed: () {
                        paper.isPinnedToDesktop = !paper.isPinnedToDesktop;
                        if (paper.isPinnedToDesktop) {
                          paper.alwaysOnTop = false;
                        }
                        unawaited(onSurfaceChanged(paper));
                        unawaited(onChanged());
                      },
                      icon: Icon(paper.isPinnedToDesktop
                          ? Icons.desktop_windows
                          : Icons.desktop_windows_outlined),
                    ),
                    IconButton(
                      tooltip:
                          _tooltipLabel(enableToolTips, 'Save window bounds'),
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
                  ],
                ),
              ),
              _animatedPaperBody(isCollapsed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _animatedPaperBody(bool isCollapsed) {
    final body = isCollapsed
        ? const SizedBox.shrink(key: ValueKey('collapsed'))
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
                )
              else
                _NoteEditor(
                  paper: paper,
                  markdownRenderMode: markdownRenderMode,
                  lineSpacing: noteLineSpacing,
                  textZoom: paper.textZoom,
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

  void _setTextZoom(double value) {
    paper.textZoom = value.clamp(0.5, 1.5).toDouble();
    unawaited(onSurfaceChanged(paper));
    unawaited(onChanged());
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
    required this.onChanged,
  });

  final PaperData paper;
  final String markdownRenderMode;
  final double lineSpacing;
  final double textZoom;
  final Future<void> Function() onChanged;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  static const _viewEdit = 'edit';
  static const _viewPreview = 'preview';
  static const _viewSplit = 'split';

  late String _view = _defaultView(widget.markdownRenderMode);
  String? _selectedCanvasElementId;

  @override
  void didUpdateWidget(covariant _NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdownRenderMode != widget.markdownRenderMode) {
      _view = _defaultView(widget.markdownRenderMode);
    }
    if (_selectedCanvasElementId != null &&
        !widget.paper.noteCanvasElements.any(
          (element) => element.id == _selectedCanvasElementId,
        )) {
      _selectedCanvasElementId = null;
    }
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
    return TextFormField(
      key: ValueKey('${widget.paper.id}-content'),
      initialValue: widget.paper.content,
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
      ],
      onChanged: (value) {
        setState(() => widget.paper.content = value);
        unawaited(widget.onChanged());
      },
    );
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
    return DecoratedBox(
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
    );
  }

  String _safeView(String mode) {
    if (_view == _viewSplit && mode != MarkdownRenderModes.enhanced) {
      return _viewEdit;
    }
    return _view;
  }

  String _defaultView(String mode) {
    return MarkdownRenderModes.normalize(mode) == MarkdownRenderModes.enhanced
        ? _viewSplit
        : _viewEdit;
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
      onSelect: _selectCanvasElement,
      onEdit: _editCanvasElement,
      onDuplicate: _duplicateCanvasElement,
      onLayerAction: _applyCanvasLayerAction,
      onDelete: _deleteCanvasElement,
    );
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
    final maxLayer = elements.fold<int>(
      0,
      (max, element) => element.zIndex > max ? element.zIndex : max,
    );
    setState(() {
      final elementId = _newCanvasElementId();
      elements.add(
        NoteCanvasElement(
          id: elementId,
          type: normalizedType,
          text: normalizedType == NoteCanvasElementTypes.text
              ? 'Canvas text $nextIndex'
              : 'Console.WriteLine("PaperTodo");',
          x: 32.0 + elements.length * 16.0,
          y: 32.0 + elements.length * 16.0,
          width: 230,
          height: 116,
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
    final maxLayer = elements.fold<int>(
      0,
      (max, candidate) => candidate.zIndex > max ? candidate.zIndex : max,
    );
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
    final minLayer = elements.fold<int>(
      element.zIndex,
      (min, candidate) => candidate.zIndex < min ? candidate.zIndex : min,
    );
    final maxLayer = elements.fold<int>(
      element.zIndex,
      (max, candidate) => candidate.zIndex > max ? candidate.zIndex : max,
    );
    setState(() {
      switch (action) {
        case _CanvasLayerAction.bringForward:
          if (elementIndex >= 0 && elementIndex < orderedElements.length - 1) {
            final nextElement = orderedElements[elementIndex + 1];
            final currentLayer = element.zIndex;
            element.zIndex = nextElement.zIndex;
            nextElement.zIndex = currentLayer;
          }
          break;
        case _CanvasLayerAction.sendBackward:
          if (elementIndex > 0) {
            final previousElement = orderedElements[elementIndex - 1];
            final currentLayer = element.zIndex;
            element.zIndex = previousElement.zIndex;
            previousElement.zIndex = currentLayer;
          }
          break;
        case _CanvasLayerAction.bringToFront:
          element.zIndex = (maxLayer + 10).clamp(-10000, 10000).toInt();
          break;
        case _CanvasLayerAction.sendToBack:
          element.zIndex = (minLayer - 10).clamp(-10000, 10000).toInt();
          break;
      }
      _selectedCanvasElementId = element.id;
    });
    unawaited(widget.onChanged());
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
}

class _NoteCanvasPreview extends StatelessWidget {
  const _NoteCanvasPreview({
    required this.elements,
    required this.selectedElementId,
    required this.textZoom,
    required this.onChanged,
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
          return SizedBox(
            height: (contentHeight * scale).clamp(120, 640).toDouble(),
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
                      textZoom: textZoom,
                      onChanged: onChanged,
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

class _NoteCanvasElementPreview extends StatelessWidget {
  const _NoteCanvasElementPreview({
    required this.element,
    required this.layerRank,
    required this.layerCount,
    required this.isSelected,
    required this.scale,
    required this.textZoom,
    required this.onChanged,
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
  final double textZoom;
  final Future<void> Function() onChanged;
  final void Function(NoteCanvasElement element) onSelect;
  final Future<void> Function(NoteCanvasElement element) onEdit;
  final void Function(NoteCanvasElement element) onDuplicate;
  final void Function(NoteCanvasElement element, _CanvasLayerAction action)
      onLayerAction;
  final void Function(NoteCanvasElement element) onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCode = element.type == NoteCanvasElementTypes.code;
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.apply(fontSizeFactor: textZoom)
        .copyWith(fontFamily: isCode ? 'monospace' : null);
    final typeLabel = _noteCanvasElementTypeLabel(element.type);
    final layerLabel = _noteCanvasLayerLabel(layerRank, layerCount);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border.all(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.18),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.all((8 * scale).clamp(4, 8).toDouble()),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: (6 * scale).clamp(3, 6).toDouble(),
                    runSpacing: (4 * scale).clamp(2, 4).toDouble(),
                    children: [
                      _NoteCanvasElementBadge(
                        label: typeLabel,
                        scale: scale,
                        color: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.onPrimaryContainer,
                      ),
                      _NoteCanvasElementBadge(
                        label: layerLabel,
                        scale: scale,
                        color: colorScheme.secondaryContainer,
                        foregroundColor: colorScheme.onSecondaryContainer,
                      ),
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: (28 * scale).clamp(24, 28).toDouble(),
                  child: IconButton(
                    tooltip: 'Edit canvas geometry',
                    onPressed: () {
                      onSelect(element);
                      unawaited(onEdit(element));
                    },
                    iconSize: (18 * scale).clamp(16, 18).toDouble(),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.tune_outlined),
                  ),
                ),
                SizedBox.square(
                  dimension: (28 * scale).clamp(24, 28).toDouble(),
                  child: IconButton(
                    tooltip: 'Duplicate canvas block',
                    onPressed: () {
                      onSelect(element);
                      onDuplicate(element);
                    },
                    iconSize: (18 * scale).clamp(16, 18).toDouble(),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.content_copy_outlined),
                  ),
                ),
                SizedBox.square(
                  dimension: (28 * scale).clamp(24, 28).toDouble(),
                  child: PopupMenuButton<_CanvasLayerAction>(
                    key: ValueKey('note-canvas-layer-actions-${element.id}'),
                    tooltip: 'Canvas layer actions',
                    icon: const Icon(Icons.layers_outlined),
                    iconSize: (18 * scale).clamp(16, 18).toDouble(),
                    padding: EdgeInsets.zero,
                    onSelected: (action) {
                      onSelect(element);
                      onLayerAction(element, action);
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
                  dimension: (28 * scale).clamp(24, 28).toDouble(),
                  child: IconButton(
                    tooltip: 'Delete canvas block',
                    onPressed: () {
                      onSelect(element);
                      onDelete(element);
                    },
                    iconSize: (18 * scale).clamp(16, 18).toDouble(),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close_outlined),
                  ),
                ),
              ],
            ),
            Expanded(
              child: TextFormField(
                key: ValueKey('note-canvas-element-text-${element.id}'),
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
                onTap: () => onSelect(element),
                onChanged: (value) {
                  element.text = value;
                  unawaited(onChanged());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
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

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<_TodoEditor> {
  static const _maxTodoUndoDepth = 100;

  final _todoFocusNode = FocusNode(debugLabel: 'todo-editor');
  final _undoStack = <List<Map<String, Object?>>>[];
  final _redoStack = <List<Map<String, Object?>>>[];
  var _textFieldRevision = 0;

  @override
  void dispose() {
    _todoFocusNode.dispose();
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
    final editor = Column(
      children: [
        for (final item in widget.paper.items)
          Padding(
            padding: EdgeInsets.only(bottom: visualSpec.itemGap),
            child: Row(
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
                          if (_formatDueDate(item.dueAtLocal)
                              case final dueDate?)
                            InputChip(
                              avatar: Icon(Icons.event_outlined,
                                  size: visualSpec.chipIconSize),
                              label: Text('Due $dueDate'),
                              onDeleted: () => _clearDueDate(item),
                              deleteIcon: Icon(Icons.close_outlined,
                                  size: visualSpec.chipIconSize),
                              deleteButtonTooltipMessage: _tooltipLabel(
                                  widget.enableToolTips, 'Clear due date'),
                            ),
                          if (_formatReminderInterval(item)
                              case final reminderInterval?)
                            InputChip(
                              avatar: Icon(Icons.notifications_active_outlined,
                                  size: visualSpec.chipIconSize),
                              label: Text(reminderInterval),
                              onDeleted: () => _clearReminderInterval(item),
                              deleteIcon: Icon(Icons.close_outlined,
                                  size: visualSpec.chipIconSize),
                              deleteButtonTooltipMessage: _tooltipLabel(
                                  widget.enableToolTips,
                                  'Clear reminder interval'),
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
                  tooltip: _tooltipLabel(
                      widget.enableToolTips, 'Set reminder interval'),
                  onPressed: () =>
                      unawaited(_pickReminderInterval(context, item)),
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
                        enabled: item.todoColumnCount < 8,
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
                      widget.notePapers.isNotEmpty,
                  iconSize: visualSpec.iconSize,
                  icon: Icon(item.linkedNoteId == null
                      ? Icons.note_add_outlined
                      : Icons.link_outlined),
                  onSelected: (noteId) => _linkNote(item, noteId),
                  itemBuilder: (context) {
                    return [
                      for (final note in widget.notePapers)
                        PopupMenuItem(
                          value: note.id,
                          child: Text(_displayPaperTitle(note)),
                        ),
                    ];
                  },
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
              ],
            ),
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
                tooltip:
                    _tooltipLabel(widget.enableToolTips, 'Undo todo change'),
                onPressed: _undoStack.isEmpty ? null : _undoTodoChange,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip:
                    _tooltipLabel(widget.enableToolTips, 'Redo todo change'),
                onPressed: _redoStack.isEmpty ? null : _redoTodoChange,
                icon: const Icon(Icons.redo),
              ),
            ],
          ),
        ),
      ],
    );
    return Focus(
      focusNode: _todoFocusNode,
      autofocus: true,
      onKeyEvent: _handleTodoKeyEvent,
      child: editor,
    );
  }

  static const _columnActionAdd = 'add';
  static const _columnActionRemove = 'remove';
  static const _columnActionEqualWidths = 'equal-widths';
  static const _columnActionWideFirst = 'wide-first';

  List<Map<String, Object?>> _snapshotTodoItems() {
    return [
      for (final item in widget.paper.items)
        Map<String, Object?>.from(item.toJson()),
    ];
  }

  void _pushTodoUndoSnapshot() {
    _undoStack.add(_snapshotTodoItems());
    if (_undoStack.length > _maxTodoUndoDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _restoreTodoSnapshot(List<Map<String, Object?>> snapshot) {
    setState(() {
      widget.paper.items = [
        for (final itemJson in snapshot)
          PaperItem.fromJson(Map<String, Object?>.from(itemJson)),
      ];
      widget.paper.normalize();
      _textFieldRevision++;
    });
    _requestTodoFocus();
    unawaited(widget.onChanged());
  }

  void _requestTodoFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _todoFocusNode.requestFocus();
      }
    });
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
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  flex: _columnFlex(item, index),
                  child: fields[index],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _mainColumnField(
    BuildContext context,
    PaperItem item,
    TextStyle? itemTextStyle,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return KeyedSubtree(
      key: ValueKey('${widget.paper.id}-${item.id}-text'),
      child: TextFormField(
        key: ValueKey(
          '${widget.paper.id}-${item.id}-text-field-$_textFieldRevision',
        ),
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
        onFieldSubmitted: (_) => _addItem(),
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
    return TextFormField(
      key: ValueKey(
        '${widget.paper.id}-${item.id}-column-${index + 2}',
      ),
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
      if (action == _columnActionAdd && item.todoColumnCount < 8) {
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
    unawaited(widget.onChanged());
  }

  void _addItem() {
    _pushTodoUndoSnapshot();
    final inheritedItem =
        widget.paper.items.isEmpty ? null : widget.paper.items.last;
    final inheritedColumnCount = inheritedItem?.todoColumnCount ?? 1;
    final inheritedColumnWidths =
        inheritedItem?.todoColumnWidths.length == inheritedColumnCount
            ? inheritedItem!.todoColumnWidths
            : <double>[];
    setState(() {
      widget.paper.items.add(
        PaperItem(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          order: widget.paper.items.length,
          todoColumnCount: inheritedColumnCount,
          todoExtraColumns: List.filled(inheritedColumnCount - 1, ''),
          todoColumnWidths: [...inheritedColumnWidths],
        ),
      );
      widget.paper.normalize();
    });
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

  void _deleteItem(BuildContext context, PaperItem item) {
    final removedIndex = widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (removedIndex < 0 || widget.paper.items.length <= 1) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      widget.paper.items.removeAt(removedIndex);
      widget.paper.normalize();
    });
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
            unawaited(widget.onChanged());
          },
        ),
      ),
    );
  }

  Future<void> _pickDueDate(BuildContext context, PaperItem item) async {
    final initialDate =
        DateTime.tryParse(item.dueAtLocal ?? '')?.toLocal() ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) {
      return;
    }
    _pushTodoUndoSnapshot();
    setState(() {
      item.dueAtLocal =
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day)
              .toIso8601String();
    });
    unawaited(widget.onChanged());
  }

  void _clearDueDate(PaperItem item) {
    _pushTodoUndoSnapshot();
    setState(() => item.dueAtLocal = null);
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
    unawaited(widget.onChanged());
  }

  void _clearReminderInterval(PaperItem item) {
    _pushTodoUndoSnapshot();
    setState(() {
      item.reminderIntervalValue = null;
      item.reminderIntervalUnit = null;
    });
    unawaited(widget.onChanged());
  }

  void _linkNote(PaperItem item, String noteId) {
    _pushTodoUndoSnapshot();
    setState(() => item.linkedNoteId = noteId);
    unawaited(widget.onChanged());
  }

  void _clearLinkedNote(PaperItem item) {
    _pushTodoUndoSnapshot();
    setState(() => item.linkedNoteId = null);
    unawaited(widget.onChanged());
  }

  PaperData? _linkedNoteFor(PaperItem item) {
    final noteId = item.linkedNoteId;
    if (noteId == null) {
      return null;
    }
    for (final note in widget.notePapers) {
      if (note.id == noteId) {
        return note;
      }
    }
    return null;
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
    final title = paper.title.trim();
    return title.isEmpty ? 'Untitled' : title;
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
    return switch (TodoDueYearDisplayModes.normalize(
      widget.dueYearDisplayMode,
    )) {
      TodoDueYearDisplayModes.short =>
        '${(date.year % 100).toString().padLeft(2, '0')}-$month-$day',
      TodoDueYearDisplayModes.full => '${date.year}-$month-$day',
      _ => '$month-$day',
    };
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
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(date.year, date.month, date.day);
    final days = dueDay.difference(today).inDays;
    return switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      > 1 => 'In $days days',
      _ => '${-days} days overdue',
    };
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
