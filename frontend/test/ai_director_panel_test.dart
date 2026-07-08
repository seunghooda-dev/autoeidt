import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/widgets/ai_director_panel.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ai director shows story arc chips for shorts candidates', (
    tester,
  ) async {
    final controller = EditorController(autoStartEngine: false)
      ..duration = 120
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 20, reason: 'hook'),
      ]
      ..shortsCandidates = const [
        ShortsCandidate(
          id: 1,
          label: 'Story 01',
          reason: 'story arc candidate',
          segments: [
            HighlightSegment(order: 1, start: 0, end: 20, reason: 'hook'),
          ],
          qualityScore: 82,
          qualityGrade: 'A',
          storyFlow: ['Hook', 'Evidence'],
          storyScore: 72,
          strengths: ['Story'],
        ),
      ]
      ..selectedShortsId = 1;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 420, child: AiDirectorPanel())),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Story 01'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.text('Story Arc'), findsOneWidget);
    expect(find.text('S72'), findsOneWidget);
    expect(find.text('Hook'), findsWidgets);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('Impact'), findsOneWidget);
    expect(find.text('Resolution'), findsOneWidget);
  });
}
