import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/highlight_segment.dart';
import '../models/job_models.dart';
import '../services/api_client.dart';

class EditorController extends ChangeNotifier {
  EditorController({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;
  Timer? _pollTimer;

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
  VideoPlayerController? videoController;

  bool get hasFile => selectedFile != null;
  bool get hasTimeline => duration > 0 && segments.isNotEmpty;
  bool get canStartUpload => hasFile && !isUploading && job?.status != 'processing';
  bool get canRender =>
      hasTimeline && !isRendering && job?.status != 'processing' && job?.status != 'rendering';

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
    ]..sort((a, b) => a.start.compareTo(b.start));

    segments = [
      for (var index = 0; index < segments.length; index++)
        segments[index].copyWith(order: index + 1),
    ];
    notifyListeners();
  }

  Future<void> seekTo(double seconds) async {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    await controller.seekTo(Duration(milliseconds: (seconds * 1000).round()));
    await controller.play();
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
        renderUrl = latest.renderUrl == null ? null : _apiClient.absoluteUrl(latest.renderUrl!);
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
  }

  Future<void> _initializePreview(String id) async {
    await _disposeVideoController();
    final controller = VideoPlayerController.networkUrl(Uri.parse(_apiClient.sourceUrl(id)));
    videoController = controller;
    await controller.initialize();
  }

  Future<void> _disposeVideoController() async {
    final current = videoController;
    videoController = null;
    if (current != null) {
      await current.dispose();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    videoController?.dispose();
    super.dispose();
  }
}
