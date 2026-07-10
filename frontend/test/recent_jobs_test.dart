import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/services/api_client.dart';
import 'package:highlight_editor_app/services/local_engine_service.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/state/workspace_controller.dart';
import 'package:highlight_editor_app/widgets/workspace_tools_panel.dart';
import 'package:provider/provider.dart';

void main() {
  test('recent job model exposes interrupted and resume evidence', () {
    final summary = RecentJobSummary.fromJson({
      'job_id': 'interrupted-job',
      'status': 'cancelled',
      'stage': 'interrupted',
      'progress': 45,
      'message': 'engine stopped',
      'original_filename': 'news.mxf',
      'video_path': r'C:\offline\news.mxf',
      'duration': 3600,
      'source_exists': false,
      'has_timeline': true,
      'segment_count': 6,
      'render_exists': false,
      'can_resume': true,
      'updated_at': '2026-07-10T12:00:00+00:00',
    });

    expect(summary.displayName, 'news.mxf');
    expect(summary.statusLabel, 'Interrupted');
    expect(summary.canResume, isTrue);
    expect(summary.sourceExists, isFalse);
    expect(summary.updatedAt, isNotNull);
  });

  test(
    'editor resumes rendered job while keeping offline source state',
    () async {
      final api = _RecentJobsApiClient();
      final editor = EditorController(
        apiClient: api,
        engineService: _ReadyEngineService(),
        autoStartEngine: false,
      );

      final opened = await editor.resumeRecentJob(api.summary);

      expect(opened, isTrue);
      expect(editor.jobId, 'rendered-job');
      expect(editor.projectName, 'Evening News');
      expect(editor.segments, hasLength(1));
      expect(editor.job?.status, 'rendered');
      expect(
        editor.renderUrl,
        'http://127.0.0.1:1/api/jobs/rendered-job/download',
      );
      expect(editor.sourceMediaNeedsRelink, isTrue);
      expect(editor.hasUnsavedProjectChanges, isFalse);
      editor.dispose();
    },
  );

  testWidgets('history tab confirms before replacing an unsaved edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _RecentJobsApiClient();
    final editor = EditorController(
      apiClient: api,
      engineService: _ReadyEngineService(),
      autoStartEngine: false,
    );
    await editor.openMediaFile(PlatformFile(name: 'current.mp4', size: 1));
    final workspace = WorkspaceController(persist: false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorController>.value(value: editor),
          ChangeNotifierProvider<WorkspaceController>.value(value: workspace),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                key: const Key('open-workspace-tools'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const Dialog(
                    child: SizedBox(
                      width: 460,
                      height: 620,
                      child: WorkspaceToolsPanel(),
                    ),
                  ),
                ),
                child: const Text('Tools'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-workspace-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(api.listRequests, 1);
    expect(find.text('Evening News'), findsOneWidget);
    expect(find.textContaining('Rendered'), findsOneWidget);
    expect(find.textContaining('Source offline'), findsOneWidget);

    await tester.tap(find.byTooltip('Open recent job'));
    await tester.pumpAndSettle();
    expect(find.text('Open recent job?'), findsOneWidget);
    expect(api.projectRequests, 0);

    await tester.tap(find.byKey(const Key('recent-job-confirm-open')));
    await tester.pumpAndSettle();

    expect(api.projectRequests, 1);
    expect(editor.jobId, 'rendered-job');
    expect(find.byKey(const Key('open-workspace-tools')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    workspace.dispose();
  });
}

class _RecentJobsApiClient extends ApiClient {
  _RecentJobsApiClient() : super(baseUrl: 'http://127.0.0.1:1');

  int listRequests = 0;
  int projectRequests = 0;

  final summary = RecentJobSummary(
    jobId: 'rendered-job',
    status: 'rendered',
    stage: 'rendered',
    progress: 100,
    message: 'done',
    projectName: 'Evening News',
    originalFilename: 'evening_news.mxf',
    videoPath: r'C:\offline\evening_news.mxf',
    duration: 120,
    importMode: 'local_path',
    sourceExists: false,
    hasTimeline: true,
    segmentCount: 1,
    renderExists: true,
    renderPath: r'C:\outputs\evening_news.mp4',
    renderUrl: '/api/jobs/rendered-job/download',
    canResume: true,
    updatedAt: DateTime.utc(2026, 7, 10, 12),
  );

  @override
  Future<List<RecentJobSummary>> listRecentJobs({int limit = 30}) async {
    listRequests += 1;
    return [summary];
  }

  @override
  Future<JobStatusResponse> getJob(String jobId) async {
    return JobStatusResponse(
      jobId: jobId,
      status: 'rendered',
      stage: 'rendered',
      progress: 100,
      message: 'done',
      duration: 120,
      originalFilename: 'evening_news.mxf',
      renderPath: r'C:\outputs\evening_news.mp4',
      renderUrl: '/api/jobs/rendered-job/download',
    );
  }

  @override
  Future<ProjectState> getProject(String jobId) async {
    projectRequests += 1;
    return ProjectState(
      name: 'Evening News',
      jobId: jobId,
      originalFilename: 'evening_news.mxf',
      originalPath: r'C:\offline\evening_news.mxf',
      duration: 120,
      segments: const [
        HighlightSegment(order: 1, start: 5, end: 35, reason: 'lead'),
      ],
      captions: const [],
      waveform: const [],
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
