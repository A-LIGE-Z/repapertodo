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

  test('migrates legacy PaperTodo PascalCase data before decoding', () {
    const source = '''
{
  "Theme": "dark",
  "StartAtLogin": true,
  "UseCapsuleMode": true,
  "UseDeepCapsuleMode": true,
  "DeepCapsuleSide": "left",
  "Papers": [
    {
      "Id": "todo-paper",
      "Type": "todo",
      "Title": "Inbox",
      "X": 33,
      "Y": 44,
      "Width": 300,
      "Height": 360,
      "Items": [
        {
          "Id": "todo-item",
          "Text": "Read the old data file",
          "Done": true,
          "TodoColumnCount": 2,
          "TodoExtraColumns": ["source"],
          "LinkedNoteId": "note-paper"
        }
      ]
    },
    {
      "Id": "note-paper",
      "Type": "note",
      "Title": "Notes",
      "Content": "# Migrated",
      "NoteCanvasElements": [
        {
          "Id": "canvas-code",
          "Text": "Console.WriteLine();",
          "X": 80,
          "Y": 96,
          "ZIndex": 0
        }
      ]
    }
  ]
}
''';

    const codec = AppStateCodec();
    final state = codec.decode(source);
    final todo = state.papers.first;
    final note = state.papers.last;

    expect(state.theme, 'dark');
    expect(state.startAtLogin, true);
    expect(state.deepCapsuleSide, DeepCapsuleSides.left);
    expect(todo.id, 'todo-paper');
    expect(todo.title, 'Inbox');
    expect(todo.x, 33);
    expect(todo.y, 44);
    expect(todo.width, 300);
    expect(todo.items.single.id, 'todo-item');
    expect(todo.items.single.text, 'Read the old data file');
    expect(todo.items.single.done, true);
    expect(todo.items.single.todoColumnCount, 2);
    expect(todo.items.single.todoExtraColumns, ['source']);
    expect(todo.items.single.linkedNoteId, 'note-paper');
    expect(note.type, PaperTypes.note);
    expect(note.width, PaperLayoutDefaults.noteDefaultWidth);
    expect(note.height, PaperLayoutDefaults.noteDefaultHeight);
    expect(note.content, '# Migrated');
    expect(note.noteCanvasElements.single.id, 'canvas-code');
    expect(note.noteCanvasElements.single.text, 'Console.WriteLine();');
    expect(note.noteCanvasElements.single.zIndex, 10);
  });

  test('migrates legacy PaperTodo keys case-insensitively', () {
    const source = '''
{
  "THEME": "dark",
  "usecapsulemode": true,
  "DeepCapsuleSide": "left",
  "SYNC": {
    "ENABLED": true,
    "PROVIDER": "WEBDAV",
    "WEBDAV": {
      "PRESETID": "nutstore",
      "ENDPOINT": "https://dav.jianguoyun.com/dav/",
      "USERNAME": "paper@example.com",
      "PASSWORD": "secret",
      "ROOTPATH": "/PaperTodo/"
    }
  },
  "PAPERS": [
    {
      "ID": "case-paper",
      "TYPE": "note",
      "TITLE": "Case",
      "CONTENT": "# Mixed",
      "NOTECANVASELEMENTS": [
        {
          "ID": "case-code",
          "TEXT": "Console.WriteLine();",
          "ZINDEX": 0
        }
      ]
    },
    {
      "ID": "case-todo",
      "TYPE": "todo",
      "ITEMS": [
        {
          "ID": "case-item",
          "TEXT": "Keep old data readable",
          "DONE": true,
          "DUEATLOCAL": "2026-07-03T09:30:00"
        }
      ]
    }
  ]
}
''';

    const codec = AppStateCodec();
    final state = codec.decode(source);

    expect(state.theme, 'dark');
    expect(state.deepCapsuleSide, DeepCapsuleSides.left);
    expect(state.sync.enabled, true);
    expect(state.sync.provider, SyncProviderIds.webDav);
    expect(state.sync.webDav.presetId, WebDavPresetIds.jianguoyun);
    expect(state.sync.webDav.rootPath, 'PaperTodo');
    expect(state.papers.first.id, 'case-paper');
    expect(state.papers.first.noteCanvasElements.single.id, 'case-code');
    expect(state.papers.first.noteCanvasElements.single.zIndex, 10);
    expect(state.papers.last.items.single.id, 'case-item');
    expect(state.papers.last.items.single.done, true);
    expect(state.papers.last.items.single.dueAtLocal, '2026-07-03T09:30:00');
  });

  test('keeps modern RePaperTodo keys ahead of duplicate legacy keys', () {
    const source = '''
{
  "Theme": "dark",
  "theme": "light",
  "Papers": [
    {
      "Id": "legacy-paper",
      "id": "modern-paper",
      "Type": "note",
      "type": "todo",
      "Items": [
        {
          "Id": "legacy-item",
          "id": "modern-item",
          "Text": "legacy text",
          "text": "modern text"
        }
      ]
    }
  ]
}
''';

    const codec = AppStateCodec();
    final state = codec.decode(source);

    expect(state.theme, 'light');
    expect(state.papers.single.id, 'modern-paper');
    expect(state.papers.single.type, PaperTypes.todo);
    expect(state.papers.single.items.single.id, 'modern-item');
    expect(state.papers.single.items.single.text, 'modern text');
  });

  test('does not migrate user data keys inside legacy queue maps', () {
    final migrated = migrateLegacyPaperTodoJson({
      'UseCapsuleCollapseAll': true,
      'CapsuleCollapseAllActiveQueues': {
        'Id': true,
        'Primary|Left': true,
      },
      'DeepCapsuleQueueStartTopMargins': {
        'Width': 64,
      },
    });

    expect(migrated['capsuleCollapseAllActiveQueues'], {
      'Id': true,
      'Primary|Left': true,
    });
    expect(migrated['deepCapsuleQueueStartTopMargins'], {
      'Width': 64,
    });
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

  test('normalizes legacy enum values case-insensitively', () {
    final state = AppState.fromJson({
      'theme': ' DARK ',
      'colorScheme': ' FOREST ',
      'markdownRenderMode': 'BASIC',
      'todoVisualSize': 'EXTRALARGE',
      'uiFontPreset': 'MONO',
      'todoDueYearDisplayMode': 'FULL',
      'todoReminderIntervalUnit': 'HOURS',
      'todoReminderScope': 'NEAREST',
      'fullscreenTopmostMode': 'STAYONTOP',
      'deepCapsuleSide': 'LEFT',
      'papers': [
        {
          'id': 'note',
          'type': 'NOTE',
          'capsuleSide': 'LEFT',
          'noteCanvasElements': [
            {
              'id': 'text-block',
              'type': 'TEXT',
            },
          ],
        },
        {
          'id': 'todo',
          'type': 'TODO',
          'items': [
            {
              'id': 'item',
              'reminderIntervalValue': 2,
              'reminderIntervalUnit': 'HOURS',
            },
          ],
        },
      ],
    });

    expect(state.theme, 'dark');
    expect(state.colorScheme, ColorSchemes.forest);
    expect(state.markdownRenderMode, MarkdownRenderModes.basic);
    expect(state.todoVisualSize, TodoVisualSizes.extraLarge);
    expect(state.uiFontPreset, UiFontPresets.mono);
    expect(state.todoDueYearDisplayMode, TodoDueYearDisplayModes.full);
    expect(state.todoReminderIntervalUnit, TodoReminderIntervalUnits.hours);
    expect(state.todoReminderScope, TodoReminderScopes.nearest);
    expect(state.fullscreenTopmostMode, FullscreenTopmostModes.stayOnTop);
    expect(state.deepCapsuleSide, DeepCapsuleSides.left);
    expect(state.papers.first.type, PaperTypes.note);
    expect(state.papers.first.capsuleSide, DeepCapsuleSides.left);
    expect(state.papers.first.noteCanvasElements.single.type,
        NoteCanvasElementTypes.text);
    expect(state.papers.last.type, PaperTypes.todo);
    expect(state.papers.last.items.single.reminderIntervalUnit,
        TodoReminderIntervalUnits.hours);
  });

  test('preserves original PaperTodo UI font presets', () {
    expect(
      AppState.fromJson({'uiFontPreset': 'YAHEI'}).uiFontPreset,
      UiFontPresets.yaHei,
    );
    expect(
      AppState.fromJson({'uiFontPreset': 'DENGXIAN'}).uiFontPreset,
      UiFontPresets.dengXian,
    );
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
      AppState.fromJson({'externalMarkdownExtension': 'm\u007Fd'})
          .externalMarkdownExtension,
      '.md',
    );
    expect(
      AppState.fromJson({'externalMarkdownExtension': 'm\u0085d'})
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

  test('decodes hand-edited primitive values from strings', () {
    final state = AppState.fromJson({
      'zoom': '1.25',
      'todoLineSpacing': '1.5',
      'noteLineSpacing': '1.75',
      'maxTitleLength': '12',
      'useCapsuleMode': 'true',
      'useDeepCapsuleMode': 'true',
      'useCapsuleCollapseAll': 'true',
      'capsuleCollapseAllActiveQueues': {
        'Primary|LEFT': 'true',
        'Hidden|right': 'false',
      },
      'deepCapsuleQueueStartTopMargins': {
        'Primary|LEFT': '72.5',
      },
      'sync': {
        'operationDeviceSequences': {
          'device-a': '7',
        },
        'webDav': {
          'autoSyncOnStart': 'true',
          'autoSyncIntervalMinutes': '20',
          'requestTimeoutSeconds': '45',
        },
      },
    });

    expect(state.zoom, 1.25);
    expect(state.todoLineSpacing, 1.5);
    expect(state.noteLineSpacing, 1.75);
    expect(state.maxTitleLength, 12);
    expect(state.useCapsuleMode, true);
    expect(state.useDeepCapsuleMode, true);
    expect(state.useCapsuleCollapseAll, true);
    expect(state.capsuleCollapseAllActiveQueues, {'Primary|left': true});
    expect(state.deepCapsuleQueueStartTopMargins, {'Primary|left': 72.5});
    expect(state.sync.operationDeviceSequences, {'device-a': 7});
    expect(state.sync.webDav.autoSyncOnStart, true);
    expect(state.sync.webDav.autoSyncIntervalMinutes, 20);
    expect(state.sync.webDav.requestTimeoutSeconds, 45);
  });

  test('defaults invalid hand-edited WebDAV numeric settings', () {
    final blankInterval = AppState.fromJson({
      'sync': {
        'webDav': {
          'autoSyncIntervalMinutes': '   ',
          'requestTimeoutSeconds': 'not-a-number',
        },
      },
    });
    final nonNumericTypes = AppState.fromJson({
      'sync': {
        'webDav': {
          'autoSyncIntervalMinutes': <Object?>['15'],
          'requestTimeoutSeconds': {'seconds': 30},
        },
      },
    });

    expect(blankInterval.sync.webDav.autoSyncIntervalMinutes, 15);
    expect(blankInterval.sync.webDav.requestTimeoutSeconds, 30);
    expect(nonNumericTypes.sync.webDav.autoSyncIntervalMinutes, 15);
    expect(nonNumericTypes.sync.webDav.requestTimeoutSeconds, 30);
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

    expect(sanitized, List.filled(6000, 'a').join());
    expect(
        MarkdownPasteText.sanitize('one\r\ntwo\rthree'), 'one\r\ntwo\rthree');

    final oversized = MarkdownPasteText.sanitize(
      List.filled(7, List.filled(5000, 'b').join()).join('\n'),
    );

    expect(oversized, hasLength(30000));
    expect(
      MarkdownPasteText.trimToMaxTextLength(List.filled(100050, 'c').join()),
      hasLength(100000),
    );
  });

  test('continues markdown lists on enter like PaperTodo', () {
    expect(_markdownEnter('- Read').text, '- Read\n- ');
    expect(_markdownEnter('  * Read').text, '  * Read\n  * ');
    expect(_markdownEnter('3) Read').text, '3) Read\n4) ');
    expect(_markdownEnter('  9. Read').text, '  9. Read\n  10. ');
    expect(_markdownEnter('009. Read').text, '009. Read\n10. ');
    expect(_markdownEnter('- [x] Done').text, '- [x] Done\n- [ ] ');
    expect(_markdownEnter('1. [X] Done').text, '1. [X] Done\n2. [ ] ');
    expect(
      _markdownEnter('9223372036854775806. Read').text,
      '9223372036854775806. Read\n9223372036854775807. ',
    );

    final unchanged = _markdownEnter('Plain line');
    expect(unchanged.text, 'Plain line\n');

    final maxLong = _markdownEnter('9223372036854775807. Read');
    expect(maxLong.text, '9223372036854775807. Read\n');

    final beyondLong = _markdownEnter('9223372036854775808. Read');
    expect(beyondLong.text, '9223372036854775808. Read\n');
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

    result = _markdownEnter('9223372036854775807. ');
    expect(result.text, '9223372036854775807. \n');
    expect(result.selection.baseOffset, 22);
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
    expect(result.text, 'start[Link](https://)');
  });

  test('handles markdown tab indentation like PaperTodo', () {
    var result = MarkdownFormatting.handleTab(
      const TextEditingValue(
        text: 'alpha',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(result.text, 'al\tpha');
    expect(result.selection.baseOffset, 3);

    result = MarkdownFormatting.handleTab(
      const TextEditingValue(
        text: 'one\ntwo',
        selection: TextSelection(baseOffset: 0, extentOffset: 7),
      ),
    );
    expect(result.text, '\tone\n\ttwo');

    result = MarkdownFormatting.handleTab(
      const TextEditingValue(
        text: '\tone\n    two\n  three',
        selection: TextSelection(baseOffset: 0, extentOffset: 20),
      ),
      outdent: true,
    );
    expect(result.text, 'one\ntwo\nthree');
  });

  test('normalizes pinned hotkeys like PaperTodo', () {
    final longHotKey = 'Ctrl+Alt+${List.filled(80, 'A').join()}';
    final state = AppState.fromJson({
      'pinnedTodoHotKey': '  Ctrl+\nAlt+\u007F\u0085T  ',
      'pinnedNoteHotKey': '$longHotKey\n',
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

  test('migrates legacy PascalCase retired PaperTodo settings', () {
    const source = '''
{
  "ShowTopBarNewPaperButtons": false,
  "ShowTopBarNewTodoButton": true,
  "ShowTopBarNewNoteButton": true,
  "HideDeepCapsulesWhenFullscreen": true,
  "TopBarHeight": 19,
  "FuturePascalField": "keep-me",
  "Papers": []
}
''';

    const codec = AppStateCodec();
    final state = codec.decode(source);
    final encoded = jsonDecode(codec.encode(state)) as Map<String, Object?>;

    expect(state.showTopBarNewTodoButton, false);
    expect(state.showTopBarNewNoteButton, false);
    expect(state.hideDeepCapsulesWhenCovered, true);
    expect(encoded.containsKey('ShowTopBarNewPaperButtons'), false);
    expect(encoded.containsKey('showTopBarNewPaperButtons'), false);
    expect(encoded.containsKey('HideDeepCapsulesWhenFullscreen'), false);
    expect(encoded.containsKey('hideDeepCapsulesWhenFullscreen'), false);
    expect(encoded.containsKey('TopBarHeight'), false);
    expect(encoded.containsKey('topBarHeight'), false);
    expect(encoded['FuturePascalField'], 'keep-me');
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

  test('capsule collapse all can target one deep capsule queue', () {
    final leftPaper = PaperData(
      id: 'left-paper',
      type: PaperTypes.todo,
      title: 'Left',
      capsuleMonitorDeviceName: 'Primary',
      capsuleSide: DeepCapsuleSides.left,
    );
    final rightPaper = PaperData(
      id: 'right-paper',
      type: PaperTypes.todo,
      title: 'Right',
      capsuleMonitorDeviceName: 'Primary',
      capsuleSide: DeepCapsuleSides.right,
    );
    final state = AppState(
      useCapsuleMode: true,
      useDeepCapsuleMode: true,
      useCapsuleCollapseAll: true,
      papers: [leftPaper, rightPaper],
    )..normalize();

    state.setCapsuleCollapseAllActiveFor(leftPaper, true);

    expect(state.capsuleCollapseAllActive, true);
    expect(state.capsuleCollapseAllActiveQueues, {'Primary|left': true});
    expect(state.isCapsuleCollapseAllActiveFor(leftPaper), true);
    expect(state.isCapsuleCollapseAllActiveFor(rightPaper), false);

    state.toggleCapsuleCollapseAllFor(null);

    expect(state.capsuleCollapseAllActive, false);
    expect(state.capsuleCollapseAllActiveQueues, isEmpty);
    expect(state.isCapsuleCollapseAllActiveFor(leftPaper), false);
    expect(state.isCapsuleCollapseAllActiveFor(rightPaper), false);
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
            PaperItem(id: ' item-valid ', linkedNoteId: ' note-paper '),
            PaperItem(id: 'item-missing', linkedNoteId: 'missing-note'),
          ],
        ),
        PaperData(
          id: ' note-paper ',
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
    expect(state.papers.last.id, 'note-paper');
  });

  test('normalizes paper identity and surface fields like PaperTodo', () {
    final state = AppState(
      maxTitleLength: 6,
      deepCapsuleSide: DeepCapsuleSides.left,
      deepCapsuleMonitorDeviceName: 'Primary monitor',
      useCapsuleMode: false,
      papers: [
        PaperData(
          id: ' duplicate-paper ',
          type: PaperTypes.todo,
          title: '  Long\u0000Title  ',
          x: double.nan,
          y: double.infinity,
          width: 12,
          height: double.nan,
          textZoom: 1.26,
          isCollapsed: true,
          items: [
            PaperItem(id: ' duplicate-item ', text: 'First'),
            PaperItem(id: 'duplicate-item', text: 'Second', order: -4),
          ],
        ),
        PaperData(
          id: 'duplicate-paper',
          type: PaperTypes.note,
          title: 'Note',
          noteCanvasElements: [
            NoteCanvasElement(id: ' duplicate-element '),
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
    expect(todo.items.first.id, 'duplicate-item');
    expect(todo.items.map((item) => item.order), [0, 1]);
    expect(
      state.papers.last.noteCanvasElements.map((element) => element.id).toSet(),
      hasLength(2),
    );
    expect(state.papers.last.noteCanvasElements.first.id, 'duplicate-element');
    expect(state.papers.last.width, PaperLayoutDefaults.noteDefaultWidth);
    expect(state.papers.last.height, PaperLayoutDefaults.noteDefaultHeight);
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
      'todoReminderIntervalValue': 0,
      'todoReminderIntervalUnit': 'days',
      'todoReminderBubbleDurationSeconds': -3,
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

    expect(state.todoReminderIntervalValue, 10);
    expect(
      state.todoReminderIntervalUnit,
      TodoReminderIntervalUnits.minutes,
    );
    expect(state.todoReminderBubbleDurationSeconds, 5);

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
              'todoColumnCount': 9,
              'todoExtraColumns': ['A'],
              'todoColumnWidths': [0.1, 1.23456, 99, 10001, 7],
              'dueAtLocal': ' 2026-06-30T09:08:07.999 ',
            },
            {
              'id': 'invalid-due',
              'dueAtLocal': 'not a date',
            },
            {
              'id': 'slash-due',
              'dueAtLocal': '2026/6/30 9:08',
            },
            {
              'id': 'day-first-due',
              'dueAtLocal': '30/6/2026 09:08',
            },
          ],
        },
      ],
    });

    final itemsById = {
      for (final item in state.papers.single.items) item.id: item,
    };
    expect(itemsById['columns']?.todoColumnCount, 4);
    expect(itemsById['columns']?.todoExtraColumns, ['A', '', '']);
    expect(
      itemsById['columns']?.todoColumnWidths,
      [0.2, 1.235, 8, 8],
    );
    expect(itemsById['columns']?.dueAtLocal, '2026-06-30T09:08:07');
    expect(itemsById['invalid-due']?.dueAtLocal, isNull);
    expect(itemsById['slash-due']?.dueAtLocal, '2026-06-30T09:08:00');
    expect(itemsById['day-first-due']?.dueAtLocal, '2026-06-30T09:08:00');
  });

  test('serializes todo column lists as defensive snapshots', () {
    final item = PaperItem(
      id: 'snapshot-columns',
      text: 'Title',
      todoColumnCount: 2,
      todoExtraColumns: ['Status'],
      todoColumnWidths: [2, 1],
    );

    final json = item.toJson();
    item.todoExtraColumns[0] = 'Changed';
    item.todoColumnWidths[0] = 4;

    expect(json['todoExtraColumns'], ['Status']);
    expect(json['todoColumnWidths'], [2, 1]);
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
              id: 'invalid',
              x: double.nan,
              y: double.infinity,
              width: double.negativeInfinity,
              height: double.nan,
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
    final invalid = state.papers.single.noteCanvasElements[1];
    final layered = state.papers.single.noteCanvasElements.last;
    expect(wide.x, -2000);
    expect(wide.y, 8000);
    expect(wide.width, 1600);
    expect(wide.height, 110);
    expect(wide.zIndex, 10);
    expect(invalid.x, 32);
    expect(invalid.y, 32);
    expect(invalid.width, 220);
    expect(invalid.height, 110);
    expect(layered.zIndex, 30);
  });

  test('normalizes deep capsule top margins', () {
    final state = AppState.fromJson({
      'useCapsuleMode': true,
      'useDeepCapsuleMode': true,
      'useCapsuleCollapseAll': true,
      'deepCapsuleStartTopMargin': 2,
      'deepCapsuleQueueStartTopMargins': {
        'LEFT': 16,
        'Primary|right': 4,
        'Secondary|right': 64,
        'Tertiary|LEFT': 20000,
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
          'phone-device': 2.0,
          'bad': 9,
          'stale-device': 0,
          '': 7,
        },
        'deletedPaperTombstones': {
          ' old-paper ': '2026-07-01T10:00:00+08:00',
          'old-paper': '2026-07-01T03:00:00Z',
          'bad-paper': 'not-a-date',
          'overflow-month': '2026-13-01T10:00:00Z',
          'overflow-day': '2026-02-30T10:00:00Z',
          '': '2026-07-01T10:00:00Z',
        },
        'deletedTodoItemTombstones': {
          ' todo-paper ': {
            ' old-item ': '2026-07-01T11:30:00+08:00',
            'bad-item': 'not-a-date',
            'overflow-time': '2026-07-01T24:00:00Z',
          },
          'todo-paper': {
            'old-item': '2026-07-01T04:00:00Z',
            ' new-item ': '2026-07-01T12:30:00+08:00',
          },
          'bad-paper': 'not-a-map',
        },
        'webDav': {
          'presetId': 'jianguoyun',
          'endpoint': '',
          'username': '  user@example.com  ',
          'password': 'app-password',
          'encryptionPassphrase': '  sync secret  ',
          'rootPath': '/RePaperTodo//',
          'autoSyncOnStart': true,
          'autoSyncIntervalMinutes': 2000,
          'requestTimeoutSeconds': 999,
          'futureWebDavField': 7,
        },
      },
    });

    expect(state.sync.enabled, true);
    expect(state.sync.provider, SyncProviderIds.webDav);
    expect(state.sync.extra['futureSyncField'], 'keep-sync');
    expect(state.sync.operationDeviceSequences, {
      'win-device': 4,
      'phone-device': 2,
    });
    expect(state.sync.deletedPaperTombstones, {
      'old-paper': DateTime.utc(2026, 7, 1, 3).toIso8601String(),
    });
    expect(state.sync.deletedTodoItemTombstones, {
      'todo-paper': {
        'old-item': DateTime.utc(2026, 7, 1, 4).toIso8601String(),
        'new-item': DateTime.utc(2026, 7, 1, 4, 30).toIso8601String(),
      },
    });
    expect(state.sync.webDav.presetId, WebDavPresetIds.jianguoyun);
    expect(state.sync.webDav.endpoint, 'https://dav.jianguoyun.com/dav/');
    expect(state.sync.webDav.username, 'user@example.com');
    expect(state.sync.webDav.encryptionPassphrase, 'sync secret');
    expect(state.sync.webDav.usesEncryptedPayloads, true);
    expect(state.sync.webDav.rootPath, 'RePaperTodo');
    expect(state.sync.webDav.autoSyncIntervalMinutes, 1440);
    expect(state.sync.webDav.requestTimeoutSeconds, 300);
    expect(state.sync.webDav.extra['futureWebDavField'], 7);
    expect(state.sync.webDav.isConfigured, true);
    expect(state.sync.webDav.isSecurelyConfigured, true);
  });

  test('decodes unsafe WebDAV endpoints as incomplete settings', () {
    final state = AppState.fromJson({
      'sync': {
        'enabled': true,
        'provider': 'webDav',
        'webDav': {
          'endpoint': ' https://dav.example.test/dav/%0Afiles ',
          'username': 'user',
          'password': 'pass',
          'encryptionPassphrase': 'sync secret',
          'rootPath': 'repapertodo',
        },
      },
    });

    expect(state.sync.enabled, true);
    expect(state.sync.provider, SyncProviderIds.webDav);
    expect(state.sync.webDav.endpoint, 'https://dav.example.test/dav/%0Afiles');
    expect(state.sync.webDav.endpointUri, isNull);
    expect(state.sync.webDav.configurationIssues, {
      WebDavSyncConfigurationIssue.endpoint,
    });
    expect(state.sync.webDav.isConfigured, false);
    expect(state.sync.webDav.isSecurelyConfigured, false);
  });

  test('normalizes unsafe WebDAV root paths as incomplete settings', () {
    final safe = WebDavSyncSettings(
      endpoint: 'https://dav.example.test/dav/',
      username: 'user',
      password: 'pass',
      rootPath: '/ Team%20Space /./ RePaperTodo //',
    )..normalize();

    expect(safe.rootPath, 'Team Space/RePaperTodo');
    expect(safe.isConfigured, true);

    for (final rootPath in const [
      '../Other',
      r'RePaperTodo\..\Other',
      'RePaperTodo/%2e%2e/Other',
      'RePaperTodo/bad%',
      'RePaperTodo/%0AOther',
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
