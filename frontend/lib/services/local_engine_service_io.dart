import 'dart:async';
import 'dart:convert';
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
      message: '로컬 편집 엔진 시작 중 · 첫 실행은 최대 3분 정도 걸릴 수 있습니다',
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
  int? _startedPort;

  Future<LocalEngineState> ensureRunning({int port = 8000}) async {
    if (await _isHealthy(port)) {
      if (await _hasRequiredApi(port)) {
        return LocalEngineState.running();
      }
      if (!Platform.isWindows || !await _isManagedAutoEditEngine(port)) {
        return LocalEngineState.unavailable(
          '8000번 포트에 구버전 또는 다른 편집 엔진이 실행 중입니다. '
          'Docker compose를 종료하거나 해당 서버를 내린 뒤 AutoEdit를 다시 실행해 주세요.',
        );
      }
      if (!await _stopManagedEngine(port)) {
        return LocalEngineState.unavailable(
          '이전 AutoEdit 편집 엔진을 교체하지 못했습니다. '
          'AutoEdit를 모두 종료한 뒤 다시 실행해 주세요.',
        );
      }
      _process = null;
      _startedPort = null;
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
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
        '-Port',
        '$port',
      ], mode: ProcessStartMode.normal);
      _startedPort = port;
      _process!.stdout.drain<void>();
      _process!.stderr.drain<void>();
    }

    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy(port)) {
        if (!await _hasRequiredApi(port)) {
          return LocalEngineState.unavailable(
            '8000번 포트에 구버전 또는 다른 편집 엔진이 실행 중입니다. '
            'Docker compose를 종료하거나 해당 서버를 내린 뒤 AutoEdit를 다시 실행해 주세요.',
          );
        }
        return LocalEngineState.running(startedHere: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }

    return LocalEngineState.unavailable(
      '로컬 편집 엔진이 3분 안에 시작되지 않았습니다. Python/FFmpeg 설치 상태와 백신 검사를 확인해 주세요.',
    );
  }

  Future<void> dispose() async {
    final process = _process;
    final port = _startedPort;
    _process = null;
    _startedPort = null;
    if (port != null && await _isManagedAutoEditEngine(port)) {
      if (await _stopManagedEngine(port)) {
        return;
      }
    }
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

  Future<bool> _hasRequiredApi(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final healthRequest = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/health'),
      );
      final healthResponse = await healthRequest.close();
      final healthBody = await healthResponse.transform(utf8.decoder).join();
      if (healthResponse.statusCode != 200 ||
          !_healthHasRequiredFeatures(healthBody)) {
        return false;
      }

      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/openapi.json'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return response.statusCode == 200 &&
          body.contains('/api/jobs/probe-local');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  bool _healthHasRequiredFeatures(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }
      final features = decoded['features'];
      final previewProxySeconds = decoded['preview_proxy_seconds'];
      if (features is! List ||
          previewProxySeconds is! num ||
          previewProxySeconds > 8) {
        return false;
      }
      final featureSet = features.map((item) => '$item').toSet();
      return featureSet.contains('broadcast_audio_a1_a2_v2') &&
          featureSet.contains('fast_proxy_preview_v3') &&
          featureSet.contains('safe_storage_cleanup_v1') &&
          featureSet.contains('cancellable_jobs_v1') &&
          featureSet.contains('timeline_30p_ndf');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isManagedAutoEditEngine(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/health'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        return false;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> ||
          decoded['app'] != 'AI Highlight Editor') {
        return false;
      }
      final features = decoded['features'];
      if (features is! List) {
        return false;
      }
      final featureSet = features.map((item) => '$item').toSet();
      return featureSet.contains('local_import') &&
          featureSet.contains('local_probe');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _stopManagedEngine(int port) async {
    final scriptPath = _findWorkspaceScript('stop-desktop-engine.ps1');
    if (scriptPath == null) {
      return false;
    }
    try {
      await Process.run('powershell.exe', [
        '-NoProfile',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
        '-Port',
        '$port',
      ]).timeout(const Duration(seconds: 15));
      for (var attempt = 0; attempt < 20; attempt++) {
        if (!await _isHealthy(port)) {
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String? _findEngineScript() {
    return _findWorkspaceScript('start-desktop-engine.ps1');
  }

  String? _findWorkspaceScript(String scriptName) {
    final names = <String>[
      'scripts${Platform.pathSeparator}$scriptName',
      '..${Platform.pathSeparator}scripts${Platform.pathSeparator}$scriptName',
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
