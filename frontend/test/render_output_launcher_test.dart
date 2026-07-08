import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/services/render_output_launcher.dart';

void main() {
  test('builds Windows explorer command for rendered file path', () {
    final command = RenderOutputLauncher.commandForPath(
      r'C:\AutoEdit outputs\shorts_01.mp4',
      platform: 'windows',
    );

    expect(command, isNotNull);
    expect(command!.executable, 'explorer.exe');
    expect(command.arguments, [r'/select,C:\AutoEdit outputs\shorts_01.mp4']);
  });

  test('builds macOS reveal command for rendered file path', () {
    final command = RenderOutputLauncher.commandForPath(
      '/Users/seung/AutoEdit/shorts_01.mp4',
      platform: 'macos',
    );

    expect(command, isNotNull);
    expect(command!.executable, 'open');
    expect(command.arguments, ['-R', '/Users/seung/AutoEdit/shorts_01.mp4']);
  });

  test('returns null for empty render path', () {
    expect(
      RenderOutputLauncher.commandForPath('   ', platform: 'windows'),
      isNull,
    );
  });
}
