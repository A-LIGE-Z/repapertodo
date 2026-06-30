import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project rules preserve the requested direction', () {
    final rules = File('AGENTS.md').readAsStringSync();

    expect(rules, contains('Flutter-first reimplementation'));
    expect(rules, contains('Windows exe first'));
    expect(rules, contains('Generic WebDAV must remain supported'));
    expect(rules, contains('no fixed budget ceiling'));
  });
}

