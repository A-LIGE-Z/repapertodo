import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
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
            return PaperPreview(paper: visiblePapers[index]);
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
    super.key,
  });

  final PaperData paper;

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
                    child: Text(
                      paper.title.isEmpty ? 'Untitled' : paper.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (paper.isTodo)
                ...paper.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          item.done
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 18,
                          color: item.done
                              ? colorScheme.primary
                              : colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.text.isEmpty ? 'New item' : item.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: item.done
                                  ? colorScheme.outline
                                  : colorScheme.onSurface,
                              decoration:
                                  item.done ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Text(
                  paper.content,
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
