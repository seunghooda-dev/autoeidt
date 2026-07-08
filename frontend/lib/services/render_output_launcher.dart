import 'dart:io' as io;

import 'package:flutter/foundation.dart';

class RenderOutputOpenCommand {
  const RenderOutputOpenCommand({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

class RenderOutputLauncher {
  const RenderOutputLauncher._();

  static RenderOutputOpenCommand? commandForPath(
    String path, {
    String? platform,
  }) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final currentPlatform =
        platform ?? (kIsWeb ? 'web' : io.Platform.operatingSystem);
    return switch (currentPlatform) {
      'windows' => RenderOutputOpenCommand(
        executable: 'explorer.exe',
        arguments: ['/select,$trimmed'],
      ),
      'macos' => RenderOutputOpenCommand(
        executable: 'open',
        arguments: ['-R', trimmed],
      ),
      'linux' => RenderOutputOpenCommand(
        executable: 'xdg-open',
        arguments: [_parentDirectory(trimmed)],
      ),
      _ => null,
    };
  }

  static Future<void> reveal(String path) async {
    final command = commandForPath(path);
    if (command == null) {
      throw UnsupportedError('render output location is not available');
    }
    await io.Process.start(
      command.executable,
      command.arguments,
      mode: io.ProcessStartMode.detached,
    );
  }

  static String _parentDirectory(String path) {
    if (io.FileSystemEntity.isDirectorySync(path)) {
      return path;
    }
    return io.File(path).parent.path;
  }
}
