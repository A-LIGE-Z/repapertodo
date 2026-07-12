import 'dart:async';

import '../core/model/app_state.dart';
import '../core/model/paper_data.dart';
import '../core/script/script_capsule.dart';
import '../core/startup/startup_command.dart';

abstract interface class PlatformServices {
  PaperWindowHost get paperWindows;
  TrayHost get tray;
  StartupHost get startup;
  SystemIntegrationHost get systemIntegration;
  ExternalFileHost get externalFiles;
  UriOpenHost get uriOpener;
  ScriptCapsuleHost get scriptCapsules;
  AppStorageHost get storage;
}

abstract interface class PaperWindowHost {
  Stream<PaperData> get surfaceUpdates;
  Stream<PaperData> get paperEdits;
  Stream<PaperWindowActionRequest> get actionRequests;
  Stream<String> get paperOpenRequests;
  Stream<String> get paperDeleteRequests;
  Stream<void> get coordinatorCloseRequests;

  Future<PaperWorkArea?> workAreaForPaper(PaperData paper);
  Future<void> showPaper(PaperData paper);
  Future<void> hidePaper(PaperData paper);
  Future<void> revealPinnedPaper(PaperData paper);
  Future<bool> hasVisibleSurfaces(AppState state);
  Future<bool> hasVisibleSurface(PaperData paper);
  Future<void> closePaperSurface(PaperData paper);
  Future<void> updatePaperSurface(PaperData paper);
  Future<void> capturePaperSurfaceBounds(PaperData paper);
  Future<void> restoreAll(AppState state);
  Future<void> hideCoordinatorWindow();
}

class PaperWindowActionRequest {
  const PaperWindowActionRequest({
    required this.kind,
    required this.paperId,
    this.value = '',
  });

  final String kind;
  final String paperId;
  final String value;
}

abstract final class PaperWindowActionKinds {
  static const openPaper = 'openPaper';
  static const createTodo = 'createTodo';
  static const createNote = 'createNote';
  static const openExternalMarkdown = 'openExternalMarkdown';
  static const runScriptCapsule = 'runScriptCapsule';
  static const openUri = 'openUri';

  static const values = {
    openPaper,
    createTodo,
    createNote,
    openExternalMarkdown,
    runScriptCapsule,
    openUri,
  };
}

class PaperWorkArea {
  const PaperWorkArea({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;

  bool get isUsable =>
      x.isFinite &&
      y.isFinite &&
      width.isFinite &&
      height.isFinite &&
      width > 0 &&
      height > 0;
}

abstract interface class TrayHost {
  Future<void> initialize();
  Future<void> rebuildMenu(AppState state, {TrayMenuLabels? labels});
  Future<void> dispose();
}

class TrayMenuLabels {
  const TrayMenuLabels({
    required this.newTodo,
    required this.newNote,
    required this.settings,
    required this.showAll,
    required this.hideAll,
    required this.toggleAll,
    required this.papers,
    required this.deletePaper,
    required this.deleteConfirmTitle,
    required this.deleteConfirmMessage,
    required this.inlineConfirmDelete,
    required this.inlineConfirmAction,
    required this.cancel,
    required this.exit,
    required this.todoPaper,
    required this.notePaper,
    required this.scriptPaper,
    required this.hidden,
    required this.collapsed,
    required this.desktop,
    required this.topmost,
  });

  final String newTodo;
  final String newNote;
  final String settings;
  final String showAll;
  final String hideAll;
  final String toggleAll;
  final String papers;
  final String deletePaper;
  final String deleteConfirmTitle;
  final String deleteConfirmMessage;
  final String inlineConfirmDelete;
  final String inlineConfirmAction;
  final String cancel;
  final String exit;
  final String todoPaper;
  final String notePaper;
  final String scriptPaper;
  final String hidden;
  final String collapsed;
  final String desktop;
  final String topmost;

  Map<String, Object?> toJson() {
    return {
      'newTodo': newTodo,
      'newNote': newNote,
      'settings': settings,
      'showAll': showAll,
      'hideAll': hideAll,
      'toggleAll': toggleAll,
      'papers': papers,
      'deletePaper': deletePaper,
      'deleteConfirmTitle': deleteConfirmTitle,
      'deleteConfirmMessage': deleteConfirmMessage,
      'inlineConfirmDelete': inlineConfirmDelete,
      'inlineConfirmAction': inlineConfirmAction,
      'cancel': cancel,
      'exit': exit,
      'todoPaper': todoPaper,
      'notePaper': notePaper,
      'scriptPaper': scriptPaper,
      'hidden': hidden,
      'collapsed': collapsed,
      'desktop': desktop,
      'topmost': topmost,
    };
  }
}

abstract interface class StartupHost {
  Future<bool> acquireSingleInstance();
  Future<void> forwardToPrimary(List<String> args);
  Stream<StartupCommand> get commands;
}

abstract interface class SystemIntegrationHost {
  bool get supportsStartupAtLogin;
  bool get supportsWindowSwitcherVisibility;
  bool get supportsFullscreenTopmostMode;
  bool get supportsGlobalHotkeys;

  Future<List<String>> installedFontFamilies();
  Future<void> registerGlobalHotkeys(AppState state);
  Future<void> unregisterGlobalHotkeys();
  Future<bool> isForegroundFullscreen();
  Future<void> setStartupAtLogin(bool enabled);
  Future<void> setHideFromWindowSwitcher(bool enabled);
  Future<void> setFullscreenTopmostMode(String mode);
  Future<void> exitApplication();
}

abstract interface class ExternalFileHost {
  Future<void> openFile(String path);
}

abstract interface class UriOpenHost {
  Future<void> openUri(String uri);
}

abstract interface class ScriptCapsuleHost {
  bool get supportsScriptCapsules;

  Future<void> preparePersistentProcess({
    required bool preferPowerShell7,
    required bool hideScriptRunWindow,
  });
  Future<void> runScriptCapsule(ScriptCapsuleRunRequest request);
  Future<void> stopPersistentProcesses();
}

abstract interface class AppStorageHost {
  Future<String> documentsDirectoryPath();
}

List<String> normalizeInstalledFontFamilies(Iterable<Object?> values) {
  final unique = <String, String>{};
  for (final value in values) {
    if (value is! String) {
      continue;
    }
    final family = normalizeSystemFontFamilyName(value);
    if (family.isEmpty) {
      continue;
    }
    unique.putIfAbsent(family.toLowerCase(), () => family);
  }
  final families = unique.values.toList();
  families.sort((left, right) {
    final comparison = left.toLowerCase().compareTo(right.toLowerCase());
    return comparison == 0 ? left.compareTo(right) : comparison;
  });
  return families;
}
