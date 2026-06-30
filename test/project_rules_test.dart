import 'dart:io';

void main() {
  final rules = File('AGENTS.md').readAsStringSync();

  if (!rules.contains('Flutter-first reimplementation')) {
    throw StateError('Project rules must define the Flutter-first direction.');
  }

  if (!rules.contains('Windows exe first')) {
    throw StateError('Project rules must preserve Windows as the first target.');
  }

  if (!rules.contains('Generic WebDAV must remain supported')) {
    throw StateError('Project rules must require generic WebDAV support.');
  }
}

