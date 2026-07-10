import 'dart:async';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/services/api_client.dart';
import 'package:highlight_editor_app/services/local_engine_service.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/widgets/video_preview.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('broadcast pixel formats require a compatibility preview proxy', () {
    final probe = MediaProbeInfo.fromJson({
      'path': r'C:\media\studio-master.mp4',
      'filename': 'studio-master.mp4',
      'video_codec': 'h264',
      'pixel_format': 'yuv444p',
      'can_analyze': true,
    });

    expect(probe.pixelFormat, 'yuv444p');
    expect(probe.requiresCompatibilityProxy, isTrue);
  });

  test(
    'program time maps ordered clips and playback speed to source time',
    () async {
      final controller = EditorController(autoStartEngine: false)
        ..duration = 60
        ..segments = const [
          HighlightSegment(
            order: 1,
            start: 10,
            end: 14,
            playbackSpeed: 2,
            reason: 'fast opener',
          ),
          HighlightSegment(order: 2, start: 30, end: 33, reason: 'answer'),
        ]
        ..selectedSegmentOrder = 1;

      expect(controller.outputDurationSeconds, 5);
      expect(controller.programSegmentOrderAt(0), 1);
      expect(controller.sourceTimeForProgramPosition(1), 12);
      expect(controller.programSegmentOrderAt(2), 2);
      expect(controller.sourceTimeForProgramPosition(3.5), 31.5);
      expect(controller.programStartForSegment(2), 2);
      expect(controller.programPositionForSourceTime(12), 1);
      expect(controller.programPositionForSourceTime(31.5), 3.5);

      await controller.setPreviewMonitorMode('program');
      expect(controller.isProgramMonitor, isTrue);
      expect(controller.monitorDurationSeconds, 5);
      expect(controller.monitorPositionSeconds, 0);
      await controller.jumpToNextEditPoint();
      expect(controller.monitorPositionSeconds, 2);
      expect(controller.currentPositionSeconds, 30);
      await controller.stepPlayheadByFrames(1);
      expect(controller.monitorPositionSeconds, closeTo(2 + 1 / 30, 0.001));
      expect(controller.currentPositionSeconds, closeTo(30 + 1 / 30, 0.001));
      controller.dispose();
    },
  );

  test('program playback advances across a discontinuous source cut', () async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final controller = EditorController(
      apiClient: _ProxyApiClient(),
      engineService: _ReadyEngineService(),
      autoStartEngine: false,
    );

    try {
      await controller.openMediaFile(
        PlatformFile(
          name: 'broadcast.mxf',
          size: 1024,
          path: r'C:\media\broadcast.mxf',
        ),
      );
      await _waitUntil(
        () => controller.videoController?.value.isInitialized ?? false,
      );
      controller
        ..segments = const [
          HighlightSegment(order: 1, start: 1, end: 2, reason: 'first'),
          HighlightSegment(order: 2, start: 5, end: 6, reason: 'second'),
        ]
        ..selectedSegmentOrder = 1;
      await controller.setPreviewMonitorMode('program');
      await controller.togglePlayback();

      final firstController = controller.videoController!;
      platform.positions[firstController.playerId] = const Duration(seconds: 2);
      firstController.value = firstController.value.copyWith(
        position: const Duration(seconds: 2),
        isPlaying: true,
      );

      await _waitUntil(
        () => controller.selectedSegmentOrder == 2,
        describe: () =>
            'selected=${controller.selectedSegmentOrder} '
            'program=${controller.monitorPositionSeconds} '
            'source=${controller.currentPositionSeconds}',
      );
      expect(
        controller.programSegmentOrderAt(controller.monitorPositionSeconds),
        2,
      );
      expect(controller.monitorPositionSeconds, closeTo(1, 0.05));
      expect(controller.currentPositionSeconds, closeTo(5, 0.05));
      expect(controller.videoController!.value.isPlaying, isTrue);
    } finally {
      await controller.videoController?.dispose();
      controller.dispose();
      await platform.close();
      VideoPlayerPlatform.instance = originalPlatform;
    }
  });

  test(
    'MXF preview starts quickly and continues in the next proxy window',
    () async {
      final originalPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      final api = _ProxyApiClient();
      final controller = EditorController(
        apiClient: api,
        engineService: _ReadyEngineService(),
        autoStartEngine: false,
      );

      try {
        await controller.openMediaFile(
          PlatformFile(
            name: 'broadcast.mxf',
            size: 1024,
            path: r'C:\media\broadcast.mxf',
          ),
        );
        await _waitUntil(
          () => controller.videoController?.value.isInitialized ?? false,
          describe: () =>
              'initial requests=${api.requestedDurations} '
              'controller=${controller.videoController?.value} '
              'error=${controller.errorMessage}',
        );

        expect(api.requestedDurations, [8]);
        expect(api.requestedStarts, [0]);
        await _waitUntil(
          () => controller.duration == 120,
          describe: () =>
              'probe duration=${controller.duration} '
              'probe=${controller.selectedMediaProbe?.duration}',
        );
        expect(controller.duration, 120);

        await controller.togglePlayback();
        final firstController = controller.videoController!;
        expect(firstController.value.isPlaying, isTrue);

        platform.positions[firstController.playerId] =
            firstController.value.duration;
        firstController.value = firstController.value.copyWith(
          position: firstController.value.duration,
          isPlaying: false,
          isCompleted: true,
        );

        await _waitUntil(
          () =>
              api.requestedDurations.length == 2 &&
              !identical(controller.videoController, firstController),
          describe: () =>
              'continuation requests=${api.requestedDurations} '
              'controller=${controller.videoController?.value} '
              'error=${controller.errorMessage}',
        );
        final continuedController = controller.videoController!;

        expect(api.requestedDurations, [8, 30]);
        expect(api.requestedStarts[1], closeTo(0, 0.001));
        expect(continuedController.value.position.inMilliseconds, 8000);
        expect(continuedController.value.isPlaying, isTrue);
        expect(controller.currentPositionSeconds, closeTo(8, 0.001));
      } finally {
        await controller.videoController?.dispose();
        controller.dispose();
        await platform.close();
        VideoPlayerPlatform.instance = originalPlatform;
      }
    },
  );

  test('proxy preview falls back to HTTP when local playback fails', () async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeVideoPlayerPlatform(failFileSources: true);
    VideoPlayerPlatform.instance = platform;
    final temporaryDirectory = await io.Directory.systemTemp.createTemp(
      'autoedit-preview-test-',
    );
    final localPreview = io.File(
      '${temporaryDirectory.path}${io.Platform.pathSeparator}proxy.mp4',
    );
    await localPreview.writeAsBytes(const [0, 0, 0, 0]);
    final controller = EditorController(
      apiClient: _ProxyApiClient(localPreviewPath: localPreview.path),
      engineService: _ReadyEngineService(),
      autoStartEngine: false,
    );

    try {
      await controller.openMediaFile(
        PlatformFile(
          name: 'broadcast.mxf',
          size: 1024,
          path: r'C:\media\broadcast.mxf',
        ),
      );
      await _waitUntil(
        () => controller.videoController?.value.isInitialized ?? false,
        describe: () =>
            'sources=${platform.createdUris} error=${controller.errorMessage}',
      );

      expect(platform.createdUris, hasLength(2));
      expect(platform.createdUris.first, startsWith('file:'));
      expect(platform.createdUris.last, startsWith('https://'));
      expect(controller.isPreparingPreview, isFalse);
      expect(controller.errorMessage, isNull);
    } finally {
      await controller.videoController?.dispose();
      controller.dispose();
      await platform.close();
      await temporaryDirectory.delete(recursive: true);
      VideoPlayerPlatform.instance = originalPlatform;
    }
  });

  testWidgets('preview controls use the external sequence time', (
    tester,
  ) async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final player = VideoPlayerController.networkUrl(
      Uri.parse('https://preview.invalid/proxy.mp4'),
    );
    player.value = const VideoPlayerValue(
      duration: Duration(seconds: 30),
      position: Duration(seconds: 8),
      size: Size(960, 540),
      isInitialized: true,
    );

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoPreview(
              controller: player,
              volume: 1,
              muted: false,
              positionSeconds: 3,
              durationSeconds: 120,
            ),
          ),
        ),
      );

      final timeDisplay = tester.widget<Text>(
        find.byKey(const Key('preview-time-display')),
      );
      expect(timeDisplay.data, contains('00:00:03:00 / 00:02:00:00'));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await player.dispose();
      await platform.close();
      VideoPlayerPlatform.instance = originalPlatform;
    }
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  String Function()? describe,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'preview pipeline did not reach the expected state: '
        '${describe?.call() ?? 'no diagnostics'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _ProxyApiClient extends ApiClient {
  _ProxyApiClient({this.localPreviewPath})
    : super(baseUrl: 'http://127.0.0.1:1');

  final String? localPreviewPath;

  final List<double> requestedStarts = [];
  final List<double> requestedDurations = [];

  @override
  Future<MediaProbeInfo> probeLocalMedia(String path) async {
    return MediaProbeInfo.fromJson({
      'path': path,
      'filename': 'broadcast.mxf',
      'duration': 120,
      'can_analyze': true,
      'is_mxf': true,
      'audio_stream_count': 8,
      'audio_channel_count': 8,
    });
  }

  @override
  Future<LocalPreviewInfo> createLocalPreview(
    String path, {
    double startSeconds = 0,
    double? durationSeconds,
  }) async {
    final duration = durationSeconds ?? 8;
    requestedStarts.add(startSeconds);
    requestedDurations.add(duration);
    return LocalPreviewInfo(
      url: 'https://preview.invalid/proxy-${requestedDurations.length}.mp4',
      localPath: localPreviewPath,
      sourceStart: startSeconds,
      duration: duration,
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

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({this.failFileSources = false});

  final bool failFileSources;
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> positions = {};
  final List<String> createdUris = [];
  int _nextPlayerId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final uri = options.dataSource.uri ?? '';
    createdUris.add(uri);
    if (failFileSources && uri.startsWith('file:')) {
      throw StateError('local file playback failed');
    }
    final id = _nextPlayerId++;
    final duration = uri.contains('proxy-1')
        ? const Duration(seconds: 8)
        : const Duration(seconds: 30);
    late final StreamController<VideoEvent> events;
    events = StreamController<VideoEvent>.broadcast(
      onListen: () {
        scheduleMicrotask(
          () => events.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: duration,
              size: const Size(960, 540),
            ),
          ),
        );
      },
    );
    _events[id] = events;
    positions[id] = Duration.zero;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
    positions.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return positions[playerId] ?? Duration.zero;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  Future<void> close() async {
    for (final events in _events.values.toList()) {
      await events.close();
    }
    _events.clear();
    positions.clear();
  }
}
