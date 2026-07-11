import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/main.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/utils/timecode.dart';
import 'package:highlight_editor_app/widgets/clip_inspector.dart';
import 'package:highlight_editor_app/widgets/render_outputs_panel.dart';
import 'package:highlight_editor_app/widgets/timeline_editor.dart';
import 'package:highlight_editor_app/widgets/video_preview.dart';
import 'package:provider/provider.dart';

import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/state/workspace_controller.dart';

void main() {
  testWidgets('clip inspector edits an incoming A/V transition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'opener'),
        HighlightSegment(order: 2, start: 20, end: 30, reason: 'answer'),
      ]
      ..selectedSegmentOrder = 2;

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 380, child: ClipInspector())),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('clip-transition-control')), findsOneWidget);
    await tester.tap(find.byKey(const Key('clip-transition-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dip to Black').last);
    await tester.pumpAndSettle();

    expect(controller.selectedSegment!.transitionType, 'dip_black');
    expect(controller.selectedSegment!.transitionDuration, 0.3);
    expect(find.byKey(const Key('clip-transition-duration')), findsOneWidget);
    expect(controller.outputDurationSeconds, closeTo(19.7, 0.001));
    controller.dispose();
  });

  testWidgets('clip inspector exposes professional motion controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = EditorController(autoStartEngine: false)
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 0,
          end: 10,
          reason: 'motion',
          videoOpacity: 0.8,
          videoScale: 1.25,
          videoPositionX: 0.1,
          videoPositionY: -0.2,
          videoRotation: 5,
        ),
      ]
      ..selectedSegmentOrder = 1;

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 380, child: ClipInspector())),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Motion / Opacity'), findsOneWidget);
    expect(find.byKey(const Key('clip-motion-keyframes')), findsOneWidget);
    expect(
      find.byKey(const Key('clip-motion-keyframe-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('clip-video-opacity')), findsOneWidget);
    expect(find.byKey(const Key('clip-video-scale')), findsOneWidget);
    expect(find.byKey(const Key('clip-video-position-x')), findsOneWidget);
    expect(find.byKey(const Key('clip-video-position-y')), findsOneWidget);
    expect(find.byKey(const Key('clip-video-rotation')), findsOneWidget);

    await tester.tap(find.byKey(const Key('clip-motion-keyframe-toggle')));
    await tester.pump();
    expect(controller.selectedSegment!.motionKeyframes.length, 1);
    expect(controller.selectedMotionHasKeyframeAtPlayhead, isTrue);

    await tester.tap(find.byKey(const Key('clip-motion-reset')));
    await tester.pump();
    expect(controller.selectedSegment!.videoOpacity, 1);
    expect(controller.selectedSegment!.videoScale, 1);
    expect(controller.selectedSegment!.videoPositionX, 0);
    expect(controller.selectedSegment!.videoPositionY, 0);
    expect(controller.selectedSegment!.videoRotation, 0);
    expect(controller.selectedSegment!.motionKeyframes, isEmpty);
    controller.dispose();
  });

  testWidgets('preview loading state can queue playback', (tester) async {
    var toggleCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoPreview(
            controller: null,
            volume: 1,
            muted: false,
            loading: true,
            onTogglePlayback: () => toggleCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('빠른 프리뷰 준비 중'), findsOneWidget);
    await tester.tap(find.byKey(const Key('preview-play-when-ready')));
    expect(toggleCount, 1);
  });

  testWidgets('renders editor dashboard', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => EditorController(autoStartEngine: false),
        child: const HighlightEditorApp(),
      ),
    );

    expect(find.text('AutoEdit'), findsOneWidget);
    expect(find.text('Import'), findsWidgets);
  });

  testWidgets('source and program monitors expose distinct sequence time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 12, reason: 'first'),
        HighlightSegment(order: 2, start: 30, end: 33, reason: 'second'),
      ]
      ..selectedSegmentOrder = 1;

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('preview-monitor-selector')), findsOneWidget);
    expect(controller.previewMonitorMode, 'source');
    await tester.tap(find.text('Program').first);
    await tester.pumpAndSettle();

    expect(controller.previewMonitorMode, 'program');
    expect(controller.monitorDurationSeconds, 5);
    expect(find.byKey(const Key('timeline-view-selector')), findsOneWidget);
    expect(find.textContaining('Sequence 00:00:05:00'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('timeline-view-selector')),
        matching: find.text('Source'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.previewMonitorMode, 'source');
    expect(find.textContaining('Source 00:01:00:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('Ctrl+S invokes project save and shows dirty project title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _ShortcutSaveEditorController()
      ..projectName = 'Shortcut Project'
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 20, reason: 'first'),
      ]
      ..selectedSegmentOrder = 1;
    controller.updateSegment(
      controller.segments.single.copyWith(end: 24, reason: 'saved by shortcut'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    expect(controller.hasUnsavedProjectChanges, isTrue);
    expect(find.text('Shortcut Project *'), findsOneWidget);
    await _pressShortcut(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump();

    expect(controller.saveInvocations, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('project media bin filters and organizes local assets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late io.Directory directory;
    late String newsPath;
    late String interviewPath;
    late String offlinePath;
    await tester.runAsync(() async {
      directory = await io.Directory.systemTemp.createTemp(
        'autoedit_media_bin_test',
      );
      newsPath =
          '${directory.path}${io.Platform.pathSeparator}evening_news.mxf';
      interviewPath =
          '${directory.path}${io.Platform.pathSeparator}interview.mp4';
      offlinePath =
          '${directory.path}${io.Platform.pathSeparator}missing_broll.mov';
      await io.File(newsPath).writeAsBytes([0]);
      await io.File(interviewPath).writeAsBytes([0]);
    });
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final workspace = WorkspaceController(persist: false)
      ..addAsset(name: 'evening_news.mxf', path: newsPath)
      ..addAsset(name: 'interview.mp4', path: interviewPath)
      ..addAsset(name: 'missing_broll.mov', path: offlinePath);
    workspace.setAssetFolder(workspace.assets[1], 'Footage');
    final controller = EditorController(autoStartEngine: false);

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: controller,
        child: MaterialApp(
          home: EditorDashboard(workspaceController: workspace),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('media-bin-search')), findsOneWidget);
    expect(find.text('evening_news.mxf'), findsOneWidget);
    expect(find.text('interview.mp4'), findsOneWidget);
    expect(find.text('Offline · Unsorted'), findsOneWidget);
    expect(find.byTooltip('Relink media'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('media-bin-search')),
      'interview',
    );
    await tester.pump();
    expect(find.text('interview.mp4'), findsOneWidget);
    expect(find.text('evening_news.mxf'), findsNothing);
    expect(find.text('1 of 3 items'), findsOneWidget);

    final interviewTile = find.byKey(Key('media-asset-$interviewPath'));
    await tester.tap(
      find.descendant(
        of: interviewTile,
        matching: find.byTooltip('Add favorite'),
      ),
    );
    await tester.enterText(find.byKey(const Key('media-bin-search')), '');
    await tester.tap(find.byKey(const Key('media-bin-favorites')));
    await tester.pump();
    expect(find.text('interview.mp4'), findsOneWidget);
    expect(find.text('missing_broll.mov'), findsNothing);

    await tester.tap(find.byKey(const Key('media-bin-favorites')));
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(Key('media-asset-$newsPath'))),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Move to Footage'), findsOneWidget);
    await tester.tap(find.text('Move to Footage'));
    await tester.pumpAndSettle();
    expect(workspace.assets.first.folder, 'Footage');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    workspace.dispose();
  });

  testWidgets('media bin confirms before replacing an unsaved project', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late io.Directory directory;
    late String nextPath;
    await tester.runAsync(() async {
      directory = await io.Directory.systemTemp.createTemp(
        'autoedit_media_switch_test',
      );
      nextPath = '${directory.path}${io.Platform.pathSeparator}next_source.mp4';
      await io.File(nextPath).writeAsBytes([0]);
    });
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final workspace = WorkspaceController(persist: false)
      ..addAsset(name: 'next_source.mp4', path: nextPath);
    final controller = _MediaBinEditorController()
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 20, reason: 'rough cut'),
      ]
      ..selectedSegmentOrder = 1;
    controller.updateSegment(controller.segments.single.copyWith(end: 24));

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: controller,
        child: MaterialApp(
          home: EditorDashboard(workspaceController: workspace),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(Key('media-asset-$nextPath')));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved project'), findsOneWidget);
    expect(controller.openedPath, isNull);

    await tester.tap(find.text('Switch without saving'));
    await tester.pumpAndSettle();
    expect(controller.openedPath, nextPath);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    workspace.dispose();
  });

  testWidgets('top workspace tabs open captions and export tools', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workspace = WorkspaceController(persist: false);
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 25, reason: 'lead'),
      ]
      ..captions = const [
        CaptionSegment(
          order: 1,
          start: 5,
          end: 8,
          text: 'Caption workspace text',
        ),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider<EditorController>.value(
        value: controller,
        child: MaterialApp(
          home: EditorDashboard(workspaceController: workspace),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('workspace-tab-captions')));
    await tester.pumpAndSettle();
    expect(workspace.activeWorkspaceView, 'captions');
    expect(find.text('Caption workspace text'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workspace-tab-export')));
    await tester.pumpAndSettle();
    expect(workspace.activeWorkspaceView, 'export');
    expect(find.byKey(const Key('export-workspace-panel')), findsOneWidget);
    expect(find.text('Delivery formats'), findsOneWidget);
    expect(find.text('Render preflight'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workspace-tab-edit')));
    await tester.pumpAndSettle();
    expect(workspace.activeWorkspaceView, 'edit');
    expect(find.byKey(const Key('export-workspace-panel')), findsNothing);

    await tester.tap(find.byKey(const Key('workspace-rail-ai')));
    await tester.pumpAndSettle();
    expect(workspace.activeWorkspaceView, 'edit');
    expect(workspace.activeInspectorTab, 1);

    await tester.tap(find.byKey(const Key('workspace-rail-text')));
    await tester.pumpAndSettle();
    expect(workspace.activeWorkspaceView, 'captions');
    expect(workspace.activeInspectorTab, 3);

    workspace.setActivePanel('preview');
    await tester.tap(find.byKey(const Key('workspace-rail-media')));
    await tester.pump();
    expect(workspace.activePanel, 'media');

    await tester.tap(find.byKey(const Key('workspace-rail-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Layout'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    workspace.dispose();
  });

  testWidgets(
    'timeline keeps professional track headers fixed and interactive',
    (tester) async {
      var videoTargetToggles = 0;
      var overlayTargetToggles = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 240,
              child: TimelineEditor(
                duration: 120,
                segments: const [
                  HighlightSegment(
                    order: 1,
                    start: 10,
                    end: 40,
                    reason: 'test',
                  ),
                ],
                playheadSeconds: 20,
                selectedSegmentOrder: 1,
                markIn: null,
                markOut: null,
                timelineMarkers: const [],
                waveform: const [0.1, 0.7, 0.4, 0.9],
                zoom: 2,
                trackHeightScale: 1,
                snappingEnabled: true,
                videoTrackTargeted: true,
                audioTrack1Targeted: true,
                audioTrack2Targeted: true,
                videoTrackLocked: false,
                audioTrackLocked: false,
                audioTrack1Locked: false,
                audioTrack2Locked: false,
                razorTool: false,
                onSegmentChanged: (_) {},
                onScrub: (_) {},
                onSegmentSelected: (_) {},
                onToggleVideoTarget: () => videoTargetToggles += 1,
                onToggleVideoOverlayTarget: () => overlayTargetToggles += 1,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('timeline-track-headers')), findsOneWidget);
      expect(find.byKey(const Key('track-header-v1')), findsOneWidget);
      expect(find.byKey(const Key('track-header-v2')), findsOneWidget);
      expect(find.byKey(const Key('track-header-a1')), findsOneWidget);
      expect(find.byKey(const Key('track-header-a2')), findsOneWidget);
      expect(find.text('SEQUENCE 01'), findsOneWidget);
      expect(find.text('Video 1'), findsOneWidget);
      expect(find.text('Overlay / B-roll'), findsOneWidget);
      expect(find.text('Audio 1'), findsOneWidget);
      expect(find.text('Audio 2'), findsOneWidget);

      await tester.tap(find.text('V1'));
      await tester.pump();
      expect(videoTargetToggles, 1);
      await tester.tap(find.text('V2'));
      await tester.pump();
      expect(overlayTargetToggles, 1);
    },
  );

  testWidgets('V2 overlay clips can be selected and moved on sequence', (
    tester,
  ) async {
    String? selectedOverlayId;
    VideoOverlayClip? changedOverlay;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 280,
            child: TimelineEditor(
              duration: 30,
              sequenceMode: true,
              sourceDuration: 60,
              segments: const [
                HighlightSegment(order: 1, start: 0, end: 30, reason: 'base'),
              ],
              videoOverlays: const [
                VideoOverlayClip(
                  id: 'v2-test',
                  sourcePath: r'C:\media\broll.mov',
                  sourceName: 'broll.mov',
                  timelineStart: 5,
                  timelineEnd: 10,
                  sourceStart: 0,
                  sourceEnd: 5,
                ),
              ],
              playheadSeconds: 0,
              selectedSegmentOrder: null,
              selectedVideoOverlayId: 'v2-test',
              markIn: null,
              markOut: null,
              timelineMarkers: const [],
              waveform: const [],
              zoom: 1,
              trackHeightScale: 1,
              snappingEnabled: true,
              videoTrackTargeted: true,
              videoOverlayTrackTargeted: true,
              audioTrack1Targeted: true,
              audioTrack2Targeted: true,
              videoTrackLocked: false,
              videoOverlayTrackLocked: false,
              audioTrackLocked: false,
              audioTrack1Locked: false,
              audioTrack2Locked: false,
              razorTool: false,
              onSegmentChanged: (_) {},
              onVideoOverlayChanged: (overlay) => changedOverlay = overlay,
              onScrub: (_) {},
              onSegmentSelected: (_) {},
              onVideoOverlaySelected: (id) => selectedOverlayId = id,
            ),
          ),
        ),
      ),
    );

    final overlay = find.byKey(const ValueKey('video-overlay-v2-test'));
    expect(overlay, findsOneWidget);
    expect(find.text('broll.mov'), findsOneWidget);
    await tester.tap(overlay);
    await tester.pump();
    expect(selectedOverlayId, 'v2-test');

    await tester.drag(overlay, const Offset(30, 0));
    await tester.pump();
    expect(changedOverlay, isNotNull);
    expect(changedOverlay!.timelineStart, greaterThan(5));
  });

  testWidgets('timeline paints multiple cached video frames inside V1 clips', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 32, 18),
      Paint()..color = const Color(0xFF3FAE72),
    );
    final thumbnail = await recorder.endRecording().toImage(32, 18);
    addTearDown(thumbnail.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 240,
            child: TimelineEditor(
              duration: 20,
              segments: const [
                HighlightSegment(
                  order: 1,
                  start: 1,
                  end: 12,
                  reason: 'thumbnail clip',
                ),
              ],
              playheadSeconds: 1,
              selectedSegmentOrder: 1,
              markIn: null,
              markOut: null,
              timelineMarkers: const [],
              waveform: const [],
              timelineThumbnails: {
                30: thumbnail,
                195: thumbnail,
                359: thumbnail,
              },
              zoom: 1,
              trackHeightScale: 1,
              snappingEnabled: true,
              videoTrackTargeted: true,
              audioTrack1Targeted: true,
              audioTrack2Targeted: true,
              videoTrackLocked: false,
              audioTrackLocked: false,
              audioTrack1Locked: false,
              audioTrack2Locked: false,
              razorTool: false,
              onSegmentChanged: (_) {},
              onScrub: (_) {},
              onSegmentSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('timeline-canvas')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sequence timeline maps output positions back to source edits', (
    tester,
  ) async {
    double? splitSourceSeconds;
    HighlightSegment? trimmedSegment;
    int? selectedOrder;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 240,
            child: TimelineEditor(
              duration: 5,
              sourceDuration: 60,
              sequenceMode: true,
              segments: const [
                HighlightSegment(
                  order: 1,
                  start: 10,
                  end: 14,
                  playbackSpeed: 2,
                  reason: 'fast opener',
                ),
                HighlightSegment(
                  order: 2,
                  start: 30,
                  end: 33,
                  reason: 'answer',
                ),
              ],
              playheadSeconds: 0,
              selectedSegmentOrder: 1,
              markIn: null,
              markOut: null,
              timelineMarkers: const [],
              waveform: const [0.1, 0.7, 0.4, 0.9],
              zoom: 1,
              trackHeightScale: 1,
              snappingEnabled: false,
              videoTrackTargeted: true,
              audioTrack1Targeted: true,
              audioTrack2Targeted: true,
              videoTrackLocked: false,
              audioTrackLocked: false,
              audioTrack1Locked: false,
              audioTrack2Locked: false,
              razorTool: true,
              onSegmentChanged: (segment) => trimmedSegment = segment,
              onScrub: (_) {},
              onSegmentSelected: (order) => selectedOrder = order,
              onSplitAt: (seconds) => splitSourceSeconds = seconds,
            ),
          ),
        ),
      ),
    );

    final canvas = tester.getRect(find.byKey(const Key('timeline-canvas')));
    final videoY = canvas.top + 90;
    await tester.tapAt(Offset(canvas.left + canvas.width * 0.7, videoY));
    await tester.pump();

    expect(selectedOrder, 2);
    expect(splitSourceSeconds, closeTo(31.5, 0.08));
    expect(find.textContaining('Sequence 00:00:05:00'), findsOneWidget);

    final trimGesture = await tester.startGesture(
      Offset(canvas.left + canvas.width * 0.4, videoY),
    );
    await trimGesture.moveBy(const Offset(-4, 0));
    await tester.pump();
    await trimGesture.moveBy(Offset(-canvas.width * 0.1 + 4, 0));
    await tester.pump();
    await trimGesture.up();
    await tester.pump();

    expect(trimmedSegment?.order, 1);
    expect(trimmedSegment?.end, closeTo(13, 0.08));
  });

  testWidgets('registered keyboard shortcuts mutate editor state', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 30
      ..segments = const [
        HighlightSegment(order: 1, start: 5, end: 13, reason: 'test'),
      ]
      ..selectedSegmentOrder = 1;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.arrowRight);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 1);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowRight, shift: true);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 11);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowLeft);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 10);

    await _pressShortcut(tester, LogicalKeyboardKey.end);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 900);

    await _pressShortcut(tester, LogicalKeyboardKey.home);
    expect(controller.currentPositionSeconds, 0);

    await _pressShortcut(tester, LogicalKeyboardKey.end, shift: true);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 390);

    await _pressShortcut(tester, LogicalKeyboardKey.home, shift: true);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 150);

    await _pressShortcut(tester, LogicalKeyboardKey.home);
    expect(controller.currentPositionSeconds, 0);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowDown);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 150);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowDown);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 390);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowUp);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 150);

    await _pressShortcut(tester, LogicalKeyboardKey.pageDown);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 390);

    await _pressShortcut(tester, LogicalKeyboardKey.pageUp);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 150);

    controller.setMarkInAt(6);
    controller.setMarkOutAt(8);
    await _pressShortcut(tester, LogicalKeyboardKey.keyO, shift: true);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 240);

    await _pressShortcut(tester, LogicalKeyboardKey.keyI, shift: true);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 180);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowRight, alt: true);
    expect(secondsToTimecodeFrame(controller.selectedSegment!.start), 151);
    expect(secondsToTimecodeFrame(controller.selectedSegment!.end), 391);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.arrowLeft,
      alt: true,
      shift: true,
    );
    expect(secondsToTimecodeFrame(controller.selectedSegment!.start), 141);
    expect(secondsToTimecodeFrame(controller.selectedSegment!.end), 381);

    await _pressShortcut(tester, LogicalKeyboardKey.keyC);
    expect(controller.isRazorTool, isTrue);

    await _pressShortcut(tester, LogicalKeyboardKey.keyV);
    expect(controller.isRazorTool, isFalse);

    expect(controller.timelineSnappingEnabled, isTrue);
    await _pressShortcut(tester, LogicalKeyboardKey.keyS);
    expect(controller.timelineSnappingEnabled, isFalse);
    await _pressShortcut(tester, LogicalKeyboardKey.keyS);
    expect(controller.timelineSnappingEnabled, isTrue);

    expect(controller.timelineTrackHeightLabel, 'Tracks Normal');
    await _pressShortcut(tester, LogicalKeyboardKey.equal, alt: true);
    expect(controller.timelineTrackHeightLabel, 'Tracks Tall');
    await _pressShortcut(tester, LogicalKeyboardKey.minus, alt: true);
    expect(controller.timelineTrackHeightLabel, 'Tracks Normal');
    await _pressShortcut(tester, LogicalKeyboardKey.minus, alt: true);
    expect(controller.timelineTrackHeightLabel, 'Tracks Compact');

    expect(controller.timelineZoom, 1.0);
    await _pressShortcut(tester, LogicalKeyboardKey.equal);
    expect(controller.timelineZoom, 1.5);
    await _pressShortcut(tester, LogicalKeyboardKey.minus);
    expect(controller.timelineZoom, 1.0);
    controller.zoomTimeline(2.0);
    await tester.pump();
    expect(controller.timelineZoom, 3.0);
    await _pressShortcut(tester, LogicalKeyboardKey.backslash);
    expect(controller.timelineZoom, 1.0);

    await _pressShortcut(tester, LogicalKeyboardKey.digit1, control: true);
    expect(controller.videoTrackTargeted, isFalse);
    await _pressShortcut(tester, LogicalKeyboardKey.digit2, control: true);
    expect(controller.audioTrack1Targeted, isFalse);
    await _pressShortcut(tester, LogicalKeyboardKey.digit3, control: true);
    expect(controller.audioTrack2Targeted, isTrue);
    await _pressShortcut(tester, LogicalKeyboardKey.digit1, control: true);
    expect(controller.videoTrackTargeted, isTrue);
    await _pressShortcut(tester, LogicalKeyboardKey.digit2, control: true);
    expect(controller.audioTrack1Targeted, isTrue);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.digit1,
      control: true,
      alt: true,
    );
    expect(controller.videoTrackLocked, isTrue);
    await _pressShortcut(
      tester,
      LogicalKeyboardKey.digit1,
      control: true,
      alt: true,
    );
    expect(controller.videoTrackLocked, isFalse);
    await _pressShortcut(
      tester,
      LogicalKeyboardKey.digit2,
      control: true,
      alt: true,
    );
    expect(controller.audioTrack1Locked, isTrue);
    await _pressShortcut(
      tester,
      LogicalKeyboardKey.digit3,
      control: true,
      alt: true,
    );
    expect(controller.audioTrack2Locked, isTrue);
    await _pressShortcut(
      tester,
      LogicalKeyboardKey.digit2,
      control: true,
      alt: true,
    );
    await _pressShortcut(
      tester,
      LogicalKeyboardKey.digit3,
      control: true,
      alt: true,
    );
    expect(controller.anyAudioTrackEditLocked, isFalse);

    await _pressShortcut(tester, LogicalKeyboardKey.keyL);
    expect(controller.playbackShuttleLabel, 'L 1x');
    await _pressShortcut(tester, LogicalKeyboardKey.keyL);
    expect(controller.playbackShuttleLabel, 'L 2x');
    await _pressShortcut(tester, LogicalKeyboardKey.keyJ);
    expect(controller.playbackShuttleLabel, 'J 1x');
    await _pressShortcut(tester, LogicalKeyboardKey.keyK);
    expect(controller.playbackShuttleLabel, 'K Stop');

    await _pressShortcut(tester, LogicalKeyboardKey.keyL, control: true);
    expect(controller.selectedSegment!.audioLinked, isFalse);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.arrowRight,
      control: true,
      alt: true,
    );
    expect(
      secondsToTimecodeFrame(controller.selectedSegment!.effectiveAudioStart),
      142,
    );
    expect(
      secondsToTimecodeFrame(controller.selectedSegment!.effectiveAudioEnd),
      382,
    );

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.arrowLeft,
      control: true,
      alt: true,
      shift: true,
    );
    expect(
      secondsToTimecodeFrame(controller.selectedSegment!.effectiveAudioStart),
      132,
    );
    expect(
      secondsToTimecodeFrame(controller.selectedSegment!.effectiveAudioEnd),
      372,
    );

    await _pressShortcut(tester, LogicalKeyboardKey.keyL, control: true);
    expect(controller.selectedSegment!.audioLinked, isTrue);

    await _pressShortcut(tester, LogicalKeyboardKey.keyD, control: true);
    expect(controller.selectedSegment!.transitionType, 'cut');

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.keyD,
      control: true,
      shift: true,
    );
    expect(controller.selectedSegment!.transitionType, 'cut');

    await _pressShortcut(tester, LogicalKeyboardKey.home);
    expect(controller.currentPositionSeconds, 0);

    controller.addTimelineMarkerAt(5, label: 'A');
    controller.addTimelineMarkerAt(12, label: 'B');

    await _pressShortcut(tester, LogicalKeyboardKey.keyM, shift: true);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 150);

    await _pressShortcut(tester, LogicalKeyboardKey.keyM, shift: true);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 360);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.keyM,
      control: true,
      shift: true,
    );
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 150);

    await _pressShortcut(tester, LogicalKeyboardKey.keyM);
    expect(controller.timelineMarkers.length, 3);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.keyM,
      control: true,
      alt: true,
    );
    expect(controller.timelineMarkers, isEmpty);

    await _pressShortcut(tester, LogicalKeyboardKey.semicolon);
    expect(controller.segments.length, 3);
    expect(controller.segments[1].videoEnabled, isFalse);

    await _pressShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(controller.segments.length, 1);

    await _pressShortcut(tester, LogicalKeyboardKey.quote);
    expect(controller.segments.length, 2);
    expect(secondsToTimecodeFrame(controller.segments.first.end), 180);
    expect(secondsToTimecodeFrame(controller.segments.last.start), 240);

    await _pressShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(controller.segments.length, 1);

    await _pressShortcut(tester, LogicalKeyboardKey.delete);
    expect(controller.segments, isEmpty);

    await _pressShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(controller.segments.length, 1);

    await _pressShortcut(tester, LogicalKeyboardKey.backspace);
    expect(controller.segments, isEmpty);

    await _pressShortcut(tester, LogicalKeyboardKey.keyZ, control: true);
    expect(controller.segments.length, 1);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.keyZ,
      control: true,
      shift: true,
    );
    expect(controller.segments, isEmpty);
  });

  testWidgets('rolling trim shortcuts adjust adjacent edit boundaries', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'first'),
        HighlightSegment(order: 2, start: 20, end: 30, reason: 'second'),
        HighlightSegment(order: 3, start: 40, end: 50, reason: 'third'),
      ]
      ..selectedSegmentOrder = 2;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.period, alt: true);
    expect(secondsToTimecodeFrame(controller.segments[0].end), 301);
    expect(secondsToTimecodeFrame(controller.segments[1].start), 601);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.comma,
      alt: true,
      shift: true,
    );
    expect(secondsToTimecodeFrame(controller.segments[1].end), 899);
    expect(secondsToTimecodeFrame(controller.segments[2].start), 1199);
  });

  testWidgets('Premiere playhead shortcuts select and add edit under cursor', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'first'),
        HighlightSegment(order: 2, start: 20, end: 30, reason: 'second'),
        HighlightSegment(order: 3, start: 40, end: 50, reason: 'third'),
      ]
      ..selectedSegmentOrder = 1;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await controller.seekTo(22, autoplay: false);
    await tester.pump();
    await _pressShortcut(tester, LogicalKeyboardKey.keyD);
    expect(controller.selectedSegmentOrder, 2);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowRight, control: true);
    expect(controller.selectedSegmentOrder, 3);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowRight, control: true);
    expect(controller.selectedSegmentOrder, 3);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowLeft, control: true);
    expect(controller.selectedSegmentOrder, 2);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowLeft, control: true);
    expect(controller.selectedSegmentOrder, 1);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowRight, control: true);
    expect(controller.selectedSegmentOrder, 2);

    await controller.seekTo(25, autoplay: false);
    await tester.pump();
    await _pressShortcut(tester, LogicalKeyboardKey.keyK, control: true);
    expect(controller.segments.length, 4);
    expect(secondsToTimecodeFrame(controller.segments[1].end), 750);
    expect(secondsToTimecodeFrame(controller.segments[2].start), 750);
    expect(controller.selectedSegmentOrder, 3);

    controller.undo();
    await tester.pump();
    expect(controller.segments.length, 3);
    controller.selectedSegmentOrder = 1;
    await controller.seekTo(45, autoplay: false);
    await tester.pump();
    await _pressShortcut(
      tester,
      LogicalKeyboardKey.keyK,
      control: true,
      shift: true,
    );
    expect(controller.segments.length, 4);
    expect(secondsToTimecodeFrame(controller.segments[2].end), 1350);
    expect(secondsToTimecodeFrame(controller.segments[3].start), 1350);

    controller.undo();
    controller.toggleVideoTrackLock();
    await controller.seekTo(45, autoplay: false);
    await tester.pump();
    await _pressShortcut(
      tester,
      LogicalKeyboardKey.keyK,
      control: true,
      shift: true,
    );
    expect(controller.segments.length, 3);
  });

  testWidgets('mark clip shortcut falls back to clip under playhead', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'first'),
        HighlightSegment(order: 2, start: 20, end: 30, reason: 'second'),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await controller.seekTo(22, autoplay: false);
    await tester.pump();
    await _pressShortcut(tester, LogicalKeyboardKey.keyX);

    expect(controller.selectedSegmentOrder, 2);
    expect(secondsToTimecodeFrame(controller.markIn!), 600);
    expect(secondsToTimecodeFrame(controller.markOut!), 900);
  });

  testWidgets('rate stretch shortcut fits selected clip to marked duration', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 22, reason: 'rate'),
      ]
      ..selectedSegmentOrder = 1;
    controller.setMarkInAt(40);
    controller.setMarkOutAt(46);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.keyR);

    expect(controller.selectedSegment!.playbackSpeed, 2);
    expect(controller.selectedSegment!.source, contains('rate-stretch'));
    expect(controller.selectedSegment!.outputDuration, closeTo(6, 0.01));
  });

  testWidgets('selected clip lift and extract shortcuts edit timeline', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'one'),
        HighlightSegment(order: 2, start: 20, end: 40, reason: 'two'),
        HighlightSegment(order: 3, start: 50, end: 60, reason: 'three'),
      ]
      ..selectedSegmentOrder = 2;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.semicolon, control: true);
    expect(controller.segments[1].videoEnabled, isFalse);
    expect(controller.segments[1].audioMuted, isTrue);

    controller.undo();
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.quote, control: true);
    expect(controller.segments.length, 2);
    expect(controller.selectedSegment!.reason, 'three');

    controller.undo();
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.delete, shift: true);
    expect(controller.segments.length, 2);
    expect(controller.selectedSegment!.reason, 'three');

    controller.undo();
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.backspace, shift: true);
    expect(controller.segments.length, 2);
    expect(controller.selectedSegment!.reason, 'three');
  });

  testWidgets('selected clip move shortcuts reorder timeline', (tester) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'one'),
        HighlightSegment(order: 2, start: 20, end: 40, reason: 'two'),
        HighlightSegment(order: 3, start: 50, end: 60, reason: 'three'),
      ]
      ..selectedSegmentOrder = 2;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(controller.segments.map((segment) => segment.reason), [
      'two',
      'one',
      'three',
    ]);
    expect(controller.selectedSegmentOrder, 1);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowUp, control: true);
    expect(controller.segments.map((segment) => segment.reason), [
      'two',
      'one',
      'three',
    ]);
    expect(controller.selectedSegmentOrder, 1);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowDown, control: true);
    await _pressShortcut(tester, LogicalKeyboardKey.arrowDown, control: true);
    expect(controller.segments.map((segment) => segment.reason), [
      'one',
      'three',
      'two',
    ]);
    expect(controller.selectedSegmentOrder, 3);
  });

  testWidgets('selected clip enable shortcut toggles linked media', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'one'),
      ]
      ..selectedSegmentOrder = 1;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.keyE, shift: true);
    expect(controller.selectedSegment!.videoEnabled, isFalse);
    expect(controller.selectedSegment!.audioMuted, isTrue);

    await _pressShortcut(tester, LogicalKeyboardKey.keyE, shift: true);
    expect(controller.selectedSegment!.videoEnabled, isTrue);
    expect(controller.selectedSegment!.audioMuted, isFalse);

    controller.toggleVideoTrackLock();
    await tester.pump();
    await _pressShortcut(tester, LogicalKeyboardKey.keyE, shift: true);
    expect(controller.selectedSegment!.videoEnabled, isTrue);
    expect(controller.selectedSegment!.audioMuted, isFalse);
  });

  testWidgets('deselect shortcuts clear selected clip without history', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'one'),
        HighlightSegment(order: 2, start: 12, end: 18, reason: 'two'),
      ]
      ..selectedSegmentOrder = 2;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.keyA,
      control: true,
      shift: true,
    );
    expect(controller.selectedSegmentOrder, isNull);

    await controller.seekTo(13, autoplay: false);
    await tester.pump();
    await _pressShortcut(tester, LogicalKeyboardKey.keyD);
    expect(controller.selectedSegmentOrder, 2);

    await _pressShortcut(tester, LogicalKeyboardKey.escape);
    expect(controller.selectedSegmentOrder, isNull);
  });

  testWidgets('clip clipboard shortcuts copy paste and cut selected clips', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 60
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 5, reason: 'one'),
        HighlightSegment(order: 2, start: 10, end: 15, reason: 'two'),
      ]
      ..selectedSegmentOrder = 1;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.keyC, control: true);
    expect(controller.hasClipClipboard, isTrue);

    controller.selectedSegmentOrder = 2;
    await tester.pump();
    await _pressShortcut(tester, LogicalKeyboardKey.keyV, control: true);
    expect(controller.segments.length, 3);
    expect(controller.selectedSegmentOrder, 3);
    expect(secondsToTimecodeFrame(controller.segments.last.start), 0);
    expect(secondsToTimecodeFrame(controller.segments.last.end), 150);

    controller.selectedSegmentOrder = 2;
    await tester.pump();
    await _pressShortcut(tester, LogicalKeyboardKey.keyX, control: true);
    expect(controller.segments.length, 2);
    expect(controller.hasClipClipboard, isTrue);

    await _pressShortcut(tester, LogicalKeyboardKey.keyV, control: true);
    expect(controller.segments.length, 3);
    expect(secondsToTimecodeFrame(controller.segments.last.start), 300);
    expect(secondsToTimecodeFrame(controller.segments.last.end), 450);
  });

  testWidgets('insert and overwrite shortcuts use marked source range', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 90
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 10, reason: 'one'),
        HighlightSegment(order: 2, start: 20, end: 30, reason: 'two'),
      ]
      ..selectedSegmentOrder = 2;
    controller.setMarkInAt(40);
    controller.setMarkOutAt(46);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.comma);
    expect(controller.segments.length, 3);
    expect(controller.selectedSegment!.reason, 'Insert In/Out edit');
    expect(secondsToTimecodeFrame(controller.selectedSegment!.start), 1200);

    controller.setMarkInAt(50);
    controller.setMarkOutAt(56);
    await tester.pump();

    await _pressShortcut(tester, LogicalKeyboardKey.period);
    expect(controller.segments.length, 3);
    expect(controller.selectedSegment!.reason, 'Overwrite In/Out edit');
    expect(secondsToTimecodeFrame(controller.selectedSegment!.start), 1500);
  });

  testWidgets('mouse wheel zooms the timeline track', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 35, reason: 'test'),
      ]
      ..selectedSegmentOrder = 1;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    final timelineCenter = tester.getCenter(find.byType(TimelineEditor).first);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: timelineCenter,
        scrollDelta: Offset(0, -120),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.timelineZoom, greaterThan(1.0));

    await tester.sendEventToBinding(
      PointerScrollEvent(position: timelineCenter, scrollDelta: Offset(0, 120)),
    );
    await tester.pumpAndSettle();

    expect(controller.timelineZoom, 1.0);
  });

  testWidgets('timeline snapping pulls scrubber to marker and edit points', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = EditorController(autoStartEngine: false)
      ..duration = 100
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 30, reason: 'test'),
      ]
      ..timelineMarkers = const [
        TimelineMarker(id: 1, seconds: 20, label: 'M01'),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    final timelineBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('timeline-scroll-area')),
    );
    final timelineTopLeft = timelineBox.localToGlobal(Offset.zero);
    final markerNearX = timelineBox.size.width * 20.4 / controller.duration;
    const videoLaneY = 56.0;

    await tester.tapAt(timelineTopLeft + Offset(markerNearX, videoLaneY));
    await tester.pump();
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 600);

    await _pressShortcut(tester, LogicalKeyboardKey.keyS);
    expect(controller.timelineSnappingEnabled, isFalse);
    await tester.pumpAndSettle();

    final updatedTimelineBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('timeline-scroll-area')),
    );
    final updatedTimelineTopLeft = updatedTimelineBox.localToGlobal(
      Offset.zero,
    );

    await tester.tapAt(
      updatedTimelineTopLeft + Offset(markerNearX, videoLaneY),
    );
    await tester.pump();
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 612);

    await _pressShortcut(tester, LogicalKeyboardKey.keyS);
    expect(controller.timelineSnappingEnabled, isTrue);
    expect(find.text('Snap S'), findsOneWidget);
  });

  testWidgets('timeline context menu exposes detached audio nudge commands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..segments = const [
        HighlightSegment(
          order: 1,
          start: 10,
          end: 35,
          reason: 'test',
          audioStart: 12,
          audioEnd: 37,
          audioLinked: false,
        ),
      ]
      ..selectedSegmentOrder = 1;
    controller.setMarkInAt(42);
    controller.setMarkOutAt(48);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    final timelineBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('timeline-scroll-area')),
    );
    final timelineTopLeft = timelineBox.localToGlobal(Offset.zero);
    final menuPoint =
        timelineTopLeft + Offset(timelineBox.size.width * 20 / 120, 132);

    await tester.tapAt(menuPoint, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Disable snapping'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('Track Targets'), findsOneWidget);
    expect(find.text('Untarget V1 video'), findsOneWidget);
    expect(find.text('Ctrl+1'), findsOneWidget);
    expect(find.text('Track Locks'), findsOneWidget);
    expect(find.text('Lock V1 video'), findsOneWidget);
    expect(find.text('Ctrl+Alt+1'), findsOneWidget);
    expect(find.text('Lock A1 audio'), findsOneWidget);
    expect(find.text('Ctrl+Alt+2'), findsOneWidget);
    expect(find.text('Lock A2 audio'), findsOneWidget);
    expect(find.text('Ctrl+Alt+3'), findsOneWidget);
    expect(find.text('Move detached audio earlier 1f'), findsOneWidget);
    expect(find.text('Ctrl+Alt+Left'), findsOneWidget);
    expect(find.text('Move detached audio later 10f'), findsOneWidget);
    expect(find.text('Ctrl+Alt+Shift+Right'), findsOneWidget);
    expect(find.text('Roll incoming later 1f'), findsOneWidget);
    expect(find.text('Alt+.'), findsOneWidget);
    expect(find.text('Roll outgoing earlier 1f'), findsOneWidget);
    expect(find.text('Alt+Shift+,'), findsOneWidget);
    expect(find.text('Select clip at cursor'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(find.text('Deselect clip'), findsOneWidget);
    expect(find.text('Ctrl+Shift+A'), findsOneWidget);
    expect(find.text('Select previous clip'), findsOneWidget);
    expect(find.text('Ctrl+Left'), findsOneWidget);
    expect(find.text('Select next clip'), findsOneWidget);
    expect(find.text('Ctrl+Right'), findsOneWidget);
    expect(find.text('Add Edit to all tracks'), findsOneWidget);
    expect(find.text('Ctrl+Shift+K'), findsOneWidget);
    expect(find.text('Previous edit point'), findsOneWidget);
    expect(find.text('Up / PageUp'), findsOneWidget);
    expect(find.text('Next edit point'), findsOneWidget);
    expect(find.text('Down / PageDown'), findsOneWidget);
    expect(find.text('Go to clip start'), findsOneWidget);
    expect(find.text('Shift+Home'), findsOneWidget);
    expect(find.text('Go to clip end'), findsOneWidget);
    expect(find.text('Shift+End'), findsOneWidget);
    expect(find.text('Rate stretch to In/Out'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
    expect(find.text('Lift selected clip'), findsOneWidget);
    expect(find.text('Ctrl+;'), findsOneWidget);
    expect(find.text('Delete clip'), findsOneWidget);
    expect(find.text('Delete / Backspace'), findsOneWidget);
    expect(find.text('Extract selected clip'), findsOneWidget);
    expect(
      find.text("Ctrl+' / Shift+Delete / Shift+Backspace"),
      findsOneWidget,
    );
    expect(find.text('Move earlier'), findsOneWidget);
    expect(find.text('Ctrl+Up'), findsOneWidget);
    expect(find.text('Move later'), findsOneWidget);
    expect(find.text('Ctrl+Down'), findsOneWidget);
    expect(find.text('Disable clip'), findsOneWidget);
    expect(find.text('Shift+E'), findsOneWidget);
    expect(find.text('Insert In/Out before clip'), findsOneWidget);
    expect(find.text(','), findsOneWidget);
    expect(find.text('Overwrite selected with In/Out'), findsOneWidget);
    expect(find.text('.'), findsOneWidget);

    await tester.tap(find.text('Move detached audio later 1f'));
    await tester.pumpAndSettle();

    expect(
      secondsToTimecodeFrame(controller.selectedSegment!.effectiveAudioStart),
      361,
    );
    expect(
      secondsToTimecodeFrame(controller.selectedSegment!.effectiveAudioEnd),
      1111,
    );
  });

  testWidgets('timeline context menu exposes audio bus commands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..segments = const [
        HighlightSegment(order: 1, start: 10, end: 35, reason: 'test'),
        HighlightSegment(order: 2, start: 45, end: 70, reason: 'test 2'),
      ]
      ..selectedSegmentOrder = 1;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const HighlightEditorApp(),
      ),
    );
    await tester.pump();

    final timelineBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('timeline-scroll-area')),
    );
    final timelineTopLeft = timelineBox.localToGlobal(Offset.zero);
    final menuPoint =
        timelineTopLeft + Offset(timelineBox.size.width * 20 / 120, 132);

    await tester.tapAt(menuPoint, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Audio Track Bus'), findsOneWidget);
    expect(find.text('Disable all A1'), findsOneWidget);
    expect(find.text('Disable all A2'), findsOneWidget);
    expect(find.text('Solo A2 track'), findsOneWidget);

    await tester.tap(find.text('Solo A2 track'));
    await tester.pumpAndSettle();

    expect(
      controller.segments.every((segment) => !segment.audioChannel1Enabled),
      isTrue,
    );
    expect(
      controller.segments.every((segment) => segment.audioChannel2Enabled),
      isTrue,
    );
  });

  testWidgets('render output panel can reveal local file location', (
    tester,
  ) async {
    String? revealedPath;
    String? openedPath;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RenderOutputsPanel(
            outputs: const [
              BatchRenderItemResult(
                label: 'Shorts 01',
                outputName: 'shorts_01.mp4',
                url:
                    'http://127.0.0.1:8000/api/jobs/job/download/shorts_01.mp4',
                path: r'C:\AutoEdit outputs\shorts_01.mp4',
                durationSeconds: 61.2,
                sizeBytes: 234567,
                warnings: ['렌더 파일 크기가 매우 작습니다.'],
              ),
              BatchRenderItemResult(
                label: 'Render Manifest CSV',
                outputName: 'render_manifest.csv',
                url:
                    'http://127.0.0.1:8000/api/jobs/job/download/render_manifest.csv',
                kind: 'manifest',
                path: r'C:\AutoEdit outputs\render_manifest.csv',
                sizeBytes: 1024,
              ),
            ],
            onRevealPath: (path) async {
              revealedPath = path;
            },
            onOpenPath: (path) async {
              openedPath = path;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Open rendered file'));
    await tester.pump();

    expect(find.text('Rendered outputs (1 + 1 manifests)'), findsOneWidget);
    expect(find.text('렌더 파일 크기가 매우 작습니다.'), findsOneWidget);
    expect(find.textContaining('229 KB'), findsOneWidget);
    expect(openedPath, r'C:\AutoEdit outputs\shorts_01.mp4');
    expect(find.text('shorts_01.mp4 opened'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byTooltip('Show in folder').first);
    await tester.pump();

    expect(revealedPath, r'C:\AutoEdit outputs\shorts_01.mp4');

    await tester.tap(find.byTooltip('Open render manifest'));
    await tester.pump();

    expect(openedPath, r'C:\AutoEdit outputs\render_manifest.csv');
  });
}

class _ShortcutSaveEditorController extends EditorController {
  _ShortcutSaveEditorController() : super(autoStartEngine: false);

  int saveInvocations = 0;

  @override
  Future<void> saveProjectFile() async {
    saveInvocations += 1;
  }
}

class _MediaBinEditorController extends EditorController {
  _MediaBinEditorController() : super(autoStartEngine: false);

  String? openedPath;

  @override
  Future<void> openMediaPath(String path) async {
    openedPath = path;
  }
}

Future<void> _pressShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool alt = false,
}) async {
  if (control) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (alt) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  }
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  if (alt) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }
  if (control) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await tester.pump();
}
