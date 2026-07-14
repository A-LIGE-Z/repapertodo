import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('round-trips normalized pending sync operation batches', () {
    final settings = SyncSettings.fromJson({
      'enabled': true,
      'provider': SyncProviderIds.webDav,
      'pendingOperationBatch': {
        'baseState': {
          'papers': [
            {
              'id': 'paper-1',
              'items': [
                {'id': 'item-1', 'text': 'Draft'},
              ],
            },
          ],
        },
        'deviceId': ' Device A ',
        'startSequence': 0,
        'createdAtUtc': '2026-07-01T09:30:00Z',
      },
    });

    final batch = settings.pendingOperationBatch;
    expect(batch, isNotNull);
    expect(batch!.deviceId, 'device-a');
    expect(batch.startSequence, 0);
    expect(batch.createdAtUtc, DateTime.utc(2026, 7, 1, 9, 30));
    expect(batch.createdAtUtc.isUtc, true);
    expect(batch.baseState, {
      'papers': [
        {
          'id': 'paper-1',
          'items': [
            {'id': 'item-1', 'text': 'Draft'},
          ],
        },
      ],
    });

    final wire = settings.toJson();
    expect(wire['pendingOperationBatch'], {
      'baseState': {
        'papers': [
          {
            'id': 'paper-1',
            'items': [
              {'id': 'item-1', 'text': 'Draft'},
            ],
          },
        ],
      },
      'deviceId': 'device-a',
      'startSequence': 0,
      'createdAtUtc': DateTime.utc(2026, 7, 1, 9, 30).toIso8601String(),
    });

    final roundTripped = SyncSettings.fromJson(wire).pendingOperationBatch;
    expect(roundTripped, isNotNull);
    expect(roundTripped!.toJson(), batch.toJson());
  });

  test('deep-copies pending batch base state at every model boundary', () {
    final source = <String, Object?>{
      'papers': <Object?>[
        <String, Object?>{
          'id': 'paper-1',
          'metadata': <String, Object?>{
            'tags': <Object?>['draft'],
          },
        },
      ],
    };
    final batch = PendingSyncOperationBatch(
      baseState: source,
      deviceId: 'device-a',
      startSequence: 7,
      createdAtUtc: DateTime.utc(2026, 7, 1, 9),
    );

    final sourcePapers = source['papers']! as List<Object?>;
    final sourcePaper = sourcePapers.single! as Map<String, Object?>;
    final sourceMetadata = sourcePaper['metadata']! as Map<String, Object?>;
    final sourceTags = sourceMetadata['tags']! as List<Object?>;
    sourcePaper['id'] = 'changed-at-source';
    sourceTags.add('source-only');

    final batchPapers = batch.baseState['papers']! as List<Object?>;
    final batchPaper = batchPapers.single! as Map<String, Object?>;
    final batchMetadata = batchPaper['metadata']! as Map<String, Object?>;
    final batchTags = batchMetadata['tags']! as List<Object?>;
    expect(batchPaper['id'], 'paper-1');
    expect(batchTags, ['draft']);
    expect(identical(sourcePapers, batchPapers), false);
    expect(identical(sourceMetadata, batchMetadata), false);
    expect(identical(sourceTags, batchTags), false);

    final copied = batch.copy();
    final encoded = batch.toJson();
    batchPaper['id'] = 'changed-at-batch';
    batchTags.add('batch-only');

    final copiedPaper = (copied.baseState['papers']! as List<Object?>).single!
        as Map<String, Object?>;
    final copiedTags = (copiedPaper['metadata']!
        as Map<String, Object?>)['tags']! as List<Object?>;
    final encodedBaseState = encoded['baseState']! as Map<String, Object?>;
    final encodedPaper = (encodedBaseState['papers']! as List<Object?>).single!
        as Map<String, Object?>;
    final encodedTags = (encodedPaper['metadata']!
        as Map<String, Object?>)['tags']! as List<Object?>;
    expect(copiedPaper['id'], 'paper-1');
    expect(copiedTags, ['draft']);
    expect(encodedPaper['id'], 'paper-1');
    expect(encodedTags, ['draft']);

    encodedPaper['id'] = 'changed-at-wire';
    encodedTags.add('wire-only');
    expect(batchPaper['id'], 'changed-at-batch');
    expect(batchTags, ['draft', 'batch-only']);
  });

  test('drops malformed pending batches without blocking settings startup', () {
    final validTimestamp = DateTime.utc(2026, 7, 1, 9).toIso8601String();
    final malformedBatches = <Object?>[
      {
        'baseState': <String, Object?>{},
        'deviceId': '   ',
        'startSequence': 0,
        'createdAtUtc': validTimestamp,
      },
      {
        'baseState': <String, Object?>{},
        'deviceId': 'short',
        'startSequence': 0,
        'createdAtUtc': validTimestamp,
      },
      {
        'baseState': <String, Object?>{},
        'deviceId': 'device-a',
        'startSequence': -1,
        'createdAtUtc': validTimestamp,
      },
      {
        'baseState': <String, Object?>{},
        'deviceId': 'device-a',
        'startSequence': maxSyncDeviceSequence + 1,
        'createdAtUtc': validTimestamp,
      },
      {
        'baseState': <String, Object?>{},
        'deviceId': 'device-a',
        'startSequence': 0.0,
        'createdAtUtc': validTimestamp,
      },
      {
        'baseState': <String, Object?>{},
        'deviceId': 'device-a',
        'startSequence': 0,
        'createdAtUtc': '2026-07-01T09:00:00',
      },
      {
        'baseState': <String, Object?>{},
        'deviceId': 'device-a',
        'startSequence': 0,
        'createdAtUtc': '2026-02-30T09:00:00Z',
      },
      {
        'baseState': <String, Object?>{},
        'deviceId': 'device-a',
        'startSequence': 0,
        'createdAtUtc': ' $validTimestamp',
      },
      {
        'baseState': <Object?>[],
        'deviceId': 'device-a',
        'startSequence': 0,
        'createdAtUtc': validTimestamp,
      },
      <Object?, Object?>{
        1: 'not-a-json-object',
      },
    ];

    for (final malformedBatch in malformedBatches) {
      final settings = SyncSettings.fromJson({
        'enabled': true,
        'provider': 'WEBDAV',
        'pendingOperationBatch': malformedBatch,
        'futureSetting': {'kept': true},
      });

      expect(settings.enabled, true, reason: '$malformedBatch');
      expect(
        settings.provider,
        SyncProviderIds.webDav,
        reason: '$malformedBatch',
      );
      expect(
        settings.pendingOperationBatch,
        isNull,
        reason: '$malformedBatch',
      );
      expect(settings.extra['futureSetting'], {'kept': true});
      expect(
        settings.toJson().containsKey('pendingOperationBatch'),
        false,
        reason: '$malformedBatch',
      );
    }
  });

  test('keeps pending batch absent for legacy sync settings JSON', () {
    final settings = SyncSettings.fromJson({
      'enabled': false,
      'provider': SyncProviderIds.none,
      'legacyFutureSetting': true,
    });

    expect(settings.pendingOperationBatch, isNull);
    expect(settings.copy().pendingOperationBatch, isNull);
    expect(settings.toJson().containsKey('pendingOperationBatch'), false);
    expect(settings.toJson()['legacyFutureSetting'], true);
  });

  test('keeps latest tombstones when marking deleted records', () {
    final ten = DateTime.utc(2026, 7, 1, 10);
    final tenThirty = DateTime.utc(2026, 7, 1, 10, 30);
    final settings = SyncSettings(
      deletedPaperTombstones: {'paper': ten.toIso8601String()},
      deletedTodoItemTombstones: {
        'paper': {'item': tenThirty.toIso8601String()},
        'todo': {'item': ten.toIso8601String()},
      },
    );

    expect(
      settings.markPaperDeleted(' paper ', DateTime.utc(2026, 7, 1, 9)),
      false,
    );
    expect(
      settings.markTodoItemDeleted(
        ' todo ',
        ' item ',
        DateTime.utc(2026, 7, 1, 9),
      ),
      false,
    );

    expect(settings.deletedPaperTombstones['paper'], ten.toIso8601String());
    expect(
      settings.deletedTodoItemTombstones['paper']?['item'],
      tenThirty.toIso8601String(),
    );
    expect(
      settings.deletedTodoItemTombstones['todo']?['item'],
      ten.toIso8601String(),
    );

    expect(
      settings.markTodoItemDeleted(
        'todo',
        'item',
        DateTime.utc(2026, 7, 1, 11),
      ),
      true,
    );
    expect(
      settings.markPaperDeleted('paper', DateTime.utc(2026, 7, 1, 11)),
      true,
    );

    expect(
      settings.deletedPaperTombstones['paper'],
      DateTime.utc(2026, 7, 1, 11).toIso8601String(),
    );
    expect(settings.deletedTodoItemTombstones.containsKey('paper'), false);
    expect(
      settings.deletedTodoItemTombstones['todo']?['item'],
      DateTime.utc(2026, 7, 1, 11).toIso8601String(),
    );
  });

  test('paper tombstones keep newer todo item tombstones', () {
    final nineThirty = DateTime.utc(2026, 7, 1, 9, 30);
    final ten = DateTime.utc(2026, 7, 1, 10);
    final tenThirty = DateTime.utc(2026, 7, 1, 10, 30);
    final settings = SyncSettings(
      deletedTodoItemTombstones: {
        'paper': {
          'before': nineThirty.toIso8601String(),
          'same': ten.toIso8601String(),
          'after': tenThirty.toIso8601String(),
          'invalid': 'not-a-date',
        },
      },
    );

    settings.markPaperDeleted('paper', ten);

    expect(settings.deletedPaperTombstones['paper'], ten.toIso8601String());
    expect(settings.deletedTodoItemTombstones['paper'], {
      'after': tenThirty.toIso8601String(),
    });
  });

  test('todo item tombstones skip records covered by paper tombstones', () {
    final nineThirty = DateTime.utc(2026, 7, 1, 9, 30);
    final ten = DateTime.utc(2026, 7, 1, 10);
    final tenThirty = DateTime.utc(2026, 7, 1, 10, 30);
    final settings = SyncSettings(
      deletedPaperTombstones: {'paper': ten.toIso8601String()},
      deletedTodoItemTombstones: {
        'paper': {
          'old': nineThirty.toIso8601String(),
          'new': tenThirty.toIso8601String(),
        },
      },
    );

    settings
      ..markTodoItemDeleted('paper', 'same', ten)
      ..markTodoItemDeleted('paper', 'older', nineThirty)
      ..markTodoItemDeleted('paper', 'newer', tenThirty);

    expect(settings.deletedTodoItemTombstones['paper'], {
      'new': tenThirty.toIso8601String(),
      'newer': tenThirty.toIso8601String(),
    });
  });

  test('normalizes todo item tombstones covered by paper tombstones', () {
    final nineThirty = DateTime.utc(2026, 7, 1, 9, 30);
    final ten = DateTime.utc(2026, 7, 1, 10);
    final tenThirty = DateTime.utc(2026, 7, 1, 10, 30);

    final settings = SyncSettings.fromJson({
      'deletedPaperTombstones': {' paper ': ten.toIso8601String()},
      'deletedTodoItemTombstones': {
        ' paper ': {
          'before': nineThirty.toIso8601String(),
          'same': ten.toIso8601String(),
          'after': tenThirty.toIso8601String(),
        },
      },
    });

    expect(settings.deletedPaperTombstones, {'paper': ten.toIso8601String()});
    expect(settings.deletedTodoItemTombstones, {
      'paper': {'after': tenThirty.toIso8601String()},
    });
  });

  test('drops tombstones with invalid timestamps during normalization', () {
    final settings = SyncSettings.fromJson({
      'deletedPaperTombstones': {
        'valid-paper': '2026-07-01T10:00:00Z',
        'overflow-month': '2026-13-01T10:00:00Z',
        'overflow-day': '2026-02-30T10:00:00Z',
        'missing-zone': '2026-07-01T10:00:00',
        'too-precise': '2026-07-01T10:00:00.1234567Z',
        'edge-space': ' 2026-07-01T10:00:00Z ',
      },
      'deletedTodoItemTombstones': {
        'todo': {
          'valid-item': '2026-07-01T10:30:00Z',
          'overflow-time': '2026-07-01T24:00:00Z',
          'missing-zone': '2026-07-01T10:30:00',
          'too-precise': '2026-07-01T10:30:00.1234567Z',
          'edge-space': ' 2026-07-01T10:30:00Z ',
        },
      },
    });

    expect(settings.deletedPaperTombstones, {
      'valid-paper': DateTime.utc(2026, 7, 1, 10).toIso8601String(),
    });
    expect(settings.deletedTodoItemTombstones, {
      'todo': {
        'valid-item': DateTime.utc(2026, 7, 1, 10, 30).toIso8601String(),
      },
    });
  });

  test('drops tombstones with control-character ids', () {
    final deletedAt = DateTime.utc(2026, 7, 1, 10);
    final settings = SyncSettings.fromJson({
      'deletedPaperTombstones': {
        'valid-paper': deletedAt.toIso8601String(),
        'bad\u0000paper': deletedAt.toIso8601String(),
        '\nedge-control-paper': deletedAt.toIso8601String(),
      },
      'deletedTodoItemTombstones': {
        'todo': {
          'valid-item': deletedAt.toIso8601String(),
          'bad\u007Fitem': deletedAt.toIso8601String(),
          'edge-control-item\r': deletedAt.toIso8601String(),
        },
        'bad\u0085paper': {
          'dropped-item': deletedAt.toIso8601String(),
        },
      },
    });

    expect(settings.deletedPaperTombstones, {
      'valid-paper': deletedAt.toIso8601String(),
    });
    expect(settings.deletedTodoItemTombstones, {
      'todo': {'valid-item': deletedAt.toIso8601String()},
    });

    expect(settings.isPaperDeleted('valid-paper'), true);
    expect(settings.isPaperDeleted('bad\u0000paper'), false);
    expect(settings.paperDeletedAtUtc('\nvalid-paper'), isNull);
    expect(settings.isTodoItemDeleted('todo', 'valid-item'), true);
    expect(settings.isTodoItemDeleted('todo', 'bad\u007Fitem'), false);
    expect(settings.todoItemDeletedAtUtc('todo\r', 'valid-item'), isNull);

    expect(settings.markPaperDeleted('new\u0000paper', deletedAt), false);
    expect(settings.markTodoItemDeleted('todo', 'new\nitem', deletedAt), false);
    settings
      ..clearPaperDeleted('valid-paper\n')
      ..clearTodoItemDeleted('todo', 'valid-item\n');

    expect(settings.deletedPaperTombstones, {
      'valid-paper': deletedAt.toIso8601String(),
    });
    expect(settings.deletedTodoItemTombstones, {
      'todo': {'valid-item': deletedAt.toIso8601String()},
    });
  });

  test('normalizes WebDAV provider values case-insensitively', () {
    expect(SyncProviderIds.normalize(' WEBDAV '), SyncProviderIds.webDav);
    expect(SyncProviderIds.normalize('webdav'), SyncProviderIds.webDav);
    expect(SyncProviderIds.normalize('future-provider'), SyncProviderIds.none);

    final settings = SyncSettings.fromJson({
      'enabled': true,
      'provider': 'WEBDAV',
    });

    expect(settings.enabled, true);
    expect(settings.provider, SyncProviderIds.webDav);
  });

  test('skips malformed non-json WebDAV settings objects', () {
    final settings = SyncSettings.fromJson({
      'enabled': true,
      'provider': SyncProviderIds.webDav,
      'webDav': <Object?, Object?>{1: 'not-json-object'},
    });

    expect(settings.enabled, true);
    expect(settings.provider, SyncProviderIds.webDav);
    expect(settings.webDav.endpoint, isEmpty);
    expect(
      settings.webDav.configurationIssues,
      contains(WebDavSyncConfigurationIssue.endpoint),
    );
  });

  test('keeps generic WebDAV settings generic after normalization', () {
    final settings = WebDavSyncSettings(
      presetId: WebDavPresetIds.custom,
      endpoint: ' https://dav.jianguoyun.com/dav/ ',
      username: 'user@example.com',
      password: 'app-password',
      encryptionPassphrase: ' shared sync secret ',
      rootPath: 'RePaperTodo',
    )..normalize();

    expect(settings.presetId, WebDavPresetIds.custom);
    expect(settings.endpoint, 'https://dav.jianguoyun.com/dav/');
    expect(settings.isSecurelyConfigured, true);
  });

  test('rejects Jianguoyun sandbox names longer than 30 characters', () {
    WebDavSyncSettings settings({
      required String presetId,
      required String endpoint,
      required String rootPath,
    }) {
      return WebDavSyncSettings(
        presetId: presetId,
        endpoint: endpoint,
        username: 'user@example.com',
        password: 'app-password',
        encryptionPassphrase: 'shared sync secret',
        rootPath: rootPath,
      )..normalize();
    }

    final accepted = settings(
      presetId: WebDavPresetIds.jianguoyun,
      endpoint: WebDavPresets.jianguoyun.endpointText,
      rootPath: List.filled(30, 'a').join(),
    );
    final rejectedPreset = settings(
      presetId: WebDavPresetIds.jianguoyun,
      endpoint: WebDavPresets.jianguoyun.endpointText,
      rootPath: List.filled(31, 'a').join(),
    );
    final rejectedGenericEndpoint = settings(
      presetId: WebDavPresetIds.custom,
      endpoint: WebDavPresets.jianguoyun.endpointText,
      rootPath: List.filled(31, 'a').join(),
    );

    expect(accepted.isSecurelyConfigured, true);
    expect(accepted.providerRootPathFirstSegmentLengthLimit, 30);
    expect(accepted.hasProviderRootPathLengthViolation, false);
    for (final rejected in [rejectedPreset, rejectedGenericEndpoint]) {
      expect(rejected.providerRootPathFirstSegmentLengthLimit, 30);
      expect(rejected.hasProviderRootPathLengthViolation, true);
      expect(
        rejected.configurationIssues,
        contains(WebDavSyncConfigurationIssue.rootPath),
      );
      expect(rejected.isSecurelyConfigured, false);
    }
  });

  test('uses preset root defaults only when imported WebDAV root is missing',
      () {
    final missingRoot = WebDavSyncSettings.fromJson({
      'presetId': WebDavPresetIds.jianguoyun,
      'endpoint': '',
      'username': 'user@example.com',
      'password': 'app-password',
      'encryptionPassphrase': 'shared sync secret',
    });
    final customRoot = WebDavSyncSettings.fromJson({
      'presetId': WebDavPresetIds.jianguoyun,
      'endpoint': '',
      'username': 'user@example.com',
      'password': 'app-password',
      'encryptionPassphrase': 'shared sync secret',
      'rootPath': 'My Papers',
    });
    final explicitBlankRoot = WebDavSyncSettings.fromJson({
      'presetId': WebDavPresetIds.jianguoyun,
      'endpoint': '',
      'username': 'user@example.com',
      'password': 'app-password',
      'encryptionPassphrase': 'shared sync secret',
      'rootPath': '',
    });

    expect(missingRoot.endpoint, WebDavPresets.jianguoyun.endpointText);
    expect(missingRoot.rootPath, WebDavPresets.jianguoyun.defaultRootPath);
    expect(customRoot.rootPath, 'My Papers');
    expect(explicitBlankRoot.rootPath, isEmpty);
    expect(
      explicitBlankRoot.configurationIssues,
      contains(WebDavSyncConfigurationIssue.rootPath),
    );
  });

  test('applies domestic preset root defaults for new programmatic settings',
      () {
    final blankRoot = WebDavSyncSettings(
      presetId: WebDavPresetIds.jianguoyun,
      endpoint: '',
      username: 'user@example.com',
      password: 'app-password',
      encryptionPassphrase: 'shared sync secret',
      rootPath: '',
    )..normalize();
    final unsafeRoot = WebDavSyncSettings(
      presetId: WebDavPresetIds.jianguoyun,
      endpoint: '',
      username: 'user@example.com',
      password: 'app-password',
      encryptionPassphrase: 'shared sync secret',
      rootPath: '../Other',
    )..normalize();

    expect(blankRoot.endpoint, WebDavPresets.jianguoyun.endpointText);
    expect(blankRoot.rootPath, WebDavPresets.jianguoyun.defaultRootPath);
    expect(blankRoot.isSecurelyConfigured, true);
    expect(unsafeRoot.endpoint, WebDavPresets.jianguoyun.endpointText);
    expect(unsafeRoot.rootPath, isEmpty);
    expect(
      unsafeRoot.configurationIssues,
      contains(WebDavSyncConfigurationIssue.rootPath),
    );
  });

  test('normalizes domestic WebDAV preset aliases during settings import', () {
    final settings = WebDavSyncSettings.fromJson({
      'presetId': '坚果云 WebDAV',
      'endpoint': '',
      'username': 'user@example.com',
      'password': 'app-password',
      'encryptionPassphrase': 'shared sync secret',
    });

    expect(settings.presetId, WebDavPresetIds.jianguoyun);
    expect(settings.endpoint, WebDavPresets.jianguoyun.endpointText);
    expect(settings.rootPath, WebDavPresets.jianguoyun.defaultRootPath);
    expect(settings.isSecurelyConfigured, true);
    expect(settings.toJson()['presetId'], WebDavPresetIds.jianguoyun);
  });

  test('requires encryption passphrase for secure WebDAV configuration', () {
    final settings = WebDavSyncSettings(
      endpoint: 'https://dav.example.test/dav/',
      username: 'user',
      password: 'pass',
      rootPath: 'repapertodo',
    )..normalize();

    expect(settings.isConfigured, true);
    expect(settings.usesEncryptedPayloads, false);
    expect(settings.isSecurelyConfigured, false);

    settings.encryptionPassphrase = ' shared sync secret ';
    settings.normalize();

    expect(settings.encryptionPassphrase, 'shared sync secret');
    expect(settings.usesEncryptedPayloads, true);
    expect(settings.isSecurelyConfigured, true);
  });

  test('normalizes WebDAV Basic Auth username while preserving password', () {
    final settings = WebDavSyncSettings(
      endpoint: 'https://dav.example.test/dav/',
      username: ' user@example.com ',
      password: ' app:password ',
      encryptionPassphrase: 'shared sync secret',
      rootPath: 'repapertodo',
    )..normalize();
    final copied = settings.copy();

    expect(settings.username, 'user@example.com');
    expect(settings.password, ' app:password ');
    expect(settings.toJson()['username'], 'user@example.com');
    expect(settings.toJson()['password'], ' app:password ');
    expect(copied.username, 'user@example.com');
    expect(copied.password, ' app:password ');
    expect(settings.isSecurelyConfigured, true);
  });

  test('rejects invalid WebDAV encryption passphrases', () {
    for (final passphrase in const [
      'shared\nsecret',
      'shared\u007Fsecret',
      'shared\u0085secret',
    ]) {
      final settings = WebDavSyncSettings(
        endpoint: 'https://dav.example.test/dav/',
        username: 'user',
        password: 'pass',
        rootPath: 'repapertodo',
        encryptionPassphrase: passphrase,
      )..normalize();

      expect(settings.isConfigured, true);
      expect(settings.usesEncryptedPayloads, false);
      expect(settings.isSecurelyConfigured, false);
      expect(
        settings.secureConfigurationIssues,
        contains(WebDavSyncConfigurationIssue.encryptionPassphrase),
      );
    }
  });

  test('normalizes WebDAV auto-sync interval minutes', () {
    final defaults = WebDavSyncSettings();
    final tooLow = WebDavSyncSettings(autoSyncIntervalMinutes: 0)..normalize();
    final tooHigh = WebDavSyncSettings(autoSyncIntervalMinutes: 2000)
      ..normalize();
    final parsed = WebDavSyncSettings.fromJson({
      'autoSyncIntervalMinutes': 45,
    });
    final copied = WebDavSyncSettings(autoSyncIntervalMinutes: 75).copy();

    expect(defaults.autoSyncIntervalMinutes, 15);
    expect(tooLow.autoSyncIntervalMinutes, 1);
    expect(tooHigh.autoSyncIntervalMinutes, 1440);
    expect(parsed.autoSyncIntervalMinutes, 45);
    expect(parsed.toJson()['autoSyncIntervalMinutes'], 45);
    expect(copied.autoSyncIntervalMinutes, 75);
  });

  test('normalizes sync operation device sequences from strict integers', () {
    final settings = SyncSettings.fromJson({
      'operationDeviceSequences': {
        ' Device A ': '7',
        'device-a': 8,
        'device-b': 2.0,
        'device-j': 1e0,
        'device-c': 1.2,
        'device-d': '1.2',
        'device-i': '1e0',
        'device-plus': '+1',
        'device-e': 0,
        'device-f': maxSyncDeviceSequence + 1,
        'device-g': ' 9',
        'device-h': '9 ',
        'bad': 9,
      },
    });

    expect(settings.operationDeviceSequences, {
      'device-a': 8,
    });
  });

  test('normalizes WebDAV request timeout seconds', () {
    final tooLow = WebDavSyncSettings(requestTimeoutSeconds: 0)..normalize();
    final tooHigh = WebDavSyncSettings(requestTimeoutSeconds: 999)..normalize();
    final parsed = WebDavSyncSettings.fromJson({
      'requestTimeoutSeconds': 45,
    });
    final copied = WebDavSyncSettings(requestTimeoutSeconds: 75).copy();

    expect(tooLow.requestTimeoutSeconds, 1);
    expect(tooHigh.requestTimeoutSeconds, 300);
    expect(parsed.requestTimeoutSeconds, 45);
    expect(parsed.toJson()['requestTimeoutSeconds'], 45);
    expect(copied.requestTimeoutSeconds, 75);
  });

  test('normalizes WebDAV root paths from desktop-style input', () {
    final windowsSeparators = WebDavSyncSettings(
      rootPath: r' \ Team Space \ . \ RePaperTodo \ ',
    )..normalize();
    final encodedSeparators = WebDavSyncSettings(
      rootPath: 'Team%20Space%2FRePaperTodo',
    )..normalize();
    final utf8 = WebDavSyncSettings(
      rootPath: 'Team%20%E2%82%AC/RePaperTodo',
    )..normalize();
    final blank = WebDavSyncSettings(rootPath: '   ')..normalize();
    final empty = WebDavSyncSettings(rootPath: '')..normalize();

    expect(windowsSeparators.rootPath, 'Team Space/RePaperTodo');
    expect(encodedSeparators.rootPath, 'Team Space/RePaperTodo');
    expect(utf8.rootPath, 'Team €/RePaperTodo');
    expect(blank.rootPath, 'repapertodo');
    expect(empty.rootPath, isEmpty);
    expect(
      empty.configurationIssues,
      contains(WebDavSyncConfigurationIssue.rootPath),
    );
  });

  test('rejects unsafe WebDAV root path segments', () {
    for (final rootPath in const [
      '../Other',
      r'RePaperTodo\..\Other',
      'RePaperTodo/%2e%2e/Other',
      'RePaperTodo/bad%',
      'RePaperTodo/%0AOther',
      'RePaperTodo/%7FOther',
      'RePaperTodo/\u0085Other',
      'RePaperTodo/%C2%85Other',
      'RePaperTodo/%20/Other',
      'RePaperTodo/ /Other',
      'RePaperTodo//Other',
    ]) {
      final settings = WebDavSyncSettings(rootPath: rootPath)..normalize();

      expect(settings.rootPath, isEmpty);
      expect(
        settings.configurationIssues,
        contains(WebDavSyncConfigurationIssue.rootPath),
      );
    }
  });

  test('keeps unsafe WebDAV root paths incomplete after repeated normalize',
      () {
    final settings = WebDavSyncSettings(
      rootPath: 'RePaperTodo/%0AOther',
    )..normalize();

    expect(settings.rootPath, isEmpty);
    expect(
      settings.configurationIssues,
      contains(WebDavSyncConfigurationIssue.rootPath),
    );

    settings.normalize();

    expect(settings.rootPath, isEmpty);
    expect(
      settings.configurationIssues,
      contains(WebDavSyncConfigurationIssue.rootPath),
    );
  });

  test('normalizes valid WebDAV endpoints before saving', () {
    final mixedCase = WebDavSyncSettings(
      endpoint: ' HTTPS://DAV.EXAMPLE.TEST/dav ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final spacedPath = WebDavSyncSettings(
      endpoint: 'https://dav.example.test/dav/Team%20Space',
      username: 'user',
      password: 'pass',
    )..normalize();
    final utf8Path = WebDavSyncSettings(
      endpoint: 'https://dav.example.test/dav/Team%20%E2%82%AC',
      username: 'user',
      password: 'pass',
    )..normalize();
    final rootEndpoint = WebDavSyncSettings(
      endpoint: 'https://dav.example.test',
      username: 'user',
      password: 'pass',
    )..normalize();
    final invalid = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav/%2e%2e/files ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final controlCharacterPath = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav/%0Afiles ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final delCharacterPath = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav/%7Ffiles ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final rawC1CharacterPath = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav/\u0085files ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final c1CharacterPath = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav/%C2%85files ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final encodedSeparatorPath = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav%2Ffiles ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final blankSegmentPath = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav/%20/files ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final emptySegmentPath = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav//files ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final leadingWhitespaceSegmentPath = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav/%20files ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final trailingWhitespaceSegmentPath = WebDavSyncSettings(
      endpoint: ' https://dav.example.test/dav/files%20 ',
      username: 'user',
      password: 'pass',
    )..normalize();
    final encodedAuthorityAtSign = WebDavSyncSettings(
      endpoint: ' https://dav.example%40evil.test/dav/ ',
      username: 'user',
      password: 'pass',
    )..normalize();

    expect(mixedCase.endpoint, 'https://dav.example.test/dav/');
    expect(mixedCase.isConfigured, true);
    expect(spacedPath.endpoint, 'https://dav.example.test/dav/Team%20Space/');
    expect(spacedPath.isConfigured, true);
    expect(utf8Path.endpoint, 'https://dav.example.test/dav/Team%20%E2%82%AC/');
    expect(utf8Path.isConfigured, true);
    expect(rootEndpoint.endpoint, 'https://dav.example.test/');
    expect(rootEndpoint.isConfigured, true);
    expect(invalid.endpoint, 'https://dav.example.test/dav/%2e%2e/files');
    expect(invalid.isConfigured, false);
    expect(
        controlCharacterPath.endpoint, 'https://dav.example.test/dav/%0Afiles');
    expect(controlCharacterPath.isConfigured, false);
    expect(delCharacterPath.endpoint, 'https://dav.example.test/dav/%7Ffiles');
    expect(delCharacterPath.isConfigured, false);
    expect(rawC1CharacterPath.endpoint,
        'https://dav.example.test/dav/\u0085files');
    expect(rawC1CharacterPath.isConfigured, false);
    expect(
        c1CharacterPath.endpoint, 'https://dav.example.test/dav/%C2%85files');
    expect(c1CharacterPath.isConfigured, false);
    expect(
        encodedSeparatorPath.endpoint, 'https://dav.example.test/dav%2Ffiles');
    expect(encodedSeparatorPath.isConfigured, false);
    expect(blankSegmentPath.endpoint, 'https://dav.example.test/dav/%20/files');
    expect(blankSegmentPath.isConfigured, false);
    expect(emptySegmentPath.endpoint, 'https://dav.example.test/dav//files');
    expect(emptySegmentPath.isConfigured, false);
    expect(leadingWhitespaceSegmentPath.endpoint,
        'https://dav.example.test/dav/%20files');
    expect(leadingWhitespaceSegmentPath.isConfigured, false);
    expect(trailingWhitespaceSegmentPath.endpoint,
        'https://dav.example.test/dav/files%20');
    expect(trailingWhitespaceSegmentPath.isConfigured, false);
    expect(encodedAuthorityAtSign.endpoint,
        'https://dav.example%40evil.test/dav/');
    expect(encodedAuthorityAtSign.isConfigured, false);
  });

  test('reports WebDAV configuration issues for field-level recovery', () {
    final settings = WebDavSyncSettings(
      endpoint: 'dav.example.test/dav',
      username: 'user:name',
      password: 'bad\npass',
      rootPath: '../Other',
    )..normalize();

    expect(settings.configurationIssues, {
      WebDavSyncConfigurationIssue.endpoint,
      WebDavSyncConfigurationIssue.username,
      WebDavSyncConfigurationIssue.password,
      WebDavSyncConfigurationIssue.rootPath,
    });
    expect(settings.secureConfigurationIssues, {
      WebDavSyncConfigurationIssue.endpoint,
      WebDavSyncConfigurationIssue.username,
      WebDavSyncConfigurationIssue.password,
      WebDavSyncConfigurationIssue.rootPath,
      WebDavSyncConfigurationIssue.encryptionPassphrase,
    });
  });

  test('rejects whitespace-only WebDAV Basic Auth usernames', () {
    final settings = WebDavSyncSettings(
      endpoint: 'https://dav.example.test/dav/',
      username: '   ',
      password: 'pass',
      rootPath: 'repapertodo',
      encryptionPassphrase: 'shared sync secret',
    );

    expect(settings.configurationIssues,
        contains(WebDavSyncConfigurationIssue.username));
    expect(settings.secureConfigurationIssues,
        contains(WebDavSyncConfigurationIssue.username));

    settings.normalize();

    expect(settings.username, isEmpty);
    expect(settings.isSecurelyConfigured, false);
    expect(settings.secureConfigurationIssues,
        contains(WebDavSyncConfigurationIssue.username));
  });
}
