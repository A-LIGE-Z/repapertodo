import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../app_controller.dart';
import '../core/model/app_state.dart';
import '../core/model/paper_data.dart';
import '../core/model/sync_settings.dart';
import '../core/storage/state_store.dart';
import '../platform/noop_platform_services.dart';

const _paperWindowChannel = MethodChannel('repapertodo/paper_window');

Future<void> runRePaperTodoPaperWindow(String paperId) async {
  final store = _PaperWindowMemoryStore(paperId: paperId);
  final controller = RePaperTodoController(
    initialState: store.state,
    platform: NoopPlatformServices(),
  );
  runApp(
    _PaperWindowEngineApp(
      paperId: paperId,
      controller: controller,
      store: store,
    ),
  );
}

class _PaperWindowEngineApp extends StatefulWidget {
  const _PaperWindowEngineApp({
    required this.paperId,
    required this.controller,
    required this.store,
  });

  final String paperId;
  final RePaperTodoController controller;
  final _PaperWindowMemoryStore store;

  @override
  State<_PaperWindowEngineApp> createState() => _PaperWindowEngineAppState();
}

class _PaperWindowEngineAppState extends State<_PaperWindowEngineApp> {
  @override
  void initState() {
    super.initState();
    _paperWindowChannel.setMethodCallHandler(_handleCoordinatorCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_paperWindowChannel.invokeMethod<void>('ready', {
        'paperId': widget.paperId,
      }));
    });
  }

  @override
  void dispose() {
    _paperWindowChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<Object?> _handleCoordinatorCall(MethodCall call) async {
    switch (call.method) {
      case 'applyState':
        final stateJson = _stringKeyedMap(call.arguments);
        if (stateJson == null) {
          return false;
        }
        final state = _sanitizeChildState(AppState.fromJson(stateJson));
        if (!state.papers.any((paper) => paper.id == widget.paperId)) {
          return false;
        }
        widget.store.replaceState(state);
        if (mounted) {
          setState(() => widget.controller.replaceState(state));
        }
        return true;
      case 'applyPaper':
        final paperJson = _stringKeyedMap(call.arguments);
        if (paperJson == null) {
          return false;
        }
        final paper = PaperData.fromJson(paperJson);
        if (paper.id != widget.paperId) {
          return false;
        }
        final state = widget.controller.state;
        final index = state.papers.indexWhere((item) => item.id == paper.id);
        if (index < 0) {
          state.papers.add(paper);
        } else {
          state.papers[index] = paper;
        }
        state.normalize();
        widget.store.replaceState(state);
        if (mounted) {
          setState(() {});
        }
        return true;
    }
    throw MissingPluginException('Unknown paper window call: ${call.method}');
  }

  @override
  Widget build(BuildContext context) {
    return RePaperTodoApp(
      controller: widget.controller,
      store: widget.store,
      initialSurfacePaperId: widget.paperId,
      paperWindowMode: true,
      paperWindowActionSender: (kind, {value = ''}) async {
        await _paperWindowChannel.invokeMethod<void>('actionRequested', {
          'paperId': widget.paperId,
          'kind': kind,
          'value': value,
        });
      },
      paperWindowDragStarter: () async {
        await _paperWindowChannel.invokeMethod<void>('startDrag');
      },
      paperWindowResizeStarter: (direction) async {
        await _paperWindowChannel.invokeMethod<void>('startResize', direction);
      },
      configureAndroidBackgroundSync: ({
        required sync,
        required stateFilePath,
      }) async {},
    );
  }
}

class _PaperWindowMemoryStore extends StateStore {
  _PaperWindowMemoryStore({required this.paperId})
      : state = _sanitizeChildState(AppState()),
        super(filePath: 'paper-window-$paperId.json');

  final String paperId;
  AppState state;

  void replaceState(AppState value) {
    state = _sanitizeChildState(AppState.fromJson(value.toJson()));
  }

  @override
  Future<AppState> load() async => AppState.fromJson(state.toJson());

  @override
  Future<DateTime?> lastModifiedUtc() async => null;

  @override
  Future<void> save(AppState value) async {
    final previousState = state;
    replaceState(value);
    PaperData? paper;
    for (final item in state.papers) {
      if (item.id == paperId) {
        paper = item;
        break;
      }
    }
    if (paper == null) {
      await _paperWindowChannel.invokeMethod<void>('deleteRequested', {
        'paperId': paperId,
      });
      return;
    }
    for (final candidate in state.papers) {
      if (candidate.id == paperId || !candidate.isVisible) {
        continue;
      }
      final wasVisible = previousState.papers.any(
        (item) => item.id == candidate.id && item.isVisible,
      );
      if (!wasVisible) {
        await _paperWindowChannel.invokeMethod<void>('openRequested', {
          'paperId': candidate.id,
        });
      }
    }
    await _paperWindowChannel.invokeMethod<void>(
      'paperChanged',
      paper.toJson(),
    );
  }
}

AppState _sanitizeChildState(AppState state) {
  state.sync = SyncSettings();
  state.startAtLogin = false;
  state.normalize();
  return state;
}

Map<String, Object?>? _stringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      return null;
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}
