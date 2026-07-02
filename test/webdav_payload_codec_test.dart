import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('encrypted payload codec round trips snapshots and operation logs',
      () async {
    final codec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(1),
    );
    const stateCodec = AppStateCodec();
    final state = AppState(
      papers: [
        PaperData(
          id: 'paper-secret',
          type: PaperTypes.note,
          title: 'Secret',
          content: 'Private sync body',
        ),
      ],
    );
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 2, 10),
      payload: {'paperId': 'paper-secret', 'content': 'Encrypted edit'},
    );

    final snapshotBytes = await codec.encodeSnapshot(state, stateCodec);
    final operationBytes = await codec.encodeOperationLog(operation);

    final snapshotText = utf8.decode(snapshotBytes);
    final operationText = utf8.decode(operationBytes);
    expect(snapshotText, startsWith('RePaperTodo-Encrypted-Payload-v1\n'));
    expect(operationText, startsWith('RePaperTodo-Encrypted-Payload-v1\n'));
    expect(codec.inspectPayloadFormat(snapshotBytes),
        WebDavPayloadFormat.encrypted);
    expect(codec.inspectPayloadFormat(operationBytes),
        WebDavPayloadFormat.encrypted);
    expect(snapshotText, isNot(contains('Private sync body')));
    expect(operationText, isNot(contains('Encrypted edit')));

    final decodedState = await codec.decodeSnapshot(snapshotBytes, stateCodec);
    final decodedOperations = await codec.decodeOperationLog(operationBytes);

    expect(decodedState.papers.single.content, 'Private sync body');
    expect(decodedOperations.single.deviceId, 'device-a');
    expect(decodedOperations.single.sequence, 1);
    expect(decodedOperations.single.payload, {
      'paperId': 'paper-secret',
      'content': 'Encrypted edit',
    });
  });

  test('encrypted payload codec can read legacy plain payloads', () async {
    final encryptedCodec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(2),
    );
    const plainCodec = PlainWebDavPayloadCodec();
    const stateCodec = AppStateCodec();
    final state = AppState(
      papers: [
        PaperData(
          id: 'legacy',
          type: PaperTypes.note,
          title: 'Legacy',
          content: 'Plain old body',
        ),
      ],
    );
    final operation = SyncOperation(
      id: 'device-a-1',
      deviceId: 'device-a',
      sequence: 1,
      kind: SyncOperationKind.updateNoteContent,
      createdAtUtc: DateTime.utc(2026, 7, 2, 10),
      payload: {'paperId': 'legacy', 'content': 'Plain edit'},
    );

    final plainSnapshotBytes = plainCodec.encodeSnapshot(state, stateCodec);
    final plainOperationBytes = plainCodec.encodeOperationLog(operation);

    expect(encryptedCodec.inspectPayloadFormat(plainSnapshotBytes),
        WebDavPayloadFormat.plainJson);
    expect(encryptedCodec.inspectPayloadFormat(plainOperationBytes),
        WebDavPayloadFormat.plainJson);
    final decodedState =
        await encryptedCodec.decodeSnapshot(plainSnapshotBytes, stateCodec);
    final decodedOperations =
        await encryptedCodec.decodeOperationLog(plainOperationBytes);

    expect(decodedState.papers.single.content, 'Plain old body');
    expect(decodedOperations.single.payload, {
      'paperId': 'legacy',
      'content': 'Plain edit',
    });
  });

  test('plain payload codec accepts UTF-8 BOM legacy payloads', () {
    const plainCodec = PlainWebDavPayloadCodec();
    const stateCodec = AppStateCodec();
    final snapshotBytes = utf8.encode('''\uFEFF{
  "papers": [
    {
      "id": "bom-note",
      "type": "note",
      "title": "BOM note",
      "content": "Read from a BOM-prefixed snapshot"
    }
  ]
}
''');
    final operationBytes = utf8.encode(
      '\uFEFF{"id":"device-a-1","deviceId":"device-a","sequence":1,'
      '"kind":"updateNoteContent","createdAtUtc":"2026-07-02T10:00:00Z",'
      '"payload":{"paperId":"bom-note","content":"BOM edit"}}\n',
    );

    final decodedState = plainCodec.decodeSnapshot(snapshotBytes, stateCodec);
    final decodedOperations = plainCodec.decodeOperationLog(operationBytes);

    expect(decodedState.papers.single.id, 'bom-note');
    expect(decodedState.papers.single.content,
        'Read from a BOM-prefixed snapshot');
    expect(decodedOperations.single.id, 'device-a-1');
    expect(decodedOperations.single.payload, {
      'paperId': 'bom-note',
      'content': 'BOM edit',
    });
  });

  test('encrypted payload codec reports unknown for non-json plain bytes', () {
    final encryptedCodec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(6),
    );

    expect(
      encryptedCodec.inspectPayloadFormat(utf8.encode('not-json')),
      WebDavPayloadFormat.unknown,
    );
    expect(
      encryptedCodec.inspectPayloadFormat([0xFF, 0xFE, 0xFD]),
      WebDavPayloadFormat.unknown,
    );
  });

  test('encrypted payload codec migrates legacy PaperTodo plain snapshots',
      () async {
    final encryptedCodec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(5),
    );
    const stateCodec = AppStateCodec();
    final legacySnapshotBytes = utf8.encode('''
{
  "Theme": "dark",
  "Papers": [
    {
      "Id": "legacy-paper",
      "Type": "note",
      "Title": "Legacy cloud note",
      "Content": "Old PaperTodo snapshot body"
    }
  ]
}
''');

    expect(encryptedCodec.inspectPayloadFormat(legacySnapshotBytes),
        WebDavPayloadFormat.plainJson);

    final decodedState =
        await encryptedCodec.decodeSnapshot(legacySnapshotBytes, stateCodec);

    expect(decodedState.theme, 'dark');
    expect(decodedState.papers.single.id, 'legacy-paper');
    expect(decodedState.papers.single.type, PaperTypes.note);
    expect(decodedState.papers.single.title, 'Legacy');
    expect(decodedState.papers.single.content, 'Old PaperTodo snapshot body');
  });

  test('encrypted payload codec rejects the wrong passphrase', () async {
    final codec = EncryptedWebDavPayloadCodec(
      passphrase: 'right secret',
      kdfIterations: 100000,
      random: Random(3),
    );
    final wrongCodec = EncryptedWebDavPayloadCodec(
      passphrase: 'wrong secret',
      kdfIterations: 100000,
      random: Random(4),
    );
    const stateCodec = AppStateCodec();
    final encryptedBytes = await codec.encodeSnapshot(
      AppState(
        papers: [
          PaperData(
            id: 'secret',
            type: PaperTypes.note,
            title: 'Secret',
            content: 'Wrong keys fail',
          ),
        ],
      ),
      stateCodec,
    );

    expect(
      wrongCodec.decodeSnapshot(encryptedBytes, stateCodec),
      throwsA(
        isA<WebDavPayloadDecryptionException>().having(
          (error) => error.message,
          'message',
          contains('sync encryption passphrase'),
        ),
      ),
    );
  });
}
