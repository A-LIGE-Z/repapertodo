import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'app_controller.dart';
import 'core/model/app_state.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
import 'core/model/paper_item.dart';
import 'core/storage/state_store.dart';
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
        seedColor: _seedColor(state.colorScheme),
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

  Color _seedColor(String colorSchemeId) {
    return switch (ColorSchemes.normalize(colorSchemeId)) {
      ColorSchemes.ink => const Color(0xFF4F6D7A),
      ColorSchemes.forest => const Color(0xFF2E7D32),
      ColorSchemes.rose => const Color(0xFFC85A7C),
      _ => const Color(0xFFE07A5F),
    };
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
    _restartTodoReminderTimer();
  }

  @override
  void dispose() {
    _surfaceSaveDebounce?.cancel();
    _titleSurfaceDebounce?.cancel();
    _todoReminderTimer?.cancel();
    unawaited(_surfaceUpdateSubscription?.cancel());
    unawaited(_paperOpenSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                tooltip: 'Back to board',
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
              tooltip: 'Open current paper surface',
              onPressed: () => _openPaper(surfacePaper),
              icon: const Icon(Icons.open_in_new),
            ),
          if (controller.state.showTopBarNewTodoButton)
            IconButton(
              tooltip: 'New todo paper',
              onPressed: () => _createPaper(PaperTypes.todo),
              icon: const Icon(Icons.add_task),
            ),
          if (controller.state.showTopBarNewNoteButton)
            IconButton(
              tooltip: 'New note paper',
              onPressed: () => _createPaper(PaperTypes.note),
              icon: const Icon(Icons.note_add_outlined),
            ),
          if (controller.state.useCapsuleCollapseAll)
            IconButton(
              tooltip: controller.state.capsuleCollapseAllActive
                  ? 'Expand all papers'
                  : 'Collapse all papers',
              onPressed: _toggleCollapseAll,
              icon: Icon(controller.state.capsuleCollapseAllActive
                  ? Icons.unfold_more
                  : Icons.unfold_less),
            ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: _isSyncing ? null : _syncNow,
            icon: _isSyncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_outlined),
          ),
          IconButton(
            tooltip: 'Show hidden papers',
            onPressed: hiddenPapers.isEmpty ? null : _showHiddenPapers,
            icon: const Icon(Icons.visibility_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
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
      markdownRenderMode: controller.state.markdownRenderMode,
      todoVisualSize: controller.state.todoVisualSize,
      todoLineSpacing: controller.state.todoLineSpacing,
      showTodoDueRelativeTime: controller.state.showTodoDueRelativeTime,
      todoDueYearDisplayMode: controller.state.todoDueYearDisplayMode,
      collapseAllActive: controller.state.useCapsuleCollapseAll &&
          controller.state.capsuleCollapseAllActive,
      noteLineSpacing: controller.state.noteLineSpacing,
      onChanged: _refreshAndSaveState,
      onTitleChanged: _updatePaperTitle,
      onOpen: _openPaper,
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
    final result = await showSyncSettingsDialog(
      context: context,
      initialSettings: controller.state.sync,
      initialTheme: controller.state.theme,
      initialColorScheme: controller.state.colorScheme,
      initialMarkdownRenderMode: controller.state.markdownRenderMode,
      initialTodoVisualSize: controller.state.todoVisualSize,
      initialUiFontPreset: controller.state.uiFontPreset,
      initialSystemFontFamilyName: controller.state.systemFontFamilyName,
      initialZoom: controller.state.zoom,
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
      initialUseCapsuleCollapseAll: controller.state.useCapsuleCollapseAll,
      initialCapsuleCollapseAllActive:
          controller.state.capsuleCollapseAllActive,
      initialStartAtLogin: controller.state.startAtLogin,
      initialHideFromWindowSwitcher:
          controller.state.hidePapersFromWindowSwitcher,
      initialFullscreenTopmostMode: controller.state.fullscreenTopmostMode,
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
      controller.state.markdownRenderMode = result.markdownRenderMode;
      controller.state.todoVisualSize = result.todoVisualSize;
      controller.state.uiFontPreset = result.uiFontPreset;
      controller.state.systemFontFamilyName = result.systemFontFamilyName;
      controller.state.zoom = result.zoom;
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
      controller.state.useCapsuleCollapseAll = result.useCapsuleCollapseAll;
      controller.state.capsuleCollapseAllActive =
          result.capsuleCollapseAllActive;
      controller.state.startAtLogin = result.startAtLogin;
      controller.state.hidePapersFromWindowSwitcher =
          result.hideFromWindowSwitcher;
      controller.state.fullscreenTopmostMode = result.fullscreenTopmostMode;
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
    widget.onAppThemeChanged?.call();
    _restartTodoReminderTimer();
    await _saveState();
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
    return title.isEmpty ? 'Untitled' : title;
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
  final Future<void> Function(PaperData paper) onHide;
  final Future<void> Function(PaperData paper) onDelete;
  final Future<void> Function(PaperData paper) onSurfaceChanged;
  final Future<void> Function(PaperData paper) onCaptureBounds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCollapsed = collapseAllActive || paper.isCollapsed;
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
                      style: theme.textTheme.titleMedium,
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
                      tooltip: 'Open paper surface',
                      onPressed: () => unawaited(onOpen(paper)),
                      icon: const Icon(Icons.open_in_new),
                    ),
                    IconButton(
                      tooltip: collapseAllActive
                          ? 'Collapse all is active'
                          : paper.isCollapsed
                              ? 'Expand paper'
                              : 'Collapse paper',
                      onPressed: collapseAllActive
                          ? null
                          : () {
                              paper.isCollapsed = !paper.isCollapsed;
                              unawaited(onChanged());
                            },
                      icon: Icon(
                          isCollapsed ? Icons.expand_more : Icons.expand_less),
                    ),
                    IconButton(
                      tooltip: paper.alwaysOnTop
                          ? 'Disable always on top'
                          : 'Keep on top',
                      onPressed: () {
                        paper.alwaysOnTop = !paper.alwaysOnTop;
                        unawaited(onSurfaceChanged(paper));
                        unawaited(onChanged());
                      },
                      icon: Icon(paper.alwaysOnTop
                          ? Icons.push_pin
                          : Icons.push_pin_outlined),
                    ),
                    IconButton(
                      tooltip: 'Save window bounds',
                      onPressed: () => unawaited(onCaptureBounds(paper)),
                      icon: const Icon(Icons.aspect_ratio_outlined),
                    ),
                    IconButton(
                      tooltip: 'Hide paper',
                      onPressed: () => unawaited(onHide(paper)),
                      icon: const Icon(Icons.visibility_off_outlined),
                    ),
                    IconButton(
                      tooltip: 'Delete paper',
                      onPressed: () => unawaited(onDelete(paper)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
              if (!isCollapsed) ...[
                const SizedBox(height: 12),
                if (paper.isTodo)
                  _TodoEditor(
                    paper: paper,
                    notePapers: notePapers,
                    enableTodoNoteLinks: enableTodoNoteLinks,
                    showLinkedNoteName: showLinkedNoteName,
                    allowLongLinkedNoteTitles: allowLongLinkedNoteTitles,
                    visualSize: todoVisualSize,
                    lineSpacing: todoLineSpacing,
                    showDueRelativeTime: showTodoDueRelativeTime,
                    dueYearDisplayMode: todoDueYearDisplayMode,
                    onOpen: onOpen,
                    onChanged: onChanged,
                  )
                else
                  _NoteEditor(
                    paper: paper,
                    markdownRenderMode: markdownRenderMode,
                    lineSpacing: noteLineSpacing,
                    onChanged: onChanged,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    required this.paper,
    required this.markdownRenderMode,
    required this.lineSpacing,
    required this.onChanged,
  });

  final PaperData paper;
  final String markdownRenderMode;
  final double lineSpacing;
  final Future<void> Function() onChanged;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  static const _viewEdit = 'edit';
  static const _viewPreview = 'preview';
  static const _viewSplit = 'split';

  late String _view = _defaultView(widget.markdownRenderMode);

  @override
  void didUpdateWidget(covariant _NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdownRenderMode != widget.markdownRenderMode) {
      _view = _defaultView(widget.markdownRenderMode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = MarkdownRenderModes.normalize(widget.markdownRenderMode);
    if (mode == MarkdownRenderModes.off) {
      return _editor(context, minLines: 4, maxLines: 12);
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
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: widget.lineSpacing,
          ),
      onChanged: (value) {
        widget.paper.content = value;
        unawaited(widget.onChanged());
      },
    );
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
                    p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: widget.lineSpacing,
                        )),
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
}

class _TodoEditor extends StatefulWidget {
  const _TodoEditor({
    required this.paper,
    required this.notePapers,
    required this.enableTodoNoteLinks,
    required this.showLinkedNoteName,
    required this.allowLongLinkedNoteTitles,
    required this.visualSize,
    required this.lineSpacing,
    required this.showDueRelativeTime,
    required this.dueYearDisplayMode,
    required this.onOpen,
    required this.onChanged,
  });

  final PaperData paper;
  final List<PaperData> notePapers;
  final bool enableTodoNoteLinks;
  final bool showLinkedNoteName;
  final bool allowLongLinkedNoteTitles;
  final String visualSize;
  final double lineSpacing;
  final bool showDueRelativeTime;
  final String dueYearDisplayMode;
  final Future<void> Function(PaperData paper) onOpen;
  final Future<void> Function() onChanged;

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<_TodoEditor> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visualSpec = _TodoVisualSpec.from(widget.visualSize);
    final itemTextStyle = theme.textTheme.bodyMedium
        ?.apply(fontSizeFactor: visualSpec.textScale)
        .copyWith(
          height: widget.lineSpacing,
        );
    return Column(
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
                      TextFormField(
                        key: ValueKey('${widget.paper.id}-${item.id}-text'),
                        initialValue: item.text,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'New item',
                          isDense: true,
                        ),
                        style: itemTextStyle?.copyWith(
                          color: item.done
                              ? colorScheme.outline
                              : colorScheme.onSurface,
                          decoration:
                              item.done ? TextDecoration.lineThrough : null,
                        ),
                        onChanged: (value) {
                          item.text = value;
                          unawaited(widget.onChanged());
                        },
                        onFieldSubmitted: (_) => _addItem(),
                      ),
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
                              deleteButtonTooltipMessage: 'Clear due date',
                            ),
                          if (widget.enableTodoNoteLinks)
                            if (_linkedNoteFor(item) case final linkedNote?)
                              InputChip(
                                avatar: Icon(Icons.notes_outlined,
                                    size: visualSpec.chipIconSize),
                                label: Text(_noteChipLabel(linkedNote)),
                                onPressed: () =>
                                    unawaited(widget.onOpen(linkedNote)),
                                onDeleted: () => _clearLinkedNote(item),
                                deleteIcon: Icon(Icons.close_outlined,
                                    size: visualSpec.chipIconSize),
                                deleteButtonTooltipMessage: 'Unlink note',
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Set due date',
                  onPressed: () => unawaited(_pickDueDate(context, item)),
                  iconSize: visualSpec.iconSize,
                  constraints: BoxConstraints.tightFor(
                    width: visualSpec.controlExtent,
                    height: visualSpec.controlExtent,
                  ),
                  icon: const Icon(Icons.event_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Link note',
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
                  tooltip: 'Delete item',
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
          child: TextButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ),
      ],
    );
  }

  void _addItem() {
    setState(() {
      widget.paper.items.add(
        PaperItem(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          order: widget.paper.items.length,
        ),
      );
      widget.paper.normalize();
    });
    unawaited(widget.onChanged());
  }

  void _deleteItem(BuildContext context, PaperItem item) {
    final removedIndex = widget.paper.items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (removedIndex < 0 || widget.paper.items.length <= 1) {
      return;
    }
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
    setState(() {
      item.dueAtLocal =
          DateTime(pickedDate.year, pickedDate.month, pickedDate.day)
              .toIso8601String();
    });
    unawaited(widget.onChanged());
  }

  void _clearDueDate(PaperItem item) {
    setState(() => item.dueAtLocal = null);
    unawaited(widget.onChanged());
  }

  void _linkNote(PaperItem item, String noteId) {
    setState(() => item.linkedNoteId = noteId);
    unawaited(widget.onChanged());
  }

  void _clearLinkedNote(PaperItem item) {
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

  String _noteChipLabel(PaperData note) {
    if (!widget.showLinkedNoteName) {
      return 'Note';
    }
    final title = _displayPaperTitle(note);
    if (widget.allowLongLinkedNoteTitles || title.length <= 24) {
      return 'Note $title';
    }
    return 'Note ${title.substring(0, 23)}...';
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
