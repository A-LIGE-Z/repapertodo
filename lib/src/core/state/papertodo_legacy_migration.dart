import '../model/json_helpers.dart';

JsonMap migrateLegacyPaperTodoJson(JsonMap source) {
  final migrated = _renameKnownKeys(source, _rootKeys);
  migrated['papers'] = _migrateList(migrated['papers'], _migratePaper);
  migrated['sync'] = _migrateOptionalMap(migrated['sync'], _migrateSync);
  return migrated;
}

JsonMap _migratePaper(JsonMap source) {
  final migrated = _renameKnownKeys(source, _paperKeys);
  migrated['items'] = _migrateList(migrated['items'], _migrateItem);
  migrated['noteCanvasElements'] = _migrateList(
    migrated['noteCanvasElements'],
    _migrateNoteCanvasElement,
  );
  return migrated;
}

JsonMap _migrateItem(JsonMap source) {
  return _renameKnownKeys(source, _itemKeys);
}

JsonMap _migrateNoteCanvasElement(JsonMap source) {
  return _renameKnownKeys(source, _noteCanvasElementKeys);
}

JsonMap _migrateSync(JsonMap source) {
  final migrated = _renameKnownKeys(source, _syncKeys);
  migrated['webDav'] = _migrateOptionalMap(migrated['webDav'], _migrateWebDav);
  return migrated;
}

JsonMap _migrateWebDav(JsonMap source) {
  return _renameKnownKeys(source, _webDavKeys);
}

JsonMap? _migrateOptionalMap(
  Object? value,
  JsonMap Function(JsonMap source) migrate,
) {
  final map = jsonMapOrNull(value);
  if (map == null) {
    return null;
  }
  return migrate(map);
}

List<JsonMap> _migrateList(
  Object? value,
  JsonMap Function(JsonMap source) migrate,
) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (jsonMapOrNull(item) case final map?) migrate(map),
  ];
}

JsonMap _renameKnownKeys(JsonMap source, Map<String, String> keys) {
  final caseInsensitiveKeys = {
    for (final entry in keys.entries) entry.key.toLowerCase(): entry.value,
  };
  final migrated = <String, Object?>{};
  for (final entry in source.entries) {
    final normalizedKey = keys[entry.key] ??
        caseInsensitiveKeys[entry.key.toLowerCase()] ??
        entry.key;
    if (normalizedKey != entry.key && source.containsKey(normalizedKey)) {
      continue;
    }
    migrated[normalizedKey] = entry.value;
  }
  return migrated;
}

const _rootKeys = {
  'Papers': 'papers',
  'Theme': 'theme',
  'ColorScheme': 'colorScheme',
  'CustomThemeColorHex': 'customThemeColorHex',
  'MarkdownRenderMode': 'markdownRenderMode',
  'TodoVisualSize': 'todoVisualSize',
  'UiFontPreset': 'uiFontPreset',
  'SystemFontFamilyName': 'systemFontFamilyName',
  'ExternalMarkdownExtension': 'externalMarkdownExtension',
  'Zoom': 'zoom',
  'UseCapsuleMode': 'useCapsuleMode',
  'UseDeepCapsuleMode': 'useDeepCapsuleMode',
  'ShowTopBarNewTodoButton': 'showTopBarNewTodoButton',
  'ShowTopBarNewNoteButton': 'showTopBarNewNoteButton',
  'ShowTopBarNewPaperButtons': 'showTopBarNewPaperButtons',
  'ShowTopBarExternalOpenButton': 'showTopBarExternalOpenButton',
  'HidePapersFromWindowSwitcher': 'hidePapersFromWindowSwitcher',
  'EnableTodoNoteLinks': 'enableTodoNoteLinks',
  'ShowTodoDueRelativeTime': 'showTodoDueRelativeTime',
  'TodoDueYearDisplayMode': 'todoDueYearDisplayMode',
  'TodoLineSpacing': 'todoLineSpacing',
  'NoteLineSpacing': 'noteLineSpacing',
  'UseTodoReminderInterval': 'useTodoReminderInterval',
  'TodoReminderIntervalValue': 'todoReminderIntervalValue',
  'TodoReminderIntervalUnit': 'todoReminderIntervalUnit',
  'TodoReminderScope': 'todoReminderScope',
  'TodoReminderBubbleDurationSeconds': 'todoReminderBubbleDurationSeconds',
  'MoveCompletedTodosToBottom': 'moveCompletedTodosToBottom',
  'ShowLinkedNoteName': 'showLinkedNoteName',
  'AllowLongLinkedNoteTitles': 'allowLongLinkedNoteTitles',
  'HideLinkedNotesFromCapsules': 'hideLinkedNotesFromCapsules',
  'RunLinkedScriptCapsulesOnClick': 'runLinkedScriptCapsulesOnClick',
  'MaxTitleLength': 'maxTitleLength',
  'UseCapsuleCollapseAll': 'useCapsuleCollapseAll',
  'CapsuleCollapseAllActive': 'capsuleCollapseAllActive',
  'CapsuleCollapseAllActiveQueues': 'capsuleCollapseAllActiveQueues',
  'ShowDeepCapsuleWhileExpanded': 'showDeepCapsuleWhileExpanded',
  'CollapseExpandedDeepCapsuleOnClick': 'collapseExpandedDeepCapsuleOnClick',
  'HideDeepCapsulesWhenCovered': 'hideDeepCapsulesWhenCovered',
  'HideDeepCapsulesWhenFullscreen': 'hideDeepCapsulesWhenFullscreen',
  'EnableAnimations': 'enableAnimations',
  'EnableToolTips': 'enableToolTips',
  'StartAtLogin': 'startAtLogin',
  'PinnedTodoHotKey': 'pinnedTodoHotKey',
  'PinnedNoteHotKey': 'pinnedNoteHotKey',
  'FullscreenTopmostMode': 'fullscreenTopmostMode',
  'UsePersistentPowerShellProcess': 'usePersistentPowerShellProcess',
  'PreferPowerShell7': 'preferPowerShell7',
  'HideScriptRunWindow': 'hideScriptRunWindow',
  'DeepCapsuleStartTopMargin': 'deepCapsuleStartTopMargin',
  'DeepCapsuleQueueStartTopMargins': 'deepCapsuleQueueStartTopMargins',
  'DeepCapsuleSide': 'deepCapsuleSide',
  'DeepCapsuleMonitorDeviceName': 'deepCapsuleMonitorDeviceName',
  'TopBarHeight': 'topBarHeight',
  'Sync': 'sync',
};

const _paperKeys = {
  'Id': 'id',
  'Type': 'type',
  'Title': 'title',
  'X': 'x',
  'Y': 'y',
  'Width': 'width',
  'Height': 'height',
  'IsVisible': 'isVisible',
  'AlwaysOnTop': 'alwaysOnTop',
  'IsCollapsed': 'isCollapsed',
  'IsPinnedToDesktop': 'isPinnedToDesktop',
  'TextZoom': 'textZoom',
  'CapsuleSide': 'capsuleSide',
  'CapsuleMonitorDeviceName': 'capsuleMonitorDeviceName',
  'Items': 'items',
  'Content': 'content',
  'NoteCanvasElements': 'noteCanvasElements',
};

const _itemKeys = {
  'Id': 'id',
  'Text': 'text',
  'Done': 'done',
  'Order': 'order',
  'TodoColumnCount': 'todoColumnCount',
  'TodoExtraColumns': 'todoExtraColumns',
  'TodoColumnWidths': 'todoColumnWidths',
  'LinkedNoteId': 'linkedNoteId',
  'DueAtLocal': 'dueAtLocal',
  'ReminderIntervalValue': 'reminderIntervalValue',
  'ReminderIntervalUnit': 'reminderIntervalUnit',
};

const _noteCanvasElementKeys = {
  'Id': 'id',
  'Type': 'type',
  'Text': 'text',
  'X': 'x',
  'Y': 'y',
  'Width': 'width',
  'Height': 'height',
  'ZIndex': 'zIndex',
};

const _syncKeys = {
  'Enabled': 'enabled',
  'Provider': 'provider',
  'WebDav': 'webDav',
  'OperationDeviceSequences': 'operationDeviceSequences',
  'DeletedPaperTombstones': 'deletedPaperTombstones',
  'DeletedTodoItemTombstones': 'deletedTodoItemTombstones',
};

const _webDavKeys = {
  'PresetId': 'presetId',
  'Endpoint': 'endpoint',
  'Username': 'username',
  'Password': 'password',
  'EncryptionPassphrase': 'encryptionPassphrase',
  'RootPath': 'rootPath',
  'AutoSyncOnStart': 'autoSyncOnStart',
  'AutoSyncIntervalMinutes': 'autoSyncIntervalMinutes',
  'RequestTimeoutSeconds': 'requestTimeoutSeconds',
};
