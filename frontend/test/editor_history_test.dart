import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';

void main() {
  test('history points restore a previous editable timeline state', () {
    final editor = EditorController(autoStartEngine: false);
    editor.segments = const [
      HighlightSegment(order: 1, start: 0, end: 10, reason: 'Opening'),
      HighlightSegment(order: 2, start: 12, end: 22, reason: 'Answer'),
    ];
    editor.selectedSegmentOrder = 1;

    editor.deleteSelectedSegment();
    expect(editor.segments, hasLength(1));
    expect(editor.editorHistoryPoints, hasLength(2));
    expect(editor.editorHistoryPoints.first.isCurrent, isTrue);

    editor.restoreHistoryDepth(1);
    expect(editor.segments, hasLength(2));
    expect(editor.canRedo, isTrue);
    editor.dispose();
  });

  test('history restore safely clamps requests beyond available states', () {
    final editor = EditorController(autoStartEngine: false)
      ..segments = const [
        HighlightSegment(order: 1, start: 0, end: 5, reason: 'Clip'),
      ]
      ..selectedSegmentOrder = 1;
    editor.deleteSelectedSegment();
    editor.restoreHistoryDepth(99);
    expect(editor.segments, hasLength(1));
    editor.dispose();
  });
}
