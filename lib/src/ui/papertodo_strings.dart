import 'package:flutter/widgets.dart';

abstract final class PaperTodoStringKeys {
  static const appTitle = 'appTitle';
  static const actionAddColumn = 'actionAddColumn';
  static const actionAddCanvasBlock = 'actionAddCanvasBlock';
  static const actionAddCodeBlock = 'actionAddCodeBlock';
  static const actionAddItem = 'actionAddItem';
  static const actionAddTextBlock = 'actionAddTextBlock';
  static const actionBackToBoard = 'actionBackToBoard';
  static const actionBrowse = 'actionBrowse';
  static const actionCancel = 'actionCancel';
  static const actionConfirm = 'actionConfirm';
  static const actionChangeDueDate = 'actionChangeDueDate';
  static const actionChangeReminder = 'actionChangeReminder';
  static const actionClear = 'actionClear';
  static const actionClose = 'actionClose';
  static const actionClearCompleted = 'actionClearCompleted';
  static const actionClearCompletedItems = 'actionClearCompletedItems';
  static const actionClearDueDate = 'actionClearDueDate';
  static const actionClearReminder = 'actionClearReminder';
  static const actionClearReminderInterval = 'actionClearReminderInterval';
  static const actionCollapseAll = 'actionCollapseAll';
  static const actionCollapseAllPapers = 'actionCollapseAllPapers';
  static const actionCollapsePaper = 'actionCollapsePaper';
  static const actionCollapseToCapsule = 'actionCollapseToCapsule';
  static const actionCopy = 'actionCopy';
  static const actionDelete = 'actionDelete';
  static const actionDeleteColumn = 'actionDeleteColumn';
  static const actionDeleteItem = 'actionDeleteItem';
  static const actionDeletePaper = 'actionDeletePaper';
  static const actionDisableAlwaysOnTop = 'actionDisableAlwaysOnTop';
  static const actionDragToLinkNoteToTodo = 'actionDragToLinkNoteToTodo';
  static const actionDragToReorder = 'actionDragToReorder';
  static const actionEditLinkedScript = 'actionEditLinkedScript';
  static const actionEditScriptCapsule = 'actionEditScriptCapsule';
  static const actionEditTitle = 'actionEditTitle';
  static const actionEqualWidths = 'actionEqualWidths';
  static const actionExpandAll = 'actionExpandAll';
  static const actionExpandAllPapers = 'actionExpandAllPapers';
  static const actionExpandPaper = 'actionExpandPaper';
  static const actionHidePaper = 'actionHidePaper';
  static const actionHideThisPaper = 'actionHideThisPaper';
  static const actionHideCompact = 'actionHideCompact';
  static const actionInsertBeforeColumn = 'actionInsertBeforeColumn';
  static const menuDeleteTodoColumn = 'menuDeleteTodoColumn';
  static const menuDecreaseTodoColumns = 'menuDecreaseTodoColumns';
  static const menuIncreaseTodoColumns = 'menuIncreaseTodoColumns';
  static const menuInsertTodoColumnBefore = 'menuInsertTodoColumnBefore';
  static const menuOpenLinkedNote = 'menuOpenLinkedNote';
  static const menuEditLinkedScriptCapsule = 'menuEditLinkedScriptCapsule';
  static const actionKeepOnTop = 'actionKeepOnTop';
  static const actionLinkNote = 'actionLinkNote';
  static const actionLinkPaper = 'actionLinkPaper';
  static const actionMore = 'actionMore';
  static const actionMoveItemDown = 'actionMoveItemDown';
  static const actionMoveItemUp = 'actionMoveItemUp';
  static const actionMovePaperWindow = 'actionMovePaperWindow';
  static const actionResizePaperWindow = 'actionResizePaperWindow';
  static const actionNewNote = 'actionNewNote';
  static const actionNewNotePaper = 'actionNewNotePaper';
  static const actionNewNotePaperCompact = 'actionNewNotePaperCompact';
  static const actionNewTodo = 'actionNewTodo';
  static const actionNewTodoPaper = 'actionNewTodoPaper';
  static const actionNewTodoPaperCompact = 'actionNewTodoPaperCompact';
  static const actionOpen = 'actionOpen';
  static const actionOpenCurrentPaperSurface = 'actionOpenCurrentPaperSurface';
  static const actionOpenLinkedNote = 'actionOpenLinkedNote';
  static const actionOpenMarkdownExternally = 'actionOpenMarkdownExternally';
  static const actionOpenMarkdownInDefaultEditor =
      'actionOpenMarkdownInDefaultEditor';
  static const actionOpenPaperSurface = 'actionOpenPaperSurface';
  static const actionOpenSurface = 'actionOpenSurface';
  static const actionPaperActions = 'actionPaperActions';
  static const actionPaperTextZoom = 'actionPaperTextZoom';
  static const actionPaste = 'actionPaste';
  static const actionPinToDesktop = 'actionPinToDesktop';
  static const actionRecovery = 'actionRecovery';
  static const actionRecoverySnapshots = 'actionRecoverySnapshots';
  static const actionRedoTodoChange = 'actionRedoTodoChange';
  static const actionRemoveLastColumn = 'actionRemoveLastColumn';
  static const actionRetry = 'actionRetry';
  static const actionRestoreWindow = 'actionRestoreWindow';
  static const actionRestore = 'actionRestore';
  static const actionResetTextZoom = 'actionResetTextZoom';
  static const actionRunPaper = 'actionRunPaper';
  static const actionRunLinkedScriptCapsule = 'actionRunLinkedScriptCapsule';
  static const actionRunScriptCapsule = 'actionRunScriptCapsule';
  static const actionSave = 'actionSave';
  static const actionSaveWindowBounds = 'actionSaveWindowBounds';
  static const actionSelectAll = 'actionSelectAll';
  static const actionSetDueDate = 'actionSetDueDate';
  static const actionSetReminder = 'actionSetReminder';
  static const actionSetReminderInterval = 'actionSetReminderInterval';
  static const actionSettings = 'actionSettings';
  static const actionShowHidden = 'actionShowHidden';
  static const actionShowHiddenPapers = 'actionShowHiddenPapers';
  static const actionSyncNow = 'actionSyncNow';
  static const actionTodoColumns = 'actionTodoColumns';
  static const actionTodoItemActions = 'actionTodoItemActions';
  static const actionUndo = 'actionUndo';
  static const actionUndoTodoChange = 'actionUndoTodoChange';
  static const actionUnlinkNote = 'actionUnlinkNote';
  static const actionUnpinFromDesktop = 'actionUnpinFromDesktop';
  static const actionWideFirstColumn = 'actionWideFirstColumn';
  static const allowLongLinkedNoteTitles = 'allowLongLinkedNoteTitles';
  static const allDue = 'allDue';
  static const animations = 'animations';
  static const appearance = 'appearance';
  static const avoidFullscreen = 'avoidFullscreen';
  static const basic = 'basic';
  static const capsuleMode = 'capsuleMode';
  static const canvasBlockActions = 'canvasBlockActions';
  static const canvasBlockGeometry = 'canvasBlockGeometry';
  static const canvasBlockTypeBlock = 'canvasBlockTypeBlock';
  static const canvasBlockTypeCode = 'canvasBlockTypeCode';
  static const canvasBlockTypeCodeLabel = 'canvasBlockTypeCodeLabel';
  static const canvasBlockTypeText = 'canvasBlockTypeText';
  static const canvasBlockTypeTextLabel = 'canvasBlockTypeTextLabel';
  static const canvasBringForward = 'canvasBringForward';
  static const canvasBringToFront = 'canvasBringToFront';
  static const canvasDefaultText = 'canvasDefaultText';
  static const canvasDeleteBlock = 'canvasDeleteBlock';
  static const canvasDragBlock = 'canvasDragBlock';
  static const canvasDuplicateBlock = 'canvasDuplicateBlock';
  static const canvasEditGeometry = 'canvasEditGeometry';
  static const canvasEnterValidNumbers = 'canvasEnterValidNumbers';
  static const canvasFieldHeight = 'canvasFieldHeight';
  static const canvasFieldLayer = 'canvasFieldLayer';
  static const canvasFieldWidth = 'canvasFieldWidth';
  static const canvasLayer = 'canvasLayer';
  static const canvasLayerActions = 'canvasLayerActions';
  static const canvasResizeBlock = 'canvasResizeBlock';
  static const canvasSendBackward = 'canvasSendBackward';
  static const canvasSendToBack = 'canvasSendToBack';
  static const canvasTopLayer = 'canvasTopLayer';
  static const collapseAllActive = 'collapseAllActive';
  static const collapseAllControl = 'collapseAllControl';
  static const collapseExpandedDeepCapsuleOnClick =
      'collapseExpandedDeepCapsuleOnClick';
  static const colorForest = 'colorForest';
  static const colorInk = 'colorInk';
  static const colorRose = 'colorRose';
  static const colorScheme = 'colorScheme';
  static const colorWarm = 'colorWarm';
  static const columnLabel = 'columnLabel';
  static const custom = 'custom';
  static const customFontFamily = 'customFontFamily';
  static const customThemeColor = 'customThemeColor';
  static const themeColorDefault = 'themeColorDefault';
  static const themeColorPick = 'themeColorPick';
  static const themeColorClear = 'themeColorClear';
  static const deepCapsuleMode = 'deepCapsuleMode';
  static const deepCapsuleMonitor = 'deepCapsuleMonitor';
  static const deepCapsuleSide = 'deepCapsuleSide';
  static const deepCapsuleTopMargin = 'deepCapsuleTopMargin';
  static const defaultFont = 'defaultFont';
  static const uiFontDefault = 'uiFontDefault';
  static const dengXian = 'dengXian';
  static const dialogDeletePaper = 'dialogDeletePaper';
  static const dialogDeletePaperBody = 'dialogDeletePaperBody';
  static const dialogDueDate = 'dialogDueDate';
  static const dialogDueDateMessage = 'dialogDueDateMessage';
  static const dialogDueDateConfirm = 'dialogDueDateConfirm';
  static const dialogRestoreSnapshot = 'dialogRestoreSnapshot';
  static const dialogSyncSettings = 'dialogSyncSettings';
  static const settingsTodoAndNotes = 'settingsTodoAndNotes';
  static const settingsCapsules = 'settingsCapsules';
  static const settingsGeneralAdvanced = 'settingsGeneralAdvanced';
  static const settingsLineSpacingReset = 'settingsLineSpacingReset';
  static const settingsSectionCapsule = 'settingsSectionCapsule';
  static const settingsSectionDisplay = 'settingsSectionDisplay';
  static const settingsSectionExternalOpen = 'settingsSectionExternalOpen';
  static const settingsSectionGeneral = 'settingsSectionGeneral';
  static const settingsSectionScriptCapsule = 'settingsSectionScriptCapsule';
  static const settingsSectionTodoAndNotes = 'settingsSectionTodoAndNotes';
  static const settingsSectionTopBarButtons = 'settingsSectionTopBarButtons';
  static const dataDirectory = 'dataDirectory';
  static const dataDirectoryHelp = 'dataDirectoryHelp';
  static const dueLabel = 'dueLabel';
  static const dueTomorrow = 'dueTomorrow';
  static const dueYearDisplay = 'dueYearDisplay';
  static const enhanced = 'enhanced';
  static const externalMarkdownOpenFailed = 'externalMarkdownOpenFailed';
  static const externalMarkdownExtension = 'externalMarkdownExtension';
  static const externalMarkdownExtensionInvalid =
      'externalMarkdownExtensionInvalid';
  static const fontPreset = 'fontPreset';
  static const fullscreenTopmostMode = 'fullscreenTopmostMode';
  static const generic = 'generic';
  static const hideCoveredDeepCapsules = 'hideCoveredDeepCapsules';
  static const hideFullscreenDeepCapsules = 'hideFullscreenDeepCapsules';
  static const hideFromTaskSwitcher = 'hideFromTaskSwitcher';
  static const hideLinkedNoteCapsules = 'hideLinkedNoteCapsules';
  static const hidePassphrase = 'hidePassphrase';
  static const hidePassword = 'hidePassword';
  static const hideScriptRunWindow = 'hideScriptRunWindow';
  static const hour = 'hour';
  static const hours = 'hours';
  static const interval = 'interval';
  static const intervalMinutes = 'intervalMinutes';
  static const large = 'large';
  static const left = 'left';
  static const labelNote = 'labelNote';
  static const labelNoteTitle = 'labelNoteTitle';
  static const labelScript = 'labelScript';
  static const markdownActionBold = 'markdownActionBold';
  static const markdownActionBoldShortcut = 'markdownActionBoldShortcut';
  static const markdownActionCodeBlock = 'markdownActionCodeBlock';
  static const markdownActionHeading = 'markdownActionHeading';
  static const markdownActionInsertLink = 'markdownActionInsertLink';
  static const markdownActionInsertLinkShortcut =
      'markdownActionInsertLinkShortcut';
  static const markdownActionItalic = 'markdownActionItalic';
  static const markdownActionItalicShortcut = 'markdownActionItalicShortcut';
  static const markdownActionList = 'markdownActionList';
  static const markdownActionMore = 'markdownActionMore';
  static const markdownActionQuote = 'markdownActionQuote';
  static const markdownActionStrikethrough = 'markdownActionStrikethrough';
  static const markdownMode = 'markdownMode';
  static const markdownOff = 'markdownOff';
  static const menuCanvas = 'menuCanvas';
  static const menuDesktopPin = 'menuDesktopPin';
  static const menuFormat = 'menuFormat';
  static const menuNew = 'menuNew';
  static const menuText = 'menuText';
  static const menuTodo = 'menuTodo';
  static const menuTodoItem = 'menuTodoItem';
  static const maxTitleLength = 'maxTitleLength';
  static const moveCompletedTodosToBottom = 'moveCompletedTodosToBottom';
  static const medium = 'medium';
  static const minute = 'minute';
  static const minutes = 'minutes';
  static const mono = 'mono';
  static const nearest = 'nearest';
  static const noYear = 'noYear';
  static const noteEmptyPreview = 'noteEmptyPreview';
  static const noteEditorHint = 'noteEditorHint';
  static const noteSpacing = 'noteSpacing';
  static const noteViewEdit = 'noteViewEdit';
  static const noteViewPreview = 'noteViewPreview';
  static const noteViewSplit = 'noteViewSplit';
  static const openedMarkdownFile = 'openedMarkdownFile';
  static const openLinkFailed = 'openLinkFailed';
  static const openLinkUnsupported = 'openLinkUnsupported';
  static const paperDeleted = 'paperDeleted';
  static const paperLimitMessage = 'paperLimitMessage';
  static const paperLimitTitle = 'paperLimitTitle';
  static const passphraseHelper = 'passphraseHelper';
  static const password = 'password';
  static const persistentPowerShellProcess = 'persistentPowerShellProcess';
  static const platformFileNotFound = 'platformFileNotFound';
  static const platformFileShareFailed = 'platformFileShareFailed';
  static const platformInvalidPath = 'platformInvalidPath';
  static const platformInvalidUri = 'platformInvalidUri';
  static const platformOpenExternalFileFailed =
      'platformOpenExternalFileFailed';
  static const platformOpenUriFailed = 'platformOpenUriFailed';
  static const platformSettingFullscreenTopmostMode =
      'platformSettingFullscreenTopmostMode';
  static const platformSettingGlobalHotkeys = 'platformSettingGlobalHotkeys';
  static const platformSettingPaperSurfaces = 'platformSettingPaperSurfaces';
  static const platformSettingScriptCapsuleProcess =
      'platformSettingScriptCapsuleProcess';
  static const platformSettingStartupAtLogin = 'platformSettingStartupAtLogin';
  static const platformSettingWindowSwitcherVisibility =
      'platformSettingWindowSwitcherVisibility';
  static const platformSettingsFailed = 'platformSettingsFailed';
  static const pinnedNoteHotkey = 'pinnedNoteHotkey';
  static const pinnedTodoHotkey = 'pinnedTodoHotkey';
  static const preferPowerShell7 = 'preferPowerShell7';
  static const relativeDueDates = 'relativeDueDates';
  static const relativeDueDayUnit = 'relativeDueDayUnit';
  static const relativeDueFuture = 'relativeDueFuture';
  static const relativeDueHourUnit = 'relativeDueHourUnit';
  static const relativeDueMinuteUnit = 'relativeDueMinuteUnit';
  static const relativeDueOverdue = 'relativeDueOverdue';
  static const recoverySnapshotFallback = 'recoverySnapshotFallback';
  static const recoverySnapshotLoadFailed = 'recoverySnapshotLoadFailed';
  static const recoverySnapshotModified = 'recoverySnapshotModified';
  static const recoverySnapshotsEmpty = 'recoverySnapshotsEmpty';
  static const reminderDisplaySeconds = 'reminderDisplaySeconds';
  static const reminderEveryHours = 'reminderEveryHours';
  static const reminderEveryMinutes = 'reminderEveryMinutes';
  static const reminderInterval = 'reminderInterval';
  static const reminderIntervalGlobal = 'reminderIntervalGlobal';
  static const reminderIntervalMessage = 'reminderIntervalMessage';
  static const reminderScope = 'reminderScope';
  static const reminderUnit = 'reminderUnit';
  static const remoteFolder = 'remoteFolder';
  static const requestTimeoutSeconds = 'requestTimeoutSeconds';
  static const right = 'right';
  static const runLinkedScriptCapsulesOnClick =
      'runLinkedScriptCapsulesOnClick';
  static const scriptCapsuleFailed = 'scriptCapsuleFailed';
  static const serif = 'serif';
  static const settingsSaveFailed = 'settingsSaveFailed';
  static const showDeepCapsuleWhileExpanded = 'showDeepCapsuleWhileExpanded';
  static const showLinkedNoteName = 'showLinkedNoteName';
  static const showPassphrase = 'showPassphrase';
  static const showPassword = 'showPassword';
  static const small = 'small';
  static const startAtLogin = 'startAtLogin';
  static const stayOnTop = 'stayOnTop';
  static const systemFont = 'systemFont';
  static const trayCollapsed = 'trayCollapsed';
  static const trayDeleteConfirmMessage = 'trayDeleteConfirmMessage';
  static const trayDeleteConfirmTitle = 'trayDeleteConfirmTitle';
  static const trayDeletePaper = 'trayDeletePaper';
  static const trayInlineConfirmDelete = 'trayInlineConfirmDelete';
  static const trayInlineConfirmAction = 'trayInlineConfirmAction';
  static const trayDesktop = 'trayDesktop';
  static const trayExit = 'trayExit';
  static const trayHidden = 'trayHidden';
  static const trayHideAll = 'trayHideAll';
  static const trayNewNote = 'trayNewNote';
  static const trayNewTodo = 'trayNewTodo';
  static const trayNotePaper = 'trayNotePaper';
  static const trayPapers = 'trayPapers';
  static const trayScriptPaper = 'trayScriptPaper';
  static const traySettings = 'traySettings';
  static const trayShowAll = 'trayShowAll';
  static const trayTodoPaper = 'trayTodoPaper';
  static const trayToggleAll = 'trayToggleAll';
  static const trayTopmost = 'trayTopmost';
  static const syncCompleteConfiguration = 'syncCompleteConfiguration';
  static const syncConflict = 'syncConflict';
  static const syncConflictSnapshotPreserved = 'syncConflictSnapshotPreserved';
  static const syncDisabled = 'syncDisabled';
  static const syncDownloaded = 'syncDownloaded';
  static const syncDownloadedLegacyPlainMigrated =
      'syncDownloadedLegacyPlainMigrated';
  static const syncDownloadedLegacyPlainNextUpload =
      'syncDownloadedLegacyPlainNextUpload';
  static const syncDownloadedLegacyPlainRetry =
      'syncDownloadedLegacyPlainRetry';
  static const syncEncryptionPassphrase = 'syncEncryptionPassphrase';
  static const webDavAppPassword = 'webDavAppPassword';
  static const jianguoyunAppPasswordHelper = 'jianguoyunAppPasswordHelper';
  static const jianguoyunAuthenticationFailed =
      'jianguoyunAuthenticationFailed';
  static const year = 'year';
  static const month = 'month';
  static const day = 'day';
  static const syncFailed = 'syncFailed';
  static const syncFoundLegacyOperationLogs = 'syncFoundLegacyOperationLogs';
  static const syncMergedRemoteChanges = 'syncMergedRemoteChanges';
  static const syncMigratedLegacyOperationLogs =
      'syncMigratedLegacyOperationLogs';
  static const syncMigratedLegacyOperationLogsPartial =
      'syncMigratedLegacyOperationLogsPartial';
  static const syncOnStart = 'syncOnStart';
  static const syncOperationLog = 'syncOperationLog';
  static const syncOperationLogs = 'syncOperationLogs';
  static const syncPayloadUnreadable = 'syncPayloadUnreadable';
  static const syncRemoteChange = 'syncRemoteChange';
  static const syncRemoteChanges = 'syncRemoteChanges';
  static const syncRemoteSnapshotEmpty = 'syncRemoteSnapshotEmpty';
  static const syncRestoreSnapshotFailed = 'syncRestoreSnapshotFailed';
  static const syncSnapshotRestored = 'syncSnapshotRestored';
  static const syncSnapshotRestoredLegacyPlainNextUpload =
      'syncSnapshotRestoredLegacyPlainNextUpload';
  static const syncUploaded = 'syncUploaded';
  static const theme = 'theme';
  static const themeDark = 'themeDark';
  static const themeLight = 'themeLight';
  static const themeSystem = 'themeSystem';
  static const todoNoteLinks = 'todoNoteLinks';
  static const todoReminders = 'todoReminders';
  static const todoSpacing = 'todoSpacing';
  static const todoReminderBubbleMessage = 'todoReminderBubbleMessage';
  static const todoReminderBubbleOverdue = 'todoReminderBubbleOverdue';
  static const todoReminderBubbleRemaining = 'todoReminderBubbleRemaining';
  static const todoReminderBubbleTitle = 'todoReminderBubbleTitle';
  static const todoReminderCountdownDay = 'todoReminderCountdownDay';
  static const todoReminderCountdownHour = 'todoReminderCountdownHour';
  static const todoReminderCountdownMinute = 'todoReminderCountdownMinute';
  static const todoReminderCountdownSecond = 'todoReminderCountdownSecond';
  static const todoReminderMultiple = 'todoReminderMultiple';
  static const todoReminderSingle = 'todoReminderSingle';
  static const todoNewItemHint = 'todoNewItemHint';
  static const todoItemDeleted = 'todoItemDeleted';
  static const todoItemFallback = 'todoItemFallback';
  static const todoVisualSize = 'todoVisualSize';
  static const tipAllowLongLinkedNoteTitles = 'tipAllowLongLinkedNoteTitles';
  static const tipCapsuleCollapseAll = 'tipCapsuleCollapseAll';
  static const tipCapsuleMode = 'tipCapsuleMode';
  static const tipCollapseExpandedDeepCapsuleOnClick =
      'tipCollapseExpandedDeepCapsuleOnClick';
  static const tipCustomThemeColor = 'tipCustomThemeColor';
  static const tipDeepCapsuleMode = 'tipDeepCapsuleMode';
  static const tipEnableAnimations = 'tipEnableAnimations';
  static const tipEnableTodoNoteLinks = 'tipEnableTodoNoteLinks';
  static const tipEnableToolTips = 'tipEnableToolTips';
  static const tipExternalExtension = 'tipExternalExtension';
  static const tipExternalOpenButton = 'tipExternalOpenButton';
  static const tipFullscreenTopmostMode = 'tipFullscreenTopmostMode';
  static const tipHideDeepCapsulesWhenCovered =
      'tipHideDeepCapsulesWhenCovered';
  static const tipHideLinkedNotesFromCapsules =
      'tipHideLinkedNotesFromCapsules';
  static const tipHidePapersFromWindowSwitcher =
      'tipHidePapersFromWindowSwitcher';
  static const tipHideScriptRunWindow = 'tipHideScriptRunWindow';
  static const tipMarkdownRender = 'tipMarkdownRender';
  static const tipMaxTitleLength = 'tipMaxTitleLength';
  static const tipMoveCompletedTodosToBottom = 'tipMoveCompletedTodosToBottom';
  static const tipNewNoteButton = 'tipNewNoteButton';
  static const tipNewTodoButton = 'tipNewTodoButton';
  static const tipNoteLineSpacing = 'tipNoteLineSpacing';
  static const tipPersistentPowerShellProcess =
      'tipPersistentPowerShellProcess';
  static const tipPinnedNoteHotKey = 'tipPinnedNoteHotKey';
  static const tipPinnedTodoHotKey = 'tipPinnedTodoHotKey';
  static const tipPreferPowerShell7 = 'tipPreferPowerShell7';
  static const tipRunLinkedScriptCapsulesOnClick =
      'tipRunLinkedScriptCapsulesOnClick';
  static const tipShowDeepCapsuleWhileExpanded =
      'tipShowDeepCapsuleWhileExpanded';
  static const tipShowLinkedNoteName = 'tipShowLinkedNoteName';
  static const tipShowTodoDueRelativeTime = 'tipShowTodoDueRelativeTime';
  static const tipStartup = 'tipStartup';
  static const tipSystemFont = 'tipSystemFont';
  static const tipThemeMode = 'tipThemeMode';
  static const tipTodoDueYearDisplay = 'tipTodoDueYearDisplay';
  static const tipTodoLineSpacing = 'tipTodoLineSpacing';
  static const tipTodoReminderBubbleDuration = 'tipTodoReminderBubbleDuration';
  static const tipTodoReminderInterval = 'tipTodoReminderInterval';
  static const tipTodoReminderIntervalUnit = 'tipTodoReminderIntervalUnit';
  static const tipTodoReminderScope = 'tipTodoReminderScope';
  static const tipTodoVisualSize = 'tipTodoVisualSize';
  static const tipUseTodoReminderInterval = 'tipUseTodoReminderInterval';
  static const tooltips = 'tooltips';
  static const tooltipsHelp = 'tooltipsHelp';
  static const topBarNewNote = 'topBarNewNote';
  static const topBarNewTodo = 'topBarNewTodo';
  static const topBarOpenSurface = 'topBarOpenSurface';
  static const untitledPaper = 'untitledPaper';
  static const username = 'username';
  static const webDavIssueEndpointInvalid = 'webDavIssueEndpointInvalid';
  static const webDavIssueEndpointRequired = 'webDavIssueEndpointRequired';
  static const webDavIssuePasswordInvalid = 'webDavIssuePasswordInvalid';
  static const webDavIssuePasswordRequired = 'webDavIssuePasswordRequired';
  static const webDavIssuePassphraseRequired = 'webDavIssuePassphraseRequired';
  static const webDavIssueProviderRootPathTooLong =
      'webDavIssueProviderRootPathTooLong';
  static const webDavIssueRootPathInvalid = 'webDavIssueRootPathInvalid';
  static const webDavIssueSummary = 'webDavIssueSummary';
  static const webDavIssueUsernameInvalid = 'webDavIssueUsernameInvalid';
  static const webDavIssueUsernameRequired = 'webDavIssueUsernameRequired';
  static const webDavProvider = 'webDavProvider';
  static const webDavSync = 'webDavSync';
  static const enableWebDavSync = 'enableWebDavSync';
  static const webDavUrl = 'webDavUrl';
  static const xl = 'xl';
  static const yaHei = 'yaHei';
  static const yy = 'yy';
  static const yyyy = 'yyyy';
  static const zoom = 'zoom';
}

final class PaperTodoStrings {
  const PaperTodoStrings._({
    required this.languageCode,
    required Map<String, String> values,
  }) : _values = values;

  static const supportedLocales = [
    Locale('zh'),
    Locale('en'),
  ];

  final String languageCode;
  final Map<String, String> _values;

  static Locale resolveLocale(
    Locale? locale,
    Iterable<Locale> supportedLocales,
  ) {
    final languageCode = _supportedLanguageCode(locale?.languageCode);
    for (final supportedLocale in supportedLocales) {
      final supportedLanguageCode =
          _supportedLanguageCode(supportedLocale.languageCode);
      if (supportedLanguageCode != null &&
          supportedLanguageCode == languageCode) {
        return Locale(supportedLanguageCode);
      }
    }
    return const Locale('en');
  }

  static PaperTodoStrings resolve(Locale locale) {
    return switch (locale.languageCode.toLowerCase()) {
      'zh' => const PaperTodoStrings._(
          languageCode: 'zh',
          values: _zhStrings,
        ),
      _ => const PaperTodoStrings._(
          languageCode: 'en',
          values: _enStrings,
        ),
    };
  }

  String get(String key) {
    return _values[key] ?? _enStrings[key] ?? key;
  }

  String format(String key, Iterable<Object?> args) {
    var text = get(key);
    var index = 0;
    for (final arg in args) {
      text = text.replaceAll('{$index}', '$arg');
      index += 1;
    }
    return text;
  }

  static String? _supportedLanguageCode(String? languageCode) {
    return switch (languageCode?.toLowerCase()) {
      'zh' => 'zh',
      'en' => 'en',
      _ => null,
    };
  }
}

final class PaperTodoStringsScope extends InheritedWidget {
  const PaperTodoStringsScope({
    required this.strings,
    required super.child,
    super.key,
  });

  final PaperTodoStrings strings;

  static PaperTodoStrings of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<PaperTodoStringsScope>();
    if (scope != null) {
      return scope.strings;
    }
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return PaperTodoStrings.resolve(locale);
  }

  @override
  bool updateShouldNotify(PaperTodoStringsScope oldWidget) {
    return oldWidget.strings.languageCode != strings.languageCode;
  }
}

const _enStrings = {
  PaperTodoStringKeys.appTitle: 'RePaperTodo',
  PaperTodoStringKeys.actionAddColumn: 'Add column',
  PaperTodoStringKeys.actionAddCanvasBlock: 'Add canvas block',
  PaperTodoStringKeys.actionAddCodeBlock: 'Add code block',
  PaperTodoStringKeys.actionAddItem: 'Add item',
  PaperTodoStringKeys.actionAddTextBlock: 'Add text block',
  PaperTodoStringKeys.actionBackToBoard: 'Back to board',
  PaperTodoStringKeys.actionCancel: 'Cancel',
  PaperTodoStringKeys.actionConfirm: 'Confirm',
  PaperTodoStringKeys.actionChangeDueDate: 'Change time',
  PaperTodoStringKeys.actionChangeReminder: 'Change reminder interval',
  PaperTodoStringKeys.actionClear: 'Clear',
  PaperTodoStringKeys.actionClose: 'Close',
  PaperTodoStringKeys.actionClearCompleted: 'Clear completed',
  PaperTodoStringKeys.actionClearCompletedItems: 'Clear completed items',
  PaperTodoStringKeys.actionClearDueDate: 'Clear time',
  PaperTodoStringKeys.actionClearReminder: 'Use global reminder interval',
  PaperTodoStringKeys.actionClearReminderInterval: 'Clear reminder interval',
  PaperTodoStringKeys.actionCollapseAll: 'Collapse all',
  PaperTodoStringKeys.actionCollapseAllPapers: 'Collapse all papers',
  PaperTodoStringKeys.actionCollapsePaper: 'Collapse paper',
  PaperTodoStringKeys.actionCollapseToCapsule: 'Collapse to capsule',
  PaperTodoStringKeys.actionCopy: 'Copy',
  PaperTodoStringKeys.actionDelete: 'Delete',
  PaperTodoStringKeys.actionDeleteColumn: 'Delete column {0}',
  PaperTodoStringKeys.actionDeleteItem: 'Delete this item',
  PaperTodoStringKeys.actionDeletePaper: 'Delete paper',
  PaperTodoStringKeys.actionDisableAlwaysOnTop: 'Disable always on top',
  PaperTodoStringKeys.actionDragToLinkNoteToTodo: 'Drag to link note to todo',
  PaperTodoStringKeys.actionDragToReorder: 'Drag to reorder',
  PaperTodoStringKeys.actionEditLinkedScript: 'Edit linked script',
  PaperTodoStringKeys.actionEditScriptCapsule: 'Edit script capsule',
  PaperTodoStringKeys.actionEditTitle: 'Click to edit title',
  PaperTodoStringKeys.actionEqualWidths: 'Equal widths',
  PaperTodoStringKeys.actionExpandAll: 'Expand all',
  PaperTodoStringKeys.actionExpandAllPapers: 'Expand all papers',
  PaperTodoStringKeys.actionExpandPaper: 'Expand paper',
  PaperTodoStringKeys.actionHidePaper: 'Hide paper',
  PaperTodoStringKeys.actionHideThisPaper: 'Hide this paper',
  PaperTodoStringKeys.actionHideCompact: 'Hide',
  PaperTodoStringKeys.actionInsertBeforeColumn: 'Insert before column {0}',
  PaperTodoStringKeys.menuDeleteTodoColumn: 'Delete this column',
  PaperTodoStringKeys.menuDecreaseTodoColumns: 'Remove column from this todo',
  PaperTodoStringKeys.menuIncreaseTodoColumns: 'Add column to this todo',
  PaperTodoStringKeys.menuInsertTodoColumnBefore:
      'Insert column before this one',
  PaperTodoStringKeys.menuOpenLinkedNote: 'Open linked note: {0}',
  PaperTodoStringKeys.menuEditLinkedScriptCapsule: 'Edit linked script: {0}',
  PaperTodoStringKeys.actionKeepOnTop: 'Keep on top',
  PaperTodoStringKeys.actionLinkNote: 'Link note',
  PaperTodoStringKeys.actionLinkPaper: 'Link {0}',
  PaperTodoStringKeys.actionMore: 'More actions',
  PaperTodoStringKeys.actionMoveItemDown: 'Move item down',
  PaperTodoStringKeys.actionMoveItemUp: 'Move item up',
  PaperTodoStringKeys.actionMovePaperWindow: 'Drag to move paper',
  PaperTodoStringKeys.actionResizePaperWindow: 'Drag an edge to resize paper',
  PaperTodoStringKeys.actionNewNote: 'New note',
  PaperTodoStringKeys.actionNewNotePaper: 'New note paper',
  PaperTodoStringKeys.actionNewNotePaperCompact: '+ Note paper',
  PaperTodoStringKeys.actionNewTodo: 'New todo',
  PaperTodoStringKeys.actionNewTodoPaper: 'New todo paper',
  PaperTodoStringKeys.actionNewTodoPaperCompact: '+ Todo paper',
  PaperTodoStringKeys.actionOpen: 'Open',
  PaperTodoStringKeys.actionOpenCurrentPaperSurface:
      'Open current paper surface',
  PaperTodoStringKeys.actionOpenLinkedNote: 'Open linked note',
  PaperTodoStringKeys.actionOpenMarkdownExternally: 'Open markdown externally',
  PaperTodoStringKeys.actionOpenMarkdownInDefaultEditor:
      'Open in default {0} editor',
  PaperTodoStringKeys.actionOpenPaperSurface: 'Open paper surface',
  PaperTodoStringKeys.actionOpenSurface: 'Open surface',
  PaperTodoStringKeys.actionPaperActions: 'Paper actions',
  PaperTodoStringKeys.actionPaperTextZoom: 'Paper text zoom',
  PaperTodoStringKeys.actionPaste: 'Paste',
  PaperTodoStringKeys.actionPinToDesktop: 'Pin to desktop',
  PaperTodoStringKeys.actionRecovery: 'Recovery',
  PaperTodoStringKeys.actionRecoverySnapshots: 'Recovery snapshots',
  PaperTodoStringKeys.actionRedoTodoChange: 'Redo todo change',
  PaperTodoStringKeys.actionRemoveLastColumn: 'Remove last column',
  PaperTodoStringKeys.actionRetry: 'Retry',
  PaperTodoStringKeys.actionRestoreWindow: 'Restore window',
  PaperTodoStringKeys.actionRestore: 'Restore',
  PaperTodoStringKeys.actionResetTextZoom: 'Click to reset to 100%',
  PaperTodoStringKeys.actionRunPaper: 'Run {0}',
  PaperTodoStringKeys.actionRunLinkedScriptCapsule: 'Run linked script capsule',
  PaperTodoStringKeys.actionRunScriptCapsule: 'Run script capsule',
  PaperTodoStringKeys.actionSave: 'Save',
  PaperTodoStringKeys.actionSaveWindowBounds: 'Save window bounds',
  PaperTodoStringKeys.actionSelectAll: 'Select all',
  PaperTodoStringKeys.actionSetDueDate: 'Set time',
  PaperTodoStringKeys.actionSetReminder: 'Set reminder interval',
  PaperTodoStringKeys.actionSetReminderInterval: 'Set reminder interval',
  PaperTodoStringKeys.actionSettings: 'Settings',
  PaperTodoStringKeys.actionShowHidden: 'Show hidden',
  PaperTodoStringKeys.actionShowHiddenPapers: 'Show hidden papers',
  PaperTodoStringKeys.actionSyncNow: 'Sync now',
  PaperTodoStringKeys.actionTodoColumns: 'Todo columns',
  PaperTodoStringKeys.actionTodoItemActions: 'Todo item actions',
  PaperTodoStringKeys.actionUndo: 'Undo',
  PaperTodoStringKeys.actionUndoTodoChange: 'Undo todo change',
  PaperTodoStringKeys.actionUnlinkNote: 'Unlink note',
  PaperTodoStringKeys.actionUnpinFromDesktop: 'Unpin from desktop',
  PaperTodoStringKeys.actionWideFirstColumn: 'Wide first column',
  PaperTodoStringKeys.allowLongLinkedNoteTitles: 'Long linked note titles',
  PaperTodoStringKeys.allDue: 'All',
  PaperTodoStringKeys.animations: 'Enable animations',
  PaperTodoStringKeys.appearance: 'Display',
  PaperTodoStringKeys.avoidFullscreen: 'Avoid',
  PaperTodoStringKeys.basic: 'Basic',
  PaperTodoStringKeys.capsuleMode: 'Capsule mode',
  PaperTodoStringKeys.canvasBlockActions: 'Canvas block actions',
  PaperTodoStringKeys.canvasBlockGeometry: 'Canvas block geometry',
  PaperTodoStringKeys.canvasBlockTypeBlock: 'BLOCK',
  PaperTodoStringKeys.canvasBlockTypeCode: 'CODE',
  PaperTodoStringKeys.canvasBlockTypeCodeLabel: 'Code',
  PaperTodoStringKeys.canvasBlockTypeText: 'TEXT',
  PaperTodoStringKeys.canvasBlockTypeTextLabel: 'Text',
  PaperTodoStringKeys.canvasBringForward: 'Bring forward',
  PaperTodoStringKeys.canvasBringToFront: 'Bring to front',
  PaperTodoStringKeys.canvasDefaultText: 'Canvas text {0}',
  PaperTodoStringKeys.canvasDeleteBlock: 'Delete canvas block',
  PaperTodoStringKeys.canvasDragBlock: 'Drag canvas block',
  PaperTodoStringKeys.canvasDuplicateBlock: 'Duplicate canvas block',
  PaperTodoStringKeys.canvasEditGeometry: 'Edit canvas geometry',
  PaperTodoStringKeys.canvasEnterValidNumbers:
      'Enter valid numbers for every field.',
  PaperTodoStringKeys.canvasFieldHeight: 'Height',
  PaperTodoStringKeys.canvasFieldLayer: 'Layer',
  PaperTodoStringKeys.canvasFieldWidth: 'Width',
  PaperTodoStringKeys.canvasLayer: 'Layer {0}',
  PaperTodoStringKeys.canvasLayerActions: 'Canvas layer actions',
  PaperTodoStringKeys.canvasResizeBlock: 'Resize canvas block',
  PaperTodoStringKeys.canvasSendBackward: 'Send backward',
  PaperTodoStringKeys.canvasSendToBack: 'Send to back',
  PaperTodoStringKeys.canvasTopLayer: 'Top {0}',
  PaperTodoStringKeys.collapseAllActive: 'Collapse all active',
  PaperTodoStringKeys.collapseAllControl: 'Show main capsule',
  PaperTodoStringKeys.collapseExpandedDeepCapsuleOnClick:
      'Click edge capsule again to retract paper',
  PaperTodoStringKeys.colorForest: 'Forest',
  PaperTodoStringKeys.colorInk: 'Ink',
  PaperTodoStringKeys.colorRose: 'Rose',
  PaperTodoStringKeys.colorScheme: 'Color scheme',
  PaperTodoStringKeys.colorWarm: 'Warm',
  PaperTodoStringKeys.columnLabel: 'Column {0}',
  PaperTodoStringKeys.custom: 'Custom',
  PaperTodoStringKeys.customFontFamily: 'Custom font family',
  PaperTodoStringKeys.customThemeColor: 'Global theme color',
  PaperTodoStringKeys.themeColorDefault: 'Use default palette',
  PaperTodoStringKeys.themeColorPick: 'Choose color',
  PaperTodoStringKeys.themeColorClear: 'Default color',
  PaperTodoStringKeys.deepCapsuleMode: 'Edge capsule mode',
  PaperTodoStringKeys.deepCapsuleMonitor: 'Deep capsule monitor',
  PaperTodoStringKeys.deepCapsuleSide: 'Deep capsule side',
  PaperTodoStringKeys.deepCapsuleTopMargin: 'Deep capsule top margin',
  PaperTodoStringKeys.defaultFont: 'Default',
  PaperTodoStringKeys.uiFontDefault: 'Language default',
  PaperTodoStringKeys.dengXian: 'DengXian',
  PaperTodoStringKeys.dialogDeletePaper: 'Delete paper?',
  PaperTodoStringKeys.dialogDeletePaperBody:
      'This paper will be permanently removed and cannot be restored from the tray.',
  PaperTodoStringKeys.dialogDueDate: 'Set time',
  PaperTodoStringKeys.dialogDueDateMessage:
      'Choose the local date and time for this todo item.',
  PaperTodoStringKeys.dialogDueDateConfirm: 'OK',
  PaperTodoStringKeys.dialogRestoreSnapshot: 'Restore snapshot?',
  PaperTodoStringKeys.dialogSyncSettings: 'Sync settings',
  PaperTodoStringKeys.settingsTodoAndNotes: 'Todo / Notes',
  PaperTodoStringKeys.settingsCapsules: 'Capsules',
  PaperTodoStringKeys.settingsGeneralAdvanced: 'General / Advanced',
  PaperTodoStringKeys.settingsLineSpacingReset: 'Default',
  PaperTodoStringKeys.settingsSectionCapsule: 'Capsule',
  PaperTodoStringKeys.settingsSectionDisplay: 'Display',
  PaperTodoStringKeys.settingsSectionExternalOpen: 'External open',
  PaperTodoStringKeys.settingsSectionGeneral: 'General',
  PaperTodoStringKeys.settingsSectionScriptCapsule: 'Script capsule',
  PaperTodoStringKeys.settingsSectionTodoAndNotes: 'To-dos & notes',
  PaperTodoStringKeys.settingsSectionTopBarButtons: 'Top-bar buttons',
  PaperTodoStringKeys.actionBrowse: 'Browse',
  PaperTodoStringKeys.dataDirectory: 'Data folder',
  PaperTodoStringKeys.dataDirectoryHelp:
      'Stores data.json, backups, and recovery files. Existing data is copied when this folder changes.',
  PaperTodoStringKeys.dueLabel: 'Due {0}',
  PaperTodoStringKeys.dueTomorrow: 'Tomorrow {0}',
  PaperTodoStringKeys.dueYearDisplay: 'Due year display',
  PaperTodoStringKeys.enhanced: 'Enhanced',
  PaperTodoStringKeys.externalMarkdownOpenFailed:
      'External markdown open failed: {0}',
  PaperTodoStringKeys.externalMarkdownExtension: 'External open file type',
  PaperTodoStringKeys.externalMarkdownExtensionInvalid:
      'Use an extension such as .md, .txt, or .todo.md without reserved filename characters, control characters, or a trailing dot or space.',
  PaperTodoStringKeys.fontPreset: 'Font preset',
  PaperTodoStringKeys.fullscreenTopmostMode: 'Fullscreen handling',
  PaperTodoStringKeys.generic: 'Generic',
  PaperTodoStringKeys.hideCoveredDeepCapsules:
      'Hide edge capsules when covered',
  PaperTodoStringKeys.hideFullscreenDeepCapsules:
      'Hide edge capsules during fullscreen apps',
  PaperTodoStringKeys.hideFromTaskSwitcher: 'Hide papers from window switching',
  PaperTodoStringKeys.hideLinkedNoteCapsules:
      'Linked notes not shown as capsules',
  PaperTodoStringKeys.hidePassphrase: 'Hide passphrase',
  PaperTodoStringKeys.hidePassword: 'Hide password',
  PaperTodoStringKeys.hideScriptRunWindow: 'Hide script window',
  PaperTodoStringKeys.hour: 'Hour',
  PaperTodoStringKeys.hours: 'Hours',
  PaperTodoStringKeys.interval: 'Interval',
  PaperTodoStringKeys.intervalMinutes: 'Interval minutes',
  PaperTodoStringKeys.large: 'Large',
  PaperTodoStringKeys.left: 'Left',
  PaperTodoStringKeys.labelNote: 'Note',
  PaperTodoStringKeys.labelNoteTitle: 'Note {0}',
  PaperTodoStringKeys.labelScript: 'Script',
  PaperTodoStringKeys.markdownActionBold: 'Bold',
  PaperTodoStringKeys.markdownActionBoldShortcut: 'Bold (Ctrl+B)',
  PaperTodoStringKeys.markdownActionCodeBlock: 'Code block',
  PaperTodoStringKeys.markdownActionHeading: 'Heading',
  PaperTodoStringKeys.markdownActionInsertLink: 'Insert link',
  PaperTodoStringKeys.markdownActionInsertLinkShortcut: 'Insert link (Ctrl+K)',
  PaperTodoStringKeys.markdownActionItalic: 'Italic',
  PaperTodoStringKeys.markdownActionItalicShortcut: 'Italic (Ctrl+I)',
  PaperTodoStringKeys.markdownActionList: 'List',
  PaperTodoStringKeys.markdownActionMore: 'More markdown actions',
  PaperTodoStringKeys.markdownActionQuote: 'Quote',
  PaperTodoStringKeys.markdownActionStrikethrough: 'Strikethrough',
  PaperTodoStringKeys.markdownMode: 'Markdown display',
  PaperTodoStringKeys.markdownOff: 'Off',
  PaperTodoStringKeys.menuCanvas: 'Canvas',
  PaperTodoStringKeys.menuDesktopPin: 'Desktop pin',
  PaperTodoStringKeys.menuFormat: 'Format',
  PaperTodoStringKeys.menuNew: 'New',
  PaperTodoStringKeys.menuText: 'Text',
  PaperTodoStringKeys.menuTodo: 'Todo',
  PaperTodoStringKeys.menuTodoItem: 'Item',
  PaperTodoStringKeys.maxTitleLength: 'Title length limit',
  PaperTodoStringKeys.moveCompletedTodosToBottom:
      'Move completed todos below unfinished todos',
  PaperTodoStringKeys.medium: 'Medium',
  PaperTodoStringKeys.minute: 'Minute',
  PaperTodoStringKeys.minutes: 'Minutes',
  PaperTodoStringKeys.mono: 'Mono',
  PaperTodoStringKeys.nearest: 'Nearest',
  PaperTodoStringKeys.noYear: 'None',
  PaperTodoStringKeys.noteEmptyPreview: '_No note content._',
  PaperTodoStringKeys.noteEditorHint: 'Write a note...',
  PaperTodoStringKeys.noteSpacing: 'Note spacing',
  PaperTodoStringKeys.noteViewEdit: 'Edit',
  PaperTodoStringKeys.noteViewPreview: 'Preview',
  PaperTodoStringKeys.noteViewSplit: 'Split',
  PaperTodoStringKeys.openedMarkdownFile: 'Opened markdown file: {0}',
  PaperTodoStringKeys.openLinkFailed: 'Open link failed: {0}',
  PaperTodoStringKeys.openLinkUnsupported:
      'Open link failed: unsupported link target.',
  PaperTodoStringKeys.paperDeleted: '{0} deleted.',
  PaperTodoStringKeys.paperLimitMessage:
      'You have reached the 100-paper limit.\nDelete papers you no longer need before creating more.',
  PaperTodoStringKeys.paperLimitTitle: 'Paper limit reached',
  PaperTodoStringKeys.passphraseHelper:
      'Required for encrypted Windows and Android sync.',
  PaperTodoStringKeys.password: 'Password',
  PaperTodoStringKeys.persistentPowerShellProcess:
      'Persistent PowerShell process',
  PaperTodoStringKeys.platformFileNotFound: 'The file does not exist.',
  PaperTodoStringKeys.platformFileShareFailed:
      'The file cannot be shared securely.',
  PaperTodoStringKeys.platformInvalidPath:
      'The file path is invalid or outside the RePaperTodo share folders.',
  PaperTodoStringKeys.platformInvalidUri: 'The URI is invalid or unsupported.',
  PaperTodoStringKeys.platformOpenExternalFileFailed:
      'Unable to open the external file.',
  PaperTodoStringKeys.platformOpenUriFailed: 'Unable to open the URI.',
  PaperTodoStringKeys.platformSettingFullscreenTopmostMode:
      'Fullscreen/topmost mode',
  PaperTodoStringKeys.platformSettingGlobalHotkeys: 'Global hotkeys',
  PaperTodoStringKeys.platformSettingPaperSurfaces: 'Paper surfaces',
  PaperTodoStringKeys.platformSettingScriptCapsuleProcess:
      'Script capsule process',
  PaperTodoStringKeys.platformSettingStartupAtLogin: 'Startup at login',
  PaperTodoStringKeys.platformSettingWindowSwitcherVisibility:
      'Window switcher visibility',
  PaperTodoStringKeys.platformSettingsFailed: 'Platform settings failed: {0}',
  PaperTodoStringKeys.pinnedNoteHotkey: 'Pinned note hotkey',
  PaperTodoStringKeys.pinnedTodoHotkey: 'Pinned todo hotkey',
  PaperTodoStringKeys.preferPowerShell7: 'Prefer PowerShell 7',
  PaperTodoStringKeys.relativeDueDates: 'Show relative todo time',
  PaperTodoStringKeys.relativeDueDayUnit: '{0}d',
  PaperTodoStringKeys.relativeDueFuture: 'in {0}',
  PaperTodoStringKeys.relativeDueHourUnit: '{0}h',
  PaperTodoStringKeys.relativeDueMinuteUnit: '{0}m',
  PaperTodoStringKeys.relativeDueOverdue: '{0} overdue',
  PaperTodoStringKeys.recoverySnapshotFallback: 'Snapshot',
  PaperTodoStringKeys.recoverySnapshotLoadFailed:
      'Unable to load snapshots: {0}',
  PaperTodoStringKeys.recoverySnapshotModified: 'Modified {0}',
  PaperTodoStringKeys.recoverySnapshotsEmpty: 'No recovery snapshots found.',
  PaperTodoStringKeys.reminderDisplaySeconds: 'Bubble duration (seconds)',
  PaperTodoStringKeys.reminderEveryHours: 'Every {0} hr',
  PaperTodoStringKeys.reminderEveryMinutes: 'Every {0} min',
  PaperTodoStringKeys.reminderInterval: 'Reminder interval',
  PaperTodoStringKeys.reminderIntervalGlobal: 'Global',
  PaperTodoStringKeys.reminderIntervalMessage:
      'Set a custom reminder interval for this todo. It overrides the app setting when interval reminder bubbles are enabled.',
  PaperTodoStringKeys.reminderScope: 'Reminder target',
  PaperTodoStringKeys.reminderUnit: 'Interval unit',
  PaperTodoStringKeys.remoteFolder: 'Remote folder',
  PaperTodoStringKeys.requestTimeoutSeconds: 'Request timeout seconds',
  PaperTodoStringKeys.right: 'Right',
  PaperTodoStringKeys.runLinkedScriptCapsulesOnClick:
      'Run linked scripts directly',
  PaperTodoStringKeys.scriptCapsuleFailed: 'Script capsule failed: {0}',
  PaperTodoStringKeys.serif: 'Serif',
  PaperTodoStringKeys.settingsSaveFailed: 'Settings save failed: {0}',
  PaperTodoStringKeys.showDeepCapsuleWhileExpanded:
      'Show deep capsule while expanded',
  PaperTodoStringKeys.showLinkedNoteName: 'Show linked note title',
  PaperTodoStringKeys.showPassphrase: 'Show passphrase',
  PaperTodoStringKeys.showPassword: 'Show password',
  PaperTodoStringKeys.small: 'Small',
  PaperTodoStringKeys.startAtLogin: 'Start with Windows',
  PaperTodoStringKeys.stayOnTop: 'Stay on top',
  PaperTodoStringKeys.systemFont: 'System font',
  PaperTodoStringKeys.trayCollapsed: 'collapsed',
  PaperTodoStringKeys.trayDeleteConfirmMessage: 'Delete "{0}"?',
  PaperTodoStringKeys.trayDeleteConfirmTitle: 'Delete paper?',
  PaperTodoStringKeys.trayDeletePaper: 'Delete paper...',
  PaperTodoStringKeys.trayInlineConfirmDelete: '⚠ Delete',
  PaperTodoStringKeys.trayInlineConfirmAction: 'Confirm',
  PaperTodoStringKeys.trayDesktop: 'desktop',
  PaperTodoStringKeys.trayExit: 'Exit',
  PaperTodoStringKeys.trayHidden: 'hidden',
  PaperTodoStringKeys.trayHideAll: 'Hide all papers',
  PaperTodoStringKeys.trayNewNote: '+ New note paper',
  PaperTodoStringKeys.trayNewTodo: '+ New todo paper',
  PaperTodoStringKeys.trayNotePaper: 'Note',
  PaperTodoStringKeys.trayPapers: 'Papers',
  PaperTodoStringKeys.trayScriptPaper: 'Script',
  PaperTodoStringKeys.traySettings: 'Settings',
  PaperTodoStringKeys.trayShowAll: 'Show all papers',
  PaperTodoStringKeys.trayTodoPaper: 'Todo',
  PaperTodoStringKeys.trayToggleAll: 'Toggle all papers',
  PaperTodoStringKeys.trayTopmost: 'topmost',
  PaperTodoStringKeys.syncCompleteConfiguration:
      'Complete WebDAV sync settings and encryption passphrase first.',
  PaperTodoStringKeys.syncConflict:
      'Remote data changed during sync. Pull again before upload.',
  PaperTodoStringKeys.syncConflictSnapshotPreserved:
      'Remote data changed during sync. Local snapshot preserved at {0}.',
  PaperTodoStringKeys.syncDisabled: 'Sync is disabled.',
  PaperTodoStringKeys.syncDownloaded: 'Remote data downloaded.',
  PaperTodoStringKeys.syncDownloadedLegacyPlainMigrated:
      'Remote data downloaded from legacy plain WebDAV data and migrated to encrypted payloads.',
  PaperTodoStringKeys.syncDownloadedLegacyPlainNextUpload:
      'Remote data downloaded from legacy plain WebDAV data. The next successful upload will write encrypted payloads.',
  PaperTodoStringKeys.syncDownloadedLegacyPlainRetry:
      'Remote data downloaded from legacy plain WebDAV data. Automatic encryption migration could not complete; sync again to retry.',
  PaperTodoStringKeys.syncEncryptionPassphrase: 'Sync encryption passphrase',
  PaperTodoStringKeys.webDavAppPassword: 'WebDAV app password',
  PaperTodoStringKeys.jianguoyunAppPasswordHelper:
      'Jianguoyun requires an app password from Third-party app management; the account login password will return HTTP 401.',
  PaperTodoStringKeys.jianguoyunAuthenticationFailed:
      'Jianguoyun rejected the credentials. Enter the email address and the app password generated under Third-party app management. Do not enter the account login password or the sync encryption passphrase here.',
  PaperTodoStringKeys.year: 'Year',
  PaperTodoStringKeys.month: 'Month',
  PaperTodoStringKeys.day: 'Day',
  PaperTodoStringKeys.syncFailed: 'Sync failed: {0}',
  PaperTodoStringKeys.syncFoundLegacyOperationLogs:
      'Found {0} legacy plain WebDAV {1}; sync again after remote ETags are available to retry encryption migration.',
  PaperTodoStringKeys.syncMergedRemoteChanges: 'Merged {0} remote {1}.',
  PaperTodoStringKeys.syncMigratedLegacyOperationLogs:
      'Migrated {0} legacy WebDAV {1} to encrypted payloads.',
  PaperTodoStringKeys.syncMigratedLegacyOperationLogsPartial:
      'Migrated {0} of {1} legacy WebDAV {2} to encrypted payloads; sync again to retry the rest.',
  PaperTodoStringKeys.syncOnStart: 'Sync on start',
  PaperTodoStringKeys.syncOperationLog: 'operation log',
  PaperTodoStringKeys.syncOperationLogs: 'operation logs',
  PaperTodoStringKeys.syncPayloadUnreadable:
      'Unable to decrypt remote sync data. Check the sync encryption passphrase.',
  PaperTodoStringKeys.syncRemoteChange: 'change',
  PaperTodoStringKeys.syncRemoteChanges: 'changes',
  PaperTodoStringKeys.syncRemoteSnapshotEmpty: 'Remote snapshot is empty.',
  PaperTodoStringKeys.syncRestoreSnapshotFailed: 'Restore failed: {0}',
  PaperTodoStringKeys.syncSnapshotRestored: 'Snapshot restored.',
  PaperTodoStringKeys.syncSnapshotRestoredLegacyPlainNextUpload:
      'Snapshot restored from legacy plain WebDAV data. The next successful upload will write encrypted payloads.',
  PaperTodoStringKeys.syncUploaded: 'Local data uploaded.',
  PaperTodoStringKeys.theme: 'Theme mode',
  PaperTodoStringKeys.themeDark: 'Dark',
  PaperTodoStringKeys.themeLight: 'Light',
  PaperTodoStringKeys.themeSystem: 'System',
  PaperTodoStringKeys.todoNoteLinks: 'Enable todo-note links',
  PaperTodoStringKeys.todoReminders: 'Use interval reminder bubbles',
  PaperTodoStringKeys.todoSpacing: 'Todo spacing',
  PaperTodoStringKeys.todoReminderBubbleMessage: '{0}\n{1}\n{2}',
  PaperTodoStringKeys.todoReminderBubbleOverdue: '{0} overdue',
  PaperTodoStringKeys.todoReminderBubbleRemaining: 'in {0}',
  PaperTodoStringKeys.todoReminderBubbleTitle: 'Todo due soon',
  PaperTodoStringKeys.todoReminderCountdownDay: '{0}d ',
  PaperTodoStringKeys.todoReminderCountdownHour: '{0}h ',
  PaperTodoStringKeys.todoReminderCountdownMinute: '{0}m ',
  PaperTodoStringKeys.todoReminderCountdownSecond: '{0}s',
  PaperTodoStringKeys.todoReminderMultiple: 'Reminder: {0} todo items are due.',
  PaperTodoStringKeys.todoReminderSingle: 'Reminder: {0} - {1}',
  PaperTodoStringKeys.todoNewItemHint: 'New item',
  PaperTodoStringKeys.todoItemDeleted: '{0} deleted.',
  PaperTodoStringKeys.todoItemFallback: 'Todo item',
  PaperTodoStringKeys.todoVisualSize: 'Todo size',
  PaperTodoStringKeys.tipAllowLongLinkedNoteTitles:
      'When off, linked note titles stay compact. When on, they expand to fit content: about 5 full-width characters on one-line todos and 10 on multiline todos.',
  PaperTodoStringKeys.tipCapsuleCollapseAll:
      'Show a main capsule at the top of the capsule queue to collapse or expand the current queue.',
  PaperTodoStringKeys.tipCapsuleMode:
      'Allow papers to collapse into small capsules to save desktop space. Edge capsule features require this first.',
  PaperTodoStringKeys.tipCollapseExpandedDeepCapsuleOnClick:
      'When a paper is open from an edge capsule, click the same capsule again to retract the paper.',
  PaperTodoStringKeys.tipCustomThemeColor:
      'Click the color block to open the full color picker. The chosen color generates the whole app palette instead of only changing this setting item.',
  PaperTodoStringKeys.tipDeepCapsuleMode:
      'Capsules dock to the screen edge as a queue and slide out on hover.',
  PaperTodoStringKeys.tipEnableAnimations:
      'Enable transition animations for common actions. Turn off for a more direct response.',
  PaperTodoStringKeys.tipEnableTodoNoteLinks:
      'Drag a note onto a todo item to link it, then open the note directly from that item.',
  PaperTodoStringKeys.tipEnableToolTips:
      'Show brief hints when the pointer rests on buttons or interactive areas. Setting info icons stay available either way.',
  PaperTodoStringKeys.tipExternalExtension:
      'Choose the file type used when handing the note to an external app, such as .md or .txt.',
  PaperTodoStringKeys.tipExternalOpenButton:
      'Show the external open button in the top bar, writing the current note to a temporary file and handing it to the default app.',
  PaperTodoStringKeys.tipFullscreenTopmostMode:
      'When video, games, or other fullscreen windows are detected, papers and edge capsules can temporarily step aside. Stay on top keeps them visible.',
  PaperTodoStringKeys.tipHideDeepCapsulesWhenCovered:
      'When an external window overlaps an edge capsule\'s docked area, the capsule hides immediately and returns when the area is clear.',
  PaperTodoStringKeys.tipHideLinkedNotesFromCapsules:
      'Notes linked to todo items no longer appear in the capsule list, avoiding duplicate entry points.',
  PaperTodoStringKeys.tipHidePapersFromWindowSwitcher:
      'When on, expanded papers are hidden from Alt+Tab and Task View. They remain accessible from the tray, desktop papers, and capsules.',
  PaperTodoStringKeys.tipHideScriptRunWindow:
      'Hide the script window. Normal !p / !power waits for completion and captures errors; !pf / !powerf only submits to the persistent process.',
  PaperTodoStringKeys.tipMarkdownRender:
      'Basic mode applies light highlighting; Enhanced also styles headings, lists, and emphasis.',
  PaperTodoStringKeys.tipMaxTitleLength:
      'Maximum number of characters shown in paper titles and capsules.',
  PaperTodoStringKeys.tipMoveCompletedTodosToBottom:
      'When enabled, completing a todo moves it below all unfinished todos with a smooth transition. Reopening a todo restores the unfinished group order.',
  PaperTodoStringKeys.tipNewNoteButton:
      'Show the new note button in the paper top bar.',
  PaperTodoStringKeys.tipNewTodoButton:
      'Show the new todo button in the paper top bar.',
  PaperTodoStringKeys.tipNoteLineSpacing:
      'Type the line spacing multiplier for note text. Default is 1; range is 0.8 to 5.',
  PaperTodoStringKeys.tipPersistentPowerShellProcess:
      '!pf / !powerf reuse a persistent process for faster startup, but variables and state may carry between scripts. Turning this off ends that process.',
  PaperTodoStringKeys.tipPinnedNoteHotKey:
      'Press a key combination in the box to bring a pinned note paper from the desktop bottom to the front. Esc, Backspace, or Delete clears it.',
  PaperTodoStringKeys.tipPinnedTodoHotKey:
      'Press a key combination in the box to bring a pinned todo paper from the desktop bottom to the front. Esc, Backspace, or Delete clears it.',
  PaperTodoStringKeys.tipPreferPowerShell7:
      'Prefer PowerShell 7 (pwsh.exe); fall back to Windows PowerShell when unavailable. Scripts can also use !pwsh or !ps5 to choose.',
  PaperTodoStringKeys.tipRunLinkedScriptCapsulesOnClick:
      'When a linked entry points to a script capsule, left-click runs it and right-click opens it for editing. Off by default to prevent accidental runs.',
  PaperTodoStringKeys.tipShowDeepCapsuleWhileExpanded:
      'After opening a paper from an edge capsule, keep its edge entry visible. When off, that entry is hidden while the paper is open.',
  PaperTodoStringKeys.tipShowLinkedNoteName:
      'Show the linked note title after the todo item.',
  PaperTodoStringKeys.tipShowTodoDueRelativeTime:
      'Todo time badges can show how long remains, or how long they have been overdue, instead of the calendar time.',
  PaperTodoStringKeys.tipStartup:
      'Launch PaperTodo automatically when Windows starts.',
  PaperTodoStringKeys.tipSystemFont:
      'Choose from fonts currently installed in Windows. The selected font applies to the UI, tray, capsules, todos, and note text. Choose language default to clear the manual system font and use the app default font rules.',
  PaperTodoStringKeys.tipThemeMode:
      'Choose light, dark, or follow the Windows system theme.',
  PaperTodoStringKeys.tipTodoDueYearDisplay:
      'Choose whether todo due badges include a year, shown as 26 or 2026.',
  PaperTodoStringKeys.tipTodoLineSpacing:
      'Type the line spacing multiplier for multiline todo text. Default is 1; range is 0.8 to 5.',
  PaperTodoStringKeys.tipTodoReminderBubbleDuration:
      'How long reminder bubbles stay visible before closing. Hovering a bubble pauses its timer.',
  PaperTodoStringKeys.tipTodoReminderInterval:
      'How often an unfinished todo can show another reminder bubble once it is within the selected interval before due, or already overdue.',
  PaperTodoStringKeys.tipTodoReminderIntervalUnit:
      'Choose whether the reminder interval value is counted in minutes or hours.',
  PaperTodoStringKeys.tipTodoReminderScope:
      'Nearest shows only the closest matching todo per reminder check; All can show every matching todo.',
  PaperTodoStringKeys.tipTodoVisualSize:
      'Adjust todo text, row height, and spacing.',
  PaperTodoStringKeys.tipUseTodoReminderInterval:
      'Repeat reminder bubbles by the selected interval. Off keeps the original one-time due-soon reminder.',
  PaperTodoStringKeys.tooltips: 'Show hover hints',
  PaperTodoStringKeys.tooltipsHelp:
      'Only hides ordinary operation hints. Settings explanations stay available.',
  PaperTodoStringKeys.topBarNewNote: 'Top bar new note',
  PaperTodoStringKeys.topBarNewTodo: 'Top bar new todo',
  PaperTodoStringKeys.topBarOpenSurface: 'Show external open button',
  PaperTodoStringKeys.untitledPaper: 'Untitled',
  PaperTodoStringKeys.username: 'Username',
  PaperTodoStringKeys.webDavIssueEndpointInvalid:
      'Use a full http:// or https:// WebDAV URL without user info, query, fragment, backslashes, control characters, encoded authority or path separators, blank path segments, or path segment edge spaces.',
  PaperTodoStringKeys.webDavIssueEndpointRequired: 'Enter a WebDAV URL.',
  PaperTodoStringKeys.webDavIssuePasswordInvalid:
      'Password cannot contain control characters.',
  PaperTodoStringKeys.webDavIssuePasswordRequired:
      'Enter a WebDAV password or app password.',
  PaperTodoStringKeys.webDavIssuePassphraseRequired:
      'Enter a sync encryption passphrase.',
  PaperTodoStringKeys.webDavIssueProviderRootPathTooLong:
      'Jianguoyun requires the first remote-folder segment to be at most {0} characters.',
  PaperTodoStringKeys.webDavIssueRootPathInvalid:
      'Use a remote folder without parent-directory segments, invalid percent escapes, control characters, or blank path segments.',
  PaperTodoStringKeys.webDavIssueSummary:
      'Complete the WebDAV URL, username, password, remote folder, and sync encryption passphrase.',
  PaperTodoStringKeys.webDavIssueUsernameInvalid:
      'Username cannot contain colons or control characters.',
  PaperTodoStringKeys.webDavIssueUsernameRequired: 'Enter a WebDAV username.',
  PaperTodoStringKeys.webDavProvider: 'WebDAV provider',
  PaperTodoStringKeys.webDavSync: 'WebDAV sync',
  PaperTodoStringKeys.enableWebDavSync: 'Enable WebDAV sync',
  PaperTodoStringKeys.webDavUrl: 'WebDAV URL',
  PaperTodoStringKeys.xl: 'XL',
  PaperTodoStringKeys.yaHei: 'YaHei',
  PaperTodoStringKeys.yy: '26',
  PaperTodoStringKeys.yyyy: '2026',
  PaperTodoStringKeys.zoom: 'Zoom',
};

const _zhStrings = {
  PaperTodoStringKeys.appTitle: 'RePaperTodo',
  PaperTodoStringKeys.actionAddColumn: '添加列',
  PaperTodoStringKeys.actionAddCanvasBlock: '添加画布块',
  PaperTodoStringKeys.actionAddCodeBlock: '添加代码块',
  PaperTodoStringKeys.actionAddItem: '添加事项',
  PaperTodoStringKeys.actionAddTextBlock: '添加文本块',
  PaperTodoStringKeys.actionBackToBoard: '返回面板',
  PaperTodoStringKeys.actionCancel: '取消',
  PaperTodoStringKeys.actionConfirm: '确认',
  PaperTodoStringKeys.actionChangeDueDate: '修改时间节点',
  PaperTodoStringKeys.actionChangeReminder: '修改提醒间隔',
  PaperTodoStringKeys.actionClear: '清除',
  PaperTodoStringKeys.actionClose: '关闭',
  PaperTodoStringKeys.actionClearCompleted: '清理已完成',
  PaperTodoStringKeys.actionClearCompletedItems: '清除已完成事项',
  PaperTodoStringKeys.actionClearDueDate: '清除时间节点',
  PaperTodoStringKeys.actionClearReminder: '使用全局提醒间隔',
  PaperTodoStringKeys.actionClearReminderInterval: '清除提醒间隔',
  PaperTodoStringKeys.actionCollapseAll: '全部收起',
  PaperTodoStringKeys.actionCollapseAllPapers: '收起全部纸片',
  PaperTodoStringKeys.actionCollapsePaper: '收起纸片',
  PaperTodoStringKeys.actionCollapseToCapsule: '折叠为胶囊',
  PaperTodoStringKeys.actionCopy: '复制',
  PaperTodoStringKeys.actionDelete: '删除',
  PaperTodoStringKeys.actionDeleteColumn: '删除第 {0} 列',
  PaperTodoStringKeys.actionDeleteItem: '删除这一项',
  PaperTodoStringKeys.actionDeletePaper: '删除纸片',
  PaperTodoStringKeys.actionDisableAlwaysOnTop: '取消保持置顶',
  PaperTodoStringKeys.actionDragToLinkNoteToTodo: '拖动以关联笔记到待办',
  PaperTodoStringKeys.actionDragToReorder: '拖动以排序',
  PaperTodoStringKeys.actionEditLinkedScript: '编辑关联脚本',
  PaperTodoStringKeys.actionEditScriptCapsule: '编辑脚本胶囊',
  PaperTodoStringKeys.actionEditTitle: '点击编辑标题',
  PaperTodoStringKeys.actionEqualWidths: '等宽列',
  PaperTodoStringKeys.actionExpandAll: '全部展开',
  PaperTodoStringKeys.actionExpandAllPapers: '展开全部纸片',
  PaperTodoStringKeys.actionExpandPaper: '展开纸片',
  PaperTodoStringKeys.actionHidePaper: '隐藏纸片',
  PaperTodoStringKeys.actionHideThisPaper: '隐藏这张纸',
  PaperTodoStringKeys.actionHideCompact: '隐藏',
  PaperTodoStringKeys.actionInsertBeforeColumn: '在第 {0} 列前插入',
  PaperTodoStringKeys.menuDeleteTodoColumn: '删除当前列',
  PaperTodoStringKeys.menuDecreaseTodoColumns: '减少当前待办列数',
  PaperTodoStringKeys.menuIncreaseTodoColumns: '增加当前待办列数',
  PaperTodoStringKeys.menuInsertTodoColumnBefore: '在当前列前插入列',
  PaperTodoStringKeys.menuOpenLinkedNote: '打开关联笔记：{0}',
  PaperTodoStringKeys.menuEditLinkedScriptCapsule: '编辑关联脚本：{0}',
  PaperTodoStringKeys.actionKeepOnTop: '保持置顶',
  PaperTodoStringKeys.actionLinkNote: '关联笔记',
  PaperTodoStringKeys.actionLinkPaper: '关联 {0}',
  PaperTodoStringKeys.actionMore: '更多操作',
  PaperTodoStringKeys.actionMoveItemDown: '下移事项',
  PaperTodoStringKeys.actionMoveItemUp: '上移事项',
  PaperTodoStringKeys.actionMovePaperWindow: '拖动以移动纸张',
  PaperTodoStringKeys.actionResizePaperWindow: '拖动边缘以调整纸张大小',
  PaperTodoStringKeys.actionNewNote: '新建笔记',
  PaperTodoStringKeys.actionNewNotePaper: '新建笔记纸片',
  PaperTodoStringKeys.actionNewNotePaperCompact: '＋ 笔记纸',
  PaperTodoStringKeys.actionNewTodo: '新建待办',
  PaperTodoStringKeys.actionNewTodoPaper: '新建待办纸片',
  PaperTodoStringKeys.actionNewTodoPaperCompact: '＋ 待办纸',
  PaperTodoStringKeys.actionOpen: '打开',
  PaperTodoStringKeys.actionOpenCurrentPaperSurface: '打开当前纸片窗口',
  PaperTodoStringKeys.actionOpenLinkedNote: '打开关联笔记',
  PaperTodoStringKeys.actionOpenMarkdownExternally: '用外部程序打开 Markdown',
  PaperTodoStringKeys.actionOpenMarkdownInDefaultEditor: '用默认 {0} 编辑器打开',
  PaperTodoStringKeys.actionOpenPaperSurface: '打开纸片窗口',
  PaperTodoStringKeys.actionOpenSurface: '打开窗口',
  PaperTodoStringKeys.actionPaperActions: '纸片操作',
  PaperTodoStringKeys.actionPaperTextZoom: '纸片文字缩放',
  PaperTodoStringKeys.actionPaste: '粘贴',
  PaperTodoStringKeys.actionPinToDesktop: '固定到桌面',
  PaperTodoStringKeys.actionRecovery: '恢复',
  PaperTodoStringKeys.actionRecoverySnapshots: '恢复快照',
  PaperTodoStringKeys.actionRedoTodoChange: '重做待办更改',
  PaperTodoStringKeys.actionRemoveLastColumn: '移除最后一列',
  PaperTodoStringKeys.actionRetry: '重试',
  PaperTodoStringKeys.actionRestoreWindow: '恢复窗口',
  PaperTodoStringKeys.actionRestore: '恢复',
  PaperTodoStringKeys.actionResetTextZoom: '点击恢复为 100%',
  PaperTodoStringKeys.actionRunPaper: '运行 {0}',
  PaperTodoStringKeys.actionRunLinkedScriptCapsule: '运行关联脚本胶囊',
  PaperTodoStringKeys.actionRunScriptCapsule: '运行脚本胶囊',
  PaperTodoStringKeys.actionSave: '保存',
  PaperTodoStringKeys.actionSaveWindowBounds: '保存窗口边界',
  PaperTodoStringKeys.actionSelectAll: '全选',
  PaperTodoStringKeys.actionSetDueDate: '设置时间节点',
  PaperTodoStringKeys.actionSetReminder: '设置提醒间隔',
  PaperTodoStringKeys.actionSetReminderInterval: '设置提醒间隔',
  PaperTodoStringKeys.actionSettings: '设置',
  PaperTodoStringKeys.actionShowHidden: '显示隐藏',
  PaperTodoStringKeys.actionShowHiddenPapers: '显示隐藏纸片',
  PaperTodoStringKeys.actionSyncNow: '立即同步',
  PaperTodoStringKeys.actionTodoColumns: '待办列',
  PaperTodoStringKeys.actionTodoItemActions: '待办事项操作',
  PaperTodoStringKeys.actionUndo: '撤销',
  PaperTodoStringKeys.actionUndoTodoChange: '撤销待办更改',
  PaperTodoStringKeys.actionUnlinkNote: '取消关联笔记',
  PaperTodoStringKeys.actionUnpinFromDesktop: '从桌面取消固定',
  PaperTodoStringKeys.actionWideFirstColumn: '加宽第一列',
  PaperTodoStringKeys.allowLongLinkedNoteTitles: '关联笔记显示长标题',
  PaperTodoStringKeys.allDue: '每个',
  PaperTodoStringKeys.animations: '启用动画效果',
  PaperTodoStringKeys.appearance: '显示',
  PaperTodoStringKeys.avoidFullscreen: '避让',
  PaperTodoStringKeys.basic: '基础',
  PaperTodoStringKeys.capsuleMode: '胶囊模式',
  PaperTodoStringKeys.canvasBlockActions: '画布块操作',
  PaperTodoStringKeys.canvasBlockGeometry: '画布块几何参数',
  PaperTodoStringKeys.canvasBlockTypeBlock: '块',
  PaperTodoStringKeys.canvasBlockTypeCode: '代码',
  PaperTodoStringKeys.canvasBlockTypeCodeLabel: '代码',
  PaperTodoStringKeys.canvasBlockTypeText: '文本',
  PaperTodoStringKeys.canvasBlockTypeTextLabel: '文本',
  PaperTodoStringKeys.canvasBringForward: '上移一层',
  PaperTodoStringKeys.canvasBringToFront: '置于顶层',
  PaperTodoStringKeys.canvasDefaultText: '画布文本 {0}',
  PaperTodoStringKeys.canvasDeleteBlock: '删除画布块',
  PaperTodoStringKeys.canvasDragBlock: '拖动画布块',
  PaperTodoStringKeys.canvasDuplicateBlock: '复制画布块',
  PaperTodoStringKeys.canvasEditGeometry: '编辑画布几何参数',
  PaperTodoStringKeys.canvasEnterValidNumbers: '请为每个字段输入有效数字。',
  PaperTodoStringKeys.canvasFieldHeight: '高度',
  PaperTodoStringKeys.canvasFieldLayer: '层级',
  PaperTodoStringKeys.canvasFieldWidth: '宽度',
  PaperTodoStringKeys.canvasLayer: '层级 {0}',
  PaperTodoStringKeys.canvasLayerActions: '画布层级操作',
  PaperTodoStringKeys.canvasResizeBlock: '调整画布块大小',
  PaperTodoStringKeys.canvasSendBackward: '下移一层',
  PaperTodoStringKeys.canvasSendToBack: '置于底层',
  PaperTodoStringKeys.canvasTopLayer: '顶层 {0}',
  PaperTodoStringKeys.collapseAllActive: '默认收起全部',
  PaperTodoStringKeys.collapseAllControl: '显示主胶囊',
  PaperTodoStringKeys.collapseExpandedDeepCapsuleOnClick: '再次点击边缘胶囊收回纸片',
  PaperTodoStringKeys.colorForest: '森林',
  PaperTodoStringKeys.colorInk: '墨色',
  PaperTodoStringKeys.colorRose: '玫瑰',
  PaperTodoStringKeys.colorScheme: '颜色方案',
  PaperTodoStringKeys.colorWarm: '暖纸',
  PaperTodoStringKeys.columnLabel: '第 {0} 列',
  PaperTodoStringKeys.custom: '自定义',
  PaperTodoStringKeys.customFontFamily: '自定义字体族',
  PaperTodoStringKeys.customThemeColor: '全局主题颜色',
  PaperTodoStringKeys.themeColorDefault: '跟随默认调色板',
  PaperTodoStringKeys.themeColorPick: '选择颜色',
  PaperTodoStringKeys.themeColorClear: '默认颜色',
  PaperTodoStringKeys.deepCapsuleMode: '胶囊贴边模式',
  PaperTodoStringKeys.deepCapsuleMonitor: '边缘胶囊显示器',
  PaperTodoStringKeys.deepCapsuleSide: '边缘胶囊侧边',
  PaperTodoStringKeys.deepCapsuleTopMargin: '边缘胶囊顶部边距',
  PaperTodoStringKeys.defaultFont: '默认',
  PaperTodoStringKeys.uiFontDefault: '语言默认',
  PaperTodoStringKeys.dengXian: '等线',
  PaperTodoStringKeys.dialogDeletePaper: '删除纸片？',
  PaperTodoStringKeys.dialogDeletePaperBody: '删除后将永久移除，不能从托盘恢复。',
  PaperTodoStringKeys.dialogDueDate: '设置时间节点',
  PaperTodoStringKeys.dialogDueDateMessage: '选择这个待办事项的本地日期和时间。',
  PaperTodoStringKeys.dialogDueDateConfirm: '确定',
  PaperTodoStringKeys.dialogRestoreSnapshot: '恢复快照？',
  PaperTodoStringKeys.dialogSyncSettings: '同步设置',
  PaperTodoStringKeys.settingsTodoAndNotes: '待办/笔记',
  PaperTodoStringKeys.settingsCapsules: '胶囊',
  PaperTodoStringKeys.settingsGeneralAdvanced: '通用/高级',
  PaperTodoStringKeys.settingsLineSpacingReset: '默认',
  PaperTodoStringKeys.settingsSectionCapsule: '胶囊',
  PaperTodoStringKeys.settingsSectionDisplay: '显示',
  PaperTodoStringKeys.settingsSectionExternalOpen: '外部打开',
  PaperTodoStringKeys.settingsSectionGeneral: '通用',
  PaperTodoStringKeys.settingsSectionScriptCapsule: '脚本胶囊',
  PaperTodoStringKeys.settingsSectionTodoAndNotes: '待办与笔记',
  PaperTodoStringKeys.settingsSectionTopBarButtons: '顶栏按钮',
  PaperTodoStringKeys.actionBrowse: '浏览',
  PaperTodoStringKeys.dataDirectory: '数据保存目录',
  PaperTodoStringKeys.dataDirectoryHelp: '用于保存 data.json、备份和恢复文件。修改目录时会复制当前数据。',
  PaperTodoStringKeys.dueLabel: '到期 {0}',
  PaperTodoStringKeys.dueTomorrow: '明天 {0}',
  PaperTodoStringKeys.dueYearDisplay: '时间节点年份显示',
  PaperTodoStringKeys.enhanced: '增强',
  PaperTodoStringKeys.externalMarkdownOpenFailed: '外部 Markdown 打开失败：{0}',
  PaperTodoStringKeys.externalMarkdownExtension: '外部打开文件类型',
  PaperTodoStringKeys.externalMarkdownExtensionInvalid:
      '请使用 .md、.txt 或 .todo.md 这类扩展名，不要包含文件名保留字符、控制字符，也不要以点或空格结尾。',
  PaperTodoStringKeys.fontPreset: '字体预设',
  PaperTodoStringKeys.fullscreenTopmostMode: '全屏窗口处理',
  PaperTodoStringKeys.generic: '通用',
  PaperTodoStringKeys.hideCoveredDeepCapsules: '有窗口遮挡时隐藏贴边胶囊',
  PaperTodoStringKeys.hideFullscreenDeepCapsules: '全屏应用时隐藏边缘胶囊',
  PaperTodoStringKeys.hideFromTaskSwitcher: '从窗口切换中隐藏纸片',
  PaperTodoStringKeys.hideLinkedNoteCapsules: '关联笔记不显示为胶囊',
  PaperTodoStringKeys.hidePassphrase: '隐藏密钥短语',
  PaperTodoStringKeys.hidePassword: '隐藏密码',
  PaperTodoStringKeys.hideScriptRunWindow: '隐藏脚本窗口',
  PaperTodoStringKeys.hour: '小时',
  PaperTodoStringKeys.hours: '小时',
  PaperTodoStringKeys.interval: '间隔',
  PaperTodoStringKeys.intervalMinutes: '同步间隔分钟',
  PaperTodoStringKeys.large: '大',
  PaperTodoStringKeys.left: '左侧',
  PaperTodoStringKeys.labelNote: '笔记',
  PaperTodoStringKeys.labelNoteTitle: '笔记 {0}',
  PaperTodoStringKeys.labelScript: '脚本',
  PaperTodoStringKeys.markdownActionBold: '加粗',
  PaperTodoStringKeys.markdownActionBoldShortcut: '加粗 (Ctrl+B)',
  PaperTodoStringKeys.markdownActionCodeBlock: '代码块',
  PaperTodoStringKeys.markdownActionHeading: '标题',
  PaperTodoStringKeys.markdownActionInsertLink: '插入链接',
  PaperTodoStringKeys.markdownActionInsertLinkShortcut: '插入链接 (Ctrl+K)',
  PaperTodoStringKeys.markdownActionItalic: '斜体',
  PaperTodoStringKeys.markdownActionItalicShortcut: '斜体 (Ctrl+I)',
  PaperTodoStringKeys.markdownActionList: '列表',
  PaperTodoStringKeys.markdownActionMore: '更多 Markdown 操作',
  PaperTodoStringKeys.markdownActionQuote: '引用',
  PaperTodoStringKeys.markdownActionStrikethrough: '删除线',
  PaperTodoStringKeys.markdownMode: 'Markdown 显示',
  PaperTodoStringKeys.markdownOff: '关闭',
  PaperTodoStringKeys.menuCanvas: '画布',
  PaperTodoStringKeys.menuDesktopPin: '桌面钉住',
  PaperTodoStringKeys.menuFormat: '格式',
  PaperTodoStringKeys.menuNew: '新建',
  PaperTodoStringKeys.menuText: '文本',
  PaperTodoStringKeys.menuTodo: '待办',
  PaperTodoStringKeys.menuTodoItem: '事项',
  PaperTodoStringKeys.maxTitleLength: '标题字数上限',
  PaperTodoStringKeys.moveCompletedTodosToBottom: '完成后将待办移到未完成项下方',
  PaperTodoStringKeys.medium: '中',
  PaperTodoStringKeys.minute: '分钟',
  PaperTodoStringKeys.minutes: '分钟',
  PaperTodoStringKeys.mono: '等宽',
  PaperTodoStringKeys.nearest: '单个',
  PaperTodoStringKeys.noYear: '不显示',
  PaperTodoStringKeys.noteEmptyPreview: '_暂无笔记内容。_',
  PaperTodoStringKeys.noteEditorHint: '写点笔记...',
  PaperTodoStringKeys.noteSpacing: '笔记行距',
  PaperTodoStringKeys.noteViewEdit: '编辑',
  PaperTodoStringKeys.noteViewPreview: '预览',
  PaperTodoStringKeys.noteViewSplit: '分栏',
  PaperTodoStringKeys.openedMarkdownFile: '已打开 Markdown 文件：{0}',
  PaperTodoStringKeys.openLinkFailed: '打开链接失败：{0}',
  PaperTodoStringKeys.openLinkUnsupported: '打开链接失败：不支持的链接目标。',
  PaperTodoStringKeys.paperDeleted: '{0} 已删除。',
  PaperTodoStringKeys.paperLimitMessage: '纸片已达到 100 张上限。\n请删除不再需要的纸片后再新建。',
  PaperTodoStringKeys.paperLimitTitle: '纸片数量已满',
  PaperTodoStringKeys.passphraseHelper: '用于 Windows 与 Android 加密同步。',
  PaperTodoStringKeys.password: '密码',
  PaperTodoStringKeys.persistentPowerShellProcess: '常驻 PowerShell 进程',
  PaperTodoStringKeys.platformFileNotFound: '文件不存在。',
  PaperTodoStringKeys.platformFileShareFailed: '无法安全分享该文件。',
  PaperTodoStringKeys.platformInvalidPath: '文件路径无效，或不在 RePaperTodo 可分享目录内。',
  PaperTodoStringKeys.platformInvalidUri: '链接无效或不受支持。',
  PaperTodoStringKeys.platformOpenExternalFileFailed: '无法打开外部文件。',
  PaperTodoStringKeys.platformOpenUriFailed: '无法打开链接。',
  PaperTodoStringKeys.platformSettingFullscreenTopmostMode: '全屏/置顶模式',
  PaperTodoStringKeys.platformSettingGlobalHotkeys: '全局快捷键',
  PaperTodoStringKeys.platformSettingPaperSurfaces: '纸片窗口',
  PaperTodoStringKeys.platformSettingScriptCapsuleProcess: '脚本胶囊进程',
  PaperTodoStringKeys.platformSettingStartupAtLogin: '开机启动',
  PaperTodoStringKeys.platformSettingWindowSwitcherVisibility: '任务切换器可见性',
  PaperTodoStringKeys.platformSettingsFailed: '平台设置失败：{0}',
  PaperTodoStringKeys.pinnedNoteHotkey: '呼出钉住笔记纸快捷键',
  PaperTodoStringKeys.pinnedTodoHotkey: '呼出钉住待办纸快捷键',
  PaperTodoStringKeys.preferPowerShell7: '优先使用 PowerShell 7',
  PaperTodoStringKeys.relativeDueDates: '显示相对待办时间',
  PaperTodoStringKeys.relativeDueDayUnit: '{0}天',
  PaperTodoStringKeys.relativeDueFuture: '{0}后',
  PaperTodoStringKeys.relativeDueHourUnit: '{0}小时',
  PaperTodoStringKeys.relativeDueMinuteUnit: '{0}分',
  PaperTodoStringKeys.relativeDueOverdue: '已过期{0}',
  PaperTodoStringKeys.recoverySnapshotFallback: '快照',
  PaperTodoStringKeys.recoverySnapshotLoadFailed: '无法加载快照：{0}',
  PaperTodoStringKeys.recoverySnapshotModified: '修改于 {0}',
  PaperTodoStringKeys.recoverySnapshotsEmpty: '未找到恢复快照。',
  PaperTodoStringKeys.reminderDisplaySeconds: '气泡悬浮时长（秒）',
  PaperTodoStringKeys.reminderEveryHours: '每 {0} 小时',
  PaperTodoStringKeys.reminderEveryMinutes: '每 {0} 分钟',
  PaperTodoStringKeys.reminderInterval: '提醒间隔',
  PaperTodoStringKeys.reminderIntervalGlobal: '全局',
  PaperTodoStringKeys.reminderIntervalMessage:
      '为这个待办设置单独的提醒间隔。开启间隔气泡提醒时，它会覆盖应用设置。',
  PaperTodoStringKeys.reminderScope: '提醒对象',
  PaperTodoStringKeys.reminderUnit: '间隔单位',
  PaperTodoStringKeys.remoteFolder: '远程文件夹',
  PaperTodoStringKeys.requestTimeoutSeconds: '请求超时秒数',
  PaperTodoStringKeys.right: '右侧',
  PaperTodoStringKeys.runLinkedScriptCapsulesOnClick: '关联脚本直接运行',
  PaperTodoStringKeys.scriptCapsuleFailed: '脚本胶囊运行失败：{0}',
  PaperTodoStringKeys.serif: '衬线',
  PaperTodoStringKeys.settingsSaveFailed: '设置保存失败：{0}',
  PaperTodoStringKeys.showDeepCapsuleWhileExpanded: '展开时保留边缘胶囊',
  PaperTodoStringKeys.showLinkedNoteName: '显示关联笔记标题',
  PaperTodoStringKeys.showPassphrase: '显示密钥短语',
  PaperTodoStringKeys.showPassword: '显示密码',
  PaperTodoStringKeys.small: '小',
  PaperTodoStringKeys.startAtLogin: '开机自启动',
  PaperTodoStringKeys.stayOnTop: '保持置顶',
  PaperTodoStringKeys.systemFont: '系统字体',
  PaperTodoStringKeys.trayCollapsed: '已折叠',
  PaperTodoStringKeys.trayDeleteConfirmMessage: '删除“{0}”？',
  PaperTodoStringKeys.trayDeleteConfirmTitle: '删除纸片？',
  PaperTodoStringKeys.trayDeletePaper: '删除纸片...',
  PaperTodoStringKeys.trayInlineConfirmDelete: '⚠ 删除',
  PaperTodoStringKeys.trayInlineConfirmAction: '确认',
  PaperTodoStringKeys.trayDesktop: '桌面',
  PaperTodoStringKeys.trayExit: '退出',
  PaperTodoStringKeys.trayHidden: '已隐藏',
  PaperTodoStringKeys.trayHideAll: '隐藏全部纸片',
  PaperTodoStringKeys.trayNewNote: '＋ 新建笔记纸',
  PaperTodoStringKeys.trayNewTodo: '＋ 新建待办纸',
  PaperTodoStringKeys.trayNotePaper: '笔记',
  PaperTodoStringKeys.trayPapers: '纸片',
  PaperTodoStringKeys.trayScriptPaper: '脚本',
  PaperTodoStringKeys.traySettings: '设置',
  PaperTodoStringKeys.trayShowAll: '显示全部纸片',
  PaperTodoStringKeys.trayTodoPaper: '待办',
  PaperTodoStringKeys.trayToggleAll: '切换全部纸片',
  PaperTodoStringKeys.trayTopmost: '置顶',
  PaperTodoStringKeys.syncCompleteConfiguration: '请先完成 WebDAV 同步设置和同步加密密钥短语。',
  PaperTodoStringKeys.syncConflict: '同步期间远端数据已变化，请先拉取后再上传。',
  PaperTodoStringKeys.syncConflictSnapshotPreserved:
      '同步期间远端数据已变化。本地快照已保存在 {0}。',
  PaperTodoStringKeys.syncDisabled: '同步已关闭。',
  PaperTodoStringKeys.syncDownloaded: '已下载远端数据。',
  PaperTodoStringKeys.syncDownloadedLegacyPlainMigrated:
      '已从旧版明文 WebDAV 数据下载远端数据，并迁移为加密载荷。',
  PaperTodoStringKeys.syncDownloadedLegacyPlainNextUpload:
      '已从旧版明文 WebDAV 数据下载远端数据。下次成功上传时会写入加密载荷。',
  PaperTodoStringKeys.syncDownloadedLegacyPlainRetry:
      '已从旧版明文 WebDAV 数据下载远端数据。自动加密迁移未完成，请再次同步重试。',
  PaperTodoStringKeys.syncEncryptionPassphrase: '同步加密密钥短语',
  PaperTodoStringKeys.webDavAppPassword: 'WebDAV 应用密码',
  PaperTodoStringKeys.jianguoyunAppPasswordHelper:
      '坚果云必须使用“第三方应用管理”生成的应用密码；账户登录密码会返回 HTTP 401。',
  PaperTodoStringKeys.jianguoyunAuthenticationFailed:
      '坚果云拒绝了认证。请填写邮箱账号，并在此处填写“第三方应用管理”生成的应用密码；不要填写账户登录密码，也不要与同步加密密钥短语混用。',
  PaperTodoStringKeys.year: '年',
  PaperTodoStringKeys.month: '月',
  PaperTodoStringKeys.day: '日',
  PaperTodoStringKeys.syncFailed: '同步失败：{0}',
  PaperTodoStringKeys.syncFoundLegacyOperationLogs:
      '发现 {0} 个旧版明文 WebDAV {1}；远端 ETag 可用后再次同步以重试加密迁移。',
  PaperTodoStringKeys.syncMergedRemoteChanges: '已合并 {0} 个远端{1}。',
  PaperTodoStringKeys.syncMigratedLegacyOperationLogs:
      '已将 {0} 个旧版 WebDAV {1} 迁移为加密载荷。',
  PaperTodoStringKeys.syncMigratedLegacyOperationLogsPartial:
      '已将 {1} 个旧版 WebDAV {2} 中的 {0} 个迁移为加密载荷；请再次同步重试剩余部分。',
  PaperTodoStringKeys.syncOnStart: '启动时同步',
  PaperTodoStringKeys.syncOperationLog: '操作日志',
  PaperTodoStringKeys.syncOperationLogs: '操作日志',
  PaperTodoStringKeys.syncPayloadUnreadable: '无法解密远端同步数据，请检查同步加密密钥短语。',
  PaperTodoStringKeys.syncRemoteChange: '变更',
  PaperTodoStringKeys.syncRemoteChanges: '变更',
  PaperTodoStringKeys.syncRemoteSnapshotEmpty: '远端快照为空。',
  PaperTodoStringKeys.syncRestoreSnapshotFailed: '恢复失败：{0}',
  PaperTodoStringKeys.syncSnapshotRestored: '快照已恢复。',
  PaperTodoStringKeys.syncSnapshotRestoredLegacyPlainNextUpload:
      '已从旧版明文 WebDAV 数据恢复快照。下次成功上传时会写入加密载荷。',
  PaperTodoStringKeys.syncUploaded: '已上传本地数据。',
  PaperTodoStringKeys.theme: '主题模式',
  PaperTodoStringKeys.themeDark: '深色',
  PaperTodoStringKeys.themeLight: '浅色',
  PaperTodoStringKeys.themeSystem: '跟随系统',
  PaperTodoStringKeys.todoNoteLinks: '启用待办关联笔记',
  PaperTodoStringKeys.todoReminders: '使用间隔气泡提醒',
  PaperTodoStringKeys.todoSpacing: '待办行距',
  PaperTodoStringKeys.todoReminderBubbleMessage: '{0}\n{1}\n{2}',
  PaperTodoStringKeys.todoReminderBubbleOverdue: '过期 {0}',
  PaperTodoStringKeys.todoReminderBubbleRemaining: '还有 {0}',
  PaperTodoStringKeys.todoReminderBubbleTitle: '待办快到时间',
  PaperTodoStringKeys.todoReminderCountdownDay: '{0}天',
  PaperTodoStringKeys.todoReminderCountdownHour: '{0}小时',
  PaperTodoStringKeys.todoReminderCountdownMinute: '{0}分',
  PaperTodoStringKeys.todoReminderCountdownSecond: '{0}秒',
  PaperTodoStringKeys.todoReminderMultiple: '提醒：{0} 个待办事项已到期。',
  PaperTodoStringKeys.todoReminderSingle: '提醒：{0} - {1}',
  PaperTodoStringKeys.todoNewItemHint: '新事项',
  PaperTodoStringKeys.todoItemDeleted: '{0} 已删除。',
  PaperTodoStringKeys.todoItemFallback: '待办事项',
  PaperTodoStringKeys.todoVisualSize: '待办大小',
  PaperTodoStringKeys.tipAllowLongLinkedNoteTitles:
      '关闭时保持紧凑显示；开启后关联笔记标题会按内容扩展，单行最多约 5 个全角字符，多行最多约 10 个。',
  PaperTodoStringKeys.tipCapsuleCollapseAll: '在胶囊队列顶部显示主胶囊，用于一键收起或展开当前队列。',
  PaperTodoStringKeys.tipCapsuleMode: '允许纸片折叠为小胶囊，减少桌面占用；胶囊贴边等功能需要先开启此项。',
  PaperTodoStringKeys.tipCollapseExpandedDeepCapsuleOnClick:
      '纸片已从边缘胶囊展开时，再次点击同一胶囊会把纸片收回。',
  PaperTodoStringKeys.tipCustomThemeColor:
      '点击色块打开全色域颜色选择器。选中的颜色会生成整套应用调色板，而不只是改变设置项本身。',
  PaperTodoStringKeys.tipDeepCapsuleMode: '胶囊会自动停靠到屏幕边缘并排列成队列，鼠标悬停时滑出。',
  PaperTodoStringKeys.tipEnableAnimations: '为常见操作启用过渡动画；关闭后响应更直接。',
  PaperTodoStringKeys.tipEnableTodoNoteLinks:
      '允许把笔记拖到待办项上建立关联，之后可从待办项直接打开对应笔记。',
  PaperTodoStringKeys.tipEnableToolTips: '指针停在按钮和可操作区域上时显示简短说明；设置页说明图标始终可用。',
  PaperTodoStringKeys.tipExternalExtension: '选择交给外部程序打开时使用的文件类型，例如 .md 或 .txt。',
  PaperTodoStringKeys.tipExternalOpenButton:
      '在顶栏显示外部打开按钮，将当前笔记写入临时文件并交给系统默认程序打开。',
  PaperTodoStringKeys.tipFullscreenTopmostMode:
      '检测到视频、游戏等全屏窗口时，纸片和边缘胶囊可临时避让；选择保持置顶则始终可见。',
  PaperTodoStringKeys.tipHideDeepCapsulesWhenCovered:
      '外部窗口与贴边胶囊停靠区域重叠时，胶囊会立即隐藏；区域空出后自动恢复。',
  PaperTodoStringKeys.tipHideLinkedNotesFromCapsules:
      '已关联到待办项的笔记不再出现在胶囊列表中，避免重复入口。',
  PaperTodoStringKeys.tipHidePapersFromWindowSwitcher:
      '开启后，展开的纸片会从 Alt+Tab 和任务视图中隐藏；仍可通过托盘、桌面纸片和胶囊访问。',
  PaperTodoStringKeys.tipHideScriptRunWindow:
      '隐藏脚本运行窗口。普通 !p / !power 会等待脚本结束并捕获错误；!pf / !powerf 只投递到常驻进程。',
  PaperTodoStringKeys.tipMarkdownRender: '基础模式只做轻量高亮；增强模式进一步美化标题、列表和强调。',
  PaperTodoStringKeys.tipMaxTitleLength: '纸片标题和胶囊显示的最大字数。',
  PaperTodoStringKeys.tipMoveCompletedTodosToBottom:
      '开启后，完成待办会平滑地移到所有未完成项之后；重新打开时回到未完成分组。',
  PaperTodoStringKeys.tipNewNoteButton: '在纸片顶栏显示新建笔记按钮。',
  PaperTodoStringKeys.tipNewTodoButton: '在纸片顶栏显示新建待办按钮。',
  PaperTodoStringKeys.tipNoteLineSpacing: '输入笔记正文的行距倍数，默认 1，范围 0.8 到 5。',
  PaperTodoStringKeys.tipPersistentPowerShellProcess:
      '!pf / !powerf 会复用常驻进程，启动更快，但脚本间的变量和状态可能保留。关闭后结束该进程。',
  PaperTodoStringKeys.tipPinnedNoteHotKey:
      '在输入框中按下组合键，用于把钉在桌面底层的笔记纸呼出到前面；按 Esc、Backspace 或 Delete 可清空。',
  PaperTodoStringKeys.tipPinnedTodoHotKey:
      '在输入框中按下组合键，用于把钉在桌面底层的待办纸呼出到前面；按 Esc、Backspace 或 Delete 可清空。',
  PaperTodoStringKeys.tipPreferPowerShell7:
      '优先使用 PowerShell 7（pwsh.exe）；找不到时回退到 Windows PowerShell。脚本中也可用 !pwsh 或 !ps5 指定。',
  PaperTodoStringKeys.tipRunLinkedScriptCapsulesOnClick:
      '关联入口指向脚本胶囊时，左键直接运行脚本，右键打开编辑。默认关闭以避免误触。',
  PaperTodoStringKeys.tipShowDeepCapsuleWhileExpanded:
      '从边缘胶囊打开纸片后，边缘仍保留对应入口；关闭后，打开期间暂时隐藏该入口。',
  PaperTodoStringKeys.tipShowLinkedNoteName: '在待办项后显示已关联笔记的标题。',
  PaperTodoStringKeys.tipShowTodoDueRelativeTime:
      '待办时间徽标显示距离到期还有多久，或已经过期多久，而不是固定日期时间。',
  PaperTodoStringKeys.tipStartup: '开机时自动启动 PaperTodo。',
  PaperTodoStringKeys.tipSystemFont:
      '从当前 Windows 已安装字体中选择一个字体；选择后会应用到界面、托盘、胶囊、待办和笔记正文。选择语言默认会清除手动系统字体，并使用应用默认字体规则。',
  PaperTodoStringKeys.tipThemeMode: '选择浅色、深色，或跟随 Windows 系统主题。',
  PaperTodoStringKeys.tipTodoDueYearDisplay: '选择待办时间节点是否显示年份，可显示为 26年 或 2026年。',
  PaperTodoStringKeys.tipTodoLineSpacing: '输入待办多行文本的行距倍数，默认 1，范围 0.8 到 5。',
  PaperTodoStringKeys.tipTodoReminderBubbleDuration:
      '提醒气泡自动关闭前保持显示的秒数；鼠标悬停在气泡上时会暂停计时。',
  PaperTodoStringKeys.tipTodoReminderInterval:
      '未完成待办进入所选间隔范围内或已经过期后，再次弹出气泡提醒的最短间隔。',
  PaperTodoStringKeys.tipTodoReminderIntervalUnit: '选择提醒间隔数值按分钟或小时计算。',
  PaperTodoStringKeys.tipTodoReminderScope: '单个只提醒当前最接近到期的待办；每个会提醒所有符合条件的待办。',
  PaperTodoStringKeys.tipTodoVisualSize: '调整待办项的文字、行高和间距。',
  PaperTodoStringKeys.tipUseTodoReminderInterval:
      '开启后按所选间隔重复弹出提醒气泡；关闭时保留原来的临期一次提醒。',
  PaperTodoStringKeys.tooltips: '显示悬停提示',
  PaperTodoStringKeys.tooltipsHelp: '仅隐藏普通操作提示。设置说明仍会保留。',
  PaperTodoStringKeys.topBarNewNote: '显示新建笔记按钮',
  PaperTodoStringKeys.topBarNewTodo: '显示新建待办按钮',
  PaperTodoStringKeys.topBarOpenSurface: '显示外部打开按钮',
  PaperTodoStringKeys.untitledPaper: '未命名',
  PaperTodoStringKeys.username: '用户名',
  PaperTodoStringKeys.webDavIssueEndpointInvalid:
      '请输入完整的 http:// 或 https:// WebDAV URL，且不能包含用户信息、查询、片段、反斜杠、控制字符、编码后的主机或路径分隔符、空路径段或路径段首尾空格。',
  PaperTodoStringKeys.webDavIssueEndpointRequired: '请输入 WebDAV URL。',
  PaperTodoStringKeys.webDavIssuePasswordInvalid: '密码不能包含控制字符。',
  PaperTodoStringKeys.webDavIssuePasswordRequired: '请输入 WebDAV 密码或应用密码。',
  PaperTodoStringKeys.webDavIssuePassphraseRequired: '请输入同步加密密钥短语。',
  PaperTodoStringKeys.webDavIssueProviderRootPathTooLong:
      '坚果云要求远程文件夹的第一段不超过 {0} 个字符。',
  PaperTodoStringKeys.webDavIssueRootPathInvalid:
      '远程文件夹不能包含上级目录段、非法百分号转义、控制字符或空路径段。',
  PaperTodoStringKeys.webDavIssueSummary:
      '请完整填写 WebDAV URL、用户名、密码、远程文件夹和同步加密密钥短语。',
  PaperTodoStringKeys.webDavIssueUsernameInvalid: '用户名不能包含冒号或控制字符。',
  PaperTodoStringKeys.webDavIssueUsernameRequired: '请输入 WebDAV 用户名。',
  PaperTodoStringKeys.webDavProvider: 'WebDAV 服务',
  PaperTodoStringKeys.webDavSync: 'WebDAV 同步',
  PaperTodoStringKeys.enableWebDavSync: '启用 WebDAV 同步',
  PaperTodoStringKeys.webDavUrl: 'WebDAV URL',
  PaperTodoStringKeys.xl: '特大',
  PaperTodoStringKeys.yaHei: '雅黑',
  PaperTodoStringKeys.yy: '26年',
  PaperTodoStringKeys.yyyy: '2026年',
  PaperTodoStringKeys.zoom: '缩放',
};
