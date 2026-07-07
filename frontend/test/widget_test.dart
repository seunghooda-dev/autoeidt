import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/main.dart';
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
    expect(find.text('Import'), findsOneWidget);
  });
}
