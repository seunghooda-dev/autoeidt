import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/services/api_client.dart';
import 'package:highlight_editor_app/services/local_engine_service.dart';
import 'package:highlight_editor_app/services/reusable_media_kit_video_player.dart';
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

  test('timeline thumbnails load for unique 30p clip in-points', () async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final temporaryDirectory = await io.Directory.systemTemp.createTemp(
      'autoedit-thumbnail-test-',
    );
    final source = io.File(
      '${temporaryDirectory.path}${io.Platform.pathSeparator}source.mxf',
    );
    final thumbnail = io.File(
      '${temporaryDirectory.path}${io.Platform.pathSeparator}thumb.png',
    );
    await source.writeAsBytes(const [0, 0, 0, 0]);
    await thumbnail.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    final api = _ThumbnailApiClient(thumbnail.path);
    final controller = EditorController(
      apiClient: api,
      engineService: _ReadyEngineService(),
      autoStartEngine: false,
      enableTimelineThumbnails: true,
    );

    try {
      await controller.openMediaFile(
        PlatformFile(
          name: 'source.mxf',
          size: await source.length(),
          path: source.path,
        ),
      );
      controller
        ..segments = const [
          HighlightSegment(order: 1, start: 1, end: 3, reason: 'first'),
          HighlightSegment(order: 2, start: 5, end: 15, reason: 'second'),
        ]
        ..selectedSegmentOrder = 1;
      controller.updateSegment(controller.segments.first);

      await _waitUntil(
        () => controller.timelineThumbnails.length == 4,
        describe: () =>
            'times=${api.thumbnailTimes} '
            'loaded=${controller.timelineThumbnails.keys}',
      );

      expect(api.thumbnailTimes.take(3), [1, 5, 10]);
      expect(api.thumbnailTimes.last, closeTo(449 / 30, 0.0001));
      expect(
        controller.timelineThumbnails.keys,
        containsAll([30, 150, 300, 449]),
      );
      expect(controller.isLoadingTimelineThumbnails, isFalse);
    } finally {
      controller.dispose();
      await platform.close();
      await temporaryDirectory.delete(recursive: true);
      VideoPlayerPlatform.instance = originalPlatform;
    }
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

  test('program time accounts for incoming clip transitions', () async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 4, reason: 'opener'),
        HighlightSegment(
          order: 2,
          start: 10,
          end: 14,
          reason: 'answer',
          transitionType: 'cross_dissolve',
          transitionDuration: 0.5,
        ),
      ]
      ..selectedSegmentOrder = 2;

    expect(controller.outputDurationSeconds, 7.5);
    expect(controller.programStartForSegment(2), 3.5);
    expect(controller.programSegmentOrderAt(3.5), 2);
    expect(controller.sourceTimeForProgramPosition(3.75), 10.25);
    expect(controller.programPositionForSourceTime(11, preferredOrder: 2), 4.5);

    await controller.setPreviewMonitorMode('program');
    expect(controller.monitorDurationSeconds, 7.5);
    await controller.jumpToTimelineStart();
    await controller.jumpToNextEditPoint();
    expect(controller.monitorPositionSeconds, closeTo(3.75, 0.001));
    controller.dispose();
  });

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
        () =>
            (controller.videoController?.value.isInitialized ?? false) &&
            !controller.isPreparingPreview &&
            controller.duration == 120,
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
        () =>
            controller.selectedSegmentOrder == 2 &&
            (controller.currentPositionSeconds - 5).abs() < 0.05,
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
      controller.dispose();
      await platform.close();
      VideoPlayerPlatform.instance = originalPlatform;
    }
  });

  test(
    'program monitor requests an effect-aware selected clip proxy',
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
          () =>
              (controller.videoController?.value.isInitialized ?? false) &&
              !controller.isPreparingPreview,
        );
        controller
          ..segments = const [
            HighlightSegment(
              order: 1,
              start: 10,
              end: 14,
              reason: 'animated clip',
              motionKeyframes: [
                MotionKeyframe(
                  time: 0,
                  opacity: 1,
                  scale: 1,
                  positionX: 0,
                  positionY: 0,
                  rotation: 0,
                ),
                MotionKeyframe(
                  time: 4,
                  opacity: 1,
                  scale: 2,
                  positionX: 0,
                  positionY: 0,
                  rotation: 0,
                ),
              ],
            ),
          ]
          ..selectedSegmentOrder = 1;

        await controller.setPreviewMonitorMode('program');
        await _waitUntil(() => api.requestedSegments.isNotEmpty);

        expect(api.requestedSegments.last?.motionKeyframes.length, 2);
        expect(api.requestedSegments.last?.motionKeyframes.last.scale, 2);
        expect(api.requestedAspectRatios.last, '16:9');
        expect(controller.currentPositionSeconds, closeTo(10, 0.05));
      } finally {
        controller.dispose();
        await platform.close();
        VideoPlayerPlatform.instance = originalPlatform;
      }
    },
  );

  test('long program clips request an eight second effect window', () async {
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
        () =>
            (controller.videoController?.value.isInitialized ?? false) &&
            !controller.isPreparingPreview,
      );
      controller
        ..segments = const [
          HighlightSegment(
            order: 1,
            start: 10,
            end: 40,
            reason: 'long animated clip',
            videoScale: 1.2,
          ),
        ]
        ..selectedSegmentOrder = 1;

      await controller.setPreviewMonitorMode('program');
      expect(api.requestedStarts.last, 10);
      expect(api.requestedDurations.last, 8);

      await controller.seekMonitorTo(15, autoplay: false);

      expect(api.requestedStarts.last, closeTo(23, 0.001));
      expect(api.requestedDurations.last, 8);
      expect(api.requestedSegments.last?.videoScale, 1.2);
      expect(controller.currentPositionSeconds, closeTo(25, 0.05));
    } finally {
      controller.dispose();
      await platform.close();
      VideoPlayerPlatform.instance = originalPlatform;
    }
  });

  test(
    'program preview maps only overlapping V2 and audio media into its window',
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
          () =>
              (controller.videoController?.value.isInitialized ?? false) &&
              !controller.isPreparingPreview,
        );
        controller
          ..segments = const [
            HighlightSegment(order: 1, start: 10, end: 40, reason: 'base clip'),
          ]
          ..videoOverlays = const [
            VideoOverlayClip(
              id: 'v2-overlap',
              sourcePath: r'C:\media\broll.mov',
              sourceName: 'broll.mov',
              timelineStart: 4,
              timelineEnd: 12,
              sourceStart: 2,
              sourceEnd: 10,
              audioTrack: 7,
              muted: false,
            ),
            VideoOverlayClip(
              id: 'v2-outside',
              sourcePath: r'C:\media\later.mov',
              sourceName: 'later.mov',
              timelineStart: 20,
              timelineEnd: 24,
              sourceStart: 0,
              sourceEnd: 4,
            ),
          ]
          ..audioClips = const [
            AudioClip(
              id: 'audio-overlap',
              sourcePath: r'C:\media\music.wav',
              sourceName: 'music.wav',
              timelineStart: 4,
              timelineEnd: 12,
              sourceStart: 2,
              sourceEnd: 10,
              track: 8,
            ),
            AudioClip(
              id: 'audio-outside',
              sourcePath: r'C:\media\later.wav',
              sourceName: 'later.wav',
              timelineStart: 20,
              timelineEnd: 24,
              sourceStart: 0,
              sourceEnd: 4,
            ),
          ]
          ..soloAudioTracks = <int>{8}
          ..selectedSegmentOrder = 1;

        await controller.setPreviewMonitorMode('program');

        final overlays = api.requestedVideoOverlays.last;
        expect(overlays, hasLength(1));
        expect(overlays.single.id, 'v2-overlap');
        expect(overlays.single.timelineStart, 4);
        expect(overlays.single.timelineEnd, 8);
        expect(overlays.single.sourceStart, 2);
        expect(overlays.single.sourceEnd, 6);
        expect(overlays.single.muted, isTrue);
        expect(api.requestedSegments.last?.audioMuted, isTrue);
        expect(api.requestedSegments.last?.audioChannel1Enabled, isFalse);
        expect(api.requestedSegments.last?.audioChannel2Enabled, isFalse);
        final audioClips = api.requestedAudioClips.last;
        expect(audioClips, hasLength(1));
        expect(audioClips.single.id, 'audio-overlap');
        expect(audioClips.single.timelineStart, 4);
        expect(audioClips.single.timelineEnd, 8);
        expect(audioClips.single.sourceStart, 2);
        expect(audioClips.single.sourceEnd, 6);
      } finally {
        controller.dispose();
        await platform.close();
        VideoPlayerPlatform.instance = originalPlatform;
      }
    },
  );

  test('program playback continues into the next effect window', () async {
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
        () =>
            (controller.videoController?.value.isInitialized ?? false) &&
            !controller.isPreparingPreview,
      );
      controller
        ..segments = const [
          HighlightSegment(
            order: 1,
            start: 10,
            end: 30,
            reason: 'continued animated clip',
            videoRotation: 5,
          ),
        ]
        ..selectedSegmentOrder = 1;
      await controller.setPreviewMonitorMode('program');
      await controller.togglePlayback();
      final firstController = controller.videoController!;

      platform.positions[firstController.playerId] =
          firstController.value.duration;
      firstController.value = firstController.value.copyWith(
        position: firstController.value.duration,
        isPlaying: false,
        isCompleted: true,
      );

      await _waitUntil(
        () =>
            !identical(controller.videoController, firstController) &&
            (controller.videoController?.value.isPlaying ?? false),
        describe: () =>
            'starts=${api.requestedStarts} '
            'durations=${api.requestedDurations}',
      );

      expect(
        api.requestedStarts.where((start) => (start - 16).abs() < 0.001),
        hasLength(1),
      );
      expect(api.requestedStarts.last, closeTo(22, 0.001));
      expect(api.requestedDurations.last, 8);
      expect(api.requestedSegments.last?.videoRotation, 5);
      expect(controller.currentPositionSeconds, closeTo(18, 0.05));
      expect(controller.videoController!.value.isPlaying, isTrue);
    } finally {
      controller.dispose();
      await platform.close();
      VideoPlayerPlatform.instance = originalPlatform;
    }
  });

  test('failed program prefetch retries during window transition', () async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final api = _FailingPrefetchApiClient();
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
        () =>
            (controller.videoController?.value.isInitialized ?? false) &&
            !controller.isPreparingPreview,
      );
      controller
        ..segments = const [
          HighlightSegment(
            order: 1,
            start: 10,
            end: 30,
            reason: 'prefetch retry clip',
            videoScale: 1.1,
          ),
        ]
        ..selectedSegmentOrder = 1;
      await controller.setPreviewMonitorMode('program');
      await controller.togglePlayback();
      final firstController = controller.videoController!;

      await _waitUntil(() => api.failedPrefetches == 1);
      platform.positions[firstController.playerId] =
          firstController.value.duration;
      firstController.value = firstController.value.copyWith(
        position: firstController.value.duration,
        isPlaying: false,
        isCompleted: true,
      );

      await _waitUntil(
        () =>
            !identical(controller.videoController, firstController) &&
            (controller.videoController?.value.isPlaying ?? false),
      );

      expect(
        api.requestedStarts.where((start) => (start - 16).abs() < 0.001),
        hasLength(2),
      );
      expect(controller.currentPositionSeconds, closeTo(18, 0.05));
    } finally {
      controller.dispose();
      await platform.close();
      VideoPlayerPlatform.instance = originalPlatform;
    }
  });

  test(
    'MXF preview starts quickly and continues in the next proxy window',
    () async {
      final originalPlatform = VideoPlayerPlatform.instance;
      final platform = _FakeVideoPlayerPlatform(rejectConcurrentPlayers: true);
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

        expect(api.requestedDurations, [8, 10]);
        expect(api.requestedStarts[1], closeTo(6, 0.001));
        expect(continuedController.value.position.inMilliseconds, 2000);
        expect(continuedController.value.isPlaying, isTrue);
        expect(controller.currentPositionSeconds, closeTo(8, 0.001));
      } finally {
        controller.dispose();
        await platform.close();
        VideoPlayerPlatform.instance = originalPlatform;
      }
    },
  );

  test('Windows proxy replaces media on the active player', () async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final platform = _ReusableFakeVideoPlayerPlatform();
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
        () =>
            (controller.videoController?.value.isInitialized ?? false) &&
            !controller.isPreparingPreview &&
            controller.duration == 120,
        describe: () =>
            'initial requests=${api.requestedDurations} '
            'created=${platform.createdUris} '
            'error=${controller.errorMessage}',
      );
      final activeController = controller.videoController!;

      await controller.togglePlayback();
      platform.positions[activeController.playerId] =
          activeController.value.duration;
      activeController.value = activeController.value.copyWith(
        position: activeController.value.duration,
        isPlaying: false,
        isCompleted: true,
      );

      await _waitUntil(
        () =>
            api.requestedDurations.length == 2 &&
            platform.replacedResources.length == 1,
        describe: () =>
            'requests=${api.requestedDurations} '
            'replacements=${platform.replacedResources} '
            'position=${activeController.value.position} '
            'duration=${activeController.value.duration} '
            'error=${controller.errorMessage}',
      );

      expect(controller.videoController, same(activeController));
      expect(platform.createdUris, hasLength(1));
      expect(
        platform.replacedResources.single,
        contains('proxy-2-d10.000.mp4'),
      );
      expect(activeController.value.duration, const Duration(seconds: 10));
      expect(activeController.value.isPlaying, isTrue);
    } finally {
      controller.dispose();
      await platform.close();
      VideoPlayerPlatform.instance = originalPlatform;
    }
  });

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
      controller.dispose();
      await platform.close();
      await temporaryDirectory.delete(recursive: true);
      VideoPlayerPlatform.instance = originalPlatform;
    }
  });

  test('stalled local proxy player is recreated before HTTP fallback', () async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final platform = _FakeVideoPlayerPlatform(stallFirstProxyFileSource: true);
    VideoPlayerPlatform.instance = platform;
    final temporaryDirectory = await io.Directory.systemTemp.createTemp(
      'autoedit-preview-recovery-test-',
    );
    final localPreview = io.File(
      '${temporaryDirectory.path}${io.Platform.pathSeparator}proxy.mp4',
    );
    await localPreview.writeAsBytes(const [0, 0, 0, 0]);
    final controller = EditorController(
      apiClient: _ProxyApiClient(localPreviewPath: localPreview.path),
      engineService: _ReadyEngineService(),
      autoStartEngine: false,
      proxyPreviewInitializationTimeout: const Duration(milliseconds: 30),
      proxyPreviewRecoveryTimeout: const Duration(milliseconds: 200),
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

      final proxyFileSources = platform.createdUris.where(
        (uri) => uri.startsWith('file:') && uri.contains('proxy.mp4'),
      );
      expect(proxyFileSources, hasLength(2));
      expect(
        platform.createdUris.where((uri) => uri.startsWith('http')),
        isEmpty,
      );
      expect(controller.errorMessage, isNull);
      expect(controller.isPreparingPreview, isFalse);
    } finally {
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
  final List<HighlightSegment?> requestedSegments = [];
  final List<List<VideoOverlayClip>> requestedVideoOverlays = [];
  final List<List<AudioClip>> requestedAudioClips = [];
  final List<String> requestedAspectRatios = [];

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
    HighlightSegment? segment,
    List<VideoOverlayClip> videoOverlays = const [],
    List<AudioClip> audioClips = const [],
    String aspectRatio = '16:9',
  }) async {
    final duration = durationSeconds ?? segment?.outputDuration ?? 8;
    final resolvedStart = startSeconds;
    requestedStarts.add(startSeconds);
    requestedDurations.add(duration);
    requestedSegments.add(segment);
    requestedVideoOverlays.add(List<VideoOverlayClip>.of(videoOverlays));
    requestedAudioClips.add(List<AudioClip>.of(audioClips));
    requestedAspectRatios.add(aspectRatio);
    return LocalPreviewInfo(
      url:
          'https://preview.invalid/proxy-${requestedDurations.length}'
          '-d${duration.toStringAsFixed(3)}.mp4',
      localPath: localPreviewPath,
      sourceStart: resolvedStart,
      duration: duration,
    );
  }
}

class _FailingPrefetchApiClient extends _ProxyApiClient {
  int failedPrefetches = 0;

  @override
  Future<LocalPreviewInfo> createLocalPreview(
    String path, {
    double startSeconds = 0,
    double? durationSeconds,
    HighlightSegment? segment,
    List<VideoOverlayClip> videoOverlays = const [],
    List<AudioClip> audioClips = const [],
    String aspectRatio = '16:9',
  }) async {
    if (segment != null &&
        (startSeconds - 16).abs() < 0.001 &&
        failedPrefetches == 0) {
      failedPrefetches += 1;
      requestedStarts.add(startSeconds);
      requestedDurations.add(durationSeconds ?? segment.outputDuration);
      requestedSegments.add(segment);
      requestedVideoOverlays.add(List<VideoOverlayClip>.of(videoOverlays));
      requestedAudioClips.add(List<AudioClip>.of(audioClips));
      requestedAspectRatios.add(aspectRatio);
      throw StateError('simulated prefetch failure');
    }
    return super.createLocalPreview(
      path,
      startSeconds: startSeconds,
      durationSeconds: durationSeconds,
      segment: segment,
      videoOverlays: videoOverlays,
      audioClips: audioClips,
      aspectRatio: aspectRatio,
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

class _ThumbnailApiClient extends _ProxyApiClient {
  _ThumbnailApiClient(this.thumbnailPath);

  final String thumbnailPath;
  final List<double> thumbnailTimes = [];

  @override
  Future<LocalThumbnailInfo> createLocalThumbnail(
    String path, {
    required double timeSeconds,
    int width = 320,
  }) async {
    thumbnailTimes.add(timeSeconds);
    return LocalThumbnailInfo(
      url: 'https://preview.invalid/thumb.png',
      localPath: thumbnailPath,
      sourceTime: timeSeconds,
      width: width,
    );
  }
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({
    this.failFileSources = false,
    this.stallFirstProxyFileSource = false,
    this.rejectConcurrentPlayers = false,
  });

  final bool failFileSources;
  final bool stallFirstProxyFileSource;
  final bool rejectConcurrentPlayers;
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> positions = {};
  final List<String> createdUris = [];
  int _nextPlayerId = 1;
  bool _stalledProxyFile = false;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final uri = options.dataSource.uri ?? '';
    createdUris.add(uri);
    if (failFileSources && uri.startsWith('file:')) {
      throw StateError('local file playback failed');
    }
    if (rejectConcurrentPlayers && _events.isNotEmpty) {
      throw StateError('concurrent player creation is not supported');
    }
    final shouldStall =
        stallFirstProxyFileSource &&
        !_stalledProxyFile &&
        uri.startsWith('file:') &&
        uri.contains('proxy.mp4');
    if (shouldStall) {
      _stalledProxyFile = true;
    }
    final id = _nextPlayerId++;
    final durationMatch = RegExp(r'-d([0-9.]+)\.mp4').firstMatch(uri);
    final durationSeconds = double.tryParse(durationMatch?.group(1) ?? '');
    final duration = durationSeconds == null
        ? const Duration(seconds: 30)
        : Duration(milliseconds: (durationSeconds * 1000).round());
    late final StreamController<VideoEvent> events;
    events = StreamController<VideoEvent>.broadcast(
      onListen: () {
        if (shouldStall) {
          return;
        }
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

class _ReusableFakeVideoPlayerPlatform extends _FakeVideoPlayerPlatform
    implements ReusableVideoPlayerPlatform {
  final List<String> replacedResources = [];

  @override
  Future<ReusableMediaInfo> replaceActiveSource(
    String resource, {
    Map<String, String> httpHeaders = const {},
    Duration timeout = const Duration(seconds: 12),
  }) async {
    replacedResources.add(resource);
    positions.updateAll((key, value) => Duration.zero);
    return const ReusableMediaInfo(
      duration: Duration(seconds: 10),
      size: Size(960, 540),
    );
  }
}
