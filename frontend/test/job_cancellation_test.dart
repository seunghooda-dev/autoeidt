import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/main.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/services/api_client.dart';
import 'package:highlight_editor_app/services/local_engine_service.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/state/workspace_controller.dart';
import 'package:highlight_editor_app/widgets/status_panel.dart';
import 'package:provider/provider.dart';

void main() {
  test(
    'editor cancellation stops active state and preserves prior render',
    () async {
      final api = _CancellationApiClient();
      final controller = _activeController(api);

      expect(controller.hasActiveJob, isTrue);
      expect(controller.canCancelJob, isTrue);

      final cancelled = await controller.cancelActiveJob();

      expect(cancelled, isTrue);
      expect(api.cancelRequests, 1);
      expect(api.cancelledJobId, 'active-job');
      expect(controller.job?.status, 'cancelled');
      expect(controller.job?.renderPath, r'C:\outputs\previous.mp4');
      expect(controller.hasActiveJob, isFalse);
      expect(controller.canCancelJob, isFalse);
      expect(controller.isRendering, isFalse);
      expect(controller.errorMessage, isNull);
      controller.dispose();
    },
  );

  testWidgets('status panel confirms before cancelling a running job', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(460, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _CancellationApiClient();
    final controller = _activeController(api);

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(
            body: Padding(padding: EdgeInsets.all(12), child: StatusPanel()),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('job-cancel-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('job-cancel-button')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel current job?'), findsOneWidget);
    expect(api.cancelRequests, 0);

    await tester.tap(find.text('Keep running'));
    await tester.pumpAndSettle();
    expect(api.cancelRequests, 0);
    expect(controller.hasActiveJob, isTrue);

    await tester.tap(find.byKey(const Key('job-cancel-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('job-confirm-cancel-button')));
    await tester.pumpAndSettle();

    expect(api.cancelRequests, 1);
    expect(find.text('작업이 취소되었습니다'), findsOneWidget);
    expect(find.byKey(const Key('job-cancel-button')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('desktop media activity exposes the cancel control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _CancellationApiClient();
    final controller = _activeController(api);
    final workspace = WorkspaceController(persist: false);

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: controller,
        child: MaterialApp(
          home: EditorDashboard(workspaceController: workspace),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('job-cancel-button')), findsOneWidget);
    expect(find.byTooltip('Cancel current job'), findsOneWidget);
    await tester.tap(find.byKey(const Key('job-cancel-button')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel current job?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('job-confirm-cancel-button')));
    await tester.pumpAndSettle();
    expect(api.cancelRequests, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    workspace.dispose();
  });
}

EditorController _activeController(_CancellationApiClient api) {
  return EditorController(
      apiClient: api,
      engineService: _ReadyEngineService(),
      autoStartEngine: false,
    )
    ..jobId = 'active-job'
    ..job = JobStatusResponse(
      jobId: 'active-job',
      status: 'processing',
      stage: 'transcribing',
      progress: 45,
      message: '스크립트 추출 중',
      renderPath: r'C:\outputs\previous.mp4',
      renderUrl: '/api/jobs/active-job/download',
    );
}

class _CancellationApiClient extends ApiClient {
  _CancellationApiClient() : super(baseUrl: 'http://127.0.0.1:1');

  int cancelRequests = 0;
  String? cancelledJobId;

  @override
  Future<JobStatusResponse> cancelJob(String jobId) async {
    cancelRequests += 1;
    cancelledJobId = jobId;
    return JobStatusResponse(
      jobId: jobId,
      status: 'cancelled',
      stage: 'cancelled',
      progress: 45,
      message: '작업이 취소되었습니다',
      renderPath: r'C:\outputs\previous.mp4',
      renderUrl: '/api/jobs/active-job/download',
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
