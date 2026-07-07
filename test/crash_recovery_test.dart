import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/src/bootstrap/crash_recovery.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('writes crash recovery state beside the primary data file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_crash_recovery_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    const writer = CrashRecoveryWriter();
    final state = AppState(
      theme: 'dark',
      papers: [
        PaperData(
          id: 'crash-paper',
          type: PaperTypes.todo,
          title: 'Unsaved crash state',
          items: [
            PaperItem(id: 'crash-item', text: 'Recover me'),
          ],
        ),
      ],
    );

    writer.saveSync(
      store: store,
      state: state,
      error: StateError('boom'),
      stackTrace: StackTrace.fromString('stack line'),
    );

    final recovery = File(writer.recoveryPathFor(store));
    final log = File(writer.logPathFor(store));
    expect(recovery.path, p.join(directory.path, 'data.crash_recovery.json'));
    expect(await recovery.exists(), true);
    expect(await log.exists(), true);

    final recoveredState = const AppStateCodec().decode(
      await recovery.readAsString(),
    );
    expect(recoveredState.theme, 'dark');
    expect(recoveredState.papers.single.id, 'crash-paper');
    expect(recoveredState.papers.single.items.single.text, 'Recover me');

    final logText = await log.readAsString();
    expect(logText, contains('Unhandled RePaperTodo error'));
    expect(logText, contains('Bad state: boom'));
    expect(logText, contains('stack line'));
  });

  test('crash recovery snapshots do not mutate live state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'repapertodo_crash_recovery_snapshot_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    const writer = CrashRecoveryWriter();
    final state = AppState(
      papers: [
        PaperData(
          id: 'crash-title-paper',
          type: PaperTypes.todo,
          title: List.filled(80, 'A').join(),
        ),
      ],
    );

    writer.saveSync(store: store, state: state);

    expect(state.papers.single.title, List.filled(80, 'A').join());
    final recoveredState = const AppStateCodec().decode(
      await File(writer.recoveryPathFor(store)).readAsString(),
    );
    expect(recoveredState.papers.single.title,
        List.filled(state.maxTitleLength, 'A').join());
  });
}
