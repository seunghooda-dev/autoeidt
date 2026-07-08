import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/main.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/models/job_models.dart';
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

    await _pressShortcut(tester, LogicalKeyboardKey.keyC);
    expect(controller.isRazorTool, isTrue);

    await _pressShortcut(tester, LogicalKeyboardKey.keyV);
    expect(controller.isRazorTool, isFalse);

    await _pressShortcut(tester, LogicalKeyboardKey.keyL, control: true);
    expect(controller.selectedSegment!.audioLinked, isFalse);

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

    await _pressShortcut(tester, LogicalKeyboardKey.keyM);
    expect(controller.timelineMarkers.length, 1);

    await _pressShortcut(
      tester,
      LogicalKeyboardKey.keyM,
      control: true,
      shift: true,
    );
    expect(controller.timelineMarkers, isEmpty);

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

    expect(find.text('렌더 파일 크기가 매우 작습니다.'), findsOneWidget);
    expect(find.textContaining('229 KB'), findsOneWidget);
    expect(openedPath, r'C:\AutoEdit outputs\shorts_01.mp4');
    expect(find.text('shorts_01.mp4 opened'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byTooltip('Show in folder'));
    await tester.pump();

    expect(revealedPath, r'C:\AutoEdit outputs\shorts_01.mp4');
  });
}

Future<void> _pressShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  if (control) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await tester.pump();
}
