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
    final normalized =
        args.map(_normalize).where((arg) => arg.isNotEmpty).firstOrNull;
    if (normalized == null) {
      return StartupCommand(defaultWhenEmpty);
    }
    return StartupCommand(switch (normalized) {
      'show' || 'open' => StartupCommandKind.show,
      'hide' => StartupCommandKind.hide,
      'toggle' => StartupCommandKind.toggle,
      'new-todo' || 'todo' => StartupCommandKind.newTodo,
      'new-note' || 'note' || 'paper' => StartupCommandKind.newNote,
      'settings' ||
      'setting' ||
      'preferences' ||
      'prefs' =>
        StartupCommandKind.settings,
      'exit' || 'quit' => StartupCommandKind.exit,
      _ => StartupCommandKind.none,
    });
  }
}

String _normalize(String arg) {
  return arg.trim().replaceFirst(RegExp(r'^[-/]+'), '').toLowerCase();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
