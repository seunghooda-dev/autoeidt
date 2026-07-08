import 'dart:async';
import 'dart:convert';

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
  bool isProbingMedia = false;
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

  int get selectedShortsCount =>
      shortsCandidates.where((candidate) => candidate.selected).length;
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
      !isRendering &&
      job?.status != 'processing' &&
      job?.status != 'rendering';
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isRazorTool => timelineTool == 'razor';
  String get timelineToolLabel => isRazorTool ? 'Razor C' : 'Selection V';
  bool get allAudioMuted =>
      segments.isNotEmpty && segments.every((segment) => segment.audioMuted);
  bool get hasValidMarks =>
      markIn != null &&
      markOut != null &&
      markOut! - markIn! >= timecodeFrameDurationSeconds;
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
    ];
  }

  int get editorialBlockCount => editorialChecklist
      .where((item) => item.status == EditorialCheckStatus.block)
      .length;

  int get editorialWarnCount => editorialChecklist
      .where((item) => item.status == EditorialCheckStatus.warn)
      .length;

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
        await _initializePreview(response.jobId);
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
    final output = <ShortsCandidate>[];
    final used = <int>{};
    var nextId = 1;
    for (final seed in ranked) {
      if (output.length >= maxCandidates) {
        break;
      }
      if (used.contains(seed.order) || seed.score > 0 && seed.score < 4.5) {
        continue;
      }
      final group = _buildShortsGroup(
        seed,
        used,
        minSeconds: minSeconds,
        maxSeconds: maxSeconds,
      );
      if (group.isEmpty) {
        continue;
      }
      for (final segment in group) {
        used.add(segment.order);
      }
      final normalized = _reorderSegments([
        for (final segment in group)
          _referenceStyleSegment(
            segment,
            maxSeconds,
          ).copyWith(source: _appendSource(segment.source, 'shorts')),
      ]);
      output.add(
        ShortsCandidate(
          id: nextId,
          label: 'Shorts ${nextId.toString().padLeft(2, '0')}',
          reason: _shortsReason(normalized),
          segments: normalized,
          selected: true,
        ),
      );
      nextId += 1;
    }
    if (output.isEmpty) {
      output.add(
        ShortsCandidate(
          id: 1,
          label: 'Shorts 01',
          reason: '현재 타임라인 기반 기본 쇼츠 후보',
          segments: _reorderSegments(segments.take(4).toList()),
          selected: true,
        ),
      );
    }
    shortsCandidates = output;
    selectedShortsId = output.first.id;
    _loadShortsCandidateToTimeline(output.first);
    notifyListeners();
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
          candidate.copyWith(
            segments: _reorderSegments(List<HighlightSegment>.of(segments)),
            reason: _shortsReason(segments),
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
      source.copyWith(
        id: nextId,
        label: 'Shorts ${nextId.toString().padLeft(2, '0')}',
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
    isRendering = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _apiClient.requestBatchRender(
        id,
        [
          for (var index = 0; index < selected.length; index++)
            {
              'label': selected[index].label,
              'output_name':
                  'shorts_${(index + 1).toString().padLeft(2, '0')}.mp4',
              'segments': selected[index].segments
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

  double _clampTime(double value) => value.clamp(0.0, duration).toDouble();

  double _snapToFrame(double value) => snapSecondsToFrame(value);

  double _clampProjectTime(double value) {
    if (duration <= 0) {
      return value < 0 ? 0 : value;
    }
    return value.clamp(0.0, duration).toDouble();
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
    final normalizedSegment = segment.copyWith(
      start: start,
      end: end,
      playbackSpeed: playbackSpeed,
      colorBrightness: colorBrightness,
      colorContrast: colorContrast,
      colorSaturation: colorSaturation,
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

  String _shortsReason(List<HighlightSegment> input) {
    final tags = <String>{};
    for (final segment in input) {
      tags.addAll(segment.tags.take(3));
    }
    final tagText = tags.take(3).join(', ');
    final durationText = input
        .fold<double>(0, (total, segment) => total + segment.outputDuration)
        .round();
    return tagText.isEmpty
        ? '${durationText}s 쇼츠 후보'
        : '${durationText}s · $tagText';
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
    segments = _reorderSegments(project.segments);
    captions = [
      for (var index = 0; index < project.captions.length; index++)
        project.captions[index].copyWith(order: index + 1),
    ];
    waveform = project.waveform;
    comparisonDefaultSegments = [];
    comparisonReferenceSegments = [];
    comparisonSelection = 'current';
    shortsCandidates = [];
    selectedShortsId = null;
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

class ShortsCandidate {
  const ShortsCandidate({
    required this.id,
    required this.label,
    required this.reason,
    required this.segments,
    this.selected = true,
  });

  final int id;
  final String label;
  final String reason;
  final List<HighlightSegment> segments;
  final bool selected;

  double get durationSeconds => segments.fold<double>(
    0,
    (total, segment) => total + segment.outputDuration,
  );

  ShortsCandidate copyWith({
    int? id,
    String? label,
    String? reason,
    List<HighlightSegment>? segments,
    bool? selected,
  }) {
    return ShortsCandidate(
      id: id ?? this.id,
      label: label ?? this.label,
      reason: reason ?? this.reason,
      segments: segments ?? this.segments,
      selected: selected ?? this.selected,
    );
  }
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.segments,
    required this.captions,
    required this.selectedSegmentOrder,
    required this.markIn,
    required this.markOut,
    required this.includeCaptions,
    required this.captionStylePreset,
    required this.exportAspectRatio,
  });

  final List<HighlightSegment> segments;
  final List<CaptionSegment> captions;
  final int? selectedSegmentOrder;
  final double? markIn;
  final double? markOut;
  final bool includeCaptions;
  final String captionStylePreset;
  final String exportAspectRatio;
}
