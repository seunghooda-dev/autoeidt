import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/main.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
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
