import '../core/model/app_state.dart';
import '../core/model/sync_settings.dart';
import '../core/storage/state_store.dart';
import 'webdav/webdav_state_sync_service.dart';

typedef WebDavStateSyncServiceFactory = WebDavStateSyncService Function(
  WebDavSyncSettings settings,
);

enum AppSyncStatus {
  disabled,
  configurationMissing,
  uploaded,
  downloaded,
  conflict,
}

class AppSyncResult {
  const AppSyncResult({
    required this.status,
    this.state,
    this.message = '',
  });

  final AppSyncStatus status;
  final AppState? state;
  final String message;
}

class AppSyncService {
  AppSyncService({
    WebDavStateSyncServiceFactory? webDavFactory,
  }) : _webDavFactory = webDavFactory ?? WebDavStateSyncService.fromSettings;

  final WebDavStateSyncServiceFactory _webDavFactory;

  Future<AppSyncResult> syncNow({
    required AppState localState,
    required StateStore store,
    DateTime? localUpdatedAtUtc,
  }) async {
    localState.normalize();
    final settings = localState.sync;
    if (!settings.enabled) {
      return const AppSyncResult(
        status: AppSyncStatus.disabled,
        message: 'Sync is disabled.',
      );
    }
    if (settings.provider != SyncProviderIds.webDav ||
        !settings.webDav.isConfigured) {
      return const AppSyncResult(
        status: AppSyncStatus.configurationMissing,
        message: 'Complete WebDAV sync settings first.',
      );
    }

    final client = _webDavFactory(settings.webDav.copy());
    final result = await client.sync(
      localState: localState,
      localUpdatedAtUtc: localUpdatedAtUtc ?? await store.lastModifiedUtc(),
    );

    switch (result.status) {
      case WebDavStateSyncStatus.uploaded:
      case WebDavStateSyncStatus.remoteMissing:
        await store.save(localState);
        return const AppSyncResult(
          status: AppSyncStatus.uploaded,
          message: 'Local data uploaded.',
        );
      case WebDavStateSyncStatus.downloaded:
        final remoteState = result.state;
        if (remoteState == null) {
          return const AppSyncResult(
            status: AppSyncStatus.configurationMissing,
            message: 'Remote snapshot is empty.',
          );
        }
        await store.save(remoteState);
        return AppSyncResult(
          status: AppSyncStatus.downloaded,
          state: remoteState,
          message: 'Remote data downloaded.',
        );
      case WebDavStateSyncStatus.conflict:
        return const AppSyncResult(
          status: AppSyncStatus.conflict,
          message: 'Remote data changed during sync. Pull again before upload.',
        );
    }
  }
}
