import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/main.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/utils/timecode.dart';
import 'package:highlight_editor_app/widgets/render_outputs_panel.dart';
import 'package:highlight_editor_app/widgets/timeline_editor.dart';
import 'package:provider/provider.dart';

import 'package:highlight_editor_app/state/editor_controller.dart';

void main() {
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

    await _pressShortcut(tester, LogicalKeyboardKey.arrowDown);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 150);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowDown);
    expect(secondsToTimecodeFrame(controller.currentPositionSeconds), 390);

    await _pressShortcut(tester, LogicalKeyboardKey.arrowUp);
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
    expect(controller.selectedSegment!.videoFadeIn, 0.15);
    expect(controller.selectedSegment!.videoFadeOut, 0.15);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.keyD,
      control: true,
      shift: true,
    );
    expect(controller.selectedSegment!.audioFadeIn, 0.12);
    expect(controller.selectedSegment!.audioFadeOut, 0.12);

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
      find.byType(TimelineEditor).first,
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
      find.byType(TimelineEditor).first,
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
      find.byType(TimelineEditor).first,
    );
    final timelineTopLeft = timelineBox.localToGlobal(Offset.zero);
    final menuPoint = timelineTopLeft + const Offset(170, 98);

    await tester.tapAt(menuPoint, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Disable snapping'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('Track Targets'), findsOneWidget);
    expect(find.text('Untarget V1 video'), findsOneWidget);
    expect(find.text('Ctrl+1'), findsOneWidget);
    expect(find.text('Move detached audio earlier 1f'), findsOneWidget);
    expect(find.text('Ctrl+Alt+Left'), findsOneWidget);
    expect(find.text('Move detached audio later 10f'), findsOneWidget);
    expect(find.text('Ctrl+Alt+Shift+Right'), findsOneWidget);
    expect(find.text('Roll incoming later 1f'), findsOneWidget);
    expect(find.text('Alt+.'), findsOneWidget);
    expect(find.text('Roll outgoing earlier 1f'), findsOneWidget);
    expect(find.text('Alt+Shift+,'), findsOneWidget);
    expect(find.text('Lift selected clip'), findsOneWidget);
    expect(find.text('Ctrl+;'), findsOneWidget);
    expect(find.text('Extract selected clip'), findsOneWidget);
    expect(find.text("Ctrl+'"), findsOneWidget);
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
      find.byType(TimelineEditor).first,
    );
    final timelineTopLeft = timelineBox.localToGlobal(Offset.zero);
    final menuPoint = timelineTopLeft + const Offset(170, 98);

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
