import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/widgets/timeline_marker_panel.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('timeline marker panel seeks and deletes markers', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..timelineMarkers = const [
        TimelineMarker(
          id: 1,
          seconds: 5,
          label: 'Hook',
          color: 'cyan',
          note: 'opening beat',
        ),
        TimelineMarker(id: 2, seconds: 12, label: 'Fact', color: 'green'),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: Scaffold(body: TimelineMarkerPanel())),
      ),
    );

    expect(find.text('Markers'), findsOneWidget);
    expect(find.text('Hook'), findsOneWidget);
    expect(find.text('Fact'), findsOneWidget);
    expect(find.text('opening beat'), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);

    await tester.tap(find.text('Hook'));
    await tester.pump();
    expect(controller.currentPositionSeconds, 5);

    await tester.tap(find.byTooltip('Hook 구간을 In/Out으로 지정'));
    await tester.pump();
    expect(controller.markIn, 5);
    expect(controller.markOut, 12);

    await tester.tap(find.byTooltip('Hook 구간을 클립으로 추가'));
    await tester.pump();
    expect(controller.segments.single.start, 5);
    expect(controller.segments.single.end, 12);
    expect(controller.segments.single.reason, '마커 Hook 구간');

    await tester.tap(find.text('Rough cut'));
    await tester.pump();
    expect(controller.segments.length, 2);
    expect(controller.segments.first.reason, '마커 Hook 구간');
    expect(controller.segments.last.reason, '마커 Fact 구간');

    await tester.tap(find.byKey(const ValueKey('marker-roughcut-1')));
    await tester.pump();
    expect(controller.timelineMarkers.first.enabled, isFalse);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('러프컷 제외'), findsOneWidget);

    await tester.tap(find.text('Rough cut'));
    await tester.pump();
    expect(controller.segments.length, 1);
    expect(controller.segments.single.reason, '마커 Fact 구간');

    await tester.tap(find.byTooltip('Hook 마커 편집'));
    await tester.pumpAndSettle();
    expect(find.text('마커 편집'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('marker-label-field')),
      'Cold open',
    );
    await tester.enterText(
      find.byKey(const Key('marker-note-field')),
      'tighten this intro',
    );
    await tester.tap(find.text('Violet'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(controller.timelineMarkers.first.label, 'Cold open');
    expect(controller.timelineMarkers.first.note, 'tighten this intro');
    expect(controller.timelineMarkers.first.color, 'violet');
    expect(find.text('Cold open'), findsOneWidget);
    expect(find.text('tighten this intro'), findsOneWidget);

    await tester.tap(find.byTooltip('Cold open 마커 삭제'));
    await tester.pump();
    expect(controller.timelineMarkers.map((marker) => marker.label), ['Fact']);
  });

  testWidgets('timeline marker panel can add the first marker', (tester) async {
    final controller = EditorController(autoStartEngine: false)..duration = 60;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: Scaffold(body: TimelineMarkerPanel())),
      ),
    );

    expect(find.text('마커 없음'), findsOneWidget);

    await tester.tap(find.text('현재 위치 마커'));
    await tester.pump();

    expect(controller.timelineMarkers.length, 1);
    expect(controller.timelineMarkers.single.label, 'M01');
  });
}
