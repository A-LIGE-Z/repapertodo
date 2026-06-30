import 'dart:async';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
import 'core/model/paper_item.dart';
import 'core/storage/state_store.dart';
import 'sync/app_sync_service.dart';
import 'ui/sync_settings_dialog.dart';

class RePaperTodoApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RePaperTodo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B7CFA)),
        useMaterial3: true,
      ),
      home: PaperBoardScreen(
        controller: controller,
        store: store,
        syncService: syncService ?? AppSyncService(),
      ),
    );
  }
}

class PaperBoardScreen extends StatefulWidget {
  const PaperBoardScreen({
    required this.controller,
    required this.store,
    required this.syncService,
    super.key,
  });

  final RePaperTodoController controller;
  final StateStore store;
  final AppSyncService syncService;

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

  RePaperTodoController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _surfaceUpdateSubscription =
        controller.paperSurfaceUpdates.listen(_handleSurfaceUpdate);
    _paperOpenSubscription = controller.paperOpenRequests.listen((paperId) {
      unawaited(_handlePaperOpenRequest(paperId));
    });
  }

  @override
  void dispose() {
    _surfaceSaveDebounce?.cancel();
    _titleSurfaceDebounce?.cancel();
    unawaited(_surfaceUpdateSubscription?.cancel());
    unawaited(_paperOpenSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visiblePapers =
        controller.state.papers.where((paper) => paper.isVisible).toList();
    final hiddenPapers =
        controller.state.papers.where((paper) => !paper.isVisible).toList();
    final notePapers =
        controller.state.papers.where((paper) => paper.isNote).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('RePaperTodo'),
        actions: [
          IconButton(
            tooltip: 'New todo paper',
            onPressed: () => _createPaper(PaperTypes.todo),
            icon: const Icon(Icons.add_task),
          ),
          IconButton(
            tooltip: 'New note paper',
            onPressed: () => _createPaper(PaperTypes.note),
            icon: const Icon(Icons.note_add_outlined),
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
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: visiblePapers.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return PaperPreview(
              paper: visiblePapers[index],
              notePapers: notePapers,
              onChanged: _refreshAndSaveState,
              onTitleChanged: _updatePaperTitle,
              onOpen: _openPaper,
              onHide: _hidePaper,
              onDelete: _deletePaper,
              onSurfaceChanged: _updatePaperSurface,
              onCaptureBounds: _capturePaperBounds,
            );
          },
        ),
      ),
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
    setState(() {
      controller.state.papers.removeAt(removedIndex);
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
    });
    await controller.hidePaper(paper);
    await _saveState();
  }

  Future<void> _openPaper(PaperData paper) async {
    setState(() {
      paper.isVisible = true;
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
      initialStartAtLogin: controller.state.startAtLogin,
      initialHideFromWindowSwitcher:
          controller.state.hidePapersFromWindowSwitcher,
      initialFullscreenTopmostMode: controller.state.fullscreenTopmostMode,
    );
    if (result == null) {
      return;
    }
    setState(() {
      controller.state.sync = result.sync;
      controller.state.startAtLogin = result.startAtLogin;
      controller.state.hidePapersFromWindowSwitcher =
          result.hideFromWindowSwitcher;
      controller.state.fullscreenTopmostMode = result.fullscreenTopmostMode;
    });
    await controller.setStartupAtLogin(result.startAtLogin);
    await controller.setHideFromWindowSwitcher(result.hideFromWindowSwitcher);
    await controller.setFullscreenTopmostMode(result.fullscreenTopmostMode);
    await widget.store.save(controller.state);
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
}

class PaperPreview extends StatelessWidget {
  const PaperPreview({
    required this.paper,
    required this.notePapers,
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
                      tooltip:
                          paper.isCollapsed ? 'Expand paper' : 'Collapse paper',
                      onPressed: () {
                        paper.isCollapsed = !paper.isCollapsed;
                        unawaited(onChanged());
                      },
                      icon: Icon(paper.isCollapsed
                          ? Icons.expand_more
                          : Icons.expand_less),
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
              if (!paper.isCollapsed) ...[
                const SizedBox(height: 12),
                if (paper.isTodo)
                  _TodoEditor(
                    paper: paper,
                    notePapers: notePapers,
                    onOpen: onOpen,
                    onChanged: onChanged,
                  )
                else
                  TextFormField(
                    key: ValueKey('${paper.id}-content'),
                    initialValue: paper.content,
                    minLines: 4,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Write a note...',
                    ),
                    style: theme.textTheme.bodyMedium,
                    onChanged: (value) {
                      paper.content = value;
                      unawaited(onChanged());
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TodoEditor extends StatefulWidget {
  const _TodoEditor({
    required this.paper,
    required this.notePapers,
    required this.onOpen,
    required this.onChanged,
  });

  final PaperData paper;
  final List<PaperData> notePapers;
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
    return Column(
      children: [
        for (final item in widget.paper.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: item.done,
                  onChanged: (value) {
                    setState(() => item.done = value ?? false);
                    unawaited(widget.onChanged());
                  },
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
                        style: theme.textTheme.bodyMedium?.copyWith(
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
                              avatar:
                                  const Icon(Icons.event_outlined, size: 18),
                              label: Text('Due $dueDate'),
                              onDeleted: () => _clearDueDate(item),
                              deleteIcon:
                                  const Icon(Icons.close_outlined, size: 18),
                              deleteButtonTooltipMessage: 'Clear due date',
                            ),
                          if (_linkedNoteFor(item) case final linkedNote?)
                            InputChip(
                              avatar:
                                  const Icon(Icons.notes_outlined, size: 18),
                              label: Text(_noteChipLabel(linkedNote)),
                              onPressed: () =>
                                  unawaited(widget.onOpen(linkedNote)),
                              onDeleted: () => _clearLinkedNote(item),
                              deleteIcon:
                                  const Icon(Icons.close_outlined, size: 18),
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
                  icon: const Icon(Icons.event_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Link note',
                  enabled: widget.notePapers.isNotEmpty,
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
    return 'Note ${_displayPaperTitle(note)}';
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
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
