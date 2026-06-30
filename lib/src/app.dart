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

  RePaperTodoController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visiblePapers =
        controller.state.papers.where((paper) => paper.isVisible).toList();
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
              onChanged: _saveState,
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
    setState(() {
      controller.createPaper(type);
    });
    await widget.store.save(controller.state);
  }

  Future<void> _saveState() async {
    _saveQueue = _saveQueue.catchError((_) {}).then((_) {
      return widget.store.save(controller.state);
    });
    await _saveQueue;
  }

  Future<void> _deletePaper(PaperData paper) async {
    setState(() {
      controller.state.papers.removeWhere(
        (candidate) => candidate.id == paper.id,
      );
    });
    await _saveState();
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
    final settings = await showSyncSettingsDialog(
      context: context,
      initialSettings: controller.state.sync,
    );
    if (settings == null) {
      return;
    }
    setState(() {
      controller.state.sync = settings;
    });
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
}

class PaperPreview extends StatelessWidget {
  const PaperPreview({
    required this.paper,
    required this.onChanged,
    required this.onDelete,
    required this.onSurfaceChanged,
    required this.onCaptureBounds,
    super.key,
  });

  final PaperData paper;
  final Future<void> Function() onChanged;
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
                        unawaited(onChanged());
                      },
                    ),
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
                    tooltip: 'Delete paper',
                    onPressed: () => unawaited(onDelete(paper)),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (paper.isTodo)
                _TodoEditor(
                  paper: paper,
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
          ),
        ),
      ),
    );
  }
}

class _TodoEditor extends StatefulWidget {
  const _TodoEditor({
    required this.paper,
    required this.onChanged,
  });

  final PaperData paper;
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
              children: [
                Checkbox(
                  value: item.done,
                  onChanged: (value) {
                    setState(() => item.done = value ?? false);
                    unawaited(widget.onChanged());
                  },
                ),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('${widget.paper.id}-${item.id}-text'),
                    initialValue: item.text,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'New item',
                      isDense: true,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: item.done
                          ? colorScheme.outline
                          : colorScheme.onSurface,
                      decoration: item.done ? TextDecoration.lineThrough : null,
                    ),
                    onChanged: (value) {
                      item.text = value;
                      unawaited(widget.onChanged());
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Delete item',
                  onPressed: widget.paper.items.length <= 1
                      ? null
                      : () {
                          setState(() {
                            widget.paper.items.removeWhere(
                              (candidate) => candidate.id == item.id,
                            );
                            widget.paper.normalize();
                          });
                          unawaited(widget.onChanged());
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
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
            },
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ),
      ],
    );
  }
}
