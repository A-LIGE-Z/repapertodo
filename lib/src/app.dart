import 'package:flutter/material.dart';

import 'core/model/app_state.dart';
import 'core/model/paper_constants.dart';
import 'core/model/paper_data.dart';
import 'core/model/paper_item.dart';

class RePaperTodoApp extends StatelessWidget {
  const RePaperTodoApp({super.key});

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
        initialState: AppState(
          papers: [
            PaperData(
              id: 'welcome-todo',
              type: PaperTypes.todo,
              title: 'Windows parity',
              items: [
                PaperItem(id: 'todo-1', text: 'Build compatible data core'),
                PaperItem(id: 'todo-2', text: 'Restore independent paper windows'),
                PaperItem(id: 'todo-3', text: 'Add WebDAV sync'),
              ],
            ),
            PaperData(
              id: 'welcome-note',
              type: PaperTypes.note,
              title: 'RePaperTodo',
              content: 'Flutter-first, local-first, Windows exe first.',
              x: 460,
              y: 150,
              width: PaperLayoutDefaults.noteDefaultWidth,
              height: PaperLayoutDefaults.noteDefaultHeight,
            ),
          ],
        ),
      ),
    );
  }
}

class PaperBoardScreen extends StatefulWidget {
  const PaperBoardScreen({
    required this.initialState,
    super.key,
  });

  final AppState initialState;

  @override
  State<PaperBoardScreen> createState() => _PaperBoardScreenState();
}

class _PaperBoardScreenState extends State<PaperBoardScreen> {
  late final AppState state = widget.initialState..normalize();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RePaperTodo'),
        actions: [
          IconButton(
            tooltip: 'New todo paper',
            onPressed: () {},
            icon: const Icon(Icons.add_task),
          ),
          IconButton(
            tooltip: 'New note paper',
            onPressed: () {},
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
          itemCount: state.papers.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return PaperPreview(paper: state.papers[index]);
          },
        ),
      ),
    );
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
