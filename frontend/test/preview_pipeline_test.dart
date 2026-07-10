import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/services/api_client.dart';
import 'package:highlight_editor_app/services/local_engine_service.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
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
  _ProxyApiClient() : super(baseUrl: 'http://127.0.0.1:1');

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
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> positions = {};
  int _nextPlayerId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextPlayerId++;
    final uri = options.dataSource.uri ?? '';
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
