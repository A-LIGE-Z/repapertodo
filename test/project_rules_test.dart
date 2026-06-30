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

  test('Android build targets Android 14 through 17', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('compileSdk = 37'));
    expect(gradle, contains('minSdk = 34'));
    expect(gradle, contains('targetSdk = 37'));
  });
}
