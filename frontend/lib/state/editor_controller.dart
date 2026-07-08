import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/highlight_segment.dart';
import '../models/job_models.dart';
import '../services/api_client.dart';
import '../services/local_engine_service.dart';
import '../utils/timecode.dart';

class EditorController extends ChangeNotifier {
  EditorController({
    ApiClient? apiClient,
    LocalEngineService? engineService,
    bool autoStartEngine = true,
  }) : _apiClient = apiClient ?? ApiClient(),
       _engineService = engineService ?? LocalEngineService() {
    if (_demoMode) {
      _loadDemoProject();
    } else if (autoStartEngine) {
      unawaited(ensureLocalEngine());
    }
  }

  final ApiClient _apiClient;
  final LocalEngineService _engineService;
  Timer? _pollTimer;
  Timer? _stylePollTimer;
  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];

  LocalEngineState engineState = LocalEngineState.idle();
  PlatformFile? selectedFile;
  MediaProbeInfo? selectedMediaProbe;
  List<PlatformFile> referenceFiles = [];
  String? jobId;
  JobStatusResponse? job;
  StyleProfile? activeStyleProfile;
  StyleProfile? trainingStyleProfile;
  double uploadProgress = 0;
  double styleUploadProgress = 0;
  bool isUploading = false;
  bool isTrainingStyle = false;
  bool isRendering = false;
  String? errorMessage;
  double duration = 0;
  List<HighlightSegment> segments = [];
  List<TranscriptSegment> transcript = [];
  List<CaptionSegment> captions = [];
  List<double> waveform = [];
  List<TimelineMarker> timelineMarkers = [];
  String? renderUrl;
  int? selectedSegmentOrder;
  double? markIn;
  double? markOut;
  bool includeCaptions = true;
  String captionStylePreset = 'news';
  String exportAspectRatio = '16:9';
  double timelineZoom = 1.0;
  String timelineTool = 'selection';
  bool videoTrackLocked = false;
  bool audioTrackLocked = false;
  String projectName = 'AutoEdit Project';
  List<HighlightSegment> comparisonDefaultSegments = [];
  List<HighlightSegment> comparisonReferenceSegments = [];
  String comparisonSelection = 'current';
  List<ShortsCandidate> shortsCandidates = [];
  int? selectedShortsId;
  VideoPlayerController? videoController;
  double _lastNotifiedPosition = -1;
  bool? _lastNotifiedPlaying;
  int _previewRevision = 0;
  bool isPreparingPreview = false;
  bool isProbingMedia = false;
  bool _previewUsesProxy = false;
  double _previewSourceStartSeconds = 0;
  double? _previewSourceDurationSeconds;
  double _manualPlayheadSeconds = 0;
  static const bool _demoMode = bool.fromEnvironment('AUTOEDIT_DEMO');
  static const List<String> supportedVideoExtensions = [
    'mp4',
    'mov',
    'm4v',
    'mkv',
    'webm',
    'avi',
    'wmv',
    'asf',
    'mpg',
    'mpeg',
    'ts',
    'm2ts',
    'mts',
    'flv',
    'mxf',
  ];
  static final RegExp _fillerPattern = RegExp(
    r'(^|\s)(음+|어+|아+|그니까|그러니까|뭐랄까|약간|이제)(\s|$)|you know|um+|uh+',
    caseSensitive: false,
  );
  static final RegExp _riskPattern = RegExp(
    r'루머|카더라|추정|추측|아마도|미확인|확인되지|일각에서는|떠돌|rumor|unconfirmed|allegedly|speculation',
    caseSensitive: false,
  );

  bool get hasFile => selectedFile != null;
  bool get hasTimeline => duration > 0 && segments.isNotEmpty;
  bool get hasTimelineSource => hasTimeline || hasFile;
  double get timelineSourceDuration {
    if (duration > 0) {
      return duration;
    }
    final probeDuration = selectedMediaProbe?.duration ?? 0;
    return probeDuration > 0 ? probeDuration : 0;
  }

  bool get canStartUpload =>
      hasFile &&
      !isUploading &&
      !isProbingMedia &&
      selectedMediaProbe?.canAnalyze != false &&
      job?.status != 'processing';
  bool get hasReadyStyle => activeStyleProfile?.isReady ?? false;
  bool get hasComparisonVariants =>
      comparisonDefaultSegments.isNotEmpty &&
      comparisonReferenceSegments.isNotEmpty;
  bool get hasShortsCandidates => shortsCandidates.isNotEmpty;
  bool get hasTimelineMarkers => timelineMarkers.isNotEmpty;
  bool get canJumpToNextTimelineMarker =>
      _nextTimelineMarkerFrom(currentPositionSeconds) != null;
  bool get canJumpToPreviousTimelineMarker =>
      _previousTimelineMarkerFrom(currentPositionSeconds) != null;
  List<BatchRenderItemResult> get renderOutputs {
    final currentRenderUrl = renderUrl;
    if (currentRenderUrl == null || currentRenderUrl.isEmpty) {
      return const [];
    }

    final batchItems = job?.batchRenderItems ?? const [];
    if (batchItems.isNotEmpty) {
      return [
        for (final item in batchItems)
          if (item.url.isNotEmpty)
            BatchRenderItemResult(
              label: item.label,
              outputName: item.outputName.isEmpty
                  ? _outputNameFromUrl(item.url)
                  : item.outputName,
              url: _apiClient.absoluteUrl(item.url),
              path: item.path,
              durationSeconds: item.durationSeconds,
              sizeBytes: item.sizeBytes,
              warnings: item.warnings,
            ),
      ];
    }

    return [
      BatchRenderItemResult(
        label: 'Export',
        outputName: _outputNameFromUrl(currentRenderUrl),
        url: currentRenderUrl,
        path: job?.renderPath ?? '',
        durationSeconds: job?.renderDurationSeconds ?? 0,
        sizeBytes: job?.renderSizeBytes ?? 0,
        warnings: job?.renderWarnings ?? const [],
      ),
    ];
  }

  ShortsCandidate? get selectedShortsCandidate {
    final id = selectedShortsId;
    if (id == null) {
      return null;
    }
    for (final candidate in shortsCandidates) {
      if (candidate.id == id) {
        return candidate;
      }
    }
    return null;
  }

  String _outputNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segments = uri?.pathSegments ?? const [];
    if (segments.isEmpty) {
      return 'render.mp4';
    }
    return Uri.decodeComponent(segments.last);
  }

  int get selectedShortsCount =>
      shortsCandidates.where((candidate) => candidate.selected).length;
  int get selectedShortsRenderBlockCount =>
      _selectedShortsRenderSafetyCount(EditorialCheckStatus.block);
  int get selectedShortsRenderWarnCount =>
      _selectedShortsRenderSafetyCount(EditorialCheckStatus.warn);
  bool get hasSelectedShortsRenderSafetyIssues =>
      selectedShortsRenderBlockCount > 0 || selectedShortsRenderWarnCount > 0;
  CaptionRenderStyle get captionRenderStyle =>
      CaptionRenderStyle.preset(captionStylePreset);
  String get styleStatusText {
    final profile = trainingStyleProfile ?? activeStyleProfile;
    if (profile == null) {
      return 'No reference';
    }
    if (profile.status == 'failed') {
      return profile.error ?? 'Reference failed';
    }
    if (profile.isReady) {
      return '${profile.pace} · ${profile.averageCutSeconds.toStringAsFixed(1)}s cut';
    }
    return profile.message.isEmpty ? 'Reference training' : profile.message;
  }

  bool get canRender =>
      jobId != null &&
      hasTimeline &&
      segments.isNotEmpty &&
      !hasManualRenderSafetyBlock &&
      !isRendering &&
      job?.status != 'processing' &&
      job?.status != 'rendering';
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isRazorTool => timelineTool == 'razor';
  String get timelineToolLabel => isRazorTool ? 'Razor C' : 'Selection V';
  bool get allAudioMuted =>
      segments.isNotEmpty &&
      segments.every(
        (segment) => segment.audioMuted || !segment.hasActiveAudioChannel,
      );
  bool get hasValidMarks =>
      markIn != null &&
      markOut != null &&
      markOut! - markIn! >= timecodeFrameDurationSeconds;
  double get currentPositionSeconds {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      return _manualPlayheadSeconds;
    }
    return _previewSourceStartSeconds +
        controller.value.position.inMilliseconds / 1000;
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

  double get outputDurationSeconds {
    return segments.fold<double>(
      0,
      (total, segment) => total + segment.outputDuration,
    );
  }

  double get averageClipScore {
    final scored = segments.where((segment) => segment.score > 0).toList();
    if (scored.isEmpty) {
      return 0;
    }
    return scored.fold<double>(0, (total, item) => total + item.score) /
        scored.length;
  }

  int get weakClipCount {
    final average = averageClipScore;
    if (average <= 0) {
      return 0;
    }
    final threshold = _weakScoreThreshold(average);
    return segments
        .where((segment) => segment.score > 0 && segment.score < threshold)
        .length;
  }

  int get fillerCaptionCount {
    return captions
        .where(
          (caption) => caption.enabled && _fillerPattern.hasMatch(caption.text),
        )
        .length;
  }

  int get riskyTextCount {
    final captionCount = captions
        .where(
          (caption) => caption.enabled && _riskPattern.hasMatch(caption.text),
        )
        .length;
    final segmentCount = segments
        .where(
          (segment) =>
              _riskPattern.hasMatch(segment.script) ||
              _riskPattern.hasMatch(segment.reason) ||
              segment.tags.any((tag) => _riskPattern.hasMatch(tag)),
        )
        .length;
    return captionCount + segmentCount;
  }

  int get offlineReviewSegmentCount =>
      segments.where(_isOfflineReviewSegment).length;

  bool get hasOfflineReviewSegments => offlineReviewSegmentCount > 0;

  List<EditorialCheckItem> get editorialChecklist {
    final hasNewsSignals = segments.any(
      (segment) => segment.tags.any(
        (tag) => {'뉴스핵심', '근거', '영향', '대응', '출처확인', '시간축', '발언'}.contains(tag),
      ),
    );
    final hasAttribution = segments.any(
      (segment) =>
          segment.tags.any((tag) => {'근거', '출처확인', '발언'}.contains(tag)),
    );
    final enabledCaptionCount = captions
        .where((caption) => caption.enabled)
        .length;
    final audioReady =
        segments.isNotEmpty &&
        segments
            .where((segment) => !segment.audioMuted)
            .every(
              (segment) => segment.audioNormalize && segment.audioPan == 0,
            );
    final minDurationOk =
        outputDurationSeconds >= 150 && outputDurationSeconds <= 270;

    return [
      EditorialCheckItem(
        label: 'Timeline',
        detail: segments.isEmpty ? '선택된 컷 없음' : '${segments.length} clips',
        status: segments.isEmpty
            ? EditorialCheckStatus.block
            : EditorialCheckStatus.pass,
      ),
      EditorialCheckItem(
        label: 'Runtime',
        detail: '${outputDurationSeconds.round()}s',
        status: minDurationOk
            ? EditorialCheckStatus.pass
            : EditorialCheckStatus.warn,
      ),
      EditorialCheckItem(
        label: 'Risk',
        detail: riskyTextCount == 0
            ? 'No risky wording'
            : '$riskyTextCount flags',
        status: riskyTextCount == 0
            ? EditorialCheckStatus.pass
            : EditorialCheckStatus.block,
      ),
      EditorialCheckItem(
        label: 'Filler',
        detail: fillerCaptionCount == 0
            ? 'Clean'
            : '$fillerCaptionCount captions',
        status: fillerCaptionCount == 0
            ? EditorialCheckStatus.pass
            : EditorialCheckStatus.warn,
      ),
      EditorialCheckItem(
        label: 'Attribution',
        detail: hasNewsSignals
            ? (hasAttribution ? 'Sourced' : 'Needs source')
            : 'Not news',
        status: !hasNewsSignals || hasAttribution
            ? EditorialCheckStatus.pass
            : EditorialCheckStatus.warn,
      ),
      EditorialCheckItem(
        label: 'Audio',
        detail: audioReady ? 'Normalized' : 'Needs mix pass',
        status: audioReady
            ? EditorialCheckStatus.pass
            : EditorialCheckStatus.warn,
      ),
      EditorialCheckItem(
        label: 'Captions',
        detail: includeCaptions ? '$enabledCaptionCount enabled' : 'Off',
        status: includeCaptions && enabledCaptionCount > 0
            ? EditorialCheckStatus.pass
            : EditorialCheckStatus.warn,
      ),
      EditorialCheckItem(
        label: 'Offline review',
        detail: offlineReviewSegmentCount == 0
            ? 'Content analysis'
            : '$offlineReviewSegmentCount clips need review',
        status: offlineReviewSegmentCount == 0
            ? EditorialCheckStatus.pass
            : EditorialCheckStatus.warn,
      ),
    ];
  }

  int get editorialBlockCount => editorialChecklist
      .where((item) => item.status == EditorialCheckStatus.block)
      .length;

  int get editorialWarnCount => editorialChecklist
      .where((item) => item.status == EditorialCheckStatus.warn)
      .length;

  List<RenderSafetyItem> get renderSafetyChecklist =>
      _buildRenderSafetyChecklist(
        segments,
        aspectRatio: exportAspectRatio,
        requireCaptions: includeCaptions,
      );

  int get renderSafetyBlockCount => renderSafetyChecklist
      .where((item) => item.status == EditorialCheckStatus.block)
      .length;

  int get renderSafetyWarnCount => renderSafetyChecklist
      .where((item) => item.status == EditorialCheckStatus.warn)
      .length;

  bool get canPassRenderSafety => renderSafetyBlockCount == 0;

  bool get hasManualRenderSafetyBlock => renderSafetyChecklist.any(
    (item) =>
        item.status == EditorialCheckStatus.block &&
        !_isAutoRepairableRenderSafetyItem(item),
  );

  List<AutoFixReviewItem> get autoFixQueue =>
      _buildAutoFixQueue(segments, captions);

  int get autoFixCount => autoFixQueue.length;

  AutoFixReviewItem? get selectedAutoFixReview {
    final order = selectedSegmentOrder;
    if (order == null) {
      return null;
    }
    for (final item in autoFixQueue) {
      if (item.segmentOrder == order) {
        return item;
      }
    }
    return null;
  }

  Map<String, int> get signalCounts {
    final counts = <String, int>{};
    for (final segment in segments) {
      for (final tag in segment.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries.take(6));
  }

  String get statusText {
    if (errorMessage != null) {
      return errorMessage!;
    }
    if (job != null && job!.message.isNotEmpty) {
      return job!.message;
    }
    if (isProbingMedia) {
      return '미디어 사전검사 중...';
    }
    if (isPreparingPreview) {
      return '프리뷰 프록시 생성 중...';
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
      timelineMarkers: timelineMarkers,
      shortsCandidates: _serializeShortsCandidates(shortsCandidates),
      selectedShortsId: selectedShortsId,
      includeCaptions: includeCaptions,
      captionStylePreset: captionStylePreset,
      exportAspectRatio: exportAspectRatio,
      markIn: markIn,
      markOut: markOut,
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

  Future<void> _ensureLocalEngineForApi() async {
    if (kIsWeb || engineState.isRunning) {
      return;
    }
    if (engineState.isStarting) {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (engineState.isStarting && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (engineState.isRunning) {
        return;
      }
    }
    await ensureLocalEngine();
    if (!engineState.isRunning) {
      throw StateError(engineState.message);
    }
  }

  Future<void> pickVideo() async {
    errorMessage = null;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '원본 영상 가져오기',
      type: kIsWeb ? FileType.video : FileType.custom,
      allowedExtensions: kIsWeb ? null : supportedVideoExtensions,
      allowMultiple: false,
      withData: kIsWeb,
      withReadStream: !kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    selectedFile = result.files.single;
    selectedMediaProbe = null;
    isProbingMedia = false;
    isPreparingPreview = false;
    jobId = null;
    job = null;
    duration = 0;
    _manualPlayheadSeconds = 0;
    segments = [];
    transcript = [];
    captions = [];
    waveform = [];
    timelineMarkers = [];
    renderUrl = null;
    selectedSegmentOrder = null;
    markIn = null;
    markOut = null;
    uploadProgress = 0;
    timelineTool = 'selection';
    videoTrackLocked = false;
    audioTrackLocked = false;
    comparisonDefaultSegments = [];
    comparisonReferenceSegments = [];
    comparisonSelection = 'current';
    shortsCandidates = [];
    selectedShortsId = null;
    _clearHistory();
    await _disposeVideoController();
    notifyListeners();
    if (!kIsWeb && selectedFile?.path != null) {
      unawaited(_initializeLocalPreview(selectedFile!.path!));
      unawaited(probeSelectedMedia());
    }
  }

  Future<void> probeSelectedMedia() async {
    final file = selectedFile;
    final path = file?.path;
    if (kIsWeb || path == null || path.isEmpty) {
      return;
    }

    isProbingMedia = true;
    selectedMediaProbe = null;
    if (errorMessage?.startsWith('사전검사 실패') ?? false) {
      errorMessage = null;
    }
    notifyListeners();

    try {
      await _ensureLocalEngineForApi();
      final probe = await _apiClient.probeLocalMedia(path);
      if (selectedFile?.path != path) {
        return;
      }
      selectedMediaProbe = probe;
      if (!probe.canAnalyze) {
        errorMessage = '사전검사 실패: 분석 가능한 비디오 스트림이 없습니다.';
      } else if (probe.isMxf) {
        unawaited(_initializeProxyPreview(path));
      }
    } catch (error) {
      if (selectedFile?.path == path) {
        errorMessage = '사전검사 실패: $error';
      }
    } finally {
      if (selectedFile?.path == path) {
        isProbingMedia = false;
        notifyListeners();
      }
    }
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
      final styleId = hasReadyStyle ? activeStyleProfile!.styleId : null;
      final localPath = file.path;
      final UploadJobResponse response;
      if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
        await _ensureLocalEngineForApi();
        response = await _apiClient.importLocalVideo(
          path: localPath,
          displayName: file.name,
          styleId: styleId,
        );
        uploadProgress = 1;
      } else {
        response = await _apiClient.uploadVideo(
          file,
          styleId: styleId,
          onSendProgress: (sent, total) {
            if (total <= 0) {
              return;
            }
            uploadProgress = sent / total;
            notifyListeners();
          },
        );
      }
      jobId = response.jobId;
      isUploading = false;
      try {
        if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
          final previewFocus = currentPositionSeconds;
          if (selectedMediaProbe?.isMxf == true || _previewUsesProxy) {
            await _initializeProxyPreview(
              localPath,
              focusSeconds: previewFocus,
            );
          } else {
            await _initializeLocalPreview(localPath);
          }
        } else {
          await _initializePreview(response.jobId);
        }
      } catch (_) {
        await _disposeVideoController();
      }
      _startPolling();
    } catch (error) {
      isUploading = false;
      errorMessage = '분석 요청 실패: $error';
    }
    notifyListeners();
  }

  Future<void> dropSelectedFileOnTimeline() async {
    if (!hasFile) {
      errorMessage = '타임라인에 올릴 파일을 먼저 Import해 주세요';
      notifyListeners();
      return;
    }
    if (!canStartUpload) {
      return;
    }
    await startUpload();
  }

  Future<void> pickReferenceVideos() async {
    errorMessage = null;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '레퍼런스 영상 가져오기',
      type: kIsWeb ? FileType.video : FileType.custom,
      allowedExtensions: kIsWeb ? null : supportedVideoExtensions,
      allowMultiple: true,
      withData: kIsWeb,
      withReadStream: !kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    referenceFiles = result.files.take(8).toList();
    notifyListeners();
  }

  Future<void> trainReferenceStyle(String urlsText) async {
    final urls = urlsText
        .split(RegExp(r'[\n,]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(8)
        .toList();
    if (referenceFiles.isEmpty && urls.isEmpty) {
      errorMessage = '레퍼런스 파일 또는 URL을 먼저 추가해 주세요';
      notifyListeners();
      return;
    }

    isTrainingStyle = true;
    styleUploadProgress = 0;
    trainingStyleProfile = null;
    errorMessage = null;
    notifyListeners();

    try {
      final localPaths = referenceFiles
          .map((file) => file.path)
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList();
      final StyleTrainingResponse response;
      if (!kIsWeb && localPaths.length == referenceFiles.length) {
        response = await _apiClient.trainLocalStyleProfile(
          name: 'Company Reference Style',
          urls: urls,
          filePaths: localPaths,
        );
        styleUploadProgress = 1;
      } else {
        response = await _apiClient.trainStyleProfile(
          name: 'Company Reference Style',
          urls: urls,
          files: referenceFiles,
          onSendProgress: (sent, total) {
            if (total <= 0) {
              return;
            }
            styleUploadProgress = sent / total;
            notifyListeners();
          },
        );
      }
      trainingStyleProfile = response.profile;
      if (response.profile?.isReady ?? false) {
        activeStyleProfile = response.profile;
        isTrainingStyle = false;
      } else {
        _startStylePolling(response.styleId);
      }
    } catch (error) {
      isTrainingStyle = false;
      errorMessage = '레퍼런스 학습 요청 실패: $error';
    }
    notifyListeners();
  }

  void clearReferenceStyle() {
    _stylePollTimer?.cancel();
    referenceFiles = [];
    activeStyleProfile = null;
    trainingStyleProfile = null;
    isTrainingStyle = false;
    styleUploadProgress = 0;
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
    exportAspectRatio = aspectRatio;
    final repaired = _repairSegmentsForRenderSafety(segments);
    if (repaired.$2) {
      _commitHistory();
      segments = repaired.$1;
      renderUrl = null;
    }
    final safetyBlocks = _buildRenderSafetyChecklist(
      segments,
      aspectRatio: aspectRatio,
      requireCaptions: includeCaptions,
    ).where((item) => item.status == EditorialCheckStatus.block).toList();
    if (safetyBlocks.isNotEmpty) {
      final firstBlock = safetyBlocks.first;
      errorMessage = '렌더 안전 검사 실패: ${firstBlock.label} · ${firstBlock.detail}';
      notifyListeners();
      return;
    }
    isRendering = true;
    errorMessage = null;
    notifyListeners();

    try {
      await saveProjectToBackend(silent: true);
      await _apiClient.requestRender(
        id,
        segments,
        captions: captions,
        captionStyle: captionRenderStyle,
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
      _applyProject(project, keepJob: true, resetHistory: false);
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
    _commitHistory();
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
    setMarkInAt(currentPositionSeconds);
  }

  void setMarkInAt(double seconds) {
    _commitHistory();
    markIn = _snapToFrame(_clampTime(seconds));
    if (markOut != null && markOut! <= markIn!) {
      markOut = null;
    }
    notifyListeners();
  }

  void setMarkOutFromPlayhead() {
    setMarkOutAt(currentPositionSeconds);
  }

  void setMarkOutAt(double seconds) {
    _commitHistory();
    markOut = _snapToFrame(_clampTime(seconds));
    if (markIn != null && markOut! <= markIn!) {
      markIn = null;
    }
    notifyListeners();
  }

  void clearMarks() {
    _commitHistory();
    markIn = null;
    markOut = null;
    notifyListeners();
  }

  void clearMarkIn() {
    if (markIn == null) {
      return;
    }
    _commitHistory();
    markIn = null;
    notifyListeners();
  }

  void clearMarkOut() {
    if (markOut == null) {
      return;
    }
    _commitHistory();
    markOut = null;
    notifyListeners();
  }

  void addTimelineMarkerAtPlayhead() {
    addTimelineMarkerAt(currentPositionSeconds);
  }

  void addTimelineMarkerAt(double seconds, {String? label, String? note}) {
    final sourceDuration = timelineSourceDuration;
    if (sourceDuration <= 0) {
      return;
    }
    final point = _snapToFrame(seconds.clamp(0.0, sourceDuration).toDouble());
    final id =
        timelineMarkers.fold<int>(
          0,
          (maxId, marker) => math.max(maxId, marker.id),
        ) +
        1;
    final markerLabel = label ?? 'M${id.toString().padLeft(2, '0')}';
    _commitHistory();
    timelineMarkers = _normalizeTimelineMarkers([
      ...timelineMarkers,
      TimelineMarker(
        id: id,
        seconds: point,
        label: markerLabel,
        color: _markerColorFor(id),
        note: note ?? '',
      ),
    ]);
    notifyListeners();
  }

  void deleteTimelineMarker(int id) {
    if (!timelineMarkers.any((marker) => marker.id == id)) {
      return;
    }
    _commitHistory();
    timelineMarkers = [
      for (final marker in timelineMarkers)
        if (marker.id != id) marker,
    ];
    notifyListeners();
  }

  void clearTimelineMarkers() {
    if (timelineMarkers.isEmpty) {
      return;
    }
    _commitHistory();
    timelineMarkers = [];
    notifyListeners();
  }

  void jumpToNextTimelineMarker() {
    final marker = _nextTimelineMarkerFrom(currentPositionSeconds);
    if (marker == null) {
      return;
    }
    unawaited(seekTo(marker.seconds, autoplay: false));
  }

  void jumpToPreviousTimelineMarker() {
    final marker = _previousTimelineMarkerFrom(currentPositionSeconds);
    if (marker == null) {
      return;
    }
    unawaited(seekTo(marker.seconds, autoplay: false));
  }

  void markSelectedClip() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    _commitHistory();
    markIn = selected.start;
    markOut = selected.end;
    notifyListeners();
  }

  void setSelectionTool() {
    if (timelineTool == 'selection') {
      return;
    }
    timelineTool = 'selection';
    notifyListeners();
  }

  void setRazorTool() {
    if (timelineTool == 'razor') {
      return;
    }
    timelineTool = 'razor';
    notifyListeners();
  }

  void addMarkedSegment() {
    if (!hasValidMarks) {
      return;
    }
    final start = markIn!;
    final end = markOut!;
    final nextOrder = segments.length + 1;
    _commitHistory();
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

  void addEditAtPlayhead() {
    addEditAt(currentPositionSeconds);
  }

  void addEditAt(double seconds) {
    splitSelectedAt(seconds);
  }

  void rippleTrimSelectedStartToPlayhead() {
    rippleTrimSelectedStartTo(currentPositionSeconds);
  }

  void rippleTrimSelectedEndToPlayhead() {
    rippleTrimSelectedEndTo(currentPositionSeconds);
  }

  void extendSelectedStartToPlayhead() {
    extendSelectedStartTo(currentPositionSeconds);
  }

  void extendSelectedEndToPlayhead() {
    extendSelectedEndTo(currentPositionSeconds);
  }

  void rippleTrimSelectedStartTo(double seconds) {
    final point = _snapToFrame(_clampProjectTime(seconds));
    final selected = _segmentForEditAt(point);
    if (selected == null ||
        point <= selected.start + timecodeFrameDurationSeconds ||
        point >= selected.end - timecodeFrameDurationSeconds) {
      return;
    }
    updateSegment(
      selected.copyWith(
        start: point,
        audioStart: selected.audioLinked ? point : selected.audioStart,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void rippleTrimSelectedEndTo(double seconds) {
    final point = _snapToFrame(_clampProjectTime(seconds));
    final selected = _segmentForEditAt(point);
    if (selected == null ||
        point <= selected.start + timecodeFrameDurationSeconds ||
        point >= selected.end - timecodeFrameDurationSeconds) {
      return;
    }
    updateSegment(
      selected.copyWith(
        end: point,
        audioEnd: selected.audioLinked ? point : selected.audioEnd,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void extendSelectedStartTo(double seconds) {
    final point = _snapToFrame(_clampProjectTime(seconds));
    final selected = _segmentForEditAt(point, requireInside: false);
    if (selected == null ||
        point >= selected.end - timecodeFrameDurationSeconds) {
      return;
    }
    updateSegment(
      selected.copyWith(
        start: point,
        audioStart: selected.audioLinked ? point : selected.audioStart,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void extendSelectedEndTo(double seconds) {
    final point = _snapToFrame(_clampProjectTime(seconds));
    final selected = _segmentForEditAt(point, requireInside: false);
    if (selected == null ||
        point <= selected.start + timecodeFrameDurationSeconds) {
      return;
    }
    updateSegment(
      selected.copyWith(
        end: point,
        audioEnd: selected.audioLinked ? point : selected.audioEnd,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void applyDefaultVideoTransition() {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        videoFadeIn: selected.videoFadeIn == 0 ? 0.15 : selected.videoFadeIn,
        videoFadeOut: selected.videoFadeOut == 0 ? 0.15 : selected.videoFadeOut,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void applyDefaultAudioTransition() {
    final selected = selectedSegment;
    if (selected == null || audioTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioFadeIn: selected.audioFadeIn == 0 ? 0.12 : selected.audioFadeIn,
        audioFadeOut: selected.audioFadeOut == 0 ? 0.12 : selected.audioFadeOut,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void detachAudioForSelectedSegment() {
    final selected = selectedSegment;
    if (selected == null || audioTrackLocked) {
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
    if (selected == null || audioTrackLocked) {
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

  void toggleSelectedAudioLink() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    if (selected.audioLinked) {
      detachAudioForSelectedSegment();
    } else {
      relinkAudioForSelectedSegment();
    }
  }

  void toggleSelectedAudioMute() {
    final selected = selectedSegment;
    if (selected == null || audioTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioMuted: !selected.audioMuted,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void toggleSelectedAudioChannel1() {
    _toggleSelectedAudioChannel(1);
  }

  void toggleSelectedAudioChannel2() {
    _toggleSelectedAudioChannel(2);
  }

  void _toggleSelectedAudioChannel(int channel) {
    final selected = selectedSegment;
    if (selected == null || audioTrackLocked) {
      return;
    }
    final nextChannel1 = channel == 1
        ? !selected.audioChannel1Enabled
        : selected.audioChannel1Enabled;
    final nextChannel2 = channel == 2
        ? !selected.audioChannel2Enabled
        : selected.audioChannel2Enabled;
    if (!nextChannel1 && !nextChannel2) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioChannel1Enabled: nextChannel1,
        audioChannel2Enabled: nextChannel2,
        audioMuted: false,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void toggleSelectedVideoEnabled() {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        videoEnabled: !selected.videoEnabled,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedVideoFadeIn(double value) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        videoFadeIn: value.clamp(0.0, 10.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedVideoFadeOut(double value) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        videoFadeOut: value.clamp(0.0, 10.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedColorBrightness(double value) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        colorBrightness: value.clamp(-0.3, 0.3).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedColorContrast(double value) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        colorContrast: value.clamp(0.5, 1.8).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedColorSaturation(double value) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        colorSaturation: value.clamp(0.0, 2.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void resetSelectedColor() {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        colorBrightness: 0,
        colorContrast: 1,
        colorSaturation: 1,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedAudioPan(double value) {
    final selected = selectedSegment;
    if (selected == null || audioTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioPan: value.clamp(-1.0, 1.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void resetSelectedAudioPan() {
    setSelectedAudioPan(0);
  }

  void toggleSelectedAudioNormalize() {
    final selected = selectedSegment;
    if (selected == null || audioTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioNormalize: !selected.audioNormalize,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void toggleAllAudioMute() {
    setAllAudioMute(!allAudioMuted);
  }

  void setAllAudioMute(bool muted) {
    if (audioTrackLocked ||
        segments.isEmpty ||
        segments.every((segment) => segment.audioMuted == muted)) {
      return;
    }
    _commitHistory();
    segments = [
      for (final segment in segments)
        segment.copyWith(
          audioMuted: muted,
          source: segment.source == 'ai' ? 'ai+manual' : segment.source,
        ),
    ];
    renderUrl = null;
    notifyListeners();
  }

  void toggleVideoTrackLock() {
    videoTrackLocked = !videoTrackLocked;
    notifyListeners();
  }

  void toggleAudioTrackLock() {
    audioTrackLocked = !audioTrackLocked;
    notifyListeners();
  }

  void setSelectedAudioVolume(double value) {
    final selected = selectedSegment;
    if (selected == null || audioTrackLocked) {
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
    if (selected == null || selected.audioLinked || audioTrackLocked) {
      return;
    }
    final audioDuration = selected.audioDuration;
    if (audioDuration <= 0) {
      return;
    }
    var start = _snapToFrame(selected.effectiveAudioStart + delta);
    var end = _snapToFrame(selected.effectiveAudioEnd + delta);
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

  void nudgeSelectedAudioFrames(int frameDelta) {
    nudgeSelectedAudio(frameDelta * timecodeFrameDurationSeconds);
  }

  void setSelectedPlaybackSpeed(double value) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked || audioTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        playbackSpeed: value.clamp(0.25, 4.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedAudioFadeIn(double value) {
    final selected = selectedSegment;
    if (selected == null || audioTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioFadeIn: value.clamp(0.0, 10.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedAudioFadeOut(double value) {
    final selected = selectedSegment;
    if (selected == null || audioTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioFadeOut: value.clamp(0.0, 10.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void duplicateSelectedSegment() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    _commitHistory();
    final output = <HighlightSegment>[];
    for (final segment in segments) {
      output.add(segment);
      if (segment.order == selected.order) {
        output.add(
          selected.copyWith(
            order: selected.order + 1,
            reason: '${selected.reason} / copy',
            source: selected.source == 'ai' ? 'ai+manual' : selected.source,
          ),
        );
      }
    }
    segments = _reorderSegments(output);
    selectedSegmentOrder = (selected.order + 1)
        .clamp(1, segments.length)
        .toInt();
    renderUrl = null;
    notifyListeners();
  }

  void undo() {
    if (!canUndo) {
      return;
    }
    final current = _captureSnapshot();
    final previous = _undoStack.removeLast();
    _redoStack.add(current);
    _restoreSnapshot(previous);
    renderUrl = null;
    notifyListeners();
  }

  void redo() {
    if (!canRedo) {
      return;
    }
    final current = _captureSnapshot();
    final next = _redoStack.removeLast();
    _undoStack.add(current);
    _restoreSnapshot(next);
    renderUrl = null;
    notifyListeners();
  }

  void deleteSelectedSegment() {
    final order = selectedSegmentOrder;
    if (order == null) {
      return;
    }
    _commitHistory();
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
    splitSelectedAt(currentPositionSeconds);
  }

  void splitSelectedAt(double seconds) {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    final splitAt = _snapToFrame(_clampTime(seconds));
    if (splitAt <= selected.start + timecodeFrameDurationSeconds ||
        splitAt >= selected.end - timecodeFrameDurationSeconds) {
      return;
    }
    _commitHistory();
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
    _commitHistory();
    final editable = [...segments];
    final item = editable.removeAt(index);
    editable.insert(target, item);
    segments = _reorderSegments(editable);
    selectedSegmentOrder = target + 1;
    renderUrl = null;
    notifyListeners();
  }

  void condenseTimelineByScore({double targetSeconds = 240}) {
    if (segments.length <= 1) {
      return;
    }
    _commitHistory();
    final ranked = [...segments]
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.order.compareTo(b.order);
      });
    final selected = <HighlightSegment>[];
    var total = 0.0;
    for (final segment in ranked) {
      if (selected.isNotEmpty && total >= targetSeconds) {
        break;
      }
      selected.add(_directorSegment(segment));
      total += segment.outputDuration;
    }
    selected.sort((a, b) => a.start.compareTo(b.start));
    segments = _reorderSegments(selected);
    selectedSegmentOrder = segments.isEmpty ? null : segments.first.order;
    renderUrl = null;
    notifyListeners();
  }

  void removeWeakSegments() {
    if (segments.length <= 1 || averageClipScore <= 0) {
      return;
    }
    final threshold = _weakScoreThreshold(averageClipScore);
    final filtered = [
      for (final segment in segments)
        if (segment.score == 0 || segment.score >= threshold)
          _directorSegment(segment),
    ];
    if (filtered.isEmpty || filtered.length == segments.length) {
      return;
    }
    _commitHistory();
    segments = _reorderSegments(filtered);
    selectedSegmentOrder = selectedSegmentOrder == null
        ? segments.first.order
        : selectedSegmentOrder!.clamp(1, segments.length).toInt();
    renderUrl = null;
    notifyListeners();
  }

  void padSelectedClipForContext() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    final start = _snapToFrame(_clampProjectTime(selected.start - 1.2));
    final end = _snapToFrame(_clampProjectTime(selected.end + 0.8));
    updateSegment(
      _directorSegment(
        selected.copyWith(
          start: start,
          end: end,
          audioStart: selected.audioLinked ? start : selected.audioStart,
          audioEnd: selected.audioLinked ? end : selected.audioEnd,
        ),
      ),
    );
  }

  void hideFillerCaptions() {
    if (captions.isEmpty) {
      return;
    }
    final updated = [
      for (final caption in captions)
        if (_fillerPattern.hasMatch(caption.text))
          caption.copyWith(enabled: false)
        else
          caption,
    ];
    if (_sameCaptionEnabledState(updated, captions)) {
      return;
    }
    _commitHistory();
    captions = updated;
    renderUrl = null;
    notifyListeners();
  }

  void applyShortsDirectorPreset() {
    if (duration <= 0 || segments.isEmpty) {
      return;
    }
    _commitHistory();
    exportAspectRatio = '9:16';
    includeCaptions = true;
    segments = _reorderSegments([
      for (final segment in segments)
        _directorSegment(
          segment.copyWith(
            audioFadeIn: segment.audioFadeIn == 0 ? 0.12 : segment.audioFadeIn,
            audioFadeOut: segment.audioFadeOut == 0
                ? 0.18
                : segment.audioFadeOut,
          ),
        ),
    ]);
    renderUrl = null;
    notifyListeners();
  }

  void applyFinishingPreset() {
    if (segments.isEmpty) {
      return;
    }
    _commitHistory();
    includeCaptions = true;
    segments = _reorderSegments([
      for (final segment in segments)
        segment.copyWith(
          videoFadeIn: segment.videoFadeIn == 0 ? 0.10 : segment.videoFadeIn,
          videoFadeOut: segment.videoFadeOut == 0 ? 0.14 : segment.videoFadeOut,
          audioFadeIn: segment.audioFadeIn == 0 ? 0.12 : segment.audioFadeIn,
          audioFadeOut: segment.audioFadeOut == 0 ? 0.18 : segment.audioFadeOut,
          audioNormalize: !segment.audioMuted,
          colorContrast: segment.colorContrast == 1
              ? 1.06
              : segment.colorContrast,
          colorSaturation: segment.colorSaturation == 1
              ? 1.04
              : segment.colorSaturation,
          source: segment.source.contains('finish')
              ? segment.source
              : '${segment.source}+finish',
        ),
    ]);
    renderUrl = null;
    notifyListeners();
  }

  void buildAiComparisonVariants() {
    if (segments.isEmpty) {
      return;
    }
    comparisonDefaultSegments = _reorderSegments([
      for (final segment in segments)
        segment.copyWith(
          source: segment.source.contains('baseline')
              ? segment.source
              : '${segment.source}+baseline',
        ),
    ]);
    comparisonReferenceSegments = _buildReferenceStyleVariant();
    comparisonSelection = 'compare';
    notifyListeners();
  }

  void applyComparisonVariant(String variant) {
    if (!hasComparisonVariants) {
      buildAiComparisonVariants();
    }
    final source = variant == 'reference'
        ? comparisonReferenceSegments
        : comparisonDefaultSegments;
    if (source.isEmpty) {
      return;
    }
    _commitHistory();
    segments = _reorderSegments(List<HighlightSegment>.of(source));
    selectedSegmentOrder = segments.first.order;
    comparisonSelection = variant;
    renderUrl = null;
    notifyListeners();
  }

  void applyCaptionStylePreset(String preset) {
    if (captionStylePreset == preset && includeCaptions) {
      return;
    }
    _commitHistory();
    captionStylePreset = preset;
    includeCaptions = true;
    renderUrl = null;
    notifyListeners();
  }

  void applyAudioAutoMix() {
    if (segments.isEmpty || audioTrackLocked) {
      return;
    }
    _commitHistory();
    segments = _reorderSegments([
      for (final segment in segments)
        segment.copyWith(
          audioNormalize: !segment.audioMuted,
          audioPan: 0,
          audioVolume: segment.audioMuted
              ? segment.audioVolume
              : segment.audioVolume.clamp(0.85, 1.15).toDouble(),
          audioFadeIn: segment.audioFadeIn == 0 ? 0.08 : segment.audioFadeIn,
          audioFadeOut: segment.audioFadeOut == 0 ? 0.16 : segment.audioFadeOut,
          source: _appendSource(segment.source, 'audio'),
        ),
    ]);
    renderUrl = null;
    notifyListeners();
  }

  void applyEditorialReviewPass() {
    if (segments.isEmpty && captions.isEmpty) {
      return;
    }
    _commitHistory();
    includeCaptions = true;
    captionStylePreset = captionStylePreset == 'minimal'
        ? captionStylePreset
        : 'news';
    captions = [
      for (final caption in captions)
        if (_fillerPattern.hasMatch(caption.text))
          caption.copyWith(enabled: false)
        else
          caption,
    ];
    segments = _reorderSegments([
      for (final segment in segments)
        segment.copyWith(
          videoFadeIn: segment.videoFadeIn == 0 ? 0.08 : segment.videoFadeIn,
          videoFadeOut: segment.videoFadeOut == 0 ? 0.12 : segment.videoFadeOut,
          audioNormalize: !segment.audioMuted,
          audioPan: 0,
          audioFadeIn: segment.audioFadeIn == 0 ? 0.08 : segment.audioFadeIn,
          audioFadeOut: segment.audioFadeOut == 0 ? 0.16 : segment.audioFadeOut,
          source: _appendSource(segment.source, 'qa'),
        ),
    ]);
    renderUrl = null;
    notifyListeners();
  }

  void applyAutoFixForSegment(int order, AutoFixAction action) {
    if (segments.isEmpty) {
      return;
    }
    final index = segments.indexWhere((segment) => segment.order == order);
    if (index < 0) {
      return;
    }
    if (action == AutoFixAction.selectForReview) {
      selectedSegmentOrder = order;
      notifyListeners();
      return;
    }
    final result = _applyAutoFixToSegment(
      segments[index],
      action,
      segmentCount: segments.length,
    );
    if (result == segments[index] && action != AutoFixAction.hideFiller) {
      return;
    }
    if (result == null && segments.length <= 1) {
      return;
    }
    _commitHistory();
    if (action == AutoFixAction.hideFiller) {
      captions = _hideFillerCaptionsForSegment(segments[index]);
    }
    if (result == null) {
      if (segments.length <= 1) {
        return;
      }
      final updated = [...segments]..removeAt(index);
      segments = _reorderSegments(updated);
      selectedSegmentOrder = segments.isEmpty
          ? null
          : index.clamp(0, segments.length - 1).toInt() + 1;
    } else {
      segments = _reorderSegments([
        for (final segment in segments)
          if (segment.order == order) result else segment,
      ]);
      selectedSegmentOrder = result.order.clamp(1, segments.length).toInt();
    }
    renderUrl = null;
    notifyListeners();
  }

  void applyAllAutoFixes() {
    if (segments.isEmpty) {
      return;
    }
    var workingSegments = List<HighlightSegment>.of(segments);
    var workingCaptions = List<CaptionSegment>.of(captions);
    var applied = false;
    for (var pass = 0; pass < 5; pass++) {
      final queue = _buildAutoFixQueue(workingSegments, workingCaptions);
      if (queue.isEmpty) {
        break;
      }
      var appliedThisPass = false;
      for (final item in queue.take(24)) {
        if (item.action == AutoFixAction.selectForReview) {
          continue;
        }
        final index = workingSegments.indexWhere(
          (segment) => segment.order == item.segmentOrder,
        );
        if (index < 0) {
          continue;
        }
        if (item.action == AutoFixAction.hideFiller) {
          workingCaptions = _hideFillerCaptionsForSegment(
            workingSegments[index],
            sourceCaptions: workingCaptions,
          );
          applied = true;
          appliedThisPass = true;
          continue;
        }
        final result = _applyAutoFixToSegment(
          workingSegments[index],
          item.action,
          segmentCount: workingSegments.length,
        );
        if (result == null) {
          if (workingSegments.length <= 1) {
            continue;
          }
          workingSegments.removeAt(index);
          workingSegments = _reorderSegments(workingSegments);
          applied = true;
          appliedThisPass = true;
        } else if (result != workingSegments[index]) {
          workingSegments[index] = result;
          workingSegments = _reorderSegments(workingSegments);
          applied = true;
          appliedThisPass = true;
        }
      }
      if (!appliedThisPass) {
        break;
      }
    }
    if (!applied) {
      return;
    }
    _commitHistory();
    segments = _reorderSegments(workingSegments);
    captions = [
      for (var index = 0; index < workingCaptions.length; index++)
        workingCaptions[index].copyWith(order: index + 1),
    ];
    selectedSegmentOrder = segments.isEmpty
        ? null
        : (selectedSegmentOrder ?? segments.first.order)
              .clamp(1, segments.length)
              .toInt();
    renderUrl = null;
    notifyListeners();
  }

  void applyRenderSafetyAutoRepair() {
    if (segments.isEmpty) {
      return;
    }
    final repaired = _repairSegmentsForRenderSafety(segments);
    final workingSegments = repaired.$1;
    final applied = repaired.$2;

    final remainingBlocks = _buildRenderSafetyChecklist(
      workingSegments,
      aspectRatio: exportAspectRatio,
      requireCaptions: includeCaptions,
    ).where((item) => item.status == EditorialCheckStatus.block).toList();
    RenderSafetyItem? firstManualBlock;
    for (final block in remainingBlocks) {
      if (block.segmentOrder != null) {
        firstManualBlock = block;
        break;
      }
    }

    if (!applied && remainingBlocks.isEmpty) {
      return;
    }
    if (applied) {
      _commitHistory();
      segments = workingSegments;
      renderUrl = null;
    }
    if (firstManualBlock?.segmentOrder != null) {
      selectedSegmentOrder = firstManualBlock!.segmentOrder;
    } else if (segments.isNotEmpty) {
      selectedSegmentOrder = (selectedSegmentOrder ?? segments.first.order)
          .clamp(1, segments.length)
          .toInt();
    }
    errorMessage = remainingBlocks.isEmpty
        ? null
        : '자동 수리 후에도 수동 검수 필요: ${remainingBlocks.first.label} · ${remainingBlocks.first.detail}';
    notifyListeners();
  }

  void applySelectedShortsRenderSafetyAutoRepair() {
    final selected = shortsCandidates
        .where(
          (candidate) => candidate.selected && candidate.segments.isNotEmpty,
        )
        .toList();
    if (selected.isEmpty) {
      errorMessage = '안전 수리할 쇼츠 후보를 선택해 주세요';
      notifyListeners();
      return;
    }

    var applied = false;
    shortsCandidates = [
      for (final candidate in shortsCandidates)
        if (candidate.selected && candidate.segments.isNotEmpty)
          _repairShortsCandidateForRenderSafety(
            candidate,
            onApplied: () {
              applied = true;
            },
          )
        else
          candidate,
    ];

    final remainingBlock = _firstSelectedShortsRenderBlock();
    if (applied) {
      renderUrl = null;
      final active = selectedShortsId == null
          ? null
          : _shortsCandidateById(selectedShortsId!);
      if (active != null) {
        _loadShortsCandidateToTimeline(active);
      }
    }
    if (remainingBlock != null) {
      selectedShortsId = remainingBlock.candidate.id;
      _loadShortsCandidateToTimeline(remainingBlock.candidate);
      if (remainingBlock.item.segmentOrder != null) {
        selectedSegmentOrder = remainingBlock.item.segmentOrder;
      }
    }
    errorMessage = remainingBlock == null
        ? null
        : '쇼츠 자동 수리 후에도 수동 검수 필요: ${remainingBlock.candidate.label} · ${remainingBlock.item.label} · ${remainingBlock.item.detail}';
    notifyListeners();
  }

  void buildMultiShortsCandidates({
    int maxCandidates = 6,
    double minSeconds = 120,
    double maxSeconds = 180,
  }) {
    if (segments.isEmpty) {
      return;
    }
    final ranked = [...segments]
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.start.compareTo(b.start);
      });
    final strategies = _shortsBuildStrategies();
    final pool = <ShortsCandidate>[];
    var nextId = 1;
    for (final strategy in strategies) {
      final strategyUsed = <int>{};
      var strategyCount = 0;
      for (final seed in _rankSegmentsForShortsStrategy(
        strategy.kind,
        ranked,
      )) {
        if (strategyCount >= strategy.maxCandidates) {
          break;
        }
        if (_skipSeedForShortsStrategy(strategy.kind, seed)) {
          continue;
        }
        final group = _buildShortsGroup(
          seed,
          strategyUsed,
          minSeconds: minSeconds,
          maxSeconds: maxSeconds,
        );
        if (group.isEmpty) {
          continue;
        }
        for (final segment in group) {
          strategyUsed.add(segment.order);
        }
        final normalized = _reorderSegments(
          _prepareShortsCandidateSegments(group, strategy.kind, maxSeconds),
        );
        pool.add(
          _scoreShortsCandidate(
            ShortsCandidate(
              id: nextId,
              label: '${strategy.label} ${nextId.toString().padLeft(2, '0')}',
              reason: _shortsReason(normalized),
              segments: normalized,
              strategyKind: strategy.kind,
              strategyLabel: strategy.label,
              selected: true,
            ),
          ),
        );
        nextId += 1;
        strategyCount += 1;
      }
    }
    if (pool.isEmpty) {
      pool.add(
        _scoreShortsCandidate(
          ShortsCandidate(
            id: 1,
            label: 'Balanced 01',
            reason: '현재 타임라인 기반 기본 쇼츠 후보',
            segments: _reorderSegments(segments.take(4).toList()),
            strategyKind: 'balanced',
            strategyLabel: 'Balanced',
            selected: true,
          ),
        ),
      );
    }
    final output = _selectDiverseShortsCandidates(
      pool,
      strategies,
      maxCandidates: maxCandidates,
    );
    output.sort((a, b) {
      final scoreCompare = b.qualityScore.compareTo(a.qualityScore);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.durationSeconds.compareTo(b.durationSeconds);
    });
    final rankedOutput = [
      for (var index = 0; index < output.length; index++)
        output[index].copyWith(
          id: index + 1,
          label:
              '${output[index].strategyLabel} ${(index + 1).toString().padLeft(2, '0')}',
        ),
    ];
    shortsCandidates = _applyShortsReadinessSelection(rankedOutput);
    selectedShortsId = rankedOutput.first.id;
    _loadShortsCandidateToTimeline(shortsCandidates.first);
    notifyListeners();
  }

  List<ShortsCandidate> _applyShortsReadinessSelection(
    List<ShortsCandidate> input,
  ) {
    return [
      for (final candidate in input)
        candidate.copyWith(
          selected: _shouldAutoSelectShortsCandidate(candidate),
        ),
    ];
  }

  bool _shouldAutoSelectShortsCandidate(ShortsCandidate candidate) {
    if (!candidate.isPublishReady) {
      return false;
    }
    final safetyBlocks = _buildRenderSafetyChecklist(
      candidate.segments,
      aspectRatio: '9:16',
      requireCaptions: true,
    ).where((item) => item.status == EditorialCheckStatus.block);
    return safetyBlocks.isEmpty;
  }

  List<_ShortsBuildStrategy> _shortsBuildStrategies() {
    return const [
      _ShortsBuildStrategy(
        kind: 'balanced',
        label: 'Balanced',
        maxCandidates: 3,
      ),
      _ShortsBuildStrategy(kind: 'hook', label: 'Hook', maxCandidates: 2),
      _ShortsBuildStrategy(kind: 'news', label: 'News', maxCandidates: 2),
      _ShortsBuildStrategy(kind: 'info', label: 'Info', maxCandidates: 2),
      _ShortsBuildStrategy(kind: 'risk', label: 'Risk', maxCandidates: 1),
    ];
  }

  List<ShortsCandidate> _selectDiverseShortsCandidates(
    List<ShortsCandidate> pool,
    List<_ShortsBuildStrategy> strategies, {
    required int maxCandidates,
  }) {
    final selected = <ShortsCandidate>[];
    final signatures = <String>{};

    void addCandidate(ShortsCandidate candidate) {
      if (selected.length >= maxCandidates) {
        return;
      }
      final signature = _shortsCandidateSignature(candidate);
      if (signatures.add(signature)) {
        selected.add(candidate);
      }
    }

    for (final strategy in strategies) {
      final strategyCandidates =
          pool
              .where((candidate) => candidate.strategyKind == strategy.kind)
              .toList()
            ..sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
      if (strategyCandidates.isNotEmpty) {
        addCandidate(strategyCandidates.first);
      }
    }

    final rankedPool = [...pool]
      ..sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
    for (final candidate in rankedPool) {
      addCandidate(candidate);
      if (selected.length >= maxCandidates) {
        break;
      }
    }
    return selected.isEmpty
        ? rankedPool.take(maxCandidates).toList()
        : selected;
  }

  String _shortsCandidateSignature(ShortsCandidate candidate) {
    return candidate.segments
        .map(
          (segment) =>
              '${segment.start.toStringAsFixed(1)}-${segment.end.toStringAsFixed(1)}',
        )
        .join('|');
  }

  List<HighlightSegment> _rankSegmentsForShortsStrategy(
    String strategyKind,
    List<HighlightSegment> input,
  ) {
    final ranked = [...input]
      ..sort((a, b) {
        final scoreCompare = _shortsSeedScore(
          strategyKind,
          b,
        ).compareTo(_shortsSeedScore(strategyKind, a));
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.start.compareTo(b.start);
      });
    return ranked;
  }

  bool _skipSeedForShortsStrategy(String strategyKind, HighlightSegment seed) {
    if (seed.score > 0 && seed.score < 4.5 && strategyKind != 'risk') {
      return true;
    }
    if (strategyKind == 'risk') {
      return !_segmentHasRiskSignal(seed);
    }
    if (strategyKind == 'news') {
      return !_segmentHasAnyTag(seed, const {
            '뉴스핵심',
            '근거',
            '영향',
            '대응',
            '출처확인',
            '시간축',
            '발언',
          }) &&
          !_containsAny(seed.reason, const ['뉴스', '속보', '단독', '발언', '확인']);
    }
    if (strategyKind == 'info') {
      return !_segmentHasAnyTag(seed, const {'문제해결', '구체성', '비교', '근거'}) &&
          !_containsAny(seed.script, const ['방법', '이유', '차이', '원인', '비교']);
    }
    return false;
  }

  double _shortsSeedScore(String strategyKind, HighlightSegment segment) {
    final base = segment.score > 0 ? segment.score * 10 : 52.0;
    final text =
        '${segment.reason} ${segment.script} ${segment.tags.join(' ')}';
    return switch (strategyKind) {
      'hook' =>
        base +
            (_containsAny(text, const [
                  '결과',
                  '핵심',
                  '충격',
                  '문제',
                  '원인',
                  '논란',
                  '후킹',
                  '유지율',
                ])
                ? 28
                : 0) +
            (segment.start <= 60 ? 8 : 0),
      'news' =>
        base +
            _tagMatchCount(segment, const {
                  '뉴스핵심',
                  '근거',
                  '영향',
                  '대응',
                  '출처확인',
                  '시간축',
                  '발언',
                }) *
                13 +
            (_containsAny(text, const ['속보', '단독', '공식', '발표', '확인']) ? 16 : 0),
      'info' =>
        base +
            _tagMatchCount(segment, const {'문제해결', '구체성', '비교', '근거'}) * 12 +
            (_containsAny(text, const ['방법', '이유', '차이', '원인', '비교', '수치'])
                ? 14
                : 0),
      'risk' => base + (_segmentHasRiskSignal(segment) ? 42 : -80),
      _ => base + (_segmentHasRiskSignal(segment) ? -10 : 0),
    };
  }

  bool _segmentHasRiskSignal(HighlightSegment segment) {
    return _riskPattern.hasMatch(segment.reason) ||
        _riskPattern.hasMatch(segment.script) ||
        segment.tags.any((tag) => _riskPattern.hasMatch(tag));
  }

  bool _segmentHasAnyTag(HighlightSegment segment, Set<String> tags) {
    return segment.tags.any(tags.contains);
  }

  int _tagMatchCount(HighlightSegment segment, Set<String> tags) {
    return segment.tags.where(tags.contains).length;
  }

  bool _containsAny(String value, List<String> needles) {
    final normalized = value.toLowerCase();
    return needles.any((needle) => normalized.contains(needle.toLowerCase()));
  }

  List<HighlightSegment> _prepareShortsCandidateSegments(
    List<HighlightSegment> group,
    String strategyKind,
    double targetMax,
  ) {
    final ordered = _orderShortsStorySegments(group, strategyKind);
    return [
      for (var index = 0; index < ordered.length; index++)
        _prepareShortsStorySegment(
          ordered[index],
          strategyKind,
          targetMax,
          index: index,
          total: ordered.length,
        ),
    ];
  }

  List<HighlightSegment> _orderShortsStorySegments(
    List<HighlightSegment> group,
    String strategyKind,
  ) {
    if (group.length <= 1) {
      return group;
    }
    final ordered = [...group]
      ..sort((a, b) {
        final roleCompare = _shortsRoleRank(
          _shortsStoryRole(a, strategyKind),
        ).compareTo(_shortsRoleRank(_shortsStoryRole(b, strategyKind)));
        if (roleCompare != 0) {
          return roleCompare;
        }
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.start.compareTo(b.start);
      });

    final hookIndex = ordered.indexWhere(
      (segment) => _shortsStoryRole(segment, strategyKind) == 'hook',
    );
    if (hookIndex > 0) {
      final hook = ordered.removeAt(hookIndex);
      ordered.insert(0, hook);
    }
    return ordered;
  }

  HighlightSegment _prepareShortsStorySegment(
    HighlightSegment segment,
    String strategyKind,
    double targetMax, {
    required int index,
    required int total,
  }) {
    final role = _shortsStoryRole(segment, strategyKind);
    final padding = _shortsRolePadding(role, index: index, total: total);
    final paddedStart = _snapToFrame(
      _clampProjectTime(segment.start - padding.$1),
    );
    final paddedEnd = _snapToFrame(_clampProjectTime(segment.end + padding.$2));
    final padded = segment.copyWith(
      start: paddedStart,
      end: paddedEnd,
      audioStart: segment.audioLinked ? paddedStart : segment.audioStart,
      audioEnd: segment.audioLinked ? paddedEnd : segment.audioEnd,
      tags: [
        ...segment.tags,
        if (!segment.tags.contains(_storyTagForRole(role)))
          _storyTagForRole(role),
      ],
    );
    return _referenceStyleSegment(
      padded,
      targetMax,
    ).copyWith(source: _appendSource(padded.source, 'shorts'));
  }

  String _shortsStoryRole(HighlightSegment segment, String strategyKind) {
    final text =
        '${segment.reason} ${segment.script} ${segment.tags.join(' ')}';
    if (_segmentHasRiskSignal(segment)) {
      return strategyKind == 'risk' ? 'risk' : 'evidence';
    }
    if (_containsAny(text, const ['결과', '핵심', '충격', '문제', '후킹', '유지율'])) {
      return 'hook';
    }
    if (_segmentHasAnyTag(segment, const {'근거', '출처확인', '발언', '뉴스핵심'}) ||
        _containsAny(text, const ['근거', '공식', '발표', '확인', '발언'])) {
      return 'evidence';
    }
    if (_segmentHasAnyTag(segment, const {'문제해결', '구체성', '비교'}) ||
        _containsAny(text, const ['방법', '이유', '원인', '차이', '비교', '수치'])) {
      return 'context';
    }
    if (_segmentHasAnyTag(segment, const {'영향', '대응'}) ||
        _containsAny(text, const ['영향', '대응', '결론', '그래서', '앞으로'])) {
      return 'impact';
    }
    if (_segmentHasAnyTag(segment, const {'CTA'})) {
      return 'close';
    }
    return strategyKind == 'hook' ? 'context' : 'evidence';
  }

  int _shortsRoleRank(String role) {
    return switch (role) {
      'hook' => 0,
      'risk' => 1,
      'evidence' => 2,
      'context' => 3,
      'impact' => 4,
      'close' => 5,
      _ => 3,
    };
  }

  (double, double) _shortsRolePadding(
    String role, {
    required int index,
    required int total,
  }) {
    final isFirst = index == 0;
    final isLast = index == total - 1;
    final base = switch (role) {
      'hook' => (isFirst ? 0.25 : 0.45, 0.75),
      'risk' => (0.65, 0.65),
      'evidence' => (0.50, 0.55),
      'context' => (0.45, 0.60),
      'impact' => (0.35, isLast ? 1.10 : 0.70),
      'close' => (0.30, 1.00),
      _ => (0.45, 0.55),
    };
    return (base.$1, isLast ? math.max(base.$2, 0.90) : base.$2);
  }

  String _storyTagForRole(String role) {
    return switch (role) {
      'hook' => 'Story:Hook',
      'risk' => 'Story:Risk',
      'evidence' => 'Story:Evidence',
      'context' => 'Story:Context',
      'impact' => 'Story:Impact',
      'close' => 'Story:Close',
      _ => 'Story:Context',
    };
  }

  List<String> _shortsStoryFlow(
    List<HighlightSegment> input,
    String strategyKind,
  ) {
    final roles = <String>[];
    for (final segment in input) {
      final label = _storyLabelForRole(_shortsStoryRole(segment, strategyKind));
      if (!roles.contains(label)) {
        roles.add(label);
      }
    }
    return roles;
  }

  String _storyLabelForRole(String role) {
    return switch (role) {
      'hook' => 'Hook',
      'risk' => 'Risk',
      'evidence' => 'Evidence',
      'context' => 'Context',
      'impact' => 'Impact',
      'close' => 'Close',
      _ => 'Context',
    };
  }

  double _shortsStoryScore(List<HighlightSegment> input, String strategyKind) {
    if (input.isEmpty) {
      return 0;
    }
    final roles = [
      for (final segment in input) _shortsStoryRole(segment, strategyKind),
    ];
    var score = 40.0;
    if (roles.first == 'hook' ||
        strategyKind == 'risk' && roles.first == 'risk') {
      score += 24;
    }
    if (roles.contains('evidence')) {
      score += 14;
    }
    if (roles.contains('context')) {
      score += 10;
    }
    if (roles.contains('impact') || roles.contains('close')) {
      score += 8;
    }
    for (var index = 1; index < roles.length; index++) {
      if (_shortsRoleRank(roles[index]) < _shortsRoleRank(roles[index - 1])) {
        score -= 8;
      }
    }
    return score.clamp(0.0, 100.0).toDouble();
  }

  ShortsCandidate _scoreShortsCandidate(ShortsCandidate candidate) {
    final candidateSegments = candidate.segments;
    if (candidateSegments.isEmpty) {
      return candidate.copyWith(
        qualityScore: 0,
        qualityGrade: 'D',
        riskCount: 0,
        strengths: const [],
        issues: const ['No clips'],
        storyFlow: const [],
        storyScore: 0,
      );
    }

    final duration = candidate.durationSeconds;
    final durationScore = _shortsDurationScore(duration);
    final scored = candidateSegments
        .where((segment) => segment.score > 0)
        .toList();
    final averageScore = scored.isEmpty
        ? 5.5
        : scored.fold<double>(0, (total, segment) => total + segment.score) /
              scored.length;
    final highlightScore = (averageScore * 10).clamp(0.0, 100.0).toDouble();
    final first = candidateSegments.first;
    final hookScore = _shortsHookScore(first);
    final signalScore = _shortsSignalScore(candidateSegments);
    final audioScore = _shortsAudioScore(candidateSegments);
    final captionScore = _shortsCaptionScore(candidateSegments);
    final storyScore = _shortsStoryScore(
      candidateSegments,
      candidate.strategyKind,
    );
    final riskCount = _shortsRiskCount(candidateSegments);
    final fillerCount = _shortsFillerCaptionCount(candidateSegments);
    final offlineReviewCount = _shortsOfflineReviewCount(candidateSegments);
    final riskPenalty = (riskCount * 12 + fillerCount * 3)
        .clamp(0, 35)
        .toDouble();
    final offlinePenalty = (offlineReviewCount * 16).clamp(0, 42).toDouble();
    final quality =
        (durationScore * 0.18) +
        (highlightScore * 0.26) +
        (hookScore * 0.18) +
        (signalScore * 0.16) +
        (audioScore * 0.12) +
        (captionScore * 0.08) +
        (storyScore * 0.02) -
        riskPenalty -
        offlinePenalty;
    final score = quality.clamp(0.0, 100.0).toDouble();
    return candidate.copyWith(
      qualityScore: score,
      qualityGrade: _shortsGrade(score),
      riskCount: riskCount,
      strengths: _shortsStrengths(
        durationScore: durationScore,
        hookScore: hookScore,
        signalScore: signalScore,
        audioScore: audioScore,
        captionScore: captionScore,
        storyScore: storyScore,
      ),
      issues: _shortsIssues(
        duration: duration,
        riskCount: riskCount,
        fillerCount: fillerCount,
        offlineReviewCount: offlineReviewCount,
        audioScore: audioScore,
        captionScore: captionScore,
        storyScore: storyScore,
      ),
      storyFlow: _shortsStoryFlow(candidateSegments, candidate.strategyKind),
      storyScore: storyScore,
      reason: _shortsReason(
        candidateSegments,
        score: score,
        riskCount: riskCount,
      ),
    );
  }

  double _shortsDurationScore(double duration) {
    const ideal = 150.0;
    if (duration <= 0) {
      return 0;
    }
    final distance = (duration - ideal).abs();
    var score = 100 - distance * 0.9;
    if (duration < 90) {
      score -= (90 - duration) * 0.35;
    }
    if (duration > 210) {
      score -= (duration - 210) * 0.35;
    }
    return score.clamp(0.0, 100.0).toDouble();
  }

  double _shortsHookScore(HighlightSegment first) {
    var score = first.score > 0 ? (first.score * 8).clamp(35.0, 82.0) : 55.0;
    final text = '${first.reason} ${first.script} ${first.tags.join(' ')}';
    final hookPattern = RegExp(
      r'결과|핵심|충격|문제|원인|비밀|공개|논란|단독|속보|후킹|유지율|impact|hook',
      caseSensitive: false,
    );
    if (hookPattern.hasMatch(text)) {
      score += 16;
    }
    if (first.start <= 45) {
      score += 6;
    }
    return score.clamp(0.0, 100.0).toDouble();
  }

  double _shortsSignalScore(List<HighlightSegment> input) {
    final tags = <String>{};
    for (final segment in input) {
      tags.addAll(segment.tags);
    }
    final strongSignals = {
      '뉴스핵심',
      '근거',
      '영향',
      '문제해결',
      '구체성',
      '비교',
      '대응',
      '발언',
      '유지율',
    };
    final strongCount = tags.where(strongSignals.contains).length;
    final density = input.isEmpty ? 0.0 : tags.length / input.length;
    return (45 + strongCount * 10 + density * 9).clamp(0.0, 100.0).toDouble();
  }

  double _shortsAudioScore(List<HighlightSegment> input) {
    if (input.isEmpty) {
      return 0;
    }
    final readyCount = input
        .where(
          (segment) =>
              !segment.audioMuted &&
              segment.hasActiveAudioChannel &&
              segment.audioNormalize &&
              segment.audioPan.abs() <= 0.001,
        )
        .length;
    return (readyCount / input.length * 100).clamp(0.0, 100.0).toDouble();
  }

  double _shortsCaptionScore(List<HighlightSegment> input) {
    if (input.isEmpty) {
      return 0;
    }
    if (captions.isEmpty) {
      return includeCaptions ? 45 : 25;
    }
    var covered = 0;
    for (final segment in input) {
      final hasCaption = captions.any(
        (caption) =>
            caption.enabled &&
            caption.start < segment.end &&
            caption.end > segment.start,
      );
      if (hasCaption) {
        covered += 1;
      }
    }
    return (covered / input.length * 100).clamp(0.0, 100.0).toDouble();
  }

  int _shortsRiskCount(List<HighlightSegment> input) {
    var count = 0;
    for (final segment in input) {
      if (_riskPattern.hasMatch(segment.reason) ||
          _riskPattern.hasMatch(segment.script) ||
          segment.tags.any((tag) => _riskPattern.hasMatch(tag))) {
        count += 1;
      }
    }
    return count;
  }

  int _shortsFillerCaptionCount(List<HighlightSegment> input) {
    var count = 0;
    for (final segment in input) {
      count += captions
          .where(
            (caption) =>
                caption.enabled &&
                caption.start < segment.end &&
                caption.end > segment.start &&
                _fillerPattern.hasMatch(caption.text),
          )
          .length;
    }
    return count;
  }

  int _shortsOfflineReviewCount(List<HighlightSegment> input) {
    return input.where(_isOfflineReviewSegment).length;
  }

  List<RenderSafetyItem> _buildRenderSafetyChecklist(
    List<HighlightSegment> input, {
    required String aspectRatio,
    required bool requireCaptions,
  }) {
    final checks = <RenderSafetyItem>[];
    final totalDuration = input.fold<double>(
      0,
      (total, segment) => total + segment.outputDuration,
    );

    if (input.isEmpty) {
      return const [
        RenderSafetyItem(
          label: 'Timeline',
          detail: '렌더할 컷이 없습니다',
          status: EditorialCheckStatus.block,
        ),
      ];
    }

    checks.add(
      RenderSafetyItem(
        label: 'Timeline',
        detail: '${input.length} clips · ${formatSeconds(totalDuration)}',
        status: totalDuration > 0
            ? EditorialCheckStatus.pass
            : EditorialCheckStatus.block,
      ),
    );

    if (aspectRatio == '9:16') {
      final status = totalDuration >= 60 && totalDuration <= 210
          ? EditorialCheckStatus.pass
          : EditorialCheckStatus.warn;
      checks.add(
        RenderSafetyItem(
          label: 'Shorts runtime',
          detail: '${totalDuration.round()}s · 권장 60-210s',
          status: status,
        ),
      );
    } else {
      final status = totalDuration >= 45 && totalDuration <= 420
          ? EditorialCheckStatus.pass
          : EditorialCheckStatus.warn;
      checks.add(
        RenderSafetyItem(
          label: 'Program runtime',
          detail: '${totalDuration.round()}s · 권장 45-420s',
          status: status,
        ),
      );
    }

    for (final segment in input) {
      final clipLabel = 'Clip ${segment.order}';
      final timeLabel =
          '${formatSeconds(segment.start)}-${formatSeconds(segment.end)}';
      if (segment.start < 0 ||
          segment.end <= segment.start ||
          (duration > 0 &&
              segment.end > duration + timecodeFrameDurationSeconds)) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel range',
            detail: '$timeLabel 소스 범위를 확인해 주세요',
            status: EditorialCheckStatus.block,
            segmentOrder: segment.order,
          ),
        );
      }
      if (segment.duration < 0.8) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel cut',
            detail: '${segment.duration.toStringAsFixed(1)}s · 컷이 너무 짧습니다',
            status: EditorialCheckStatus.block,
            segmentOrder: segment.order,
          ),
        );
      } else if (segment.duration < 2.0) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel cut',
            detail: '${segment.duration.toStringAsFixed(1)}s · 호흡 확인 필요',
            status: EditorialCheckStatus.warn,
            segmentOrder: segment.order,
          ),
        );
      }
      if (!segment.videoEnabled) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel video',
            detail: '비디오 트랙이 꺼져 검은 화면 위험이 있습니다',
            status: EditorialCheckStatus.block,
            segmentOrder: segment.order,
          ),
        );
      }
      if (segment.playbackSpeed <= 0) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel speed',
            detail: '재생 속도가 0 이하입니다',
            status: EditorialCheckStatus.block,
            segmentOrder: segment.order,
          ),
        );
      }
      if (segment.effectiveAudioEnd <= segment.effectiveAudioStart) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel audio',
            detail: '오디오 인/아웃 범위가 비정상입니다',
            status: EditorialCheckStatus.block,
            segmentOrder: segment.order,
          ),
        );
      }
      if (segment.audioMuted ||
          !segment.hasActiveAudioChannel ||
          segment.audioVolume <= 0.01) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel audio',
            detail: '무음 또는 활성 오디오 채널 없음',
            status: EditorialCheckStatus.block,
            segmentOrder: segment.order,
          ),
        );
      } else if (!segment.audioNormalize ||
          segment.audioPan.abs() > 0.001 ||
          segment.audioVolume > 1.35) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel mix',
            detail: '정규화/팬/볼륨 믹스 확인 필요',
            status: EditorialCheckStatus.warn,
            segmentOrder: segment.order,
          ),
        );
      }
      if (segment.videoFadeIn + segment.videoFadeOut >= segment.duration) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel fade',
            detail: '비디오 페이드가 컷 길이보다 깁니다',
            status: EditorialCheckStatus.warn,
            segmentOrder: segment.order,
          ),
        );
      }
      if (segment.audioFadeIn + segment.audioFadeOut >= segment.audioDuration) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel audio fade',
            detail: '오디오 페이드가 오디오 길이보다 깁니다',
            status: EditorialCheckStatus.warn,
            segmentOrder: segment.order,
          ),
        );
      }
      if (_riskPattern.hasMatch(segment.reason) ||
          _riskPattern.hasMatch(segment.script) ||
          segment.tags.any((tag) => _riskPattern.hasMatch(tag))) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel risk',
            detail: '미확인/추정 표현은 수동 검수 후 렌더하세요',
            status: EditorialCheckStatus.block,
            segmentOrder: segment.order,
          ),
        );
      }
      if (_isOfflineReviewSegment(segment)) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel review',
            detail: 'STT/LLM 내용 분석 없이 생성된 검토용 후보입니다',
            status: EditorialCheckStatus.warn,
            segmentOrder: segment.order,
          ),
        );
      }
    }

    final enabledCaptions = captions
        .where((caption) => caption.enabled)
        .toList();
    if (requireCaptions && enabledCaptions.isEmpty) {
      checks.add(
        const RenderSafetyItem(
          label: 'Captions',
          detail: '자막 렌더가 켜졌지만 활성 자막이 없습니다',
          status: EditorialCheckStatus.warn,
        ),
      );
    } else if (requireCaptions && enabledCaptions.isNotEmpty) {
      final uncoveredCount = input
          .where(
            (segment) => !enabledCaptions.any(
              (caption) =>
                  caption.start < segment.end && caption.end > segment.start,
            ),
          )
          .length;
      checks.add(
        RenderSafetyItem(
          label: 'Caption coverage',
          detail: uncoveredCount == 0
              ? '모든 컷에 자막 겹침'
              : '$uncoveredCount clips 자막 확인 필요',
          status: uncoveredCount == 0
              ? EditorialCheckStatus.pass
              : EditorialCheckStatus.warn,
        ),
      );
    }

    if (checks.every((item) => item.status != EditorialCheckStatus.block)) {
      checks.add(
        const RenderSafetyItem(
          label: 'Render gate',
          detail: '차단 항목 없음',
          status: EditorialCheckStatus.pass,
        ),
      );
    }
    return checks;
  }

  int _selectedShortsRenderSafetyCount(EditorialCheckStatus status) {
    var count = 0;
    for (final candidate in shortsCandidates) {
      if (!candidate.selected || candidate.segments.isEmpty) {
        continue;
      }
      count += _buildRenderSafetyChecklist(
        candidate.segments,
        aspectRatio: '9:16',
        requireCaptions: true,
      ).where((item) => item.status == status).length;
    }
    return count;
  }

  ({ShortsCandidate candidate, RenderSafetyItem item})?
  _firstSelectedShortsRenderBlock() {
    for (final candidate in shortsCandidates) {
      if (!candidate.selected || candidate.segments.isEmpty) {
        continue;
      }
      final blocks = _buildRenderSafetyChecklist(
        candidate.segments,
        aspectRatio: '9:16',
        requireCaptions: true,
      ).where((item) => item.status == EditorialCheckStatus.block).toList();
      if (blocks.isNotEmpty) {
        return (candidate: candidate, item: blocks.first);
      }
    }
    return null;
  }

  bool _isAutoRepairableRenderSafetyItem(RenderSafetyItem item) {
    if (item.status != EditorialCheckStatus.block) {
      return false;
    }
    if (item.segmentOrder == null) {
      return false;
    }
    return item.label.endsWith('range') ||
        item.label.endsWith('cut') ||
        item.label.endsWith('video') ||
        item.label.endsWith('speed') ||
        item.label.endsWith('audio') ||
        item.label.endsWith('fade');
  }

  bool _isOfflineReviewSegment(HighlightSegment segment) {
    return segment.source.startsWith('fallback-') ||
        segment.tags.contains('STT미설정') ||
        segment.tags.contains('검토필요');
  }

  String _shortsGrade(double score) {
    if (score >= 86) {
      return 'S';
    }
    if (score >= 74) {
      return 'A';
    }
    if (score >= 62) {
      return 'B';
    }
    if (score >= 50) {
      return 'C';
    }
    return 'D';
  }

  List<String> _shortsStrengths({
    required double durationScore,
    required double hookScore,
    required double signalScore,
    required double audioScore,
    required double captionScore,
    required double storyScore,
  }) {
    final strengths = <String>[];
    if (hookScore >= 78) {
      strengths.add('Hook');
    }
    if (durationScore >= 78) {
      strengths.add('Runtime');
    }
    if (signalScore >= 72) {
      strengths.add('Signals');
    }
    if (audioScore >= 90) {
      strengths.add('Audio');
    }
    if (captionScore >= 80) {
      strengths.add('Captions');
    }
    if (storyScore >= 78) {
      strengths.add('Story');
    }
    return strengths.take(4).toList();
  }

  List<String> _shortsIssues({
    required double duration,
    required int riskCount,
    required int fillerCount,
    required int offlineReviewCount,
    required double audioScore,
    required double captionScore,
    required double storyScore,
  }) {
    final issues = <String>[];
    if (duration < 90) {
      issues.add('Short runtime');
    } else if (duration > 210) {
      issues.add('Long runtime');
    }
    if (riskCount > 0) {
      issues.add('Risk review');
    }
    if (offlineReviewCount > 0) {
      issues.add('Offline review');
    }
    if (fillerCount > 0) {
      issues.add('Filler captions');
    }
    if (audioScore < 75) {
      issues.add('Audio mix');
    }
    if (captionScore < 60) {
      issues.add('Captions');
    }
    if (storyScore < 58) {
      issues.add('Story flow');
    }
    return issues.take(4).toList();
  }

  void selectShortsCandidate(int id) {
    final candidate = _shortsCandidateById(id);
    if (candidate == null) {
      return;
    }
    selectedShortsId = id;
    _loadShortsCandidateToTimeline(candidate);
    notifyListeners();
  }

  void updateSelectedShortsFromTimeline() {
    final id = selectedShortsId;
    if (id == null || segments.isEmpty) {
      return;
    }
    shortsCandidates = [
      for (final candidate in shortsCandidates)
        if (candidate.id == id)
          _scoreShortsCandidate(
            candidate.copyWith(
              segments: _reorderSegments(List<HighlightSegment>.of(segments)),
            ),
          )
        else
          candidate,
    ];
    notifyListeners();
  }

  void toggleShortsCandidate(int id) {
    shortsCandidates = [
      for (final candidate in shortsCandidates)
        if (candidate.id == id)
          candidate.copyWith(selected: !candidate.selected)
        else
          candidate,
    ];
    notifyListeners();
  }

  void deleteShortsCandidate(int id) {
    shortsCandidates = [
      for (final candidate in shortsCandidates)
        if (candidate.id != id) candidate,
    ];
    if (selectedShortsId == id) {
      selectedShortsId = shortsCandidates.isEmpty
          ? null
          : shortsCandidates.first.id;
      if (shortsCandidates.isNotEmpty) {
        _loadShortsCandidateToTimeline(shortsCandidates.first);
      }
    }
    notifyListeners();
  }

  void duplicateShortsCandidate(int id) {
    final source = _shortsCandidateById(id);
    if (source == null) {
      return;
    }
    final nextId =
        shortsCandidates.fold<int>(
          0,
          (maxId, candidate) => candidate.id > maxId ? candidate.id : maxId,
        ) +
        1;
    shortsCandidates = [
      ...shortsCandidates,
      _scoreShortsCandidate(
        source.copyWith(
          id: nextId,
          label: 'Shorts ${nextId.toString().padLeft(2, '0')}',
        ),
      ),
    ];
    notifyListeners();
  }

  Future<void> requestSelectedShortsRender() async {
    final id = jobId;
    if (id == null) {
      return;
    }
    final selected = shortsCandidates
        .where(
          (candidate) => candidate.selected && candidate.segments.isNotEmpty,
        )
        .toList();
    if (selected.isEmpty) {
      errorMessage = '렌더링할 쇼츠 후보를 선택해 주세요';
      notifyListeners();
      return;
    }
    var repairedCandidates = false;
    shortsCandidates = [
      for (final candidate in shortsCandidates)
        if (candidate.selected && candidate.segments.isNotEmpty)
          _repairShortsCandidateForRenderSafety(
            candidate,
            onApplied: () {
              repairedCandidates = true;
            },
          )
        else
          candidate,
    ];
    if (repairedCandidates) {
      renderUrl = null;
      final active = selectedShortsId == null
          ? null
          : _shortsCandidateById(selectedShortsId!);
      if (active != null) {
        _loadShortsCandidateToTimeline(active);
      }
    }
    final renderItems = shortsCandidates
        .where(
          (candidate) => candidate.selected && candidate.segments.isNotEmpty,
        )
        .toList();
    for (final candidate in renderItems) {
      final safetyBlocks = _buildRenderSafetyChecklist(
        candidate.segments,
        aspectRatio: '9:16',
        requireCaptions: true,
      ).where((item) => item.status == EditorialCheckStatus.block).toList();
      if (safetyBlocks.isNotEmpty) {
        final firstBlock = safetyBlocks.first;
        errorMessage =
            '쇼츠 렌더 안전 검사 실패: ${candidate.label} · ${firstBlock.label} · ${firstBlock.detail}';
        notifyListeners();
        return;
      }
    }
    isRendering = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _apiClient.requestBatchRender(
        id,
        [
          for (var index = 0; index < renderItems.length; index++)
            {
              'label': renderItems[index].label,
              'output_name':
                  'shorts_${(index + 1).toString().padLeft(2, '0')}.mp4',
              'segments': renderItems[index].segments
                  .map((segment) => segment.toJson())
                  .toList(),
            },
        ],
        captions: captions,
        captionStyle: CaptionRenderStyle.preset('shorts'),
        aspectRatio: '9:16',
        includeCaptions: true,
      );
      _startPolling();
    } catch (error) {
      isRendering = false;
      errorMessage = '쇼츠 일괄 렌더링 요청 실패: $error';
      notifyListeners();
    }
  }

  void updateCaption(CaptionSegment updated) {
    _commitHistory();
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
    _commitHistory();
    includeCaptions = value;
    renderUrl = null;
    notifyListeners();
  }

  void setExportAspectRatio(String value) {
    _commitHistory();
    exportAspectRatio = value;
    renderUrl = null;
    notifyListeners();
  }

  void zoomTimeline(double delta) {
    timelineZoom = (timelineZoom + delta).clamp(1.0, 6.0).toDouble();
    notifyListeners();
  }

  bool _proxyContainsSourceTime(double seconds) {
    if (!_previewUsesProxy) {
      return true;
    }
    final durationSeconds = _previewSourceDurationSeconds;
    if (durationSeconds == null || durationSeconds <= 0) {
      return true;
    }
    final endSeconds = _previewSourceStartSeconds + durationSeconds;
    return seconds >=
            _previewSourceStartSeconds - timecodeFrameDurationSeconds &&
        seconds <= endSeconds - timecodeFrameDurationSeconds;
  }

  double _previewLocalSecondsFor(
    double sourceSeconds,
    VideoPlayerController controller,
  ) {
    final durationSeconds = controller.value.duration.inMilliseconds / 1000;
    final localSeconds = sourceSeconds - _previewSourceStartSeconds;
    if (durationSeconds <= 0) {
      return math.max(0, localSeconds);
    }
    return localSeconds.clamp(0.0, durationSeconds).toDouble();
  }

  Future<void> seekTo(double seconds, {bool autoplay = true}) async {
    var controller = videoController;
    final clamped = _clampTime(seconds);
    _manualPlayheadSeconds = clamped;
    if (_previewUsesProxy && !_proxyContainsSourceTime(clamped)) {
      final path = selectedFile?.path;
      if (!kIsWeb && path != null && path.isNotEmpty) {
        await _initializeProxyPreview(path, focusSeconds: clamped);
        controller = videoController;
      }
    }
    if (controller == null || !controller.value.isInitialized) {
      notifyListeners();
      return;
    }
    final localSeconds = _previewLocalSecondsFor(clamped, controller);
    await controller.seekTo(
      Duration(milliseconds: (localSeconds * 1000).round()),
    );
    if (autoplay) {
      await controller.play();
    }
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
    _pollOnce();
  }

  void _startStylePolling(String styleId) {
    _stylePollTimer?.cancel();
    _stylePollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollStyleProfile(styleId),
    );
    unawaited(_pollStyleProfile(styleId));
  }

  Future<void> _pollStyleProfile(String styleId) async {
    try {
      final profile = await _apiClient.getStyleProfile(styleId);
      trainingStyleProfile = profile;
      if (profile.isReady) {
        activeStyleProfile = profile;
        isTrainingStyle = false;
        _stylePollTimer?.cancel();
      } else if (profile.status == 'failed') {
        isTrainingStyle = false;
        errorMessage = profile.error ?? '레퍼런스 스타일 학습 실패';
        _stylePollTimer?.cancel();
      }
      notifyListeners();
    } catch (error) {
      isTrainingStyle = false;
      errorMessage = '레퍼런스 상태 조회 실패: $error';
      _stylePollTimer?.cancel();
      notifyListeners();
    }
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
    comparisonDefaultSegments = [];
    comparisonReferenceSegments = [];
    comparisonSelection = 'current';
    shortsCandidates = [];
    selectedShortsId = null;
    if (segments.isNotEmpty &&
        !segments.any((segment) => segment.order == selectedSegmentOrder)) {
      selectedSegmentOrder = segments.first.order;
    }
    _clearHistory();
  }

  Future<void> _initializePreview(String id) async {
    final revision = ++_previewRevision;
    await _disposeVideoController();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(_apiClient.sourceUrl(id)),
    );
    await controller.initialize();
    if (revision != _previewRevision) {
      await controller.dispose();
      return;
    }
    videoController = controller;
    _previewUsesProxy = false;
    _previewSourceStartSeconds = 0;
    _previewSourceDurationSeconds = null;
    final previewDuration = controller.value.duration.inMilliseconds / 1000;
    if (previewDuration > 0 && duration == 0) {
      duration = previewDuration;
    }
    controller.addListener(_handleVideoTick);
  }

  Future<void> _initializeLocalPreview(String path) async {
    final revision = ++_previewRevision;
    try {
      final file = io.File(path);
      if (!await file.exists()) {
        return;
      }
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (revision != _previewRevision || selectedFile?.path != path) {
        await controller.dispose();
        return;
      }
      await _disposeVideoController();
      videoController = controller;
      _previewUsesProxy = false;
      _previewSourceStartSeconds = 0;
      _previewSourceDurationSeconds = null;
      final previewDuration = controller.value.duration.inMilliseconds / 1000;
      if (previewDuration > 0 && duration == 0) {
        duration = previewDuration;
      }
      controller.addListener(_handleVideoTick);
      notifyListeners();
    } catch (_) {
      if (selectedFile?.path == path) {
        await _disposeVideoController();
        unawaited(_initializeProxyPreview(path));
        notifyListeners();
      }
    }
  }

  Future<void> _initializeProxyPreview(
    String path, {
    double focusSeconds = 0,
    bool autoplay = false,
  }) async {
    if (kIsWeb || path.isEmpty) {
      return;
    }
    isPreparingPreview = true;
    notifyListeners();
    try {
      await _ensureLocalEngineForApi();
      final sourceStart = math.max(0.0, focusSeconds - 8.0);
      final preview = await _apiClient.createLocalPreview(
        path,
        startSeconds: sourceStart,
        durationSeconds: focusSeconds > 0 ? 240 : null,
      );
      if (selectedFile?.path != path) {
        return;
      }
      final revision = ++_previewRevision;
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(preview.url),
      );
      await controller.initialize();
      if (revision != _previewRevision || selectedFile?.path != path) {
        await controller.dispose();
        return;
      }
      await _disposeVideoController();
      videoController = controller;
      _previewUsesProxy = true;
      _previewSourceStartSeconds = preview.sourceStart;
      final previewDuration = controller.value.duration.inMilliseconds / 1000;
      _previewSourceDurationSeconds =
          previewDuration > 0 && preview.duration > 0
          ? math.min(previewDuration, preview.duration)
          : (preview.duration > 0 ? preview.duration : previewDuration);
      final sourceDuration = selectedMediaProbe?.duration ?? 0;
      if (sourceDuration > 0 && duration == 0) {
        duration = sourceDuration;
      }
      if (focusSeconds > 0) {
        final localSeconds = _previewLocalSecondsFor(focusSeconds, controller);
        await controller.seekTo(
          Duration(milliseconds: (localSeconds * 1000).round()),
        );
      }
      if (autoplay) {
        await controller.play();
      }
      controller.addListener(_handleVideoTick);
    } catch (error) {
      if (selectedFile?.path == path && errorMessage == null) {
        errorMessage = '프리뷰 생성 실패: $error';
      }
    } finally {
      if (selectedFile?.path == path) {
        isPreparingPreview = false;
        notifyListeners();
      }
    }
  }

  Future<void> _disposeVideoController() async {
    final current = videoController;
    videoController = null;
    _previewUsesProxy = false;
    _previewSourceStartSeconds = 0;
    _previewSourceDurationSeconds = null;
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
    _manualPlayheadSeconds = seconds;
    final isPlaying = controller.value.isPlaying;
    if ((seconds - _lastNotifiedPosition).abs() >=
            timecodeFrameDurationSeconds ||
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

  double _clampTime(double value) {
    final sourceDuration = timelineSourceDuration;
    if (sourceDuration <= 0) {
      return value < 0 ? 0 : value;
    }
    return value.clamp(0.0, sourceDuration).toDouble();
  }

  double _snapToFrame(double value) => snapSecondsToFrame(value);

  double _clampProjectTime(double value) {
    if (duration <= 0) {
      return value < 0 ? 0 : value;
    }
    return value.clamp(0.0, duration).toDouble();
  }

  List<TimelineMarker> _normalizeTimelineMarkers(List<TimelineMarker> input) {
    final normalized = <TimelineMarker>[];
    final usedIds = <int>{};
    for (final marker in input) {
      var id = marker.id <= 0 ? normalized.length + 1 : marker.id;
      while (usedIds.contains(id)) {
        id += 1;
      }
      usedIds.add(id);
      final label = marker.label.trim().isEmpty
          ? 'M${id.toString().padLeft(2, '0')}'
          : marker.label.trim();
      normalized.add(
        marker.copyWith(
          id: id,
          seconds: _snapToFrame(_clampProjectTime(marker.seconds)),
          label: label,
          color: marker.color.trim().isEmpty
              ? _markerColorFor(id)
              : marker.color,
          note: marker.note.trim(),
        ),
      );
    }
    normalized.sort((a, b) {
      final timeCompare = a.seconds.compareTo(b.seconds);
      if (timeCompare != 0) {
        return timeCompare;
      }
      return a.id.compareTo(b.id);
    });
    return normalized;
  }

  TimelineMarker? _nextTimelineMarkerFrom(double seconds) {
    final threshold = seconds + timecodeFrameDurationSeconds / 2;
    for (final marker in timelineMarkers) {
      if (marker.seconds > threshold) {
        return marker;
      }
    }
    return null;
  }

  TimelineMarker? _previousTimelineMarkerFrom(double seconds) {
    final threshold = seconds - timecodeFrameDurationSeconds / 2;
    for (final marker in timelineMarkers.reversed) {
      if (marker.seconds < threshold) {
        return marker;
      }
    }
    return null;
  }

  String _markerColorFor(int id) {
    const colors = ['amber', 'cyan', 'green', 'rose', 'violet'];
    return colors[(id - 1).clamp(0, 9999) % colors.length];
  }

  HighlightSegment _normalizeSegmentAudio(HighlightSegment segment) {
    final start = _snapToFrame(_clampProjectTime(segment.start));
    var end = _snapToFrame(_clampProjectTime(segment.end));
    if (end <= start) {
      end = _snapToFrame(
        _clampProjectTime(start + timecodeFrameDurationSeconds),
      );
    }
    final playbackSpeed = segment.playbackSpeed.clamp(0.25, 4.0).toDouble();
    final audioPan = segment.audioPan.clamp(-1.0, 1.0).toDouble();
    final colorBrightness = segment.colorBrightness.clamp(-0.3, 0.3).toDouble();
    final colorContrast = segment.colorContrast.clamp(0.5, 1.8).toDouble();
    final colorSaturation = segment.colorSaturation.clamp(0.0, 2.0).toDouble();
    final audioChannel1Enabled =
        segment.audioChannel1Enabled || !segment.audioChannel2Enabled;
    final audioChannel2Enabled = segment.audioChannel2Enabled;
    final normalizedSegment = segment.copyWith(
      start: start,
      end: end,
      playbackSpeed: playbackSpeed,
      colorBrightness: colorBrightness,
      colorContrast: colorContrast,
      colorSaturation: colorSaturation,
      audioChannel1Enabled: audioChannel1Enabled,
      audioChannel2Enabled: audioChannel2Enabled,
    );
    final volume = segment.audioVolume.clamp(0.0, 2.0).toDouble();
    final maxFade = (normalizedSegment.outputDuration / 2)
        .clamp(0.0, 10.0)
        .toDouble();
    final audioFadeIn = segment.audioFadeIn.clamp(0.0, maxFade).toDouble();
    final audioFadeOut = segment.audioFadeOut.clamp(0.0, maxFade).toDouble();
    final videoFadeIn = segment.videoFadeIn.clamp(0.0, maxFade).toDouble();
    final videoFadeOut = segment.videoFadeOut.clamp(0.0, maxFade).toDouble();
    if (normalizedSegment.audioLinked) {
      return normalizedSegment.copyWith(
        audioStart: normalizedSegment.start,
        audioEnd: normalizedSegment.end,
        audioVolume: volume,
        audioPan: audioPan,
        videoFadeIn: videoFadeIn,
        videoFadeOut: videoFadeOut,
        audioFadeIn: audioFadeIn,
        audioFadeOut: audioFadeOut,
      );
    }

    var audioStart = _snapToFrame(
      _clampProjectTime(normalizedSegment.effectiveAudioStart),
    );
    var audioEnd = _snapToFrame(
      _clampProjectTime(normalizedSegment.effectiveAudioEnd),
    );
    if (audioEnd <= audioStart) {
      audioStart = normalizedSegment.start;
      audioEnd = normalizedSegment.end;
    }
    return normalizedSegment.copyWith(
      audioStart: audioStart,
      audioEnd: audioEnd,
      audioVolume: volume,
      audioPan: audioPan,
      videoFadeIn: videoFadeIn,
      videoFadeOut: videoFadeOut,
      audioFadeIn: audioFadeIn,
      audioFadeOut: audioFadeOut,
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
    final audioSplit = _snapToFrame(
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

  List<AutoFixReviewItem> _buildAutoFixQueue(
    List<HighlightSegment> sourceSegments,
    List<CaptionSegment> sourceCaptions,
  ) {
    if (sourceSegments.isEmpty) {
      return const [];
    }
    final average = _averageScoreFor(sourceSegments);
    final weakThreshold = _weakScoreThreshold(average);
    final targetMax = _targetMaxClipSeconds();
    final targetIdeal = _targetIdealClipSeconds();
    final output = <AutoFixReviewItem>[];
    for (final segment in sourceSegments) {
      final hasFillerCaption = sourceCaptions.any(
        (caption) =>
            caption.enabled &&
            caption.start < segment.end &&
            caption.end > segment.start &&
            _fillerPattern.hasMatch(caption.text),
      );
      final hasRiskText =
          _riskPattern.hasMatch(segment.script) ||
          _riskPattern.hasMatch(segment.reason) ||
          segment.tags.any((tag) => _riskPattern.hasMatch(tag));

      if (!_segmentVideoReady(segment)) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'V1 video disabled',
            detail: '검은 화면으로 나갈 수 있어 V1을 다시 켭니다.',
            severity: AutoFixSeverity.block,
            action: AutoFixAction.restoreVideo,
          ),
        );
      }
      if (!_segmentAudioReady(segment)) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'A1/A2 inactive',
            detail: '오디오 채널 또는 음소거 상태를 방송 기본값으로 복구합니다.',
            severity: AutoFixSeverity.block,
            action: AutoFixAction.enableAudioPair,
          ),
        );
      }
      if (hasRiskText) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'Risk wording',
            detail: '루머/미확인 표현이 있어 직접 확인이 필요합니다.',
            severity: AutoFixSeverity.block,
            action: AutoFixAction.selectForReview,
          ),
        );
      }
      if (segment.duration < 2.5) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'Clip too short',
            detail: '문맥이 끊길 수 있어 앞뒤 여유를 붙입니다.',
            severity: AutoFixSeverity.warn,
            action: AutoFixAction.padContext,
          ),
        );
      }
      if (segment.duration > targetMax) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'Clip too long',
            detail: '${targetIdeal.round()}초 안팎으로 줄여 숏폼/하이라이트 호흡을 맞춥니다.',
            severity: AutoFixSeverity.warn,
            action: AutoFixAction.trimLongClip,
          ),
        );
      }
      if (sourceSegments.length > 1 &&
          average > 0 &&
          segment.score > 0 &&
          segment.score < weakThreshold) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'Low highlight score',
            detail: '전체 평균 대비 약한 컷이라 제거 후보입니다.',
            severity: AutoFixSeverity.warn,
            action: AutoFixAction.removeWeak,
          ),
        );
      }
      if (_segmentNeedsAudioMix(segment)) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'Audio needs mix',
            detail: '정규화, 팬, 레벨을 기본 방송 믹스로 정리합니다.',
            severity: AutoFixSeverity.warn,
            action: AutoFixAction.mixAudio,
          ),
        );
      }
      if (hasFillerCaption) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'Filler caption',
            detail: '불필요한 추임새 자막을 숨깁니다.',
            severity: AutoFixSeverity.polish,
            action: AutoFixAction.hideFiller,
          ),
        );
      }
      if (_segmentNeedsFadePolish(segment)) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'No edge polish',
            detail: '컷 시작/끝에 아주 짧은 페이드 안전값을 넣습니다.',
            severity: AutoFixSeverity.polish,
            action: AutoFixAction.addFades,
          ),
        );
      }
    }
    output.sort((a, b) {
      final severityCompare = a.severity.index.compareTo(b.severity.index);
      if (severityCompare != 0) {
        return severityCompare;
      }
      return a.segmentOrder.compareTo(b.segmentOrder);
    });
    return output;
  }

  (List<HighlightSegment>, bool) _repairSegmentsForRenderSafety(
    List<HighlightSegment> sourceSegments,
  ) {
    var applied = false;
    var workingSegments = List<HighlightSegment>.of(sourceSegments);
    for (var pass = 0; pass < 3; pass++) {
      var changedThisPass = false;
      final nextSegments = <HighlightSegment>[];
      for (final segment in workingSegments) {
        final repaired = _repairSegmentForRenderSafety(segment);
        nextSegments.add(repaired.$1);
        if (repaired.$2) {
          changedThisPass = true;
          applied = true;
        }
      }
      workingSegments = _reorderSegments(nextSegments);
      if (!changedThisPass) {
        break;
      }
    }
    return (workingSegments, applied);
  }

  ShortsCandidate _repairShortsCandidateForRenderSafety(
    ShortsCandidate candidate, {
    required void Function() onApplied,
  }) {
    final repaired = _repairSegmentsForRenderSafety(candidate.segments);
    if (!repaired.$2) {
      return candidate;
    }
    onApplied();
    return _scoreShortsCandidate(candidate.copyWith(segments: repaired.$1));
  }

  (HighlightSegment, bool) _repairSegmentForRenderSafety(
    HighlightSegment segment,
  ) {
    var next = segment;
    var changed = false;

    var start = _snapToFrame(_clampProjectTime(next.start));
    var end = _snapToFrame(_clampProjectTime(next.end));
    if (end <= start) {
      end = _snapToFrame(_clampProjectTime(start + 2.0));
      if (end <= start && duration > 0) {
        start = _snapToFrame(_clampProjectTime(math.max(0, duration - 2.0)));
        end = _snapToFrame(_clampProjectTime(duration));
      }
    }
    if (start != next.start || end != next.end) {
      next = next.copyWith(
        start: start,
        end: end,
        audioStart: next.audioLinked ? start : next.audioStart,
        audioEnd: next.audioLinked ? end : next.audioEnd,
      );
      changed = true;
    }

    if (next.duration < 2.0) {
      next = _padSegmentForAutoFix(next);
      changed = true;
    }

    if (!next.videoEnabled) {
      next = next.copyWith(videoEnabled: true);
      changed = true;
    }

    if (next.playbackSpeed <= 0) {
      next = next.copyWith(playbackSpeed: 1.0);
      changed = true;
    }

    if (next.effectiveAudioEnd <= next.effectiveAudioStart ||
        next.audioMuted ||
        !next.hasActiveAudioChannel ||
        next.audioVolume <= 0.01) {
      next = next.copyWith(
        audioStart: next.start,
        audioEnd: next.end,
        audioLinked: true,
        audioMuted: false,
        audioChannel1Enabled: true,
        audioChannel2Enabled: true,
        audioNormalize: true,
        audioPan: 0,
        audioVolume: 1.0,
      );
      changed = true;
    } else if (!next.audioNormalize ||
        next.audioPan.abs() > 0.001 ||
        next.audioVolume < 0.85 ||
        next.audioVolume > 1.15) {
      next = next.copyWith(
        audioNormalize: true,
        audioPan: 0,
        audioVolume: next.audioVolume.clamp(0.85, 1.15).toDouble(),
      );
      changed = true;
    }

    final maxVideoFade = (next.duration / 3).clamp(0.04, 0.18).toDouble();
    if (next.videoFadeIn + next.videoFadeOut >= next.duration) {
      next = next.copyWith(
        videoFadeIn: math.min(next.videoFadeIn, maxVideoFade),
        videoFadeOut: math.min(next.videoFadeOut, maxVideoFade),
      );
      changed = true;
    } else if (next.videoFadeIn == 0 && next.videoFadeOut == 0) {
      next = next.copyWith(videoFadeIn: 0.08, videoFadeOut: 0.12);
      changed = true;
    }

    final maxAudioFade = (next.audioDuration / 3).clamp(0.04, 0.18).toDouble();
    if (next.audioFadeIn + next.audioFadeOut >= next.audioDuration) {
      next = next.copyWith(
        audioFadeIn: math.min(next.audioFadeIn, maxAudioFade),
        audioFadeOut: math.min(next.audioFadeOut, maxAudioFade),
      );
      changed = true;
    } else if (next.audioFadeIn == 0 && next.audioFadeOut == 0) {
      next = next.copyWith(audioFadeIn: 0.08, audioFadeOut: 0.16);
      changed = true;
    }

    if (!changed) {
      return (segment, false);
    }
    return (_directorSegment(_normalizeSegmentAudio(next)), true);
  }

  HighlightSegment? _applyAutoFixToSegment(
    HighlightSegment segment,
    AutoFixAction action, {
    required int segmentCount,
  }) {
    switch (action) {
      case AutoFixAction.restoreVideo:
        return _directorSegment(segment.copyWith(videoEnabled: true));
      case AutoFixAction.enableAudioPair:
        return _directorSegment(
          segment.copyWith(
            audioMuted: false,
            audioChannel1Enabled: true,
            audioChannel2Enabled: true,
            audioNormalize: true,
            audioPan: 0,
            audioVolume: segment.audioVolume.clamp(0.85, 1.15).toDouble(),
          ),
        );
      case AutoFixAction.padContext:
        return _padSegmentForAutoFix(segment);
      case AutoFixAction.trimLongClip:
        return _trimLongSegmentForAutoFix(segment);
      case AutoFixAction.removeWeak:
        return segmentCount > 1 ? null : _trimLongSegmentForAutoFix(segment);
      case AutoFixAction.mixAudio:
        return _directorSegment(
          segment.copyWith(
            audioMuted: false,
            audioChannel1Enabled:
                segment.audioChannel1Enabled || !segment.audioChannel2Enabled,
            audioNormalize: true,
            audioPan: 0,
            audioVolume: segment.audioVolume.clamp(0.85, 1.15).toDouble(),
            audioFadeIn: segment.audioFadeIn == 0 ? 0.08 : segment.audioFadeIn,
            audioFadeOut: segment.audioFadeOut == 0
                ? 0.16
                : segment.audioFadeOut,
          ),
        );
      case AutoFixAction.addFades:
        return _directorSegment(
          segment.copyWith(
            videoFadeIn: segment.videoFadeIn == 0 ? 0.08 : segment.videoFadeIn,
            videoFadeOut: segment.videoFadeOut == 0
                ? 0.12
                : segment.videoFadeOut,
            audioFadeIn: segment.audioFadeIn == 0 ? 0.08 : segment.audioFadeIn,
            audioFadeOut: segment.audioFadeOut == 0
                ? 0.16
                : segment.audioFadeOut,
          ),
        );
      case AutoFixAction.hideFiller:
        return _directorSegment(segment);
      case AutoFixAction.selectForReview:
        return segment;
    }
  }

  List<CaptionSegment> _hideFillerCaptionsForSegment(
    HighlightSegment segment, {
    List<CaptionSegment>? sourceCaptions,
  }) {
    final input = sourceCaptions ?? captions;
    return [
      for (final caption in input)
        if (caption.enabled &&
            caption.start < segment.end &&
            caption.end > segment.start &&
            _fillerPattern.hasMatch(caption.text))
          caption.copyWith(enabled: false)
        else
          caption,
    ];
  }

  HighlightSegment _padSegmentForAutoFix(HighlightSegment segment) {
    final before = segment.start <= 1 ? 0.4 : 1.0;
    final after = segment.end >= duration - 1 ? 0.4 : 1.0;
    final start = _snapToFrame(_clampProjectTime(segment.start - before));
    final end = _snapToFrame(_clampProjectTime(segment.end + after));
    return _directorSegment(
      segment.copyWith(
        start: start,
        end: end,
        audioStart: segment.audioLinked ? start : segment.audioStart,
        audioEnd: segment.audioLinked ? end : segment.audioEnd,
      ),
    );
  }

  HighlightSegment _trimLongSegmentForAutoFix(HighlightSegment segment) {
    final target = _targetIdealClipSeconds();
    if (segment.duration <= target) {
      return segment;
    }
    final center = (segment.start + segment.end) / 2;
    var start = center - target / 2;
    var end = center + target / 2;
    if (start < 0) {
      end -= start;
      start = 0;
    }
    if (duration > 0 && end > duration) {
      start = math.max(0, start - (end - duration));
      end = duration;
    }
    final snappedStart = _snapToFrame(_clampProjectTime(start));
    final snappedEnd = _snapToFrame(_clampProjectTime(end));
    return _directorSegment(
      segment.copyWith(
        start: snappedStart,
        end: snappedEnd,
        audioStart: segment.audioLinked ? snappedStart : segment.audioStart,
        audioEnd: segment.audioLinked ? snappedEnd : segment.audioEnd,
      ),
    );
  }

  bool _segmentVideoReady(HighlightSegment segment) => segment.videoEnabled;

  bool _segmentAudioReady(HighlightSegment segment) =>
      !segment.audioMuted && segment.hasActiveAudioChannel;

  bool _segmentNeedsAudioMix(HighlightSegment segment) {
    if (!_segmentAudioReady(segment)) {
      return false;
    }
    return !segment.audioNormalize ||
        segment.audioPan.abs() > 0.001 ||
        segment.audioVolume < 0.85 ||
        segment.audioVolume > 1.15;
  }

  bool _segmentNeedsFadePolish(HighlightSegment segment) {
    return segment.videoFadeIn == 0 &&
        segment.videoFadeOut == 0 &&
        segment.audioFadeIn == 0 &&
        segment.audioFadeOut == 0;
  }

  double _averageScoreFor(List<HighlightSegment> input) {
    final scored = input.where((segment) => segment.score > 0).toList();
    if (scored.isEmpty) {
      return 0;
    }
    return scored.fold<double>(0, (total, item) => total + item.score) /
        scored.length;
  }

  double _targetMaxClipSeconds() {
    final profileMax = activeStyleProfile?.targetSegmentSecondsMax;
    if (profileMax != null && profileMax > 0) {
      return profileMax * 1.35;
    }
    return exportAspectRatio == '9:16' ? 42 : 70;
  }

  double _targetIdealClipSeconds() {
    final profileIdeal = activeStyleProfile?.targetSegmentSecondsIdeal;
    if (profileIdeal != null && profileIdeal > 0) {
      return profileIdeal;
    }
    return exportAspectRatio == '9:16' ? 24 : 38;
  }

  double _weakScoreThreshold(double average) {
    return average <= 0 ? 0 : (average * 0.68).clamp(4.5, 8.0).toDouble();
  }

  HighlightSegment _directorSegment(HighlightSegment segment) {
    return segment.copyWith(
      source: segment.source.contains('director')
          ? segment.source
          : '${segment.source}+director',
    );
  }

  List<HighlightSegment> _buildReferenceStyleVariant() {
    final profile = activeStyleProfile;
    final targetMax = profile?.targetSegmentSecondsMax ?? 52.0;
    final targetTotal = profile?.preferShortsStructure == true ? 75.0 : 240.0;
    final ranked = [...segments]
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.order.compareTo(b.order);
      });
    final selected = <HighlightSegment>[];
    var total = 0.0;
    for (final segment in ranked) {
      if (selected.isNotEmpty && total >= targetTotal) {
        break;
      }
      final fitted = _referenceStyleSegment(segment, targetMax);
      selected.add(fitted);
      total += fitted.outputDuration;
    }
    if (selected.isEmpty) {
      selected.addAll(
        segments.map((segment) => _referenceStyleSegment(segment, targetMax)),
      );
    }
    selected.sort((a, b) => a.start.compareTo(b.start));
    return _reorderSegments(selected);
  }

  HighlightSegment _referenceStyleSegment(
    HighlightSegment segment,
    double targetMax,
  ) {
    var start = segment.start;
    var end = segment.end;
    if (segment.duration > targetMax && targetMax >= 6.0) {
      end = _snapToFrame(_clampProjectTime(start + targetMax));
    }
    return segment.copyWith(
      start: start,
      end: end,
      audioStart: segment.audioLinked ? start : segment.audioStart,
      audioEnd: segment.audioLinked ? end : segment.audioEnd,
      videoFadeIn: segment.videoFadeIn == 0 ? 0.06 : segment.videoFadeIn,
      videoFadeOut: segment.videoFadeOut == 0 ? 0.10 : segment.videoFadeOut,
      audioFadeIn: segment.audioFadeIn == 0 ? 0.08 : segment.audioFadeIn,
      audioFadeOut: segment.audioFadeOut == 0 ? 0.16 : segment.audioFadeOut,
      audioNormalize: !segment.audioMuted,
      audioPan: 0,
      colorContrast: segment.colorContrast == 1 ? 1.05 : segment.colorContrast,
      source: _appendSource(segment.source, 'reference'),
      tags: [...segment.tags, if (!segment.tags.contains('레퍼런스적용')) '레퍼런스적용'],
    );
  }

  String _appendSource(String source, String suffix) {
    return source.contains(suffix) ? source : '$source+$suffix';
  }

  List<Map<String, dynamic>> _serializeShortsCandidates(
    List<ShortsCandidate> input,
  ) {
    return [
      for (final candidate in input)
        {
          'id': candidate.id,
          'label': candidate.label,
          'reason': candidate.reason,
          'segments': candidate.segments
              .map((segment) => segment.toJson())
              .toList(),
          'strategy_kind': candidate.strategyKind,
          'strategy_label': candidate.strategyLabel,
          'quality_score': candidate.qualityScore,
          'quality_grade': candidate.qualityGrade,
          'risk_count': candidate.riskCount,
          'strengths': candidate.strengths,
          'issues': candidate.issues,
          'story_flow': candidate.storyFlow,
          'story_score': candidate.storyScore,
          'selected': candidate.selected,
        },
    ];
  }

  List<ShortsCandidate> _shortsCandidatesFromProject(ProjectState project) {
    final restored = <ShortsCandidate>[];
    for (final raw in project.shortsCandidates) {
      final rawSegments = raw['segments'] as List<dynamic>? ?? const [];
      final candidateSegments = <HighlightSegment>[];
      for (final rawSegment in rawSegments) {
        if (rawSegment is! Map) {
          continue;
        }
        try {
          candidateSegments.add(
            HighlightSegment.fromJson(Map<String, dynamic>.from(rawSegment)),
          );
        } catch (_) {
          continue;
        }
      }
      final fallbackId = restored.length + 1;
      final id = _intFromProjectJson(
        raw['id'],
        fallbackId,
      ).clamp(1, 9999).toInt();
      var candidate = ShortsCandidate(
        id: id,
        label: _stringFromProjectJson(
          raw['label'],
          'Shorts ${id.toString().padLeft(2, '0')}',
        ),
        reason: _stringFromProjectJson(raw['reason'], ''),
        segments: _reorderSegments(candidateSegments),
        strategyKind: _stringFromProjectJson(
          raw['strategy_kind'] ?? raw['strategyKind'],
          'balanced',
        ),
        strategyLabel: _stringFromProjectJson(
          raw['strategy_label'] ?? raw['strategyLabel'],
          'Balanced',
        ),
        qualityScore: _doubleFromProjectJson(
          raw['quality_score'] ?? raw['qualityScore'],
          0,
        ),
        qualityGrade: _stringFromProjectJson(
          raw['quality_grade'] ?? raw['qualityGrade'],
          'C',
        ),
        riskCount: _intFromProjectJson(
          raw['risk_count'] ?? raw['riskCount'],
          0,
        ),
        strengths: _stringListFromProjectJson(raw['strengths']),
        issues: _stringListFromProjectJson(raw['issues']),
        storyFlow: _stringListFromProjectJson(
          raw['story_flow'] ?? raw['storyFlow'],
        ),
        storyScore: _doubleFromProjectJson(
          raw['story_score'] ?? raw['storyScore'],
          0,
        ),
        selected: raw['selected'] as bool? ?? true,
      );
      if (candidate.qualityScore <= 0 && candidate.segments.isNotEmpty) {
        candidate = _scoreShortsCandidate(candidate);
      }
      restored.add(candidate);
    }
    return restored;
  }

  String _stringFromProjectJson(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return fallback;
  }

  double _doubleFromProjectJson(Object? value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  int _intFromProjectJson(Object? value, int fallback) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  List<String> _stringListFromProjectJson(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  ShortsCandidate? _shortsCandidateById(int id) {
    for (final candidate in shortsCandidates) {
      if (candidate.id == id) {
        return candidate;
      }
    }
    return null;
  }

  List<HighlightSegment> _buildShortsGroup(
    HighlightSegment seed,
    Set<int> used, {
    required double minSeconds,
    required double maxSeconds,
  }) {
    final neighbors =
        segments.where((segment) => !used.contains(segment.order)).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final seedIndex = neighbors.indexWhere(
      (segment) => segment.order == seed.order,
    );
    if (seedIndex < 0) {
      return const [];
    }
    final group = <HighlightSegment>[seed];
    var total = seed.outputDuration;
    var left = seedIndex - 1;
    var right = seedIndex + 1;
    while (total < minSeconds && (left >= 0 || right < neighbors.length)) {
      HighlightSegment? next;
      if (right < neighbors.length) {
        next = neighbors[right++];
      } else if (left >= 0) {
        next = neighbors[left--];
      }
      if (next == null || used.contains(next.order)) {
        continue;
      }
      if (group.isNotEmpty && total + next.outputDuration > maxSeconds) {
        continue;
      }
      group.add(next);
      total += next.outputDuration;
    }
    group.sort((a, b) => a.start.compareTo(b.start));
    return group;
  }

  String _shortsReason(
    List<HighlightSegment> input, {
    double? score,
    int riskCount = 0,
  }) {
    final tags = <String>{};
    for (final segment in input) {
      tags.addAll(segment.tags.take(3));
    }
    final tagText = tags.take(3).join(', ');
    final durationText = input
        .fold<double>(0, (total, segment) => total + segment.outputDuration)
        .round();
    final scoreText = score == null ? '' : ' · Q${score.round()}';
    final riskText = riskCount <= 0 ? '' : ' · Risk $riskCount';
    return tagText.isEmpty
        ? '${durationText}s 쇼츠 후보$scoreText$riskText'
        : '${durationText}s · $tagText$scoreText$riskText';
  }

  void _loadShortsCandidateToTimeline(ShortsCandidate candidate) {
    _commitHistory();
    segments = _reorderSegments(List<HighlightSegment>.of(candidate.segments));
    selectedSegmentOrder = segments.isEmpty ? null : segments.first.order;
    exportAspectRatio = '9:16';
    includeCaptions = true;
    captionStylePreset = 'shorts';
    renderUrl = null;
  }

  HighlightSegment? _segmentForEditAt(
    double seconds, {
    bool requireInside = true,
  }) {
    final selected = selectedSegment;
    if (selected != null) {
      final insideSelected =
          seconds >= selected.start && seconds <= selected.end;
      if (!requireInside || insideSelected) {
        return selected;
      }
    }
    for (final segment in segments) {
      if (seconds >= segment.start && seconds <= segment.end) {
        selectedSegmentOrder = segment.order;
        return segment;
      }
    }
    return requireInside ? null : selected;
  }

  bool _sameCaptionEnabledState(
    List<CaptionSegment> next,
    List<CaptionSegment> current,
  ) {
    if (next.length != current.length) {
      return false;
    }
    for (var index = 0; index < next.length; index++) {
      if (next[index].enabled != current[index].enabled) {
        return false;
      }
    }
    return true;
  }

  void _applyProject(
    ProjectState project, {
    required bool keepJob,
    bool resetHistory = true,
  }) {
    projectName = project.name;
    if (!keepJob && project.jobId != null) {
      jobId = project.jobId;
    }
    duration = project.duration;
    _manualPlayheadSeconds = 0;
    segments = _reorderSegments(project.segments);
    captions = [
      for (var index = 0; index < project.captions.length; index++)
        project.captions[index].copyWith(order: index + 1),
    ];
    waveform = project.waveform;
    timelineMarkers = _normalizeTimelineMarkers(project.timelineMarkers);
    comparisonDefaultSegments = [];
    comparisonReferenceSegments = [];
    comparisonSelection = 'current';
    shortsCandidates = _shortsCandidatesFromProject(project);
    selectedShortsId =
        shortsCandidates.any(
          (candidate) => candidate.id == project.selectedShortsId,
        )
        ? project.selectedShortsId
        : shortsCandidates.isEmpty
        ? null
        : shortsCandidates.first.id;
    includeCaptions = project.includeCaptions;
    captionStylePreset = project.captionStylePreset;
    exportAspectRatio = project.exportAspectRatio;
    markIn = project.markIn;
    markOut = project.markOut;
    selectedSegmentOrder = segments.isEmpty ? null : segments.first.order;
    renderUrl = null;
    if (resetHistory) {
      _clearHistory();
    }
  }

  _EditorSnapshot _captureSnapshot() {
    return _EditorSnapshot(
      segments: List<HighlightSegment>.of(segments),
      captions: List<CaptionSegment>.of(captions),
      timelineMarkers: List<TimelineMarker>.of(timelineMarkers),
      selectedSegmentOrder: selectedSegmentOrder,
      markIn: markIn,
      markOut: markOut,
      includeCaptions: includeCaptions,
      captionStylePreset: captionStylePreset,
      exportAspectRatio: exportAspectRatio,
    );
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    segments = _reorderSegments(snapshot.segments);
    captions = [
      for (var index = 0; index < snapshot.captions.length; index++)
        snapshot.captions[index].copyWith(order: index + 1),
    ];
    selectedSegmentOrder = snapshot.selectedSegmentOrder;
    if (selectedSegmentOrder != null &&
        !segments.any((segment) => segment.order == selectedSegmentOrder)) {
      selectedSegmentOrder = segments.isEmpty ? null : segments.first.order;
    }
    markIn = snapshot.markIn;
    markOut = snapshot.markOut;
    timelineMarkers = _normalizeTimelineMarkers(snapshot.timelineMarkers);
    includeCaptions = snapshot.includeCaptions;
    captionStylePreset = snapshot.captionStylePreset;
    exportAspectRatio = snapshot.exportAspectRatio;
  }

  void _commitHistory() {
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  void _loadDemoProject() {
    projectName = 'AI Director Demo';
    duration = 600;
    activeStyleProfile = const StyleProfile(
      styleId: 'demo-style',
      name: 'Company Reference Style',
      status: 'ready',
      message: 'Demo reference profile',
      progress: 100,
      sourceCount: 6,
      readySourceCount: 6,
      pace: 'fast',
      averageCutSeconds: 4.2,
      hookWindowSeconds: 11.0,
      silenceAggressiveness: 0.82,
      visualChangeSensitivity: 0.68,
      targetSegmentSecondsMin: 12,
      targetSegmentSecondsIdeal: 24,
      targetSegmentSecondsMax: 38,
      preferNewsStructure: true,
      preferShortsStructure: false,
      transitionStyle: 'hard_cut',
      scoringWeights: {'hook': 1.4, 'style_duration': 1.2},
      sources: [
        StyleReferenceSource(
          label: 'company_ref_01.mp4',
          kind: 'file',
          duration: 600,
          sceneCount: 143,
          averageCutSeconds: 4.2,
          silenceRatio: 0.09,
        ),
      ],
    );
    segments = const [
      HighlightSegment(
        order: 1,
        start: 18,
        end: 52,
        reason: '초반 후킹과 문제 제시가 명확함',
        script: '결과부터 보여드리면 이 문제는 세 가지 실수에서 시작됩니다',
        source: 'skill-engine',
        videoFadeIn: 0.1,
        videoFadeOut: 0.2,
        colorContrast: 1.06,
        colorSaturation: 1.04,
        audioPan: -0.15,
        audioNormalize: true,
        score: 9.2,
        tags: ['유지율', '문제해결', '구체성'],
      ),
      HighlightSegment(
        order: 2,
        start: 118,
        end: 162,
        reason: '핵심 원인과 해결 순서가 이어짐',
        script: '핵심은 먼저 원인을 확인하고 그 다음 해결 순서를 적용하는 것입니다',
        source: 'skill-engine',
        videoFadeIn: 0.1,
        videoFadeOut: 0.2,
        colorContrast: 1.06,
        audioPan: 0.2,
        audioNormalize: true,
        score: 8.7,
        tags: ['핵심', '전환'],
      ),
      HighlightSegment(
        order: 3,
        start: 244,
        end: 286,
        reason: '구체적인 숫자와 비교가 포함됨',
        script: '첫 번째 방법과 두 번째 방법의 차이는 실제로 30퍼센트 정도입니다',
        source: 'skill-engine',
        videoEnabled: false,
        score: 7.9,
        tags: ['구체성', '비교'],
      ),
      HighlightSegment(
        order: 4,
        start: 384,
        end: 418,
        reason: '반복 인사와 CTA 성격이 강함',
        script: '음 이제 구독 좋아요 알림도 부탁드립니다',
        source: 'skill-engine',
        score: 2.8,
        tags: ['CTA'],
      ),
    ];
    captions = const [
      CaptionSegment(order: 1, start: 18, end: 23, text: '결과부터 보여드리면'),
      CaptionSegment(
        order: 2,
        start: 23,
        end: 31,
        text: '이 문제는 세 가지 실수에서 시작됩니다',
      ),
      CaptionSegment(
        order: 3,
        start: 118,
        end: 126,
        text: '핵심은 먼저 원인을 확인하는 것입니다',
      ),
      CaptionSegment(
        order: 4,
        start: 384,
        end: 389,
        text: '음 이제 구독 좋아요 부탁드립니다',
      ),
    ];
    waveform = [
      for (var index = 0; index < 180; index++) ((index % 13) + 4) / 17,
    ];
    timelineMarkers = const [
      TimelineMarker(
        id: 1,
        seconds: 18,
        label: 'Hook',
        color: 'cyan',
        note: '초반 유지율 검토 지점',
      ),
      TimelineMarker(
        id: 2,
        seconds: 118,
        label: 'Evidence',
        color: 'green',
        note: '핵심 근거 시작',
      ),
      TimelineMarker(
        id: 3,
        seconds: 384,
        label: 'Review',
        color: 'rose',
        note: 'CTA 또는 삭제 후보',
      ),
    ];
    selectedSegmentOrder = 1;
  }

  String _safeProjectFileName() {
    final base = projectName.trim().isEmpty ? 'autoedit_project' : projectName;
    return base.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stylePollTimer?.cancel();
    videoController?.dispose();
    unawaited(_engineService.dispose());
    super.dispose();
  }
}

enum EditorialCheckStatus { pass, warn, block }

class EditorialCheckItem {
  const EditorialCheckItem({
    required this.label,
    required this.detail,
    required this.status,
  });

  final String label;
  final String detail;
  final EditorialCheckStatus status;
}

class RenderSafetyItem {
  const RenderSafetyItem({
    required this.label,
    required this.detail,
    required this.status,
    this.segmentOrder,
  });

  final String label;
  final String detail;
  final EditorialCheckStatus status;
  final int? segmentOrder;
}

enum AutoFixSeverity { block, warn, polish }

enum AutoFixAction {
  restoreVideo,
  enableAudioPair,
  padContext,
  trimLongClip,
  removeWeak,
  mixAudio,
  addFades,
  hideFiller,
  selectForReview,
}

class AutoFixReviewItem {
  const AutoFixReviewItem({
    required this.segmentOrder,
    required this.title,
    required this.detail,
    required this.severity,
    required this.action,
  });

  final int segmentOrder;
  final String title;
  final String detail;
  final AutoFixSeverity severity;
  final AutoFixAction action;
}

class _ShortsBuildStrategy {
  const _ShortsBuildStrategy({
    required this.kind,
    required this.label,
    required this.maxCandidates,
  });

  final String kind;
  final String label;
  final int maxCandidates;
}

class ShortsCandidate {
  const ShortsCandidate({
    required this.id,
    required this.label,
    required this.reason,
    required this.segments,
    this.strategyKind = 'balanced',
    this.strategyLabel = 'Balanced',
    this.qualityScore = 0,
    this.qualityGrade = 'C',
    this.riskCount = 0,
    this.strengths = const [],
    this.issues = const [],
    this.storyFlow = const [],
    this.storyScore = 0,
    this.selected = true,
  });

  final int id;
  final String label;
  final String reason;
  final List<HighlightSegment> segments;
  final String strategyKind;
  final String strategyLabel;
  final double qualityScore;
  final String qualityGrade;
  final int riskCount;
  final List<String> strengths;
  final List<String> issues;
  final List<String> storyFlow;
  final double storyScore;
  final bool selected;

  double get durationSeconds => segments.fold<double>(
    0,
    (total, segment) => total + segment.outputDuration,
  );

  bool get hasSeriousReviewIssue =>
      riskCount > 0 ||
      issues.contains('Risk review') ||
      issues.contains('Offline review');

  bool get isPublishReady =>
      qualityScore >= 70 &&
      storyScore >= 58 &&
      !hasSeriousReviewIssue &&
      !issues.contains('Story flow') &&
      !issues.contains('Audio mix');

  bool get needsEditorialReview =>
      !isPublishReady && qualityScore >= 55 && !issues.contains('No clips');

  String get readinessLabel {
    if (isPublishReady) {
      return 'Ready';
    }
    if (needsEditorialReview) {
      return 'Review';
    }
    return 'Hold';
  }

  String get readinessDetail {
    if (isPublishReady) {
      return '기본 렌더 선택 가능';
    }
    if (hasSeriousReviewIssue) {
      return '사실 확인 또는 원본 검수 필요';
    }
    if (issues.isNotEmpty) {
      return issues.first;
    }
    return '점수 보강 필요';
  }

  ShortsCandidate copyWith({
    int? id,
    String? label,
    String? reason,
    List<HighlightSegment>? segments,
    String? strategyKind,
    String? strategyLabel,
    double? qualityScore,
    String? qualityGrade,
    int? riskCount,
    List<String>? strengths,
    List<String>? issues,
    List<String>? storyFlow,
    double? storyScore,
    bool? selected,
  }) {
    return ShortsCandidate(
      id: id ?? this.id,
      label: label ?? this.label,
      reason: reason ?? this.reason,
      segments: segments ?? this.segments,
      strategyKind: strategyKind ?? this.strategyKind,
      strategyLabel: strategyLabel ?? this.strategyLabel,
      qualityScore: qualityScore ?? this.qualityScore,
      qualityGrade: qualityGrade ?? this.qualityGrade,
      riskCount: riskCount ?? this.riskCount,
      strengths: strengths ?? this.strengths,
      issues: issues ?? this.issues,
      storyFlow: storyFlow ?? this.storyFlow,
      storyScore: storyScore ?? this.storyScore,
      selected: selected ?? this.selected,
    );
  }
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.segments,
    required this.captions,
    required this.timelineMarkers,
    required this.selectedSegmentOrder,
    required this.markIn,
    required this.markOut,
    required this.includeCaptions,
    required this.captionStylePreset,
    required this.exportAspectRatio,
  });

  final List<HighlightSegment> segments;
  final List<CaptionSegment> captions;
  final List<TimelineMarker> timelineMarkers;
  final int? selectedSegmentOrder;
  final double? markIn;
  final double? markOut;
  final bool includeCaptions;
  final String captionStylePreset;
  final String exportAspectRatio;
}
