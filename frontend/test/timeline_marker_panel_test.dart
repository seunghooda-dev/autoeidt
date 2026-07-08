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

    await tester.tap(find.text('Hook'));
    await tester.pump();
    expect(controller.currentPositionSeconds, 5);

    await tester.tap(find.byTooltip('Hook 마커 삭제'));
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
