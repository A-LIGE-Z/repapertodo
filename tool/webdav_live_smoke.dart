import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/model/sync_settings.dart';
import 'package:repapertodo/src/core/storage/state_store.dart';
import 'package:repapertodo/src/sync/app_sync_service.dart';
import 'package:repapertodo/src/sync/sync_device_id_store.dart';
import 'package:repapertodo/src/sync/webdav/webdav_client.dart';
import 'package:repapertodo/src/sync/webdav/webdav_presets.dart';

Future<void> main() async {
  final env = Platform.environment;
  final endpoint = _requiredEnv(env, 'REPAPERTODO_WEBDAV_ENDPOINT');
  final username = _requiredEnv(env, 'REPAPERTODO_WEBDAV_USERNAME');
  final password = _requiredEnv(env, 'REPAPERTODO_WEBDAV_PASSWORD');
  final passphrase = _requiredEnv(env, 'REPAPERTODO_WEBDAV_PASSPHRASE');
  final provider = _optionalEnv(env, 'REPAPERTODO_WEBDAV_PROVIDER') ??
      WebDavPresetIds.custom;
  final baseRoot =
      _optionalEnv(env, 'REPAPERTODO_WEBDAV_ROOT') ?? 'repapertodo-live-smoke';
  final keepRemote = _parseBool(env['REPAPERTODO_WEBDAV_KEEP_REMOTE']);
  final timeoutSeconds =
      int.tryParse(env['REPAPERTODO_WEBDAV_TIMEOUT_SECONDS'] ?? '') ?? 30;

  final runId = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[^0-9A-Za-z]'),
        '',
      );
  final rootPath = '${_cleanPathSegment(baseRoot)}/run-$runId';
  final directory = await Directory.systemTemp.createTemp(
    'repapertodo_webdav_live_smoke_',
  );
  final windowsStore = StateStore(
    filePath: p.join(directory.path, 'windows-data.json'),
  );
  final androidStore = StateStore(
    filePath: p.join(directory.path, 'android-data.json'),
  );
  final windowsDeviceIdStore = SyncDeviceIdStore(
    filePath: p.join(directory.path, 'windows-device-id.txt'),
  );
  final androidDeviceIdStore = SyncDeviceIdStore(
    filePath: p.join(directory.path, 'android-device-id.txt'),
  );
  await File(windowsDeviceIdStore.filePath).writeAsString(
    'windows-live-smoke',
    flush: true,
  );
  await File(androidDeviceIdStore.filePath).writeAsString(
    'android-live-smoke',
    flush: true,
  );

  final settings = SyncSettings(
    enabled: true,
    provider: SyncProviderIds.webDav,
    webDav: WebDavSyncSettings(
      presetId: provider,
      endpoint: endpoint,
      username: username,
      password: password,
      encryptionPassphrase: passphrase,
      rootPath: rootPath,
      requestTimeoutSeconds: timeoutSeconds,
    ),
  );
  final windowsService = AppSyncService(deviceIdStore: windowsDeviceIdStore);
  final androidService = AppSyncService(deviceIdStore: androidDeviceIdStore);
  final startedAtUtc = DateTime.now().toUtc();

  try {
    final windowsInitial = AppState(
      sync: settings.copy(),
      papers: [
        PaperData(
          id: 'live-smoke-shared-note',
          type: PaperTypes.note,
          title: 'Live smoke',
          content: 'Windows live smoke upload',
        ),
      ],
    );
    await windowsStore.save(windowsInitial);
    final windowsUpload = await windowsService.syncAndMergeNow(
      localState: windowsInitial,
      store: windowsStore,
      localUpdatedAtUtc: DateTime.utc(2026, 7, 3, 9),
    );
    _requireStatus(
      windowsUpload.syncResult.status,
      AppSyncStatus.uploaded,
      'Windows initial upload',
    );

    final androidDownload = await androidService.syncAndMergeNow(
      localState: AppState(sync: settings.copy()),
      store: androidStore,
      localUpdatedAtUtc: DateTime.utc(2026, 7, 3, 8),
    );
    _requireStatus(
      androidDownload.syncResult.status,
      AppSyncStatus.downloaded,
      'Android snapshot download',
    );
    if (androidDownload.state.papers.single.content !=
        'Windows live smoke upload') {
      throw StateError('Android side did not download the Windows note body.');
    }

    final androidBeforeEdit = await androidStore.load();
    final androidAfterEdit = AppState.fromJson(androidBeforeEdit.toJson());
    androidAfterEdit.papers.single.content = 'Android live smoke edit';
    final androidOperationUpload = await androidService.uploadLocalOperations(
      beforeState: androidBeforeEdit,
      afterState: androidAfterEdit,
      store: androidStore,
      createdAtUtc: DateTime.utc(2026, 7, 3, 9, 5),
    );
    if (androidOperationUpload.uploadedCount != 1) {
      throw StateError(
        'Android operation upload expected 1 log, got '
        '${androidOperationUpload.uploadedCount}.',
      );
    }

    final windowsMerge = await windowsService.mergeRemoteOperations(
      localState: await windowsStore.load(),
      store: windowsStore,
    );
    if (windowsMerge.appliedCount != 1 ||
        windowsMerge.state.papers.single.content != 'Android live smoke edit') {
      throw StateError('Windows side did not merge the Android operation log.');
    }

    final result = {
      'status': 'passed',
      'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'startedAtUtc': startedAtUtc.toIso8601String(),
      'endpointHost': Uri.parse(endpoint).host,
      'providerId': provider,
      'rootPath': rootPath,
      'windowsUploadStatus': windowsUpload.syncResult.status.name,
      'androidDownloadStatus': androidDownload.syncResult.status.name,
      'androidOperationUploadedCount': androidOperationUpload.uploadedCount,
      'windowsOperationAppliedCount': windowsMerge.appliedCount,
      'deviceSequences': windowsMerge.deviceSequences,
      'remoteCleanup': keepRemote ? 'skipped' : 'attempted',
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  } finally {
    if (!keepRemote) {
      await _tryDeleteRemoteRoot(
        endpoint: endpoint,
        username: username,
        password: password,
        rootPath: rootPath,
        timeoutSeconds: timeoutSeconds,
      );
    }
    await directory.delete(recursive: true);
  }
}

String _requiredEnv(Map<String, String> env, String name) {
  final value = _optionalEnv(env, name);
  if (value == null) {
    throw StateError('Missing required environment variable: $name');
  }
  return value;
}

String? _optionalEnv(Map<String, String> env, String name) {
  final value = env[name]?.trim();
  if (value == null || value.isEmpty || _hasControlCharacter(value)) {
    return null;
  }
  return value;
}

bool _parseBool(String? value) {
  return switch (value?.trim().toLowerCase()) {
    '1' || 'true' || 'yes' || 'y' => true,
    _ => false,
  };
}

String _cleanPathSegment(String value) {
  final cleaned = value
      .trim()
      .replaceAll(RegExp(r'[/\\]+'), '-')
      .replaceAll(RegExp(r'[^0-9A-Za-z._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  if (cleaned.isEmpty) {
    return 'repapertodo-live-smoke';
  }
  return cleaned;
}

bool _hasControlCharacter(String value) {
  return value.runes.any(
    (rune) => rune < 0x20 || (rune >= 0x7F && rune <= 0x9F),
  );
}

void _requireStatus(
  AppSyncStatus actual,
  AppSyncStatus expected,
  String context,
) {
  if (actual != expected) {
    throw StateError('$context expected $expected, got $actual.');
  }
}

Future<void> _tryDeleteRemoteRoot({
  required String endpoint,
  required String username,
  required String password,
  required String rootPath,
  required int timeoutSeconds,
}) async {
  final client = WebDavClient(
    baseUri: Uri.parse(endpoint),
    credentials: WebDavCredentials(username: username, password: password),
    requestTimeout: Duration(seconds: timeoutSeconds),
  );
  try {
    await client.delete(rootPath);
  } catch (error) {
    stderr
        .writeln('Warning: failed to clean live-smoke root $rootPath: $error');
  } finally {
    client.close();
  }
}
