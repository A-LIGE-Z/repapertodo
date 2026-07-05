enum StartupCommandKind {
  none,
  show,
  hide,
  toggle,
  newTodo,
  newNote,
  settings,
  exit,
}

class StartupCommand {
  const StartupCommand(this.kind);

  final StartupCommandKind kind;

  bool get createsPaper =>
      kind == StartupCommandKind.newTodo || kind == StartupCommandKind.newNote;

  static StartupCommand parse(
    Iterable<String> args, {
    StartupCommandKind defaultWhenEmpty = StartupCommandKind.none,
  }) {
    final normalizedArgs =
        args.expand(_normalizeSegments).where((arg) => arg.isNotEmpty).toList();
    if (normalizedArgs.isEmpty) {
      return StartupCommand(defaultWhenEmpty);
    }
    for (var index = 0; index < normalizedArgs.length; index++) {
      final current = normalizedArgs[index];
      if (current == 'new' && index + 1 < normalizedArgs.length) {
        final createdKind = _createdPaperKind(normalizedArgs[index + 1]);
        if (createdKind != StartupCommandKind.none) {
          return StartupCommand(createdKind);
        }
      }
      final kind = _kindFor(current);
      if (kind != StartupCommandKind.none) {
        return StartupCommand(kind);
      }
    }
    return const StartupCommand(StartupCommandKind.none);
  }
}

String _normalize(String arg) {
  return arg
      .trim()
      .replaceFirst(RegExp(r'^[-/]+'), '')
      .replaceAll(RegExp(r'[\s_-]+'), '-')
      .replaceFirst(RegExp(r'-$'), '')
      .toLowerCase();
}

Iterable<String> _normalizeSegments(String arg) {
  return arg.split(RegExp(r'[=:]+')).map(_normalize);
}

StartupCommandKind _kindFor(String normalized) {
  return switch (normalized) {
    'show' || 'open' => StartupCommandKind.show,
    'hide' || 'close' => StartupCommandKind.hide,
    'toggle' => StartupCommandKind.toggle,
    'new-todo' ||
    'newtodo' ||
    'add-todo' ||
    'addtodo' ||
    'todo' =>
      StartupCommandKind.newTodo,
    'new-note' ||
    'newnote' ||
    'add-note' ||
    'addnote' ||
    'note' ||
    'paper' =>
      StartupCommandKind.newNote,
    'settings' ||
    'setting' ||
    'preferences' ||
    'preference' ||
    'prefs' =>
      StartupCommandKind.settings,
    'exit' || 'quit' => StartupCommandKind.exit,
    _ => StartupCommandKind.none,
  };
}

StartupCommandKind _createdPaperKind(String normalized) {
  return switch (normalized) {
    'todo' || 'task' => StartupCommandKind.newTodo,
    'note' || 'paper' => StartupCommandKind.newNote,
    _ => StartupCommandKind.none,
  };
}
