import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/main.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/state/workspace_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('workspace keyboard commands lock and maximize active panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editor = EditorController(autoStartEngine: false);
    final workspace = WorkspaceController(persist: false)
      ..setActivePanel('timeline');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: editor,
        child: MaterialApp(
          home: EditorDashboard(workspaceController: workspace),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backquote);
    await tester.pump();
    expect(workspace.maximizedPanel, 'timeline');
    await tester.sendKeyEvent(LogicalKeyboardKey.backquote);
    expect(workspace.maximizedPanel, isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(workspace.layoutLocked, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('command-palette-search')), findsOneWidget);
    expect(find.text('Import media'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    editor.dispose();
    workspace.dispose();
  });
}
