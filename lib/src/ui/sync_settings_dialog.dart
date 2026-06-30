import 'package:flutter/material.dart';

import '../core/model/paper_constants.dart';
import '../core/model/sync_settings.dart';

class SyncSettingsDialogResult {
  const SyncSettingsDialogResult({
    required this.sync,
    required this.theme,
    required this.colorScheme,
    required this.markdownRenderMode,
    required this.todoVisualSize,
    required this.uiFontPreset,
    required this.systemFontFamilyName,
    required this.zoom,
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
    required this.useCapsuleCollapseAll,
    required this.capsuleCollapseAllActive,
    required this.startAtLogin,
    required this.hideFromWindowSwitcher,
    required this.fullscreenTopmostMode,
    required this.enableTodoNoteLinks,
    required this.showLinkedNoteName,
    required this.allowLongLinkedNoteTitles,
    required this.hideLinkedNotesFromCapsules,
  });

  final SyncSettings sync;
  final String theme;
  final String colorScheme;
  final String markdownRenderMode;
  final String todoVisualSize;
  final String uiFontPreset;
  final String systemFontFamilyName;
  final double zoom;
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
  final bool useCapsuleCollapseAll;
  final bool capsuleCollapseAllActive;
  final bool startAtLogin;
  final bool hideFromWindowSwitcher;
  final String fullscreenTopmostMode;
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
  required String initialMarkdownRenderMode,
  required String initialTodoVisualSize,
  required String initialUiFontPreset,
  required String initialSystemFontFamilyName,
  required double initialZoom,
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
  required bool initialUseCapsuleCollapseAll,
  required bool initialCapsuleCollapseAllActive,
  required bool initialStartAtLogin,
  required bool initialHideFromWindowSwitcher,
  required String initialFullscreenTopmostMode,
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
      initialMarkdownRenderMode: initialMarkdownRenderMode,
      initialTodoVisualSize: initialTodoVisualSize,
      initialUiFontPreset: initialUiFontPreset,
      initialSystemFontFamilyName: initialSystemFontFamilyName,
      initialZoom: initialZoom,
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
      initialUseCapsuleCollapseAll: initialUseCapsuleCollapseAll,
      initialCapsuleCollapseAllActive: initialCapsuleCollapseAllActive,
      initialStartAtLogin: initialStartAtLogin,
      initialHideFromWindowSwitcher: initialHideFromWindowSwitcher,
      initialFullscreenTopmostMode: initialFullscreenTopmostMode,
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
    required this.initialMarkdownRenderMode,
    required this.initialTodoVisualSize,
    required this.initialUiFontPreset,
    required this.initialSystemFontFamilyName,
    required this.initialZoom,
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
    required this.initialUseCapsuleCollapseAll,
    required this.initialCapsuleCollapseAllActive,
    required this.initialStartAtLogin,
    required this.initialHideFromWindowSwitcher,
    required this.initialFullscreenTopmostMode,
    required this.initialEnableTodoNoteLinks,
    required this.initialShowLinkedNoteName,
    required this.initialAllowLongLinkedNoteTitles,
    required this.initialHideLinkedNotesFromCapsules,
    super.key,
  });

  final SyncSettings initialSettings;
  final String initialTheme;
  final String initialColorScheme;
  final String initialMarkdownRenderMode;
  final String initialTodoVisualSize;
  final String initialUiFontPreset;
  final String initialSystemFontFamilyName;
  final double initialZoom;
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
  final bool initialUseCapsuleCollapseAll;
  final bool initialCapsuleCollapseAllActive;
  final bool initialStartAtLogin;
  final bool initialHideFromWindowSwitcher;
  final String initialFullscreenTopmostMode;
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
  late bool _useCapsuleCollapseAll;
  late bool _capsuleCollapseAllActive;
  late bool _startAtLogin;
  late bool _hideFromWindowSwitcher;
  late String _fullscreenTopmostMode;
  late bool _enableTodoNoteLinks;
  late bool _showLinkedNoteName;
  late bool _allowLongLinkedNoteTitles;
  late bool _hideLinkedNotesFromCapsules;
  late String _presetId;
  late bool _obscurePassword = true;
  late final TextEditingController _endpointController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _rootPathController;
  late final TextEditingController _intervalController;
  late final TextEditingController _fontFamilyController;
  late final TextEditingController _reminderIntervalController;
  late final TextEditingController _reminderDurationController;
  String? _errorText;

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
    _zoom = widget.initialZoom.clamp(0.6, 1.8).toDouble();
    _todoLineSpacing = widget.initialTodoLineSpacing.clamp(0.8, 2.4).toDouble();
    _noteLineSpacing = widget.initialNoteLineSpacing.clamp(0.8, 2.4).toDouble();
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
    _useCapsuleCollapseAll = widget.initialUseCapsuleCollapseAll;
    _capsuleCollapseAllActive = widget.initialCapsuleCollapseAllActive;
    _startAtLogin = widget.initialStartAtLogin;
    _hideFromWindowSwitcher = widget.initialHideFromWindowSwitcher;
    _fullscreenTopmostMode =
        FullscreenTopmostModes.normalize(widget.initialFullscreenTopmostMode);
    _enableTodoNoteLinks = widget.initialEnableTodoNoteLinks;
    _showLinkedNoteName = widget.initialShowLinkedNoteName;
    _allowLongLinkedNoteTitles = widget.initialAllowLongLinkedNoteTitles;
    _hideLinkedNotesFromCapsules = widget.initialHideLinkedNotesFromCapsules;
    _presetId = webDav.presetId;
    _endpointController = TextEditingController(text: webDav.endpoint);
    _usernameController = TextEditingController(text: webDav.username);
    _passwordController = TextEditingController(text: webDav.password);
    _rootPathController = TextEditingController(text: webDav.rootPath);
    _intervalController =
        TextEditingController(text: webDav.autoSyncIntervalMinutes.toString());
    _fontFamilyController =
        TextEditingController(text: widget.initialSystemFontFamilyName);
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
    _rootPathController.dispose();
    _intervalController.dispose();
    _fontFamilyController.dispose();
    _reminderIntervalController.dispose();
    _reminderDurationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.sync_outlined),
          SizedBox(width: 12),
          Text('Sync settings'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'system',
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: 'light',
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: 'dark',
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark'),
                  ),
                ],
                selected: {_theme},
                onSelectionChanged: (selection) =>
                    setState(() => _theme = selection.single),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: ColorSchemes.warm,
                    label: Text('Warm'),
                  ),
                  ButtonSegment(
                    value: ColorSchemes.ink,
                    label: Text('Ink'),
                  ),
                  ButtonSegment(
                    value: ColorSchemes.forest,
                    label: Text('Forest'),
                  ),
                  ButtonSegment(
                    value: ColorSchemes.rose,
                    label: Text('Rose'),
                  ),
                ],
                selected: {_colorScheme},
                onSelectionChanged: (selection) =>
                    setState(() => _colorScheme = selection.single),
              ),
              const SizedBox(height: 16),
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: MarkdownRenderModes.off,
                    icon: Icon(Icons.edit_outlined),
                    label: Text('Markdown off'),
                  ),
                  ButtonSegment(
                    value: MarkdownRenderModes.basic,
                    icon: Icon(Icons.article_outlined),
                    label: Text('Basic'),
                  ),
                  ButtonSegment(
                    value: MarkdownRenderModes.enhanced,
                    icon: Icon(Icons.vertical_split_outlined),
                    label: Text('Enhanced'),
                  ),
                ],
                selected: {_markdownRenderMode},
                onSelectionChanged: (selection) =>
                    setState(() => _markdownRenderMode = selection.single),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: TodoVisualSizes.small,
                    label: Text('Small'),
                  ),
                  ButtonSegment(
                    value: TodoVisualSizes.medium,
                    label: Text('Medium'),
                  ),
                  ButtonSegment(
                    value: TodoVisualSizes.large,
                    label: Text('Large'),
                  ),
                  ButtonSegment(
                    value: TodoVisualSizes.extraLarge,
                    label: Text('XL'),
                  ),
                ],
                selected: {_todoVisualSize},
                onSelectionChanged: (selection) =>
                    setState(() => _todoVisualSize = selection.single),
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
              _SettingsSlider(
                icon: Icons.zoom_in_outlined,
                label: 'Zoom',
                valueLabel: '${(_zoom * 100).round()}%',
                value: _zoom,
                min: 0.6,
                max: 1.8,
                divisions: 12,
                onChanged: (value) => setState(() => _zoom = value),
              ),
              _SettingsSlider(
                icon: Icons.checklist_outlined,
                label: 'Todo spacing',
                valueLabel: _todoLineSpacing.toStringAsFixed(1),
                value: _todoLineSpacing,
                min: 0.8,
                max: 2.4,
                divisions: 16,
                onChanged: (value) => setState(() => _todoLineSpacing = value),
              ),
              _SettingsSlider(
                icon: Icons.notes_outlined,
                label: 'Note spacing',
                valueLabel: _noteLineSpacing.toStringAsFixed(1),
                value: _noteLineSpacing,
                min: 0.8,
                max: 2.4,
                divisions: 16,
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
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: TodoDueYearDisplayModes.none,
                    label: Text('No year'),
                  ),
                  ButtonSegment(
                    value: TodoDueYearDisplayModes.short,
                    label: Text('YY'),
                  ),
                  ButtonSegment(
                    value: TodoDueYearDisplayModes.full,
                    label: Text('YYYY'),
                  ),
                ],
                selected: {_todoDueYearDisplayMode},
                onSelectionChanged: _showTodoDueRelativeTime
                    ? null
                    : (selection) => setState(
                        () => _todoDueYearDisplayMode = selection.single),
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
                secondary: const Icon(Icons.unfold_less_outlined),
                title: const Text('Collapse all control'),
                value: _useCapsuleCollapseAll,
                onChanged: (value) => setState(() {
                  _useCapsuleCollapseAll = value;
                  if (!value) {
                    _capsuleCollapseAllActive = false;
                  }
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.vertical_align_center_outlined),
                title: const Text('Collapse all active'),
                value: _capsuleCollapseAllActive,
                onChanged: _useCapsuleCollapseAll
                    ? (value) =>
                        setState(() => _capsuleCollapseAllActive = value)
                    : null,
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.login_outlined),
                title: const Text('Start at login'),
                value: _startAtLogin,
                onChanged: (value) => setState(() => _startAtLogin = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide from task switcher'),
                value: _hideFromWindowSwitcher,
                onChanged: (value) =>
                    setState(() => _hideFromWindowSwitcher = value),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: FullscreenTopmostModes.avoid,
                    icon: Icon(Icons.fullscreen_exit_outlined),
                    label: Text('Avoid fullscreen'),
                  ),
                  ButtonSegment(
                    value: FullscreenTopmostModes.stayOnTop,
                    icon: Icon(Icons.push_pin_outlined),
                    label: Text('Stay on top'),
                  ),
                ],
                selected: {_fullscreenTopmostMode},
                onSelectionChanged: (selection) => setState(
                  () => _fullscreenTopmostMode = selection.single,
                ),
              ),
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reminderIntervalController,
                      enabled: _useTodoReminderInterval,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Reminder interval',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: TodoReminderIntervalUnits.minutes,
                          label: Text('Minutes'),
                        ),
                        ButtonSegment(
                          value: TodoReminderIntervalUnits.hours,
                          label: Text('Hours'),
                        ),
                      ],
                      selected: {_todoReminderIntervalUnit},
                      onSelectionChanged: _useTodoReminderInterval
                          ? (selection) => setState(
                                () => _todoReminderIntervalUnit =
                                    selection.single,
                              )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: TodoReminderScopes.all,
                    icon: Icon(Icons.format_list_bulleted_outlined),
                    label: Text('All due'),
                  ),
                  ButtonSegment(
                    value: TodoReminderScopes.nearest,
                    icon: Icon(Icons.near_me_outlined),
                    label: Text('Nearest'),
                  ),
                ],
                selected: {_todoReminderScope},
                onSelectionChanged: _useTodoReminderInterval
                    ? (selection) =>
                        setState(() => _todoReminderScope = selection.single)
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
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: WebDavPresetIds.jianguoyun,
                    icon: Icon(Icons.cloud_queue_outlined),
                    label: Text('Jianguoyun'),
                  ),
                  ButtonSegment(
                    value: WebDavPresetIds.custom,
                    icon: Icon(Icons.dns_outlined),
                    label: Text('Generic'),
                  ),
                ],
                selected: {_presetId},
                onSelectionChanged: (selection) =>
                    _applyPreset(selection.single),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _endpointController,
                enabled: _enabled,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'WebDAV URL',
                  prefixIcon: Icon(Icons.link_outlined),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rootPathController,
                enabled: _enabled,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Remote folder',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                enabled: _enabled,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                enabled: _enabled,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    tooltip:
                        _obscurePassword ? 'Show password' : 'Hide password',
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
                controller: _intervalController,
                enabled: _enabled,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Interval minutes',
                  prefixIcon: Icon(Icons.schedule_outlined),
                ),
                keyboardType: TextInputType.number,
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

  void _applyPreset(String presetId) {
    setState(() {
      _presetId = presetId;
      if (presetId == WebDavPresetIds.jianguoyun) {
        _endpointController.text = 'https://dav.jianguoyun.com/dav/';
        if (_rootPathController.text.trim().isEmpty ||
            _rootPathController.text.trim() == 'repapertodo') {
          _rootPathController.text = 'RePaperTodo';
        }
      }
    });
  }

  void _save() {
    final interval = int.tryParse(_intervalController.text.trim());
    final reminderInterval =
        int.tryParse(_reminderIntervalController.text.trim()) ?? 10;
    final reminderDuration =
        int.tryParse(_reminderDurationController.text.trim()) ?? 5;
    final settings = SyncSettings(
      enabled: _enabled,
      provider: _enabled ? SyncProviderIds.webDav : SyncProviderIds.none,
      webDav: WebDavSyncSettings(
        presetId: _presetId,
        endpoint: _endpointController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        rootPath: _rootPathController.text,
        autoSyncOnStart: _autoSyncOnStart,
        autoSyncIntervalMinutes: interval ?? 15,
      ),
    )..normalize();

    if (_enabled && !settings.webDav.isConfigured) {
      setState(() => _errorText =
          'Complete the WebDAV URL, username, password, and remote folder.');
      return;
    }

    Navigator.of(context).pop(
      SyncSettingsDialogResult(
        sync: settings,
        theme: _theme,
        colorScheme: _colorScheme,
        markdownRenderMode: _markdownRenderMode,
        todoVisualSize: _todoVisualSize,
        uiFontPreset: _uiFontPreset,
        systemFontFamilyName: _fontFamilyController.text.trim(),
        zoom: _zoom,
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
        useCapsuleCollapseAll: _useCapsuleCollapseAll,
        capsuleCollapseAllActive:
            _useCapsuleCollapseAll && _capsuleCollapseAllActive,
        startAtLogin: _startAtLogin,
        hideFromWindowSwitcher: _hideFromWindowSwitcher,
        fullscreenTopmostMode: _fullscreenTopmostMode,
        enableTodoNoteLinks: _enableTodoNoteLinks,
        showLinkedNoteName: _showLinkedNoteName,
        allowLongLinkedNoteTitles: _allowLongLinkedNoteTitles,
        hideLinkedNotesFromCapsules:
            _enableTodoNoteLinks && _hideLinkedNotesFromCapsules,
      ),
    );
  }

  String _normalizeTheme(String theme) {
    return switch (theme) {
      'light' || 'dark' || 'system' => theme,
      _ => 'system',
    };
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
