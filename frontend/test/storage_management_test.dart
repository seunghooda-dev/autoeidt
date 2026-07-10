import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/services/api_client.dart';
import 'package:highlight_editor_app/services/local_engine_service.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/state/workspace_controller.dart';
import 'package:highlight_editor_app/widgets/workspace_tools_panel.dart';
import 'package:provider/provider.dart';

void main() {
  test('storage models parse protected and reclaimable categories', () {
    final usage = StorageUsageInfo.fromJson(_usageJson(reclaimable: 300));

    expect(usage.totalBytes, 2048);
    expect(usage.reclaimableBytes, 300);
    expect(usage.categories, hasLength(3));
    expect(
      usage.categories
          .firstWhere((item) => item.key == 'source_copies')
          .protected,
      isTrue,
    );
  });

  test('editor refreshes and cleans storage for the active job', () async {
    final api = _StorageApiClient();
    final controller = EditorController(
      apiClient: api,
      engineService: _ReadyEngineService(),
      autoStartEngine: false,
    )..jobId = 'current-job';

    await controller.refreshStorageUsage();

    expect(api.usageRequests, 1);
    expect(api.lastActiveJobId, 'current-job');
    expect(controller.storageUsage?.reclaimableBytes, 300);

    final result = await controller.cleanupSafeStorage();

    expect(result?.freedBytes, 300);
    expect(api.cleanupRequests, 1);
    expect(api.lastActiveJobId, 'current-job');
    expect(controller.storageUsage?.reclaimableBytes, 0);
    expect(controller.storageErrorMessage, isNull);
    controller.dispose();
  });

  testWidgets('storage tab requires confirmation before safe cleanup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _StorageApiClient();
    final editor = EditorController(
      apiClient: api,
      engineService: _ReadyEngineService(),
      autoStartEngine: false,
    )..jobId = 'visible-job';
    final workspace = WorkspaceController(persist: false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorController>.value(value: editor),
          ChangeNotifierProvider<WorkspaceController>.value(value: workspace),
        ],
        child: const MaterialApp(home: Scaffold(body: WorkspaceToolsPanel())),
      ),
    );

    await tester.tap(find.text('Storage'));
    await tester.pumpAndSettle();

    expect(api.usageRequests, 1);
    expect(find.byKey(const Key('storage-total-value')), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('300 B reclaimable'), findsOneWidget);
    expect(
      find.text('Sources, projects and exports protected'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('storage-clean-button')));
    await tester.pumpAndSettle();
    expect(find.text('Clean local cache?'), findsOneWidget);
    expect(api.cleanupRequests, 0);

    await tester.tap(find.byKey(const Key('storage-confirm-clean-button')));
    await tester.pumpAndSettle();

    expect(api.cleanupRequests, 1);
    expect(api.lastActiveJobId, 'visible-job');
    expect(find.text('0 B reclaimable'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    workspace.dispose();
  });
}

Map<String, dynamic> _usageJson({required int reclaimable}) {
  return {
    'data_dir': r'C:\AutoEdit\data',
    'total_bytes': 2048,
    'reclaimable_bytes': reclaimable,
    'retention_hours': 24,
    'categories': [
      {
        'key': 'preview_cache',
        'label': 'Preview cache',
        'bytes': 500,
        'files': 2,
        'reclaimable_bytes': reclaimable,
        'protected': false,
      },
      {
        'key': 'source_copies',
        'label': 'Imported sources',
        'bytes': 1000,
        'files': 1,
        'reclaimable_bytes': 0,
        'protected': true,
      },
      {
        'key': 'render_outputs',
        'label': 'Render outputs',
        'bytes': 548,
        'files': 1,
        'reclaimable_bytes': 0,
        'protected': true,
      },
    ],
    'protected_items': [
      'Imported source copies',
      'Render outputs',
      'Project metadata',
      'Current and running jobs',
    ],
  };
}

class _StorageApiClient extends ApiClient {
  _StorageApiClient() : super(baseUrl: 'http://127.0.0.1:1');

  int usageRequests = 0;
  int cleanupRequests = 0;
  String? lastActiveJobId;

  @override
  Future<StorageUsageInfo> getStorageUsage({
    String? activeJobId,
    int retentionHours = 24,
  }) async {
    usageRequests += 1;
    lastActiveJobId = activeJobId;
    return StorageUsageInfo.fromJson(_usageJson(reclaimable: 300));
  }

  @override
  Future<StorageCleanupInfo> cleanupSafeStorage({
    String? activeJobId,
    int retentionHours = 24,
  }) async {
    cleanupRequests += 1;
    lastActiveJobId = activeJobId;
    final before = StorageUsageInfo.fromJson(_usageJson(reclaimable: 300));
    final after = StorageUsageInfo.fromJson(_usageJson(reclaimable: 0));
    return StorageCleanupInfo(
      freedBytes: 300,
      deletedFiles: 2,
      skippedFiles: 0,
      before: before,
      after: after,
    );
  }
}

class _ReadyEngineService extends LocalEngineService {
  @override
  Future<LocalEngineState> ensureRunning({int port = 8000}) async {
    return const LocalEngineState(
      status: 'running',
      message: 'ready',
      isRunning: true,
      canStart: true,
    );
  }

  @override
  Future<void> dispose() async {}
}
