class LocalEngineState {
  const LocalEngineState({
    required this.status,
    required this.message,
    this.isRunning = false,
    this.isStarting = false,
    this.canStart = false,
  });

  final String status;
  final String message;
  final bool isRunning;
  final bool isStarting;
  final bool canStart;

  factory LocalEngineState.idle() {
    return const LocalEngineState(
      status: 'browser',
      message: '브라우저 모드는 실행 중인 API 서버에 연결합니다.',
    );
  }
}

class LocalEngineService {
  Future<LocalEngineState> ensureRunning({int port = 8000}) async {
    return LocalEngineState.idle();
  }

  Future<void> dispose() async {}
}
