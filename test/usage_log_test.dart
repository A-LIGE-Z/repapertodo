import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/src/core/logging/usage_log.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/model/paper_item.dart';
import 'package:repapertodo/src/core/model/sync_settings.dart';

void main() {
  test('writes redacted seven-day usage logs for settings and paper changes',
      () async {
    final directory = await Directory.systemTemp.createTemp('repapertodo-log-');
    addTearDown(() => directory.delete(recursive: true));
    var now = DateTime(2026, 7, 15, 12);
    final logger = UsageLog(now: () => now);
    final stateFile = p.join(directory.path, 'data.json');
    await logger.configureForStateFile(stateFile);
    final logDirectory = Directory(p.join(directory.path, 'LOG'));
    final expired = File(p.join(logDirectory.path, '2026-07-07.txt'));
    await expired.writeAsString('expired\n');

    final before = AppState(
      sync: SyncSettings(
        enabled: true,
        provider: SyncProviderIds.webDav,
        webDav: WebDavSyncSettings(
          endpoint: 'https://dav.example.test/dav/',
          username: 'user@example.com',
          password: 'old-secret',
          encryptionPassphrase: 'old-passphrase',
        ),
      ),
      papers: [
        PaperData(
          id: 'paper-1',
          title: 'Before',
          items: [PaperItem(id: 'item-1', text: 'Before')],
        ),
      ],
    );
    final after = AppState.fromJson(before.toJson())
      ..sync.webDav.password = 'new-secret'
      ..sync.webDav.encryptionPassphrase = 'new-passphrase';
    after.papers.single.title = 'After';
    after.papers.single.items.single.text = 'After text';
    await logger.recordStateChange(
      before: before,
      after: after,
      source: 'test',
    );
    await logger.record(
      'sync',
      'failed',
      details: {
        'password': 'new-secret',
        'encryptionPassphrase': 'new-passphrase',
      },
    );

    final logFile = File(p.join(logDirectory.path, '2026-07-15.txt'));
    final text = await logFile.readAsString();
    expect(text, contains('[settings] changed'));
    expect(text, contains('[paper] changed'));
    expect(text, contains('<redacted>'));
    expect(text, isNot(contains('old-secret')));
    expect(text, isNot(contains('new-secret')));
    expect(text, isNot(contains('old-passphrase')));
    expect(text, isNot(contains('new-passphrase')));
    expect(await expired.exists(), isFalse);

    now = DateTime(2026, 7, 23, 12);
    await logger.record('application', 'retention-check');
    expect(await logFile.exists(), isFalse);
  });
}
