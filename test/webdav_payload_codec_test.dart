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

  test('encrypted payload codec rejects unsafe passphrases', () {
    for (final passphrase in const [
      '   ',
      'shared\nsecret',
      'shared\u007Fsecret',
      'shared\u0085secret',
    ]) {
      expect(
        () => EncryptedWebDavPayloadCodec(passphrase: passphrase),
        throwsA(isA<ArgumentError>()),
      );
    }
  });

  test('encrypted payload codec rejects unsafe KDF iteration counts', () {
    for (final kdfIterations in const [99999, 1000001]) {
      expect(
        () => EncryptedWebDavPayloadCodec(
          passphrase: 'shared sync secret',
          kdfIterations: kdfIterations,
        ),
        throwsA(isA<ArgumentError>()),
      );
    }
  });

  test('encrypted payload codec trims passphrases before encryption', () async {
    final encoder = EncryptedWebDavPayloadCodec(
      passphrase: ' shared sync secret ',
      kdfIterations: 100000,
      random: Random(2),
    );
    final decoder = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(3),
    );
    const stateCodec = AppStateCodec();
    final state = AppState(
      papers: [
        PaperData(
          id: 'trimmed-passphrase-paper',
          type: PaperTypes.note,
          title: 'Trimmed passphrase',
          content: 'Edge spaces do not change the key',
        ),
      ],
    );

    final snapshotBytes = await encoder.encodeSnapshot(state, stateCodec);
    final decodedState =
        await decoder.decodeSnapshot(snapshotBytes, stateCodec);

    expect(
      decodedState.papers.single.content,
      'Edge spaces do not change the key',
    );
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

  test('plain payload codec accepts standalone CR operation log line endings',
      () {
    const plainCodec = PlainWebDavPayloadCodec();
    final operationJson = jsonEncode({
      'id': 'device-a-1',
      'deviceId': 'device-a',
      'sequence': 1,
      'kind': 'updateNoteContent',
      'createdAtUtc': '2026-07-02T10:00:00Z',
      'payload': {'paperId': 'note', 'content': 'First edit'},
    });

    final operations = plainCodec.decodeOperationLog(
      utf8.encode('\r$operationJson\r'),
    );

    expect(operations.single.id, 'device-a-1');
    expect(operations.single.payload['content'], 'First edit');
  });

  test('plain payload codec reports unknown for non-json plain bytes', () {
    const plainCodec = PlainWebDavPayloadCodec();

    expect(
      plainCodec.inspectPayloadFormat(utf8.encode('not-json')),
      WebDavPayloadFormat.unknown,
    );
    expect(
      plainCodec.inspectPayloadFormat([0xFF, 0xFE, 0xFD]),
      WebDavPayloadFormat.unknown,
    );
  });

  test('plain payload codec rejects empty and multi-operation logs', () {
    const plainCodec = PlainWebDavPayloadCodec();
    final firstOperation = jsonEncode({
      'id': 'device-a-1',
      'deviceId': 'device-a',
      'sequence': 1,
      'kind': 'updateNoteContent',
      'createdAtUtc': '2026-07-02T10:00:00Z',
      'payload': {'paperId': 'note', 'content': 'First edit'},
    });
    final secondOperation = jsonEncode({
      'id': 'device-a-2',
      'deviceId': 'device-a',
      'sequence': 2,
      'kind': 'updateNoteContent',
      'createdAtUtc': '2026-07-02T10:01:00Z',
      'payload': {'paperId': 'note', 'content': 'Second edit'},
    });

    for (final operationBytes in [
      utf8.encode('\r\r'),
      utf8.encode('$firstOperation\r$secondOperation\r'),
    ]) {
      expect(
        () => plainCodec.decodeOperationLog(operationBytes),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('exactly one operation'),
          ),
        ),
      );
    }
  });

  test('plain payload codec reports malformed operation log line numbers', () {
    const plainCodec = PlainWebDavPayloadCodec();
    final validOperation = jsonEncode({
      'id': 'device-a-1',
      'deviceId': 'device-a',
      'sequence': 1,
      'kind': 'updateNoteContent',
      'createdAtUtc': '2026-07-02T10:00:00Z',
      'payload': {'paperId': 'note', 'content': 'Remote edit'},
    });
    final operationBytes = utf8.encode('\n$validOperation\n\n[]\n');

    expect(
      () => plainCodec.decodeOperationLog(operationBytes),
      throwsA(
        isA<FormatException>()
            .having(
              (error) => error.message,
              'message',
              contains('operation log line 4'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('JSON object'),
            ),
      ),
    );

    final crOperationBytes = utf8.encode('$validOperation\r\r[]\r');
    expect(
      () => plainCodec.decodeOperationLog(crOperationBytes),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('operation log line 3'),
        ),
      ),
    );
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

  test('encrypted payload codec reports malformed envelopes separately',
      () async {
    final codec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(7),
    );
    final unsupportedEnvelope = utf8.encode(
      'RePaperTodo-Encrypted-Payload-v1\n'
      '${jsonEncode({
            'version': 2,
            'algorithm': 'aes-gcm-256',
            'kdf': 'pbkdf2-hmac-sha256',
            'kdfIterations': 100000,
            'salt': base64Url.encode(List.filled(16, 1)).replaceAll('=', ''),
            'nonce': base64Url.encode(List.filled(12, 2)).replaceAll('=', ''),
            'cipherText':
                base64Url.encode(List.filled(8, 3)).replaceAll('=', ''),
            'mac': base64Url.encode(List.filled(16, 4)).replaceAll('=', ''),
          })}\n',
    );

    expect(
      codec.decodeSnapshot(unsupportedEnvelope, const AppStateCodec()),
      throwsA(
        isA<WebDavPayloadDecryptionException>()
            .having(
              (error) => error.message,
              'message',
              contains('unsupported or corrupted'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('passphrase')),
            ),
      ),
    );
  });

  test(
      'encrypted payload codec rejects excessive remote KDF iterations quickly',
      () async {
    final codec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(11),
    );
    final malformedEnvelope = utf8.encode(
      'RePaperTodo-Encrypted-Payload-v1\n'
      '${jsonEncode({
            'version': 1,
            'algorithm': 'aes-gcm-256',
            'kdf': 'pbkdf2-hmac-sha256',
            'kdfIterations': 1000001,
            'salt': base64Url.encode(List.filled(16, 1)).replaceAll('=', ''),
            'nonce': base64Url.encode(List.filled(12, 2)).replaceAll('=', ''),
            'cipherText':
                base64Url.encode(List.filled(8, 3)).replaceAll('=', ''),
            'mac': base64Url.encode(List.filled(16, 4)).replaceAll('=', ''),
          })}\n',
    );

    expect(
      codec.decodeSnapshot(malformedEnvelope, const AppStateCodec()),
      throwsA(
        isA<WebDavPayloadDecryptionException>()
            .having(
              (error) => error.message,
              'message',
              contains('unsupported or corrupted'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('passphrase')),
            ),
      ),
    );
  });

  test('encrypted payload codec reports malformed nonce separately', () async {
    final codec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(8),
    );
    final malformedEnvelope = utf8.encode(
      'RePaperTodo-Encrypted-Payload-v1\n'
      '${jsonEncode({
            'version': 1,
            'algorithm': 'aes-gcm-256',
            'kdf': 'pbkdf2-hmac-sha256',
            'kdfIterations': 100000,
            'salt': base64Url.encode(List.filled(16, 1)).replaceAll('=', ''),
            'nonce': base64Url.encode(List.filled(4, 2)).replaceAll('=', ''),
            'cipherText':
                base64Url.encode(List.filled(8, 3)).replaceAll('=', ''),
            'mac': base64Url.encode(List.filled(16, 4)).replaceAll('=', ''),
          })}\n',
    );

    expect(
      codec.decodeSnapshot(malformedEnvelope, const AppStateCodec()),
      throwsA(
        isA<WebDavPayloadDecryptionException>()
            .having(
              (error) => error.message,
              'message',
              contains('unsupported or corrupted'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('passphrase')),
            ),
      ),
    );
  });

  test('encrypted payload codec rejects malformed base64url fields', () async {
    final codec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(12),
    );

    for (final malformedSalt in const ['AQE=', 'salt+value', 'A']) {
      final malformedEnvelope = utf8.encode(
        'RePaperTodo-Encrypted-Payload-v1\n'
        '${jsonEncode({
              'version': 1,
              'algorithm': 'aes-gcm-256',
              'kdf': 'pbkdf2-hmac-sha256',
              'kdfIterations': 100000,
              'salt': malformedSalt,
              'nonce': base64Url.encode(List.filled(12, 2)).replaceAll('=', ''),
              'cipherText':
                  base64Url.encode(List.filled(8, 3)).replaceAll('=', ''),
              'mac': base64Url.encode(List.filled(16, 4)).replaceAll('=', ''),
            })}\n',
      );

      expect(
        codec.decodeSnapshot(malformedEnvelope, const AppStateCodec()),
        throwsA(
          isA<WebDavPayloadDecryptionException>()
              .having(
                (error) => error.message,
                'message',
                contains('unsupported or corrupted'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('passphrase')),
              ),
        ),
        reason: malformedSalt,
      );
    }
  });

  test('encrypted payload codec reports malformed MAC separately', () async {
    final codec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(9),
    );
    final malformedEnvelope = utf8.encode(
      'RePaperTodo-Encrypted-Payload-v1\n'
      '${jsonEncode({
            'version': 1,
            'algorithm': 'aes-gcm-256',
            'kdf': 'pbkdf2-hmac-sha256',
            'kdfIterations': 100000,
            'salt': base64Url.encode(List.filled(16, 1)).replaceAll('=', ''),
            'nonce': base64Url.encode(List.filled(12, 2)).replaceAll('=', ''),
            'cipherText':
                base64Url.encode(List.filled(8, 3)).replaceAll('=', ''),
            'mac': base64Url.encode(List.filled(4, 4)).replaceAll('=', ''),
          })}\n',
    );

    expect(
      codec.decodeOperationLog(malformedEnvelope),
      throwsA(
        isA<WebDavPayloadDecryptionException>()
            .having(
              (error) => error.message,
              'message',
              contains('unsupported or corrupted'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('passphrase')),
            ),
      ),
    );
  });

  test('encrypted payload codec reports empty ciphertext separately', () async {
    final codec = EncryptedWebDavPayloadCodec(
      passphrase: 'shared sync secret',
      kdfIterations: 100000,
      random: Random(10),
    );
    final malformedEnvelope = utf8.encode(
      'RePaperTodo-Encrypted-Payload-v1\n'
      '${jsonEncode({
            'version': 1,
            'algorithm': 'aes-gcm-256',
            'kdf': 'pbkdf2-hmac-sha256',
            'kdfIterations': 100000,
            'salt': base64Url.encode(List.filled(16, 1)).replaceAll('=', ''),
            'nonce': base64Url.encode(List.filled(12, 2)).replaceAll('=', ''),
            'cipherText': '',
            'mac': base64Url.encode(List.filled(16, 4)).replaceAll('=', ''),
          })}\n',
    );

    expect(
      codec.decodeSnapshot(malformedEnvelope, const AppStateCodec()),
      throwsA(
        isA<WebDavPayloadDecryptionException>()
            .having(
              (error) => error.message,
              'message',
              contains('unsupported or corrupted'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('passphrase')),
            ),
      ),
    );
  });
}
