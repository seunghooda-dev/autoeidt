import 'dart:async';
import 'dart:io';

class LocalEngineState {
  const LocalEngineState({
    required this.status,
    required this.message,
    this.isRunning = false,
    this.isStarting = false,
    this.canStart = true,
  });

  final String status;
  final String message;
  final bool isRunning;
  final bool isStarting;
  final bool canStart;

  factory LocalEngineState.idle() {
    return const LocalEngineState(status: 'idle', message: '로컬 편집 엔진 확인 전');
  }

  factory LocalEngineState.running({bool startedHere = false}) {
    return LocalEngineState(
      status: 'running',
      message: startedHere ? '로컬 편집 엔진 실행 완료' : '실행 중인 편집 엔진에 연결됨',
      isRunning: true,
    );
  }

  factory LocalEngineState.starting() {
    return const LocalEngineState(
      status: 'starting',
      message: '로컬 편집 엔진 시작 중',
      isStarting: true,
    );
  }

  factory LocalEngineState.unavailable(String message) {
    return LocalEngineState(
      status: 'unavailable',
      message: message,
      canStart: false,
    );
  }
}

class LocalEngineService {
  Process? _process;

  Future<LocalEngineState> ensureRunning({int port = 8000}) async {
    if (await _isHealthy(port)) {
      return LocalEngineState.running();
    }

    if (!Platform.isWindows) {
      return LocalEngineState.unavailable('현재 자동 엔진 시작은 Windows 데스크톱에서 지원됩니다.');
    }

    final scriptPath = _findEngineScript();
    if (scriptPath == null) {
      return LocalEngineState.unavailable(
        '엔진 스크립트를 찾지 못했습니다. scripts/start-desktop-engine.ps1을 확인해 주세요.',
      );
    }

    if (_process == null) {
      _process = await Process.start('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
        '-Port',
        '$port',
      ], mode: ProcessStartMode.normal);
      _process!.stdout.drain<void>();
      _process!.stderr.drain<void>();
    }

    final deadline = DateTime.now().add(const Duration(seconds: 75));
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy(port)) {
        return LocalEngineState.running(startedHere: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }

    return LocalEngineState.unavailable(
      '로컬 편집 엔진 시작 시간이 초과되었습니다. Python/FFmpeg 설치 상태를 확인해 주세요.',
    );
  }

  Future<void> dispose() async {
    final process = _process;
    _process = null;
    process?.kill();
  }

  Future<bool> _isHealthy(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/health'),
      );
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  String? _findEngineScript() {
    final names = <String>[
      'scripts${Platform.pathSeparator}start-desktop-engine.ps1',
      '..${Platform.pathSeparator}scripts${Platform.pathSeparator}start-desktop-engine.ps1',
    ];
    final roots = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];

    for (final root in roots) {
      Directory? current = root;
      for (var depth = 0; depth < 8 && current != null; depth++) {
        for (final name in names) {
          final candidate = File(
            '${current.path}${Platform.pathSeparator}$name',
          );
          if (candidate.existsSync()) {
            return candidate.resolveSymbolicLinksSync();
          }
        }
        current = current.parent.path == current.path ? null : current.parent;
      }
    }
    return null;
  }
}
