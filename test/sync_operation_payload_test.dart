import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('accepts well-formed sync operation payloads', () {
    expect(
      isSyncOperationPayloadWellFormed(
        _operation(
          kind: SyncOperationKind.stateSnapshot,
          payload: {'snapshotPath': 'repapertodo/snapshots/state.json'},
        ),
      ),
      true,
    );
    expect(
      isSyncOperationPayloadWellFormed(
        _operation(
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'Paper': {
              'Id': 'paper-1',
              'Type': PaperTypes.note,
              'Title': 'Remote note',
            },
          },
        ),
      ),
      true,
    );
    expect(
      isSyncOperationPayloadWellFormed(
        _operation(
          kind: SyncOperationKind.upsertPaper,
          payload: {
            'Paper': {
              'Id': 'paper-legacy-canvas',
              'Type': PaperTypes.note,
              'NoteCanvasElements': [
                {'Id': 'sticky-block', 'Type': 'STICKY'},
              ],
            },
          },
        ),
      ),
      true,
    );
    expect(
      isSyncOperationPayloadWellFormed(
        _operation(
          kind: SyncOperationKind.upsertTodoItem,
          payload: {
            'paperId': 'todo',
            'item': {
              'Id': 'item-1',
              'Text': 'Remote item',
              'DueAtLocal': '2026/6/30 9:08',
            },
          },
        ),
      ),
      true,
    );
    expect(
      isSyncOperationPayloadWellFormed(
        _operation(
          kind: SyncOperationKind.updateSettings,
          payload: {
            'settings': {
              'enableToolTips': true,
              'futureRemoteOnlySetting': true,
            },
          },
        ),
      ),
      true,
    );
    expect(
      applicableSyncOperationSettingsPayload({
        'EnableToolTips': false,
        'Sync': {'enabled': false},
        'StartAtLogin': true,
        'futureRemoteOnlySetting': true,
      }),
      {'enableToolTips': false},
    );
  });

  test('compares legacy-cased payloads by operation semantics', () {
    final modern = _operation(
      kind: SyncOperationKind.updateNoteContent,
      deviceId: 'Device A',
      id: 'stale-operation-id',
      payload: {'paperId': 'note', 'content': 'Remote'},
    );
    final legacy = _operation(
      kind: SyncOperationKind.updateNoteContent,
      deviceId: 'device-a',
      id: 'device-a-1',
      payload: {'PaperId': 'note', 'Content': 'Remote'},
    );
    final different = _operation(
      kind: SyncOperationKind.updateNoteContent,
      deviceId: 'device-a',
      id: 'device-a-1',
      payload: {'PaperId': 'note', 'Content': 'Different'},
    );

    expect(areSyncOperationsEquivalent(modern, legacy), true);
    expect(areSyncOperationsEquivalent(modern, different), false);
  });

  test('compares upsert payloads by model-normalized semantics', () {
    final legacyPaper = _operation(
      kind: SyncOperationKind.upsertPaper,
      payload: {
        'Paper': {
          'Id': ' note ',
          'Type': 'NOTE',
          'Title': 'Remote note',
          'TextZoom': 9,
          'NoteCanvasElements': [
            {
              'Id': ' block ',
              'Type': 'TEXT',
              'Width': 72,
              'Height': 48,
              'ZIndex': 0,
            },
          ],
        },
      },
    );
    final modernPaper = _operation(
      kind: SyncOperationKind.upsertPaper,
      payload: {
        'paper': PaperData.fromJson({
          'id': ' note ',
          'type': 'NOTE',
          'title': 'Remote note',
          'textZoom': 9,
          'noteCanvasElements': [
            {
              'id': ' block ',
              'type': 'TEXT',
              'width': 72,
              'height': 48,
              'zIndex': 0,
            },
          ],
        }).toJson(),
      },
    );
    final legacyItem = _operation(
      kind: SyncOperationKind.upsertTodoItem,
      payload: {
        'PaperId': ' todo ',
        'Item': {
          'Id': ' item ',
          'Text': 'Remote item',
          'TodoColumnCount': 9,
          'TodoExtraColumns': ['A', 'B', 'C', 'D'],
          'TodoColumnWidths': [0, 1.23456, 99],
          'ReminderIntervalValue': 999,
          'ReminderIntervalUnit': 'HOURS',
        },
      },
    );
    final modernItem = _operation(
      kind: SyncOperationKind.upsertTodoItem,
      payload: {
        'paperId': 'todo',
        'item': PaperItem.fromJson({
          'id': ' item ',
          'text': 'Remote item',
          'todoColumnCount': 9,
          'todoExtraColumns': ['A', 'B', 'C', 'D'],
          'todoColumnWidths': [0, 1.23456, 99],
          'reminderIntervalValue': 999,
          'reminderIntervalUnit': 'HOURS',
        }).toJson(),
      },
    );

    expect(isSyncOperationPayloadWellFormed(legacyPaper), true);
    expect(isSyncOperationPayloadWellFormed(legacyItem), true);
    expect(
      canonicalSyncOperationPayload(legacyPaper),
      canonicalSyncOperationPayload(modernPaper),
    );
    expect(
      canonicalSyncOperationPayload(legacyItem),
      canonicalSyncOperationPayload(modernItem),
    );
    expect(areSyncOperationsEquivalent(legacyPaper, modernPaper), true);
    expect(areSyncOperationsEquivalent(legacyItem, modernItem), true);
  });

  test('compares encoded snapshot marker paths by decoded semantics', () {
    final encoded = _operation(
      kind: SyncOperationKind.stateSnapshot,
      payload: {'snapshotPath': 'repapertodo/snapshots/state%2Ejson'},
    );
    final decoded = _operation(
      kind: SyncOperationKind.stateSnapshot,
      payload: {'snapshotPath': 'repapertodo/snapshots/state.json'},
    );

    expect(isSyncOperationPayloadWellFormed(encoded), true);
    expect(canonicalSyncOperationPayload(encoded), {
      'snapshotPath': 'repapertodo/snapshots/state.json',
    });
    expect(areSyncOperationsEquivalent(encoded, decoded), true);
  });

  test('compares legacy settings payloads by current app semantics', () {
    final retiredTopBar = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {'ShowTopBarNewPaperButtons': false},
      },
    );
    final splitTopBar = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'showTopBarNewTodoButton': false,
          'showTopBarNewNoteButton': false,
        },
      },
    );
    final legacyFullscreen = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {'HideDeepCapsulesWhenFullscreen': true},
      },
    );
    final legacyFullscreenOff = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {'HideDeepCapsulesWhenFullscreen': false},
      },
    );
    final legacyFullscreenString = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {'HideDeepCapsulesWhenFullscreen': 'true'},
      },
    );
    final covered = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {'hideDeepCapsulesWhenCovered': true},
      },
    );

    expect(canonicalSyncOperationPayload(retiredTopBar), {
      'settings': {
        'showTopBarNewTodoButton': false,
        'showTopBarNewNoteButton': false,
      },
    });
    expect(areSyncOperationsEquivalent(retiredTopBar, splitTopBar), true);
    expect(canonicalSyncOperationPayload(legacyFullscreen), {
      'settings': {'hideDeepCapsulesWhenFullscreen': true},
    });
    expect(areSyncOperationsEquivalent(legacyFullscreen, covered), false);
    expect(canonicalSyncOperationPayload(legacyFullscreenOff), {
      'settings': {'hideDeepCapsulesWhenFullscreen': false},
    });
    expect(canonicalSyncOperationPayload(legacyFullscreenString), {
      'settings': {'hideDeepCapsulesWhenFullscreen': true},
    });
  });

  test('compares boolean settings by parsed app semantics', () {
    final stringValue = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {'enableToolTips': 'false'},
      },
    );
    final boolValue = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {'enableToolTips': false},
      },
    );

    expect(isSyncOperationPayloadWellFormed(stringValue), true);
    expect(canonicalSyncOperationPayload(stringValue), {
      'settings': {'enableToolTips': false},
    });
    expect(areSyncOperationsEquivalent(stringValue, boolValue), true);
  });

  test('compares numeric settings by parsed app semantics', () {
    final stringValue = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'zoom': '9',
          'todoLineSpacing': '1.234',
          'todoReminderIntervalValue': '15',
          'maxTitleLength': '999',
        },
      },
    );
    final numericValue = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'zoom': 1.5,
          'todoLineSpacing': 1.23,
          'todoReminderIntervalValue': 15,
          'maxTitleLength': 20,
        },
      },
    );

    expect(isSyncOperationPayloadWellFormed(stringValue), true);
    expect(canonicalSyncOperationPayload(stringValue), {
      'settings': {
        'zoom': 1.5,
        'todoLineSpacing': 1.23,
        'todoReminderIntervalValue': 15,
        'maxTitleLength': 20,
      },
    });
    expect(areSyncOperationsEquivalent(stringValue, numericValue), true);
  });

  test(
      'drops signed padded or exponent double setting strings instead of coercing them',
      () {
    final mixedValue = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'theme': 'dark',
          'zoom': '+1',
          'todoLineSpacing': ' 1.2 ',
          'noteLineSpacing': '1e0',
          'deepCapsuleStartTopMargin': '-4',
          'deepCapsuleQueueStartTopMargins': {
            'left': '+16',
            'right': ' 16.25 ',
            'Primary|left': '1e2',
            'Primary|right': '16.',
          },
        },
      },
    );

    expect(isSyncOperationPayloadWellFormed(mixedValue), true);
    expect(canonicalSyncOperationPayload(mixedValue), {
      'settings': {'theme': 'dark'},
    });
  });

  test('drops fractional integer settings instead of coercing them', () {
    final mixedValue = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'theme': 'dark',
          'todoReminderIntervalValue': 15.0,
          'todoReminderBubbleDurationSeconds': 5.5,
          'maxTitleLength': 6.2,
        },
      },
    );

    expect(isSyncOperationPayloadWellFormed(mixedValue), true);
    expect(canonicalSyncOperationPayload(mixedValue), {
      'settings': {'theme': 'dark'},
    });
  });

  test(
      'drops signed or padded integer setting strings instead of coercing them',
      () {
    final mixedValue = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'theme': 'dark',
          'todoReminderIntervalValue': '+15',
          'todoReminderBubbleDurationSeconds': ' 5 ',
          'maxTitleLength': '6.0',
        },
      },
    );

    expect(isSyncOperationPayloadWellFormed(mixedValue), true);
    expect(canonicalSyncOperationPayload(mixedValue), {
      'settings': {'theme': 'dark'},
    });
  });

  test('compares string and queue-map settings by parsed app semantics', () {
    final longHotKey = 'Ctrl+Alt+${List.filled(80, 'A').join()}';
    final legacyValue = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'theme': ' DARK ',
          'colorScheme': ' FOREST ',
          'customThemeColorHex': '336699',
          'markdownRenderMode': 'BASIC',
          'todoVisualSize': 'EXTRALARGE',
          'uiFontPreset': 'MONO',
          'systemFontFamilyName': ' \u0000Paper Font\u007F ',
          'externalMarkdownExtension': '*.MD',
          'todoDueYearDisplayMode': 'FULL',
          'todoReminderIntervalUnit': 'HOURS',
          'todoReminderScope': 'NEAREST',
          'pinnedTodoHotKey': ' Ctrl+\nAlt+\u007FT ',
          'pinnedNoteHotKey': '$longHotKey\n',
          'fullscreenTopmostMode': 'STAYONTOP',
          'deepCapsuleSide': 'LEFT',
          'deepCapsuleMonitorDeviceName': ' Primary ',
          'capsuleCollapseAllActiveQueues': {
            'left': 'true',
            ' Primary | RIGHT ': true,
            'Ghost|left': 'false',
          },
          'deepCapsuleQueueStartTopMargins': {
            'left': '16.25',
            ' Primary | RIGHT ': 2,
          },
        },
      },
    );
    final canonicalValue = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'theme': 'dark',
          'colorScheme': 'forest',
          'customThemeColorHex': '#336699',
          'markdownRenderMode': MarkdownRenderModes.basic,
          'todoVisualSize': TodoVisualSizes.extraLarge,
          'uiFontPreset': UiFontPresets.mono,
          'systemFontFamilyName': 'Paper Font',
          'externalMarkdownExtension': '.md',
          'todoDueYearDisplayMode': TodoDueYearDisplayModes.full,
          'todoReminderIntervalUnit': TodoReminderIntervalUnits.hours,
          'todoReminderScope': TodoReminderScopes.nearest,
          'pinnedTodoHotKey': 'Ctrl+Alt+T',
          'pinnedNoteHotKey': longHotKey.substring(0, 64),
          'fullscreenTopmostMode': FullscreenTopmostModes.stayOnTop,
          'deepCapsuleSide': DeepCapsuleSides.left,
          'deepCapsuleMonitorDeviceName': 'Primary',
          'capsuleCollapseAllActiveQueues': {
            '|left': true,
            'Primary|right': true,
          },
          'deepCapsuleQueueStartTopMargins': {
            '|left': 16.25,
            'Primary|right': 8.0,
          },
        },
      },
    );

    expect(isSyncOperationPayloadWellFormed(legacyValue), true);
    expect(
      canonicalSyncOperationPayload(legacyValue),
      canonicalSyncOperationPayload(canonicalValue),
    );
    expect(areSyncOperationsEquivalent(legacyValue, canonicalValue), true);
  });

  test('allows file-name-safe external markdown suffix settings', () {
    final operation = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {'externalMarkdownExtension': '*.TODO.MD'},
      },
    );

    expect(isSyncOperationPayloadWellFormed(operation), true);
    expect(canonicalSyncOperationPayload(operation), {
      'settings': {'externalMarkdownExtension': '.todo.md'},
    });
  });

  test('compares capsule dependency settings by app normalization semantics',
      () {
    final rawDisabledCapsules = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'useCapsuleMode': false,
          'useDeepCapsuleMode': true,
          'useCapsuleCollapseAll': true,
          'capsuleCollapseAllActive': true,
          'capsuleCollapseAllActiveQueues': {
            'left': true,
          },
          'deepCapsuleStartTopMargin': 16,
          'deepCapsuleQueueStartTopMargins': {
            'left': 16,
          },
        },
      },
    );
    final normalizedDisabledCapsules = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'useCapsuleMode': false,
          'useDeepCapsuleMode': false,
          'useCapsuleCollapseAll': false,
          'capsuleCollapseAllActive': false,
          'capsuleCollapseAllActiveQueues': const <String, Object?>{},
          'deepCapsuleStartTopMargin': 48,
          'deepCapsuleQueueStartTopMargins': const <String, Object?>{},
          'hideDeepCapsulesWhenCovered': false,
          'hideDeepCapsulesWhenFullscreen': false,
        },
      },
    );
    final activeDeepQueues = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'useCapsuleMode': true,
          'useDeepCapsuleMode': true,
          'useCapsuleCollapseAll': true,
          'capsuleCollapseAllActive': false,
          'capsuleCollapseAllActiveQueues': {
            'left': true,
          },
        },
      },
    );

    expect(canonicalSyncOperationPayload(rawDisabledCapsules), {
      'settings': {
        'useCapsuleMode': false,
        'useDeepCapsuleMode': false,
        'useCapsuleCollapseAll': false,
        'capsuleCollapseAllActive': false,
        'capsuleCollapseAllActiveQueues': const <String, bool>{},
        'deepCapsuleStartTopMargin': 48.0,
        'deepCapsuleQueueStartTopMargins': const <String, double>{},
        'hideDeepCapsulesWhenCovered': false,
        'hideDeepCapsulesWhenFullscreen': false,
      },
    });
    expect(
      areSyncOperationsEquivalent(
        rawDisabledCapsules,
        normalizedDisabledCapsules,
      ),
      true,
    );
    expect(canonicalSyncOperationPayload(activeDeepQueues), {
      'settings': {
        'useCapsuleMode': true,
        'useDeepCapsuleMode': true,
        'useCapsuleCollapseAll': true,
        'capsuleCollapseAllActive': true,
        'capsuleCollapseAllActiveQueues': {'|left': true},
      },
    });
  });

  test('canonical queue map settings override legacy aliases', () {
    final rawQueues = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'useCapsuleMode': true,
          'useDeepCapsuleMode': true,
          'useCapsuleCollapseAll': true,
          'capsuleCollapseAllActive': false,
          'capsuleCollapseAllActiveQueues': {
            'left': true,
            '|left': false,
            'Primary | right ': false,
            'Primary|right': true,
          },
        },
      },
    );
    final canonicalQueues = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'useCapsuleMode': true,
          'useDeepCapsuleMode': true,
          'useCapsuleCollapseAll': true,
          'capsuleCollapseAllActive': true,
          'capsuleCollapseAllActiveQueues': {
            'Primary|right': true,
          },
        },
      },
    );

    expect(canonicalSyncOperationPayload(rawQueues), {
      'settings': {
        'useCapsuleMode': true,
        'useDeepCapsuleMode': true,
        'useCapsuleCollapseAll': true,
        'capsuleCollapseAllActive': true,
        'capsuleCollapseAllActiveQueues': {
          'Primary|right': true,
        },
      },
    });
    expect(areSyncOperationsEquivalent(rawQueues, canonicalQueues), true);
  });

  test('canonical margin queue map settings override legacy aliases', () {
    final rawMargins = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'useCapsuleMode': true,
          'useDeepCapsuleMode': true,
          'useCapsuleCollapseAll': true,
          'deepCapsuleQueueStartTopMargins': {
            'right': '32.5',
            '|right': 4,
            'Primary | left ': 12,
            'Primary|left': 12000,
          },
        },
      },
    );
    final canonicalMargins = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'useCapsuleMode': true,
          'useDeepCapsuleMode': true,
          'useCapsuleCollapseAll': true,
          'deepCapsuleQueueStartTopMargins': {
            '|right': 8.0,
            'Primary|left': 10000.0,
          },
        },
      },
    );

    expect(canonicalSyncOperationPayload(rawMargins), {
      'settings': {
        'useCapsuleMode': true,
        'useDeepCapsuleMode': true,
        'useCapsuleCollapseAll': true,
        'deepCapsuleQueueStartTopMargins': {
          '|right': 8.0,
          'Primary|left': 10000.0,
        },
      },
    });
    expect(areSyncOperationsEquivalent(rawMargins, canonicalMargins), true);
  });

  test('drops control-character deep capsule monitor and queue settings', () {
    final mixed = _operation(
      kind: SyncOperationKind.updateSettings,
      payload: {
        'settings': {
          'theme': 'dark',
          'deepCapsuleMonitorDeviceName': 'Primary\u0000Monitor',
          'capsuleCollapseAllActiveQueues': {
            'Primary\u007F|left': true,
            'Primary|right': true,
          },
          'deepCapsuleQueueStartTopMargins': {
            'Primary\u0085|left': 32,
            'Primary|right': 64,
          },
        },
      },
    );

    expect(isSyncOperationPayloadWellFormed(mixed), true);
    expect(canonicalSyncOperationPayload(mixed), {
      'settings': {
        'theme': 'dark',
        'capsuleCollapseAllActiveQueues': {'Primary|right': true},
        'deepCapsuleQueueStartTopMargins': {'Primary|right': 64.0},
      },
    });
  });

  test('rejects structurally incomplete sync operation payloads', () {
    final longMarkdownText =
        List.filled(MarkdownPasteText.maxTextLength + 1, 'n').join();
    final longTodoText =
        List.filled(TodoPasteItems.maxLineLength + 1, 't').join();
    final cases = [
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': '   '},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': 'https://example.com/snapshot.json'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': '//example.com/snapshot.json'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': 'repapertodo/../snapshot.json'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': 'repapertodo/./snapshot.json'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': 'repapertodo/%2e/snapshot.json'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': 'repapertodo//snapshot.json'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': '/repapertodo/snapshot.json'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': 'repapertodo/snapshot.json/'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': r'repapertodo\snapshot.json'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': 'repapertodo/%2F/snapshot.json'},
      ),
      _operation(
        kind: SyncOperationKind.stateSnapshot,
        payload: {'snapshotPath': 'repapertodo/snapshot\u0000.json'},
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'title': 'Missing ID'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'title': 'Missing type'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper\u0000bad', 'type': PaperTypes.note},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': '\npaper', 'type': PaperTypes.note},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'type': 'memo'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'paper',
            'type': PaperTypes.note,
            'title': {'not': 'a string'},
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'paper',
            'type': PaperTypes.note,
            'title': ' Remote note ',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'paper',
            'type': PaperTypes.note,
            'title': 'Remote\u0000note',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'paper',
            'type': PaperTypes.note,
            'title': List.filled(
              PaperTitles.maxTitleLength + 1,
              'A',
            ).join(),
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'paper',
            'content': ['not', 'a string']
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'paper',
            'type': PaperTypes.note,
            'content': longMarkdownText,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'content': 'Hidden todo body',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'x': '120'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'height': double.nan},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'width': 12},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'height': 12},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'isVisible': 'true'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'textZoom': '1.25'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'textZoom': 0},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'textZoom': -1},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'capsuleSide': 'center'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'capsuleSide': 'left\u0000'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {'id': 'paper', 'capsuleMonitorDeviceName': 'Primary\u0000'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': 'not-a-list',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'noteCanvasElements': [
              {'id': 'block-1', 'type': 'text'},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {
                'id': 'item-1',
                'text': longTodoText,
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {
                'id': 'item-1',
                'text': 'Extra column too long',
                'todoColumnCount': 2,
                'todoExtraColumns': [longTodoText],
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'items': [
              {
                'id': 'item-1',
                'text': 'Wrong collection',
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {'id': 'item-1', 'text': 'Valid item'},
              'not-a-json-object',
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {
                'id': 'item-1',
                'text': 'Column widths without count',
                'todoColumnWidths': [1],
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {
                'id': 'item-1',
                'text': 'Non-positive column count',
                'todoColumnCount': 0,
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {
                'id': 'item-1',
                'text': 'Blank linked note ID',
                'linkedNoteId': '   ',
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              <Object?, Object?>{1: 'not-string-keyed'},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {'id': 'item\u007Fbad', 'text': 'Unsafe item ID'},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {'id': 'item-1', 'text': 'First'},
              {'id': ' item-1 ', 'text': 'Duplicate'},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {
                'id': 'item-1',
                'text': 'Unsafe linked note ID',
                'linkedNoteId': 'note\u0085bad',
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {
                'id': 'item-1',
                'text': 'Malformed extra columns',
                'todoExtraColumns': 'not-a-list',
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {
                'id': 'item-1',
                'text': 'Malformed column widths',
                'todoColumnWidths': [1, '2'],
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'todo',
            'type': PaperTypes.todo,
            'items': [
              {
                'id': 'item-1',
                'text': 'Negative column width',
                'todoColumnWidths': [-1],
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {
                'id': 'block-1',
                'text': longMarkdownText,
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': 'not-a-list',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'type': 'text'},
              'not-a-json-object',
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'type': ''},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'type': ' text '},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'type': 'diagram'},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'type': 'text\u0000'},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'x': -2000.1},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'y': 8000.1},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'width': 12},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'height': 12},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'width': 1600.1},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'height': 1600.1},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'type': 'text'},
              {'id': ' block-1 ', 'type': 'text'},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block\u0001bad', 'type': 'text'},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'type': 7},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {
                'id': 'block-1',
                'text': {'not': 'string'}
              },
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'x': '32'},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'width': double.infinity},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'zIndex': 1.5},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertPaper,
        payload: {
          'paper': {
            'id': 'note',
            'type': PaperTypes.note,
            'noteCanvasElements': [
              {'id': 'block-1', 'zIndex': -1},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.deletePaper,
        payload: {'paperId': ''},
      ),
      _operation(
        kind: SyncOperationKind.deletePaper,
        payload: {'paperId': 'paper\u0000bad'},
      ),
      _operation(
        kind: SyncOperationKind.deletePaper,
        payload: {'paperId': 'paper\r'},
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {'text': 'Missing item ID'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo\u0000bad',
          'item': {'id': 'item-1', 'text': 'Bad paper ID'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {'id': 'item\u007Fbad', 'text': 'Bad item ID'},
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad linked note ID',
            'linkedNoteId': 'note\u0085bad',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Blank linked note ID',
            'linkedNoteId': '   ',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad linked note ID type',
            'linkedNoteId': 42,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': {'not': 'a string'},
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': longTodoText,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad done type',
            'done': 'true',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad order type',
            'order': 1.5,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad column count type',
            'TodoColumnCount': '2',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Zero column count',
            'todoColumnCount': 0,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Negative column count',
            'todoColumnCount': -1,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad due date type',
            'dueAtLocal': ['2026-07-01T09:00:00'],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad due date text',
            'dueAtLocal': 'not a date',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad blank due date',
            'dueAtLocal': '   ',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad control due date',
            'dueAtLocal': '2026-07-01T09:00:00\u0000',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad reminder interval value type',
            'reminderIntervalValue': 2.5,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad reminder interval zero value',
            'reminderIntervalValue': 0,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad reminder interval negative value',
            'reminderIntervalValue': -1,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad reminder interval unit type',
            'reminderIntervalUnit': 7,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad reminder interval unit without value',
            'reminderIntervalUnit': TodoReminderIntervalUnits.hours,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad reminder interval unit',
            'reminderIntervalValue': 2,
            'reminderIntervalUnit': 'days',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad reminder interval padded unit',
            'reminderIntervalValue': 2,
            'reminderIntervalUnit': ' hours ',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad reminder interval control unit',
            'reminderIntervalValue': 2,
            'reminderIntervalUnit': 'hours\u0000',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad extra columns',
            'todoExtraColumns': ['A', 2],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Extra column too long',
            'todoColumnCount': 2,
            'todoExtraColumns': [longTodoText],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Bad column widths',
            'todoColumnWidths': 'wide',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Negative column width',
            'todoColumnWidths': [-1],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Extra columns without count',
            'todoExtraColumns': ['Status'],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Too many extra columns',
            'todoColumnCount': 2,
            'todoExtraColumns': ['Status', 'Owner'],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.upsertTodoItem,
        payload: {
          'paperId': 'todo',
          'item': {
            'id': 'item-1',
            'text': 'Too many column widths',
            'todoColumnCount': 2,
            'todoColumnWidths': [1, 1, 1],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.deleteTodoItem,
        payload: {'paperId': 'todo'},
      ),
      _operation(
        kind: SyncOperationKind.deleteTodoItem,
        payload: {'paperId': 'todo', 'itemId': 'item\u0000bad'},
      ),
      _operation(
        kind: SyncOperationKind.deleteTodoItem,
        payload: {'paperId': 'todo\u0000bad', 'itemId': 'item-1'},
      ),
      _operation(
        kind: SyncOperationKind.updateNoteContent,
        payload: {'paperId': 'note', 'content': 42},
      ),
      _operation(
        kind: SyncOperationKind.updateNoteContent,
        payload: {'paperId': 'note\u0000bad', 'content': 'Unsafe target'},
      ),
      _operation(
        kind: SyncOperationKind.updateNoteContent,
        payload: {'paperId': 'note', 'content': longMarkdownText},
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {'settings': const <String, Object?>{}},
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'sync': {'enabled': true},
            'startAtLogin': true,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'papers': [
              {'id': 'paper-1', 'type': PaperTypes.note},
            ],
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'futureRemoteOnlySetting': true,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'ShowTopBarNewPaperButtons': 'false',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'HideDeepCapsulesWhenFullscreen': 'maybe',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'enableToolTips': 'maybe',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'zoom': 'far',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'zoom': '+1',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'todoLineSpacing': ' 1.2 ',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'deepCapsuleStartTopMargin': '1e2',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'deepCapsuleQueueStartTopMargins': {'left': '+16'},
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'todoReminderIntervalValue': 'often',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'todoReminderIntervalValue': 15.0,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'todoReminderBubbleDurationSeconds': 5.5,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'maxTitleLength': 6.2,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'todoReminderIntervalValue': '+15',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'todoReminderBubbleDurationSeconds': ' 5 ',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'maxTitleLength': '6.0',
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'noteLineSpacing': double.nan,
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'theme': 'mystery'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'colorScheme': 'unknown'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'customThemeColorHex': '#not-a-color'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'markdownRenderMode': 'rich'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'todoVisualSize': 'giant'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'uiFontPreset': 'handwritten'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'externalMarkdownExtension': 'md:bad'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'todoDueYearDisplayMode': 'forever'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'todoReminderIntervalUnit': 'days'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'todoReminderScope': 'latest'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'pinnedTodoHotKey': 42},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'fullscreenTopmostMode': 'pin'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'deepCapsuleSide': 'center'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {'deepCapsuleMonitorDeviceName': 'Primary\u0000Monitor'},
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'capsuleCollapseAllActiveQueues': {'Primary|middle': true},
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'capsuleCollapseAllActiveQueues': {'Primary|left': 'maybe'},
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'deepCapsuleQueueStartTopMargins': {'Primary|left': 'far'},
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'capsuleCollapseAllActiveQueues': {'Primary\u0000|left': true},
          },
        },
      ),
      _operation(
        kind: SyncOperationKind.updateSettings,
        payload: {
          'settings': {
            'deepCapsuleQueueStartTopMargins': {'Primary\u007F|left': 32},
          },
        },
      ),
    ];

    for (final operation in cases) {
      expect(
        isSyncOperationPayloadWellFormed(operation),
        false,
        reason: operation.kind.name,
      );
    }
  });
}

SyncOperation _operation({
  required SyncOperationKind kind,
  required Map<String, Object?> payload,
  String id = 'device-a-1',
  String deviceId = 'device-a',
}) {
  return SyncOperation(
    id: id,
    deviceId: deviceId,
    sequence: 1,
    kind: kind,
    createdAtUtc: DateTime.utc(2026, 7, 1, 9),
    payload: payload,
  );
}
