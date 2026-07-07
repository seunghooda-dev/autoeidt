import 'dart:async';
import 'dart:convert';

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
  List<CaptionSegment> captions = [];
  List<double> waveform = [];
  String? renderUrl;
  int? selectedSegmentOrder;
  double? markIn;
  double? markOut;
  bool includeCaptions = true;
  String exportAspectRatio = '16:9';
  double timelineZoom = 1.0;
  String projectName = 'AutoEdit Project';
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

  ProjectState get projectState {
    return ProjectState(
      name: projectName,
      jobId: jobId,
      originalFilename: job?.originalFilename ?? selectedFile?.name,
      duration: duration,
      segments: segments,
      captions: captions,
      waveform: waveform,
    );
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
    captions = [];
    waveform = [];
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
    await _requestRender(
      aspectRatio: exportAspectRatio,
      outputName: exportAspectRatio == '9:16'
          ? 'youtube_shorts_highlights.mp4'
          : 'youtube_highlights.mp4',
    );
  }

  Future<void> requestShortsRender() async {
    await _requestRender(
      aspectRatio: '9:16',
      outputName: 'youtube_shorts_highlights.mp4',
    );
  }

  Future<void> _requestRender({
    required String aspectRatio,
    required String outputName,
  }) async {
    final id = jobId;
    if (id == null || segments.isEmpty) {
      return;
    }
    isRendering = true;
    errorMessage = null;
    notifyListeners();

    try {
      exportAspectRatio = aspectRatio;
      await saveProjectToBackend(silent: true);
      await _apiClient.requestRender(
        id,
        segments,
        captions: captions,
        aspectRatio: aspectRatio,
        includeCaptions: includeCaptions,
        outputName: outputName,
      );
      _startPolling();
    } catch (error) {
      isRendering = false;
      errorMessage = '렌더링 요청 실패: $error';
    }
    notifyListeners();
  }

  Future<void> saveProjectToBackend({bool silent = false}) async {
    final id = jobId;
    if (id == null) {
      return;
    }
    try {
      final project = await _apiClient.saveProject(id, projectState);
      _applyProject(project, keepJob: true);
    } catch (error) {
      if (!silent) {
        errorMessage = '프로젝트 저장 실패: $error';
      }
    }
    if (!silent) {
      notifyListeners();
    }
  }

  Future<void> exportProjectFile() async {
    final bytes = Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'version': 1, ...projectState.toJson()}),
      ),
    );
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: '프로젝트 저장',
        fileName: '${_safeProjectFileName()}.autoedit.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
    } catch (error) {
      errorMessage = '프로젝트 파일 저장 실패: $error';
      notifyListeners();
    }
  }

  Future<void> importProjectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '프로젝트 불러오기',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw StateError('프로젝트 파일을 읽을 수 없습니다.');
      }
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final project = ProjectState.fromJson(payload);
      _applyProject(project, keepJob: false);
      if (jobId != null) {
        try {
          await _initializePreview(jobId!);
        } catch (_) {
          await _disposeVideoController();
        }
      }
    } catch (error) {
      errorMessage = '프로젝트 불러오기 실패: $error';
    }
    notifyListeners();
  }

  void updateSegment(HighlightSegment updated) {
    final normalized = _normalizeSegmentAudio(updated);
    segments = [
      for (final segment in segments)
        if (segment.order == normalized.order) normalized else segment,
    ];

    segments = [
      for (var index = 0; index < segments.length; index++)
        segments[index].copyWith(order: index + 1),
    ];
    selectedSegmentOrder = normalized.order.clamp(1, segments.length).toInt();
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

  void detachAudioForSelectedSegment() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioLinked: false,
        audioStart: selected.effectiveAudioStart,
        audioEnd: selected.effectiveAudioEnd,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void relinkAudioForSelectedSegment() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioLinked: true,
        audioStart: selected.start,
        audioEnd: selected.end,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void toggleSelectedAudioMute() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioMuted: !selected.audioMuted,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedAudioVolume(double value) {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioVolume: value.clamp(0.0, 2.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void nudgeSelectedAudio(double delta) {
    final selected = selectedSegment;
    if (selected == null || selected.audioLinked) {
      return;
    }
    final audioDuration = selected.audioDuration;
    if (audioDuration <= 0) {
      return;
    }
    var start = _snapToTenth(selected.effectiveAudioStart + delta);
    var end = _snapToTenth(selected.effectiveAudioEnd + delta);
    if (start < 0) {
      end -= start;
      start = 0;
    }
    if (duration > 0 && end > duration) {
      final overshoot = end - duration;
      start = (start - overshoot).clamp(0.0, duration).toDouble();
      end = duration;
    }
    updateSegment(
      selected.copyWith(
        audioStart: start,
        audioEnd: end,
        audioLinked: false,
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

  void splitSelectedAtPlayhead() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    final splitAt = _snapToTenth(_clampTime(currentPositionSeconds));
    if (splitAt <= selected.start + 0.5 || splitAt >= selected.end - 0.5) {
      return;
    }
    final output = <HighlightSegment>[];
    for (final segment in segments) {
      if (segment.order != selected.order) {
        output.add(segment);
        continue;
      }
      output.add(_splitSegment(segment, splitAt, firstHalf: true));
      output.add(_splitSegment(segment, splitAt, firstHalf: false));
    }
    segments = _reorderSegments(output);
    selectedSegmentOrder = (selected.order + 1)
        .clamp(1, segments.length)
        .toInt();
    renderUrl = null;
    notifyListeners();
  }

  void moveSelectedSegment(int delta) {
    final order = selectedSegmentOrder;
    if (order == null) {
      return;
    }
    final index = segments.indexWhere((segment) => segment.order == order);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= segments.length) {
      return;
    }
    final editable = [...segments];
    final item = editable.removeAt(index);
    editable.insert(target, item);
    segments = _reorderSegments(editable);
    selectedSegmentOrder = target + 1;
    renderUrl = null;
    notifyListeners();
  }

  void updateCaption(CaptionSegment updated) {
    captions = [
      for (final caption in captions)
        if (caption.order == updated.order) updated else caption,
    ];
    renderUrl = null;
    notifyListeners();
  }

  void toggleCaption(CaptionSegment caption) {
    updateCaption(caption.copyWith(enabled: !caption.enabled));
  }

  void setIncludeCaptions(bool value) {
    includeCaptions = value;
    renderUrl = null;
    notifyListeners();
  }

  void setExportAspectRatio(String value) {
    exportAspectRatio = value;
    renderUrl = null;
    notifyListeners();
  }

  void zoomTimeline(double delta) {
    timelineZoom = (timelineZoom + delta).clamp(1.0, 6.0).toDouble();
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
    segments = _reorderSegments(timeline.segments);
    transcript = timeline.transcript;
    captions = timeline.captions;
    waveform = timeline.waveform;
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

  double _clampProjectTime(double value) {
    if (duration <= 0) {
      return value < 0 ? 0 : value;
    }
    return value.clamp(0.0, duration).toDouble();
  }

  HighlightSegment _normalizeSegmentAudio(HighlightSegment segment) {
    final volume = segment.audioVolume.clamp(0.0, 2.0).toDouble();
    if (segment.audioLinked) {
      return segment.copyWith(
        audioStart: segment.start,
        audioEnd: segment.end,
        audioVolume: volume,
      );
    }

    var audioStart = _snapToTenth(
      _clampProjectTime(segment.effectiveAudioStart),
    );
    var audioEnd = _snapToTenth(_clampProjectTime(segment.effectiveAudioEnd));
    if (audioEnd <= audioStart) {
      audioStart = segment.start;
      audioEnd = segment.end;
    }
    return segment.copyWith(
      audioStart: audioStart,
      audioEnd: audioEnd,
      audioVolume: volume,
    );
  }

  HighlightSegment _splitSegment(
    HighlightSegment segment,
    double splitAt, {
    required bool firstHalf,
  }) {
    final source = segment.source == 'ai' ? 'ai+manual' : segment.source;
    final reasonSuffix = firstHalf ? 'split A' : 'split B';
    if (segment.audioLinked) {
      final start = firstHalf ? segment.start : splitAt;
      final end = firstHalf ? splitAt : segment.end;
      return _normalizeSegmentAudio(
        segment.copyWith(
          start: start,
          end: end,
          audioStart: start,
          audioEnd: end,
          reason: '${segment.reason} / $reasonSuffix',
          source: source,
        ),
      );
    }

    final videoDuration = segment.duration;
    final audioDuration = segment.audioDuration;
    final splitRatio = videoDuration <= 0
        ? 0.5
        : ((splitAt - segment.start) / videoDuration).clamp(0.0, 1.0);
    final audioSplit = _snapToTenth(
      segment.effectiveAudioStart + audioDuration * splitRatio,
    );
    return _normalizeSegmentAudio(
      segment.copyWith(
        start: firstHalf ? segment.start : splitAt,
        end: firstHalf ? splitAt : segment.end,
        audioStart: firstHalf ? segment.effectiveAudioStart : audioSplit,
        audioEnd: firstHalf ? audioSplit : segment.effectiveAudioEnd,
        audioLinked: false,
        reason: '${segment.reason} / $reasonSuffix',
        source: source,
      ),
    );
  }

  List<HighlightSegment> _reorderSegments(List<HighlightSegment> input) {
    return [
      for (var index = 0; index < input.length; index++)
        _normalizeSegmentAudio(input[index].copyWith(order: index + 1)),
    ];
  }

  void _applyProject(ProjectState project, {required bool keepJob}) {
    projectName = project.name;
    if (!keepJob && project.jobId != null) {
      jobId = project.jobId;
    }
    duration = project.duration;
    segments = _reorderSegments(project.segments);
    captions = [
      for (var index = 0; index < project.captions.length; index++)
        project.captions[index].copyWith(order: index + 1),
    ];
    waveform = project.waveform;
    selectedSegmentOrder = segments.isEmpty ? null : segments.first.order;
    renderUrl = null;
  }

  String _safeProjectFileName() {
    final base = projectName.trim().isEmpty ? 'autoedit_project' : projectName;
    return base.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    videoController?.dispose();
    unawaited(_engineService.dispose());
    super.dispose();
  }
}
