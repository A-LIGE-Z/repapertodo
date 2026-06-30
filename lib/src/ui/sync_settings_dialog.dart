import 'package:flutter/material.dart';

import '../core/model/sync_settings.dart';

Future<SyncSettings?> showSyncSettingsDialog({
  required BuildContext context,
  required SyncSettings initialSettings,
}) {
  return showDialog<SyncSettings>(
    context: context,
    builder: (context) => SyncSettingsDialog(initialSettings: initialSettings),
  );
}

class SyncSettingsDialog extends StatefulWidget {
  const SyncSettingsDialog({
    required this.initialSettings,
    super.key,
  });

  final SyncSettings initialSettings;

  @override
  State<SyncSettingsDialog> createState() => _SyncSettingsDialogState();
}

class _SyncSettingsDialogState extends State<SyncSettingsDialog> {
  late bool _enabled;
  late bool _autoSyncOnStart;
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
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

    Navigator.of(context).pop(settings);
  }
}
