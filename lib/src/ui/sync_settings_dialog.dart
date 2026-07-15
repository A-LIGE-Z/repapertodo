import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model/app_state.dart';
import '../core/model/paper_constants.dart';
import '../core/model/sync_settings.dart';
import '../core/model/webdav_presets.dart';
import '../platform/platform_services.dart';
import 'papertodo_strings.dart';

typedef InstalledFontFamilyLoader = Future<List<String>> Function();
typedef DataDirectoryPicker = Future<String?> Function(String currentPath);

class SyncSettingsDialogResult {
  const SyncSettingsDialogResult({
    required this.sync,
    required this.theme,
    required this.colorScheme,
    required this.customThemeColorHex,
    required this.markdownRenderMode,
    required this.todoVisualSize,
    required this.uiFontPreset,
    required this.systemFontFamilyName,
    required this.externalMarkdownExtension,
    required this.zoom,
    required this.maxTitleLength,
    required this.enableToolTips,
    required this.enableAnimations,
    required this.todoLineSpacing,
    required this.noteLineSpacing,
    required this.showTodoDueRelativeTime,
    required this.todoDueYearDisplayMode,
    required this.useTodoReminderInterval,
    required this.todoReminderIntervalValue,
    required this.todoReminderIntervalUnit,
    required this.todoReminderScope,
    required this.todoReminderBubbleDurationSeconds,
    required this.showTopBarNewTodoButton,
    required this.showTopBarNewNoteButton,
    required this.showTopBarExternalOpenButton,
    required this.useCapsuleMode,
    required this.useDeepCapsuleMode,
    required this.useCapsuleCollapseAll,
    required this.capsuleCollapseAllActive,
    required this.deepCapsuleSide,
    required this.deepCapsuleStartTopMargin,
    required this.deepCapsuleMonitorDeviceName,
    required this.showDeepCapsuleWhileExpanded,
    required this.collapseExpandedDeepCapsuleOnClick,
    required this.hideDeepCapsulesWhenCovered,
    required this.hideDeepCapsulesWhenFullscreen,
    required this.startAtLogin,
    required this.hideFromWindowSwitcher,
    required this.fullscreenTopmostMode,
    required this.pinnedTodoHotKey,
    required this.pinnedNoteHotKey,
    required this.runLinkedScriptCapsulesOnClick,
    required this.usePersistentPowerShellProcess,
    required this.preferPowerShell7,
    required this.hideScriptRunWindow,
    required this.enableTodoNoteLinks,
    required this.showLinkedNoteName,
    required this.allowLongLinkedNoteTitles,
    required this.hideLinkedNotesFromCapsules,
    required this.dataDirectoryPath,
  });

  final SyncSettings sync;
  final String theme;
  final String colorScheme;
  final String customThemeColorHex;
  final String markdownRenderMode;
  final String todoVisualSize;
  final String uiFontPreset;
  final String systemFontFamilyName;
  final String externalMarkdownExtension;
  final double zoom;
  final int maxTitleLength;
  final bool enableToolTips;
  final bool enableAnimations;
  final double todoLineSpacing;
  final double noteLineSpacing;
  final bool showTodoDueRelativeTime;
  final String todoDueYearDisplayMode;
  final bool useTodoReminderInterval;
  final int todoReminderIntervalValue;
  final String todoReminderIntervalUnit;
  final String todoReminderScope;
  final int todoReminderBubbleDurationSeconds;
  final bool showTopBarNewTodoButton;
  final bool showTopBarNewNoteButton;
  final bool showTopBarExternalOpenButton;
  final bool useCapsuleMode;
  final bool useDeepCapsuleMode;
  final bool useCapsuleCollapseAll;
  final bool capsuleCollapseAllActive;
  final String deepCapsuleSide;
  final double deepCapsuleStartTopMargin;
  final String deepCapsuleMonitorDeviceName;
  final bool showDeepCapsuleWhileExpanded;
  final bool collapseExpandedDeepCapsuleOnClick;
  final bool hideDeepCapsulesWhenCovered;
  final bool hideDeepCapsulesWhenFullscreen;
  final bool startAtLogin;
  final bool hideFromWindowSwitcher;
  final String fullscreenTopmostMode;
  final String pinnedTodoHotKey;
  final String pinnedNoteHotKey;
  final bool runLinkedScriptCapsulesOnClick;
  final bool usePersistentPowerShellProcess;
  final bool preferPowerShell7;
  final bool hideScriptRunWindow;
  final bool enableTodoNoteLinks;
  final bool showLinkedNoteName;
  final bool allowLongLinkedNoteTitles;
  final bool hideLinkedNotesFromCapsules;
  final String dataDirectoryPath;
}

Future<SyncSettingsDialogResult?> showSyncSettingsDialog({
  required BuildContext context,
  required SyncSettings initialSettings,
  required String initialTheme,
  required String initialColorScheme,
  required String initialCustomThemeColorHex,
  required String initialMarkdownRenderMode,
  required String initialTodoVisualSize,
  required String initialUiFontPreset,
  required String initialSystemFontFamilyName,
  required String initialExternalMarkdownExtension,
  required double initialZoom,
  required int initialMaxTitleLength,
  required bool initialEnableToolTips,
  required bool initialEnableAnimations,
  required double initialTodoLineSpacing,
  required double initialNoteLineSpacing,
  required bool initialShowTodoDueRelativeTime,
  required String initialTodoDueYearDisplayMode,
  required bool initialUseTodoReminderInterval,
  required int initialTodoReminderIntervalValue,
  required String initialTodoReminderIntervalUnit,
  required String initialTodoReminderScope,
  required int initialTodoReminderBubbleDurationSeconds,
  required bool initialShowTopBarNewTodoButton,
  required bool initialShowTopBarNewNoteButton,
  required bool initialShowTopBarExternalOpenButton,
  required bool initialUseCapsuleMode,
  required bool initialUseDeepCapsuleMode,
  required bool initialUseCapsuleCollapseAll,
  required bool initialCapsuleCollapseAllActive,
  required String initialDeepCapsuleSide,
  required double initialDeepCapsuleStartTopMargin,
  required String initialDeepCapsuleMonitorDeviceName,
  required bool initialShowDeepCapsuleWhileExpanded,
  required bool initialCollapseExpandedDeepCapsuleOnClick,
  required bool initialHideDeepCapsulesWhenCovered,
  required bool initialHideDeepCapsulesWhenFullscreen,
  required bool initialStartAtLogin,
  required bool supportsStartAtLogin,
  required bool supportsHideFromWindowSwitcher,
  required bool supportsFullscreenTopmostMode,
  required bool supportsGlobalHotkeys,
  required bool supportsScriptCapsules,
  required bool initialHideFromWindowSwitcher,
  required String initialFullscreenTopmostMode,
  required String initialPinnedTodoHotKey,
  required String initialPinnedNoteHotKey,
  required bool initialRunLinkedScriptCapsulesOnClick,
  required bool initialUsePersistentPowerShellProcess,
  required bool initialPreferPowerShell7,
  required bool initialHideScriptRunWindow,
  required bool initialEnableTodoNoteLinks,
  required bool initialShowLinkedNoteName,
  required bool initialAllowLongLinkedNoteTitles,
  required bool initialHideLinkedNotesFromCapsules,
  required String initialDataDirectoryPath,
  required bool supportsDataDirectorySelection,
  DataDirectoryPicker? selectDataDirectory,
  InstalledFontFamilyLoader? loadInstalledFontFamilies,
}) {
  return showDialog<SyncSettingsDialogResult>(
    context: context,
    builder: (context) => SyncSettingsDialog(
      initialSettings: initialSettings,
      initialTheme: initialTheme,
      initialColorScheme: initialColorScheme,
      initialCustomThemeColorHex: initialCustomThemeColorHex,
      initialMarkdownRenderMode: initialMarkdownRenderMode,
      initialTodoVisualSize: initialTodoVisualSize,
      initialUiFontPreset: initialUiFontPreset,
      initialSystemFontFamilyName: initialSystemFontFamilyName,
      initialExternalMarkdownExtension: initialExternalMarkdownExtension,
      initialZoom: initialZoom,
      initialMaxTitleLength: initialMaxTitleLength,
      initialEnableToolTips: initialEnableToolTips,
      initialEnableAnimations: initialEnableAnimations,
      initialTodoLineSpacing: initialTodoLineSpacing,
      initialNoteLineSpacing: initialNoteLineSpacing,
      initialShowTodoDueRelativeTime: initialShowTodoDueRelativeTime,
      initialTodoDueYearDisplayMode: initialTodoDueYearDisplayMode,
      initialUseTodoReminderInterval: initialUseTodoReminderInterval,
      initialTodoReminderIntervalValue: initialTodoReminderIntervalValue,
      initialTodoReminderIntervalUnit: initialTodoReminderIntervalUnit,
      initialTodoReminderScope: initialTodoReminderScope,
      initialTodoReminderBubbleDurationSeconds:
          initialTodoReminderBubbleDurationSeconds,
      initialShowTopBarNewTodoButton: initialShowTopBarNewTodoButton,
      initialShowTopBarNewNoteButton: initialShowTopBarNewNoteButton,
      initialShowTopBarExternalOpenButton: initialShowTopBarExternalOpenButton,
      initialUseCapsuleMode: initialUseCapsuleMode,
      initialUseDeepCapsuleMode: initialUseDeepCapsuleMode,
      initialUseCapsuleCollapseAll: initialUseCapsuleCollapseAll,
      initialCapsuleCollapseAllActive: initialCapsuleCollapseAllActive,
      initialDeepCapsuleSide: initialDeepCapsuleSide,
      initialDeepCapsuleStartTopMargin: initialDeepCapsuleStartTopMargin,
      initialDeepCapsuleMonitorDeviceName: initialDeepCapsuleMonitorDeviceName,
      initialShowDeepCapsuleWhileExpanded: initialShowDeepCapsuleWhileExpanded,
      initialCollapseExpandedDeepCapsuleOnClick:
          initialCollapseExpandedDeepCapsuleOnClick,
      initialHideDeepCapsulesWhenCovered: initialHideDeepCapsulesWhenCovered,
      initialHideDeepCapsulesWhenFullscreen:
          initialHideDeepCapsulesWhenFullscreen,
      initialStartAtLogin: initialStartAtLogin,
      supportsStartAtLogin: supportsStartAtLogin,
      supportsHideFromWindowSwitcher: supportsHideFromWindowSwitcher,
      supportsFullscreenTopmostMode: supportsFullscreenTopmostMode,
      supportsGlobalHotkeys: supportsGlobalHotkeys,
      supportsScriptCapsules: supportsScriptCapsules,
      initialHideFromWindowSwitcher: initialHideFromWindowSwitcher,
      initialFullscreenTopmostMode: initialFullscreenTopmostMode,
      initialPinnedTodoHotKey: initialPinnedTodoHotKey,
      initialPinnedNoteHotKey: initialPinnedNoteHotKey,
      initialRunLinkedScriptCapsulesOnClick:
          initialRunLinkedScriptCapsulesOnClick,
      initialUsePersistentPowerShellProcess:
          initialUsePersistentPowerShellProcess,
      initialPreferPowerShell7: initialPreferPowerShell7,
      initialHideScriptRunWindow: initialHideScriptRunWindow,
      initialEnableTodoNoteLinks: initialEnableTodoNoteLinks,
      initialShowLinkedNoteName: initialShowLinkedNoteName,
      initialAllowLongLinkedNoteTitles: initialAllowLongLinkedNoteTitles,
      initialHideLinkedNotesFromCapsules: initialHideLinkedNotesFromCapsules,
      initialDataDirectoryPath: initialDataDirectoryPath,
      supportsDataDirectorySelection: supportsDataDirectorySelection,
      selectDataDirectory: selectDataDirectory,
      loadInstalledFontFamilies: loadInstalledFontFamilies,
    ),
  );
}

class SyncSettingsDialog extends StatefulWidget {
  const SyncSettingsDialog({
    required this.initialSettings,
    required this.initialTheme,
    required this.initialColorScheme,
    required this.initialCustomThemeColorHex,
    required this.initialMarkdownRenderMode,
    required this.initialTodoVisualSize,
    required this.initialUiFontPreset,
    required this.initialSystemFontFamilyName,
    required this.initialExternalMarkdownExtension,
    required this.initialZoom,
    required this.initialMaxTitleLength,
    required this.initialEnableToolTips,
    required this.initialEnableAnimations,
    required this.initialTodoLineSpacing,
    required this.initialNoteLineSpacing,
    required this.initialShowTodoDueRelativeTime,
    required this.initialTodoDueYearDisplayMode,
    required this.initialUseTodoReminderInterval,
    required this.initialTodoReminderIntervalValue,
    required this.initialTodoReminderIntervalUnit,
    required this.initialTodoReminderScope,
    required this.initialTodoReminderBubbleDurationSeconds,
    required this.initialShowTopBarNewTodoButton,
    required this.initialShowTopBarNewNoteButton,
    required this.initialShowTopBarExternalOpenButton,
    required this.initialUseCapsuleMode,
    required this.initialUseDeepCapsuleMode,
    required this.initialUseCapsuleCollapseAll,
    required this.initialCapsuleCollapseAllActive,
    required this.initialDeepCapsuleSide,
    required this.initialDeepCapsuleStartTopMargin,
    required this.initialDeepCapsuleMonitorDeviceName,
    required this.initialShowDeepCapsuleWhileExpanded,
    required this.initialCollapseExpandedDeepCapsuleOnClick,
    required this.initialHideDeepCapsulesWhenCovered,
    required this.initialHideDeepCapsulesWhenFullscreen,
    required this.initialStartAtLogin,
    required this.supportsStartAtLogin,
    required this.supportsHideFromWindowSwitcher,
    required this.supportsFullscreenTopmostMode,
    required this.supportsGlobalHotkeys,
    required this.supportsScriptCapsules,
    required this.initialHideFromWindowSwitcher,
    required this.initialFullscreenTopmostMode,
    required this.initialPinnedTodoHotKey,
    required this.initialPinnedNoteHotKey,
    required this.initialRunLinkedScriptCapsulesOnClick,
    required this.initialUsePersistentPowerShellProcess,
    required this.initialPreferPowerShell7,
    required this.initialHideScriptRunWindow,
    required this.initialEnableTodoNoteLinks,
    required this.initialShowLinkedNoteName,
    required this.initialAllowLongLinkedNoteTitles,
    required this.initialHideLinkedNotesFromCapsules,
    required this.initialDataDirectoryPath,
    required this.supportsDataDirectorySelection,
    this.selectDataDirectory,
    this.loadInstalledFontFamilies,
    super.key,
  });

  final SyncSettings initialSettings;
  final String initialTheme;
  final String initialColorScheme;
  final String initialCustomThemeColorHex;
  final String initialMarkdownRenderMode;
  final String initialTodoVisualSize;
  final String initialUiFontPreset;
  final String initialSystemFontFamilyName;
  final String initialExternalMarkdownExtension;
  final double initialZoom;
  final int initialMaxTitleLength;
  final bool initialEnableToolTips;
  final bool initialEnableAnimations;
  final double initialTodoLineSpacing;
  final double initialNoteLineSpacing;
  final bool initialShowTodoDueRelativeTime;
  final String initialTodoDueYearDisplayMode;
  final bool initialUseTodoReminderInterval;
  final int initialTodoReminderIntervalValue;
  final String initialTodoReminderIntervalUnit;
  final String initialTodoReminderScope;
  final int initialTodoReminderBubbleDurationSeconds;
  final bool initialShowTopBarNewTodoButton;
  final bool initialShowTopBarNewNoteButton;
  final bool initialShowTopBarExternalOpenButton;
  final bool initialUseCapsuleMode;
  final bool initialUseDeepCapsuleMode;
  final bool initialUseCapsuleCollapseAll;
  final bool initialCapsuleCollapseAllActive;
  final String initialDeepCapsuleSide;
  final double initialDeepCapsuleStartTopMargin;
  final String initialDeepCapsuleMonitorDeviceName;
  final bool initialShowDeepCapsuleWhileExpanded;
  final bool initialCollapseExpandedDeepCapsuleOnClick;
  final bool initialHideDeepCapsulesWhenCovered;
  final bool initialHideDeepCapsulesWhenFullscreen;
  final bool initialStartAtLogin;
  final bool supportsStartAtLogin;
  final bool supportsHideFromWindowSwitcher;
  final bool supportsFullscreenTopmostMode;
  final bool supportsGlobalHotkeys;
  final bool supportsScriptCapsules;
  final bool initialHideFromWindowSwitcher;
  final String initialFullscreenTopmostMode;
  final String initialPinnedTodoHotKey;
  final String initialPinnedNoteHotKey;
  final bool initialRunLinkedScriptCapsulesOnClick;
  final bool initialUsePersistentPowerShellProcess;
  final bool initialPreferPowerShell7;
  final bool initialHideScriptRunWindow;
  final bool initialEnableTodoNoteLinks;
  final bool initialShowLinkedNoteName;
  final bool initialAllowLongLinkedNoteTitles;
  final bool initialHideLinkedNotesFromCapsules;
  final String initialDataDirectoryPath;
  final bool supportsDataDirectorySelection;
  final DataDirectoryPicker? selectDataDirectory;
  final InstalledFontFamilyLoader? loadInstalledFontFamilies;

  @override
  State<SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends State<SyncSettingsDialog> {
  _SettingsSection _selectedSettingsSection = _SettingsSection.display;
  final Map<_SettingsSection, GlobalKey> _settingsSectionKeys = {
    for (final section in _SettingsSection.values) section: GlobalKey(),
  };
  late bool _enabled;
  late bool _autoSyncOnStart;
  late String _theme;
  late String _colorScheme;
  late String _markdownRenderMode;
  late String _todoVisualSize;
  late String _uiFontPreset;
  late double _zoom;
  late double _maxTitleLength;
  late bool _enableToolTips;
  late bool _enableAnimations;
  late double _todoLineSpacing;
  late double _noteLineSpacing;
  late bool _showTodoDueRelativeTime;
  late String _todoDueYearDisplayMode;
  late bool _useTodoReminderInterval;
  late String _todoReminderIntervalUnit;
  late String _todoReminderScope;
  late bool _showTopBarNewTodoButton;
  late bool _showTopBarNewNoteButton;
  late bool _showTopBarExternalOpenButton;
  late bool _useCapsuleMode;
  late bool _useDeepCapsuleMode;
  late bool _useCapsuleCollapseAll;
  late bool _capsuleCollapseAllActive;
  late String _deepCapsuleSide;
  late bool _showDeepCapsuleWhileExpanded;
  late bool _collapseExpandedDeepCapsuleOnClick;
  late bool _hideDeepCapsulesWhenCovered;
  late bool _hideDeepCapsulesWhenFullscreen;
  late bool _startAtLogin;
  late bool _hideFromWindowSwitcher;
  late String _fullscreenTopmostMode;
  late bool _runLinkedScriptCapsulesOnClick;
  late bool _usePersistentPowerShellProcess;
  late bool _preferPowerShell7;
  late bool _hideScriptRunWindow;
  late bool _enableTodoNoteLinks;
  late bool _showLinkedNoteName;
  late bool _allowLongLinkedNoteTitles;
  late bool _hideLinkedNotesFromCapsules;
  late String _presetId;
  late bool _obscurePassword = true;
  late bool _obscureEncryptionPassphrase = true;
  late final TextEditingController _endpointController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _encryptionPassphraseController;
  late final TextEditingController _rootPathController;
  final FocusNode _endpointFocusNode = FocusNode();
  final FocusNode _rootPathFocusNode = FocusNode();
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _encryptionPassphraseFocusNode = FocusNode();
  final FocusNode _externalMarkdownExtensionFocusNode = FocusNode();
  final FocusNode _fontFamilyFocusNode = FocusNode();
  late final TextEditingController _intervalController;
  late final TextEditingController _requestTimeoutController;
  late final TextEditingController _fontFamilyController;
  late final TextEditingController _customThemeColorController;
  late final TextEditingController _externalMarkdownExtensionController;
  late final TextEditingController _deepCapsuleTopMarginController;
  late final TextEditingController _deepCapsuleMonitorController;
  late final TextEditingController _pinnedTodoHotKeyController;
  late final TextEditingController _pinnedNoteHotKeyController;
  late final TextEditingController _reminderIntervalController;
  late final TextEditingController _reminderDurationController;
  late final TextEditingController _todoLineSpacingController;
  late final TextEditingController _noteLineSpacingController;
  late final TextEditingController _dataDirectoryController;
  String? _errorText;
  String? _endpointErrorText;
  String? _rootPathErrorText;
  String? _usernameErrorText;
  String? _passwordErrorText;
  String? _encryptionPassphraseErrorText;
  String? _externalMarkdownExtensionErrorText;
  List<String> _installedFontFamilies = const [];
  bool _isLoadingInstalledFontFamilies = false;

  PaperTodoStrings get strings => PaperTodoStringsScope.of(context);

  bool get _hasDesktopIntegrationSettings =>
      widget.supportsStartAtLogin ||
      widget.supportsHideFromWindowSwitcher ||
      widget.supportsFullscreenTopmostMode ||
      widget.supportsGlobalHotkeys ||
      widget.supportsScriptCapsules;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings.copy()..normalize();
    final webDav = settings.webDav;
    _enabled = settings.enabled;
    _autoSyncOnStart = webDav.autoSyncOnStart;
    _theme = _normalizeTheme(widget.initialTheme);
    _colorScheme = ColorSchemes.normalize(widget.initialColorScheme);
    _markdownRenderMode =
        MarkdownRenderModes.normalize(widget.initialMarkdownRenderMode);
    _todoVisualSize = TodoVisualSizes.normalize(widget.initialTodoVisualSize);
    // PaperTodo keeps the legacy preset value only for data compatibility.
    // The current settings UI exposes one installed-system-font selector.
    _uiFontPreset = UiFontPresets.defaultPreset;
    _zoom = widget.initialZoom.clamp(0.5, 1.5).toDouble();
    _maxTitleLength = widget.initialMaxTitleLength.clamp(2, 20).toDouble();
    _enableToolTips = widget.initialEnableToolTips;
    _enableAnimations = widget.initialEnableAnimations;
    _todoLineSpacing = widget.initialTodoLineSpacing.clamp(0.8, 5.0).toDouble();
    _noteLineSpacing = widget.initialNoteLineSpacing.clamp(0.8, 5.0).toDouble();
    _showTodoDueRelativeTime = widget.initialShowTodoDueRelativeTime;
    _todoDueYearDisplayMode =
        TodoDueYearDisplayModes.normalize(widget.initialTodoDueYearDisplayMode);
    _useTodoReminderInterval = widget.initialUseTodoReminderInterval;
    _todoReminderIntervalUnit = TodoReminderIntervalUnits.normalize(
      widget.initialTodoReminderIntervalUnit,
    );
    _todoReminderScope =
        TodoReminderScopes.normalize(widget.initialTodoReminderScope);
    _showTopBarNewTodoButton = widget.initialShowTopBarNewTodoButton;
    _showTopBarNewNoteButton = widget.initialShowTopBarNewNoteButton;
    _showTopBarExternalOpenButton = widget.initialShowTopBarExternalOpenButton;
    _useCapsuleMode = widget.initialUseCapsuleMode;
    _useDeepCapsuleMode = widget.initialUseDeepCapsuleMode;
    _useCapsuleCollapseAll = widget.initialUseCapsuleCollapseAll;
    _capsuleCollapseAllActive = widget.initialCapsuleCollapseAllActive;
    _deepCapsuleSide =
        DeepCapsuleSides.normalize(widget.initialDeepCapsuleSide);
    _showDeepCapsuleWhileExpanded = widget.initialShowDeepCapsuleWhileExpanded;
    _collapseExpandedDeepCapsuleOnClick =
        widget.initialCollapseExpandedDeepCapsuleOnClick;
    _hideDeepCapsulesWhenCovered = widget.initialHideDeepCapsulesWhenCovered;
    _hideDeepCapsulesWhenFullscreen =
        widget.initialHideDeepCapsulesWhenFullscreen;
    _startAtLogin = widget.initialStartAtLogin;
    _hideFromWindowSwitcher = widget.initialHideFromWindowSwitcher;
    _fullscreenTopmostMode =
        FullscreenTopmostModes.normalize(widget.initialFullscreenTopmostMode);
    _runLinkedScriptCapsulesOnClick =
        widget.initialRunLinkedScriptCapsulesOnClick;
    _usePersistentPowerShellProcess =
        widget.initialUsePersistentPowerShellProcess;
    _preferPowerShell7 = widget.initialPreferPowerShell7;
    _hideScriptRunWindow = widget.initialHideScriptRunWindow;
    _enableTodoNoteLinks = widget.initialEnableTodoNoteLinks;
    _showLinkedNoteName = widget.initialShowLinkedNoteName;
    _allowLongLinkedNoteTitles = widget.initialAllowLongLinkedNoteTitles;
    _hideLinkedNotesFromCapsules = widget.initialHideLinkedNotesFromCapsules;
    _presetId = webDav.presetId;
    _endpointController = TextEditingController(text: webDav.endpoint);
    _usernameController = TextEditingController(text: webDav.username);
    _passwordController = TextEditingController(text: webDav.password);
    _encryptionPassphraseController =
        TextEditingController(text: webDav.encryptionPassphrase);
    _rootPathController = TextEditingController(text: webDav.rootPath);
    _intervalController =
        TextEditingController(text: webDav.autoSyncIntervalMinutes.toString());
    _requestTimeoutController =
        TextEditingController(text: webDav.requestTimeoutSeconds.toString());
    _fontFamilyController =
        TextEditingController(text: widget.initialSystemFontFamilyName);
    _customThemeColorController = TextEditingController(
      text: widget.initialCustomThemeColorHex,
    );
    _externalMarkdownExtensionController = TextEditingController(
      text: widget.initialExternalMarkdownExtension,
    );
    _deepCapsuleTopMarginController = TextEditingController(
      text: widget.initialDeepCapsuleStartTopMargin
          .clamp(8, 10000)
          .toStringAsFixed(0),
    );
    _deepCapsuleMonitorController = TextEditingController(
      text: widget.initialDeepCapsuleMonitorDeviceName.trim(),
    );
    _pinnedTodoHotKeyController = TextEditingController(
      text: widget.initialPinnedTodoHotKey.trim(),
    );
    _pinnedNoteHotKeyController = TextEditingController(
      text: widget.initialPinnedNoteHotKey.trim(),
    );
    _reminderIntervalController = TextEditingController(
      text: widget.initialTodoReminderIntervalValue.clamp(1, 240).toString(),
    );
    _reminderDurationController = TextEditingController(
      text: widget.initialTodoReminderBubbleDurationSeconds
          .clamp(1, 600)
          .toString(),
    );
    _todoLineSpacingController = TextEditingController(
      text: _todoLineSpacing.toStringAsFixed(1),
    );
    _noteLineSpacingController = TextEditingController(
      text: _noteLineSpacing.toStringAsFixed(1),
    );
    _dataDirectoryController = TextEditingController(
      text: widget.initialDataDirectoryPath,
    );
    _loadInstalledFontFamilies();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _encryptionPassphraseController.dispose();
    _rootPathController.dispose();
    _endpointFocusNode.dispose();
    _rootPathFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _encryptionPassphraseFocusNode.dispose();
    _externalMarkdownExtensionFocusNode.dispose();
    _fontFamilyFocusNode.dispose();
    _intervalController.dispose();
    _requestTimeoutController.dispose();
    _fontFamilyController.dispose();
    _customThemeColorController.dispose();
    _externalMarkdownExtensionController.dispose();
    _deepCapsuleTopMarginController.dispose();
    _deepCapsuleMonitorController.dispose();
    _pinnedTodoHotKeyController.dispose();
    _pinnedNoteHotKeyController.dispose();
    _reminderIntervalController.dispose();
    _reminderDurationController.dispose();
    _todoLineSpacingController.dispose();
    _noteLineSpacingController.dispose();
    _dataDirectoryController.dispose();
    super.dispose();
  }

  Future<void> _chooseDataDirectory() async {
    final picker = widget.selectDataDirectory;
    if (picker == null) {
      return;
    }
    final selected = await picker(_dataDirectoryController.text);
    if (!mounted || selected == null || selected.trim().isEmpty) {
      return;
    }
    setState(() => _dataDirectoryController.text = selected.trim());
  }

  Future<void> _loadInstalledFontFamilies() async {
    final loader = widget.loadInstalledFontFamilies;
    if (loader == null) {
      return;
    }
    _isLoadingInstalledFontFamilies = true;
    try {
      final families = normalizeInstalledFontFamilies(await loader());
      if (!mounted) {
        return;
      }
      setState(() {
        _installedFontFamilies = families;
        _isLoadingInstalledFontFamilies = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _installedFontFamilies = const [];
        _isLoadingInstalledFontFamilies = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final desktopLayout = mediaSize.width >= 900;
    final contentHeight = (mediaSize.height - 170).clamp(360.0, 680.0);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          Icon(Icons.settings_outlined, color: colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              strings.get(PaperTodoStringKeys.actionSettings),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          IconButton(
            tooltip: strings.get(PaperTodoStringKeys.actionCancel),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: desktopLayout ? 820 : 520,
        height: contentHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: desktopLayout ? 164 : 52,
              child: _settingsNavigation(compact: !desktopLayout),
            ),
            const VerticalDivider(width: 20),
            Expanded(
              child: Scrollbar(
                thumbVisibility: desktopLayout,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_selectedSettingsSection ==
                          _SettingsSection.display) ...[
                        _settingsSectionHeader(
                          section: _SettingsSection.display,
                          icon: Icons.palette_outlined,
                          label: strings.get(PaperTodoStringKeys.appearance),
                        ),
                        const SizedBox(height: 12),
                        _adaptiveChoiceSelector(
                          key: const ValueKey('settings-theme-selector'),
                          labelText: strings.get(PaperTodoStringKeys.theme),
                          compactIcon: Icons.brightness_auto_outlined,
                          selectedValue: _theme,
                          choices: [
                            _SettingsChoice(
                              value: 'system',
                              label:
                                  strings.get(PaperTodoStringKeys.themeSystem),
                              icon: Icons.brightness_auto_outlined,
                            ),
                            _SettingsChoice(
                              value: 'light',
                              label:
                                  strings.get(PaperTodoStringKeys.themeLight),
                              icon: Icons.light_mode_outlined,
                            ),
                            _SettingsChoice(
                              value: 'dark',
                              label: strings.get(PaperTodoStringKeys.themeDark),
                              icon: Icons.dark_mode_outlined,
                            ),
                          ],
                          onChanged: (value) => setState(() => _theme = value),
                        ),
                        const SizedBox(height: 12),
                        _adaptiveChoiceSelector(
                          key: const ValueKey('settings-color-scheme-selector'),
                          labelText:
                              strings.get(PaperTodoStringKeys.colorScheme),
                          compactIcon: Icons.palette_outlined,
                          selectedValue: _colorScheme,
                          choices: [
                            _SettingsChoice(
                              value: ColorSchemes.warm,
                              label: strings.get(PaperTodoStringKeys.colorWarm),
                            ),
                            _SettingsChoice(
                              value: ColorSchemes.ink,
                              label: strings.get(PaperTodoStringKeys.colorInk),
                            ),
                            _SettingsChoice(
                              value: ColorSchemes.forest,
                              label:
                                  strings.get(PaperTodoStringKeys.colorForest),
                            ),
                            _SettingsChoice(
                              value: ColorSchemes.rose,
                              label: strings.get(PaperTodoStringKeys.colorRose),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _colorScheme = value),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          strings.get(PaperTodoStringKeys.customThemeColor),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        _customThemeColorEditor(),
                        const SizedBox(height: 16),
                        Text(
                          strings.get(PaperTodoStringKeys.appearance),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        _adaptiveChoiceSelector(
                          key:
                              const ValueKey('settings-markdown-mode-selector'),
                          labelText:
                              strings.get(PaperTodoStringKeys.markdownMode),
                          compactIcon: Icons.article_outlined,
                          selectedValue: _markdownRenderMode,
                          choices: [
                            _SettingsChoice(
                              value: MarkdownRenderModes.off,
                              label:
                                  strings.get(PaperTodoStringKeys.markdownOff),
                              icon: Icons.edit_outlined,
                            ),
                            _SettingsChoice(
                              value: MarkdownRenderModes.basic,
                              label: strings.get(PaperTodoStringKeys.basic),
                              icon: Icons.article_outlined,
                            ),
                            _SettingsChoice(
                              value: MarkdownRenderModes.enhanced,
                              label: strings.get(PaperTodoStringKeys.enhanced),
                              icon: Icons.vertical_split_outlined,
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _markdownRenderMode = value),
                        ),
                        const SizedBox(height: 12),
                        _adaptiveChoiceSelector(
                          key: const ValueKey(
                              'settings-todo-visual-size-selector'),
                          labelText:
                              strings.get(PaperTodoStringKeys.todoVisualSize),
                          compactIcon: Icons.format_size_outlined,
                          selectedValue: _todoVisualSize,
                          choices: [
                            _SettingsChoice(
                              value: TodoVisualSizes.small,
                              label: strings.get(PaperTodoStringKeys.small),
                            ),
                            _SettingsChoice(
                              value: TodoVisualSizes.medium,
                              label: strings.get(PaperTodoStringKeys.medium),
                            ),
                            _SettingsChoice(
                              value: TodoVisualSizes.large,
                              label: strings.get(PaperTodoStringKeys.large),
                            ),
                            _SettingsChoice(
                              value: TodoVisualSizes.extraLarge,
                              label: strings.get(PaperTodoStringKeys.xl),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _todoVisualSize = value),
                        ),
                        const SizedBox(height: 12),
                        _fontFamilyField(),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _externalMarkdownExtensionController,
                          focusNode: _externalMarkdownExtensionFocusNode,
                          onChanged: (_) {
                            if (_externalMarkdownExtensionErrorText == null) {
                              return;
                            }
                            setState(() =>
                                _externalMarkdownExtensionErrorText = null);
                          },
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: strings.get(
                              PaperTodoStringKeys.externalMarkdownExtension,
                            ),
                            errorText: _externalMarkdownExtensionErrorText,
                            prefixIcon: const Icon(Icons.file_open_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SettingsSlider(
                          icon: Icons.zoom_in_outlined,
                          label: strings.get(PaperTodoStringKeys.zoom),
                          valueLabel: '${(_zoom * 100).round()}%',
                          value: _zoom,
                          min: 0.5,
                          max: 1.5,
                          divisions: 10,
                          onChanged: (value) => setState(() => _zoom = value),
                        ),
                        _SettingsSlider(
                          icon: Icons.short_text_outlined,
                          label:
                              strings.get(PaperTodoStringKeys.maxTitleLength),
                          valueLabel: '${_maxTitleLength.round()} chars',
                          value: _maxTitleLength,
                          min: 2,
                          max: 20,
                          divisions: 18,
                          onChanged: (value) =>
                              setState(() => _maxTitleLength = value),
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: _SettingsHelpIcon(
                            message:
                                strings.get(PaperTodoStringKeys.tooltipsHelp),
                          ),
                          title:
                              Text(strings.get(PaperTodoStringKeys.tooltips)),
                          value: _enableToolTips,
                          onChanged: (value) =>
                              setState(() => _enableToolTips = value),
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.animation_outlined),
                          title:
                              Text(strings.get(PaperTodoStringKeys.animations)),
                          value: _enableAnimations,
                          onChanged: (value) =>
                              setState(() => _enableAnimations = value),
                        ),
                        _adaptiveFieldPair(
                          first: _lineSpacingEditor(
                            key: const ValueKey('settings-todo-line-spacing'),
                            controller: _todoLineSpacingController,
                            icon: Icons.checklist_outlined,
                            label: strings.get(PaperTodoStringKeys.todoSpacing),
                          ),
                          second: _lineSpacingEditor(
                            key: const ValueKey('settings-note-line-spacing'),
                            controller: _noteLineSpacingController,
                            icon: Icons.notes_outlined,
                            label: strings.get(PaperTodoStringKeys.noteSpacing),
                          ),
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.event_repeat_outlined),
                          title: Text(strings
                              .get(PaperTodoStringKeys.relativeDueDates)),
                          value: _showTodoDueRelativeTime,
                          onChanged: (value) =>
                              setState(() => _showTodoDueRelativeTime = value),
                        ),
                        const SizedBox(height: 8),
                        _adaptiveChoiceSelector(
                          key: const ValueKey('settings-due-year-selector'),
                          labelText:
                              strings.get(PaperTodoStringKeys.dueYearDisplay),
                          compactIcon: Icons.event_outlined,
                          selectedValue: _todoDueYearDisplayMode,
                          choices: [
                            _SettingsChoice(
                              value: TodoDueYearDisplayModes.none,
                              label: strings.get(PaperTodoStringKeys.noYear),
                            ),
                            _SettingsChoice(
                              value: TodoDueYearDisplayModes.short,
                              label: strings.get(PaperTodoStringKeys.yy),
                            ),
                            _SettingsChoice(
                              value: TodoDueYearDisplayModes.full,
                              label: strings.get(PaperTodoStringKeys.yyyy),
                            ),
                          ],
                          onChanged: _showTodoDueRelativeTime
                              ? null
                              : (value) => setState(
                                  () => _todoDueYearDisplayMode = value),
                        ),
                        const Divider(height: 24),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.add_task_outlined),
                          title: Text(
                              strings.get(PaperTodoStringKeys.topBarNewTodo)),
                          value: _showTopBarNewTodoButton,
                          onChanged: (value) =>
                              setState(() => _showTopBarNewTodoButton = value),
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.note_add_outlined),
                          title: Text(
                              strings.get(PaperTodoStringKeys.topBarNewNote)),
                          value: _showTopBarNewNoteButton,
                          onChanged: (value) =>
                              setState(() => _showTopBarNewNoteButton = value),
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.file_open_outlined),
                          title: Text(strings
                              .get(PaperTodoStringKeys.topBarOpenSurface)),
                          value: _showTopBarExternalOpenButton,
                          onChanged: (value) => setState(
                              () => _showTopBarExternalOpenButton = value),
                        ),
                      ],
                      if (_selectedSettingsSection ==
                          _SettingsSection.capsules) ...[
                        const Divider(height: 24),
                        _settingsSectionHeader(
                          section: _SettingsSection.capsules,
                          icon: Icons.view_agenda_outlined,
                          label:
                              strings.get(PaperTodoStringKeys.settingsCapsules),
                        ),
                        const SizedBox(height: 4),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.view_agenda_outlined),
                          title: Text(
                              strings.get(PaperTodoStringKeys.capsuleMode)),
                          value: _useCapsuleMode,
                          onChanged: (value) => setState(() {
                            _useCapsuleMode = value;
                            if (!value) {
                              _useDeepCapsuleMode = false;
                              _useCapsuleCollapseAll = false;
                              _capsuleCollapseAllActive = false;
                              _showDeepCapsuleWhileExpanded = false;
                              _collapseExpandedDeepCapsuleOnClick = false;
                              _hideDeepCapsulesWhenCovered = false;
                              _hideDeepCapsulesWhenFullscreen = false;
                            }
                          }),
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary:
                              const Icon(Icons.stacked_line_chart_outlined),
                          title: Text(
                              strings.get(PaperTodoStringKeys.deepCapsuleMode)),
                          value: _useDeepCapsuleMode,
                          onChanged: _useCapsuleMode
                              ? (value) => setState(() {
                                    _useDeepCapsuleMode = value;
                                    if (!value) {
                                      _showDeepCapsuleWhileExpanded = false;
                                      _collapseExpandedDeepCapsuleOnClick =
                                          false;
                                      _hideDeepCapsulesWhenCovered = false;
                                      _hideDeepCapsulesWhenFullscreen = false;
                                    }
                                  })
                              : null,
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.unfold_less_outlined),
                          title: Text(strings
                              .get(PaperTodoStringKeys.collapseAllControl)),
                          value: _useCapsuleCollapseAll,
                          onChanged: _useCapsuleMode
                              ? (value) => setState(() {
                                    _useCapsuleCollapseAll = value;
                                    if (!value) {
                                      _capsuleCollapseAllActive = false;
                                    }
                                  })
                              : null,
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary:
                              const Icon(Icons.vertical_align_center_outlined),
                          title: Text(strings
                              .get(PaperTodoStringKeys.collapseAllActive)),
                          value: _capsuleCollapseAllActive,
                          onChanged: _useCapsuleMode && _useCapsuleCollapseAll
                              ? (value) => setState(
                                  () => _capsuleCollapseAllActive = value)
                              : null,
                        ),
                        const SizedBox(height: 8),
                        _adaptiveChoiceSelector(
                          key: const ValueKey(
                              'settings-deep-capsule-side-selector'),
                          labelText:
                              strings.get(PaperTodoStringKeys.deepCapsuleSide),
                          compactIcon: Icons.vertical_align_center_outlined,
                          selectedValue: _deepCapsuleSide,
                          choices: [
                            _SettingsChoice(
                              value: DeepCapsuleSides.left,
                              label: strings.get(PaperTodoStringKeys.left),
                              icon: Icons.keyboard_double_arrow_left_outlined,
                            ),
                            _SettingsChoice(
                              value: DeepCapsuleSides.right,
                              label: strings.get(PaperTodoStringKeys.right),
                              icon: Icons.keyboard_double_arrow_right_outlined,
                            ),
                          ],
                          onChanged: _useCapsuleMode && _useDeepCapsuleMode
                              ? (value) =>
                                  setState(() => _deepCapsuleSide = value)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _deepCapsuleTopMarginController,
                          enabled: _useCapsuleMode && _useDeepCapsuleMode,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: strings.get(
                              PaperTodoStringKeys.deepCapsuleTopMargin,
                            ),
                            prefixIcon:
                                const Icon(Icons.vertical_align_top_outlined),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _deepCapsuleMonitorController,
                          enabled: _useCapsuleMode && _useDeepCapsuleMode,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: strings
                                .get(PaperTodoStringKeys.deepCapsuleMonitor),
                            prefixIcon: const Icon(Icons.monitor_outlined),
                          ),
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.open_in_full_outlined),
                          title: Text(
                            strings.get(PaperTodoStringKeys
                                .showDeepCapsuleWhileExpanded),
                          ),
                          value: _showDeepCapsuleWhileExpanded,
                          onChanged: _useCapsuleMode && _useDeepCapsuleMode
                              ? (value) => setState(
                                  () => _showDeepCapsuleWhileExpanded = value)
                              : null,
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.ads_click_outlined),
                          title: Text(
                            strings.get(
                              PaperTodoStringKeys
                                  .collapseExpandedDeepCapsuleOnClick,
                            ),
                          ),
                          value: _collapseExpandedDeepCapsuleOnClick,
                          onChanged: _useCapsuleMode && _useDeepCapsuleMode
                              ? (value) => setState(
                                    () => _collapseExpandedDeepCapsuleOnClick =
                                        value,
                                  )
                              : null,
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.layers_clear_outlined),
                          title: Text(
                            strings.get(
                                PaperTodoStringKeys.hideCoveredDeepCapsules),
                          ),
                          value: _hideDeepCapsulesWhenCovered,
                          onChanged: _useCapsuleMode && _useDeepCapsuleMode
                              ? (value) => setState(
                                  () => _hideDeepCapsulesWhenCovered = value)
                              : null,
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.fullscreen_exit_outlined),
                          title: Text(
                            strings.get(
                                PaperTodoStringKeys.hideFullscreenDeepCapsules),
                          ),
                          value: _hideDeepCapsulesWhenFullscreen,
                          onChanged: _useCapsuleMode && _useDeepCapsuleMode
                              ? (value) => setState(
                                    () =>
                                        _hideDeepCapsulesWhenFullscreen = value,
                                  )
                              : null,
                        ),
                      ],
                      if (_selectedSettingsSection ==
                          _SettingsSection.general) ...[
                        const Divider(height: 24),
                        _settingsSectionHeader(
                          section: _SettingsSection.general,
                          icon: Icons.tune_outlined,
                          label: strings
                              .get(PaperTodoStringKeys.settingsGeneralAdvanced),
                        ),
                        if (_hasDesktopIntegrationSettings)
                          const SizedBox(height: 4),
                        if (widget.supportsDataDirectorySelection) ...[
                          TextField(
                            key: const ValueKey('settings-data-directory'),
                            controller: _dataDirectoryController,
                            readOnly: true,
                            onTap: _chooseDataDirectory,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: strings
                                  .get(PaperTodoStringKeys.dataDirectory),
                              helperText: strings
                                  .get(PaperTodoStringKeys.dataDirectoryHelp),
                              prefixIcon: const Icon(Icons.folder_outlined),
                              suffixIcon: TextButton(
                                key: const ValueKey(
                                    'settings-data-directory-browse'),
                                onPressed: _chooseDataDirectory,
                                child: Text(strings
                                    .get(PaperTodoStringKeys.actionBrowse)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (widget.supportsStartAtLogin)
                          _SettingsCheckboxTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.login_outlined),
                            title: Text(
                                strings.get(PaperTodoStringKeys.startAtLogin)),
                            value: _startAtLogin,
                            onChanged: (value) =>
                                setState(() => _startAtLogin = value),
                          ),
                        if (widget.supportsHideFromWindowSwitcher)
                          _SettingsCheckboxTile(
                            contentPadding: EdgeInsets.zero,
                            secondary:
                                const Icon(Icons.visibility_off_outlined),
                            title: Text(
                              strings.get(
                                  PaperTodoStringKeys.hideFromTaskSwitcher),
                            ),
                            value: _hideFromWindowSwitcher,
                            onChanged: (value) =>
                                setState(() => _hideFromWindowSwitcher = value),
                          ),
                        if (widget.supportsFullscreenTopmostMode) ...[
                          const SizedBox(height: 8),
                          _adaptiveChoiceSelector(
                            key: const ValueKey(
                                'settings-fullscreen-topmost-selector'),
                            labelText: strings
                                .get(PaperTodoStringKeys.fullscreenTopmostMode),
                            compactIcon: Icons.fullscreen_exit_outlined,
                            selectedValue: _fullscreenTopmostMode,
                            choices: [
                              _SettingsChoice(
                                value: FullscreenTopmostModes.avoid,
                                label: strings
                                    .get(PaperTodoStringKeys.avoidFullscreen),
                                icon: Icons.fullscreen_exit_outlined,
                              ),
                              _SettingsChoice(
                                value: FullscreenTopmostModes.stayOnTop,
                                label:
                                    strings.get(PaperTodoStringKeys.stayOnTop),
                                icon: Icons.push_pin_outlined,
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _fullscreenTopmostMode = value),
                          ),
                        ],
                        if (widget.supportsGlobalHotkeys) ...[
                          const SizedBox(height: 12),
                          _adaptiveFieldPair(
                            first: _hotKeyCaptureField(
                              controller: _pinnedTodoHotKeyController,
                              labelText: strings
                                  .get(PaperTodoStringKeys.pinnedTodoHotkey),
                              icon: Icons.keyboard_outlined,
                            ),
                            second: _hotKeyCaptureField(
                              controller: _pinnedNoteHotKeyController,
                              labelText: strings
                                  .get(PaperTodoStringKeys.pinnedNoteHotkey),
                              icon: Icons.keyboard_command_key_outlined,
                            ),
                          ),
                        ],
                        if (widget.supportsScriptCapsules) ...[
                          const Divider(height: 24),
                          _SettingsCheckboxTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.terminal_outlined),
                            title: Text(
                              strings.get(
                                PaperTodoStringKeys
                                    .runLinkedScriptCapsulesOnClick,
                              ),
                            ),
                            value: _runLinkedScriptCapsulesOnClick,
                            onChanged: _enableTodoNoteLinks
                                ? (value) => setState(
                                      () => _runLinkedScriptCapsulesOnClick =
                                          value,
                                    )
                                : null,
                          ),
                          _SettingsCheckboxTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.memory_outlined),
                            title: Text(
                              strings.get(
                                PaperTodoStringKeys.persistentPowerShellProcess,
                              ),
                            ),
                            value: _usePersistentPowerShellProcess,
                            onChanged: (value) => setState(
                              () => _usePersistentPowerShellProcess = value,
                            ),
                          ),
                          _SettingsCheckboxTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.bolt_outlined),
                            title: Text(strings
                                .get(PaperTodoStringKeys.preferPowerShell7)),
                            value: _preferPowerShell7,
                            onChanged: (value) =>
                                setState(() => _preferPowerShell7 = value),
                          ),
                          _SettingsCheckboxTile(
                            contentPadding: EdgeInsets.zero,
                            secondary:
                                const Icon(Icons.visibility_off_outlined),
                            title: Text(strings
                                .get(PaperTodoStringKeys.hideScriptRunWindow)),
                            value: _hideScriptRunWindow,
                            onChanged: (value) =>
                                setState(() => _hideScriptRunWindow = value),
                          ),
                        ],
                      ],
                      if (_selectedSettingsSection ==
                          _SettingsSection.todoAndNotes) ...[
                        const Divider(height: 24),
                        _settingsSectionHeader(
                          section: _SettingsSection.todoAndNotes,
                          icon: Icons.checklist_outlined,
                          label: strings
                              .get(PaperTodoStringKeys.settingsTodoAndNotes),
                        ),
                        const SizedBox(height: 4),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary:
                              const Icon(Icons.notifications_active_outlined),
                          title: Text(
                              strings.get(PaperTodoStringKeys.todoReminders)),
                          value: _useTodoReminderInterval,
                          onChanged: (value) =>
                              setState(() => _useTodoReminderInterval = value),
                        ),
                        const SizedBox(height: 8),
                        _adaptiveFieldPair(
                          first: TextField(
                            controller: _reminderIntervalController,
                            enabled: _useTodoReminderInterval,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: strings
                                  .get(PaperTodoStringKeys.reminderInterval),
                              prefixIcon: const Icon(Icons.timer_outlined),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          second: _adaptiveChoiceSelector(
                            key: const ValueKey(
                                'settings-reminder-unit-selector'),
                            labelText:
                                strings.get(PaperTodoStringKeys.reminderUnit),
                            compactIcon: Icons.schedule_outlined,
                            selectedValue: _todoReminderIntervalUnit,
                            choices: [
                              _SettingsChoice(
                                value: TodoReminderIntervalUnits.minutes,
                                label: strings.get(PaperTodoStringKeys.minutes),
                              ),
                              _SettingsChoice(
                                value: TodoReminderIntervalUnits.hours,
                                label: strings.get(PaperTodoStringKeys.hours),
                              ),
                            ],
                            onChanged: _useTodoReminderInterval
                                ? (value) => setState(
                                    () => _todoReminderIntervalUnit = value)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _adaptiveChoiceSelector(
                          key: const ValueKey(
                              'settings-reminder-scope-selector'),
                          labelText:
                              strings.get(PaperTodoStringKeys.reminderScope),
                          compactIcon: Icons.notifications_active_outlined,
                          selectedValue: _todoReminderScope,
                          choices: [
                            _SettingsChoice(
                              value: TodoReminderScopes.all,
                              label: strings.get(PaperTodoStringKeys.allDue),
                              icon: Icons.format_list_bulleted_outlined,
                            ),
                            _SettingsChoice(
                              value: TodoReminderScopes.nearest,
                              label: strings.get(PaperTodoStringKeys.nearest),
                              icon: Icons.near_me_outlined,
                            ),
                          ],
                          onChanged: _useTodoReminderInterval
                              ? (value) =>
                                  setState(() => _todoReminderScope = value)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _reminderDurationController,
                          enabled: _useTodoReminderInterval,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: strings.get(
                                PaperTodoStringKeys.reminderDisplaySeconds),
                            prefixIcon:
                                const Icon(Icons.hourglass_bottom_outlined),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const Divider(height: 24),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.account_tree_outlined),
                          title: Text(
                              strings.get(PaperTodoStringKeys.todoNoteLinks)),
                          value: _enableTodoNoteLinks,
                          onChanged: (value) =>
                              setState(() => _enableTodoNoteLinks = value),
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.notes_outlined),
                          title: Text(strings
                              .get(PaperTodoStringKeys.showLinkedNoteName)),
                          value: _showLinkedNoteName,
                          onChanged: _enableTodoNoteLinks
                              ? (value) =>
                                  setState(() => _showLinkedNoteName = value)
                              : null,
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.subject_outlined),
                          title: Text(
                            strings.get(
                                PaperTodoStringKeys.allowLongLinkedNoteTitles),
                          ),
                          value: _allowLongLinkedNoteTitles,
                          onChanged: _enableTodoNoteLinks && _showLinkedNoteName
                              ? (value) => setState(
                                  () => _allowLongLinkedNoteTitles = value)
                              : null,
                        ),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.layers_clear_outlined),
                          title: Text(strings
                              .get(PaperTodoStringKeys.hideLinkedNoteCapsules)),
                          value: _hideLinkedNotesFromCapsules,
                          onChanged: _enableTodoNoteLinks
                              ? (value) => setState(
                                  () => _hideLinkedNotesFromCapsules = value)
                              : null,
                        ),
                      ],
                      if (_selectedSettingsSection ==
                          _SettingsSection.sync) ...[
                        const Divider(height: 24),
                        _settingsSectionHeader(
                          section: _SettingsSection.sync,
                          icon: Icons.cloud_sync_outlined,
                          label: strings.get(PaperTodoStringKeys.webDavSync),
                        ),
                        const SizedBox(height: 4),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.sync_outlined),
                          title:
                              Text(strings.get(PaperTodoStringKeys.webDavSync)),
                          value: _enabled,
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                        ),
                        const SizedBox(height: 12),
                        _webDavPresetSelector(context),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _endpointController,
                          focusNode: _endpointFocusNode,
                          enabled: _enabled,
                          onChanged: (_) => _clearWebDavError(
                            WebDavSyncConfigurationIssue.endpoint,
                          ),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText:
                                strings.get(PaperTodoStringKeys.webDavUrl),
                            errorText: _endpointErrorText,
                            prefixIcon: const Icon(Icons.link_outlined),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _rootPathController,
                          focusNode: _rootPathFocusNode,
                          enabled: _enabled,
                          onChanged: (_) => _clearWebDavError(
                            WebDavSyncConfigurationIssue.rootPath,
                          ),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText:
                                strings.get(PaperTodoStringKeys.remoteFolder),
                            errorText: _rootPathErrorText,
                            prefixIcon: const Icon(Icons.folder_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _usernameController,
                          focusNode: _usernameFocusNode,
                          enabled: _enabled,
                          onChanged: (_) => _clearWebDavError(
                            WebDavSyncConfigurationIssue.username,
                          ),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText:
                                strings.get(PaperTodoStringKeys.username),
                            errorText: _usernameErrorText,
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          enabled: _enabled,
                          obscureText: _obscurePassword,
                          onChanged: (_) => _clearWebDavError(
                            WebDavSyncConfigurationIssue.password,
                          ),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: strings.get(
                              _presetId == WebDavPresetIds.jianguoyun
                                  ? PaperTodoStringKeys.webDavAppPassword
                                  : PaperTodoStringKeys.password,
                            ),
                            helperText: _presetId == WebDavPresetIds.jianguoyun
                                ? strings.get(PaperTodoStringKeys
                                    .jianguoyunAppPasswordHelper)
                                : null,
                            errorText: _passwordErrorText,
                            prefixIcon: const Icon(Icons.key_outlined),
                            suffixIcon: IconButton(
                              tooltip: _enableToolTips
                                  ? _obscurePassword
                                      ? strings
                                          .get(PaperTodoStringKeys.showPassword)
                                      : strings
                                          .get(PaperTodoStringKeys.hidePassword)
                                  : null,
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _encryptionPassphraseController,
                          focusNode: _encryptionPassphraseFocusNode,
                          enabled: _enabled,
                          obscureText: _obscureEncryptionPassphrase,
                          onChanged: (_) => _clearWebDavError(
                            WebDavSyncConfigurationIssue.encryptionPassphrase,
                          ),
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: strings.get(
                                PaperTodoStringKeys.syncEncryptionPassphrase),
                            helperText: strings
                                .get(PaperTodoStringKeys.passphraseHelper),
                            errorText: _encryptionPassphraseErrorText,
                            prefixIcon:
                                const Icon(Icons.enhanced_encryption_outlined),
                            suffixIcon: IconButton(
                              tooltip: _enableToolTips
                                  ? _obscureEncryptionPassphrase
                                      ? strings.get(
                                          PaperTodoStringKeys.showPassphrase)
                                      : strings.get(
                                          PaperTodoStringKeys.hidePassphrase)
                                  : null,
                              onPressed: () => setState(() =>
                                  _obscureEncryptionPassphrase =
                                      !_obscureEncryptionPassphrase),
                              icon: Icon(_obscureEncryptionPassphrase
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _adaptiveFieldPair(
                          first: TextField(
                            controller: _intervalController,
                            enabled: _enabled,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: strings
                                  .get(PaperTodoStringKeys.intervalMinutes),
                              prefixIcon: const Icon(Icons.schedule_outlined),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                          ),
                          second: TextField(
                            controller: _requestTimeoutController,
                            enabled: _enabled,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText: strings.get(
                                  PaperTodoStringKeys.requestTimeoutSeconds),
                              prefixIcon: const Icon(Icons.timer_outlined),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        _SettingsCheckboxTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              strings.get(PaperTodoStringKeys.syncOnStart)),
                          value: _autoSyncOnStart,
                          onChanged: _enabled
                              ? (value) =>
                                  setState(() => _autoSyncOnStart = value)
                              : null,
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorText!,
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: Text(strings.get(PaperTodoStringKeys.actionSave)),
        ),
      ],
    );
  }

  Widget _customThemeColorEditor() {
    final colors = Theme.of(context).colorScheme;
    final normalized = _normalizeColorHex(_customThemeColorController.text);
    final selectedColor = normalized.isEmpty
        ? colors.primary
        : Color(int.parse('FF${normalized.substring(1)}', radix: 16));
    final currentLabel = normalized.isEmpty
        ? strings.get(PaperTodoStringKeys.themeColorDefault)
        : normalized;

    return Semantics(
      label: strings.get(PaperTodoStringKeys.customThemeColor),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: selectedColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('settings-theme-color-swatch'),
              onTap: _showCustomThemeColorDialog,
              child: const SizedBox(width: 58, height: 42),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonalIcon(
                      key: const ValueKey('settings-theme-color-pick'),
                      onPressed: _showCustomThemeColorDialog,
                      icon: const Icon(Icons.colorize_outlined, size: 16),
                      label: Text(
                        strings.get(PaperTodoStringKeys.themeColorPick),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('settings-theme-color-clear'),
                      onPressed: normalized.isEmpty
                          ? null
                          : () => setState(
                                () => _customThemeColorController.clear(),
                              ),
                      child: Text(
                        strings.get(PaperTodoStringKeys.themeColorClear),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomThemeColorDialog() async {
    final normalized = _normalizeColorHex(_customThemeColorController.text);
    final initialColor = normalized.isEmpty
        ? Theme.of(context).colorScheme.primary
        : Color(int.parse('FF${normalized.substring(1)}', radix: 16));
    var hsv = HSVColor.fromColor(initialColor);
    final selected = await showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final color = hsv.toColor();
            Widget channelSlider({
              required String label,
              required double value,
              required double max,
              required ValueChanged<double> onChanged,
            }) {
              return Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: value,
                      min: 0,
                      max: max,
                      onChanged: onChanged,
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Text(strings.get(PaperTodoStringKeys.themeColorPick)),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 64,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    channelSlider(
                      label: 'H',
                      value: hsv.hue,
                      max: 360,
                      onChanged: (value) =>
                          setDialogState(() => hsv = hsv.withHue(value)),
                    ),
                    channelSlider(
                      label: 'S',
                      value: hsv.saturation,
                      max: 1,
                      onChanged: (value) => setDialogState(
                        () => hsv = hsv.withSaturation(value),
                      ),
                    ),
                    channelSlider(
                      label: 'V',
                      value: hsv.value,
                      max: 1,
                      onChanged: (value) =>
                          setDialogState(() => hsv = hsv.withValue(value)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(strings.get(PaperTodoStringKeys.actionCancel)),
                ),
                FilledButton(
                  key: const ValueKey('settings-theme-color-apply'),
                  onPressed: () => Navigator.of(dialogContext).pop(color),
                  child: Text(strings.get(PaperTodoStringKeys.themeColorPick)),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || selected == null) {
      return;
    }
    final red = (selected.r * 255).round().toRadixString(16).padLeft(2, '0');
    final green = (selected.g * 255).round().toRadixString(16).padLeft(2, '0');
    final blue = (selected.b * 255).round().toRadixString(16).padLeft(2, '0');
    setState(() {
      _customThemeColorController.text = '#$red$green$blue'.toUpperCase();
    });
  }

  Widget _settingsNavigation({required bool compact}) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('settings-category-navigation'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final section in _SettingsSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Tooltip(
              message: compact ? _settingsSectionLabel(section) : '',
              child: Material(
                color: section == _selectedSettingsSection
                    ? colors.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: ValueKey('settings-category-${section.name}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _selectSettingsSection(section),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 0 : 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: compact
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                        children: [
                          Icon(
                            _settingsSectionIcon(section),
                            size: 19,
                            color: section == _selectedSettingsSection
                                ? colors.onPrimaryContainer
                                : colors.onSurfaceVariant,
                          ),
                          if (!compact) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _settingsSectionLabel(section),
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: section == _selectedSettingsSection
                                          ? colors.onPrimaryContainer
                                          : colors.onSurfaceVariant,
                                      fontWeight:
                                          section == _selectedSettingsSection
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _settingsSectionHeader({
    required _SettingsSection section,
    required IconData icon,
    required String label,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: _settingsSectionKeys[section],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectSettingsSection(_SettingsSection section) {
    setState(() => _selectedSettingsSection = section);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _settingsSectionKeys[section]?.currentContext;
      if (!mounted || target == null) {
        return;
      }
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0,
      );
    });
  }

  String _settingsSectionLabel(_SettingsSection section) {
    return switch (section) {
      _SettingsSection.display => strings.get(PaperTodoStringKeys.appearance),
      _SettingsSection.todoAndNotes =>
        strings.get(PaperTodoStringKeys.settingsTodoAndNotes),
      _SettingsSection.capsules =>
        strings.get(PaperTodoStringKeys.settingsCapsules),
      _SettingsSection.general =>
        strings.get(PaperTodoStringKeys.settingsGeneralAdvanced),
      _SettingsSection.sync => strings.get(PaperTodoStringKeys.webDavSync),
    };
  }

  IconData _settingsSectionIcon(_SettingsSection section) {
    return switch (section) {
      _SettingsSection.display => Icons.palette_outlined,
      _SettingsSection.todoAndNotes => Icons.checklist_outlined,
      _SettingsSection.capsules => Icons.view_agenda_outlined,
      _SettingsSection.general => Icons.tune_outlined,
      _SettingsSection.sync => Icons.cloud_sync_outlined,
    };
  }

  Widget _fontFamilyField() {
    const enabled = true;
    return LayoutBuilder(
      builder: (context, constraints) {
        final optionsWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 520.0;
        return RawAutocomplete<String>(
          textEditingController: _fontFamilyController,
          focusNode: _fontFamilyFocusNode,
          displayStringForOption: (option) => option,
          optionsBuilder: (textEditingValue) {
            if (!enabled || _installedFontFamilies.isEmpty) {
              return const Iterable<String>.empty();
            }
            final query = normalizeSystemFontFamilyName(
              textEditingValue.text,
            ).toLowerCase();
            if (query.isEmpty) {
              return _installedFontFamilies.take(40);
            }
            return _installedFontFamilies
                .where((family) => family.toLowerCase().contains(query))
                .take(40);
          },
          onSelected: (fontFamily) {
            setState(() {
              _uiFontPreset = UiFontPresets.defaultPreset;
              _fontFamilyController.text = fontFamily;
            });
          },
          fieldViewBuilder: (
            context,
            controller,
            focusNode,
            onFieldSubmitted,
          ) {
            return TextField(
              key: const ValueKey('settings-custom-font-family-field'),
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: strings.get(PaperTodoStringKeys.customFontFamily),
                prefixIcon: const Icon(Icons.title_outlined),
                suffixIcon: _isLoadingInstalledFontFamilies
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_installedFontFamilies.isEmpty
                        ? null
                        : const Icon(Icons.arrow_drop_down)),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final fontOptions = options.toList(growable: false);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: optionsWidth,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: fontOptions.length,
                      itemBuilder: (context, index) {
                        final fontFamily = fontOptions[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            fontFamily,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => onSelected(fontFamily),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _hotKeyCaptureField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
  }) {
    return Focus(
      onKeyEvent: (_, event) => _handleHotKeyCapture(controller, event),
      child: TextField(
        controller: controller,
        readOnly: true,
        showCursor: false,
        enableInteractiveSelection: false,
        onTap: () {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        },
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: labelText,
          prefixIcon: Icon(icon),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: _enableToolTips
                      ? strings.get(PaperTodoStringKeys.actionClear)
                      : null,
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(controller.clear),
                ),
        ),
      ),
    );
  }

  KeyEventResult _handleHotKeyCapture(
    TextEditingController controller,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      setState(controller.clear);
      return KeyEventResult.handled;
    }

    if (_isHotKeyModifierKey(key)) {
      return KeyEventResult.handled;
    }

    final keyboard = HardwareKeyboard.instance;
    final parts = <String>[
      if (keyboard.isControlPressed) 'Ctrl',
      if (keyboard.isAltPressed) 'Alt',
      if (keyboard.isShiftPressed) 'Shift',
      if (keyboard.isMetaPressed) 'Win',
    ];
    if (parts.isEmpty) {
      return KeyEventResult.handled;
    }

    final keyName = _hotKeyNameForKey(key);
    if (keyName == null) {
      return KeyEventResult.handled;
    }
    parts.add(keyName);
    final value = parts.join('+');
    setState(() {
      controller.text = value;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: value.length,
      );
    });
    return KeyEventResult.handled;
  }

  bool _isHotKeyModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  String? _hotKeyNameForKey(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.length == 1 && RegExp(r'^[A-Za-z0-9]$').hasMatch(label)) {
      return label.toUpperCase();
    }
    if (RegExp(r'^F(?:[1-9]|1[0-9]|2[0-4])$').hasMatch(label)) {
      return label.toUpperCase();
    }

    final namedKeys = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.numpad0: 'Numpad0',
      LogicalKeyboardKey.numpad1: 'Numpad1',
      LogicalKeyboardKey.numpad2: 'Numpad2',
      LogicalKeyboardKey.numpad3: 'Numpad3',
      LogicalKeyboardKey.numpad4: 'Numpad4',
      LogicalKeyboardKey.numpad5: 'Numpad5',
      LogicalKeyboardKey.numpad6: 'Numpad6',
      LogicalKeyboardKey.numpad7: 'Numpad7',
      LogicalKeyboardKey.numpad8: 'Numpad8',
      LogicalKeyboardKey.numpad9: 'Numpad9',
      LogicalKeyboardKey.numpadAdd: 'NumpadPlus',
      LogicalKeyboardKey.numpadSubtract: 'NumpadMinus',
      LogicalKeyboardKey.numpadMultiply: 'NumpadMultiply',
      LogicalKeyboardKey.numpadDivide: 'NumpadDivide',
      LogicalKeyboardKey.numpadDecimal: 'NumpadDecimal',
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.tab: 'Tab',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.numpadEnter: 'Enter',
      LogicalKeyboardKey.insert: 'Insert',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.pageUp: 'PageUp',
      LogicalKeyboardKey.pageDown: 'PageDown',
      LogicalKeyboardKey.arrowUp: 'Up',
      LogicalKeyboardKey.arrowDown: 'Down',
      LogicalKeyboardKey.arrowLeft: 'Left',
      LogicalKeyboardKey.arrowRight: 'Right',
      LogicalKeyboardKey.printScreen: 'PrintScreen',
      LogicalKeyboardKey.capsLock: 'CapsLock',
      LogicalKeyboardKey.numLock: 'NumLock',
      LogicalKeyboardKey.scrollLock: 'ScrollLock',
      LogicalKeyboardKey.equal: 'Equal',
      LogicalKeyboardKey.minus: 'Minus',
      LogicalKeyboardKey.comma: 'Comma',
      LogicalKeyboardKey.period: 'Period',
      LogicalKeyboardKey.slash: 'Slash',
      LogicalKeyboardKey.backslash: 'Backslash',
      LogicalKeyboardKey.semicolon: 'Semicolon',
      LogicalKeyboardKey.quote: 'Quote',
      LogicalKeyboardKey.bracketLeft: 'LeftBracket',
      LogicalKeyboardKey.bracketRight: 'RightBracket',
      LogicalKeyboardKey.backquote: 'Backquote',
    };
    return namedKeys[key];
  }

  Widget _adaptiveChoiceSelector({
    Key? key,
    required String labelText,
    required IconData compactIcon,
    required String selectedValue,
    required List<_SettingsChoice> choices,
    required ValueChanged<String>? onChanged,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return DropdownButtonFormField<String>(
        key: key,
        initialValue: selectedValue,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: labelText,
          prefixIcon: Icon(compactIcon),
        ),
        isExpanded: true,
        items: [
          for (final choice in choices)
            DropdownMenuItem(
              value: choice.value,
              child: Text(choice.label),
            ),
        ],
        onChanged: onChanged == null
            ? null
            : (value) => onChanged(value ?? selectedValue),
      );
    }
    return SegmentedButton<String>(
      key: key,
      segments: [
        for (final choice in choices)
          ButtonSegment(
            value: choice.value,
            icon: choice.icon == null ? null : Icon(choice.icon),
            label: Text(choice.label),
          ),
      ],
      selected: {selectedValue},
      onSelectionChanged:
          onChanged == null ? null : (selection) => onChanged(selection.single),
    );
  }

  Widget _adaptiveFieldPair({
    required Widget first,
    required Widget second,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          const SizedBox(height: 12),
          second,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }

  Widget _lineSpacingEditor({
    required Key key,
    required TextEditingController controller,
    required IconData icon,
    required String label,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,1}(?:\.\d{0,2})?')),
      ],
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        prefixIcon: Icon(icon),
        helperText: '0.8 - 5.0',
        suffixIcon: IconButton(
          tooltip: strings.get(PaperTodoStringKeys.themeColorClear),
          onPressed: () => setState(() => controller.text = '1.0'),
          icon: const Icon(Icons.restart_alt_outlined),
        ),
      ),
    );
  }

  Widget _webDavPresetSelector(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final presetItems = [
      for (final preset in WebDavPresets.all)
        DropdownMenuItem(
          value: preset.id,
          child: Text(_webDavPresetLabel(preset)),
        ),
    ];
    if (compact) {
      return DropdownButtonFormField<String>(
        key: const ValueKey('compact-webdav-preset-selector'),
        initialValue: _presetId,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: strings.get(PaperTodoStringKeys.webDavProvider),
          prefixIcon: const Icon(Icons.cloud_queue_outlined),
        ),
        isExpanded: true,
        items: presetItems,
        onChanged: (value) => _applyPreset(value ?? WebDavPresetIds.custom),
      );
    }
    return SegmentedButton<String>(
      segments: [
        for (final preset in WebDavPresets.all)
          ButtonSegment(
            value: preset.id,
            icon: Icon(
              preset.isCustom ? Icons.dns_outlined : Icons.cloud_queue_outlined,
            ),
            label: Text(_webDavPresetLabel(preset)),
          ),
      ],
      selected: {_presetId},
      onSelectionChanged: (selection) => _applyPreset(selection.single),
    );
  }

  String _webDavPresetLabel(WebDavPreset preset) {
    return preset.isCustom
        ? strings.get(PaperTodoStringKeys.generic)
        : preset.label;
  }

  void _applyPreset(String presetId) {
    setState(() {
      final preset = WebDavPresets.byId(presetId);
      _presetId = preset.id;
      final configuredPreset = WebDavPresets.configuredById(preset.id);
      if (configuredPreset != null) {
        _endpointController.text = configuredPreset.endpointText;
        _endpointErrorText = null;
        if (_rootPathController.text.trim().isEmpty ||
            _rootPathController.text.trim() == 'repapertodo') {
          _rootPathController.text = configuredPreset.defaultRootPath;
          _rootPathErrorText = null;
        }
      }
      if (!_hasWebDavFieldError) {
        _errorText = null;
      }
    });
  }

  void _clearWebDavError(WebDavSyncConfigurationIssue issue) {
    final hadIssue = switch (issue) {
      WebDavSyncConfigurationIssue.endpoint => _endpointErrorText != null,
      WebDavSyncConfigurationIssue.username => _usernameErrorText != null,
      WebDavSyncConfigurationIssue.password => _passwordErrorText != null,
      WebDavSyncConfigurationIssue.rootPath => _rootPathErrorText != null,
      WebDavSyncConfigurationIssue.encryptionPassphrase =>
        _encryptionPassphraseErrorText != null,
    };
    if (!hadIssue) {
      return;
    }
    setState(() {
      switch (issue) {
        case WebDavSyncConfigurationIssue.endpoint:
          _endpointErrorText = null;
        case WebDavSyncConfigurationIssue.username:
          _usernameErrorText = null;
        case WebDavSyncConfigurationIssue.password:
          _passwordErrorText = null;
        case WebDavSyncConfigurationIssue.rootPath:
          _rootPathErrorText = null;
        case WebDavSyncConfigurationIssue.encryptionPassphrase:
          _encryptionPassphraseErrorText = null;
      }
      if (!_hasWebDavFieldError) {
        _errorText = null;
      }
    });
  }

  bool get _hasWebDavFieldError {
    return _endpointErrorText != null ||
        _rootPathErrorText != null ||
        _usernameErrorText != null ||
        _passwordErrorText != null ||
        _encryptionPassphraseErrorText != null;
  }

  String _webDavIssueText(
    WebDavSyncConfigurationIssue issue,
    WebDavSyncSettings settings,
  ) {
    return switch (issue) {
      WebDavSyncConfigurationIssue.endpoint => settings.endpoint.trim().isEmpty
          ? strings.get(PaperTodoStringKeys.webDavIssueEndpointRequired)
          : strings.get(PaperTodoStringKeys.webDavIssueEndpointInvalid),
      WebDavSyncConfigurationIssue.username => settings.username.isEmpty
          ? strings.get(PaperTodoStringKeys.webDavIssueUsernameRequired)
          : strings.get(PaperTodoStringKeys.webDavIssueUsernameInvalid),
      WebDavSyncConfigurationIssue.password => settings.password.trim().isEmpty
          ? strings.get(PaperTodoStringKeys.webDavIssuePasswordRequired)
          : strings.get(PaperTodoStringKeys.webDavIssuePasswordInvalid),
      WebDavSyncConfigurationIssue.rootPath =>
        settings.hasProviderRootPathLengthViolation
            ? strings.format(
                PaperTodoStringKeys.webDavIssueProviderRootPathTooLong,
                [settings.providerRootPathFirstSegmentLengthLimit],
              )
            : strings.get(PaperTodoStringKeys.webDavIssueRootPathInvalid),
      WebDavSyncConfigurationIssue.encryptionPassphrase =>
        strings.get(PaperTodoStringKeys.webDavIssuePassphraseRequired),
    };
  }

  void _focusFirstWebDavIssue(Set<WebDavSyncConfigurationIssue> issues) {
    final focusNode = switch ((
      issues.contains(WebDavSyncConfigurationIssue.endpoint),
      issues.contains(WebDavSyncConfigurationIssue.rootPath),
      issues.contains(WebDavSyncConfigurationIssue.username),
      issues.contains(WebDavSyncConfigurationIssue.password),
      issues.contains(WebDavSyncConfigurationIssue.encryptionPassphrase),
    )) {
      (true, _, _, _, _) => _endpointFocusNode,
      (_, true, _, _, _) => _rootPathFocusNode,
      (_, _, true, _, _) => _usernameFocusNode,
      (_, _, _, true, _) => _passwordFocusNode,
      (_, _, _, _, true) => _encryptionPassphraseFocusNode,
      _ => null,
    };
    if (focusNode == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        focusNode.requestFocus();
      }
    });
  }

  void _save() {
    final interval = int.tryParse(_intervalController.text.trim());
    final requestTimeoutSeconds =
        int.tryParse(_requestTimeoutController.text.trim());
    final reminderInterval =
        int.tryParse(_reminderIntervalController.text.trim()) ?? 10;
    final reminderDuration =
        int.tryParse(_reminderDurationController.text.trim()) ?? 5;
    final todoLineSpacing =
        double.tryParse(_todoLineSpacingController.text.trim()) ?? 1;
    final noteLineSpacing =
        double.tryParse(_noteLineSpacingController.text.trim()) ?? 1;
    final deepCapsuleTopMargin =
        double.tryParse(_deepCapsuleTopMarginController.text.trim()) ?? 48;
    final externalMarkdownExtension =
        _tryNormalizeExtension(_externalMarkdownExtensionController.text);
    if (externalMarkdownExtension == null) {
      setState(() {
        _externalMarkdownExtensionErrorText = strings.get(
          PaperTodoStringKeys.externalMarkdownExtensionInvalid,
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _externalMarkdownExtensionFocusNode.requestFocus();
        }
      });
      return;
    }
    final settings = SyncSettings(
      enabled: _enabled,
      provider: _enabled ? SyncProviderIds.webDav : SyncProviderIds.none,
      webDav: WebDavSyncSettings(
        presetId: _presetId,
        endpoint: _endpointController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        encryptionPassphrase: _encryptionPassphraseController.text,
        rootPath: _rootPathController.text,
        autoSyncOnStart: _autoSyncOnStart,
        autoSyncIntervalMinutes: interval ?? 15,
        requestTimeoutSeconds: requestTimeoutSeconds ?? 30,
      ),
    )..normalize();

    if (_enabled && !settings.webDav.isSecurelyConfigured) {
      final issues = settings.webDav.secureConfigurationIssues;
      setState(() {
        _endpointErrorText =
            issues.contains(WebDavSyncConfigurationIssue.endpoint)
                ? _webDavIssueText(
                    WebDavSyncConfigurationIssue.endpoint,
                    settings.webDav,
                  )
                : null;
        _rootPathErrorText =
            issues.contains(WebDavSyncConfigurationIssue.rootPath)
                ? _webDavIssueText(
                    WebDavSyncConfigurationIssue.rootPath,
                    settings.webDav,
                  )
                : null;
        _usernameErrorText =
            issues.contains(WebDavSyncConfigurationIssue.username)
                ? _webDavIssueText(
                    WebDavSyncConfigurationIssue.username,
                    settings.webDav,
                  )
                : null;
        _passwordErrorText =
            issues.contains(WebDavSyncConfigurationIssue.password)
                ? _webDavIssueText(
                    WebDavSyncConfigurationIssue.password,
                    settings.webDav,
                  )
                : null;
        _encryptionPassphraseErrorText =
            issues.contains(WebDavSyncConfigurationIssue.encryptionPassphrase)
                ? _webDavIssueText(
                    WebDavSyncConfigurationIssue.encryptionPassphrase,
                    settings.webDav,
                  )
                : null;
        _errorText = strings.get(PaperTodoStringKeys.webDavIssueSummary);
      });
      _focusFirstWebDavIssue(issues);
      return;
    }

    Navigator.of(context).pop(
      SyncSettingsDialogResult(
        dataDirectoryPath: _dataDirectoryController.text.trim(),
        sync: settings,
        theme: _theme,
        colorScheme: _colorScheme,
        customThemeColorHex:
            _normalizeColorHex(_customThemeColorController.text),
        markdownRenderMode: _markdownRenderMode,
        todoVisualSize: _todoVisualSize,
        uiFontPreset: _uiFontPreset,
        systemFontFamilyName: normalizeSystemFontFamilyName(
          _fontFamilyController.text,
        ),
        externalMarkdownExtension: externalMarkdownExtension,
        zoom: _zoom,
        maxTitleLength: _maxTitleLength.round().clamp(2, 20).toInt(),
        enableToolTips: _enableToolTips,
        enableAnimations: _enableAnimations,
        todoLineSpacing: todoLineSpacing.clamp(0.8, 5.0).toDouble(),
        noteLineSpacing: noteLineSpacing.clamp(0.8, 5.0).toDouble(),
        showTodoDueRelativeTime: _showTodoDueRelativeTime,
        todoDueYearDisplayMode: _todoDueYearDisplayMode,
        useTodoReminderInterval: _useTodoReminderInterval,
        todoReminderIntervalValue: reminderInterval.clamp(1, 240).toInt(),
        todoReminderIntervalUnit: _todoReminderIntervalUnit,
        todoReminderScope: _todoReminderScope,
        todoReminderBubbleDurationSeconds:
            reminderDuration.clamp(1, 600).toInt(),
        showTopBarNewTodoButton: _showTopBarNewTodoButton,
        showTopBarNewNoteButton: _showTopBarNewNoteButton,
        showTopBarExternalOpenButton: _showTopBarExternalOpenButton,
        useCapsuleMode: _useCapsuleMode,
        useDeepCapsuleMode: _useCapsuleMode && _useDeepCapsuleMode,
        useCapsuleCollapseAll: _useCapsuleMode && _useCapsuleCollapseAll,
        capsuleCollapseAllActive: _useCapsuleMode &&
            _useCapsuleCollapseAll &&
            _capsuleCollapseAllActive,
        deepCapsuleSide: DeepCapsuleSides.normalize(_deepCapsuleSide),
        deepCapsuleStartTopMargin:
            deepCapsuleTopMargin.clamp(8, 10000).toDouble(),
        deepCapsuleMonitorDeviceName: _useCapsuleMode && _useDeepCapsuleMode
            ? _deepCapsuleMonitorController.text.trim()
            : '',
        showDeepCapsuleWhileExpanded: _useCapsuleMode && _useDeepCapsuleMode
            ? _showDeepCapsuleWhileExpanded
            : false,
        collapseExpandedDeepCapsuleOnClick:
            _useCapsuleMode && _useDeepCapsuleMode
                ? _collapseExpandedDeepCapsuleOnClick
                : false,
        hideDeepCapsulesWhenCovered: _useCapsuleMode && _useDeepCapsuleMode
            ? _hideDeepCapsulesWhenCovered
            : false,
        hideDeepCapsulesWhenFullscreen: _useCapsuleMode && _useDeepCapsuleMode
            ? _hideDeepCapsulesWhenFullscreen
            : false,
        startAtLogin: _startAtLogin,
        hideFromWindowSwitcher: _hideFromWindowSwitcher,
        fullscreenTopmostMode: _fullscreenTopmostMode,
        pinnedTodoHotKey: _pinnedTodoHotKeyController.text.trim(),
        pinnedNoteHotKey: _pinnedNoteHotKeyController.text.trim(),
        runLinkedScriptCapsulesOnClick: _runLinkedScriptCapsulesOnClick,
        usePersistentPowerShellProcess: _usePersistentPowerShellProcess,
        preferPowerShell7: _preferPowerShell7,
        hideScriptRunWindow: _hideScriptRunWindow,
        enableTodoNoteLinks: _enableTodoNoteLinks,
        showLinkedNoteName: _showLinkedNoteName,
        allowLongLinkedNoteTitles: _allowLongLinkedNoteTitles,
        hideLinkedNotesFromCapsules: _hideLinkedNotesFromCapsules,
      ),
    );
  }

  String _normalizeTheme(String theme) {
    return switch (theme.trim().toLowerCase()) {
      'light' => 'light',
      'dark' => 'dark',
      'system' => 'system',
      _ => 'system',
    };
  }

  String? _tryNormalizeExtension(String extension) {
    var value = extension.trim();
    if (value.isEmpty) {
      return '.md';
    }
    if (value.startsWith('*.')) {
      value = value.substring(1);
    }
    if (!value.startsWith('.')) {
      value = '.$value';
    }
    if (value.length < 2 ||
        value.length > 120 ||
        value.endsWith('.') ||
        value.endsWith(' ') ||
        _hasInvalidFileNameCharacter(value)) {
      return null;
    }
    return value.toLowerCase();
  }

  bool _hasInvalidFileNameCharacter(String value) {
    const invalid = {'<', '>', ':', '"', '/', '\\', '|', '?', '*'};
    return value.runes.any((rune) {
      if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
        return true;
      }
      return invalid.contains(String.fromCharCode(rune));
    });
  }

  String _normalizeColorHex(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final withoutPrefix =
        trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(withoutPrefix)) {
      return '';
    }
    return '#${withoutPrefix.toUpperCase()}';
  }
}

enum _SettingsSection {
  display,
  todoAndNotes,
  capsules,
  general,
  sync,
}

class _SettingsCheckboxTile extends StatelessWidget {
  const _SettingsCheckboxTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.secondary,
    this.contentPadding,
  });

  final Widget title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: contentPadding,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: secondary,
      dense: true,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
      title: title,
      value: value,
      onChanged: onChanged == null
          ? null
          : (nextValue) => onChanged!(nextValue ?? false),
    );
  }
}

class _SettingsChoice {
  const _SettingsChoice({
    required this.value,
    required this.label,
    this.icon,
  });

  final String value;
  final String label;
  final IconData? icon;
}

class _SettingsHelpIcon extends StatelessWidget {
  const _SettingsHelpIcon({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      child: const Icon(Icons.info_outline),
    );
  }
}

class _SettingsSlider extends StatelessWidget {
  const _SettingsSlider({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(label)),
                    Text(valueLabel),
                  ],
                ),
                Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: valueLabel,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
