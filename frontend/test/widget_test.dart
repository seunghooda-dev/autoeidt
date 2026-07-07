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

    expect(find.text('AI 하이라이트 편집기'), findsOneWidget);
    expect(find.text('영상 선택'), findsOneWidget);
  });
}
