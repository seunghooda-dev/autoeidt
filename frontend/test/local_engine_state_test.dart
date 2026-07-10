import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/services/local_engine_service.dart';
import 'package:highlight_editor_app/state/editor_controller.dart';

void main() {
  test(
    'engine startup exceptions leave a recoverable unavailable state',
    () async {
      final controller = EditorController(
        engineService: _ThrowingEngineService(),
        autoStartEngine: false,
      );

      await controller.ensureLocalEngine();

      expect(controller.engineState.isStarting, isFalse);
      expect(controller.engineState.isRunning, isFalse);
      expect(controller.engineState.status, 'unavailable');
      expect(controller.engineState.message, contains('startup failed'));
      controller.dispose();
    },
  );
}

class _ThrowingEngineService extends LocalEngineService {
  @override
  Future<LocalEngineState> ensureRunning({int port = 8000}) {
    throw StateError('startup failed');
  }

  @override
  Future<void> dispose() async {}
}
