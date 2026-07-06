import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model/paper_constants.dart';
import '../core/model/sync_settings.dart';
import '../core/model/webdav_presets.dart';

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

  @override
  State<SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends State<SyncSettingsDialog> {
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
  String? _errorText;
  String? _endpointErrorText;
  String? _rootPathErrorText;
  String? _usernameErrorText;
  String? _passwordErrorText;
  String? _encryptionPassphraseErrorText;

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
    _uiFontPreset = UiFontPresets.normalize(widget.initialUiFontPreset);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Row(
        children: [
          Icon(Icons.sync_outlined),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sync settings',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _adaptiveChoiceSelector(
                key: const ValueKey('settings-theme-selector'),
                labelText: 'Theme',
                compactIcon: Icons.brightness_auto_outlined,
                selectedValue: _theme,
                choices: const [
                  _SettingsChoice(
                    value: 'system',
                    label: 'System',
                    icon: Icons.brightness_auto_outlined,
                  ),
                  _SettingsChoice(
                    value: 'light',
                    label: 'Light',
                    icon: Icons.light_mode_outlined,
                  ),
                  _SettingsChoice(
                    value: 'dark',
                    label: 'Dark',
                    icon: Icons.dark_mode_outlined,
                  ),
                ],
                onChanged: (value) => setState(() => _theme = value),
              ),
              const SizedBox(height: 12),
              _adaptiveChoiceSelector(
                key: const ValueKey('settings-color-scheme-selector'),
                labelText: 'Color scheme',
                compactIcon: Icons.palette_outlined,
                selectedValue: _colorScheme,
                choices: const [
                  _SettingsChoice(value: ColorSchemes.warm, label: 'Warm'),
                  _SettingsChoice(value: ColorSchemes.ink, label: 'Ink'),
                  _SettingsChoice(value: ColorSchemes.forest, label: 'Forest'),
                  _SettingsChoice(value: ColorSchemes.rose, label: 'Rose'),
                ],
                onChanged: (value) => setState(() => _colorScheme = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customThemeColorController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Custom theme color',
                  prefixIcon: Icon(Icons.palette_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _adaptiveChoiceSelector(
                key: const ValueKey('settings-markdown-mode-selector'),
                labelText: 'Markdown mode',
                compactIcon: Icons.article_outlined,
                selectedValue: _markdownRenderMode,
                choices: const [
                  _SettingsChoice(
                    value: MarkdownRenderModes.off,
                    label: 'Markdown off',
                    icon: Icons.edit_outlined,
                  ),
                  _SettingsChoice(
                    value: MarkdownRenderModes.basic,
                    label: 'Basic',
                    icon: Icons.article_outlined,
                  ),
                  _SettingsChoice(
                    value: MarkdownRenderModes.enhanced,
                    label: 'Enhanced',
                    icon: Icons.vertical_split_outlined,
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _markdownRenderMode = value),
              ),
              const SizedBox(height: 12),
              _adaptiveChoiceSelector(
                key: const ValueKey('settings-todo-visual-size-selector'),
                labelText: 'Todo visual size',
                compactIcon: Icons.format_size_outlined,
                selectedValue: _todoVisualSize,
                choices: const [
                  _SettingsChoice(value: TodoVisualSizes.small, label: 'Small'),
                  _SettingsChoice(
                    value: TodoVisualSizes.medium,
                    label: 'Medium',
                  ),
                  _SettingsChoice(value: TodoVisualSizes.large, label: 'Large'),
                  _SettingsChoice(
                    value: TodoVisualSizes.extraLarge,
                    label: 'XL',
                  ),
                ],
                onChanged: (value) => setState(() => _todoVisualSize = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _uiFontPreset,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Font preset',
                  prefixIcon: Icon(Icons.font_download_outlined),
                ),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: UiFontPresets.defaultPreset,
                    child: Text('Default'),
                  ),
                  DropdownMenuItem(
                    value: UiFontPresets.yaHei,
                    child: Text('YaHei'),
                  ),
                  DropdownMenuItem(
                    value: UiFontPresets.dengXian,
                    child: Text('DengXian'),
                  ),
                  DropdownMenuItem(
                    value: UiFontPresets.serif,
                    child: Text('Serif'),
                  ),
                  DropdownMenuItem(
                    value: UiFontPresets.mono,
                    child: Text('Mono'),
                  ),
                  DropdownMenuItem(
                    value: UiFontPresets.custom,
                    child: Text('Custom'),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _uiFontPreset =
                      UiFontPresets.normalize(value ?? _uiFontPreset),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fontFamilyController,
                enabled: _uiFontPreset == UiFontPresets.custom,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Custom font family',
                  prefixIcon: Icon(Icons.title_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _externalMarkdownExtensionController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'External markdown extension',
                  prefixIcon: Icon(Icons.file_open_outlined),
                ),
              ),
              const SizedBox(height: 12),
              _SettingsSlider(
                icon: Icons.zoom_in_outlined,
                label: 'Zoom',
                valueLabel: '${(_zoom * 100).round()}%',
                value: _zoom,
                min: 0.5,
                max: 1.5,
                divisions: 10,
                onChanged: (value) => setState(() => _zoom = value),
              ),
              _SettingsSlider(
                icon: Icons.short_text_outlined,
                label: 'Max title length',
                valueLabel: '${_maxTitleLength.round()} chars',
                value: _maxTitleLength,
                min: 2,
                max: 20,
                divisions: 18,
                onChanged: (value) => setState(() => _maxTitleLength = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.info_outline),
                title: const Text('Tooltips'),
                value: _enableToolTips,
                onChanged: (value) => setState(() => _enableToolTips = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.animation_outlined),
                title: const Text('Animations'),
                value: _enableAnimations,
                onChanged: (value) => setState(() => _enableAnimations = value),
              ),
              _SettingsSlider(
                icon: Icons.checklist_outlined,
                label: 'Todo spacing',
                valueLabel: _todoLineSpacing.toStringAsFixed(1),
                value: _todoLineSpacing,
                min: 0.8,
                max: 5.0,
                divisions: 42,
                onChanged: (value) => setState(() => _todoLineSpacing = value),
              ),
              _SettingsSlider(
                icon: Icons.notes_outlined,
                label: 'Note spacing',
                valueLabel: _noteLineSpacing.toStringAsFixed(1),
                value: _noteLineSpacing,
                min: 0.8,
                max: 5.0,
                divisions: 42,
                onChanged: (value) => setState(() => _noteLineSpacing = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.event_repeat_outlined),
                title: const Text('Relative due dates'),
                value: _showTodoDueRelativeTime,
                onChanged: (value) =>
                    setState(() => _showTodoDueRelativeTime = value),
              ),
              const SizedBox(height: 8),
              _adaptiveChoiceSelector(
                key: const ValueKey('settings-due-year-selector'),
                labelText: 'Due year display',
                compactIcon: Icons.event_outlined,
                selectedValue: _todoDueYearDisplayMode,
                choices: const [
                  _SettingsChoice(
                    value: TodoDueYearDisplayModes.none,
                    label: 'No year',
                  ),
                  _SettingsChoice(
                    value: TodoDueYearDisplayModes.short,
                    label: 'YY',
                  ),
                  _SettingsChoice(
                    value: TodoDueYearDisplayModes.full,
                    label: 'YYYY',
                  ),
                ],
                onChanged: _showTodoDueRelativeTime
                    ? null
                    : (value) =>
                        setState(() => _todoDueYearDisplayMode = value),
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.add_task_outlined),
                title: const Text('Top bar new todo'),
                value: _showTopBarNewTodoButton,
                onChanged: (value) =>
                    setState(() => _showTopBarNewTodoButton = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.note_add_outlined),
                title: const Text('Top bar new note'),
                value: _showTopBarNewNoteButton,
                onChanged: (value) =>
                    setState(() => _showTopBarNewNoteButton = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.open_in_new_outlined),
                title: const Text('Top bar open surface'),
                value: _showTopBarExternalOpenButton,
                onChanged: (value) =>
                    setState(() => _showTopBarExternalOpenButton = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.view_agenda_outlined),
                title: const Text('Capsule mode'),
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
                  }
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.stacked_line_chart_outlined),
                title: const Text('Deep capsule mode'),
                value: _useDeepCapsuleMode,
                onChanged: _useCapsuleMode
                    ? (value) => setState(() {
                          _useDeepCapsuleMode = value;
                          if (!value) {
                            _showDeepCapsuleWhileExpanded = false;
                            _collapseExpandedDeepCapsuleOnClick = false;
                            _hideDeepCapsulesWhenCovered = false;
                          }
                        })
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.unfold_less_outlined),
                title: const Text('Collapse all control'),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.vertical_align_center_outlined),
                title: const Text('Collapse all active'),
                value: _capsuleCollapseAllActive,
                onChanged: _useCapsuleMode && _useCapsuleCollapseAll
                    ? (value) =>
                        setState(() => _capsuleCollapseAllActive = value)
                    : null,
              ),
              const SizedBox(height: 8),
              _adaptiveChoiceSelector(
                key: const ValueKey('settings-deep-capsule-side-selector'),
                labelText: 'Deep capsule side',
                compactIcon: Icons.vertical_align_center_outlined,
                selectedValue: _deepCapsuleSide,
                choices: const [
                  _SettingsChoice(
                    value: DeepCapsuleSides.left,
                    label: 'Left',
                    icon: Icons.keyboard_double_arrow_left_outlined,
                  ),
                  _SettingsChoice(
                    value: DeepCapsuleSides.right,
                    label: 'Right',
                    icon: Icons.keyboard_double_arrow_right_outlined,
                  ),
                ],
                onChanged: _useCapsuleMode && _useDeepCapsuleMode
                    ? (value) => setState(() => _deepCapsuleSide = value)
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deepCapsuleTopMarginController,
                enabled: _useCapsuleMode && _useDeepCapsuleMode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Deep capsule top margin',
                  prefixIcon: Icon(Icons.vertical_align_top_outlined),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deepCapsuleMonitorController,
                enabled: _useCapsuleMode && _useDeepCapsuleMode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Deep capsule monitor',
                  prefixIcon: Icon(Icons.monitor_outlined),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.open_in_full_outlined),
                title: const Text('Show deep capsule while expanded'),
                value: _showDeepCapsuleWhileExpanded,
                onChanged: _useCapsuleMode && _useDeepCapsuleMode
                    ? (value) =>
                        setState(() => _showDeepCapsuleWhileExpanded = value)
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.ads_click_outlined),
                title: const Text('Collapse expanded deep capsule on click'),
                value: _collapseExpandedDeepCapsuleOnClick,
                onChanged: _useCapsuleMode && _useDeepCapsuleMode
                    ? (value) => setState(
                          () => _collapseExpandedDeepCapsuleOnClick = value,
                        )
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.layers_clear_outlined),
                title: const Text('Hide covered deep capsules'),
                value: _hideDeepCapsulesWhenCovered,
                onChanged: _useCapsuleMode && _useDeepCapsuleMode
                    ? (value) =>
                        setState(() => _hideDeepCapsulesWhenCovered = value)
                    : null,
              ),
              if (_hasDesktopIntegrationSettings) const Divider(height: 24),
              if (widget.supportsStartAtLogin)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.login_outlined),
                  title: const Text('Start at login'),
                  value: _startAtLogin,
                  onChanged: (value) => setState(() => _startAtLogin = value),
                ),
              if (widget.supportsHideFromWindowSwitcher)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Hide from task switcher'),
                  value: _hideFromWindowSwitcher,
                  onChanged: (value) =>
                      setState(() => _hideFromWindowSwitcher = value),
                ),
              if (widget.supportsFullscreenTopmostMode) ...[
                const SizedBox(height: 8),
                _adaptiveChoiceSelector(
                  key: const ValueKey('settings-fullscreen-topmost-selector'),
                  labelText: 'Fullscreen behavior',
                  compactIcon: Icons.fullscreen_exit_outlined,
                  selectedValue: _fullscreenTopmostMode,
                  choices: const [
                    _SettingsChoice(
                      value: FullscreenTopmostModes.avoid,
                      label: 'Avoid fullscreen',
                      icon: Icons.fullscreen_exit_outlined,
                    ),
                    _SettingsChoice(
                      value: FullscreenTopmostModes.stayOnTop,
                      label: 'Stay on top',
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
                  first: TextField(
                    controller: _pinnedTodoHotKeyController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Pinned todo hotkey',
                      prefixIcon: Icon(Icons.keyboard_outlined),
                    ),
                  ),
                  second: TextField(
                    controller: _pinnedNoteHotKeyController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Pinned note hotkey',
                      prefixIcon: Icon(Icons.keyboard_command_key_outlined),
                    ),
                  ),
                ),
              ],
              if (widget.supportsScriptCapsules) ...[
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.terminal_outlined),
                  title: const Text('Run linked script capsules on click'),
                  value: _runLinkedScriptCapsulesOnClick,
                  onChanged: (value) =>
                      setState(() => _runLinkedScriptCapsulesOnClick = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.memory_outlined),
                  title: const Text('Persistent PowerShell process'),
                  value: _usePersistentPowerShellProcess,
                  onChanged: _runLinkedScriptCapsulesOnClick
                      ? (value) => setState(
                            () => _usePersistentPowerShellProcess = value,
                          )
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.bolt_outlined),
                  title: const Text('Prefer PowerShell 7'),
                  value: _preferPowerShell7,
                  onChanged: _runLinkedScriptCapsulesOnClick
                      ? (value) => setState(() => _preferPowerShell7 = value)
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Hide script run window'),
                  value: _hideScriptRunWindow,
                  onChanged: _runLinkedScriptCapsulesOnClick
                      ? (value) => setState(() => _hideScriptRunWindow = value)
                      : null,
                ),
              ],
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Todo reminders'),
                value: _useTodoReminderInterval,
                onChanged: (value) =>
                    setState(() => _useTodoReminderInterval = value),
              ),
              const SizedBox(height: 8),
              _adaptiveFieldPair(
                first: TextField(
                  controller: _reminderIntervalController,
                  enabled: _useTodoReminderInterval,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Reminder interval',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  keyboardType: TextInputType.number,
                ),
                second: _adaptiveChoiceSelector(
                  key: const ValueKey('settings-reminder-unit-selector'),
                  labelText: 'Reminder unit',
                  compactIcon: Icons.schedule_outlined,
                  selectedValue: _todoReminderIntervalUnit,
                  choices: const [
                    _SettingsChoice(
                      value: TodoReminderIntervalUnits.minutes,
                      label: 'Minutes',
                    ),
                    _SettingsChoice(
                      value: TodoReminderIntervalUnits.hours,
                      label: 'Hours',
                    ),
                  ],
                  onChanged: _useTodoReminderInterval
                      ? (value) =>
                          setState(() => _todoReminderIntervalUnit = value)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              _adaptiveChoiceSelector(
                key: const ValueKey('settings-reminder-scope-selector'),
                labelText: 'Reminder scope',
                compactIcon: Icons.notifications_active_outlined,
                selectedValue: _todoReminderScope,
                choices: const [
                  _SettingsChoice(
                    value: TodoReminderScopes.all,
                    label: 'All due',
                    icon: Icons.format_list_bulleted_outlined,
                  ),
                  _SettingsChoice(
                    value: TodoReminderScopes.nearest,
                    label: 'Nearest',
                    icon: Icons.near_me_outlined,
                  ),
                ],
                onChanged: _useTodoReminderInterval
                    ? (value) => setState(() => _todoReminderScope = value)
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reminderDurationController,
                enabled: _useTodoReminderInterval,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Reminder display seconds',
                  prefixIcon: Icon(Icons.hourglass_bottom_outlined),
                ),
                keyboardType: TextInputType.number,
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.account_tree_outlined),
                title: const Text('Todo-note links'),
                value: _enableTodoNoteLinks,
                onChanged: (value) => setState(() {
                  _enableTodoNoteLinks = value;
                  if (!value) {
                    _hideLinkedNotesFromCapsules = false;
                  }
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.notes_outlined),
                title: const Text('Show linked note name'),
                value: _showLinkedNoteName,
                onChanged: _enableTodoNoteLinks
                    ? (value) => setState(() => _showLinkedNoteName = value)
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.subject_outlined),
                title: const Text('Allow long linked note titles'),
                value: _allowLongLinkedNoteTitles,
                onChanged: _enableTodoNoteLinks && _showLinkedNoteName
                    ? (value) =>
                        setState(() => _allowLongLinkedNoteTitles = value)
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.layers_clear_outlined),
                title: const Text('Hide linked note capsules'),
                value: _hideLinkedNotesFromCapsules,
                onChanged: _enableTodoNoteLinks
                    ? (value) =>
                        setState(() => _hideLinkedNotesFromCapsules = value)
                    : null,
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.sync_outlined),
                title: const Text('WebDAV sync'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
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
                  labelText: 'WebDAV URL',
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
                  labelText: 'Remote folder',
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
                  labelText: 'Username',
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
                  labelText: 'Password',
                  errorText: _passwordErrorText,
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    tooltip: _enableToolTips
                        ? _obscurePassword
                            ? 'Show password'
                            : 'Hide password'
                        : null,
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
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
                  labelText: 'Sync encryption passphrase',
                  helperText:
                      'Required for encrypted Windows and Android sync.',
                  errorText: _encryptionPassphraseErrorText,
                  prefixIcon: const Icon(Icons.enhanced_encryption_outlined),
                  suffixIcon: IconButton(
                    tooltip: _enableToolTips
                        ? _obscureEncryptionPassphrase
                            ? 'Show passphrase'
                            : 'Hide passphrase'
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
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Interval minutes',
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                second: TextField(
                  controller: _requestTimeoutController,
                  enabled: _enabled,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Request timeout seconds',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sync on start'),
                value: _autoSyncOnStart,
                onChanged: _enabled
                    ? (value) =>
                        setState(() => _autoSyncOnStart = value ?? false)
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
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: const Text('Save'),
        ),
      ],
    );
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

  Widget _webDavPresetSelector(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final presetItems = [
      for (final preset in WebDavPresets.recommended)
        DropdownMenuItem(
          value: preset.id,
          child: Text(preset.label),
        ),
      const DropdownMenuItem(
        value: WebDavPresetIds.custom,
        child: Text('Generic'),
      ),
    ];
    if (compact) {
      return DropdownButtonFormField<String>(
        key: const ValueKey('compact-webdav-preset-selector'),
        initialValue: _presetId,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'WebDAV provider',
          prefixIcon: Icon(Icons.cloud_queue_outlined),
        ),
        isExpanded: true,
        items: presetItems,
        onChanged: (value) => _applyPreset(value ?? WebDavPresetIds.custom),
      );
    }
    return SegmentedButton<String>(
      segments: [
        for (final preset in WebDavPresets.recommended)
          ButtonSegment(
            value: preset.id,
            icon: const Icon(Icons.cloud_queue_outlined),
            label: Text(preset.label),
          ),
        const ButtonSegment(
          value: WebDavPresetIds.custom,
          icon: Icon(Icons.dns_outlined),
          label: Text('Generic'),
        ),
      ],
      selected: {_presetId},
      onSelectionChanged: (selection) => _applyPreset(selection.single),
    );
  }

  void _applyPreset(String presetId) {
    setState(() {
      final preset = WebDavPresets.byId(presetId);
      _presetId = preset?.id ?? WebDavPresetIds.custom;
      if (preset != null) {
        _endpointController.text = preset.endpointText;
        _endpointErrorText = null;
        if (_rootPathController.text.trim().isEmpty ||
            _rootPathController.text.trim() == 'repapertodo') {
          _rootPathController.text = preset.defaultRootPath;
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
          ? 'Enter a WebDAV URL.'
          : 'Use a full http:// or https:// WebDAV URL without user info, query, fragment, backslashes, control characters, encoded authority or path separators, blank path segments, or path segment edge spaces.',
      WebDavSyncConfigurationIssue.username => settings.username.isEmpty
          ? 'Enter a WebDAV username.'
          : 'Username cannot contain colons or control characters.',
      WebDavSyncConfigurationIssue.password => settings.password.trim().isEmpty
          ? 'Enter a WebDAV password or app password.'
          : 'Password cannot contain control characters.',
      WebDavSyncConfigurationIssue.rootPath =>
        'Use a remote folder without parent-directory segments, invalid percent escapes, control characters, or blank path segments.',
      WebDavSyncConfigurationIssue.encryptionPassphrase =>
        'Enter a sync encryption passphrase.',
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
    final deepCapsuleTopMargin =
        double.tryParse(_deepCapsuleTopMarginController.text.trim()) ?? 48;
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
        _errorText =
            'Complete the WebDAV URL, username, password, remote folder, and sync encryption passphrase.';
      });
      _focusFirstWebDavIssue(issues);
      return;
    }

    Navigator.of(context).pop(
      SyncSettingsDialogResult(
        sync: settings,
        theme: _theme,
        colorScheme: _colorScheme,
        customThemeColorHex:
            _normalizeColorHex(_customThemeColorController.text),
        markdownRenderMode: _markdownRenderMode,
        todoVisualSize: _todoVisualSize,
        uiFontPreset: _uiFontPreset,
        systemFontFamilyName: _fontFamilyController.text.trim(),
        externalMarkdownExtension:
            _normalizeExtension(_externalMarkdownExtensionController.text),
        zoom: _zoom,
        maxTitleLength: _maxTitleLength.round().clamp(2, 20).toInt(),
        enableToolTips: _enableToolTips,
        enableAnimations: _enableAnimations,
        todoLineSpacing: _todoLineSpacing,
        noteLineSpacing: _noteLineSpacing,
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
        hideLinkedNotesFromCapsules:
            _enableTodoNoteLinks && _hideLinkedNotesFromCapsules,
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

  String _normalizeExtension(String extension) {
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
        value.length > 32 ||
        value.contains('..') ||
        _hasInvalidFileNameCharacter(value)) {
      return '.md';
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
