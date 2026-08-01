import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/sync/field_level_conflict_merger.dart';

void main() {
  test('FieldLevelConflictMerger preserves non-conflicting field edits from both devices', () {
    const merger = FieldLevelConflictMerger();
    final base = {
      'id': 'paper-1',
      'title': 'Original Title',
      'due': null,
    };
    final local = {
      'id': 'paper-1',
      'title': 'Local Updated Title',
      'due': null,
    };
    final remote = {
      'id': 'paper-1',
      'title': 'Original Title',
      'due': '2026-08-05T10:00:00Z',
    };

    final merged = merger.mergeFields(base: base, local: local, remote: remote);
    expect(merged['title'], 'Local Updated Title');
    expect(merged['due'], '2026-08-05T10:00:00Z');
  });

  test('FieldLevelConflictMerger resolves conflicting title edits gracefully', () {
    const merger = FieldLevelConflictMerger();
    final base = {'title': 'Original'};
    final local = {'title': 'Windows Edit'};
    final remote = {'title': 'Android Edit'};

    final merged = merger.mergeFields(base: base, local: local, remote: remote);
    expect(merged['title'], contains('Windows Edit'));
    expect(merged['title'], contains('Android Edit'));
  });
}
