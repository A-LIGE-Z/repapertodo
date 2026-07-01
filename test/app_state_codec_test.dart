import 'dart:convert';

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
      'markdownRenderMode': 'rich',
      'todoVisualSize': 'giant',
      'externalMarkdownExtension': 'txt',
    });

    expect(state.theme, 'system');
    expect(state.colorScheme, ColorSchemes.warm);
    expect(state.markdownRenderMode, MarkdownRenderModes.enhanced);
    expect(state.todoVisualSize, TodoVisualSizes.medium);
    expect(state.externalMarkdownExtension, '.txt');
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
    )..normalize();

    final itemsById = {
      for (final item in state.papers.first.items) item.id: item,
    };
    expect(itemsById['item-valid']?.linkedNoteId, 'note-paper');
    expect(itemsById['item-missing']?.linkedNoteId, isNull);
  });

  test('normalizes deep capsule top margins', () {
    final state = AppState.fromJson({
      'deepCapsuleStartTopMargin': 2,
      'deepCapsuleQueueStartTopMargins': {
        'top': 4,
        'middle': 64,
        'bottom': 20000,
      },
    });

    expect(state.deepCapsuleStartTopMargin, 8);
    expect(state.deepCapsuleQueueStartTopMargins, {
      'top': 8,
      'middle': 64,
      'bottom': 10000,
    });
  });

  test('decodes and normalizes WebDAV sync settings', () {
    final state = AppState.fromJson({
      'sync': {
        'enabled': true,
        'provider': 'webDav',
        'futureSyncField': 'keep-sync',
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
    expect(state.sync.webDav.presetId, WebDavPresetIds.jianguoyun);
    expect(state.sync.webDav.endpoint, 'https://dav.jianguoyun.com/dav/');
    expect(state.sync.webDav.username, 'user@example.com');
    expect(state.sync.webDav.rootPath, 'RePaperTodo');
    expect(state.sync.webDav.autoSyncIntervalMinutes, 1440);
    expect(state.sync.webDav.extra['futureWebDavField'], 7);
    expect(state.sync.webDav.isConfigured, true);
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
}
