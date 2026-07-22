import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model/app_state.dart';
import '../core/model/paper_constants.dart';
import '../core/model/sync_settings.dart';
import '../core/model/webdav_presets.dart';
import '../platform/platform_services.dart';
import 'papertodo_strings.dart';
import 'papertodo_theme.dart';

typedef InstalledFontFamilyLoader = Future<List<String>> Function();
typedef DataDirectoryPicker = Future<String?> Function(String currentPath);
typedef CustomThemeColorPicker = Future<String?> Function(
  String initialColorHex,
);
typedef SettingsAuthorLinkOpener = Future<void> Function();

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
  required bool supportsCapsules,
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
  CustomThemeColorPicker? pickCustomThemeColor,
  SettingsAuthorLinkOpener? openAuthorLink,
}) {
  return showDialog<SyncSettingsDialogResult>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    useSafeArea: false,
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
      supportsCapsules: supportsCapsules,
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
      pickCustomThemeColor: pickCustomThemeColor,
      openAuthorLink: openAuthorLink,
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
    required this.supportsCapsules,
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
    this.pickCustomThemeColor,
    this.openAuthorLink,
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
  final bool supportsCapsules;
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
  final CustomThemeColorPicker? pickCustomThemeColor;
  final SettingsAuthorLinkOpener? openAuthorLink;

  @override
  State<SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends State<SyncSettingsDialog> {
  _SettingsSection _selectedSettingsSection = _SettingsSection.display;
  final ScrollController _settingsContentScrollController = ScrollController();
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
      text: _lineSpacingText(_todoLineSpacing),
    );
    _noteLineSpacingController = TextEditingController(
      text: _lineSpacingText(_noteLineSpacing),
    );
    _dataDirectoryController = TextEditingController(
      text: widget.initialDataDirectoryPath,
    );
    _loadInstalledFontFamilies();
  }

  @override
  void dispose() {
    _settingsContentScrollController.dispose();
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
    final baseTheme = Theme.of(context);
    final colorScheme = baseTheme.colorScheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final desktopLayout = mediaSize.width >= 720;
    final contentHeight = (mediaSize.height - 68).clamp(240.0, 680.0);
    final settingsTheme = baseTheme.copyWith(
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 38, minHeight: 34),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 38, minHeight: 34),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 30),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 30),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
      checkboxTheme: baseTheme.checkboxTheme.copyWith(
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: colorScheme.outline, width: 1.2),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        minLeadingWidth: 24,
        horizontalTitleGap: 4,
        minVerticalPadding: 0,
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        titleTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
          fontSize: 13,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const WidgetStatePropertyAll(Size(44, 30)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          textStyle: WidgetStatePropertyAll(
            baseTheme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
    return Theme(
      data: settingsTheme,
      child: _SettingsWindowDialog(
        title: Row(
          children: [
            Expanded(
              child: Transform.translate(
                key: const ValueKey('settings-title-metrics'),
                offset: const Offset(0, 1.5),
                child: Text(
                  strings.get(PaperTodoStringKeys.actionSettings),
                  overflow: TextOverflow.ellipsis,
                  style: baseTheme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            _SettingsCloseButton(
              tooltip: strings.get(PaperTodoStringKeys.actionClose),
              onPressed: _save,
            ),
          ],
        ),
        content: SizedBox(
          width: desktopLayout ? 760 : 520,
          height: contentHeight,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: desktopLayout ? 146 : 44,
                      child: Transform.translate(
                        key: const ValueKey('settings-navigation-metrics'),
                        offset: const Offset(1, -1),
                        child: _settingsNavigation(compact: !desktopLayout),
                      ),
                    ),
                    Transform.translate(
                      key: const ValueKey('settings-navigation-divider'),
                      offset: const Offset(1, -1),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 14, 5),
                        child: SizedBox(
                          width: 1,
                          child: ColoredBox(
                            color: PaperTodoThemeColors.of(context)
                                .paperBorder
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ScrollbarTheme(
                        key: const ValueKey('settings-scrollbar-theme'),
                        data: ScrollbarTheme.of(context).copyWith(
                          mainAxisMargin: 9,
                          crossAxisMargin: 3,
                          thumbColor: WidgetStateProperty.resolveWith(
                            (states) {
                              final active =
                                  states.contains(WidgetState.dragged) ||
                                      states.contains(WidgetState.hovered);
                              return (active
                                      ? const Color(0xFF96784F)
                                      : const Color(0xFFB39B74))
                                  .withValues(
                                alpha: states.contains(WidgetState.dragged)
                                    ? 0.64
                                    : states.contains(WidgetState.hovered)
                                        ? 0.54
                                        : 0.34,
                              );
                            },
                          ),
                        ),
                        child: Scrollbar(
                          controller: _settingsContentScrollController,
                          thumbVisibility: desktopLayout,
                          child: SingleChildScrollView(
                            key: const ValueKey('settings-content-scroll'),
                            controller: _settingsContentScrollController,
                            padding: const EdgeInsets.fromLTRB(3, 6, 13, 2),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_selectedSettingsSection ==
                                    _SettingsSection.display) ...[
                                  _settingsSectionHeader(
                                    section: _SettingsSection.display,
                                    icon: Icons.palette_outlined,
                                    label: strings.get(PaperTodoStringKeys
                                        .settingsSectionDisplay),
                                  ),
                                  const SizedBox(height: 5),
                                  _adaptiveChoiceSelector(
                                    key: const ValueKey(
                                        'settings-theme-selector'),
                                    labelText:
                                        strings.get(PaperTodoStringKeys.theme),
                                    compactIcon: Icons.brightness_auto_outlined,
                                    selectedValue: _theme,
                                    choices: [
                                      _SettingsChoice(
                                        value: 'system',
                                        label: strings.get(
                                            PaperTodoStringKeys.themeSystem),
                                        icon: Icons.brightness_auto_outlined,
                                      ),
                                      _SettingsChoice(
                                        value: 'light',
                                        label: strings.get(
                                            PaperTodoStringKeys.themeLight),
                                        icon: Icons.light_mode_outlined,
                                      ),
                                      _SettingsChoice(
                                        value: 'dark',
                                        label: strings
                                            .get(PaperTodoStringKeys.themeDark),
                                        icon: Icons.dark_mode_outlined,
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _theme = value),
                                    tipKey: PaperTodoStringKeys.tipThemeMode,
                                  ),
                                  const SizedBox(height: 12),
                                  Transform.translate(
                                    key: const ValueKey(
                                        'settings-theme-color-label-metrics'),
                                    offset: const Offset(0, 2),
                                    child: _settingsLabelWithHint(
                                      label: strings.get(
                                          PaperTodoStringKeys.customThemeColor),
                                      tipKey: PaperTodoStringKeys
                                          .tipCustomThemeColor,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontSize: 11,
                                            letterSpacing: -0.01,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _customThemeColorEditor(),
                                  const SizedBox(height: 16),
                                  _fontFamilyField(),
                                  const SizedBox(height: 14),
                                  _adaptiveChoiceSelector(
                                    key: const ValueKey(
                                        'settings-markdown-mode-selector'),
                                    labelText: strings
                                        .get(PaperTodoStringKeys.markdownMode),
                                    compactIcon: Icons.article_outlined,
                                    labelLetterSpacing: -0.02,
                                    labelPaintOffset: const Offset(1, 0),
                                    labelMetricsKey: const ValueKey(
                                      'settings-markdown-label-metrics',
                                    ),
                                    selectedValue: _markdownRenderMode,
                                    choices: [
                                      _SettingsChoice(
                                        value: MarkdownRenderModes.off,
                                        label: strings.get(
                                            PaperTodoStringKeys.markdownOff),
                                        icon: Icons.edit_outlined,
                                      ),
                                      _SettingsChoice(
                                        value: MarkdownRenderModes.basic,
                                        label: strings
                                            .get(PaperTodoStringKeys.basic),
                                        icon: Icons.article_outlined,
                                      ),
                                      _SettingsChoice(
                                        value: MarkdownRenderModes.enhanced,
                                        label: strings
                                            .get(PaperTodoStringKeys.enhanced),
                                        icon: Icons.vertical_split_outlined,
                                      ),
                                    ],
                                    onChanged: (value) => setState(
                                        () => _markdownRenderMode = value),
                                    tipKey:
                                        PaperTodoStringKeys.tipMarkdownRender,
                                  ),
                                  if (widget.supportsFullscreenTopmostMode) ...[
                                    const SizedBox(height: 14),
                                    _adaptiveChoiceSelector(
                                      key: const ValueKey(
                                          'settings-fullscreen-topmost-selector'),
                                      labelText: strings.get(PaperTodoStringKeys
                                          .fullscreenTopmostMode),
                                      compactIcon:
                                          Icons.fullscreen_exit_outlined,
                                      labelLetterSpacing: -0.003,
                                      selectedValue: _fullscreenTopmostMode,
                                      choices: [
                                        _SettingsChoice(
                                          value: FullscreenTopmostModes.avoid,
                                          label: strings.get(PaperTodoStringKeys
                                              .avoidFullscreen),
                                          icon: Icons.fullscreen_exit_outlined,
                                        ),
                                        _SettingsChoice(
                                          value:
                                              FullscreenTopmostModes.stayOnTop,
                                          label: strings.get(
                                              PaperTodoStringKeys.stayOnTop),
                                          icon: Icons.push_pin_outlined,
                                        ),
                                      ],
                                      onChanged: (value) => setState(
                                          () => _fullscreenTopmostMode = value),
                                      tipKey: PaperTodoStringKeys
                                          .tipFullscreenTopmostMode,
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  _adaptiveChoiceSelector(
                                    key: const ValueKey(
                                        'settings-todo-visual-size-selector'),
                                    labelText: strings.get(
                                        PaperTodoStringKeys.todoVisualSize),
                                    compactIcon: Icons.format_size_outlined,
                                    labelLetterSpacing: -0.001,
                                    selectedValue: _todoVisualSize,
                                    choices: [
                                      _SettingsChoice(
                                        value: TodoVisualSizes.small,
                                        label: strings
                                            .get(PaperTodoStringKeys.small),
                                      ),
                                      _SettingsChoice(
                                        value: TodoVisualSizes.medium,
                                        label: strings
                                            .get(PaperTodoStringKeys.medium),
                                      ),
                                      _SettingsChoice(
                                        value: TodoVisualSizes.large,
                                        label: strings
                                            .get(PaperTodoStringKeys.large),
                                      ),
                                      _SettingsChoice(
                                        value: TodoVisualSizes.extraLarge,
                                        label:
                                            strings.get(PaperTodoStringKeys.xl),
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _todoVisualSize = value),
                                    tipKey:
                                        PaperTodoStringKeys.tipTodoVisualSize,
                                  ),
                                  const SizedBox(height: 14),
                                  Column(
                                    children: [
                                      _lineSpacingEditor(
                                        key: const ValueKey(
                                            'settings-todo-line-spacing'),
                                        surfaceKey: const ValueKey(
                                            'settings-todo-line-spacing-surface'),
                                        controller: _todoLineSpacingController,
                                        label: strings.get(
                                            PaperTodoStringKeys.todoSpacing),
                                        tipKey: PaperTodoStringKeys
                                            .tipTodoLineSpacing,
                                        labelLetterSpacing: -0.001,
                                      ),
                                      const SizedBox(height: 14),
                                      _lineSpacingEditor(
                                        key: const ValueKey(
                                            'settings-note-line-spacing'),
                                        surfaceKey: const ValueKey(
                                            'settings-note-line-spacing-surface'),
                                        controller: _noteLineSpacingController,
                                        label: strings.get(
                                            PaperTodoStringKeys.noteSpacing),
                                        tipKey: PaperTodoStringKeys
                                            .tipNoteLineSpacing,
                                        labelLetterSpacing: -0.001,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _settingsGroupLabel(
                                    strings.get(PaperTodoStringKeys
                                        .settingsSectionTopBarButtons),
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(
                                        PaperTodoStringKeys.tipNewTodoButton),
                                    title: _topBarButtonLabel(
                                      PaperTodoStringKeys.topBarNewTodo,
                                    ),
                                    value: _showTopBarNewTodoButton,
                                    onChanged: (value) => setState(
                                        () => _showTopBarNewTodoButton = value),
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(
                                        PaperTodoStringKeys.tipNewNoteButton),
                                    title: _topBarButtonLabel(
                                      PaperTodoStringKeys.topBarNewNote,
                                    ),
                                    value: _showTopBarNewNoteButton,
                                    onChanged: (value) => setState(
                                        () => _showTopBarNewNoteButton = value),
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipExternalOpenButton),
                                    title: _topBarButtonLabel(
                                      PaperTodoStringKeys.topBarOpenSurface,
                                    ),
                                    value: _showTopBarExternalOpenButton,
                                    onChanged: (value) => setState(() =>
                                        _showTopBarExternalOpenButton = value),
                                  ),
                                ],
                                if (widget.supportsCapsules &&
                                    _selectedSettingsSection ==
                                        _SettingsSection.capsules) ...[
                                  _settingsSectionHeader(
                                    section: _SettingsSection.capsules,
                                    icon: Icons.view_agenda_outlined,
                                    label: strings.get(PaperTodoStringKeys
                                        .settingsSectionCapsule),
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(
                                        PaperTodoStringKeys.tipCapsuleMode),
                                    title: Text(strings
                                        .get(PaperTodoStringKeys.capsuleMode)),
                                    value: _useCapsuleMode,
                                    onChanged: (value) => setState(() {
                                      _useCapsuleMode = value;
                                      if (!value) {
                                        _useDeepCapsuleMode = false;
                                        _useCapsuleCollapseAll = false;
                                        _capsuleCollapseAllActive = false;
                                        _showDeepCapsuleWhileExpanded = false;
                                        _collapseExpandedDeepCapsuleOnClick =
                                            false;
                                        _hideDeepCapsulesWhenCovered = false;
                                        _hideDeepCapsulesWhenFullscreen = false;
                                      }
                                    }),
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(
                                        PaperTodoStringKeys.tipDeepCapsuleMode),
                                    title: Text(strings.get(
                                        PaperTodoStringKeys.deepCapsuleMode)),
                                    value: _useDeepCapsuleMode,
                                    onChanged: _useCapsuleMode
                                        ? (value) => setState(() {
                                              _useDeepCapsuleMode = value;
                                              if (!value) {
                                                _showDeepCapsuleWhileExpanded =
                                                    false;
                                                _collapseExpandedDeepCapsuleOnClick =
                                                    false;
                                                _hideDeepCapsulesWhenCovered =
                                                    false;
                                                _hideDeepCapsulesWhenFullscreen =
                                                    false;
                                              }
                                            })
                                        : null,
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipShowDeepCapsuleWhileExpanded),
                                    title: Text(
                                      strings.get(PaperTodoStringKeys
                                          .showDeepCapsuleWhileExpanded),
                                    ),
                                    value: _showDeepCapsuleWhileExpanded,
                                    onChanged:
                                        _useCapsuleMode && _useDeepCapsuleMode
                                            ? (value) => setState(() =>
                                                _showDeepCapsuleWhileExpanded =
                                                    value)
                                            : null,
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipCollapseExpandedDeepCapsuleOnClick),
                                    title: Text(
                                      strings.get(
                                        PaperTodoStringKeys
                                            .collapseExpandedDeepCapsuleOnClick,
                                      ),
                                    ),
                                    value: _collapseExpandedDeepCapsuleOnClick,
                                    onChanged: _useCapsuleMode &&
                                            _useDeepCapsuleMode &&
                                            _showDeepCapsuleWhileExpanded
                                        ? (value) => setState(
                                              () =>
                                                  _collapseExpandedDeepCapsuleOnClick =
                                                      value,
                                            )
                                        : null,
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipHideDeepCapsulesWhenCovered),
                                    title: Text(
                                      strings.get(PaperTodoStringKeys
                                          .hideCoveredDeepCapsules),
                                    ),
                                    value: _hideDeepCapsulesWhenCovered,
                                    onChanged:
                                        _useCapsuleMode && _useDeepCapsuleMode
                                            ? (value) => setState(() =>
                                                _hideDeepCapsulesWhenCovered =
                                                    value)
                                            : null,
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipCapsuleCollapseAll),
                                    title: Text(strings.get(PaperTodoStringKeys
                                        .collapseAllControl)),
                                    value: _useCapsuleCollapseAll,
                                    onChanged: _useCapsuleMode &&
                                            _useDeepCapsuleMode
                                        ? (value) => setState(() {
                                              _useCapsuleCollapseAll = value;
                                              if (!value) {
                                                _capsuleCollapseAllActive =
                                                    false;
                                              }
                                            })
                                        : null,
                                  ),
                                  const SizedBox(height: 4),
                                  _settingsLabelWithHint(
                                    label: strings.get(
                                        PaperTodoStringKeys.maxTitleLength),
                                    tipKey:
                                        PaperTodoStringKeys.tipMaxTitleLength,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 5),
                                  _SettingsStepper(
                                    key: const ValueKey(
                                        'settings-max-title-length'),
                                    valueLabel:
                                        _maxTitleLength.round().toString(),
                                    onDecrease: () {
                                      if (_maxTitleLength > 2) {
                                        setState(() => _maxTitleLength -= 1);
                                      }
                                    },
                                    onIncrease: () {
                                      if (_maxTitleLength < 20) {
                                        setState(() => _maxTitleLength += 1);
                                      }
                                    },
                                  ),
                                ],
                                if (_selectedSettingsSection ==
                                    _SettingsSection.general) ...[
                                  _settingsSectionHeader(
                                    section: _SettingsSection.general,
                                    icon: Icons.tune_outlined,
                                    label: strings.get(PaperTodoStringKeys
                                        .settingsSectionGeneral),
                                  ),
                                  if (widget.supportsStartAtLogin)
                                    _SettingsCheckboxTile(
                                      contentPadding: EdgeInsets.zero,
                                      secondary: _settingsHelp(
                                          PaperTodoStringKeys.tipStartup),
                                      title: Text(strings.get(
                                          PaperTodoStringKeys.startAtLogin)),
                                      value: _startAtLogin,
                                      onChanged: (value) =>
                                          setState(() => _startAtLogin = value),
                                    ),
                                  if (widget.supportsHideFromWindowSwitcher)
                                    _SettingsCheckboxTile(
                                      contentPadding: EdgeInsets.zero,
                                      secondary: _settingsHelp(
                                        PaperTodoStringKeys
                                            .tipHidePapersFromWindowSwitcher,
                                      ),
                                      title: Text(
                                        strings.get(PaperTodoStringKeys
                                            .hideFromTaskSwitcher),
                                      ),
                                      value: _hideFromWindowSwitcher,
                                      onChanged: (value) => setState(() =>
                                          _hideFromWindowSwitcher = value),
                                    ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(
                                        PaperTodoStringKeys.tipEnableToolTips),
                                    title: Text(strings
                                        .get(PaperTodoStringKeys.tooltips)),
                                    value: _enableToolTips,
                                    onChanged: (value) =>
                                        setState(() => _enableToolTips = value),
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipEnableAnimations),
                                    title: Text(strings
                                        .get(PaperTodoStringKeys.animations)),
                                    value: _enableAnimations,
                                    onChanged: (value) => setState(
                                        () => _enableAnimations = value),
                                  ),
                                  if (widget.supportsGlobalHotkeys) ...[
                                    _settingsLabeledControl(
                                      label: strings.get(
                                          PaperTodoStringKeys.pinnedTodoHotkey),
                                      tipKey: PaperTodoStringKeys
                                          .tipPinnedTodoHotKey,
                                      topSpacing: 5,
                                      child: _hotKeyCaptureField(
                                        key: const ValueKey(
                                            'settings-pinned-todo-hotkey'),
                                        controller: _pinnedTodoHotKeyController,
                                      ),
                                    ),
                                    _settingsLabeledControl(
                                      label: strings.get(
                                          PaperTodoStringKeys.pinnedNoteHotkey),
                                      tipKey: PaperTodoStringKeys
                                          .tipPinnedNoteHotKey,
                                      child: _hotKeyCaptureField(
                                        key: const ValueKey(
                                            'settings-pinned-note-hotkey'),
                                        controller: _pinnedNoteHotKeyController,
                                      ),
                                    ),
                                  ],
                                  _settingsGroupLabel(
                                    strings.get(PaperTodoStringKeys
                                        .settingsSectionExternalOpen),
                                  ),
                                  _settingsLabeledControl(
                                    label: strings.get(PaperTodoStringKeys
                                        .externalMarkdownExtension),
                                    tipKey: PaperTodoStringKeys
                                        .tipExternalExtension,
                                    bottomSpacing: 8,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _settingsCompactTextField(
                                          fieldBuilder: (decoration) =>
                                              TextField(
                                            key: const ValueKey(
                                                'settings-external-markdown-extension'),
                                            controller:
                                                _externalMarkdownExtensionController,
                                            focusNode:
                                                _externalMarkdownExtensionFocusNode,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              height: 1,
                                            ),
                                            textAlignVertical:
                                                TextAlignVertical.center,
                                            onChanged: (_) {
                                              if (_externalMarkdownExtensionErrorText ==
                                                  null) {
                                                return;
                                              }
                                              setState(() =>
                                                  _externalMarkdownExtensionErrorText =
                                                      null);
                                            },
                                            decoration: decoration,
                                          ),
                                        ),
                                        if (_externalMarkdownExtensionErrorText !=
                                            null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text(
                                              _externalMarkdownExtensionErrorText!,
                                              style: TextStyle(
                                                color: colorScheme.error,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (widget.supportsScriptCapsules) ...[
                                    _settingsGroupLabel(
                                      strings.get(PaperTodoStringKeys
                                          .settingsSectionScriptCapsule),
                                    ),
                                    _SettingsCheckboxTile(
                                      contentPadding: EdgeInsets.zero,
                                      secondary: _settingsHelp(
                                        PaperTodoStringKeys
                                            .tipPersistentPowerShellProcess,
                                      ),
                                      title: Text(
                                        strings.get(
                                          PaperTodoStringKeys
                                              .persistentPowerShellProcess,
                                        ),
                                      ),
                                      value: _usePersistentPowerShellProcess,
                                      onChanged: (value) => setState(
                                        () => _usePersistentPowerShellProcess =
                                            value,
                                      ),
                                    ),
                                    _SettingsCheckboxTile(
                                      contentPadding: EdgeInsets.zero,
                                      secondary: _settingsHelp(
                                          PaperTodoStringKeys
                                              .tipPreferPowerShell7),
                                      title: Text(strings.get(
                                          PaperTodoStringKeys
                                              .preferPowerShell7)),
                                      value: _preferPowerShell7,
                                      onChanged: (value) => setState(
                                          () => _preferPowerShell7 = value),
                                    ),
                                    _SettingsCheckboxTile(
                                      contentPadding: EdgeInsets.zero,
                                      secondary: _settingsHelp(
                                          PaperTodoStringKeys
                                              .tipHideScriptRunWindow),
                                      title: Text(strings.get(
                                          PaperTodoStringKeys
                                              .hideScriptRunWindow)),
                                      value: _hideScriptRunWindow,
                                      onChanged: (value) => setState(
                                          () => _hideScriptRunWindow = value),
                                    ),
                                  ],
                                  if (widget
                                      .supportsDataDirectorySelection) ...[
                                    _settingsGroupLabel(
                                      strings.get(
                                          PaperTodoStringKeys.dataDirectory),
                                    ),
                                    _dataDirectoryEditor(),
                                  ],
                                ],
                                if (_selectedSettingsSection ==
                                    _SettingsSection.todoAndNotes) ...[
                                  _settingsSectionHeader(
                                    section: _SettingsSection.todoAndNotes,
                                    icon: Icons.checklist_outlined,
                                    label: strings.get(PaperTodoStringKeys
                                        .settingsSectionTodoAndNotes),
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipEnableTodoNoteLinks),
                                    title: Text(strings.get(
                                        PaperTodoStringKeys.todoNoteLinks)),
                                    value: _enableTodoNoteLinks,
                                    onChanged: (value) => setState(
                                        () => _enableTodoNoteLinks = value),
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipShowTodoDueRelativeTime),
                                    title: Text(strings.get(
                                        PaperTodoStringKeys.relativeDueDates)),
                                    value: _showTodoDueRelativeTime,
                                    onChanged: (value) => setState(
                                        () => _showTodoDueRelativeTime = value),
                                  ),
                                  const SizedBox(height: 5),
                                  _adaptiveChoiceSelector(
                                    key: const ValueKey(
                                        'settings-due-year-selector'),
                                    labelText: strings.get(
                                        PaperTodoStringKeys.dueYearDisplay),
                                    compactIcon: Icons.event_outlined,
                                    selectedValue: _todoDueYearDisplayMode,
                                    choices: [
                                      _SettingsChoice(
                                        value: TodoDueYearDisplayModes.none,
                                        label: strings
                                            .get(PaperTodoStringKeys.noYear),
                                      ),
                                      _SettingsChoice(
                                        value: TodoDueYearDisplayModes.short,
                                        label:
                                            strings.get(PaperTodoStringKeys.yy),
                                      ),
                                      _SettingsChoice(
                                        value: TodoDueYearDisplayModes.full,
                                        label: strings
                                            .get(PaperTodoStringKeys.yyyy),
                                      ),
                                    ],
                                    onChanged: (value) => setState(
                                        () => _todoDueYearDisplayMode = value),
                                    tipKey: PaperTodoStringKeys
                                        .tipTodoDueYearDisplay,
                                  ),
                                  const SizedBox(height: 8),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipUseTodoReminderInterval),
                                    title: Text(strings.get(
                                        PaperTodoStringKeys.todoReminders)),
                                    value: _useTodoReminderInterval,
                                    onChanged: (value) => setState(
                                        () => _useTodoReminderInterval = value),
                                  ),
                                  Column(
                                    children: [
                                      _settingsLabeledControl(
                                        label: strings.get(PaperTodoStringKeys
                                            .reminderInterval),
                                        tipKey: PaperTodoStringKeys
                                            .tipTodoReminderInterval,
                                        topSpacing: 6,
                                        bottomSpacing: 14,
                                        child: _settingsCompactTextField(
                                          fieldBuilder: (decoration) =>
                                              TextField(
                                            key: const ValueKey(
                                                'settings-reminder-interval'),
                                            controller:
                                                _reminderIntervalController,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              height: 1,
                                            ),
                                            textAlign: TextAlign.center,
                                            textAlignVertical:
                                                TextAlignVertical.center,
                                            decoration: decoration,
                                            keyboardType: TextInputType.number,
                                          ),
                                        ),
                                      ),
                                      _adaptiveChoiceSelector(
                                        key: const ValueKey(
                                            'settings-reminder-unit-selector'),
                                        labelText: strings.get(
                                            PaperTodoStringKeys.reminderUnit),
                                        compactIcon: Icons.schedule_outlined,
                                        selectedValue:
                                            _todoReminderIntervalUnit,
                                        choices: [
                                          _SettingsChoice(
                                            value: TodoReminderIntervalUnits
                                                .minutes,
                                            label: strings.get(
                                                PaperTodoStringKeys.minutes),
                                          ),
                                          _SettingsChoice(
                                            value:
                                                TodoReminderIntervalUnits.hours,
                                            label: strings
                                                .get(PaperTodoStringKeys.hours),
                                          ),
                                        ],
                                        onChanged: (value) => setState(() =>
                                            _todoReminderIntervalUnit = value),
                                        tipKey: PaperTodoStringKeys
                                            .tipTodoReminderIntervalUnit,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  _adaptiveChoiceSelector(
                                    key: const ValueKey(
                                        'settings-reminder-scope-selector'),
                                    labelText: strings
                                        .get(PaperTodoStringKeys.reminderScope),
                                    compactIcon:
                                        Icons.notifications_active_outlined,
                                    selectedValue: _todoReminderScope,
                                    choices: [
                                      _SettingsChoice(
                                        value: TodoReminderScopes.nearest,
                                        label: strings
                                            .get(PaperTodoStringKeys.nearest),
                                        icon: Icons.near_me_outlined,
                                      ),
                                      _SettingsChoice(
                                        value: TodoReminderScopes.all,
                                        label: strings
                                            .get(PaperTodoStringKeys.allDue),
                                        icon:
                                            Icons.format_list_bulleted_outlined,
                                      ),
                                    ],
                                    onChanged: (value) => setState(
                                        () => _todoReminderScope = value),
                                    tipKey: PaperTodoStringKeys
                                        .tipTodoReminderScope,
                                  ),
                                  const SizedBox(height: 10),
                                  _settingsLabeledControl(
                                    label: strings.get(PaperTodoStringKeys
                                        .reminderDisplaySeconds),
                                    tipKey: PaperTodoStringKeys
                                        .tipTodoReminderBubbleDuration,
                                    bottomSpacing: 9,
                                    child: _settingsCompactTextField(
                                      fieldBuilder: (decoration) => TextField(
                                        key: const ValueKey(
                                            'settings-reminder-duration'),
                                        controller: _reminderDurationController,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1,
                                        ),
                                        textAlign: TextAlign.center,
                                        textAlignVertical:
                                            TextAlignVertical.center,
                                        decoration: decoration,
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipShowLinkedNoteName),
                                    title: Text(strings.get(PaperTodoStringKeys
                                        .showLinkedNoteName)),
                                    value: _showLinkedNoteName,
                                    onChanged: _enableTodoNoteLinks
                                        ? (value) => setState(
                                            () => _showLinkedNoteName = value)
                                        : null,
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipAllowLongLinkedNoteTitles),
                                    title: Text(
                                      strings.get(PaperTodoStringKeys
                                          .allowLongLinkedNoteTitles),
                                    ),
                                    value: _allowLongLinkedNoteTitles,
                                    onChanged: _enableTodoNoteLinks &&
                                            _showLinkedNoteName
                                        ? (value) => setState(() =>
                                            _allowLongLinkedNoteTitles = value)
                                        : null,
                                  ),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: _settingsHelp(PaperTodoStringKeys
                                        .tipHideLinkedNotesFromCapsules),
                                    title: Text(strings.get(PaperTodoStringKeys
                                        .hideLinkedNoteCapsules)),
                                    value: _hideLinkedNotesFromCapsules,
                                    onChanged: _enableTodoNoteLinks
                                        ? (value) => setState(() =>
                                            _hideLinkedNotesFromCapsules =
                                                value)
                                        : null,
                                  ),
                                  if (widget.supportsScriptCapsules)
                                    _SettingsCheckboxTile(
                                      contentPadding: EdgeInsets.zero,
                                      secondary: _settingsHelp(
                                        PaperTodoStringKeys
                                            .tipRunLinkedScriptCapsulesOnClick,
                                      ),
                                      title: Text(
                                        strings.get(
                                          PaperTodoStringKeys
                                              .runLinkedScriptCapsulesOnClick,
                                        ),
                                      ),
                                      value: _runLinkedScriptCapsulesOnClick,
                                      onChanged: _enableTodoNoteLinks
                                          ? (value) => setState(
                                                () =>
                                                    _runLinkedScriptCapsulesOnClick =
                                                        value,
                                              )
                                          : null,
                                    ),
                                ],
                                if (_selectedSettingsSection ==
                                    _SettingsSection.sync) ...[
                                  _settingsSectionHeader(
                                    section: _SettingsSection.sync,
                                    icon: Icons.cloud_sync_outlined,
                                    label: strings
                                        .get(PaperTodoStringKeys.webDavSync),
                                  ),
                                  const SizedBox(height: 4),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(strings.get(
                                        PaperTodoStringKeys.enableWebDavSync)),
                                    value: _enabled,
                                    onChanged: (value) =>
                                        setState(() => _enabled = value),
                                  ),
                                  const SizedBox(height: 12),
                                  _webDavPresetSelector(context),
                                  const SizedBox(height: 16),
                                  _webDavSettingsTextField(
                                    controller: _endpointController,
                                    focusNode: _endpointFocusNode,
                                    enabled: _enabled,
                                    label: strings
                                        .get(PaperTodoStringKeys.webDavUrl),
                                    errorText: _endpointErrorText,
                                    onChanged: (_) => _clearWebDavError(
                                      WebDavSyncConfigurationIssue.endpoint,
                                    ),
                                    keyboardType: TextInputType.url,
                                  ),
                                  _webDavSettingsTextField(
                                    controller: _rootPathController,
                                    focusNode: _rootPathFocusNode,
                                    enabled: _enabled,
                                    label: strings
                                        .get(PaperTodoStringKeys.remoteFolder),
                                    errorText: _rootPathErrorText,
                                    onChanged: (_) => _clearWebDavError(
                                      WebDavSyncConfigurationIssue.rootPath,
                                    ),
                                  ),
                                  _webDavSettingsTextField(
                                    controller: _usernameController,
                                    focusNode: _usernameFocusNode,
                                    enabled: _enabled,
                                    label: strings
                                        .get(PaperTodoStringKeys.username),
                                    errorText: _usernameErrorText,
                                    onChanged: (_) => _clearWebDavError(
                                      WebDavSyncConfigurationIssue.username,
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                  _webDavSettingsTextField(
                                    controller: _passwordController,
                                    focusNode: _passwordFocusNode,
                                    enabled: _enabled,
                                    label: strings.get(
                                      _presetId == WebDavPresetIds.jianguoyun
                                          ? PaperTodoStringKeys
                                              .webDavAppPassword
                                          : PaperTodoStringKeys.password,
                                    ),
                                    helperText:
                                        _presetId == WebDavPresetIds.jianguoyun
                                            ? strings.get(PaperTodoStringKeys
                                                .jianguoyunAppPasswordHelper)
                                            : null,
                                    errorText: _passwordErrorText,
                                    obscureText: _obscurePassword,
                                    onChanged: (_) => _clearWebDavError(
                                      WebDavSyncConfigurationIssue.password,
                                    ),
                                    trailing: _webDavSecretToggle(
                                      enabled: _enabled,
                                      obscure: _obscurePassword,
                                      showLabelKey:
                                          PaperTodoStringKeys.showPassword,
                                      hideLabelKey:
                                          PaperTodoStringKeys.hidePassword,
                                      onPressed: () => setState(() =>
                                          _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  _webDavSettingsTextField(
                                    controller: _encryptionPassphraseController,
                                    focusNode: _encryptionPassphraseFocusNode,
                                    enabled: _enabled,
                                    label: strings.get(PaperTodoStringKeys
                                        .syncEncryptionPassphrase),
                                    helperText: strings.get(
                                        PaperTodoStringKeys.passphraseHelper),
                                    errorText: _encryptionPassphraseErrorText,
                                    obscureText: _obscureEncryptionPassphrase,
                                    onChanged: (_) => _clearWebDavError(
                                      WebDavSyncConfigurationIssue
                                          .encryptionPassphrase,
                                    ),
                                    trailing: _webDavSecretToggle(
                                      enabled: _enabled,
                                      obscure: _obscureEncryptionPassphrase,
                                      showLabelKey:
                                          PaperTodoStringKeys.showPassphrase,
                                      hideLabelKey:
                                          PaperTodoStringKeys.hidePassphrase,
                                      onPressed: () => setState(() =>
                                          _obscureEncryptionPassphrase =
                                              !_obscureEncryptionPassphrase),
                                    ),
                                  ),
                                  _adaptiveFieldPair(
                                    first: _webDavSettingsTextField(
                                      controller: _intervalController,
                                      enabled: _enabled,
                                      label: strings.get(
                                          PaperTodoStringKeys.intervalMinutes),
                                      bottomSpacing: 0,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                    ),
                                    second: _webDavSettingsTextField(
                                      controller: _requestTimeoutController,
                                      enabled: _enabled,
                                      label: strings.get(PaperTodoStringKeys
                                          .requestTimeoutSeconds),
                                      bottomSpacing: 0,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _SettingsCheckboxTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(strings
                                        .get(PaperTodoStringKeys.syncOnStart)),
                                    value: _autoSyncOnStart,
                                    onChanged: _enabled
                                        ? (value) => setState(
                                            () => _autoSyncOnStart = value)
                                        : null,
                                  ),
                                  if (_errorText != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _errorText!,
                                      style:
                                          TextStyle(color: colorScheme.error),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: _SettingsAuthorLink(
                    onPressed: widget.openAuthorLink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customThemeColorEditor() {
    final colors = PaperTodoThemeColors.of(context);
    final normalized = _normalizeColorHex(_customThemeColorController.text);
    final selectedColor = normalized.isEmpty
        ? colors.active
        : Color(int.parse('FF${normalized.substring(1)}', radix: 16));
    final currentLabel = normalized.isEmpty
        ? strings.get(PaperTodoStringKeys.themeColorDefault)
        : normalized;
    final swatch = Material(
      color: selectedColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.paperBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        key: const ValueKey('settings-theme-color-swatch'),
        onTap: _showCustomThemeColorDialog,
        child: const SizedBox(width: 58, height: 42),
      ),
    );

    return Semantics(
      label: strings.get(PaperTodoStringKeys.customThemeColor),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_enableToolTips)
            Tooltip(
              message: strings.get(PaperTodoStringKeys.themeColorPick),
              child: swatch,
            )
          else
            swatch,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  key: const ValueKey(
                    'settings-theme-color-current-label-metrics',
                  ),
                  offset: const Offset(-1, 0),
                  child: Text(
                    currentLabel,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 76),
                      child: SizedBox(
                        height: 27,
                        child: FilledButton(
                          key: const ValueKey('settings-theme-color-pick'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(76, 27),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            backgroundColor: colors.active,
                            foregroundColor: colors.paper,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          onPressed: _showCustomThemeColorDialog,
                          child: Transform.translate(
                            key: const ValueKey(
                              'settings-theme-color-pick-label-metrics',
                            ),
                            offset: const Offset(0, -0.5),
                            child: Transform.scale(
                              scaleY: 12 / 11,
                              alignment: Alignment.topCenter,
                              child: Text(
                                strings.get(
                                  PaperTodoStringKeys.themeColorPick,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 82),
                      child: SizedBox(
                        height: 27,
                        child: TextButton(
                          key: const ValueKey('settings-theme-color-clear'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(82, 27),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            backgroundColor: colors.hover,
                            foregroundColor: colors.text,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () => setState(
                            () => _customThemeColorController.clear(),
                          ),
                          child: Text(
                            strings.get(PaperTodoStringKeys.themeColorClear),
                          ),
                        ),
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

  Widget _topBarButtonLabel(String key) {
    return Transform.translate(
      key: ValueKey('settings-$key-wpf-label'),
      offset: const Offset(0.5, -1),
      child: Text(
        strings.get(key),
        style: const TextStyle(letterSpacing: -0.075),
      ),
    );
  }

  Future<void> _showCustomThemeColorDialog() async {
    final normalized = _normalizeColorHex(_customThemeColorController.text);
    final initialColor = normalized.isEmpty
        ? Theme.of(context).colorScheme.primary
        : Color(int.parse('FF${normalized.substring(1)}', radix: 16));
    final nativePicker = widget.pickCustomThemeColor;
    if (nativePicker != null) {
      final selected = await nativePicker(_colorHex(initialColor));
      if (!mounted || selected == null) {
        return;
      }
      final selectedHex = _normalizeColorHex(selected);
      if (selectedHex.isEmpty) {
        return;
      }
      setState(() => _customThemeColorController.text = selectedHex);
      return;
    }
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

            return _SettingsPaperDialog(
              width: 392,
              icon: Icons.colorize_outlined,
              title: strings.get(PaperTodoStringKeys.themeColorPick),
              content: SizedBox(
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
    setState(() {
      _customThemeColorController.text = _colorHex(selected);
    });
  }

  String _colorHex(Color color) {
    final red = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final green = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final blue = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$red$green$blue'.toUpperCase();
  }

  Widget _settingsNavigation({required bool compact}) {
    final colors = Theme.of(context).colorScheme;
    final paperColors = PaperTodoThemeColors.of(context);
    return ListView(
      key: const ValueKey('settings-category-navigation'),
      padding: const EdgeInsets.only(top: 8, right: 12),
      children: [
        for (final section in _SettingsSection.values)
          if (widget.supportsCapsules ||
              section != _SettingsSection.capsules) ...[
            if (section == _SettingsSection.sync)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Divider(
                  key: const ValueKey('settings-sync-section-divider'),
                  height: 1,
                  color: paperColors.tint.withValues(
                    alpha: paperColors.isDark ? 34 / 255 : 24 / 255,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Tooltip(
                message: compact ? _settingsSectionLabel(section) : '',
                child: Material(
                  color: section == _selectedSettingsSection
                      ? paperColors.tint.withValues(
                          alpha: paperColors.isDark ? 42 / 255 : 24 / 255,
                        )
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    key: ValueKey('settings-category-${section.name}'),
                    borderRadius: BorderRadius.circular(8),
                    hoverColor: paperColors.tint.withValues(
                      alpha: paperColors.isDark ? 48 / 255 : 32 / 255,
                    ),
                    onTap: () => _selectSettingsSection(section),
                    child: SizedBox(
                      height: 34,
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: compact ? 0 : 9),
                        child: Row(
                          mainAxisAlignment: compact
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            if (compact)
                              Icon(
                                _settingsSectionIcon(section),
                                size: 17,
                                color: section == _selectedSettingsSection
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                              )
                            else ...[
                              Container(
                                width: 3,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: section == _selectedSettingsSection
                                      ? paperColors.active
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _settingsSectionLabel(section),
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: 12.5,
                                        color:
                                            section == _selectedSettingsSection
                                                ? colors.onSurface
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
      ],
    );
  }

  Widget _settingsSectionHeader({
    required _SettingsSection section,
    required IconData icon,
    required String label,
  }) {
    return _settingsGroupLabel(
      label,
      key: _settingsSectionKeys[section],
    );
  }

  Widget _settingsGroupLabel(String label, {Key? key}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 12, bottom: 3),
      child: Transform.translate(
        key: const ValueKey('settings-group-label-metrics'),
        offset: const Offset(-0.5, 0.5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  Widget _settingsHelp(String stringKey) {
    return _SettingsHelpIcon(message: strings.get(stringKey));
  }

  Widget _settingsLabelWithHint({
    required String label,
    required String tipKey,
    TextStyle? style,
    Offset labelPaintOffset = Offset.zero,
    Key labelMetricsKey = const ValueKey('settings-field-label-metrics'),
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Transform.translate(
            key: labelMetricsKey,
            offset: Offset(
              -0.5 + labelPaintOffset.dx,
              0.5 + labelPaintOffset.dy,
            ),
            child: Text(label, style: style),
          ),
        ),
        const SizedBox(width: 6),
        _settingsHelp(tipKey),
      ],
    );
  }

  Widget _settingsLabeledControl({
    required String label,
    required String tipKey,
    required Widget child,
    double topSpacing = 4,
    double bottomSpacing = 10,
  }) {
    final colors = PaperTodoThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: topSpacing),
          child: _settingsLabelWithHint(
            label: label,
            tipKey: tipKey,
            style: TextStyle(
              color: colors.weakText,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 4),
        child,
        SizedBox(height: bottomSpacing),
      ],
    );
  }

  InputDecoration _settingsTextBoxDecoration({double height = 28}) {
    final colors = PaperTodoThemeColors.of(context);
    return InputDecoration(
      isDense: true,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      constraints: BoxConstraints.tightFor(height: height),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.paperBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.paperBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.active),
      ),
    );
  }

  Widget _settingsCompactTextField({
    required Widget Function(InputDecoration decoration) fieldBuilder,
  }) {
    final colors = PaperTodoThemeColors.of(context);
    return Focus(
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: focused ? colors.active : colors.paperBorder,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SizedBox(
              height: 28,
              child: fieldBuilder(
                const InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _webDavSettingsTextField({
    required TextEditingController controller,
    FocusNode? focusNode,
    required bool enabled,
    required String label,
    String? helperText,
    String? errorText,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    Widget? trailing,
    double bottomSpacing = 10,
  }) {
    final colors = PaperTodoThemeColors.of(context);
    final supportingText = errorText ?? helperText;
    final supportingColor = errorText == null ? colors.weakText : colors.danger;
    final field = Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Focus(
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: errorText != null
                      ? colors.danger
                      : focused
                          ? colors.active
                          : colors.paperBorder,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                height: 28,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  onChanged: onChanged,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 13,
                    height: 1,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    labelText: label,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    labelStyle: const TextStyle(
                      color: Colors.transparent,
                      fontSize: 0,
                      height: 0,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RichText(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: enabled
                  ? colors.weakText
                  : colors.weakText.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (trailing == null)
          field
        else
          Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        if (supportingText != null && supportingText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            supportingText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: enabled
                  ? supportingColor
                  : supportingColor.withValues(alpha: 0.55),
              fontSize: 10.5,
              height: 1.25,
            ),
          ),
        ],
        SizedBox(height: bottomSpacing),
      ],
    );
  }

  Widget _webDavSecretToggle({
    required bool enabled,
    required bool obscure,
    required String showLabelKey,
    required String hideLabelKey,
    required VoidCallback onPressed,
  }) {
    final colors = PaperTodoThemeColors.of(context);
    final tooltip = _enableToolTips
        ? strings.get(obscure ? showLabelKey : hideLabelKey)
        : null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: SizedBox(
        width: 34,
        height: 26,
        child: IconButton(
          tooltip: enabled ? tooltip : null,
          style: IconButton.styleFrom(
            minimumSize: const Size(34, 26),
            maximumSize: const Size(34, 26),
            padding: EdgeInsets.zero,
            backgroundColor: colors.hover,
            foregroundColor: colors.weakText,
            disabledBackgroundColor: colors.hover,
            disabledForegroundColor: colors.weakText,
            hoverColor: colors.tint.withValues(
              alpha: colors.isDark ? 48 / 255 : 32 / 255,
            ),
            highlightColor: colors.tint.withValues(
              alpha: colors.isDark ? 64 / 255 : 48 / 255,
            ),
            shape: const RoundedRectangleBorder(),
          ),
          onPressed: enabled ? onPressed : null,
          iconSize: 15,
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
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
        final colors = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _settingsLabelWithHint(
              label: strings.get(PaperTodoStringKeys.systemFont),
              tipKey: PaperTodoStringKeys.tipSystemFont,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.005,
                  ),
            ),
            const SizedBox(height: 4),
            RawAutocomplete<String>(
              textEditingController: _fontFamilyController,
              focusNode: _fontFamilyFocusNode,
              displayStringForOption: (option) => option.isEmpty
                  ? strings.get(PaperTodoStringKeys.uiFontDefault)
                  : option,
              optionsBuilder: (textEditingValue) {
                if (!enabled || _installedFontFamilies.isEmpty) {
                  return textEditingValue.text.trim().isEmpty
                      ? const <String>['']
                      : const <String>[];
                }
                final query = normalizeSystemFontFamilyName(
                  textEditingValue.text,
                ).toLowerCase();
                if (query.isEmpty) {
                  return <String>['', ..._installedFontFamilies].take(40);
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
                  style: const TextStyle(fontSize: 12.5, height: 1),
                  textAlignVertical: const TextAlignVertical(y: -0.4),
                  decoration: _settingsTextBoxDecoration(height: 30).copyWith(
                    hintText: strings.get(PaperTodoStringKeys.uiFontDefault),
                    hintStyle: TextStyle(
                      color: PaperTodoThemeColors.of(context).text,
                      fontSize: 12.5,
                      height: 1,
                    ),
                    suffixIconConstraints:
                        const BoxConstraints.tightFor(width: 30, height: 30),
                    suffixIcon: _isLoadingInstalledFontFamilies
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox.square(
                              dimension: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                          )
                        : (_installedFontFamilies.isEmpty
                            ? null
                            : const _SettingsDropChevron()),
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
                                fontFamily.isEmpty
                                    ? strings
                                        .get(PaperTodoStringKeys.uiFontDefault)
                                    : fontFamily,
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
            ),
          ],
        );
      },
    );
  }

  Widget _hotKeyCaptureField({
    required Key key,
    required TextEditingController controller,
  }) {
    final colors = PaperTodoThemeColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Focus(
            onKeyEvent: (_, event) => _handleHotKeyCapture(controller, event),
            child: _settingsCompactTextField(
              fieldBuilder: (decoration) => TextField(
                key: key,
                controller: controller,
                readOnly: true,
                showCursor: false,
                enableInteractiveSelection: false,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  height: 1,
                ),
                textAlignVertical: TextAlignVertical.center,
                onTap: () {
                  controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  );
                },
                decoration: decoration,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          height: 26,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(52, 26),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              backgroundColor: colors.hover,
              foregroundColor: colors.text,
              textStyle: const TextStyle(fontSize: 12),
            ),
            onPressed: () => setState(controller.clear),
            child: Text(strings.get(PaperTodoStringKeys.actionClear)),
          ),
        ),
      ],
    );
  }

  Widget _dataDirectoryEditor() {
    final colors = PaperTodoThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _settingsCompactTextField(
                fieldBuilder: (decoration) => TextField(
                  key: const ValueKey('settings-data-directory'),
                  controller: _dataDirectoryController,
                  readOnly: true,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 13,
                    height: 1,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  onTap: _chooseDataDirectory,
                  decoration: decoration,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 58),
              child: SizedBox(
                height: 26,
                child: TextButton(
                  key: const ValueKey('settings-data-directory-browse'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(58, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    backgroundColor: colors.hover,
                    foregroundColor: colors.text,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _chooseDataDirectory,
                  child: Text(
                    strings.get(PaperTodoStringKeys.actionBrowse),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          strings.get(PaperTodoStringKeys.dataDirectoryHelp),
          style: TextStyle(
            color: colors.weakText,
            fontSize: 11,
          ),
        ),
      ],
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
    String? tipKey,
    double? labelLetterSpacing,
    Offset labelPaintOffset = Offset.zero,
    Key? labelMetricsKey,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final requiredWidth = choices.fold<double>(0, (total, choice) {
          final textWidth = choice.label.runes.length * 7.2;
          final chromeWidth = choice.icon == null ? 28.0 : 50.0;
          return total + math.max(74, textWidth + chromeWidth);
        });
        final compact = availableWidth < requiredWidth;
        if (compact) {
          return _paperTodoCompactDropdown(
            key: key,
            label: labelText,
            value: selectedValue,
            choices: choices,
            onChanged: onChanged,
            tipKey: tipKey,
          );
        }
        final colors = Theme.of(context).colorScheme;
        final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: labelLetterSpacing,
            );
        final selector = Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tipKey == null)
              Text(labelText, style: labelStyle)
            else
              _settingsLabelWithHint(
                label: labelText,
                tipKey: tipKey,
                style: labelStyle,
                labelPaintOffset: labelPaintOffset,
                labelMetricsKey: labelMetricsKey ??
                    const ValueKey('settings-field-label-metrics'),
              ),
            const SizedBox(height: 4),
            _SettingsSegmentSelector(
              selectedValue: selectedValue,
              choices: choices,
              onChanged: onChanged,
            ),
          ],
        );
        return selector;
      },
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
    required Key surfaceKey,
    required TextEditingController controller,
    required String label,
    required String tipKey,
    double? labelLetterSpacing,
  }) {
    final colors = PaperTodoThemeColors.of(context);
    Widget editorField() => Focus(
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return DecoratedBox(
                key: surfaceKey,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: focused ? colors.active : colors.paperBorder,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    key: key,
                    controller: controller,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 13,
                      height: 1,
                    ),
                    textAlign: TextAlign.center,
                    textAlignVertical: TextAlignVertical.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,1}(?:\.\d{0,2})?'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ),
              );
            },
          ),
        );

    Widget resetButton() => ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 58),
          child: SizedBox(
            height: 26,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(58, 26),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                backgroundColor: colors.hover,
                foregroundColor: colors.text,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: () => setState(() => controller.text = '1'),
              child: Text(
                strings.get(PaperTodoStringKeys.settingsLineSpacingReset),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _settingsLabelWithHint(
          label: label,
          tipKey: tipKey,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.weakText,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: labelLetterSpacing,
              ),
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 280) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  editorField(),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: resetButton(),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: editorField()),
                const SizedBox(width: 8),
                resetButton(),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _webDavPresetSelector(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return _paperTodoCompactDropdown(
        key: const ValueKey('compact-webdav-preset-selector'),
        label: strings.get(PaperTodoStringKeys.webDavProvider),
        value: _presetId,
        choices: [
          for (final preset in WebDavPresets.all)
            _SettingsChoice(
              value: preset.id,
              label: _webDavPresetLabel(preset),
            ),
        ],
        onChanged: (value) => _applyPreset(value),
      );
    }
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.get(PaperTodoStringKeys.webDavProvider),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        _SettingsSegmentSelector(
          key: const ValueKey('desktop-webdav-preset-selector'),
          selectedValue: _presetId,
          choices: [
            for (final preset in WebDavPresets.all)
              _SettingsChoice(
                value: preset.id,
                label: _webDavPresetLabel(preset),
              ),
          ],
          onChanged: _applyPreset,
        ),
      ],
    );
  }

  Widget _paperTodoCompactDropdown({
    Key? key,
    required String label,
    required String value,
    required List<_SettingsChoice> choices,
    required ValueChanged<String>? onChanged,
    String? tipKey,
  }) {
    final colors = PaperTodoThemeColors.of(context);
    final labelStyle = TextStyle(
      color: colors.weakText,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    );
    final field = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.paperBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: 28,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: key,
            value: value,
            isExpanded: true,
            isDense: true,
            borderRadius: BorderRadius.circular(8),
            padding: const EdgeInsets.only(left: 10, right: 7),
            icon: const _SettingsDropChevron(),
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              height: 1,
            ),
            dropdownColor: colors.paper,
            items: [
              for (final choice in choices)
                DropdownMenuItem<String>(
                  value: choice.value,
                  child: Text(
                    choice.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged == null
                ? null
                : (next) {
                    if (next != null) onChanged(next);
                  },
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tipKey == null)
          Text(label, style: labelStyle)
        else
          _settingsLabelWithHint(
            label: label,
            tipKey: tipKey,
            style: labelStyle,
          ),
        const SizedBox(height: 4),
        field,
      ],
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

  String _lineSpacingText(double value) {
    return value
        .clamp(0.8, 5.0)
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'\.?0+$'), '');
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

class _SettingsCheckboxTile extends StatefulWidget {
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
  State<_SettingsCheckboxTile> createState() => _SettingsCheckboxTileState();
}

class _SettingsCheckboxTileState extends State<_SettingsCheckboxTile> {
  bool _hovered = false;

  @override
  void didUpdateWidget(covariant _SettingsCheckboxTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onChanged == null && _hovered) {
      _hovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    final enabled = widget.onChanged != null;
    final requestedPadding =
        widget.contentPadding?.resolve(Directionality.of(context)) ??
            EdgeInsets.zero;
    final rowPadding = requestedPadding.copyWith(
      top: requestedPadding.top + 4,
    );
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SettingsCheckMark(
          value: widget.value,
          hovered: _hovered,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Transform.translate(
            key: const ValueKey('settings-checkbox-title-metrics'),
            offset: const Offset(-0.5, 0),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: colors.text,
                fontSize: 13,
                height: 1.15,
              ),
              child: widget.title,
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: rowPadding,
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: enabled ? 1 : 0.55,
              child: MouseRegion(
                cursor: enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                onEnter:
                    enabled ? (_) => setState(() => _hovered = true) : null,
                onExit:
                    enabled ? (_) => setState(() => _hovered = false) : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      enabled ? () => widget.onChanged!(!widget.value) : null,
                  child: Semantics(
                    checked: widget.value,
                    enabled: enabled,
                    child: SizedBox(
                      height: 18,
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.secondary is _SettingsHelpIcon) ...[
            const SizedBox(width: 6),
            IconTheme.merge(
              data: IconThemeData(color: colors.weakText, size: 14),
              child: widget.secondary!,
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsCheckMark extends StatelessWidget {
  const _SettingsCheckMark({
    required this.value,
    required this.hovered,
  });

  final bool value;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 16,
      child: CustomPaint(
        painter: _SettingsCheckMarkPainter(
          value: value,
          hovered: hovered,
          colors: PaperTodoThemeColors.of(context),
        ),
      ),
    );
  }
}

class _SettingsCheckMarkPainter extends CustomPainter {
  const _SettingsCheckMarkPainter({
    required this.value,
    required this.hovered,
    required this.colors,
  });

  final bool value;
  final bool hovered;
  final PaperTodoThemeColors colors;

  static const double borderWidth = 1.5;
  static const double radius = 4;
  double get checkedInset => borderWidth + 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(borderWidth / 2),
      const Radius.circular(radius - borderWidth / 2),
    );
    if (value) {
      final checkedRect = rect.deflate(checkedInset);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          checkedRect,
          Radius.circular(radius - checkedInset),
        ),
        Paint()
          ..color = colors.active
          ..style = PaintingStyle.fill,
      );
      final check = Path()
        ..moveTo(4, 8.1)
        ..lineTo(7, 11)
        ..lineTo(12, 5);
      canvas.drawPath(
        check,
        Paint()
          ..color = colors.paper
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }
    if (hovered) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = colors.hover
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = colors.paperBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _SettingsCheckMarkPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.hovered != hovered ||
        oldDelegate.colors != colors;
  }
}

class _SettingsCloseButton extends StatefulWidget {
  const _SettingsCloseButton({
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_SettingsCloseButton> createState() => _SettingsCloseButtonState();
}

class _SettingsCloseButtonState extends State<_SettingsCloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) {
          setState(() {
            _hovered = false;
            _pressed = false;
          });
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: Container(
            key: const ValueKey('settings-close-button-surface'),
            width: 28,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _pressed
                  ? colors.active
                  : _hovered
                      ? colors.hover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Transform.translate(
              key: const ValueKey('settings-close-glyph-metrics'),
              offset: const Offset(-2, 1),
              child: Text(
                '\u00D7',
                style: TextStyle(
                  fontFamily: 'Segoe UI Symbol',
                  fontFamilyFallback: const <String>['Segoe UI Emoji'],
                  fontSize: 16,
                  height: 1,
                  color: _pressed
                      ? colors.paper
                      : _hovered
                          ? colors.text
                          : colors.weakText,
                ),
              ),
            ),
          ),
        ),
      ),
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

class _SettingsAuthorLink extends StatefulWidget {
  const _SettingsAuthorLink({required this.onPressed});

  static const url = 'https://github.com/snownico0722';

  final SettingsAuthorLinkOpener? onPressed;

  @override
  State<_SettingsAuthorLink> createState() => _SettingsAuthorLinkState();
}

class _SettingsAuthorLinkState extends State<_SettingsAuthorLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    return Tooltip(
      message: _SettingsAuthorLink.url,
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 12),
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed == null
              ? null
              : () => unawaited(widget.onPressed!()),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 0, 0),
            child: Transform.scale(
              key: const ValueKey('settings-author-signature-metrics'),
              scaleX: 99 / 103,
              alignment: Alignment.centerRight,
              child: Text(
                'Designed by trigger',
                key: const ValueKey('settings-author-signature'),
                style: TextStyle(
                  color: _hovered ? colors.text : colors.weakText,
                  fontFamily: 'Segoe UI',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsDropChevron extends StatelessWidget {
  const _SettingsDropChevron();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: 18,
        child: CustomPaint(
          key: const ValueKey('settings-drop-chevron'),
          painter: _SettingsDropChevronPainter(
            color: PaperTodoThemeColors.of(context).weakText,
          ),
        ),
      ),
    );
  }
}

class _SettingsDropChevronPainter extends CustomPainter {
  const _SettingsDropChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(4, 6.05)
      ..lineTo(14, 6.05)
      ..lineTo(9, 11.15)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _SettingsDropChevronPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _SettingsSegmentSelector extends StatelessWidget {
  const _SettingsSegmentSelector({
    super.key,
    required this.selectedValue,
    required this.choices,
    required this.onChanged,
  });

  final String selectedValue;
  final List<_SettingsChoice> choices;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    return Opacity(
      opacity: onChanged == null ? 0.55 : 1,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(color: colors.paperBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            for (final choice in choices)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: _SettingsSegmentButton(
                    label: choice.label,
                    selected: choice.value == selectedValue,
                    enabled: onChanged != null,
                    onPressed: () {
                      if (choice.value != selectedValue) {
                        onChanged?.call(choice.value);
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSegmentButton extends StatefulWidget {
  const _SettingsSegmentButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_SettingsSegmentButton> createState() => _SettingsSegmentButtonState();
}

class _SettingsSegmentButtonState extends State<_SettingsSegmentButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    final hoverable = widget.enabled && !widget.selected;
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: hoverable ? (_) => setState(() => _hovered = true) : null,
      onExit: hoverable ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onPressed : null,
        child: Semantics(
          button: true,
          selected: widget.selected,
          enabled: widget.enabled,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.active
                  : _hovered
                      ? colors.hover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.selected ? colors.paper : colors.text,
                  fontSize: 12,
                  height: 1,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsHelpIcon extends StatefulWidget {
  const _SettingsHelpIcon({required this.message});

  final String message;

  @override
  State<_SettingsHelpIcon> createState() => _SettingsHelpIconState();
}

class _SettingsHelpIconState extends State<_SettingsHelpIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    return Tooltip(
      message: widget.message,
      waitDuration: const Duration(milliseconds: 200),
      showDuration: const Duration(seconds: 20),
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.paper,
        border: Border.all(color: colors.paperBorder),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      textStyle: TextStyle(
        color: colors.text,
        fontSize: 12,
        height: 1.25,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox.square(
          dimension: 18,
          child: Center(
            child: Text(
              '\u24D8',
              style: TextStyle(
                fontFamily: 'Segoe UI Symbol',
                fontSize: 12,
                height: 1,
                color: _hovered ? colors.text : colors.weakText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsStepper extends StatelessWidget {
  const _SettingsStepper({
    super.key,
    required this.valueLabel,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String valueLabel;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    return Container(
      height: 28,
      decoration: BoxDecoration(
        border: Border.all(color: colors.paperBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _SettingsStepperButton(
            glyph: '−',
            onPressed: onDecrease,
          ),
          Expanded(
            child: Center(
              child: Text(
                valueLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          _SettingsStepperButton(
            glyph: '＋',
            onPressed: onIncrease,
          ),
        ],
      ),
    );
  }
}

class _SettingsStepperButton extends StatefulWidget {
  const _SettingsStepperButton({
    required this.glyph,
    required this.onPressed,
  });

  final String glyph;
  final VoidCallback onPressed;

  @override
  State<_SettingsStepperButton> createState() => _SettingsStepperButtonState();
}

class _SettingsStepperButtonState extends State<_SettingsStepperButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = PaperTodoThemeColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => widget.onPressed(),
        child: ColoredBox(
          color: _hovered ? colors.hover : Colors.transparent,
          child: SizedBox(
            width: 34,
            height: 28,
            child: Center(
              child: Text(
                widget.glyph,
                style: TextStyle(
                  color: colors.text,
                  fontFamily: 'Segoe UI Symbol',
                  fontSize: 15,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsWindowDialog extends StatelessWidget {
  const _SettingsWindowDialog({
    required this.title,
    required this.content,
  });

  final Widget title;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    return Dialog(
      key: const ValueKey('windows-settings-paper-dialog'),
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: SizedBox.expand(
        key: const ValueKey('windows-settings-paper-fill'),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: isDark ? 0.36 : 0.20),
                blurRadius: isDark ? 30 : 28,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              key: const ValueKey('settings-window-padding'),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  const SizedBox(height: 14),
                  content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsPaperDialog extends StatelessWidget {
  const _SettingsPaperDialog({
    required this.title,
    required this.content,
    required this.actions,
    this.icon,
    this.width = 440,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final paperColors = PaperTodoThemeColors.of(context);
    final isDark = colors.brightness == Brightness.dark;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(
                  alpha: isDark ? 0.34 : 0.20,
                ),
                blurRadius: isDark ? 30 : 28,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (icon case final icon?) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: paperColors.tint.withValues(
                            alpha: isDark ? 42 / 255 : 28 / 255,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SizedBox.square(
                          dimension: 28,
                          child: Icon(
                            icon,
                            size: 17,
                            color: paperColors.active,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                content,
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
