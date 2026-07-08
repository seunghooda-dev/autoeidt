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

  test('builds Windows default-app open command for rendered file path', () {
    final command = RenderOutputLauncher.openCommandForPath(
      r'C:\AutoEdit outputs\shorts_01.mp4',
      platform: 'windows',
    );

    expect(command, isNotNull);
    expect(command!.executable, 'cmd.exe');
    expect(command.arguments, [
      '/c',
      'start',
      '',
      r'C:\AutoEdit outputs\shorts_01.mp4',
    ]);
  });

  test('builds Linux default-app open command for rendered file path', () {
    final command = RenderOutputLauncher.openCommandForPath(
      '/home/seung/AutoEdit/shorts_01.mp4',
      platform: 'linux',
    );

    expect(command, isNotNull);
    expect(command!.executable, 'xdg-open');
    expect(command.arguments, ['/home/seung/AutoEdit/shorts_01.mp4']);
  });

  test('returns null for empty render path', () {
    expect(
      RenderOutputLauncher.commandForPath('   ', platform: 'windows'),
      isNull,
    );
    expect(
      RenderOutputLauncher.openCommandForPath('   ', platform: 'windows'),
      isNull,
    );
  });
}
