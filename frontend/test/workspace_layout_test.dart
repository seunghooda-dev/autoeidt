import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/main.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';
import 'package:highlight_editor_app/state/workspace_controller.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('desktop panel borders resize the active workspace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editor = EditorController(autoStartEngine: false);
    final workspace = WorkspaceController(persist: false);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: editor,
        child: MaterialApp(
          home: EditorDashboard(workspaceController: workspace),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('workspace-media-resize')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('workspace-media-resize')),
      const Offset(45, 0),
    );
    await tester.pump();
    expect(workspace.mediaWidth, greaterThan(320));

    await tester.drag(
      find.byKey(const Key('workspace-timeline-resize')),
      const Offset(0, -35),
    );
    await tester.pump();
    expect(workspace.timelineHeight, greaterThan(342));
    editor.dispose();
    workspace.dispose();
  });
}
