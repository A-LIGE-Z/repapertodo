import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('decodes PaperTodo data and preserves unknown fields', () {
    const source = '''
{
  "theme": "dark",
  "startAtLogin": true,
  "futureRootField": "keep-me",
  "papers": [
    {
      "id": "paper-1",
      "type": "todo",
      "title": "Today",
      "futurePaperField": 42,
      "items": [
        {
          "id": "item-1",
          "text": "Read PaperTodo",
          "done": false,
          "order": 2,
          "futureItemField": true
        }
      ]
    }
  ]
}
''';

    const codec = AppStateCodec();
    final state = codec.decode(source);
    final encoded = jsonDecode(codec.encode(state)) as Map<String, Object?>;
    final papers = encoded['papers'] as List<Object?>;
    final paper = papers.single as Map<String, Object?>;
    final items = paper['items'] as List<Object?>;
    final item = items.single as Map<String, Object?>;

    expect(state.startAtLogin, true);
    expect(encoded['futureRootField'], 'keep-me');
    expect(encoded['startAtLogin'], true);
    expect(paper['futurePaperField'], 42);
    expect(item['futureItemField'], true);
    expect(item['order'], 0);
  });

  test('normalizes invalid PaperTodo enum values', () {
    final state = AppState.fromJson({
      'theme': 'mystery',
      'colorScheme': 'unknown',
      'customThemeColorHex': '#not-a-color',
      'markdownRenderMode': 'rich',
      'todoVisualSize': 'giant',
      'externalMarkdownExtension': 'txt',
    });

    expect(state.theme, 'system');
    expect(state.colorScheme, ColorSchemes.warm);
    expect(state.customThemeColorHex, isEmpty);
    expect(state.markdownRenderMode, MarkdownRenderModes.enhanced);
    expect(state.todoVisualSize, TodoVisualSizes.medium);
    expect(state.externalMarkdownExtension, '.txt');
  });

  test('normalizes external markdown extensions like PaperTodo', () {
    expect(
      AppState.fromJson({'externalMarkdownExtension': '*.MD'})
          .externalMarkdownExtension,
      '.md',
    );
    expect(
      AppState.fromJson({'externalMarkdownExtension': 'md:bad'})
          .externalMarkdownExtension,
      '.md',
    );
    expect(
      AppState.fromJson({'externalMarkdownExtension': 'md?bad'})
          .externalMarkdownExtension,
      '.md',
    );
    expect(
      AppState.fromJson({'externalMarkdownExtension': 'a..b'})
          .externalMarkdownExtension,
      '.md',
    );
    expect(
      AppState.fromJson({
        'externalMarkdownExtension': '.${List.filled(40, 'x').join()}',
      }).externalMarkdownExtension,
      '.md',
    );
  });

  test('normalizes PaperTodo display ranges', () {
    final clampedHigh = AppState.fromJson({
      'zoom': 2,
      'todoLineSpacing': 6,
      'noteLineSpacing': 1.234,
      'maxTitleLength': 99,
    });

    expect(clampedHigh.zoom, 1.5);
    expect(clampedHigh.todoLineSpacing, 5);
    expect(clampedHigh.noteLineSpacing, 1.23);
    expect(clampedHigh.maxTitleLength, 20);

    final clampedLow = AppState.fromJson({
      'zoom': 0.1,
      'todoLineSpacing': 0.2,
      'noteLineSpacing': -1,
      'maxTitleLength': 0,
    });

    expect(clampedLow.zoom, 0.5);
    expect(clampedLow.todoLineSpacing, 0.8);
    expect(clampedLow.noteLineSpacing, 1);
    expect(clampedLow.maxTitleLength, 6);
  });

  test('normalizes PaperTodo titles by visible text elements', () {
    const accented = 'e\u0301';
    const familyEmoji =
        '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';

    expect(PaperTitles.normalizeMaxTitleLength(99), 20);
    expect(PaperTitles.normalizeMaxTitleLength(0), 6);
    expect(
      PaperTitles.cleanCustomTitle(
        ' $accented$accented\u0000$familyEmoji! ',
        maxLength: 3,
      ),
      '$accented$accented$familyEmoji',
    );
    expect(PaperTitles.shorten('$familyEmoji$accented!', 2),
        '$familyEmoji$accented');
    expect(PaperTitles.defaultTitle(PaperTypes.note, 0), 'Note1');
  });

  test('cleans pasted todo lines like PaperTodo', () {
    final parsed = TodoPasteItems.parseLines('''
- [ ] Read paper
* [x] Ship build
1. Review result
2) Write notes
3、Sync device
4．Archive
☑ Done glyph
Plain item

''');

    expect(parsed, [
      'Read paper',
      'Ship build',
      'Review result',
      'Write notes',
      'Sync device',
      'Archive',
      'Done glyph',
      'Plain item',
    ]);

    final capped = TodoPasteItems.parseLines(
      List.generate(250, (index) => '- item $index').join('\n'),
    );
    expect(capped, hasLength(200));
    expect(
      TodoPasteItems.parseLines('${List.filled(5001, 'x').join()}\ny').first,
      hasLength(5000),
    );
  });

  test('clips oversized markdown pastes like PaperTodo', () {
    final longLine = List.filled(6500, 'a').join();
    final sanitized = MarkdownPasteText.sanitize('$longLine\r\nshort\rnext');

    expect(sanitized.split('\n'), [
      List.filled(6000, 'a').join(),
      'short',
      'next',
    ]);

    final oversized = MarkdownPasteText.sanitize(
      List.filled(7, List.filled(5000, 'b').join()).join('\n'),
    );

    expect(oversized, hasLength(30000));
  });

  test('continues markdown lists on enter like PaperTodo', () {
    expect(_markdownEnter('- Read').text, '- Read\n- ');
    expect(_markdownEnter('  * Read').text, '  * Read\n  * ');
    expect(_markdownEnter('3) Read').text, '3) Read\n4) ');
    expect(_markdownEnter('  9. Read').text, '  9. Read\n  10. ');
    expect(_markdownEnter('- [x] Done').text, '- [x] Done\n- [ ] ');
    expect(_markdownEnter('1. [X] Done').text, '1. [X] Done\n2. [ ] ');

    final unchanged = _markdownEnter('Plain line');
    expect(unchanged.text, 'Plain line\n');
  });

  test('removes empty markdown list markers on enter like PaperTodo', () {
    var result = _markdownEnter('- ');
    expect(result.text, '');
    expect(result.selection.baseOffset, 0);

    result = _markdownEnter('  - [ ] ');
    expect(result.text, '  ');
    expect(result.selection.baseOffset, 2);

    result = _markdownEnter('1. ');
    expect(result.text, '');
    expect(result.selection.baseOffset, 0);
  });

  test('formats markdown selections like PaperTodo', () {
    var result = MarkdownFormatting.wrapSelection(
      const TextEditingValue(
        text: 'alpha',
        selection: TextSelection.collapsed(offset: 2),
      ),
      '**',
      '**',
    );
    expect(result.text, 'al****pha');
    expect(result.selection.baseOffset, 4);

    result = MarkdownFormatting.wrapSelection(
      const TextEditingValue(
        text: 'alpha',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      ),
      '*',
      '*',
    );
    expect(result.text, 'a*lph*a');
    expect(
        result.selection, const TextSelection(baseOffset: 2, extentOffset: 5));

    result = MarkdownFormatting.wrapSelection(
      const TextEditingValue(
        text: 'one\n\ntwo',
        selection: TextSelection(baseOffset: 0, extentOffset: 8),
      ),
      '~~',
      '~~',
    );
    expect(result.text, '~~one~~\n\n~~two~~');
    expect(
        result.selection, const TextSelection(baseOffset: 0, extentOffset: 16));
  });

  test('inserts markdown prefixes and links like PaperTodo', () {
    var result = MarkdownFormatting.insertLinePrefix(
      const TextEditingValue(
        text: 'one\ntwo',
        selection: TextSelection.collapsed(offset: 5),
      ),
      '> ',
    );
    expect(result.text, 'one\n> two');
    expect(result.selection.baseOffset, 7);

    result = MarkdownFormatting.insertMarkdownLink(
      const TextEditingValue(
        text: 'read paper',
        selection: TextSelection(baseOffset: 5, extentOffset: 10),
      ),
    );
    expect(result.text, 'read [paper](https://)');
    expect(
      result.selection,
      const TextSelection(baseOffset: 13, extentOffset: 21),
    );

    result = MarkdownFormatting.insertMarkdownLink(
      const TextEditingValue(text: 'start'),
    );
    expect(result.text, 'start[link](https://)');
  });

  test('normalizes pinned hotkeys like PaperTodo', () {
    final longHotKey = 'Ctrl+Alt+${List.filled(80, 'A').join()}';
    final state = AppState.fromJson({
      'pinnedTodoHotKey': '  Ctrl+Alt+T  ',
      'pinnedNoteHotKey': longHotKey,
    });

    expect(state.pinnedTodoHotKey, 'Ctrl+Alt+T');
    expect(state.pinnedNoteHotKey, hasLength(64));
    expect(state.pinnedNoteHotKey, longHotKey.substring(0, 64));
  });

  test('migrates retired PaperTodo settings', () {
    final state = AppState.fromJson({
      'showTopBarNewPaperButtons': false,
      'showTopBarNewTodoButton': true,
      'showTopBarNewNoteButton': true,
      'hideDeepCapsulesWhenFullscreen': true,
      'futureRootField': 'keep-me',
    });

    const codec = AppStateCodec();
    final encoded = jsonDecode(codec.encode(state)) as Map<String, Object?>;

    expect(state.showTopBarNewTodoButton, false);
    expect(state.showTopBarNewNoteButton, false);
    expect(state.hideDeepCapsulesWhenCovered, true);
    expect(encoded.containsKey('showTopBarNewPaperButtons'), false);
    expect(encoded.containsKey('hideDeepCapsulesWhenFullscreen'), false);
    expect(encoded['futureRootField'], 'keep-me');
  });

  test('normalizes capsule mode dependencies like PaperTodo', () {
    final disabledCapsules = AppState.fromJson({
      'useCapsuleMode': false,
      'useDeepCapsuleMode': true,
      'useCapsuleCollapseAll': true,
      'capsuleCollapseAllActive': true,
      'capsuleCollapseAllActiveQueues': {
        'Primary|right': true,
      },
    });

    expect(disabledCapsules.useDeepCapsuleMode, false);
    expect(disabledCapsules.useCapsuleCollapseAll, false);
    expect(disabledCapsules.capsuleCollapseAllActive, false);
    expect(disabledCapsules.capsuleCollapseAllActiveQueues, isEmpty);

    final activeQueue = AppState.fromJson({
      'useCapsuleMode': true,
      'useDeepCapsuleMode': true,
      'useCapsuleCollapseAll': true,
      'capsuleCollapseAllActive': false,
      'capsuleCollapseAllActiveQueues': {
        'left': true,
        'Primary|left': true,
        'Primary|right': false,
      },
    });

    expect(activeQueue.useCapsuleCollapseAll, true);
    expect(activeQueue.capsuleCollapseAllActive, true);
    expect(activeQueue.capsuleCollapseAllActiveQueues, {
      '|left': true,
      'Primary|left': true,
    });
  });

  test('normalizes custom theme color hex values', () {
    expect(
      AppState.fromJson({'customThemeColorHex': '336699'}).customThemeColorHex,
      '#336699',
    );
    expect(
      AppState.fromJson({'customThemeColorHex': '#aabbcc'}).customThemeColorHex,
      '#AABBCC',
    );
  });

  test('normalizes todo note links against existing notes', () {
    final state = AppState(
      papers: [
        PaperData(
          id: 'todo-paper',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'item-valid', linkedNoteId: 'note-paper'),
            PaperItem(id: 'item-missing', linkedNoteId: 'missing-note'),
          ],
        ),
        PaperData(
          id: 'note-paper',
          type: PaperTypes.note,
          title: 'Keep me',
        ),
      ],
    )..normalize(storageCompatibility: true);

    final itemsById = {
      for (final item in state.papers.first.items) item.id: item,
    };
    expect(itemsById['item-valid']?.linkedNoteId, 'note-paper');
    expect(itemsById['item-missing']?.linkedNoteId, isNull);
  });

  test('normalizes paper identity and surface fields like PaperTodo', () {
    final state = AppState(
      maxTitleLength: 6,
      deepCapsuleSide: DeepCapsuleSides.left,
      deepCapsuleMonitorDeviceName: 'Primary monitor',
      useCapsuleMode: false,
      papers: [
        PaperData(
          id: 'duplicate-paper',
          type: PaperTypes.todo,
          title: '  Long\u0000Title  ',
          x: double.nan,
          y: double.infinity,
          width: 12,
          height: double.nan,
          textZoom: 1.26,
          isCollapsed: true,
          items: [
            PaperItem(id: 'duplicate-item', text: 'First'),
            PaperItem(id: 'duplicate-item', text: 'Second', order: -4),
          ],
        ),
        PaperData(
          id: 'duplicate-paper',
          type: PaperTypes.note,
          title: 'Note',
          noteCanvasElements: [
            NoteCanvasElement(id: 'duplicate-element'),
            NoteCanvasElement(id: 'duplicate-element'),
          ],
        ),
      ],
    )..normalize(storageCompatibility: true);

    expect(state.papers.map((paper) => paper.id).toSet(), hasLength(2));
    final todo = state.papers.first;
    expect(todo.title, 'LongTi');
    expect(todo.x, 120);
    expect(todo.y, 120);
    expect(todo.width, PaperLayoutDefaults.todoDefaultWidth);
    expect(todo.height, PaperLayoutDefaults.todoDefaultHeight);
    expect(todo.textZoom, 1.3);
    expect(todo.isCollapsed, false);
    expect(todo.capsuleSide, DeepCapsuleSides.left);
    expect(todo.capsuleMonitorDeviceName, 'Primary monitor');
    expect(todo.items.map((item) => item.id).toSet(), hasLength(2));
    expect(todo.items.map((item) => item.order), [0, 1]);
    expect(
      state.papers.last.noteCanvasElements.map((element) => element.id).toSet(),
      hasLength(2),
    );
  });

  test('expands hidden linked note capsules like PaperTodo', () {
    final state = AppState(
      enableTodoNoteLinks: true,
      hideLinkedNotesFromCapsules: true,
      papers: [
        PaperData(
          id: 'todo-paper',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'todo-item', linkedNoteId: 'note-paper'),
          ],
        ),
        PaperData(
          id: 'note-paper',
          type: PaperTypes.note,
          isCollapsed: true,
        ),
      ],
    )..normalize();

    expect(state.papers.last.isCollapsed, false);
  });

  test('normalizes todo reminder intervals like PaperTodo', () {
    final state = AppState.fromJson({
      'papers': [
        {
          'id': 'todo-paper',
          'type': PaperTypes.todo,
          'items': [
            {
              'id': 'too-large',
              'reminderIntervalValue': 999,
              'reminderIntervalUnit': 'days',
            },
            {
              'id': 'disabled',
              'reminderIntervalValue': 0,
              'reminderIntervalUnit': TodoReminderIntervalUnits.hours,
            },
          ],
        },
      ],
    });

    final itemsById = {
      for (final item in state.papers.single.items) item.id: item,
    };
    expect(itemsById['too-large']?.reminderIntervalValue, 240);
    expect(
      itemsById['too-large']?.reminderIntervalUnit,
      TodoReminderIntervalUnits.minutes,
    );
    expect(itemsById['disabled']?.reminderIntervalValue, isNull);
    expect(itemsById['disabled']?.reminderIntervalUnit, isNull);
  });

  test('normalizes todo columns and due dates like PaperTodo', () {
    final state = AppState.fromJson({
      'papers': [
        {
          'id': 'todo-paper',
          'type': PaperTypes.todo,
          'items': [
            {
              'id': 'columns',
              'todoColumnCount': 3,
              'todoExtraColumns': ['A'],
              'todoColumnWidths': [0.1, 1.23456, 99, 7],
              'dueAtLocal': ' 2026-06-30T09:08:07.999 ',
            },
            {
              'id': 'invalid-due',
              'dueAtLocal': 'not a date',
            },
          ],
        },
      ],
    });

    final itemsById = {
      for (final item in state.papers.single.items) item.id: item,
    };
    expect(itemsById['columns']?.todoColumnCount, 3);
    expect(itemsById['columns']?.todoExtraColumns, ['A', '']);
    expect(itemsById['columns']?.todoColumnWidths, [0.2, 1.235, 8]);
    expect(itemsById['columns']?.dueAtLocal, '2026-06-30T09:08:07');
    expect(itemsById['invalid-due']?.dueAtLocal, isNull);
  });

  test('normalizes note canvas element types', () {
    final state = AppState(
      papers: [
        PaperData(
          id: 'canvas-note',
          type: PaperTypes.note,
          noteCanvasElements: [
            NoteCanvasElement(id: 'text-block', type: 'text'),
            NoteCanvasElement(id: 'unknown-block', type: 'shape'),
          ],
        ),
      ],
    )..normalize();

    final elementsById = {
      for (final element in state.papers.single.noteCanvasElements)
        element.id: element,
    };
    expect(elementsById['text-block']?.type, NoteCanvasElementTypes.text);
    expect(elementsById['unknown-block']?.type, NoteCanvasElementTypes.code);
  });

  test('normalizes note canvas geometry like PaperTodo', () {
    final state = AppState(
      papers: [
        PaperData(
          id: 'canvas-note',
          type: PaperTypes.note,
          noteCanvasElements: [
            NoteCanvasElement(
              id: 'wide',
              x: -5000,
              y: 9000,
              width: 4000,
              height: 4,
            ),
            NoteCanvasElement(
              id: 'layered',
              zIndex: -3,
            ),
          ],
        ),
      ],
    )..normalize();

    final wide = state.papers.single.noteCanvasElements.first;
    final layered = state.papers.single.noteCanvasElements.last;
    expect(wide.x, -2000);
    expect(wide.y, 8000);
    expect(wide.width, 1600);
    expect(wide.height, 110);
    expect(wide.zIndex, 10);
    expect(layered.zIndex, 20);
  });

  test('normalizes deep capsule top margins', () {
    final state = AppState.fromJson({
      'useCapsuleMode': true,
      'useDeepCapsuleMode': true,
      'useCapsuleCollapseAll': true,
      'deepCapsuleStartTopMargin': 2,
      'deepCapsuleQueueStartTopMargins': {
        'left': 16,
        'Primary|right': 4,
        'Secondary|right': 64,
        'Tertiary|left': 20000,
      },
    });

    expect(state.deepCapsuleStartTopMargin, 8);
    expect(state.deepCapsuleQueueStartTopMargins, {
      '|left': 16,
      'Primary|right': 8,
      'Secondary|right': 64,
      'Tertiary|left': 10000,
    });

    final disabled = AppState.fromJson({
      'useCapsuleMode': false,
      'useDeepCapsuleMode': true,
      'useCapsuleCollapseAll': true,
      'deepCapsuleStartTopMargin': 72,
      'deepCapsuleQueueStartTopMargins': {
        'Primary|left': 64,
      },
    });

    expect(disabled.deepCapsuleStartTopMargin, 48);
    expect(disabled.deepCapsuleQueueStartTopMargins, isEmpty);
  });

  test('decodes and normalizes WebDAV sync settings', () {
    final state = AppState.fromJson({
      'sync': {
        'enabled': true,
        'provider': 'webDav',
        'futureSyncField': 'keep-sync',
        'operationDeviceSequences': {
          ' win-device ': 3,
          'Win Device': 4,
          'android-device': 2.4,
          'bad': 9,
          'stale-device': 0,
          '': 7,
        },
        'deletedPaperTombstones': {
          ' old-paper ': '2026-07-01T10:00:00+08:00',
          'bad-paper': 'not-a-date',
          '': '2026-07-01T10:00:00Z',
        },
        'deletedTodoItemTombstones': {
          ' todo-paper ': {
            ' old-item ': '2026-07-01T11:30:00+08:00',
            'bad-item': 'not-a-date',
          },
          'bad-paper': 'not-a-map',
        },
        'webDav': {
          'presetId': 'jianguoyun',
          'endpoint': '',
          'username': '  user@example.com  ',
          'password': 'app-password',
          'rootPath': '/RePaperTodo//',
          'autoSyncOnStart': true,
          'autoSyncIntervalMinutes': 2000,
          'futureWebDavField': 7,
        },
      },
    });

    expect(state.sync.enabled, true);
    expect(state.sync.provider, SyncProviderIds.webDav);
    expect(state.sync.extra['futureSyncField'], 'keep-sync');
    expect(state.sync.operationDeviceSequences, {
      'win-device': 4,
      'android-device': 2,
    });
    expect(state.sync.deletedPaperTombstones, {
      'old-paper':
          DateTime.parse('2026-07-01T10:00:00+08:00').toUtc().toIso8601String(),
    });
    expect(state.sync.deletedTodoItemTombstones, {
      'todo-paper': {
        'old-item': DateTime.parse('2026-07-01T11:30:00+08:00')
            .toUtc()
            .toIso8601String(),
      },
    });
    expect(state.sync.webDav.presetId, WebDavPresetIds.jianguoyun);
    expect(state.sync.webDav.endpoint, 'https://dav.jianguoyun.com/dav/');
    expect(state.sync.webDav.username, 'user@example.com');
    expect(state.sync.webDav.rootPath, 'RePaperTodo');
    expect(state.sync.webDav.autoSyncIntervalMinutes, 1440);
    expect(state.sync.webDav.extra['futureWebDavField'], 7);
    expect(state.sync.webDav.isConfigured, true);
  });

  test('normalizes unsafe WebDAV root paths as incomplete settings', () {
    final safe = WebDavSyncSettings(
      endpoint: 'https://dav.example.test/dav/',
      username: 'user',
      password: 'pass',
      rootPath: '/Team%20Space/./RePaperTodo//',
    )..normalize();

    expect(safe.rootPath, 'Team Space/RePaperTodo');
    expect(safe.isConfigured, true);

    for (final rootPath in const [
      '../Other',
      r'RePaperTodo\..\Other',
      'RePaperTodo/%2e%2e/Other',
      'RePaperTodo/bad%',
    ]) {
      final unsafe = WebDavSyncSettings(
        endpoint: 'https://dav.example.test/dav/',
        username: 'user',
        password: 'pass',
        rootPath: rootPath,
      )..normalize();

      expect(unsafe.rootPath, isEmpty);
      expect(unsafe.isConfigured, false);
    }
  });

  test('rejects incomplete WebDAV endpoint settings', () {
    final settings = WebDavSyncSettings(
      endpoint: 'dav.jianguoyun.com/dav',
      username: 'user',
      password: 'pass',
    )..normalize();

    expect(settings.endpointUri, isNull);
    expect(settings.isConfigured, false);
  });

  test('rejects invalid WebDAV Basic Auth usernames', () {
    final passwordWithColon = WebDavSyncSettings(
      endpoint: 'https://dav.example.test/dav/',
      username: ' user@example.com ',
      password: 'app:password',
    )..normalize();

    expect(passwordWithColon.username, 'user@example.com');
    expect(passwordWithColon.isConfigured, true);

    for (final username in const [
      '',
      'user:name',
      'user\nname',
      'user\u007Fname',
    ]) {
      final settings = WebDavSyncSettings(
        endpoint: 'https://dav.example.test/dav/',
        username: username,
        password: 'pass',
      )..normalize();

      expect(settings.endpointUri, isNotNull);
      expect(settings.isConfigured, false);
    }
  });

  test('rejects invalid WebDAV Basic Auth passwords', () {
    final passwordWithSpacesAndColon = WebDavSyncSettings(
      endpoint: 'https://dav.example.test/dav/',
      username: 'user@example.com',
      password: ' app:password ',
    )..normalize();

    expect(passwordWithSpacesAndColon.password, ' app:password ');
    expect(passwordWithSpacesAndColon.isConfigured, true);

    for (final password in const [
      '',
      '   ',
      'app\npassword',
      'app\u007Fpassword',
    ]) {
      final settings = WebDavSyncSettings(
        endpoint: 'https://dav.example.test/dav/',
        username: 'user',
        password: password,
      )..normalize();

      expect(settings.endpointUri, isNotNull);
      expect(settings.isConfigured, false);
    }
  });

  test('accepts only HTTP WebDAV endpoint schemes', () {
    for (final endpoint in const [
      'https://dav.example.test/dav/',
      'http://dav.example.test/dav/',
    ]) {
      final settings = WebDavSyncSettings(
        endpoint: endpoint,
        username: 'user',
        password: 'pass',
      )..normalize();

      expect(settings.endpointUri, isNotNull);
      expect(settings.isConfigured, true);
    }

    for (final endpoint in const [
      'ftp://dav.example.test/dav/',
      'file:///tmp/dav',
      'dav.example.test/dav/',
      'https://user:pass@dav.example.test/dav/',
      'https://dav.example.test/dav/?token=secret',
      'https://dav.example.test/dav/#sync-root',
      'https://dav.example.test/dav/./files/',
      'https://dav.example.test/dav/../files/',
      'https://dav.example.test/dav/%2e%2e/files/',
      r'https://dav.example.test\dav\files\',
      r'https://dav.example.test/dav\..\files/',
      'https://dav.example.test/dav/%5C..%5Cfiles/',
      'https://dav.example.test/dav/bad%/',
    ]) {
      final settings = WebDavSyncSettings(
        endpoint: endpoint,
        username: 'user',
        password: 'pass',
      )..normalize();

      expect(settings.endpointUri, isNull);
      expect(settings.isConfigured, false);
    }
  });
}

TextEditingValue _markdownEnter(String text, {int? caret}) {
  final offset = caret ?? text.length;
  final oldValue = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: offset),
  );
  final newValue = TextEditingValue(
    text: text.replaceRange(offset, offset, '\n'),
    selection: TextSelection.collapsed(offset: offset + 1),
  );
  return MarkdownListContinuation.formatEnter(oldValue, newValue);
}
