import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/highlight_segment.dart';
import '../models/job_models.dart';
import '../services/api_client.dart';
import '../services/local_engine_service.dart';

class EditorController extends ChangeNotifier {
  EditorController({
    ApiClient? apiClient,
    LocalEngineService? engineService,
    bool autoStartEngine = true,
  }) : _apiClient = apiClient ?? ApiClient(),
       _engineService = engineService ?? LocalEngineService() {
    if (autoStartEngine) {
      unawaited(ensureLocalEngine());
    }
  }

  final ApiClient _apiClient;
  final LocalEngineService _engineService;
  Timer? _pollTimer;

  LocalEngineState engineState = LocalEngineState.idle();
  PlatformFile? selectedFile;
  String? jobId;
  JobStatusResponse? job;
  double uploadProgress = 0;
  bool isUploading = false;
  bool isRendering = false;
  String? errorMessage;
  double duration = 0;
  List<HighlightSegment> segments = [];
  List<TranscriptSegment> transcript = [];
  String? renderUrl;
  int? selectedSegmentOrder;
  double? markIn;
  double? markOut;
  VideoPlayerController? videoController;
  double _lastNotifiedPosition = -1;
  bool? _lastNotifiedPlaying;

  bool get hasFile => selectedFile != null;
  bool get hasTimeline => duration > 0 && jobId != null;
  bool get canStartUpload =>
      hasFile && !isUploading && job?.status != 'processing';
  bool get canRender =>
      hasTimeline &&
      segments.isNotEmpty &&
      !isRendering &&
      job?.status != 'processing' &&
      job?.status != 'rendering';
  bool get hasValidMarks =>
      markIn != null && markOut != null && markOut! - markIn! >= 0.5;
  double get currentPositionSeconds {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      return 0;
    }
    return controller.value.position.inMilliseconds / 1000;
  }

  HighlightSegment? get selectedSegment {
    final order = selectedSegmentOrder;
    if (order == null) {
      return null;
    }
    for (final segment in segments) {
      if (segment.order == order) {
        return segment;
      }
    }
    return null;
  }

  String get statusText {
    if (errorMessage != null) {
      return errorMessage!;
    }
    if (job != null && job!.message.isNotEmpty) {
      return job!.message;
    }
    if (selectedFile != null) {
      return selectedFile!.name;
    }
    return '영상 파일을 선택해 주세요';
  }

  Future<void> ensureLocalEngine() async {
    engineState = const LocalEngineState(
      status: 'starting',
      message: '로컬 편집 엔진 확인 중',
      isStarting: true,
    );
    notifyListeners();

    engineState = await _engineService.ensureRunning();
    notifyListeners();
  }

  Future<void> pickVideo() async {
    errorMessage = null;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: kIsWeb,
      withReadStream: !kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    selectedFile = result.files.single;
    jobId = null;
    job = null;
    duration = 0;
    segments = [];
    transcript = [];
    renderUrl = null;
    selectedSegmentOrder = null;
    markIn = null;
    markOut = null;
    uploadProgress = 0;
    await _disposeVideoController();
    notifyListeners();
  }

  Future<void> startUpload() async {
    final file = selectedFile;
    if (file == null) {
      return;
    }

    isUploading = true;
    errorMessage = null;
    uploadProgress = 0;
    notifyListeners();

    try {
      final response = await _apiClient.uploadVideo(
        file,
        onSendProgress: (sent, total) {
          if (total <= 0) {
            return;
          }
          uploadProgress = sent / total;
          notifyListeners();
        },
      );
      jobId = response.jobId;
      isUploading = false;
      try {
        await _initializePreview(response.jobId);
      } catch (_) {
        await _disposeVideoController();
      }
      _startPolling();
    } catch (error) {
      isUploading = false;
      errorMessage = '업로드 실패: $error';
    }
    notifyListeners();
  }

  Future<void> requestRender() async {
    final id = jobId;
    if (id == null || segments.isEmpty) {
      return;
    }
    isRendering = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _apiClient.requestRender(id, segments);
      _startPolling();
    } catch (error) {
      isRendering = false;
      errorMessage = '렌더링 요청 실패: $error';
    }
    notifyListeners();
  }

  void updateSegment(HighlightSegment updated) {
    segments = [
      for (final segment in segments)
        if (segment.order == updated.order) updated else segment,
    ];

    segments = [
      for (var index = 0; index < segments.length; index++)
        segments[index].copyWith(order: index + 1),
    ];
    selectedSegmentOrder = updated.order.clamp(1, segments.length).toInt();
    renderUrl = null;
    notifyListeners();
  }

  void selectSegment(int order) {
    if (segments.any((segment) => segment.order == order)) {
      selectedSegmentOrder = order;
      notifyListeners();
    }
  }

  void setMarkInFromPlayhead() {
    markIn = _snapToTenth(_clampTime(currentPositionSeconds));
    if (markOut != null && markOut! <= markIn!) {
      markOut = null;
    }
    notifyListeners();
  }

  void setMarkOutFromPlayhead() {
    markOut = _snapToTenth(_clampTime(currentPositionSeconds));
    if (markIn != null && markOut! <= markIn!) {
      markIn = null;
    }
    notifyListeners();
  }

  void clearMarks() {
    markIn = null;
    markOut = null;
    notifyListeners();
  }

  void addMarkedSegment() {
    if (!hasValidMarks) {
      return;
    }
    final start = markIn!;
    final end = markOut!;
    final nextOrder = segments.length + 1;
    final segment = HighlightSegment(
      order: nextOrder,
      start: start,
      end: end,
      reason: '수동 In/Out 지정 구간',
      script: _scriptPreviewFor(start, end),
      source: 'manual',
    );
    segments = [...segments, segment];
    selectedSegmentOrder = nextOrder;
    renderUrl = null;
    notifyListeners();
  }

  void applyMarksToSelectedSegment() {
    final selected = selectedSegment;
    if (selected == null || !hasValidMarks) {
      return;
    }
    updateSegment(
      selected.copyWith(
        start: markIn!,
        end: markOut!,
        script: _scriptPreviewFor(markIn!, markOut!),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void deleteSelectedSegment() {
    final order = selectedSegmentOrder;
    if (order == null) {
      return;
    }
    final filtered = [
      for (final segment in segments)
        if (segment.order != order) segment,
    ];
    segments = [
      for (var index = 0; index < filtered.length; index++)
        filtered[index].copyWith(order: index + 1),
    ];
    selectedSegmentOrder = segments.isEmpty
        ? null
        : order.clamp(1, segments.length).toInt();
    renderUrl = null;
    notifyListeners();
  }

  Future<void> seekTo(double seconds, {bool autoplay = true}) async {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final clamped = _clampTime(seconds);
    await controller.seekTo(Duration(milliseconds: (clamped * 1000).round()));
    if (autoplay) {
      await controller.play();
    }
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
    _pollOnce();
  }

  Future<void> _pollOnce() async {
    final id = jobId;
    if (id == null) {
      return;
    }

    try {
      final latest = await _apiClient.getJob(id);
      job = latest;
      if (latest.duration != null) {
        duration = latest.duration!;
      }

      if (latest.status == 'completed') {
        await _loadTimeline(id);
        _pollTimer?.cancel();
      } else if (latest.status == 'rendered') {
        await _loadTimeline(id);
        renderUrl = latest.renderUrl == null
            ? null
            : _apiClient.absoluteUrl(latest.renderUrl!);
        isRendering = false;
        _pollTimer?.cancel();
      } else if (latest.status == 'failed') {
        errorMessage = latest.error ?? latest.message;
        isRendering = false;
        _pollTimer?.cancel();
      } else if (latest.status == 'rendering') {
        isRendering = true;
      }
    } catch (error) {
      errorMessage = '상태 조회 실패: $error';
      _pollTimer?.cancel();
    }
    notifyListeners();
  }

  Future<void> _loadTimeline(String id) async {
    final timeline = await _apiClient.getTimeline(id);
    duration = timeline.duration;
    segments = timeline.segments;
    transcript = timeline.transcript;
    if (segments.isNotEmpty &&
        !segments.any((segment) => segment.order == selectedSegmentOrder)) {
      selectedSegmentOrder = segments.first.order;
    }
  }

  Future<void> _initializePreview(String id) async {
    await _disposeVideoController();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(_apiClient.sourceUrl(id)),
    );
    videoController = controller;
    await controller.initialize();
    final previewDuration = controller.value.duration.inMilliseconds / 1000;
    if (previewDuration > 0 && duration == 0) {
      duration = previewDuration;
    }
    controller.addListener(_handleVideoTick);
  }

  Future<void> _disposeVideoController() async {
    final current = videoController;
    videoController = null;
    if (current != null) {
      current.removeListener(_handleVideoTick);
      await current.dispose();
    }
  }

  void _handleVideoTick() {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final seconds = currentPositionSeconds;
    final isPlaying = controller.value.isPlaying;
    if ((seconds - _lastNotifiedPosition).abs() >= 0.1 ||
        isPlaying != _lastNotifiedPlaying) {
      _lastNotifiedPosition = seconds;
      _lastNotifiedPlaying = isPlaying;
      notifyListeners();
    }
  }

  String _scriptPreviewFor(double start, double end) {
    for (final item in transcript) {
      if (start < item.end && end > item.start) {
        return item.text;
      }
    }
    return '';
  }

  double _clampTime(double value) => value.clamp(0.0, duration).toDouble();

  double _snapToTenth(double value) => (value * 10).round() / 10;

  @override
  void dispose() {
    _pollTimer?.cancel();
    videoController?.dispose();
    unawaited(_engineService.dispose());
    super.dispose();
  }
}
