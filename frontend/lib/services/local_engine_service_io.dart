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
  Future<LocalEngineState>? _ensureFuture;
  int? _processExitCode;
  String _processOutputTail = '';
  static const Duration _localRequestTimeout = Duration(seconds: 3);

  Future<LocalEngineState> ensureRunning({int port = 8000}) {
    final active = _ensureFuture;
    if (active != null) {
      return active;
    }
    late final Future<LocalEngineState> pending;
    pending = _ensureRunning(port).whenComplete(() {
      if (identical(_ensureFuture, pending)) {
        _ensureFuture = null;
      }
    });
    _ensureFuture = pending;
    return pending;
  }

  Future<LocalEngineState> _ensureRunning(int port) async {
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
      final workspaceRoot = File(scriptPath).parent.parent.path;
      try {
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
          '-WorkspaceRoot',
          workspaceRoot,
        ], mode: ProcessStartMode.normal);
      } on ProcessException catch (error) {
        return LocalEngineState.unavailable(
          '로컬 편집 엔진 프로세스를 시작하지 못했습니다: ${error.message}',
        );
      }
      _startedPort = port;
      _processExitCode = null;
      _processOutputTail = '';
      final startedProcess = _process!;
      startedProcess.stdout
          .transform(utf8.decoder)
          .listen(_rememberProcessOutput);
      startedProcess.stderr
          .transform(utf8.decoder)
          .listen(_rememberProcessOutput);
      unawaited(
        startedProcess.exitCode.then((code) {
          if (identical(_process, startedProcess)) {
            _processExitCode = code;
          }
        }),
      );
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
      final exitCode = _processExitCode;
      if (exitCode != null) {
        final detail = _processOutputTail.trim();
        _process = null;
        _startedPort = null;
        return LocalEngineState.unavailable(
          '로컬 편집 엔진이 시작 중 종료되었습니다 (종료 코드 $exitCode).'
          '${detail.isEmpty ? '' : ' $detail'}',
        );
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
    _processExitCode = null;
    _processOutputTail = '';
    if (port != null && await _isManagedAutoEditEngine(port)) {
      if (await _stopManagedEngine(port)) {
        return;
      }
    }
    if (process != null && Platform.isWindows) {
      try {
        await Process.run('taskkill.exe', [
          '/PID',
          '${process.pid}',
          '/T',
          '/F',
        ]).timeout(const Duration(seconds: 10));
        return;
      } catch (_) {
        // Fall through to the direct process kill.
      }
    }
    process?.kill();
  }

  Future<bool> _isHealthy(int port) async {
    final response = await _getLocalText(port, '/health');
    return response?.statusCode == 200;
  }

  Future<bool> _hasRequiredApi(int port) async {
    final health = await _getLocalText(port, '/health');
    if (health == null ||
        health.statusCode != 200 ||
        !_healthHasRequiredFeatures(health.body)) {
      return false;
    }
    final openApi = await _getLocalText(port, '/openapi.json');
    return openApi?.statusCode == 200 &&
        openApi!.body.contains('/api/jobs/probe-local');
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
          featureSet.contains('compatibility_preview_v1') &&
          featureSet.contains('local_preview_file_v1') &&
          featureSet.contains('safe_storage_cleanup_v1') &&
          featureSet.contains('cancellable_jobs_v1') &&
          featureSet.contains('recent_jobs_v1') &&
          featureSet.contains('timeline_30p_ndf') &&
          featureSet.contains('v2_overlay_render_v1') &&
          featureSet.contains('v2_overlay_program_preview_v1') &&
          featureSet.contains('overlay_audio_a3_v1') &&
          featureSet.contains('dynamic_tracks_v4_a8_v1') &&
          featureSet.contains('standalone_audio_clips_v1') &&
          featureSet.contains('per_track_controls_v1') &&
          featureSet.contains('audio_track_solo_v1') &&
          featureSet.contains('lossless_multitrack_project_v1') &&
          featureSet.contains('audio_gain_keyframes_v1');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isManagedAutoEditEngine(int port) async {
    final response = await _getLocalText(port, '/health');
    if (response == null || response.statusCode != 200) {
      return false;
    }
    try {
      final decoded = jsonDecode(response.body);
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
    }
  }

  Future<_LocalHttpResponse?> _getLocalText(int port, String path) async {
    final client = HttpClient()..connectionTimeout = _localRequestTimeout;
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port$path'),
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        return _LocalHttpResponse(response.statusCode, body);
      })().timeout(_localRequestTimeout);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _rememberProcessOutput(String chunk) {
    final value = chunk.trim();
    if (value.isEmpty) {
      return;
    }
    _processOutputTail = '$_processOutputTail\n$value'.trim();
    if (_processOutputTail.length > 900) {
      _processOutputTail = _processOutputTail.substring(
        _processOutputTail.length - 900,
      );
    }
  }

  Future<bool> _stopManagedEngine(int port) async {
    final scriptPath = _findWorkspaceScript('stop-desktop-engine.ps1');
    if (scriptPath == null) {
      return false;
    }
    try {
      final workspaceRoot = File(scriptPath).parent.parent.path;
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
        '-WorkspaceRoot',
        workspaceRoot,
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

    String? packagedFallback;
    final visited = <String>{};
    for (final root in roots) {
      Directory? current = root;
      for (var depth = 0; depth < 8 && current != null; depth++) {
        for (final name in names) {
          final candidate = File(
            '${current.path}${Platform.pathSeparator}$name',
          );
          if (!candidate.existsSync()) {
            continue;
          }
          final resolved = candidate.resolveSymbolicLinksSync();
          if (!visited.add(resolved)) {
            continue;
          }
          final workspaceRoot = File(resolved).parent.parent;
          final sourceVenv = File(
            '${workspaceRoot.path}${Platform.pathSeparator}backend'
            '${Platform.pathSeparator}.venv${Platform.pathSeparator}Scripts'
            '${Platform.pathSeparator}python.exe',
          );
          if (Directory(
                '${workspaceRoot.path}${Platform.pathSeparator}.git',
              ).existsSync() &&
              sourceVenv.existsSync()) {
            return resolved;
          }
          packagedFallback ??= resolved;
        }
        current = current.parent.path == current.path ? null : current.parent;
      }
    }
    return packagedFallback;
  }
}

class _LocalHttpResponse {
  const _LocalHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
