import 'package:flutter/material.dart';

import '../core/model/paper_constants.dart';
import '../core/model/sync_settings.dart';

class SyncSettingsDialogResult {
  const SyncSettingsDialogResult({
    required this.sync,
    required this.theme,
    required this.colorScheme,
    required this.startAtLogin,
    required this.hideFromWindowSwitcher,
    required this.fullscreenTopmostMode,
    required this.enableTodoNoteLinks,
    required this.showLinkedNoteName,
    required this.allowLongLinkedNoteTitles,
  });

  final SyncSettings sync;
  final String theme;
  final String colorScheme;
  final bool startAtLogin;
  final bool hideFromWindowSwitcher;
  final String fullscreenTopmostMode;
  final bool enableTodoNoteLinks;
  final bool showLinkedNoteName;
  final bool allowLongLinkedNoteTitles;
}

Future<SyncSettingsDialogResult?> showSyncSettingsDialog({
  required BuildContext context,
  required SyncSettings initialSettings,
  required String initialTheme,
  required String initialColorScheme,
  required bool initialStartAtLogin,
  required bool initialHideFromWindowSwitcher,
  required String initialFullscreenTopmostMode,
  required bool initialEnableTodoNoteLinks,
  required bool initialShowLinkedNoteName,
  required bool initialAllowLongLinkedNoteTitles,
}) {
  return showDialog<SyncSettingsDialogResult>(
    context: context,
    builder: (context) => SyncSettingsDialog(
      initialSettings: initialSettings,
      initialTheme: initialTheme,
      initialColorScheme: initialColorScheme,
      initialStartAtLogin: initialStartAtLogin,
      initialHideFromWindowSwitcher: initialHideFromWindowSwitcher,
      initialFullscreenTopmostMode: initialFullscreenTopmostMode,
      initialEnableTodoNoteLinks: initialEnableTodoNoteLinks,
      initialShowLinkedNoteName: initialShowLinkedNoteName,
      initialAllowLongLinkedNoteTitles: initialAllowLongLinkedNoteTitles,
    ),
  );
}

class SyncSettingsDialog extends StatefulWidget {
  const SyncSettingsDialog({
    required this.initialSettings,
    required this.initialTheme,
    required this.initialColorScheme,
    required this.initialStartAtLogin,
    required this.initialHideFromWindowSwitcher,
    required this.initialFullscreenTopmostMode,
    required this.initialEnableTodoNoteLinks,
    required this.initialShowLinkedNoteName,
    required this.initialAllowLongLinkedNoteTitles,
    super.key,
  });

  final SyncSettings initialSettings;
  final String initialTheme;
  final String initialColorScheme;
  final bool initialStartAtLogin;
  final bool initialHideFromWindowSwitcher;
  final String initialFullscreenTopmostMode;
  final bool initialEnableTodoNoteLinks;
  final bool initialShowLinkedNoteName;
  final bool initialAllowLongLinkedNoteTitles;

  @override
  State<SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends State<SyncSettingsDialog> {
  late bool _enabled;
  late bool _autoSyncOnStart;
  late String _theme;
  late String _colorScheme;
  late bool _startAtLogin;
  late bool _hideFromWindowSwitcher;
  late String _fullscreenTopmostMode;
  late bool _enableTodoNoteLinks;
  late bool _showLinkedNoteName;
  late bool _allowLongLinkedNoteTitles;
  late String _presetId;
  late bool _obscurePassword = true;
  late final TextEditingController _endpointController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _rootPathController;
  late final TextEditingController _intervalController;
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
    _startAtLogin = widget.initialStartAtLogin;
    _hideFromWindowSwitcher = widget.initialHideFromWindowSwitcher;
    _fullscreenTopmostMode =
        FullscreenTopmostModes.normalize(widget.initialFullscreenTopmostMode);
    _enableTodoNoteLinks = widget.initialEnableTodoNoteLinks;
    _showLinkedNoteName = widget.initialShowLinkedNoteName;
    _allowLongLinkedNoteTitles = widget.initialAllowLongLinkedNoteTitles;
    _presetId = webDav.presetId;
    _endpointController = TextEditingController(text: webDav.endpoint);
    _usernameController = TextEditingController(text: webDav.username);
    _passwordController = TextEditingController(text: webDav.password);
    _rootPathController = TextEditingController(text: webDav.rootPath);
    _intervalController =
        TextEditingController(text: webDav.autoSyncIntervalMinutes.toString());
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _rootPathController.dispose();
    _intervalController.dispose();
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
                secondary: const Icon(Icons.account_tree_outlined),
                title: const Text('Todo-note links'),
                value: _enableTodoNoteLinks,
                onChanged: (value) =>
                    setState(() => _enableTodoNoteLinks = value),
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
        startAtLogin: _startAtLogin,
        hideFromWindowSwitcher: _hideFromWindowSwitcher,
        fullscreenTopmostMode: _fullscreenTopmostMode,
        enableTodoNoteLinks: _enableTodoNoteLinks,
        showLinkedNoteName: _showLinkedNoteName,
        allowLongLinkedNoteTitles: _allowLongLinkedNoteTitles,
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
