import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
import 'core/storage/state_store.dart';

class RePaperTodoApp extends StatelessWidget {
  const RePaperTodoApp({
    required this.controller,
    required this.store,
    super.key,
  });

  final RePaperTodoController controller;
  final StateStore store;

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
      ),
    );
  }
}

class PaperBoardScreen extends StatefulWidget {
  const PaperBoardScreen({
    required this.controller,
    required this.store,
    super.key,
  });

  final RePaperTodoController controller;
  final StateStore store;

  @override
  State<PaperBoardScreen> createState() => _PaperBoardScreenState();
}

class _PaperBoardScreenState extends State<PaperBoardScreen> {
  RePaperTodoController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visiblePapers = controller.state.papers.where((paper) => paper.isVisible).toList();
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
            tooltip: 'Settings',
            onPressed: () {},
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
                    paper.isTodo ? Icons.check_box_outlined : Icons.notes_outlined,
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
                          item.done ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18,
                          color: item.done ? colorScheme.primary : colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.text.isEmpty ? 'New item' : item.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: item.done ? colorScheme.outline : colorScheme.onSurface,
                              decoration: item.done ? TextDecoration.lineThrough : null,
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
