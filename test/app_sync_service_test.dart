import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('returns disabled when sync is off', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_disabled_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) =>
          throw StateError('WebDAV should not be created'),
    );

    final result = await service.syncNow(
      localState: AppState(),
      store: store,
    );

    expect(result.status, AppSyncStatus.disabled);
  });

  test('uploads configured local state', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_upload_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final localState = AppState(
      papers: [
        PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
      ],
      sync: _configuredSyncSettings(),
    );
    var uploadedStateTitle = '';
    var forwardedDeviceId = '';
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        forwardedDeviceId = deviceId ?? '';
        return _FakeWebDavStateSyncService(
          onSync: ({required localState, localUpdatedAtUtc}) async {
            uploadedStateTitle = localState.papers.single.title;
            return WebDavStateSyncResult(
              status: WebDavStateSyncStatus.uploaded,
              snapshotPath: 'repapertodo/snapshots/local.json',
              manifest: SyncManifest(
                schemaVersion: 1,
                updatedAtUtc: DateTime.utc(2026, 6, 30),
                latestSnapshotPath: 'repapertodo/snapshots/local.json',
                deviceSequences: {'remote-device': 4, 'local-device': 1},
              ),
            );
          },
        );
      },
    );

    final result = await service.syncNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 6, 30),
    );

    expect(result.status, AppSyncStatus.uploaded);
    expect(result.snapshotPath, 'repapertodo/snapshots/local.json');
    expect(uploadedStateTitle, 'Local');
    expect(forwardedDeviceId, startsWith('device-'));
    final stored = await store.load();
    expect(stored.papers.single.title, 'Local');
    expect(stored.sync.operationDeviceSequences, {
      'remote-device': 4,
      'local-device': 1,
    });
    expect(
      await File(p.join(directory.path, 'sync-device-id')).readAsString(),
      forwardedDeviceId,
    );
  });

  test('saves downloaded remote state', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_download_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final remoteState = AppState(
      papers: [
        PaperData(id: 'paper-remote', type: PaperTypes.note, title: 'Remote'),
      ],
      sync: _configuredSyncSettings(),
    );
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: remoteState,
            snapshotPath: 'repapertodo/snapshots/remote.json',
            manifest: SyncManifest(
              schemaVersion: 1,
              updatedAtUtc: DateTime.utc(2026, 6, 30, 11),
              latestSnapshotPath: 'repapertodo/snapshots/remote.json',
              deviceSequences: {'remote-device': 7},
            ),
          );
        },
      ),
    );

    final result = await service.syncNow(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 6, 30),
    );

    expect(result.status, AppSyncStatus.downloaded);
    expect(result.snapshotPath, 'repapertodo/snapshots/remote.json');
    expect(result.state?.papers.single.title, 'Remote');
    final stored = await store.load();
    expect(stored.papers.single.title, 'Remote');
    expect(stored.sync.operationDeviceSequences, {'remote-device': 7});
  });

  test('closes configured WebDAV clients after sync and merge', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_close_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var createdCount = 0;
    var closedCount = 0;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) {
        createdCount += 1;
        return _FakeWebDavStateSyncService(
          onSync: ({required localState, localUpdatedAtUtc}) async {
            return const WebDavStateSyncResult(
              status: WebDavStateSyncStatus.uploaded,
              snapshotPath: 'repapertodo/snapshots/local.json',
            );
          },
          onListOperationLogs: () async => const [],
          onClose: () => closedCount += 1,
        );
      },
    );

    final result = await service.syncAndMergeNow(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.syncResult.status, AppSyncStatus.uploaded);
    expect(createdCount, 2);
    expect(closedCount, 2);
  });

  test('closes configured WebDAV client when sync fails', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_close_error_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var closedCount = 0;
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) {
        return _FakeWebDavStateSyncService(
          onSync: ({required localState, localUpdatedAtUtc}) async {
            throw StateError('network failed');
          },
          onClose: () => closedCount += 1,
        );
      },
    );

    await expectLater(
      service.syncNow(
        localState: AppState(sync: _configuredSyncSettings()),
        store: store,
        localUpdatedAtUtc: DateTime.utc(2026, 7),
      ),
      throwsA(isA<StateError>()),
    );

    expect(closedCount, 1);
  });

  test('reports WebDAV conflicts without saving local state', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_conflict_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return const WebDavStateSyncResult(
            status: WebDavStateSyncStatus.conflict,
            snapshotPath: 'repapertodo/snapshots/conflict-local.json',
          );
        },
      ),
    );

    final result = await service.syncNow(
      localState: AppState(
        papers: [
          PaperData(id: 'paper-local', type: PaperTypes.todo, title: 'Local'),
        ],
        sync: _configuredSyncSettings(),
      ),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.status, AppSyncStatus.conflict);
    expect(result.snapshotPath, 'repapertodo/snapshots/conflict-local.json');
    expect(result.message, contains('conflict-local.json'));
    expect(await File(store.filePath).exists(), isFalse);
  });

  test('syncAndMergeNow applies remote operations after sync succeeds',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_and_merge_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return const WebDavStateSyncResult(
            status: WebDavStateSyncStatus.uploaded,
            snapshotPath: 'repapertodo/snapshots/local.json',
          );
        },
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000001.jsonl',
              deviceId: 'device-a',
              sequence: 1,
            ),
          ];
        },
        onDownloadOperationLog: (operationLogPath) async {
          return [
            SyncOperation(
              id: 'device-a-1',
              deviceId: 'device-a',
              sequence: 1,
              kind: SyncOperationKind.upsertPaper,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9),
              payload: {
                'paper': PaperData(
                  id: 'remote-note',
                  type: PaperTypes.note,
                  title: 'Merged',
                ).toJson(),
              },
            ),
          ];
        },
      ),
    );

    final result = await service.syncAndMergeNow(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.syncResult.status, AppSyncStatus.uploaded);
    expect(result.operationAppliedCount, 1);
    expect(result.state.papers.single.title, 'Merged');
    expect((await store.load()).papers.single.title, 'Merged');
  });

  test('syncAndMergeNow skips remote operations after sync conflict', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_and_merge_conflict_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onSync: ({required localState, localUpdatedAtUtc}) async {
          return const WebDavStateSyncResult(
            status: WebDavStateSyncStatus.conflict,
            snapshotPath: 'repapertodo/snapshots/conflict-local.json',
          );
        },
        onListOperationLogs: () async {
          throw StateError('Conflicted sync should not merge operations.');
        },
      ),
    );
    final localState = AppState(
      papers: [
        PaperData(id: 'local', type: PaperTypes.todo, title: 'Local'),
      ],
      sync: _configuredSyncSettings(),
    );

    final result = await service.syncAndMergeNow(
      localState: localState,
      store: store,
      localUpdatedAtUtc: DateTime.utc(2026, 7),
    );

    expect(result.syncResult.status, AppSyncStatus.conflict);
    expect(result.operationMergeResult, isNull);
    expect(result.state.papers.single.title, 'Local');
    expect(await File(store.filePath).exists(), isFalse);
  });

  test('lists recovery snapshots through configured WebDAV', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_list_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var forwardedDeviceId = '';
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        forwardedDeviceId = deviceId ?? '';
        return _FakeWebDavStateSyncService(
          onListSnapshots: () async {
            return [
              WebDavSnapshotRecord(
                path: 'repapertodo/snapshots/snapshot.json',
                deviceId: forwardedDeviceId,
                updatedAtUtc: DateTime.utc(2026, 7),
              ),
            ];
          },
        );
      },
    );

    final snapshots = await service.listRecoverySnapshots(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
    );

    expect(snapshots, hasLength(1));
    expect(snapshots.single.deviceId, startsWith('device-'));
    expect(forwardedDeviceId, snapshots.single.deviceId);
  });

  test('lists operation logs through configured WebDAV', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    var forwardedDeviceId = '';
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        forwardedDeviceId = deviceId ?? '';
        return _FakeWebDavStateSyncService(
          onListOperationLogs: () async {
            return [
              WebDavOperationLogRecord(
                path: 'repapertodo/ops/$forwardedDeviceId-000000000001.jsonl',
                deviceId: forwardedDeviceId,
                sequence: 1,
              ),
            ];
          },
        );
      },
    );

    final logs = await service.listRemoteOperationLogs(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
    );

    expect(logs, hasLength(1));
    expect(logs.single.deviceId, startsWith('device-'));
    expect(logs.single.sequence, 1);
    expect(forwardedDeviceId, logs.single.deviceId);
  });

  test('downloads operation logs through configured WebDAV', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_download_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onDownloadOperationLog: (operationLogPath) async {
          return [
            SyncOperation(
              id: 'device-1',
              deviceId: deviceId ?? '',
              sequence: 1,
              kind: SyncOperationKind.stateSnapshot,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9),
              payload: {'path': operationLogPath},
            ),
          ];
        },
      ),
    );

    final operations = await service.downloadRemoteOperationLog(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      operationLogPath: 'repapertodo/ops/device-000000000001.jsonl',
    );

    expect(operations, hasLength(1));
    expect(operations.single.kind, SyncOperationKind.stateSnapshot);
    expect(operations.single.payload['path'],
        'repapertodo/ops/device-000000000001.jsonl');
  });

  test('merges remote operation logs and saves applied state', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_merge_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000001.jsonl',
              deviceId: 'device-a',
              sequence: 1,
            ),
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000002.jsonl',
              deviceId: 'device-a',
              sequence: 2,
            ),
          ];
        },
        onDownloadOperationLog: (operationLogPath) async {
          if (operationLogPath.endsWith('000000000001.jsonl')) {
            return [
              SyncOperation(
                id: 'device-a-1',
                deviceId: 'device-a',
                sequence: 1,
                kind: SyncOperationKind.upsertPaper,
                createdAtUtc: DateTime.utc(2026, 7, 1, 9),
                payload: {
                  'paper': PaperData(
                    id: 'remote-note',
                    type: PaperTypes.note,
                    title: 'Remote',
                    content: 'Old',
                  ).toJson(),
                },
              ),
            ];
          }
          return [
            SyncOperation(
              id: 'device-a-2',
              deviceId: 'device-a',
              sequence: 2,
              kind: SyncOperationKind.updateNoteContent,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9, 1),
              payload: {
                'paperId': 'remote-note',
                'content': 'Merged body',
              },
            ),
          ];
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
    );

    expect(result.appliedCount, 2);
    expect(result.deviceSequences, {'device-a': 2});
    expect(result.state.sync.operationDeviceSequences, {'device-a': 2});
    expect(result.state.papers.single.title, 'Remote');
    expect(result.state.papers.single.content, 'Merged body');
    final stored = await store.load();
    expect(stored.papers.single.content, 'Merged body');
    expect(stored.sync.operationDeviceSequences, {'device-a': 2});
  });

  test('merge waits at gaps in remote operation sequences', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_gap_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final downloadedPaths = <String>[];
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000003.jsonl',
              deviceId: 'device-a',
              sequence: 3,
            ),
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000001.jsonl',
              deviceId: 'device-a',
              sequence: 1,
            ),
          ];
        },
        onDownloadOperationLog: (operationLogPath) async {
          downloadedPaths.add(operationLogPath);
          if (operationLogPath.endsWith('000000000003.jsonl')) {
            throw StateError('Gapped operation logs should not be downloaded.');
          }
          return [
            SyncOperation(
              id: 'device-a-1',
              deviceId: 'device-a',
              sequence: 1,
              kind: SyncOperationKind.upsertPaper,
              createdAtUtc: DateTime.utc(2026, 7, 1, 9),
              payload: {
                'paper': PaperData(
                  id: 'remote-note',
                  type: PaperTypes.note,
                  title: 'First',
                ).toJson(),
              },
            ),
          ];
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
    );

    expect(result.appliedCount, 1);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.sync.operationDeviceSequences, {'device-a': 1});
    expect(result.state.papers.single.title, 'First');
    expect(downloadedPaths, ['repapertodo/ops/device-a-000000000001.jsonl']);
    final stored = await store.load();
    expect(stored.sync.operationDeviceSequences, {'device-a': 1});
    expect(stored.papers.single.title, 'First');
  });

  test('uploads local operation diffs and saves sequence progress', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_upload_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(p.join(directory.path, 'sync-device-id'))
        .writeAsString(' Device Local ');
    final beforeState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {' Device Local ': 4},
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'Before',
        ),
      ],
    );
    final afterState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {' Device Local ': 4},
      papers: [
        PaperData(
          id: 'note',
          type: PaperTypes.note,
          title: 'Note',
          content: 'After',
        ),
      ],
    );
    var forwardedDeviceId = '';
    Map<String, int>? previousSequences;
    final uploadedOperations = <SyncOperation>[];
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        forwardedDeviceId = deviceId ?? '';
        return _FakeWebDavStateSyncService(
          onUploadOperationLogs: (
            operations, {
            previousDeviceSequences,
          }) async {
            previousSequences = previousDeviceSequences;
            uploadedOperations.addAll(operations);
            return WebDavOperationLogUploadResult(
              deviceSequences: {
                ...?previousDeviceSequences,
                forwardedDeviceId: operations.last.sequence,
              },
              uploadedCount: operations.length,
            );
          },
        );
      },
    );

    final result = await service.uploadLocalOperations(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: DateTime.utc(2026, 7, 1, 10),
    );

    expect(forwardedDeviceId, 'device-local');
    expect(previousSequences, {'device-local': 4});
    expect(uploadedOperations, hasLength(1));
    expect(uploadedOperations.single.id, 'device-local-5');
    expect(uploadedOperations.single.deviceId, 'device-local');
    expect(uploadedOperations.single.sequence, 5);
    expect(uploadedOperations.single.kind, SyncOperationKind.updateNoteContent);
    expect(uploadedOperations.single.payload, {
      'paperId': 'note',
      'content': 'After',
    });
    expect(result.generatedCount, 1);
    expect(result.uploadedCount, 1);
    expect(result.deviceSequences, {'device-local': 5});
    expect(result.state.sync.operationDeviceSequences, {'device-local': 5});
    expect((await store.load()).sync.operationDeviceSequences, {
      'device-local': 5,
    });
  });

  test('uploads local delete diffs and saves tombstones', () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_upload_delete_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    await File(p.join(directory.path, 'sync-device-id'))
        .writeAsString('device-local');
    final beforeState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 8},
      papers: [
        PaperData(
          id: 'old-note',
          type: PaperTypes.note,
          title: 'Remove',
        ),
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'item-1', text: 'Remove item'),
            PaperItem(id: 'item-2', text: 'Keep item'),
          ],
        ),
      ],
    );
    final afterState = AppState(
      sync: _configuredSyncSettings()
        ..operationDeviceSequences = {'device-local': 8},
      papers: [
        PaperData(
          id: 'todo',
          type: PaperTypes.todo,
          items: [
            PaperItem(id: 'item-2', text: 'Keep item'),
          ],
        ),
      ],
    );
    final uploadedOperations = <SyncOperation>[];
    final service = AppSyncService(
      deviceIdStore: SyncDeviceIdStore(
        filePath: p.join(directory.path, 'sync-device-id'),
      ),
      webDavFactory: (_, {deviceId}) {
        return _FakeWebDavStateSyncService(
          onUploadOperationLogs: (
            operations, {
            previousDeviceSequences,
          }) async {
            uploadedOperations.addAll(operations);
            return WebDavOperationLogUploadResult(
              deviceSequences: {
                ...?previousDeviceSequences,
                deviceId ?? '': operations.last.sequence,
              },
              uploadedCount: operations.length,
            );
          },
        );
      },
    );

    final result = await service.uploadLocalOperations(
      beforeState: beforeState,
      afterState: afterState,
      store: store,
      createdAtUtc: DateTime.utc(2026, 7, 1, 12),
    );

    expect(
      uploadedOperations.map((operation) => operation.kind),
      [
        SyncOperationKind.deletePaper,
        SyncOperationKind.deleteTodoItem,
        SyncOperationKind.upsertTodoItem,
      ],
    );
    expect(result.generatedCount, 3);
    expect(result.uploadedCount, 3);
    expect(result.state.sync.operationDeviceSequences, {'device-local': 11});
    expect(result.state.sync.deletedPaperTombstones['old-note'],
        DateTime.utc(2026, 7, 1, 12).toIso8601String());
    expect(result.state.sync.deletedTodoItemTombstones['todo']?['item-1'],
        DateTime.utc(2026, 7, 1, 12).toIso8601String());

    final stored = await store.load();
    expect(stored.sync.deletedPaperTombstones.containsKey('old-note'), true);
    expect(
      stored.sync.deletedTodoItemTombstones['todo']?.containsKey('item-1'),
      true,
    );
  });

  test('merge skips operation logs covered by explicit device sequences',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_skip_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000001.jsonl',
              deviceId: 'device-a',
              sequence: 1,
            ),
          ];
        },
        onDownloadOperationLog: (operationLogPath) async {
          throw StateError('Covered operation logs should not be downloaded.');
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(
        papers: [
          PaperData(id: 'local', type: PaperTypes.todo, title: 'Local'),
        ],
        sync: _configuredSyncSettings(),
      ),
      store: store,
      deviceSequences: {' Device A ': 1},
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.papers.single.title, 'Local');
    expect(await File(store.filePath).exists(), isFalse);
  });

  test('merge skips operation logs covered by stored device sequences',
      () async {
    final directory = await Directory.systemTemp
        .createTemp('repapertodo_app_sync_merge_stored_skip_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onListOperationLogs: () async {
          return const [
            WebDavOperationLogRecord(
              path: 'repapertodo/ops/device-a-000000000001.jsonl',
              deviceId: 'device-a',
              sequence: 1,
            ),
          ];
        },
        onDownloadOperationLog: (operationLogPath) async {
          throw StateError('Covered operation logs should not be downloaded.');
        },
      ),
    );

    final result = await service.mergeRemoteOperations(
      localState: AppState(
        papers: [
          PaperData(id: 'local', type: PaperTypes.todo, title: 'Local'),
        ],
        sync: SyncSettings(
          enabled: true,
          provider: SyncProviderIds.webDav,
          webDav: WebDavSyncSettings(
            endpoint: 'https://dav.example.test/',
            username: 'user',
            password: 'pass',
            rootPath: 'repapertodo',
          ),
          operationDeviceSequences: {' Device A ': 1},
        ),
      ),
      store: store,
    );

    expect(result.appliedCount, 0);
    expect(result.deviceSequences, {'device-a': 1});
    expect(result.state.papers.single.title, 'Local');
    expect(await File(store.filePath).exists(), isFalse);
  });

  test('restores a selected recovery snapshot', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_restore_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final snapshotState = AppState(
      papers: [
        PaperData(id: 'snapshot-paper', type: PaperTypes.note, title: 'Snap'),
      ],
      sync: _configuredSyncSettings(),
    );
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) => _FakeWebDavStateSyncService(
        onDownloadSnapshot: (snapshotPath) async {
          return WebDavStateSyncResult(
            status: WebDavStateSyncStatus.downloaded,
            state: snapshotState,
            snapshotPath: snapshotPath,
          );
        },
      ),
    );

    final result = await service.restoreRecoverySnapshot(
      localState: AppState(sync: _configuredSyncSettings()),
      store: store,
      snapshotPath: 'repapertodo/snapshots/snapshot.json',
    );

    expect(result.status, AppSyncStatus.downloaded);
    expect(result.message, 'Snapshot restored.');
    expect(result.snapshotPath, 'repapertodo/snapshots/snapshot.json');
    expect((await store.load()).papers.single.title, 'Snap');
  });

  test('returns no recovery snapshots when sync is disabled', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_no_list_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) =>
          throw StateError('WebDAV should not be created'),
    );

    final snapshots = await service.listRecoverySnapshots(
      localState: AppState(),
      store: store,
    );

    expect(snapshots, isEmpty);
  });

  test('returns no operation logs when sync is disabled', () async {
    final directory =
        await Directory.systemTemp.createTemp('repapertodo_app_sync_no_ops_');
    addTearDown(() => directory.delete(recursive: true));
    final store = StateStore(filePath: p.join(directory.path, 'data.json'));
    final service = AppSyncService(
      webDavFactory: (_, {deviceId}) =>
          throw StateError('WebDAV should not be created'),
    );

    final logs = await service.listRemoteOperationLogs(
      localState: AppState(),
      store: store,
    );
    final operations = await service.downloadRemoteOperationLog(
      localState: AppState(),
      store: store,
      operationLogPath: 'repapertodo/ops/device-000000000001.jsonl',
    );

    expect(logs, isEmpty);
    expect(operations, isEmpty);
  });
}

SyncSettings _configuredSyncSettings() {
  return SyncSettings(
    enabled: true,
    provider: SyncProviderIds.webDav,
    webDav: WebDavSyncSettings(
      endpoint: 'https://dav.example.test/',
      username: 'user',
      password: 'pass',
      rootPath: 'repapertodo',
    ),
  );
}

typedef _FakeSync = Future<WebDavStateSyncResult> Function({
  required AppState localState,
  DateTime? localUpdatedAtUtc,
});

typedef _FakeListSnapshots = Future<List<WebDavSnapshotRecord>> Function();

typedef _FakeListOperationLogs = Future<List<WebDavOperationLogRecord>>
    Function();

typedef _FakeDownloadSnapshot = Future<WebDavStateSyncResult> Function(
  String snapshotPath,
);

typedef _FakeDownloadOperationLog = Future<List<SyncOperation>> Function(
  String operationLogPath,
);

typedef _FakeUploadOperationLogs = Future<WebDavOperationLogUploadResult>
    Function(
  Iterable<SyncOperation> operations, {
  Map<String, int>? previousDeviceSequences,
});

typedef _FakeClose = void Function();

class _FakeWebDavStateSyncService extends WebDavStateSyncService {
  _FakeWebDavStateSyncService({
    _FakeSync? onSync,
    _FakeListSnapshots? onListSnapshots,
    _FakeDownloadSnapshot? onDownloadSnapshot,
    _FakeListOperationLogs? onListOperationLogs,
    _FakeDownloadOperationLog? onDownloadOperationLog,
    _FakeUploadOperationLogs? onUploadOperationLogs,
    _FakeClose? onClose,
  })  : _onSync = onSync,
        _onListSnapshots = onListSnapshots,
        _onDownloadSnapshot = onDownloadSnapshot,
        _onListOperationLogs = onListOperationLogs,
        _onDownloadOperationLog = onDownloadOperationLog,
        _onUploadOperationLogs = onUploadOperationLogs,
        _onClose = onClose,
        super(
          client: WebDavClient(
            baseUri: Uri.parse('https://unused.example.test/'),
            credentials:
                const WebDavCredentials(username: 'unused', password: 'unused'),
          ),
        );

  final _FakeSync? _onSync;
  final _FakeListSnapshots? _onListSnapshots;
  final _FakeDownloadSnapshot? _onDownloadSnapshot;
  final _FakeListOperationLogs? _onListOperationLogs;
  final _FakeDownloadOperationLog? _onDownloadOperationLog;
  final _FakeUploadOperationLogs? _onUploadOperationLogs;
  final _FakeClose? _onClose;

  @override
  void close() {
    _onClose?.call();
    super.close();
  }

  @override
  Future<WebDavStateSyncResult> sync({
    required AppState localState,
    DateTime? localUpdatedAtUtc,
  }) {
    final onSync = _onSync;
    if (onSync == null) {
      throw StateError('Unexpected sync call.');
    }
    return onSync(
      localState: localState,
      localUpdatedAtUtc: localUpdatedAtUtc,
    );
  }

  @override
  Future<List<WebDavSnapshotRecord>> listSnapshots() {
    final onListSnapshots = _onListSnapshots;
    if (onListSnapshots == null) {
      throw StateError('Unexpected listSnapshots call.');
    }
    return onListSnapshots();
  }

  @override
  Future<List<WebDavOperationLogRecord>> listOperationLogs() {
    final onListOperationLogs = _onListOperationLogs;
    if (onListOperationLogs == null) {
      throw StateError('Unexpected listOperationLogs call.');
    }
    return onListOperationLogs();
  }

  @override
  Future<WebDavStateSyncResult> downloadSnapshot(String snapshotPath) {
    final onDownloadSnapshot = _onDownloadSnapshot;
    if (onDownloadSnapshot == null) {
      throw StateError('Unexpected downloadSnapshot call.');
    }
    return onDownloadSnapshot(snapshotPath);
  }

  @override
  Future<List<SyncOperation>> downloadOperationLog(String operationLogPath) {
    final onDownloadOperationLog = _onDownloadOperationLog;
    if (onDownloadOperationLog == null) {
      throw StateError('Unexpected downloadOperationLog call.');
    }
    return onDownloadOperationLog(operationLogPath);
  }

  @override
  Future<WebDavOperationLogUploadResult> uploadOperationLogs(
    Iterable<SyncOperation> operations, {
    Map<String, int>? previousDeviceSequences,
  }) {
    final onUploadOperationLogs = _onUploadOperationLogs;
    if (onUploadOperationLogs == null) {
      throw StateError('Unexpected uploadOperationLogs call.');
    }
    return onUploadOperationLogs(
      operations,
      previousDeviceSequences: previousDeviceSequences,
    );
  }
}
