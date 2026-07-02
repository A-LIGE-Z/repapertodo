import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
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
    final blank = WebDavSyncSettings(rootPath: '   ')..normalize();
    final empty = WebDavSyncSettings(rootPath: '')..normalize();

    expect(windowsSeparators.rootPath, 'Team Space/RePaperTodo');
    expect(encodedSeparators.rootPath, 'Team Space/RePaperTodo');
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

    expect(mixedCase.endpoint, 'https://dav.example.test/dav/');
    expect(mixedCase.isConfigured, true);
    expect(spacedPath.endpoint, 'https://dav.example.test/dav/Team%20Space/');
    expect(spacedPath.isConfigured, true);
    expect(rootEndpoint.endpoint, 'https://dav.example.test/');
    expect(rootEndpoint.isConfigured, true);
    expect(invalid.endpoint, 'https://dav.example.test/dav/%2e%2e/files');
    expect(invalid.isConfigured, false);
    expect(
        controlCharacterPath.endpoint, 'https://dav.example.test/dav/%0Afiles');
    expect(controlCharacterPath.isConfigured, false);
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
}
