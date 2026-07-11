import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../models/highlight_segment.dart';
import '../models/job_models.dart';
import '../services/api_client.dart';
import '../services/local_engine_service.dart';
import '../services/project_recovery_service.dart';
import '../services/reusable_media_kit_video_player.dart';
import '../utils/timecode.dart';

class EditorController extends ChangeNotifier {
  EditorController({
    ApiClient? apiClient,
    LocalEngineService? engineService,
    bool autoStartEngine = true,
    bool? enableTimelineThumbnails,
    ProjectRecoveryService? recoveryService,
    bool enableProjectRecovery = false,
    bool autoRestoreRecovery = false,
    Duration projectRecoveryDebounce = const Duration(milliseconds: 800),
    Duration proxyPreviewInitializationTimeout = const Duration(seconds: 8),
    Duration proxyPreviewRecoveryTimeout = const Duration(seconds: 20),
    double seekProxyPreviewSeconds = 10,
  }) : _apiClient = apiClient ?? ApiClient(),
       _engineService = engineService ?? LocalEngineService(),
       _recoveryService = recoveryService ?? ProjectRecoveryService(),
       _projectRecoveryEnabled = enableProjectRecovery && !kIsWeb,
       _autoRestoreRecovery = autoRestoreRecovery && !kIsWeb,
       _timelineThumbnailsEnabled =
           (enableTimelineThumbnails ?? autoStartEngine) && !kIsWeb,
       _projectRecoveryDebounce = projectRecoveryDebounce,
       _proxyPreviewInitializationTimeout = proxyPreviewInitializationTimeout,
       _proxyPreviewRecoveryTimeout = proxyPreviewRecoveryTimeout,
       _seekProxyPreviewSeconds = seekProxyPreviewSeconds
           .clamp(8.0, 30.0)
           .toDouble() {
    if (_demoMode) {
      _loadDemoProject();
    } else if (autoStartEngine) {
      unawaited(ensureLocalEngine());
    }
    if (_projectRecoveryEnabled) {
      final initialization = _initializeRecoverySession();
      _recoveryInitialization = initialization;
      unawaited(initialization);
    }
  }

  final ApiClient _apiClient;
  final LocalEngineService _engineService;
  final ProjectRecoveryService _recoveryService;
  final bool _projectRecoveryEnabled;
  final bool _autoRestoreRecovery;
  final bool _timelineThumbnailsEnabled;
  final Duration _projectRecoveryDebounce;
  final Duration _proxyPreviewInitializationTimeout;
  final Duration _proxyPreviewRecoveryTimeout;
  final double _seekProxyPreviewSeconds;
  Timer? _pollTimer;
  Timer? _stylePollTimer;
  Timer? _recoverySaveTimer;
  Future<void>? _recoveryInitialization;
  Timer? _reverseShuttleTimer;
  Timer? _timelineThumbnailTimer;
  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];
  String? _lastRecoveryPayload;
  int _projectRevision = 0;
  int _savedProjectRevision = 0;
  bool _isDisposed = false;

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
  bool isCancellingJob = false;
  bool hasRecoverySnapshot = false;
  DateTime? recoverySnapshotSavedAt;
  List<ProjectRecoverySnapshot> recoveryVersions = [];
  bool isInitializingRecoverySession = false;
  bool hasInitializedRecoverySession = false;
  bool didAutoRestoreSession = false;
  bool recoveryRequiresManualRestore = false;
  List<RecentJobSummary> recentJobs = [];
  bool isLoadingRecentJobs = false;
  bool isOpeningRecentJob = false;
  String? recentJobsError;
  String? errorMessage;
  double duration = 0;
  List<HighlightSegment> segments = [];
  List<VideoOverlayClip> videoOverlays = [];
  List<AudioClip> audioClips = [];
  List<TranscriptSegment> transcript = [];
  List<CaptionSegment> captions = [];
  List<double> waveform = [];
  Map<int, ui.Image> timelineThumbnails = const {};
  bool isLoadingTimelineThumbnails = false;
  int timelineThumbnailTargetCount = 0;
  List<TimelineMarker> timelineMarkers = [];
  String? renderUrl;
  int? selectedSegmentOrder;
  String? selectedVideoOverlayId;
  String? selectedAudioClipId;
  double? markIn;
  double? markOut;
  bool includeCaptions = true;
  String captionStylePreset = 'news';
  String exportAspectRatio = '16:9';
  List<String> selectedExportProfiles = ['16:9'];
  double timelineZoom = 1.0;
  double timelineTrackHeightScale = 1.0;
  bool timelineSnappingEnabled = true;
  String timelineTool = 'selection';
  bool videoTrackTargeted = true;
  bool videoOverlayTrackTargeted = false;
  bool audioTrack1Targeted = true;
  bool audioTrack2Targeted = true;
  bool audioTrack3Targeted = true;
  int activeVideoTrackCount = 2;
  int activeAudioTrackCount = 3;
  int targetedVideoOverlayTrack = 2;
  int targetedOverlayAudioTrack = 3;
  bool videoTrackLocked = false;
  bool videoOverlayTrackLocked = false;
  bool videoOverlayTrackVisible = true;
  bool audioTrackLocked = false;
  bool audioTrack1Locked = false;
  bool audioTrack2Locked = false;
  bool audioTrack3Locked = false;
  String projectName = 'AutoEdit Project';
  String? projectFilePath;
  HighlightSegment? _clipClipboard;
  List<HighlightSegment> comparisonDefaultSegments = [];
  List<HighlightSegment> comparisonReferenceSegments = [];
  String comparisonSelection = 'current';
  List<ShortsCandidate> shortsCandidates = [];
  int? selectedShortsId;
  VideoPlayerController? videoController;
  double _lastNotifiedPosition = -1;
  bool? _lastNotifiedPlaying;
  int _previewRevision = 0;
  int playbackShuttleDirection = 0;
  double playbackShuttleRate = 1.0;
  double previewVolume = 1.0;
  bool previewMuted = false;
  bool isPreparingPreview = false;
  String previewMonitorMode = 'source';
  bool isProbingMedia = false;
  bool isRefreshingStorage = false;
  bool isCleaningStorage = false;
  StorageUsageInfo? storageUsage;
  StorageCleanupInfo? lastStorageCleanup;
  String? storageErrorMessage;
  bool _previewUsesProxy = false;
  bool _previewAutoplayRequested = false;
  bool _proxyContinuationPending = false;
  String? _activeProxyRequestKey;
  Future<void>? _activeProxyRequest;
  double _previewSourceStartSeconds = 0;
  double? _previewSourceDurationSeconds;
  int? _previewProgramSegmentOrder;
  String? _previewProgramSegmentSignature;
  Timer? _programPreviewRefreshTimer;
  String? _programPreviewPrefetchKey;
  Future<LocalPreviewInfo?>? _programPreviewPrefetchFuture;
  double _manualPlayheadSeconds = 0;
  double _programPlayheadSeconds = 0;
  int? _programSegmentOrder;
  bool _programCutPending = false;
  int _timelineThumbnailRevision = 0;
  static const double _initialProxyPreviewSeconds = 8;
  static const double _programPreviewWindowSeconds = 8;
  static const double _programPreviewPreRollSeconds = 2;
  static const Duration _directPreviewInitializationTimeout = Duration(
    milliseconds: 1500,
  );
  static const Duration _previewControllerDisposeTimeout = Duration(seconds: 2);
  static const int _avSyncLengthToleranceFrames = 2;
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
  static const List<String> supportedAudioExtensions = [
    'wav',
    'mp3',
    'aac',
    'flac',
    'm4a',
    'ogg',
    'opus',
    'wma',
  ];
  static const List<String> supportedMediaExtensions = [
    ...supportedVideoExtensions,
    ...supportedAudioExtensions,
  ];

  static bool isAudioMediaPath(String path) {
    final normalized = path.trim().toLowerCase();
    final separator = normalized.lastIndexOf('.');
    if (separator < 0 || separator == normalized.length - 1) {
      return false;
    }
    return supportedAudioExtensions.contains(
      normalized.substring(separator + 1),
    );
  }

  static final RegExp _fillerPattern = RegExp(
    r'(^|\s)(음+|어+|아+|그니까|그러니까|뭐랄까|약간|이제)(\s|$)|you know|um+|uh+',
    caseSensitive: false,
  );
  static final RegExp _riskPattern = RegExp(
    r'루머|카더라|추정|추측|아마도|미확인|확인되지|일각에서는|떠돌|rumor|unconfirmed|allegedly|speculation',
    caseSensitive: false,
  );
  static const Set<String> _newsSignalTags = {
    '뉴스핵심',
    '근거',
    '검증팩트',
    '영향',
    '대응',
    '출처확인',
    '시간축',
    '발언',
    'Story:Evidence',
    'Story:Impact',
    'Story:Resolution',
  };
  static const Set<String> _verificationTags = {
    '근거',
    '검증팩트',
    '출처확인',
    '발언',
    'Story:Evidence',
  };

  bool get hasFile => selectedFile != null;
  String? get sourceMediaPath => selectedFile?.path;
  bool get sourceMediaNeedsRelink {
    if (kIsWeb || selectedFile == null) {
      return false;
    }
    final path = sourceMediaPath;
    return path == null || path.isEmpty || !io.File(path).existsSync();
  }

  bool get sourceMediaIsLinked {
    final path = sourceMediaPath;
    return !kIsWeb &&
        path != null &&
        path.isNotEmpty &&
        io.File(path).existsSync();
  }

  bool get hasTimeline => duration > 0 && segments.isNotEmpty;
  bool get hasTimelineSource => hasTimeline || hasFile;
  bool get canSaveProjectFile => hasFile || hasRecoverableProject;
  bool get hasUnsavedProjectChanges =>
      canSaveProjectFile && _projectRevision != _savedProjectRevision;
  String get projectTitleLabel =>
      '$projectName${hasUnsavedProjectChanges ? ' *' : ''}';
  String get projectFileLabel {
    final path = projectFilePath;
    if (path == null || path.isEmpty) {
      return hasUnsavedProjectChanges ? 'Unsaved project' : 'Project not saved';
    }
    return io.File(path).uri.pathSegments.last;
  }

  double get timelineSourceDuration {
    if (duration > 0) {
      return duration;
    }
    final probeDuration = selectedMediaProbe?.duration ?? 0;
    return probeDuration > 0 ? probeDuration : 0;
  }

  bool get hasActiveJob {
    final status = job?.status;
    return isRendering ||
        status == 'queued' ||
        status == 'processing' ||
        status == 'rendering';
  }

  bool get canCancelJob => jobId != null && hasActiveJob && !isCancellingJob;
  bool get canStartUpload =>
      hasFile &&
      !isUploading &&
      !isProbingMedia &&
      selectedMediaProbe?.canAnalyze != false &&
      !hasActiveJob &&
      !isCancellingJob;
  bool get hasReadyStyle => activeStyleProfile?.isReady ?? false;
  bool get hasComparisonVariants =>
      comparisonDefaultSegments.isNotEmpty &&
      comparisonReferenceSegments.isNotEmpty;
  bool get hasShortsCandidates => shortsCandidates.isNotEmpty;
  bool get hasTimelineMarkers => timelineMarkers.isNotEmpty;
  bool get canBuildTimelineFromMarkers =>
      _timelineMarkerRanges(enabledOnly: true).isNotEmpty;
  bool get canJumpToNextTimelineMarker {
    if (isProgramMonitor) {
      final threshold =
          _programPlayheadSeconds + timecodeFrameDurationSeconds / 2;
      return timelineMarkers.any((marker) {
        final position = programPositionForSourceTime(marker.seconds);
        return position != null && position > threshold;
      });
    }
    return _nextTimelineMarkerFrom(currentPositionSeconds) != null;
  }

  bool get canJumpToPreviousTimelineMarker {
    if (isProgramMonitor) {
      final threshold =
          _programPlayheadSeconds - timecodeFrameDurationSeconds / 2;
      return timelineMarkers.any((marker) {
        final position = programPositionForSourceTime(marker.seconds);
        return position != null && position < threshold;
      });
    }
    return _previousTimelineMarkerFrom(currentPositionSeconds) != null;
  }

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
              aspectRatio: item.aspectRatio,
              path: item.path,
              durationSeconds: item.durationSeconds,
              sizeBytes: item.sizeBytes,
              warnings: item.warnings,
            ),
        for (final item in job?.renderManifestItems ?? const [])
          if (item.url.isNotEmpty)
            BatchRenderItemResult(
              label: item.label,
              outputName: item.outputName.isEmpty
                  ? _outputNameFromUrl(item.url)
                  : item.outputName,
              url: _apiClient.absoluteUrl(item.url),
              kind: item.kind,
              aspectRatio: item.aspectRatio,
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
  List<ShortsExportQueueItem> get selectedShortsExportQueue {
    final selected = shortsCandidates
        .where(
          (candidate) => candidate.selected && candidate.segments.isNotEmpty,
        )
        .toList();
    return [
      for (var index = 0; index < selected.length; index++)
        _buildShortsExportQueueItem(selected[index], index),
    ];
  }

  double get selectedShortsExportDurationSeconds => selectedShortsExportQueue
      .fold<double>(0, (total, item) => total + item.durationSeconds);
  int get selectedShortsExportReadyCount =>
      selectedShortsExportQueue.where((item) => item.canRender).length;
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
  Set<String> get selectedExportProfileSet => selectedExportProfiles.toSet();
  bool get hasMultiFormatExport => selectedExportProfiles.length > 1;
  String get exportProfilesLabel {
    if (selectedExportProfiles.isEmpty) {
      return 'No export profile';
    }
    return selectedExportProfiles.map(_exportProfileLabel).join(' + ');
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  List<EditorHistoryPoint> get editorHistoryPoints {
    final points = <EditorHistoryPoint>[
      EditorHistoryPoint(
        depth: 0,
        label: 'Current timeline',
        detail: '${segments.length} clips · ${captions.length} captions',
        createdAt: DateTime.now(),
        isCurrent: true,
      ),
    ];
    for (var index = _undoStack.length - 1; index >= 0; index--) {
      final snapshot = _undoStack[index];
      points.add(
        EditorHistoryPoint(
          depth: _undoStack.length - index,
          label: 'Edit ${index + 1}',
          detail:
              '${snapshot.segments.length} clips · '
              '${snapshot.captions.length} captions · '
              '${snapshot.timelineMarkers.length} markers',
          createdAt: snapshot.createdAt,
        ),
      );
    }
    return points;
  }

  bool get hasRecoverableProject =>
      jobId != null ||
      duration > 0 ||
      segments.isNotEmpty ||
      captions.isNotEmpty ||
      waveform.isNotEmpty ||
      timelineMarkers.isNotEmpty ||
      shortsCandidates.isNotEmpty ||
      markIn != null ||
      markOut != null;
  bool get isRazorTool => timelineTool == 'razor';
  String get timelineToolLabel => isRazorTool ? 'Razor C' : 'Selection V';
  String get timelineSnappingLabel =>
      timelineSnappingEnabled ? 'Snap S' : 'Snap Off';
  String get timelineTrackHeightLabel {
    if (timelineTrackHeightScale < 0.9) {
      return 'Tracks Compact';
    }
    if (timelineTrackHeightScale > 1.1) {
      return 'Tracks Tall';
    }
    return 'Tracks Normal';
  }

  bool get canDecreaseTimelineTrackHeight => timelineTrackHeightScale > 0.8;
  bool get canIncreaseTimelineTrackHeight => timelineTrackHeightScale < 1.25;
  String get playbackShuttleLabel {
    if (playbackShuttleDirection < 0) {
      return 'J ${playbackShuttleRate.toStringAsFixed(0)}x';
    }
    if (playbackShuttleDirection > 0) {
      return 'L ${playbackShuttleRate.toStringAsFixed(0)}x';
    }
    return 'K Stop';
  }

  bool get hasAnyTrackTarget =>
      videoTrackTargeted || audioTrack1Targeted || audioTrack2Targeted;
  bool get hasClipClipboard => _clipClipboard != null;
  String get clipClipboardLabel {
    final clip = _clipClipboard;
    if (clip == null) {
      return 'Clipboard empty';
    }
    return 'C${clip.order} ${formatSeconds(clip.start)}-${formatSeconds(clip.end)}';
  }

  bool get allTrackTargetsEnabled =>
      videoTrackTargeted && audioTrack1Targeted && audioTrack2Targeted;
  bool get audioTrack1EditLocked => audioTrackLocked || audioTrack1Locked;
  bool get audioTrack2EditLocked => audioTrackLocked || audioTrack2Locked;
  bool get anyAudioTrackEditLocked =>
      audioTrackLocked || audioTrack1Locked || audioTrack2Locked;
  bool get allAudioTracksEditLocked =>
      audioTrackLocked || audioTrack1Locked && audioTrack2Locked;
  String get audioTrackLockLabel {
    if (allAudioTracksEditLocked) {
      return 'A1/A2 Locked';
    }
    if (audioTrack1Locked) {
      return 'A1 Locked';
    }
    if (audioTrack2Locked) {
      return 'A2 Locked';
    }
    return 'A1/A2';
  }

  bool get targetedTracksUnlocked =>
      (!videoTrackTargeted || !videoTrackLocked) &&
      (!audioTrack1Targeted || !audioTrack1EditLocked) &&
      (!audioTrack2Targeted || !audioTrack2EditLocked);
  bool get allAudioMuted =>
      segments.isNotEmpty &&
      segments.every(
        (segment) => segment.audioMuted || !segment.hasActiveAudioChannel,
      );
  bool get allAudioChannel1Enabled =>
      segments.isNotEmpty &&
      segments.every((segment) => segment.audioChannel1Enabled);
  bool get allAudioChannel2Enabled =>
      segments.isNotEmpty &&
      segments.every((segment) => segment.audioChannel2Enabled);
  int get timelineGapCount => segments.where(_segmentIsTimelineGap).length;
  bool get hasTimelineGaps => timelineGapCount > 0;
  bool get selectedSegmentIsTimelineGap {
    final selected = selectedSegment;
    return selected != null && _segmentIsTimelineGap(selected);
  }

  bool get hasValidMarks =>
      markIn != null &&
      markOut != null &&
      markOut! - markIn! >= timecodeFrameDurationSeconds;
  bool get canLiftOrExtractMarkedRange =>
      hasValidMarks &&
      hasAnyTrackTarget &&
      targetedTracksUnlocked &&
      segments.any(
        (segment) => _segmentOverlapsRange(segment, markIn!, markOut!),
      );
  bool get canLiftOrExtractSelectedSegment =>
      selectedSegment != null && hasAnyTrackTarget && targetedTracksUnlocked;
  bool get canInsertMarkedSegment =>
      hasValidMarks && hasAnyTrackTarget && targetedTracksUnlocked;
  bool get canOverwriteMarkedSegment =>
      hasValidMarks &&
      selectedSegment != null &&
      hasAnyTrackTarget &&
      targetedTracksUnlocked;
  bool get canRateStretchSelectedToMarks =>
      selectedSegment != null &&
      hasValidMarks &&
      !videoTrackLocked &&
      !anyAudioTrackEditLocked;
  bool get canAddEditAtPlayhead =>
      hasAnyTrackTarget &&
      targetedTracksUnlocked &&
      _segmentAtTimelinePoint(currentPositionSeconds) != null;
  bool get canAddEditToAllTracksAtPlayhead =>
      !videoTrackLocked &&
      !anyAudioTrackEditLocked &&
      _segmentAtTimelinePoint(currentPositionSeconds) != null;
  double get currentPositionSeconds {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      return _manualPlayheadSeconds;
    }
    final localSeconds = controller.value.position.inMilliseconds / 1000;
    final programSegment = _previewProgramSegment;
    return _previewSourceStartSeconds +
        localSeconds * (programSegment?.playbackSpeed ?? 1.0);
  }

  HighlightSegment? get _previewProgramSegment {
    final order = _previewProgramSegmentOrder;
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

  bool get canUseProgramMonitor => segments.isNotEmpty;
  bool get isProgramMonitor =>
      previewMonitorMode == 'program' && canUseProgramMonitor;
  double get monitorPositionSeconds {
    if (!isProgramMonitor) {
      return currentPositionSeconds;
    }
    final mapped = programPositionForSourceTime(
      currentPositionSeconds,
      preferredOrder: _programSegmentOrder ?? selectedSegmentOrder,
    );
    return (mapped ?? _programPlayheadSeconds)
        .clamp(0.0, outputDurationSeconds)
        .toDouble();
  }

  double get monitorDurationSeconds =>
      isProgramMonitor ? outputDurationSeconds : duration;

  HighlightSegment? get previewActiveSegment {
    if (!isProgramMonitor) {
      return selectedSegment;
    }
    return _programSpanForOrder(_programSegmentOrder)?.segment ??
        _programSpanAt(_programPlayheadSeconds)?.segment ??
        selectedSegment;
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

  VideoOverlayClip? get selectedVideoOverlay {
    final id = selectedVideoOverlayId;
    if (id == null) {
      return null;
    }
    for (final overlay in videoOverlays) {
      if (overlay.id == id) {
        return overlay;
      }
    }
    return null;
  }

  AudioClip? get selectedAudioClip {
    final id = selectedAudioClipId;
    if (id == null) {
      return null;
    }
    for (final clip in audioClips) {
      if (clip.id == id) {
        return clip;
      }
    }
    return null;
  }

  bool get selectedVideoOverlayIsOffline {
    final path = selectedVideoOverlay?.sourcePath;
    return !kIsWeb &&
        path != null &&
        path.isNotEmpty &&
        !io.File(path).existsSync();
  }

  bool get selectedAudioClipIsOffline {
    final path = selectedAudioClip?.sourcePath;
    return !kIsWeb &&
        path != null &&
        path.isNotEmpty &&
        !io.File(path).existsSync();
  }

  bool get videoOverlayAudioEnabled =>
      videoOverlays.any(
        (overlay) => !overlay.muted && overlay.audioVolume > 0,
      ) ||
      audioClips.any((clip) => clip.enabled && !clip.muted && clip.volume > 0);

  double get selectedMotionLocalTime {
    final selected = selectedSegment;
    if (selected == null) {
      return 0;
    }
    final local = isProgramMonitor
        ? monitorPositionSeconds - programStartForSegment(selected.order)
        : (currentPositionSeconds - selected.start) / selected.playbackSpeed;
    return _snapToFrame(local.clamp(0.0, selected.outputDuration).toDouble());
  }

  MotionKeyframe get selectedMotionValues {
    final selected = selectedSegment;
    final time = selectedMotionLocalTime;
    if (selected == null) {
      return MotionKeyframe(
        time: time,
        opacity: 1,
        scale: 1,
        positionX: 0,
        positionY: 0,
        rotation: 0,
      );
    }
    return sampleMotionKeyframes(
      keyframes: selected.motionKeyframes,
      time: time,
      fallback: MotionKeyframe(
        time: time,
        opacity: selected.videoOpacity,
        scale: selected.videoScale,
        positionX: selected.videoPositionX,
        positionY: selected.videoPositionY,
        rotation: selected.videoRotation,
      ),
    );
  }

  int get selectedMotionKeyframeIndex {
    final selected = selectedSegment;
    if (selected == null) {
      return -1;
    }
    final time = selectedMotionLocalTime;
    for (var index = 0; index < selected.motionKeyframes.length; index++) {
      if ((selected.motionKeyframes[index].time - time).abs() <=
          timecodeFrameDurationSeconds / 2 + 0.0001) {
        return index;
      }
    }
    return -1;
  }

  bool get selectedMotionHasKeyframeAtPlayhead =>
      selectedMotionKeyframeIndex >= 0;

  bool get canApplySelectedTransition =>
      selectedSegment != null &&
      selectedSegment!.order > 1 &&
      !videoTrackLocked &&
      !anyAudioTrackEditLocked;
  double get selectedTransitionMaxDuration {
    final selected = selectedSegment;
    if (selected == null || selected.order <= 1) {
      return 0;
    }
    final index = segments.indexWhere(
      (segment) => segment.order == selected.order,
    );
    if (index <= 0) {
      return 0;
    }
    return math
        .min(
          3.0,
          math.min(
            segments[index - 1].outputDuration / 2,
            selected.outputDuration / 2,
          ),
        )
        .clamp(0.0, 3.0)
        .toDouble();
  }

  int audioVideoLengthDriftFrames(HighlightSegment segment) {
    final videoFrames = secondsToTimecodeFrame(segment.duration);
    final audioFrames = secondsToTimecodeFrame(segment.audioDuration);
    return (audioFrames - videoFrames).abs();
  }

  bool segmentHasAudioLengthDrift(HighlightSegment segment) {
    return _segmentAudioReady(segment) &&
        audioVideoLengthDriftFrames(segment) >= _avSyncLengthToleranceFrames;
  }

  bool segmentIsTimelineGap(HighlightSegment segment) {
    return _segmentIsTimelineGap(segment);
  }

  String get previewSourceLabel {
    if (isPreparingPreview) {
      return _previewAutoplayRequested
          ? 'Preview · Play queued'
          : 'Preparing Preview';
    }
    if (videoController == null) {
      return 'No Preview';
    }
    if (isProgramMonitor) {
      final order = previewActiveSegment?.order;
      return order == null ? 'Program Preview' : 'Program Preview · C$order';
    }
    return _previewUsesProxy ? 'Proxy Preview' : 'Source Preview';
  }

  String get previewAudioLabel {
    if (previewMuted || previewVolume <= 0) {
      return 'Muted';
    }
    final audioStreams = selectedMediaProbe?.audioStreamCount;
    final audioChannels = selectedMediaProbe?.audioChannelCount;
    if (audioStreams == null) {
      return 'Audio ${previewVolumePercent.round()}%';
    }
    if (audioStreams <= 0) {
      return 'No source audio';
    }
    if (_previewUsesProxy) {
      return (audioChannels ?? audioStreams) <= 1 ? 'A1 Mono' : 'A1/A2 Program';
    }
    if (audioChannels != null && audioChannels != audioStreams) {
      return '$audioStreams stream / ${audioChannels}ch';
    }
    return audioStreams == 1 ? 'A1 Source' : '$audioStreams audio streams';
  }

  int get sourceAudioChannelCount =>
      math.max(1, selectedMediaProbe?.audioChannelCount ?? 2);

  double get previewVolumePercent => previewMuted ? 0 : previewVolume * 100;
  bool get previewPlaybackQueued => _previewAutoplayRequested;

  double get outputDurationSeconds {
    return sequenceOutputDuration(segments);
  }

  int? programSegmentOrderAt(double programSeconds) {
    return _programSpanAt(programSeconds)?.segment.order;
  }

  double sourceTimeForProgramPosition(double programSeconds) {
    final span = _programSpanAt(programSeconds);
    if (span == null) {
      return 0;
    }
    final localOutput = (programSeconds - span.sequenceStart)
        .clamp(0.0, span.sequenceEnd - span.sequenceStart)
        .toDouble();
    return (span.segment.start + localOutput * span.segment.playbackSpeed)
        .clamp(span.segment.start, span.segment.end)
        .toDouble();
  }

  double programStartForSegment(int order) {
    return _programSpanForOrder(order)?.sequenceStart ?? 0;
  }

  double? programPositionForSourceTime(
    double sourceSeconds, {
    int? preferredOrder,
  }) {
    final preferred = _programSpanForOrder(
      preferredOrder ?? _programSegmentOrder ?? selectedSegmentOrder,
    );
    if (preferred != null &&
        sourceSeconds >= preferred.segment.start &&
        sourceSeconds <= preferred.segment.end) {
      return preferred.sequenceStart +
          (sourceSeconds - preferred.segment.start) /
              math.max(0.1, preferred.segment.playbackSpeed);
    }
    for (final span in _programSpans) {
      final segment = span.segment;
      if (sourceSeconds >= segment.start && sourceSeconds <= segment.end) {
        return span.sequenceStart +
            (sourceSeconds - segment.start) /
                math.max(0.1, segment.playbackSpeed);
      }
    }
    return null;
  }

  List<_ProgramSpan> get _programSpans {
    var cursor = 0.0;
    HighlightSegment? previous;
    return [
      for (var index = 0; index < segments.length; index++)
        (() {
          final segment = segments[index];
          final overlap = previous == null
              ? 0.0
              : effectiveTransitionOverlap(previous!, segment);
          final start = math.max(0.0, cursor - overlap);
          final end = start + math.max(0.0, segment.outputDuration);
          cursor = end;
          previous = segment;
          return _ProgramSpan(
            segment: segment,
            index: index,
            sequenceStart: start,
            sequenceEnd: end,
          );
        })(),
    ];
  }

  List<double> get _programEditPoints {
    final spans = _programSpans;
    if (spans.isEmpty) {
      return const [];
    }
    final points = <double>{0};
    for (var index = 1; index < spans.length; index++) {
      final overlap = effectiveTransitionOverlap(
        spans[index - 1].segment,
        spans[index].segment,
      );
      points.add(spans[index].sequenceStart + overlap / 2);
    }
    points.add(outputDurationSeconds);
    for (final overlay in videoOverlays) {
      if (overlay.enabled) {
        points
          ..add(overlay.timelineStart)
          ..add(overlay.timelineEnd);
      }
    }
    for (final clip in audioClips) {
      if (clip.enabled) {
        points
          ..add(clip.timelineStart)
          ..add(clip.timelineEnd);
      }
    }
    return points
        .where((point) => point >= 0 && point <= outputDurationSeconds)
        .toSet()
        .toList()
      ..sort();
  }

  _ProgramSpan? _programSpanAt(double programSeconds) {
    if (segments.isEmpty) {
      return null;
    }
    final clamped = programSeconds
        .clamp(0.0, math.max(0.0, outputDurationSeconds))
        .toDouble();
    final spans = _programSpans;
    for (var index = spans.length - 1; index >= 0; index--) {
      final span = spans[index];
      if (clamped >= span.sequenceStart - timecodeFrameDurationSeconds / 2 &&
          (clamped < span.sequenceEnd - timecodeFrameDurationSeconds / 2 ||
              index == spans.length - 1)) {
        return span;
      }
    }
    return spans.first;
  }

  _ProgramSpan? _programSpanForOrder(int? order) {
    if (order == null) {
      return null;
    }
    for (final span in _programSpans) {
      if (span.segment.order == order) {
        return span;
      }
    }
    return null;
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
    final hasNewsSignals = segments.any(_segmentHasNewsSignal);
    final hasAttribution = segments.any(_segmentHasVerificationSignal);
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
    if (isProbingMedia && isPreparingPreview) {
      return '미디어 검사 · 빠른 프리뷰 준비 중...';
    }
    if (isProbingMedia) {
      return '미디어 사전검사 중...';
    }
    if (isPreparingPreview) {
      return '프리뷰 프록시 생성 중...';
    }
    if (isLoadingTimelineThumbnails) {
      return '타임라인 프레임 준비 중 · ${timelineThumbnails.length}/$timelineThumbnailTargetCount';
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
      originalPath: selectedFile?.path,
      duration: duration,
      segments: segments,
      videoOverlays: videoOverlays,
      audioClips: audioClips,
      activeVideoTrackCount: activeVideoTrackCount,
      activeAudioTrackCount: activeAudioTrackCount,
      transcript: transcript,
      captions: captions,
      waveform: waveform,
      timelineMarkers: timelineMarkers,
      shortsCandidates: _serializeShortsCandidates(shortsCandidates),
      selectedShortsId: selectedShortsId,
      includeCaptions: includeCaptions,
      captionStylePreset: captionStylePreset,
      exportAspectRatio: exportAspectRatio,
      selectedExportProfiles: selectedExportProfiles,
      markIn: markIn,
      markOut: markOut,
    );
  }

  Future<void> ensureLocalEngine() async {
    engineState = const LocalEngineState(
      status: 'starting',
      message: '로컬 편집 엔진 확인 및 시작 중 · 첫 실행은 구성요소 설치로 시간이 걸릴 수 있습니다',
      isStarting: true,
    );
    notifyListeners();

    try {
      engineState = await _engineService.ensureRunning();
    } catch (error) {
      engineState = LocalEngineState.unavailable(
        '로컬 편집 엔진 시작 중 오류가 발생했습니다: $error',
      );
    }
    notifyListeners();
  }

  Future<void> refreshStorageUsage({int retentionHours = 24}) async {
    if (isRefreshingStorage || isCleaningStorage) {
      return;
    }
    isRefreshingStorage = true;
    storageErrorMessage = null;
    notifyListeners();
    try {
      await _ensureLocalEngineForApi();
      storageUsage = await _apiClient.getStorageUsage(
        activeJobId: jobId,
        retentionHours: retentionHours,
      );
    } catch (error) {
      storageErrorMessage = '저장공간 정보를 불러오지 못했습니다: $error';
    } finally {
      isRefreshingStorage = false;
      notifyListeners();
    }
  }

  Future<StorageCleanupInfo?> cleanupSafeStorage({
    int retentionHours = 24,
  }) async {
    if (isCleaningStorage || isRefreshingStorage) {
      return null;
    }
    isCleaningStorage = true;
    storageErrorMessage = null;
    notifyListeners();
    try {
      final result = await _apiClient.cleanupSafeStorage(
        activeJobId: jobId,
        retentionHours: retentionHours,
      );
      lastStorageCleanup = result;
      storageUsage = result.after;
      return result;
    } catch (error) {
      storageErrorMessage = '안전 캐시 정리에 실패했습니다: $error';
      return null;
    } finally {
      isCleaningStorage = false;
      notifyListeners();
    }
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
    final files = await pickMediaAssets(allowMultiple: false);
    if (files.isEmpty) {
      return;
    }
    await openMediaFile(files.first);
  }

  Future<List<PlatformFile>> pickMediaAssets({
    bool allowMultiple = true,
    bool includeAudio = false,
  }) async {
    errorMessage = null;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: includeAudio ? '영상 또는 오디오 가져오기' : '원본 영상 가져오기',
      type: kIsWeb
          ? includeAudio
                ? FileType.any
                : FileType.video
          : FileType.custom,
      allowedExtensions: kIsWeb
          ? null
          : includeAudio
          ? supportedMediaExtensions
          : supportedVideoExtensions,
      allowMultiple: allowMultiple,
      withData: kIsWeb,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) {
      return const [];
    }
    return result.files;
  }

  Future<void> openMediaPath(String path) async {
    final file = io.File(path);
    if (!await file.exists()) {
      errorMessage = '미디어 파일을 찾을 수 없습니다: $path';
      notifyListeners();
      return;
    }
    final name = file.uri.pathSegments.isEmpty
        ? path
        : file.uri.pathSegments.last;
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (!supportedVideoExtensions.contains(extension)) {
      errorMessage = '지원하지 않는 미디어 형식입니다: .$extension';
      notifyListeners();
      return;
    }
    await openMediaFile(
      PlatformFile(name: name, size: await file.length(), path: path),
    );
  }

  bool _prefersProxyPreview(String path) {
    return path.toLowerCase().endsWith('.mxf');
  }

  Future<void> _prepareLocalPreview(String path, {double focusSeconds = 0}) {
    if (_prefersProxyPreview(path) ||
        selectedMediaProbe?.isMxf == true ||
        _previewUsesProxy) {
      return _initializeProxyPreview(path, focusSeconds: focusSeconds);
    }
    return _initializeLocalPreview(path);
  }

  void _clearTimelineThumbnails() {
    _timelineThumbnailTimer?.cancel();
    _timelineThumbnailRevision += 1;
    final previous = timelineThumbnails.values.toList();
    timelineThumbnails = const {};
    timelineThumbnailTargetCount = 0;
    isLoadingTimelineThumbnails = false;
    for (final image in previous) {
      image.dispose();
    }
  }

  void _scheduleTimelineThumbnails({
    Duration delay = const Duration(milliseconds: 550),
  }) {
    if (!_timelineThumbnailsEnabled || _isDisposed || segments.isEmpty) {
      return;
    }
    final path = selectedFile?.path;
    if (path == null || path.isEmpty || !io.File(path).existsSync()) {
      return;
    }
    _timelineThumbnailTimer?.cancel();
    final revision = ++_timelineThumbnailRevision;
    _timelineThumbnailTimer = Timer(delay, () {
      unawaited(_prepareTimelineThumbnails(path, revision));
    });
  }

  Future<void> _prepareTimelineThumbnails(String path, int revision) async {
    if (_isDisposed || revision != _timelineThumbnailRevision) {
      return;
    }
    if (isPreparingPreview) {
      _scheduleTimelineThumbnails(delay: const Duration(milliseconds: 900));
      return;
    }
    final targets = <int, double>{};
    for (final segment in segments) {
      for (final frame in timelineThumbnailSampleFrames(segment)) {
        targets.putIfAbsent(frame, () => timecodeFrameToSeconds(frame));
      }
    }
    timelineThumbnailTargetCount = targets.length;
    final obsoleteKeys = timelineThumbnails.keys
        .where((key) => !targets.containsKey(key))
        .toList();
    if (obsoleteKeys.isNotEmpty) {
      final next = Map<int, ui.Image>.of(timelineThumbnails);
      for (final key in obsoleteKeys) {
        next.remove(key)?.dispose();
      }
      timelineThumbnails = next;
    }
    final pending = targets.entries
        .where((entry) => !timelineThumbnails.containsKey(entry.key))
        .toList();
    if (pending.isEmpty) {
      isLoadingTimelineThumbnails = false;
      notifyListeners();
      return;
    }

    isLoadingTimelineThumbnails = true;
    notifyListeners();
    try {
      await _ensureLocalEngineForApi();
      for (final target in pending) {
        if (_isDisposed || revision != _timelineThumbnailRevision) {
          return;
        }
        if (isPreparingPreview) {
          _scheduleTimelineThumbnails(delay: const Duration(milliseconds: 900));
          return;
        }
        try {
          final info = await _apiClient.createLocalThumbnail(
            path,
            timeSeconds: target.value,
          );
          final thumbnailPath = info.localPath;
          if (thumbnailPath == null || thumbnailPath.isEmpty) {
            continue;
          }
          final file = io.File(thumbnailPath);
          if (!await file.exists()) {
            continue;
          }
          final codec = await ui.instantiateImageCodec(
            await file.readAsBytes(),
          );
          final frame = await codec.getNextFrame();
          codec.dispose();
          if (_isDisposed || revision != _timelineThumbnailRevision) {
            frame.image.dispose();
            return;
          }
          timelineThumbnails = {...timelineThumbnails, target.key: frame.image};
          notifyListeners();
        } catch (_) {
          // A missing thumbnail must not interrupt editing or playback.
        }
      }
    } finally {
      if (!_isDisposed && revision == _timelineThumbnailRevision) {
        isLoadingTimelineThumbnails = false;
        notifyListeners();
      }
    }
  }

  Future<void> openMediaFile(PlatformFile file) async {
    _clearTimelineThumbnails();
    projectFilePath = null;
    selectedFile = file;
    selectedMediaProbe = null;
    isProbingMedia = false;
    isPreparingPreview = false;
    previewMonitorMode = 'source';
    _programPlayheadSeconds = 0;
    _programSegmentOrder = null;
    _programCutPending = false;
    _previewAutoplayRequested = false;
    _proxyContinuationPending = false;
    jobId = null;
    job = null;
    duration = 0;
    _manualPlayheadSeconds = 0;
    _stopReverseShuttleTimer();
    playbackShuttleDirection = 0;
    playbackShuttleRate = 1.0;
    segments = [];
    videoOverlays = [];
    audioClips = [];
    transcript = [];
    captions = [];
    waveform = [];
    timelineMarkers = [];
    renderUrl = null;
    selectedSegmentOrder = null;
    selectedVideoOverlayId = null;
    selectedAudioClipId = null;
    markIn = null;
    markOut = null;
    uploadProgress = 0;
    timelineTool = 'selection';
    timelineSnappingEnabled = true;
    videoTrackTargeted = true;
    videoOverlayTrackTargeted = false;
    audioTrack1Targeted = true;
    audioTrack2Targeted = true;
    audioTrack3Targeted = true;
    activeVideoTrackCount = 2;
    activeAudioTrackCount = 3;
    targetedVideoOverlayTrack = 2;
    targetedOverlayAudioTrack = 3;
    videoTrackLocked = false;
    videoOverlayTrackLocked = false;
    videoOverlayTrackVisible = true;
    audioTrackLocked = false;
    audioTrack1Locked = false;
    audioTrack2Locked = false;
    audioTrack3Locked = false;
    comparisonDefaultSegments = [];
    comparisonReferenceSegments = [];
    comparisonSelection = 'current';
    shortsCandidates = [];
    selectedShortsId = null;
    _clearHistory();
    _markProjectDirty();
    await _disposeVideoController();
    notifyListeners();
    if (!kIsWeb && file.path != null) {
      unawaited(_prepareLocalPreview(file.path!));
      unawaited(probeSelectedMedia());
    }
  }

  Future<void> relinkSourceMedia() async {
    errorMessage = null;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '원본 미디어 다시 연결',
      type: kIsWeb ? FileType.video : FileType.custom,
      allowedExtensions: kIsWeb ? null : supportedVideoExtensions,
      allowMultiple: false,
      withData: kIsWeb,
      withReadStream: !kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    _clearTimelineThumbnails();
    selectedFile = file;
    selectedMediaProbe = null;
    renderUrl = null;
    _previewAutoplayRequested = false;
    _markProjectDirty();
    await _disposeVideoController();
    notifyListeners();

    if (!kIsWeb && file.path != null) {
      unawaited(_prepareLocalPreview(file.path!));
      unawaited(probeSelectedMedia());
    }
    await saveProjectToBackend(silent: true);
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
      if (probe.duration > 0 && duration == 0) {
        duration = probe.duration;
      }
      if (!probe.canAnalyze) {
        errorMessage = '사전검사 실패: 분석 가능한 비디오 스트림이 없습니다.';
      } else if (probe.requiresCompatibilityProxy && !_previewUsesProxy) {
        unawaited(
          _initializeProxyPreview(path, focusSeconds: currentPositionSeconds),
        );
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
      job = JobStatusResponse(
        jobId: response.jobId,
        status: response.status,
        stage: response.stage,
        progress: response.progress,
        message: '분석 작업 대기 중',
        duration: response.duration,
      );
      isUploading = false;
      try {
        if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
          final previewFocus = currentPositionSeconds;
          if ((selectedMediaProbe?.isMxf == true || _previewUsesProxy) &&
              (!_previewUsesProxy || !_proxyContainsSourceTime(previewFocus))) {
            await _initializeProxyPreview(
              localPath,
              focusSeconds: previewFocus,
            );
          } else if (videoController == null ||
              !videoController!.value.isInitialized) {
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

  Future<bool> cancelActiveJob() async {
    final id = jobId;
    if (id == null || !canCancelJob) {
      return false;
    }
    isCancellingJob = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _ensureLocalEngineForApi();
      final cancelled = await _apiClient.cancelJob(id);
      if (jobId != id) {
        return false;
      }
      job = cancelled;
      isUploading = false;
      isRendering = false;
      _pollTimer?.cancel();
      unawaited(refreshRecentJobs(silent: true));
      return cancelled.status == 'cancelled';
    } catch (error) {
      errorMessage = '작업 취소 실패: $error';
      return false;
    } finally {
      isCancellingJob = false;
      notifyListeners();
    }
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
    if (hasMultiFormatExport) {
      await requestMultiFormatRender();
      return;
    }
    final aspectRatio = selectedExportProfiles.isEmpty
        ? exportAspectRatio
        : selectedExportProfiles.first;
    await _requestRender(
      aspectRatio: aspectRatio,
      outputName: _exportProfileOutputName(aspectRatio),
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
    selectedExportProfiles = [aspectRatio];
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
        videoOverlays: videoOverlayTrackVisible
            ? videoOverlays.where((overlay) => overlay.enabled).toList()
            : const [],
        audioClips: audioClips.where((clip) => clip.enabled).toList(),
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

  Future<void> requestMultiFormatRender() async {
    final id = jobId;
    if (id == null || segments.isEmpty || selectedExportProfiles.isEmpty) {
      return;
    }
    final repaired = _repairSegmentsForRenderSafety(segments);
    if (repaired.$2) {
      _commitHistory();
      segments = repaired.$1;
      renderUrl = null;
    }
    for (final profile in selectedExportProfiles) {
      final safetyBlocks = _buildRenderSafetyChecklist(
        segments,
        aspectRatio: profile,
        requireCaptions: includeCaptions,
      ).where((item) => item.status == EditorialCheckStatus.block).toList();
      if (safetyBlocks.isNotEmpty) {
        final firstBlock = safetyBlocks.first;
        errorMessage =
            '${_exportProfileLabel(profile)} 렌더 안전 검사 실패: ${firstBlock.label} · ${firstBlock.detail}';
        notifyListeners();
        return;
      }
    }

    isRendering = true;
    errorMessage = null;
    notifyListeners();

    try {
      await saveProjectToBackend(silent: true);
      await _apiClient.requestBatchRender(
        id,
        [
          for (final profile in selectedExportProfiles)
            {
              'label': _exportProfileLabel(profile),
              'output_name': _exportProfileOutputName(profile),
              'aspect_ratio': profile,
              'segments': segments.map((segment) => segment.toJson()).toList(),
            },
        ],
        captions: captions,
        videoOverlays: videoOverlayTrackVisible
            ? videoOverlays.where((overlay) => overlay.enabled).toList()
            : const [],
        audioClips: audioClips.where((clip) => clip.enabled).toList(),
        captionStyle: captionRenderStyle,
        aspectRatio: selectedExportProfiles.first,
        includeCaptions: includeCaptions,
      );
      _startPolling();
    } catch (error) {
      isRendering = false;
      errorMessage = '멀티 포맷 렌더링 요청 실패: $error';
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
      _applyProject(
        project,
        keepJob: true,
        resetHistory: false,
        markProjectDirty: false,
      );
    } catch (error) {
      if (!silent) {
        errorMessage = '프로젝트 저장 실패: $error';
      }
    }
    if (!silent) {
      notifyListeners();
    }
  }

  Future<void> saveProjectFile() async {
    final path = projectFilePath;
    if (!kIsWeb && path != null && path.isNotEmpty) {
      await saveProjectToPath(path);
      return;
    }
    await exportProjectFile();
  }

  Future<void> exportProjectFile() async {
    final bytes = _projectFileBytes();
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '프로젝트 저장',
        fileName: '${_safeProjectFileName()}.autoedit.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: kIsWeb ? bytes : null,
      );
      if (path == null || path.isEmpty) {
        return;
      }
      if (kIsWeb) {
        _markProjectSaved();
        notifyListeners();
        return;
      }
      await saveProjectToPath(path);
    } catch (error) {
      errorMessage = '프로젝트 파일 저장 실패: $error';
      notifyListeners();
    }
  }

  Future<void> saveProjectToPath(String path) async {
    if (kIsWeb) {
      throw UnsupportedError('로컬 경로 저장은 데스크톱에서만 지원합니다.');
    }
    try {
      final target = io.File(path);
      await target.parent.create(recursive: true);
      await _writeProjectFileAtomically(target, _projectFileBytes());
      projectFilePath = target.path;
      _markProjectSaved();
      errorMessage = null;
    } catch (error) {
      errorMessage = '프로젝트 파일 저장 실패: $error';
    }
    notifyListeners();
  }

  String buildSelectedShortsCutListCsv() {
    final candidates = shortsCandidates
        .where(
          (candidate) => candidate.selected && candidate.segments.isNotEmpty,
        )
        .toList();
    return _buildShortsCutListCsv(candidates);
  }

  Future<void> exportSelectedShortsCutList() async {
    final csv = buildSelectedShortsCutListCsv();
    if (csv.isEmpty) {
      errorMessage = '내보낼 쇼츠 후보를 선택해 주세요';
      notifyListeners();
      return;
    }
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: '쇼츠 컷 리스트 저장',
        fileName: '${_safeProjectFileName()}_shorts_cutlist.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      );
    } catch (error) {
      errorMessage = '쇼츠 컷 리스트 저장 실패: $error';
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
      final file = result.files.single;
      final path = file.path;
      if (!kIsWeb && path != null && path.isNotEmpty) {
        await openProjectPath(path);
        return;
      }
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('프로젝트 파일을 읽을 수 없습니다.');
      }
      await _openProjectBytes(bytes, initializePreview: true);
    } catch (error) {
      errorMessage = '프로젝트 불러오기 실패: $error';
      notifyListeners();
    }
  }

  Future<void> openProjectPath(
    String path, {
    bool initializePreview = true,
  }) async {
    try {
      final file = io.File(path);
      if (!await file.exists()) {
        throw StateError('프로젝트 파일을 찾을 수 없습니다: $path');
      }
      await _openProjectBytes(
        await file.readAsBytes(),
        sourcePath: file.path,
        initializePreview: initializePreview,
      );
    } catch (error) {
      errorMessage = '프로젝트 불러오기 실패: $error';
      notifyListeners();
    }
  }

  Uint8List _projectFileBytes() {
    return Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'version': 2, ...projectState.toJson()}),
      ),
    );
  }

  Future<void> _openProjectBytes(
    Uint8List bytes, {
    String? sourcePath,
    required bool initializePreview,
  }) async {
    final decoded = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    final raw = jsonDecode(decoded);
    if (raw is! Map) {
      throw const FormatException('프로젝트 JSON 형식이 올바르지 않습니다.');
    }
    final project = ProjectState.fromJson(Map<String, dynamic>.from(raw));
    await _disposeVideoController();
    _applyProject(project, keepJob: false, markProjectDirty: false);
    projectFilePath = sourcePath;
    _markProjectSaved();
    errorMessage = null;
    notifyListeners();

    if (!initializePreview) {
      return;
    }
    if (!kIsWeb && sourceMediaIsLinked) {
      unawaited(_prepareLocalPreview(sourceMediaPath!));
      unawaited(probeSelectedMedia());
    } else if (jobId != null) {
      try {
        await _initializePreview(jobId!);
      } catch (_) {
        await _disposeVideoController();
      }
    }
  }

  Future<void> _writeProjectFileAtomically(
    io.File target,
    Uint8List bytes,
  ) async {
    final nonce = '${io.pid}.${DateTime.now().microsecondsSinceEpoch}';
    final temporary = io.File('${target.path}.$nonce.tmp');
    final backup = io.File('${target.path}.$nonce.bak');
    var originalMoved = false;
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) {
        await target.rename(backup.path);
        originalMoved = true;
      }
      await temporary.rename(target.path);
      if (await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      if (originalMoved && !await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  Future<void> _initializeRecoverySession() async {
    if (!_projectRecoveryEnabled || isInitializingRecoverySession) {
      return;
    }
    isInitializingRecoverySession = true;
    try {
      final previousSessionWasClean = await _recoveryService.beginSession();
      final snapshot = await _recoveryService.readSnapshot();
      hasRecoverySnapshot = snapshot != null;
      recoverySnapshotSavedAt = snapshot?.savedAt;
      recoveryVersions = await _recoveryService.listVersions();
      recoveryRequiresManualRestore =
          previousSessionWasClean == false && snapshot != null;
      if (_autoRestoreRecovery &&
          previousSessionWasClean != false &&
          snapshot != null &&
          !hasRecoverableProject) {
        await _restoreRecoverySnapshot(snapshot, true);
        didAutoRestoreSession = true;
        recoveryRequiresManualRestore = false;
      }
    } catch (_) {
      hasRecoverySnapshot = false;
      recoverySnapshotSavedAt = null;
      recoveryVersions = [];
    } finally {
      isInitializingRecoverySession = false;
      hasInitializedRecoverySession = true;
      notifyListeners();
    }
  }

  Future<void> prepareForExit() async {
    if (!_projectRecoveryEnabled) {
      return;
    }
    _recoverySaveTimer?.cancel();
    try {
      await _writeProjectRecoverySnapshot();
      await _recoveryService.markSessionClean();
    } catch (_) {
      // A recovery write failure must not trap the user in the application.
    }
  }

  Future<void> refreshProjectRecoveryStatus() async {
    if (!_projectRecoveryEnabled) {
      return;
    }
    try {
      final snapshot = await _recoveryService.readSnapshot();
      hasRecoverySnapshot = snapshot != null;
      recoverySnapshotSavedAt = snapshot?.savedAt;
      recoveryVersions = await _recoveryService.listVersions();
    } catch (_) {
      hasRecoverySnapshot = false;
      recoverySnapshotSavedAt = null;
      recoveryVersions = [];
    }
    notifyListeners();
  }

  Future<void> refreshRecentJobs({bool silent = false}) async {
    if (isLoadingRecentJobs || isOpeningRecentJob) {
      return;
    }
    isLoadingRecentJobs = true;
    recentJobsError = null;
    if (!silent) {
      notifyListeners();
    }
    try {
      await _ensureLocalEngineForApi();
      recentJobs = await _apiClient.listRecentJobs();
    } catch (error) {
      recentJobsError = '최근 작업을 불러오지 못했습니다: $error';
    } finally {
      isLoadingRecentJobs = false;
      notifyListeners();
    }
  }

  Future<bool> resumeRecentJob(RecentJobSummary summary) async {
    if (isOpeningRecentJob || hasActiveJob || !summary.canResume) {
      return false;
    }
    isOpeningRecentJob = true;
    recentJobsError = null;
    errorMessage = null;
    notifyListeners();
    try {
      await _ensureLocalEngineForApi();
      final status = await _apiClient.getJob(summary.jobId);
      final project = await _apiClient.getProject(summary.jobId);
      await _disposeVideoController();
      _applyProject(project, keepJob: false, markProjectDirty: false);
      job = status;
      jobId = summary.jobId;
      projectFilePath = null;
      selectedMediaProbe = null;
      isUploading = false;
      isRendering = status.status == 'rendering';
      renderUrl = status.renderUrl == null
          ? null
          : _apiClient.absoluteUrl(status.renderUrl!);
      _markProjectSaved();

      if (hasActiveJob) {
        _startPolling();
      }
      if (!kIsWeb && sourceMediaIsLinked) {
        unawaited(_prepareLocalPreview(sourceMediaPath!));
        unawaited(probeSelectedMedia());
      }
      return true;
    } catch (error) {
      recentJobsError = '최근 작업 열기 실패: $error';
      return false;
    } finally {
      isOpeningRecentJob = false;
      notifyListeners();
    }
  }

  Future<void> restoreRecoveryProject({bool initializePreview = true}) async {
    if (!_projectRecoveryEnabled) {
      return;
    }
    await _awaitRecoveryInitialization();
    try {
      final snapshot = await _recoveryService.readSnapshot();
      if (snapshot == null) {
        hasRecoverySnapshot = false;
        recoverySnapshotSavedAt = null;
        errorMessage = '복구할 자동 저장본이 없습니다.';
        notifyListeners();
        return;
      }

      await _restoreRecoverySnapshot(snapshot, initializePreview);
      recoveryRequiresManualRestore = false;
      didAutoRestoreSession = false;
    } catch (error) {
      errorMessage = '자동 저장본 복구 실패: $error';
    }
    notifyListeners();
  }

  Future<void> createManualRecoverySnapshot({String? label}) async {
    if (!_projectRecoveryEnabled || !hasRecoverableProject) {
      return;
    }
    await _awaitRecoveryInitialization();
    try {
      final project = projectState;
      final snapshot = await _recoveryService.saveProject(
        project,
        label: label,
        manual: true,
      );
      _lastRecoveryPayload = jsonEncode(project.toJson());
      hasRecoverySnapshot = true;
      recoverySnapshotSavedAt = snapshot.savedAt;
      recoveryVersions = await _recoveryService.listVersions();
      errorMessage = null;
    } catch (error) {
      errorMessage = '수동 복구 버전 저장 실패: $error';
    }
    notifyListeners();
  }

  Future<void> restoreRecoveryVersion(
    String id, {
    bool initializePreview = true,
  }) async {
    if (!_projectRecoveryEnabled) {
      return;
    }
    await _awaitRecoveryInitialization();
    try {
      final snapshot = await _recoveryService.readVersion(id);
      if (snapshot == null) {
        errorMessage = '선택한 복구 버전을 찾을 수 없습니다.';
      } else {
        await _restoreRecoverySnapshot(snapshot, initializePreview);
      }
    } catch (error) {
      errorMessage = '복구 버전 불러오기 실패: $error';
    }
    notifyListeners();
  }

  Future<void> deleteRecoveryVersion(String id) async {
    if (!_projectRecoveryEnabled) {
      return;
    }
    try {
      await _recoveryService.deleteVersion(id);
      recoveryVersions = await _recoveryService.listVersions();
    } catch (error) {
      errorMessage = '복구 버전 삭제 실패: $error';
    }
    notifyListeners();
  }

  Future<void> _restoreRecoverySnapshot(
    ProjectRecoverySnapshot snapshot,
    bool initializePreview,
  ) async {
    if (hasRecoverableProject) {
      _commitHistory();
    }
    errorMessage = null;
    isUploading = false;
    isRendering = false;
    isProbingMedia = false;
    isPreparingPreview = false;
    uploadProgress = 0;
    selectedMediaProbe = null;
    await _disposeVideoController();
    _applyProject(snapshot.project, keepJob: false, resetHistory: false);
    hasRecoverySnapshot = true;
    recoverySnapshotSavedAt = snapshot.savedAt;
    _lastRecoveryPayload = jsonEncode(snapshot.project.toJson());

    if (initializePreview && !kIsWeb && sourceMediaIsLinked) {
      unawaited(_prepareLocalPreview(sourceMediaPath!));
      unawaited(probeSelectedMedia());
    } else if (initializePreview && jobId != null) {
      try {
        await _initializePreview(jobId!);
      } catch (_) {
        await _disposeVideoController();
      }
    }
  }

  Future<void> clearRecoverySnapshot() async {
    if (!_projectRecoveryEnabled) {
      return;
    }
    try {
      await _recoveryService.clearSnapshot();
      hasRecoverySnapshot = false;
      recoverySnapshotSavedAt = null;
      recoveryVersions = [];
      _lastRecoveryPayload = null;
      didAutoRestoreSession = false;
      recoveryRequiresManualRestore = false;
    } catch (error) {
      errorMessage = '자동 저장본 삭제 실패: $error';
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

    segments = _reorderSegments(segments);
    selectedSegmentOrder = normalized.order.clamp(1, segments.length).toInt();
    renderUrl = null;
    notifyListeners();
    if (isProgramMonitor) {
      _scheduleProgramPreviewRefresh(normalized);
    }
  }

  void addVideoOverlay({
    required String sourcePath,
    required String sourceName,
    double? timelineStart,
    double sourceStart = 0,
    double? sourceDuration,
  }) {
    if (videoOverlayTrackLocked || sourcePath.trim().isEmpty) {
      return;
    }
    _commitHistory();
    if (activeVideoTrackCount < 2) {
      activeVideoTrackCount = 2;
    }
    if (activeAudioTrackCount < 3) {
      activeAudioTrackCount = 3;
    }
    final videoTrack =
        (videoOverlayTrackTargeted ? targetedVideoOverlayTrack : 2)
            .clamp(2, activeVideoTrackCount)
            .toInt();
    final audioTrack = targetedOverlayAudioTrack
        .clamp(3, activeAudioTrackCount)
        .toInt();
    final sequenceDuration = math.max(
      timecodeFrameDurationSeconds,
      outputDurationSeconds,
    );
    final start = snapSecondsToFrame(
      (timelineStart ?? monitorPositionSeconds)
          .clamp(
            0.0,
            math.max(0.0, sequenceDuration - timecodeFrameDurationSeconds),
          )
          .toDouble(),
    );
    final available = math.max(
      timecodeFrameDurationSeconds,
      sequenceDuration - start,
    );
    final clipDuration = math.min(
      available,
      math.max(
        timecodeFrameDurationSeconds,
        math.min(sourceDuration ?? 5.0, 10.0),
      ),
    );
    final normalizedSourceStart = snapSecondsToFrame(
      math.max(0.0, sourceStart),
    );
    final overlay = VideoOverlayClip(
      id: 'v2-${DateTime.now().microsecondsSinceEpoch}',
      sourcePath: sourcePath,
      sourceName: sourceName,
      timelineStart: start,
      timelineEnd: snapSecondsToFrame(start + clipDuration),
      sourceStart: normalizedSourceStart,
      sourceEnd: snapSecondsToFrame(normalizedSourceStart + clipDuration),
      videoTrack: videoTrack,
      audioTrack: audioTrack,
    );
    videoOverlays = [...videoOverlays, overlay]
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    targetedVideoOverlayTrack = videoTrack;
    targetedOverlayAudioTrack = audioTrack;
    videoOverlayTrackTargeted = true;
    audioTrack3Targeted = audioTrack == 3;
    selectedVideoOverlayId = overlay.id;
    selectedAudioClipId = null;
    selectedSegmentOrder = null;
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  void updateVideoOverlay(VideoOverlayClip updated, {bool audioOnly = false}) {
    if ((audioOnly ? audioTrack3Locked : videoOverlayTrackLocked) ||
        !videoOverlays.any((overlay) => overlay.id == updated.id)) {
      return;
    }
    _commitHistory();
    videoOverlays = [
      for (final overlay in videoOverlays)
        if (overlay.id == updated.id) updated else overlay,
    ]..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    selectedVideoOverlayId = updated.id;
    selectedAudioClipId = null;
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  void selectVideoOverlay(String id) {
    if (!videoOverlays.any((overlay) => overlay.id == id)) {
      return;
    }
    selectedVideoOverlayId = id;
    selectedAudioClipId = null;
    selectedSegmentOrder = null;
    notifyListeners();
  }

  void deleteSelectedVideoOverlay() {
    final id = selectedVideoOverlayId;
    if (id == null || videoOverlayTrackLocked) {
      return;
    }
    _commitHistory();
    videoOverlays = videoOverlays.where((overlay) => overlay.id != id).toList();
    selectedVideoOverlayId = null;
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  void toggleSelectedVideoOverlayEnabled() {
    final overlay = selectedVideoOverlay;
    if (overlay == null || videoOverlayTrackLocked) {
      return;
    }
    updateVideoOverlay(overlay.copyWith(enabled: !overlay.enabled));
  }

  void setSelectedVideoOverlayOpacity(double value) {
    final overlay = selectedVideoOverlay;
    if (overlay == null) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(opacity: value.clamp(0.0, 1.0).toDouble()),
    );
  }

  void setSelectedVideoOverlayScale(double value) {
    final overlay = selectedVideoOverlay;
    if (overlay == null) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(scale: value.clamp(0.1, 1.0).toDouble()),
    );
  }

  void setSelectedVideoOverlayPositionX(double value) {
    final overlay = selectedVideoOverlay;
    if (overlay == null) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(positionX: value.clamp(-1.0, 1.0).toDouble()),
    );
  }

  void setSelectedVideoOverlayPositionY(double value) {
    final overlay = selectedVideoOverlay;
    if (overlay == null) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(positionY: value.clamp(-1.0, 1.0).toDouble()),
    );
  }

  void setSelectedVideoOverlayRotation(double value) {
    final overlay = selectedVideoOverlay;
    if (overlay == null) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(rotation: value.clamp(-180.0, 180.0).toDouble()),
    );
  }

  void setSelectedVideoOverlayVideoTrack(int track) {
    final overlay = selectedVideoOverlay;
    if (overlay == null || videoOverlayTrackLocked) {
      return;
    }
    final normalized = track.clamp(2, activeVideoTrackCount).toInt();
    updateVideoOverlay(overlay.copyWith(videoTrack: normalized));
    targetedVideoOverlayTrack = normalized;
    videoOverlayTrackTargeted = true;
  }

  void setSelectedVideoOverlayAudioTrack(int track) {
    final overlay = selectedVideoOverlay;
    if (overlay == null || audioTrack3Locked) {
      return;
    }
    final normalized = track.clamp(3, activeAudioTrackCount).toInt();
    updateVideoOverlay(
      overlay.copyWith(audioTrack: normalized),
      audioOnly: true,
    );
    targetedOverlayAudioTrack = normalized;
    audioTrack3Targeted = normalized == 3;
  }

  void toggleSelectedVideoOverlayAudioMute() {
    final overlay = selectedVideoOverlay;
    if (overlay == null || audioTrack3Locked) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(muted: !overlay.muted),
      audioOnly: true,
    );
  }

  void setSelectedVideoOverlayAudioVolume(double value) {
    final overlay = selectedVideoOverlay;
    if (overlay == null || audioTrack3Locked) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(audioVolume: value.clamp(0.0, 2.0).toDouble()),
      audioOnly: true,
    );
  }

  void setSelectedVideoOverlayAudioPan(double value) {
    final overlay = selectedVideoOverlay;
    if (overlay == null || audioTrack3Locked) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(audioPan: value.clamp(-1.0, 1.0).toDouble()),
      audioOnly: true,
    );
  }

  void setSelectedVideoOverlayAudioFadeIn(double value) {
    final overlay = selectedVideoOverlay;
    if (overlay == null || audioTrack3Locked) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(
        audioFadeIn: value.clamp(0.0, overlay.timelineDuration / 2).toDouble(),
      ),
      audioOnly: true,
    );
  }

  void setSelectedVideoOverlayAudioFadeOut(double value) {
    final overlay = selectedVideoOverlay;
    if (overlay == null || audioTrack3Locked) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(
        audioFadeOut: value.clamp(0.0, overlay.timelineDuration / 2).toDouble(),
      ),
      audioOnly: true,
    );
  }

  void resetSelectedVideoOverlayAudio() {
    final overlay = selectedVideoOverlay;
    if (overlay == null || audioTrack3Locked) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(
        audioVolume: 1,
        audioPan: 0,
        audioFadeIn: 0,
        audioFadeOut: 0,
      ),
      audioOnly: true,
    );
  }

  void applySelectedVideoOverlayPreset(String preset) {
    final overlay = selectedVideoOverlay;
    if (overlay == null) {
      return;
    }
    final values = switch (preset) {
      'full' => (scale: 1.0, x: 0.0, y: 0.0),
      'top_left' => (scale: 0.35, x: -0.6, y: -0.55),
      'bottom_right' => (scale: 0.35, x: 0.6, y: 0.55),
      _ => (scale: 0.35, x: 0.6, y: -0.55),
    };
    updateVideoOverlay(
      overlay.copyWith(
        scale: values.scale,
        positionX: values.x,
        positionY: values.y,
        rotation: 0,
        opacity: 1,
      ),
    );
  }

  void resetSelectedVideoOverlayTransform() {
    applySelectedVideoOverlayPreset('top_right');
  }

  void duplicateSelectedVideoOverlay() {
    final overlay = selectedVideoOverlay;
    if (overlay == null || videoOverlayTrackLocked) {
      return;
    }
    final duration = overlay.timelineDuration;
    final sequenceDuration = outputDurationSeconds;
    final requestedStart = overlay.timelineEnd + timecodeFrameDurationSeconds;
    final start = requestedStart + duration <= sequenceDuration
        ? requestedStart
        : math.max(0.0, overlay.timelineStart - duration);
    final duplicate = overlay.copyWith(
      id: 'v2-${DateTime.now().microsecondsSinceEpoch}',
      timelineStart: snapSecondsToFrame(start),
      timelineEnd: snapSecondsToFrame(start + duration),
    );
    _commitHistory();
    videoOverlays = [...videoOverlays, duplicate]
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    selectedVideoOverlayId = duplicate.id;
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  Future<void> relinkSelectedVideoOverlay() async {
    final overlay = selectedVideoOverlay;
    if (overlay == null || videoOverlayTrackLocked) {
      return;
    }
    final files = await pickMediaAssets(allowMultiple: false);
    if (files.isEmpty) {
      return;
    }
    final replacement = files.first;
    final path = replacement.path;
    if (path == null || path.isEmpty) {
      return;
    }
    updateVideoOverlay(
      overlay.copyWith(sourcePath: path, sourceName: replacement.name),
    );
  }

  Future<void> addAudioClipFromMedia({
    required String sourcePath,
    required String sourceName,
    double? timelineStart,
  }) async {
    if (sourcePath.trim().isEmpty || audioTrack3Locked) {
      return;
    }
    try {
      await _ensureLocalEngineForApi();
      final probe = await _apiClient.probeLocalMedia(sourcePath);
      if (probe.audioStreamCount <= 0 || probe.duration <= 0) {
        throw StateError('재생 가능한 오디오 스트림을 찾지 못했습니다.');
      }
      addAudioClip(
        sourcePath: sourcePath,
        sourceName: sourceName,
        timelineStart: timelineStart,
        sourceDuration: probe.duration,
      );
    } catch (error) {
      errorMessage = '오디오 클립을 배치하지 못했습니다: $error';
      notifyListeners();
    }
  }

  void addAudioClip({
    required String sourcePath,
    required String sourceName,
    required double sourceDuration,
    double? timelineStart,
    double sourceStart = 0,
  }) {
    if (sourcePath.trim().isEmpty || sourceDuration <= 0 || audioTrack3Locked) {
      return;
    }
    _commitHistory();
    if (activeAudioTrackCount < 3) {
      activeAudioTrackCount = 3;
    }
    final track = targetedOverlayAudioTrack
        .clamp(3, activeAudioTrackCount)
        .toInt();
    final sequenceDuration = math.max(
      timecodeFrameDurationSeconds,
      outputDurationSeconds > 0 ? outputDurationSeconds : duration,
    );
    final normalizedSourceStart = snapSecondsToFrame(
      sourceStart
          .clamp(
            0.0,
            math.max(0.0, sourceDuration - timecodeFrameDurationSeconds),
          )
          .toDouble(),
    );
    final start = snapSecondsToFrame(
      (timelineStart ?? monitorPositionSeconds)
          .clamp(
            0.0,
            math.max(0.0, sequenceDuration - timecodeFrameDurationSeconds),
          )
          .toDouble(),
    );
    final clipDuration = math.min(
      sequenceDuration - start,
      sourceDuration - normalizedSourceStart,
    );
    if (clipDuration < timecodeFrameDurationSeconds / 2) {
      return;
    }
    final clip = AudioClip(
      id: 'a-${DateTime.now().microsecondsSinceEpoch}',
      sourcePath: sourcePath,
      sourceName: sourceName,
      timelineStart: start,
      timelineEnd: snapSecondsToFrame(start + clipDuration),
      sourceStart: normalizedSourceStart,
      sourceEnd: snapSecondsToFrame(normalizedSourceStart + clipDuration),
      track: track,
    );
    audioClips = [...audioClips, clip]
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    targetedOverlayAudioTrack = track;
    audioTrack3Targeted = track == 3;
    selectedAudioClipId = clip.id;
    selectedVideoOverlayId = null;
    selectedSegmentOrder = null;
    errorMessage = null;
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  AudioClip _normalizeStandaloneAudioClip(AudioClip clip) {
    final sequenceDuration = math.max(
      timecodeFrameDurationSeconds,
      outputDurationSeconds > 0 ? outputDurationSeconds : duration,
    );
    final timelineStart = snapSecondsToFrame(
      clip.timelineStart
          .clamp(
            0.0,
            math.max(0.0, sequenceDuration - timecodeFrameDurationSeconds),
          )
          .toDouble(),
    );
    final requestedTimelineDuration = math.max(
      timecodeFrameDurationSeconds,
      clip.timelineEnd - clip.timelineStart,
    );
    final requestedSourceDuration = math.max(
      timecodeFrameDurationSeconds,
      clip.sourceEnd - clip.sourceStart,
    );
    final normalizedDuration = math.min(
      math.min(requestedTimelineDuration, requestedSourceDuration),
      sequenceDuration - timelineStart,
    );
    final sourceStart = snapSecondsToFrame(math.max(0.0, clip.sourceStart));
    final normalizedClipDuration = math.max(
      timecodeFrameDurationSeconds,
      normalizedDuration,
    );
    return clip.copyWith(
      timelineStart: timelineStart,
      timelineEnd: snapSecondsToFrame(timelineStart + normalizedClipDuration),
      sourceStart: sourceStart,
      sourceEnd: snapSecondsToFrame(sourceStart + normalizedClipDuration),
      track: clip.track.clamp(3, activeAudioTrackCount).toInt(),
      volume: clip.volume.clamp(0.0, 2.0).toDouble(),
      pan: clip.pan.clamp(-1.0, 1.0).toDouble(),
      fadeIn: clip.fadeIn.clamp(0.0, normalizedClipDuration / 2).toDouble(),
      fadeOut: clip.fadeOut.clamp(0.0, normalizedClipDuration / 2).toDouble(),
    );
  }

  void updateAudioClip(AudioClip updated) {
    if (audioTrack3Locked || !audioClips.any((clip) => clip.id == updated.id)) {
      return;
    }
    _commitHistory();
    final normalized = _normalizeStandaloneAudioClip(updated);
    audioClips = [
      for (final clip in audioClips)
        if (clip.id == normalized.id) normalized else clip,
    ]..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    selectedAudioClipId = normalized.id;
    selectedVideoOverlayId = null;
    selectedSegmentOrder = null;
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  void selectAudioClip(String id) {
    if (!audioClips.any((clip) => clip.id == id)) {
      return;
    }
    selectedAudioClipId = id;
    selectedVideoOverlayId = null;
    selectedSegmentOrder = null;
    notifyListeners();
  }

  void deleteSelectedAudioClip() {
    final id = selectedAudioClipId;
    if (id == null || audioTrack3Locked) {
      return;
    }
    _commitHistory();
    audioClips = audioClips.where((clip) => clip.id != id).toList();
    selectedAudioClipId = null;
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  void toggleSelectedAudioClipEnabled() {
    final clip = selectedAudioClip;
    if (clip != null) {
      updateAudioClip(clip.copyWith(enabled: !clip.enabled));
    }
  }

  void toggleSelectedAudioClipMute() {
    final clip = selectedAudioClip;
    if (clip != null) {
      updateAudioClip(clip.copyWith(muted: !clip.muted));
    }
  }

  void setSelectedAudioClipTrack(int track) {
    final clip = selectedAudioClip;
    if (clip == null) {
      return;
    }
    final normalized = track.clamp(3, activeAudioTrackCount).toInt();
    updateAudioClip(clip.copyWith(track: normalized));
    targetedOverlayAudioTrack = normalized;
    audioTrack3Targeted = normalized == 3;
  }

  void setSelectedAudioClipVolume(double value) {
    final clip = selectedAudioClip;
    if (clip != null) {
      updateAudioClip(clip.copyWith(volume: value.clamp(0.0, 2.0).toDouble()));
    }
  }

  void setSelectedAudioClipPan(double value) {
    final clip = selectedAudioClip;
    if (clip != null) {
      updateAudioClip(clip.copyWith(pan: value.clamp(-1.0, 1.0).toDouble()));
    }
  }

  void setSelectedAudioClipFadeIn(double value) {
    final clip = selectedAudioClip;
    if (clip != null) {
      updateAudioClip(
        clip.copyWith(
          fadeIn: value.clamp(0.0, clip.timelineDuration / 2).toDouble(),
        ),
      );
    }
  }

  void setSelectedAudioClipFadeOut(double value) {
    final clip = selectedAudioClip;
    if (clip != null) {
      updateAudioClip(
        clip.copyWith(
          fadeOut: value.clamp(0.0, clip.timelineDuration / 2).toDouble(),
        ),
      );
    }
  }

  void resetSelectedAudioClipMix() {
    final clip = selectedAudioClip;
    if (clip != null) {
      updateAudioClip(clip.copyWith(volume: 1, pan: 0, fadeIn: 0, fadeOut: 0));
    }
  }

  void duplicateSelectedAudioClip() {
    final clip = selectedAudioClip;
    if (clip == null || audioTrack3Locked) {
      return;
    }
    final sequenceDuration = math.max(
      timecodeFrameDurationSeconds,
      outputDurationSeconds > 0 ? outputDurationSeconds : duration,
    );
    final requestedStart = clip.timelineEnd + timecodeFrameDurationSeconds;
    final start = requestedStart + clip.timelineDuration <= sequenceDuration
        ? requestedStart
        : math.max(0.0, clip.timelineStart - clip.timelineDuration);
    final duplicate = clip.copyWith(
      id: 'a-${DateTime.now().microsecondsSinceEpoch}',
      timelineStart: snapSecondsToFrame(start),
      timelineEnd: snapSecondsToFrame(start + clip.timelineDuration),
    );
    _commitHistory();
    audioClips = [...audioClips, duplicate]
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    selectedAudioClipId = duplicate.id;
    selectedVideoOverlayId = null;
    selectedSegmentOrder = null;
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  Future<void> relinkSelectedAudioClip() async {
    final clip = selectedAudioClip;
    if (clip == null || audioTrack3Locked) {
      return;
    }
    final files = await pickMediaAssets(
      allowMultiple: false,
      includeAudio: true,
    );
    if (files.isEmpty) {
      return;
    }
    final replacement = files.first;
    final path = replacement.path;
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      await _ensureLocalEngineForApi();
      final probe = await _apiClient.probeLocalMedia(path);
      if (probe.audioStreamCount <= 0) {
        throw StateError('오디오 스트림이 없는 미디어입니다.');
      }
      final available = math.max(
        timecodeFrameDurationSeconds,
        probe.duration - clip.sourceStart,
      );
      final clipDuration = math.min(clip.timelineDuration, available);
      updateAudioClip(
        clip.copyWith(
          sourcePath: path,
          sourceName: replacement.name,
          timelineEnd: clip.timelineStart + clipDuration,
          sourceEnd: clip.sourceStart + clipDuration,
        ),
      );
    } catch (error) {
      errorMessage = '오디오 다시 연결에 실패했습니다: $error';
      notifyListeners();
    }
  }

  void toggleVideoOverlayTrackTarget() {
    videoOverlayTrackTargeted = !videoOverlayTrackTargeted;
    if (videoOverlayTrackTargeted && targetedVideoOverlayTrack < 2) {
      targetedVideoOverlayTrack = 2;
    }
    notifyListeners();
  }

  void toggleVideoOverlayTrackTargetAt(int track) {
    if (track < 2 || track > activeVideoTrackCount) {
      return;
    }
    targetedVideoOverlayTrack = track;
    videoOverlayTrackTargeted = true;
    notifyListeners();
  }

  void toggleVideoOverlayTrackLock() {
    videoOverlayTrackLocked = !videoOverlayTrackLocked;
    notifyListeners();
  }

  void toggleVideoOverlayTrackVisibility() {
    videoOverlayTrackVisible = !videoOverlayTrackVisible;
    notifyListeners();
  }

  void toggleAudioTrack3Target() {
    audioTrack3Targeted = !audioTrack3Targeted;
    targetedOverlayAudioTrack = 3;
    notifyListeners();
  }

  void toggleOverlayAudioTrackTargetAt(int track) {
    if (track < 3 || track > activeAudioTrackCount) {
      return;
    }
    targetedOverlayAudioTrack = track;
    audioTrack3Targeted = track == 3;
    notifyListeners();
  }

  void toggleAudioTrack3Lock() {
    audioTrack3Locked = !audioTrack3Locked;
    notifyListeners();
  }

  void toggleAllVideoOverlayAudio() {
    if (audioTrack3Locked || (videoOverlays.isEmpty && audioClips.isEmpty)) {
      return;
    }
    final muteAll = videoOverlayAudioEnabled;
    _commitHistory();
    videoOverlays = [
      for (final overlay in videoOverlays)
        overlay.copyWith(
          muted: muteAll,
          audioVolume: !muteAll && overlay.audioVolume <= 0
              ? 1
              : overlay.audioVolume,
        ),
    ];
    audioClips = [
      for (final clip in audioClips)
        clip.copyWith(
          muted: muteAll,
          volume: !muteAll && clip.volume <= 0 ? 1 : clip.volume,
        ),
    ];
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  void toggleVideoOverlayAudioTrack(int track) {
    if (audioTrack3Locked || track < 3 || track > activeAudioTrackCount) {
      return;
    }
    final trackOverlays = videoOverlays
        .where((overlay) => overlay.audioTrack == track)
        .toList();
    final trackClips = audioClips.where((clip) => clip.track == track).toList();
    if (trackOverlays.isEmpty && trackClips.isEmpty) {
      return;
    }
    final muteTrack =
        trackOverlays.any(
          (overlay) => !overlay.muted && overlay.audioVolume > 0,
        ) ||
        trackClips.any(
          (clip) => clip.enabled && !clip.muted && clip.volume > 0,
        );
    _commitHistory();
    videoOverlays = [
      for (final overlay in videoOverlays)
        if (overlay.audioTrack == track)
          overlay.copyWith(
            muted: muteTrack,
            audioVolume: !muteTrack && overlay.audioVolume <= 0
                ? 1
                : overlay.audioVolume,
          )
        else
          overlay,
    ];
    audioClips = [
      for (final clip in audioClips)
        if (clip.track == track)
          clip.copyWith(
            muted: muteTrack,
            volume: !muteTrack && clip.volume <= 0 ? 1 : clip.volume,
          )
        else
          clip,
    ];
    renderUrl = null;
    notifyListeners();
    _refreshProgramPreviewAfterOverlayEdit();
  }

  bool get canActivateVideoTrack => activeVideoTrackCount < 4;
  bool get canActivateAudioTrack => activeAudioTrackCount < 8;
  bool get canDeactivateVideoTrack =>
      activeVideoTrackCount > 1 &&
      !videoOverlays.any(
        (overlay) => overlay.videoTrack == activeVideoTrackCount,
      );
  bool get canDeactivateAudioTrack =>
      activeAudioTrackCount > 2 &&
      !videoOverlays.any(
        (overlay) => overlay.audioTrack == activeAudioTrackCount,
      ) &&
      !audioClips.any((clip) => clip.track == activeAudioTrackCount);

  void activateVideoTrack() {
    if (!canActivateVideoTrack) {
      return;
    }
    _commitHistory();
    activeVideoTrackCount += 1;
    targetedVideoOverlayTrack = activeVideoTrackCount;
    videoOverlayTrackTargeted = true;
    notifyListeners();
  }

  void deactivateHighestVideoTrack() {
    if (!canDeactivateVideoTrack) {
      return;
    }
    _commitHistory();
    activeVideoTrackCount -= 1;
    if (targetedVideoOverlayTrack > activeVideoTrackCount) {
      targetedVideoOverlayTrack = activeVideoTrackCount >= 2
          ? activeVideoTrackCount
          : 1;
      videoOverlayTrackTargeted = activeVideoTrackCount >= 2;
    }
    notifyListeners();
  }

  void activateAudioTrack() {
    if (!canActivateAudioTrack) {
      return;
    }
    _commitHistory();
    activeAudioTrackCount += 1;
    targetedOverlayAudioTrack = activeAudioTrackCount;
    audioTrack3Targeted = activeAudioTrackCount == 3;
    notifyListeners();
  }

  void deactivateHighestAudioTrack() {
    if (!canDeactivateAudioTrack) {
      return;
    }
    _commitHistory();
    activeAudioTrackCount -= 1;
    if (targetedOverlayAudioTrack > activeAudioTrackCount) {
      targetedOverlayAudioTrack = activeAudioTrackCount >= 3
          ? activeAudioTrackCount
          : 2;
      audioTrack3Targeted = targetedOverlayAudioTrack == 3;
    }
    notifyListeners();
  }

  void selectSegment(int order) {
    if (segments.any((segment) => segment.order == order)) {
      selectedSegmentOrder = order;
      selectedVideoOverlayId = null;
      selectedAudioClipId = null;
      notifyListeners();
    }
  }

  void clearSegmentSelection() {
    if (selectedSegmentOrder == null &&
        selectedVideoOverlayId == null &&
        selectedAudioClipId == null) {
      return;
    }
    selectedSegmentOrder = null;
    selectedVideoOverlayId = null;
    selectedAudioClipId = null;
    notifyListeners();
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

  void updateTimelineMarker(
    TimelineMarker updated, {
    bool preserveHistory = true,
  }) {
    if (!timelineMarkers.any((marker) => marker.id == updated.id)) {
      return;
    }
    if (preserveHistory) {
      _commitHistory();
    }
    timelineMarkers = _normalizeTimelineMarkers([
      for (final marker in timelineMarkers)
        if (marker.id == updated.id) updated else marker,
    ]);
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
    if (isProgramMonitor) {
      final candidates = <({TimelineMarker marker, double position})>[];
      for (final marker in timelineMarkers) {
        final position = programPositionForSourceTime(marker.seconds);
        if (position != null) {
          candidates.add((marker: marker, position: position));
        }
      }
      candidates.sort((a, b) => a.position.compareTo(b.position));
      final threshold =
          _programPlayheadSeconds + timecodeFrameDurationSeconds / 2;
      for (final candidate in candidates) {
        if (candidate.position > threshold) {
          unawaited(_seekProgramTo(candidate.position, autoplay: false));
          return;
        }
      }
      return;
    }
    final marker = _nextTimelineMarkerFrom(currentPositionSeconds);
    if (marker == null) {
      return;
    }
    unawaited(seekTo(marker.seconds, autoplay: false));
  }

  void jumpToPreviousTimelineMarker() {
    if (isProgramMonitor) {
      final candidates = <({TimelineMarker marker, double position})>[];
      for (final marker in timelineMarkers) {
        final position = programPositionForSourceTime(marker.seconds);
        if (position != null) {
          candidates.add((marker: marker, position: position));
        }
      }
      candidates.sort((a, b) => a.position.compareTo(b.position));
      final threshold =
          _programPlayheadSeconds - timecodeFrameDurationSeconds / 2;
      for (final candidate in candidates.reversed) {
        if (candidate.position < threshold) {
          unawaited(_seekProgramTo(candidate.position, autoplay: false));
          return;
        }
      }
      return;
    }
    final marker = _previousTimelineMarkerFrom(currentPositionSeconds);
    if (marker == null) {
      return;
    }
    unawaited(seekTo(marker.seconds, autoplay: false));
  }

  Future<void> stepPlayheadByFrames(int frameDelta) async {
    if (frameDelta == 0) {
      return;
    }
    final limit = monitorDurationSeconds;
    final next = _snapToFrame(
      (monitorPositionSeconds + frameDelta * timecodeFrameDurationSeconds)
          .clamp(0.0, limit)
          .toDouble(),
    );
    await seekMonitorTo(next, autoplay: false);
  }

  Future<void> jumpToTimelineStart() async {
    await seekMonitorTo(0, autoplay: false);
  }

  Future<void> jumpToTimelineEnd() async {
    await seekMonitorTo(monitorDurationSeconds, autoplay: false);
  }

  Future<void> jumpToMarkIn() async {
    final point = markIn;
    if (point == null) {
      return;
    }
    final programPoint = isProgramMonitor
        ? programPositionForSourceTime(point)
        : null;
    await seekMonitorTo(programPoint ?? point, autoplay: false);
  }

  Future<void> jumpToMarkOut() async {
    final point = markOut;
    if (point == null) {
      return;
    }
    final programPoint = isProgramMonitor
        ? programPositionForSourceTime(point)
        : null;
    await seekMonitorTo(programPoint ?? point, autoplay: false);
  }

  Future<void> jumpToSelectedClipStart() async {
    final audioClip = selectedAudioClip;
    if (audioClip != null) {
      await seekMonitorTo(audioClip.timelineStart, autoplay: false);
      return;
    }
    final overlay = selectedVideoOverlay;
    if (overlay != null) {
      await seekMonitorTo(overlay.timelineStart, autoplay: false);
      return;
    }
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    await seekMonitorTo(
      isProgramMonitor
          ? programStartForSegment(selected.order)
          : selected.start,
      autoplay: false,
    );
  }

  Future<void> jumpToSelectedClipEnd() async {
    final audioClip = selectedAudioClip;
    if (audioClip != null) {
      await seekMonitorTo(audioClip.timelineEnd, autoplay: false);
      return;
    }
    final overlay = selectedVideoOverlay;
    if (overlay != null) {
      await seekMonitorTo(overlay.timelineEnd, autoplay: false);
      return;
    }
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    final span = _programSpanForOrder(selected.order);
    await seekMonitorTo(
      isProgramMonitor && span != null ? span.sequenceEnd : selected.end,
      autoplay: false,
    );
  }

  Future<void> jumpToNextEditPoint() async {
    if (isProgramMonitor) {
      final threshold =
          _programPlayheadSeconds + timecodeFrameDurationSeconds / 2;
      for (final point in _programEditPoints) {
        if (point > threshold) {
          await _seekProgramTo(point, autoplay: false);
          return;
        }
      }
      return;
    }
    final current = currentPositionSeconds;
    final threshold = current + timecodeFrameDurationSeconds / 2;
    for (final point in _timelineEditPoints()) {
      if (point > threshold) {
        await seekTo(point, autoplay: false);
        return;
      }
    }
  }

  Future<void> jumpToPreviousEditPoint() async {
    if (isProgramMonitor) {
      final threshold =
          _programPlayheadSeconds - timecodeFrameDurationSeconds / 2;
      for (final point in _programEditPoints.reversed) {
        if (point < threshold) {
          await _seekProgramTo(point, autoplay: false);
          return;
        }
      }
      return;
    }
    final current = currentPositionSeconds;
    final threshold = current - timecodeFrameDurationSeconds / 2;
    for (final point in _timelineEditPoints().reversed) {
      if (point < threshold) {
        await seekTo(point, autoplay: false);
        return;
      }
    }
  }

  void setMarksFromTimelineMarker(int id) {
    final range = _timelineMarkerRange(id);
    if (range == null) {
      return;
    }
    _commitHistory();
    markIn = range.start;
    markOut = range.end;
    unawaited(seekTo(range.start, autoplay: false));
    notifyListeners();
  }

  void addSegmentFromTimelineMarker(int id) {
    final range = _timelineMarkerRange(id);
    if (range == null) {
      return;
    }
    final marker = range.marker;
    _commitHistory();
    segments = _reorderSegments([
      ...segments,
      HighlightSegment(
        order: segments.length + 1,
        start: range.start,
        end: range.end,
        reason: '마커 ${marker.label} 구간',
        script: marker.note.isNotEmpty
            ? marker.note
            : _scriptPreviewFor(range.start, range.end),
        source: 'marker',
        tags: ['marker'],
      ),
    ]);
    selectedSegmentOrder = segments.length;
    markIn = range.start;
    markOut = range.end;
    renderUrl = null;
    unawaited(seekTo(range.start, autoplay: false));
    notifyListeners();
  }

  void replaceTimelineWithMarkerSegments() {
    final ranges = _timelineMarkerRanges(enabledOnly: true);
    if (ranges.isEmpty) {
      return;
    }
    _commitHistory();
    segments = _reorderSegments([
      for (final range in ranges)
        HighlightSegment(
          order: 0,
          start: range.start,
          end: range.end,
          reason: '마커 ${range.marker.label} 구간',
          script: range.marker.note.isNotEmpty
              ? range.marker.note
              : _scriptPreviewFor(range.start, range.end),
          source: 'marker',
          tags: ['marker'],
        ),
    ]);
    selectedSegmentOrder = segments.isEmpty ? null : segments.first.order;
    if (segments.isNotEmpty) {
      markIn = segments.first.start;
      markOut = segments.last.end;
      unawaited(seekTo(segments.first.start, autoplay: false));
    }
    renderUrl = null;
    notifyListeners();
  }

  void markSelectedClip() {
    final selected =
        selectedSegment ?? _segmentAtTimelinePoint(currentPositionSeconds);
    if (selected == null) {
      return;
    }
    _commitHistory();
    markIn = selected.start;
    markOut = selected.end;
    selectedSegmentOrder = selected.order;
    notifyListeners();
  }

  void selectSegmentAtPlayhead() {
    selectSegmentAt(currentPositionSeconds);
  }

  void selectSegmentAt(double seconds) {
    final segment = _segmentAtTimelinePoint(seconds);
    if (segment == null ||
        (selectedSegmentOrder == segment.order &&
            selectedVideoOverlayId == null &&
            selectedAudioClipId == null)) {
      return;
    }
    selectedSegmentOrder = segment.order;
    selectedVideoOverlayId = null;
    selectedAudioClipId = null;
    notifyListeners();
  }

  void selectPreviousSegment() {
    _selectAdjacentSegment(-1);
  }

  void selectNextSegment() {
    _selectAdjacentSegment(1);
  }

  void _selectAdjacentSegment(int direction) {
    if (segments.isEmpty || direction == 0) {
      return;
    }
    final currentOrder = selectedSegmentOrder;
    final currentIndex = currentOrder == null
        ? -1
        : segments.indexWhere((segment) => segment.order == currentOrder);
    final fallbackIndex = direction > 0 ? 0 : segments.length - 1;
    final targetIndex = currentIndex < 0
        ? fallbackIndex
        : (currentIndex + direction).clamp(0, segments.length - 1).toInt();
    final targetOrder = segments[targetIndex].order;
    if (selectedSegmentOrder == targetOrder &&
        selectedVideoOverlayId == null &&
        selectedAudioClipId == null) {
      return;
    }
    selectedSegmentOrder = targetOrder;
    selectedVideoOverlayId = null;
    selectedAudioClipId = null;
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

  void toggleTimelineSnapping() {
    timelineSnappingEnabled = !timelineSnappingEnabled;
    notifyListeners();
  }

  void adjustTimelineTrackHeight(int direction) {
    if (direction == 0) {
      return;
    }
    const presets = [0.78, 1.0, 1.28];
    final currentIndex = presets.indexWhere(
      (value) => (value - timelineTrackHeightScale).abs() < 0.01,
    );
    final fallbackIndex = timelineTrackHeightScale < 0.9
        ? 0
        : timelineTrackHeightScale > 1.1
        ? 2
        : 1;
    final index = currentIndex < 0 ? fallbackIndex : currentIndex;
    final nextIndex = (index + direction).clamp(0, presets.length - 1);
    final next = presets[nextIndex];
    if ((next - timelineTrackHeightScale).abs() < 0.001) {
      return;
    }
    timelineTrackHeightScale = next;
    notifyListeners();
  }

  void cycleTimelineTrackHeight() {
    const presets = [0.78, 1.0, 1.28];
    final currentIndex = presets.indexWhere(
      (value) => (value - timelineTrackHeightScale).abs() < 0.01,
    );
    final index = currentIndex < 0 ? 1 : (currentIndex + 1) % presets.length;
    timelineTrackHeightScale = presets[index];
    notifyListeners();
  }

  void toggleVideoTrackTarget() {
    if (videoTrackTargeted && !audioTrack1Targeted && !audioTrack2Targeted) {
      return;
    }
    videoTrackTargeted = !videoTrackTargeted;
    notifyListeners();
  }

  void toggleAudioTrack1Target() {
    if (audioTrack1Targeted && !videoTrackTargeted && !audioTrack2Targeted) {
      return;
    }
    audioTrack1Targeted = !audioTrack1Targeted;
    notifyListeners();
  }

  void toggleAudioTrack2Target() {
    if (audioTrack2Targeted && !videoTrackTargeted && !audioTrack1Targeted) {
      return;
    }
    audioTrack2Targeted = !audioTrack2Targeted;
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

  void insertMarkedSegmentAtSelection() {
    if (!canInsertMarkedSegment) {
      return;
    }
    final insertIndex = selectedSegmentOrder == null
        ? segments.length
        : (selectedSegmentOrder! - 1).clamp(0, segments.length).toInt();
    final inserted = _markedEditSegment(
      order: insertIndex + 1,
      reason: 'Insert In/Out edit',
      source: 'manual+insert',
    );
    _commitHistory();
    final output = <HighlightSegment>[
      ...segments.take(insertIndex),
      inserted,
      ...segments.skip(insertIndex),
    ];
    segments = _reorderSegments(output);
    selectedSegmentOrder = insertIndex + 1;
    renderUrl = null;
    notifyListeners();
  }

  void overwriteSelectedSegmentWithMarks() {
    final selected = selectedSegment;
    if (selected == null || !canOverwriteMarkedSegment) {
      return;
    }
    final audioTargeted = audioTrack1Targeted || audioTrack2Targeted;
    final originalAudioStart = selected.effectiveAudioStart;
    final originalAudioEnd = selected.effectiveAudioEnd;
    var next = selected.copyWith(
      start: videoTrackTargeted ? markIn! : selected.start,
      end: videoTrackTargeted ? markOut! : selected.end,
      reason: 'Overwrite In/Out edit',
      script: videoTrackTargeted
          ? _scriptPreviewFor(markIn!, markOut!)
          : selected.script,
      source: _appendSource(selected.source, 'overwrite'),
      videoEnabled: videoTrackTargeted ? true : selected.videoEnabled,
      audioStart: audioTargeted ? markIn! : originalAudioStart,
      audioEnd: audioTargeted ? markOut! : originalAudioEnd,
      audioMuted: audioTargeted ? false : selected.audioMuted,
      audioVolume: audioTargeted ? selected.audioVolume : selected.audioVolume,
      audioChannel1Enabled: audioTargeted
          ? audioTrack1Targeted
          : selected.audioChannel1Enabled,
      audioChannel2Enabled: audioTargeted
          ? audioTrack2Targeted
          : selected.audioChannel2Enabled,
      audioLinked: videoTrackTargeted && audioTargeted,
    );
    if (videoTrackTargeted && !audioTargeted) {
      next = next.copyWith(
        audioStart: originalAudioStart,
        audioEnd: originalAudioEnd,
        audioLinked: false,
      );
    }
    updateSegment(next);
  }

  void liftMarkedRange() {
    _editMarkedRange(leaveGap: true);
  }

  void extractMarkedRange() {
    _editMarkedRange(leaveGap: false);
  }

  void liftSelectedSegment() {
    _editSelectedSegment(leaveGap: true);
  }

  void extractSelectedSegment() {
    _editSelectedSegment(leaveGap: false);
  }

  void _editSelectedSegment({required bool leaveGap}) {
    final selected = selectedSegment;
    if (selected == null || !canLiftOrExtractSelectedSegment) {
      return;
    }
    final output = <HighlightSegment>[];
    var changed = false;
    int? selectionIndex;
    for (final segment in segments) {
      if (segment.order != selected.order) {
        output.add(segment);
        continue;
      }
      changed = true;
      selectionIndex = output.length;
      if (leaveGap || !allTrackTargetsEnabled) {
        final gap = allTrackTargetsEnabled
            ? _gapSegmentForRange(segment, segment.start, segment.end)
            : _targetedGapSegmentForRange(segment, segment.start, segment.end);
        if (gap != null) {
          output.add(gap);
        }
      }
    }
    if (!changed) {
      return;
    }
    _commitHistory();
    segments = _reorderSegments(output);
    selectedSegmentOrder = segments.isEmpty
        ? null
        : ((selectionIndex ?? segments.length - 1)
                  .clamp(0, segments.length - 1)
                  .toInt() +
              1);
    renderUrl = null;
    notifyListeners();
  }

  void _editMarkedRange({required bool leaveGap}) {
    if (!canLiftOrExtractMarkedRange) {
      return;
    }
    final useTrackTargetGap = leaveGap || !allTrackTargetsEnabled;
    final rangeStart = _snapToFrame(_clampProjectTime(markIn!));
    final rangeEnd = _snapToFrame(_clampProjectTime(markOut!));
    if (rangeEnd - rangeStart < timecodeFrameDurationSeconds) {
      return;
    }

    final output = <HighlightSegment>[];
    int? selectionIndex;
    var changed = false;
    for (final segment in segments) {
      if (!_segmentOverlapsRange(segment, rangeStart, rangeEnd)) {
        output.add(segment);
        continue;
      }

      changed = true;
      selectionIndex ??= output.length;
      final overlapStart = _snapToFrame(math.max(segment.start, rangeStart));
      final overlapEnd = _snapToFrame(math.min(segment.end, rangeEnd));
      final before = _trimSegmentToRange(
        segment,
        segment.start,
        overlapStart,
        sourceSuffix: leaveGap ? 'lift' : 'extract',
        reasonSuffix: leaveGap ? 'lift before' : 'extract before',
      );
      final after = _trimSegmentToRange(
        segment,
        overlapEnd,
        segment.end,
        sourceSuffix: leaveGap ? 'lift' : 'extract',
        reasonSuffix: leaveGap ? 'lift after' : 'extract after',
      );
      if (before != null) {
        output.add(before);
      }
      if (useTrackTargetGap) {
        final gap = allTrackTargetsEnabled
            ? _gapSegmentForRange(segment, overlapStart, overlapEnd)
            : _targetedGapSegmentForRange(segment, overlapStart, overlapEnd);
        if (gap != null) {
          output.add(gap);
        }
      }
      if (after != null) {
        output.add(after);
      }
    }

    if (!changed) {
      return;
    }
    _commitHistory();
    segments = _reorderSegments(output);
    selectedSegmentOrder = segments.isEmpty
        ? null
        : ((selectionIndex ?? segments.length - 1)
                  .clamp(0, segments.length - 1)
                  .toInt() +
              1);
    renderUrl = null;
    notifyListeners();
  }

  void addEditAtPlayhead() {
    addEditAt(currentPositionSeconds);
  }

  void addEditAt(double seconds) {
    if (!hasAnyTrackTarget || !targetedTracksUnlocked) {
      return;
    }
    final point = _snapToFrame(_clampProjectTime(seconds));
    final target = _segmentForEditAt(point);
    if (target == null) {
      return;
    }
    _splitSegmentAt(target, point);
  }

  void addEditToAllTracksAtPlayhead() {
    addEditToAllTracksAt(currentPositionSeconds);
  }

  void addEditToAllTracksAt(double seconds) {
    if (videoTrackLocked || anyAudioTrackEditLocked) {
      return;
    }
    final point = _snapToFrame(_clampProjectTime(seconds));
    final target = _segmentAtTimelinePoint(point);
    if (target == null) {
      return;
    }
    _splitSegmentAt(target, point);
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
    setSelectedTransitionType('cross_dissolve');
  }

  void applyDefaultAudioTransition() {
    setSelectedTransitionType('cross_dissolve');
  }

  void setSelectedTransitionType(String value) {
    final selected = selectedSegment;
    if (!canApplySelectedTransition || selected == null) {
      return;
    }
    final normalized = normalizeClipTransitionType(value);
    final maxDuration = selectedTransitionMaxDuration;
    final duration = normalized == 'cut'
        ? 0.0
        : (selected.transitionDuration > 0
              ? math.min(selected.transitionDuration, maxDuration)
              : math.min(0.30, maxDuration));
    if (selected.transitionType == normalized &&
        (selected.transitionDuration - duration).abs() < 0.001) {
      return;
    }
    updateSegment(
      selected.copyWith(
        transitionType: normalized,
        transitionDuration: duration,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedTransitionDuration(double value) {
    final selected = selectedSegment;
    if (!canApplySelectedTransition ||
        selected == null ||
        selected.transitionType == 'cut') {
      return;
    }
    final maxDuration = selectedTransitionMaxDuration;
    if (maxDuration < 0.10) {
      return;
    }
    final duration = value.clamp(0.10, maxDuration).toDouble();
    if ((selected.transitionDuration - duration).abs() < 0.001) {
      return;
    }
    updateSegment(
      selected.copyWith(
        transitionDuration: duration,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void detachAudioForSelectedSegment() {
    final selected = selectedSegment;
    if (selected == null || anyAudioTrackEditLocked) {
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
    if (selected == null || anyAudioTrackEditLocked) {
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

  void syncSelectedAudioToVideoLength() {
    final selected = selectedSegment;
    if (selected == null ||
        anyAudioTrackEditLocked ||
        !segmentHasAudioLengthDrift(selected)) {
      return;
    }
    updateSegment(_syncSegmentAudioLength(selected));
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
    if (selected == null || anyAudioTrackEditLocked) {
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
    if (selected == null || _audioTrackEditLocked(channel)) {
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

  void toggleSelectedClipEnabled() {
    if (selectedAudioClip != null) {
      toggleSelectedAudioClipEnabled();
      return;
    }
    if (selectedVideoOverlay != null) {
      toggleSelectedVideoOverlayEnabled();
      return;
    }
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked || anyAudioTrackEditLocked) {
      return;
    }
    final enabled = selected.videoEnabled || !selected.audioMuted;
    updateSegment(
      selected.copyWith(
        videoEnabled: !enabled,
        audioMuted: enabled,
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

  void setSelectedVideoOpacity(double value) {
    _updateSelectedMotion(videoOpacity: value.clamp(0.0, 1.0).toDouble());
  }

  void setSelectedVideoScale(double value) {
    _updateSelectedMotion(videoScale: value.clamp(1.0, 3.0).toDouble());
  }

  void setSelectedVideoPositionX(double value) {
    _updateSelectedMotion(videoPositionX: value.clamp(-1.0, 1.0).toDouble());
  }

  void setSelectedVideoPositionY(double value) {
    _updateSelectedMotion(videoPositionY: value.clamp(-1.0, 1.0).toDouble());
  }

  void setSelectedVideoRotation(double value) {
    _updateSelectedMotion(videoRotation: value.clamp(-180.0, 180.0).toDouble());
  }

  void _updateSelectedMotion({
    double? videoOpacity,
    double? videoScale,
    double? videoPositionX,
    double? videoPositionY,
    double? videoRotation,
  }) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    if (selected.motionKeyframes.isNotEmpty) {
      final time = selectedMotionLocalTime;
      final current = selectedMotionValues;
      final next = current.copyWith(
        time: time,
        opacity: videoOpacity,
        scale: videoScale,
        positionX: videoPositionX,
        positionY: videoPositionY,
        rotation: videoRotation,
      );
      final keyframes = [...selected.motionKeyframes];
      final existingIndex = selectedMotionKeyframeIndex;
      if (existingIndex >= 0) {
        keyframes[existingIndex] = next;
      } else {
        keyframes.add(next);
      }
      keyframes.sort((a, b) => a.time.compareTo(b.time));
      updateSegment(
        selected.copyWith(
          motionKeyframes: keyframes,
          source: selected.source == 'ai' ? 'ai+manual' : selected.source,
        ),
      );
      return;
    }
    updateSegment(
      selected.copyWith(
        videoOpacity: videoOpacity,
        videoScale: videoScale,
        videoPositionX: videoPositionX,
        videoPositionY: videoPositionY,
        videoRotation: videoRotation,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void addOrUpdateSelectedMotionKeyframe() {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    final current = selectedMotionValues.copyWith(
      time: selectedMotionLocalTime,
    );
    final keyframes = [...selected.motionKeyframes];
    final existingIndex = selectedMotionKeyframeIndex;
    if (existingIndex >= 0) {
      keyframes[existingIndex] = current;
    } else {
      keyframes.add(current);
    }
    keyframes.sort((a, b) => a.time.compareTo(b.time));
    updateSegment(
      selected.copyWith(
        motionKeyframes: keyframes,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void removeSelectedMotionKeyframe() {
    final selected = selectedSegment;
    final index = selectedMotionKeyframeIndex;
    if (selected == null || videoTrackLocked || index < 0) {
      return;
    }
    final removed = selected.motionKeyframes[index];
    final keyframes = [...selected.motionKeyframes]..removeAt(index);
    updateSegment(
      selected.copyWith(
        videoOpacity: keyframes.isEmpty ? removed.opacity : null,
        videoScale: keyframes.isEmpty ? removed.scale : null,
        videoPositionX: keyframes.isEmpty ? removed.positionX : null,
        videoPositionY: keyframes.isEmpty ? removed.positionY : null,
        videoRotation: keyframes.isEmpty ? removed.rotation : null,
        motionKeyframes: keyframes,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  Future<void> jumpToSelectedMotionKeyframe({required bool next}) async {
    final selected = selectedSegment;
    if (selected == null || selected.motionKeyframes.isEmpty) {
      return;
    }
    final current = selectedMotionLocalTime;
    final threshold = timecodeFrameDurationSeconds / 2;
    MotionKeyframe? target;
    if (next) {
      for (final keyframe in selected.motionKeyframes) {
        if (keyframe.time > current + threshold) {
          target = keyframe;
          break;
        }
      }
    } else {
      for (final keyframe in selected.motionKeyframes.reversed) {
        if (keyframe.time < current - threshold) {
          target = keyframe;
          break;
        }
      }
    }
    if (target == null) {
      return;
    }
    final targetSeconds = isProgramMonitor
        ? programStartForSegment(selected.order) + target.time
        : selected.start + target.time * selected.playbackSpeed;
    await seekMonitorTo(targetSeconds, autoplay: false);
  }

  void resetSelectedMotion() {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        videoOpacity: 1,
        videoScale: 1,
        videoPositionX: 0,
        videoPositionY: 0,
        videoRotation: 0,
        motionKeyframes: const [],
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

  void setSelectedFocusX(double value) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        focusX: value.clamp(0.0, 1.0).toDouble(),
        focusConfidence: 0,
        focusKeyframes: const [],
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedFocusY(double value) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        focusY: value.clamp(0.0, 1.0).toDouble(),
        focusConfidence: 0,
        focusKeyframes: const [],
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void resetSelectedFocus() {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        focusX: 0.5,
        focusY: 0.42,
        focusConfidence: 0,
        focusKeyframes: const [],
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
    if (selected == null || anyAudioTrackEditLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioPan: value.clamp(-1.0, 1.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedAudioSourceChannelLeft(int channel) {
    _setSelectedAudioSourceChannel(channel, left: true);
  }

  void setSelectedAudioSourceChannelRight(int channel) {
    _setSelectedAudioSourceChannel(channel, left: false);
  }

  void _setSelectedAudioSourceChannel(int channel, {required bool left}) {
    final selected = selectedSegment;
    if (selected == null || anyAudioTrackEditLocked) {
      return;
    }
    final safeChannel = channel.clamp(1, sourceAudioChannelCount).toInt();
    updateSegment(
      selected.copyWith(
        audioSourceChannelLeft: left
            ? safeChannel
            : selected.audioSourceChannelLeft,
        audioSourceChannelRight: left
            ? selected.audioSourceChannelRight
            : safeChannel,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void resetSelectedAudioPan() {
    setSelectedAudioPan(0);
  }

  void toggleSelectedAudioNormalize() {
    final selected = selectedSegment;
    if (selected == null || anyAudioTrackEditLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioNormalize: !selected.audioNormalize,
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void setSelectedAudioLoudnessTarget(double target) {
    final selected = selectedSegment;
    if (selected == null || anyAudioTrackEditLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        audioNormalize: true,
        audioLoudnessTarget: target.clamp(-24.0, -12.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void toggleAllAudioMute() {
    setAllAudioMute(!allAudioMuted);
  }

  void toggleAllAudioChannel1() {
    setAllAudioChannelEnabled(1, !allAudioChannel1Enabled);
  }

  void toggleAllAudioChannel2() {
    setAllAudioChannelEnabled(2, !allAudioChannel2Enabled);
  }

  void soloAudioChannel1Track() {
    setAudioChannelSolo(1);
  }

  void soloAudioChannel2Track() {
    setAudioChannelSolo(2);
  }

  void setAllAudioChannelEnabled(int channel, bool enabled) {
    if (_audioTrackEditLocked(channel) || segments.isEmpty) {
      return;
    }
    final otherChannelLocked = channel == 1
        ? audioTrack2EditLocked
        : audioTrack1EditLocked;
    var changed = false;
    final nextSegments = [
      for (final segment in segments)
        () {
          var channel1 = segment.audioChannel1Enabled;
          var channel2 = segment.audioChannel2Enabled;
          if (channel == 1) {
            channel1 = enabled;
            if (!channel1 && !channel2) {
              if (otherChannelLocked) {
                return segment;
              }
              channel2 = true;
            }
          } else if (channel == 2) {
            channel2 = enabled;
            if (!channel1 && !channel2) {
              if (otherChannelLocked) {
                return segment;
              }
              channel1 = true;
            }
          }
          if (channel1 == segment.audioChannel1Enabled &&
              channel2 == segment.audioChannel2Enabled) {
            return segment;
          }
          changed = true;
          return segment.copyWith(
            audioChannel1Enabled: channel1,
            audioChannel2Enabled: channel2,
            source: segment.source == 'ai' ? 'ai+manual' : segment.source,
          );
        }(),
    ];
    if (!changed) {
      return;
    }
    _commitHistory();
    segments = nextSegments;
    renderUrl = null;
    notifyListeners();
  }

  void setAudioChannelSolo(int channel) {
    if (anyAudioTrackEditLocked || segments.isEmpty) {
      return;
    }
    final soloChannel1 = channel == 1;
    var changed = false;
    final nextSegments = [
      for (final segment in segments)
        () {
          final channel1 = soloChannel1;
          final channel2 = !soloChannel1;
          if (segment.audioChannel1Enabled == channel1 &&
              segment.audioChannel2Enabled == channel2 &&
              !segment.audioMuted) {
            return segment;
          }
          changed = true;
          return segment.copyWith(
            audioChannel1Enabled: channel1,
            audioChannel2Enabled: channel2,
            audioMuted: false,
            source: segment.source == 'ai' ? 'ai+manual' : segment.source,
          );
        }(),
    ];
    if (!changed) {
      return;
    }
    _commitHistory();
    segments = nextSegments;
    renderUrl = null;
    notifyListeners();
  }

  void setAllAudioMute(bool muted) {
    if (anyAudioTrackEditLocked ||
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
    if (allAudioTracksEditLocked) {
      audioTrackLocked = false;
      audioTrack1Locked = false;
      audioTrack2Locked = false;
    } else {
      audioTrackLocked = true;
    }
    notifyListeners();
  }

  void toggleAudioTrack1Lock() {
    audioTrack1Locked = !audioTrack1Locked;
    notifyListeners();
  }

  void toggleAudioTrack2Lock() {
    audioTrack2Locked = !audioTrack2Locked;
    notifyListeners();
  }

  bool _audioTrackEditLocked(int channel) {
    return channel == 1 ? audioTrack1EditLocked : audioTrack2EditLocked;
  }

  void setSelectedAudioVolume(double value) {
    final selected = selectedSegment;
    if (selected == null || anyAudioTrackEditLocked) {
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
    if (selected == null || selected.audioLinked || anyAudioTrackEditLocked) {
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

  void slipSelectedSegmentFrames(int frameDelta) {
    final selected = selectedSegment;
    if (selected == null ||
        frameDelta == 0 ||
        videoTrackLocked ||
        anyAudioTrackEditLocked) {
      return;
    }

    final sourceFrames = secondsToTimecodeFrame(timelineSourceDuration);
    final startFrame = secondsToTimecodeFrame(selected.start);
    final endFrame = secondsToTimecodeFrame(selected.end);
    final clipFrames = math.max(1, endFrame - startFrame);
    if (sourceFrames <= clipFrames) {
      return;
    }

    final maxStartFrame = sourceFrames - clipFrames;
    final nextStartFrame = (startFrame + frameDelta)
        .clamp(0, maxStartFrame)
        .toInt();
    if (nextStartFrame == startFrame) {
      return;
    }
    final actualFrameDelta = nextStartFrame - startFrame;
    final nextEndFrame = nextStartFrame + clipFrames;
    final source = _appendSource(selected.source, 'slip');

    var next = selected.copyWith(
      start: timecodeFrameToSeconds(nextStartFrame),
      end: timecodeFrameToSeconds(nextEndFrame),
      source: source,
    );
    if (selected.audioLinked) {
      next = next.copyWith(
        audioStart: next.start,
        audioEnd: next.end,
        audioLinked: true,
      );
    } else {
      final audioStartFrame = secondsToTimecodeFrame(
        selected.effectiveAudioStart,
      );
      final audioEndFrame = secondsToTimecodeFrame(selected.effectiveAudioEnd);
      final audioFrames = math.max(1, audioEndFrame - audioStartFrame);
      final maxAudioStartFrame = math.max(0, sourceFrames - audioFrames);
      final nextAudioStartFrame = (audioStartFrame + actualFrameDelta)
          .clamp(0, maxAudioStartFrame)
          .toInt();
      next = next.copyWith(
        audioStart: timecodeFrameToSeconds(nextAudioStartFrame),
        audioEnd: timecodeFrameToSeconds(nextAudioStartFrame + audioFrames),
        audioLinked: false,
      );
    }
    updateSegment(next);
  }

  void rollSelectedIncomingEditFrames(int frameDelta) {
    _rollSelectedEditFrames(frameDelta, incoming: true);
  }

  void rollSelectedOutgoingEditFrames(int frameDelta) {
    _rollSelectedEditFrames(frameDelta, incoming: false);
  }

  void _rollSelectedEditFrames(int frameDelta, {required bool incoming}) {
    if (frameDelta == 0 || videoTrackLocked || anyAudioTrackEditLocked) {
      return;
    }
    final order = selectedSegmentOrder;
    if (order == null || segments.length < 2) {
      return;
    }
    final index = segments.indexWhere((segment) => segment.order == order);
    if (index < 0 ||
        (incoming && index == 0) ||
        (!incoming && index >= segments.length - 1)) {
      return;
    }

    final sourceFrames = secondsToTimecodeFrame(timelineSourceDuration);
    if (sourceFrames <= 1) {
      return;
    }
    final leftIndex = incoming ? index - 1 : index;
    final rightIndex = incoming ? index : index + 1;
    final left = segments[leftIndex];
    final right = segments[rightIndex];
    final leftStartFrame = secondsToTimecodeFrame(left.start);
    final leftEndFrame = secondsToTimecodeFrame(left.end);
    final rightStartFrame = secondsToTimecodeFrame(right.start);
    final rightEndFrame = secondsToTimecodeFrame(right.end);
    const minimumClipFrames = 1;
    final minDelta = math.max(
      leftStartFrame + minimumClipFrames - leftEndFrame,
      -rightStartFrame,
    );
    final maxDelta = math.min(
      sourceFrames - leftEndFrame,
      rightEndFrame - minimumClipFrames - rightStartFrame,
    );
    final actualDelta = frameDelta.clamp(minDelta, maxDelta).toInt();
    if (actualDelta == 0) {
      return;
    }

    final nextLeftEnd = timecodeFrameToSeconds(leftEndFrame + actualDelta);
    final nextRightStart = timecodeFrameToSeconds(
      rightStartFrame + actualDelta,
    );
    final nextSegments = List<HighlightSegment>.of(segments);
    nextSegments[leftIndex] = left.copyWith(
      end: nextLeftEnd,
      audioEnd: left.audioLinked ? nextLeftEnd : left.audioEnd,
      source: _appendSource(left.source, 'roll'),
    );
    nextSegments[rightIndex] = right.copyWith(
      start: nextRightStart,
      audioStart: right.audioLinked ? nextRightStart : right.audioStart,
      source: _appendSource(right.source, 'roll'),
    );

    _commitHistory();
    segments = _reorderSegments(nextSegments);
    selectedSegmentOrder = order.clamp(1, segments.length).toInt();
    renderUrl = null;
    notifyListeners();
  }

  void setSelectedPlaybackSpeed(double value) {
    final selected = selectedSegment;
    if (selected == null || videoTrackLocked || anyAudioTrackEditLocked) {
      return;
    }
    updateSegment(
      selected.copyWith(
        playbackSpeed: value.clamp(0.25, 4.0).toDouble(),
        source: selected.source == 'ai' ? 'ai+manual' : selected.source,
      ),
    );
  }

  void rateStretchSelectedToMarks() {
    final selected = selectedSegment;
    if (selected == null ||
        !hasValidMarks ||
        videoTrackLocked ||
        anyAudioTrackEditLocked) {
      return;
    }
    final targetOutputDuration = markOut! - markIn!;
    if (targetOutputDuration < timecodeFrameDurationSeconds ||
        selected.duration < timecodeFrameDurationSeconds) {
      return;
    }
    final nextSpeed = (selected.duration / targetOutputDuration)
        .clamp(0.25, 4.0)
        .toDouble();
    if ((selected.playbackSpeed - nextSpeed).abs() < 0.001) {
      return;
    }
    updateSegment(
      selected.copyWith(
        playbackSpeed: nextSpeed,
        source: _appendSource(selected.source, 'rate-stretch'),
      ),
    );
  }

  void setSelectedAudioFadeIn(double value) {
    final selected = selectedSegment;
    if (selected == null || anyAudioTrackEditLocked) {
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
    if (selected == null || anyAudioTrackEditLocked) {
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

  void copySelectedSegment() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    _clipClipboard = selected;
    notifyListeners();
  }

  void cutSelectedSegment() {
    final selected = selectedSegment;
    if (selected == null) {
      return;
    }
    _clipClipboard = selected;
    deleteSelectedSegment();
  }

  void pasteClipboardSegment() {
    final clip = _clipClipboard;
    if (clip == null) {
      return;
    }
    _commitHistory();
    final insertIndex = _clipboardPasteIndex();
    final pasted = clip.copyWith(
      order: insertIndex + 1,
      reason: '${clip.reason} / paste',
      source: _appendSource(clip.source, 'paste'),
    );
    final output = <HighlightSegment>[
      ...segments.take(insertIndex),
      pasted,
      ...segments.skip(insertIndex),
    ];
    segments = _reorderSegments(output);
    selectedSegmentOrder = (insertIndex + 1).clamp(1, segments.length).toInt();
    renderUrl = null;
    notifyListeners();
  }

  int _clipboardPasteIndex() {
    final order = selectedSegmentOrder;
    if (order != null) {
      final selectedIndex = segments.indexWhere(
        (segment) => segment.order == order,
      );
      if (selectedIndex >= 0) {
        return selectedIndex + 1;
      }
    }
    return segments.length;
  }

  void undo() {
    if (!canUndo) {
      return;
    }
    final current = _captureSnapshot();
    final previous = _undoStack.removeLast();
    _redoStack.add(current);
    _restoreSnapshot(previous);
    _markProjectDirty();
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
    _markProjectDirty();
    renderUrl = null;
    notifyListeners();
  }

  void restoreHistoryDepth(int depth) {
    final steps = depth.clamp(0, _undoStack.length);
    if (steps == 0) {
      return;
    }
    for (var index = 0; index < steps; index++) {
      final current = _captureSnapshot();
      final previous = _undoStack.removeLast();
      _redoStack.add(current);
      _restoreSnapshot(previous);
    }
    _markProjectDirty();
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

  void deleteSelectedTimelineItem() {
    if (selectedAudioClip != null) {
      deleteSelectedAudioClip();
      return;
    }
    if (selectedVideoOverlay != null) {
      deleteSelectedVideoOverlay();
      return;
    }
    deleteSelectedSegment();
  }

  void closeSelectedTimelineGap() {
    final selected = selectedSegment;
    if (selected == null || !_segmentIsTimelineGap(selected)) {
      return;
    }
    deleteSelectedSegment();
  }

  void closeTimelineGaps() {
    if (!hasTimelineGaps) {
      return;
    }
    final previousOrder = selectedSegmentOrder;
    _commitHistory();
    segments = _reorderSegments([
      for (final segment in segments)
        if (!_segmentIsTimelineGap(segment)) segment,
    ]);
    selectedSegmentOrder = segments.isEmpty
        ? null
        : (previousOrder ?? segments.first.order)
              .clamp(1, segments.length)
              .toInt();
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
    _splitSegmentAt(selected, seconds);
  }

  void _splitSegmentAt(HighlightSegment selected, double seconds) {
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
    if (segments.isEmpty || anyAudioTrackEditLocked) {
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
    if (result == null &&
        segments.length <= 1 &&
        !_autoFixCanRemoveLastSegment(action)) {
      return;
    }
    _commitHistory();
    if (action == AutoFixAction.hideFiller) {
      captions = _hideFillerCaptionsForSegment(segments[index]);
    }
    if (result == null) {
      if (segments.length <= 1 && !_autoFixCanRemoveLastSegment(action)) {
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
          if (workingSegments.length <= 1 &&
              !_autoFixCanRemoveLastSegment(item.action)) {
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
      _markProjectDirty();
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
      final strategyPoolLimit = math.max(strategy.maxCandidates, maxCandidates);
      for (final seed in _rankSegmentsForShortsStrategy(
        strategy.kind,
        ranked,
      )) {
        if (strategyCount >= strategyPoolLimit) {
          break;
        }
        if (_skipSeedForShortsStrategy(strategy.kind, seed)) {
          continue;
        }
        final group = _buildShortsGroup(
          seed,
          strategyUsed,
          strategyKind: strategy.kind,
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

    bool addCandidate(ShortsCandidate candidate) {
      if (selected.length >= maxCandidates) {
        return false;
      }
      final signature = _shortsCandidateSignature(candidate);
      if (signatures.contains(signature) ||
          _shortsCandidateTooSimilar(candidate, selected)) {
        return false;
      }
      signatures.add(signature);
      selected.add(candidate);
      return true;
    }

    for (final strategy in strategies) {
      final strategyCandidates =
          pool
              .where((candidate) => candidate.strategyKind == strategy.kind)
              .toList()
            ..sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
      for (final candidate in strategyCandidates) {
        if (addCandidate(candidate)) {
          break;
        }
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

  bool _shortsCandidateTooSimilar(
    ShortsCandidate candidate,
    List<ShortsCandidate> selected,
  ) {
    for (final existing in selected) {
      final overlap = _shortsCandidateTemporalOverlapRatio(candidate, existing);
      if (overlap >= 0.72) {
        return true;
      }
      final textSimilarity = _shortsCandidateTextSimilarity(
        candidate,
        existing,
      );
      if (overlap >= 0.35 && textSimilarity >= 0.82) {
        return true;
      }
    }
    return false;
  }

  double _shortsCandidateTemporalOverlapRatio(
    ShortsCandidate left,
    ShortsCandidate right,
  ) {
    final leftIntervals = _mergedCandidateIntervals(left);
    final rightIntervals = _mergedCandidateIntervals(right);
    final leftDuration = _intervalsDuration(leftIntervals);
    final rightDuration = _intervalsDuration(rightIntervals);
    final denominator = math.min(leftDuration, rightDuration);
    if (denominator <= 0) {
      return 0;
    }

    var overlap = 0.0;
    for (final leftInterval in leftIntervals) {
      for (final rightInterval in rightIntervals) {
        overlap += math.max(
          0.0,
          math.min(leftInterval.end, rightInterval.end) -
              math.max(leftInterval.start, rightInterval.start),
        );
      }
    }
    return (overlap / denominator).clamp(0.0, 1.0).toDouble();
  }

  List<({double start, double end})> _mergedCandidateIntervals(
    ShortsCandidate candidate,
  ) {
    final intervals =
        candidate.segments
            .where((segment) => segment.end > segment.start)
            .map((segment) => (start: segment.start, end: segment.end))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    if (intervals.isEmpty) {
      return const [];
    }

    final merged = <({double start, double end})>[];
    var current = intervals.first;
    for (final interval in intervals.skip(1)) {
      if (interval.start <= current.end) {
        current = (
          start: current.start,
          end: math.max(current.end, interval.end),
        );
      } else {
        merged.add(current);
        current = interval;
      }
    }
    merged.add(current);
    return merged;
  }

  double _intervalsDuration(List<({double start, double end})> intervals) {
    return intervals.fold<double>(
      0,
      (total, interval) => total + math.max(0.0, interval.end - interval.start),
    );
  }

  double _shortsCandidateTextSimilarity(
    ShortsCandidate left,
    ShortsCandidate right,
  ) {
    final leftTokens = _shortsCandidateTokens(left);
    final rightTokens = _shortsCandidateTokens(right);
    if (leftTokens.isEmpty || rightTokens.isEmpty) {
      return 0;
    }
    final intersection = leftTokens.intersection(rightTokens).length;
    final union = leftTokens.union(rightTokens).length;
    return union == 0 ? 0 : intersection / union;
  }

  Set<String> _shortsCandidateTokens(ShortsCandidate candidate) {
    final text = candidate.segments
        .map(
          (segment) =>
              '${segment.reason} ${segment.script} ${segment.tags.join(' ')}',
        )
        .join(' ')
        .toLowerCase();
    return RegExp(r'[가-힣A-Za-z0-9]{2,}')
        .allMatches(text)
        .map((match) => match.group(0)!)
        .where(
          (token) => !const {
            '그리고',
            '하지만',
            '이번',
            '관련',
            '합니다',
            '했습니다',
            'the',
            'and',
            'this',
          }.contains(token),
        )
        .toSet();
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
            '검증팩트',
            '영향',
            '대응',
            '출처확인',
            '시간축',
            '발언',
          }) &&
          !_containsAny(seed.reason, const ['뉴스', '속보', '단독', '발언', '확인']);
    }
    if (strategyKind == 'info') {
      return !_segmentHasAnyTag(seed, const {
            '문제해결',
            '구체성',
            '비교',
            '근거',
            '검증팩트',
          }) &&
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
                  '검증팩트',
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
            _tagMatchCount(segment, const {'문제해결', '구체성', '비교', '근거', '검증팩트'}) *
                12 +
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

  bool _segmentHasNewsSignal(HighlightSegment segment) {
    final text =
        '${segment.reason} ${segment.script} ${segment.tags.join(' ')}';
    return _segmentHasAnyTag(segment, _newsSignalTags) ||
        _containsAny(text, const ['뉴스', '속보', '단독', '공식', '발표', '확인']);
  }

  bool _segmentHasVerificationSignal(HighlightSegment segment) {
    final text =
        '${segment.reason} ${segment.script} ${segment.tags.join(' ')}';
    return _segmentHasAnyTag(segment, _verificationTags) ||
        _containsAny(text, const ['공식', '출처', '근거', '검증', '확인', '발언']);
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
    final explicitRole = _explicitShortsStoryRole(segment);
    if (explicitRole == 'risk') {
      return strategyKind == 'risk' ? 'risk' : 'evidence';
    }
    if (_segmentHasRiskSignal(segment)) {
      return strategyKind == 'risk' ? 'risk' : 'evidence';
    }
    if (explicitRole != null) {
      return explicitRole;
    }
    if (_containsAny(text, const ['결과', '핵심', '충격', '문제', '후킹', '유지율'])) {
      return 'hook';
    }
    if (_segmentHasAnyTag(segment, const {
          '근거',
          '검증팩트',
          '출처확인',
          '발언',
          '뉴스핵심',
        }) ||
        _containsAny(text, const ['근거', '공식', '발표', '확인', '발언', '검증'])) {
      return 'evidence';
    }
    if (_segmentHasAnyTag(segment, const {'문제해결', '구체성', '비교'}) ||
        _containsAny(text, const ['방법', '이유', '원인', '차이', '비교', '수치'])) {
      return 'context';
    }
    if (_segmentHasAnyTag(segment, const {'대응'}) ||
        _containsAny(text, const ['대응', '조치', '대책', '결론', '앞으로'])) {
      return 'resolution';
    }
    if (_segmentHasAnyTag(segment, const {'영향'}) ||
        _containsAny(text, const ['영향', '피해', '우려', '시민', '주민'])) {
      return 'impact';
    }
    if (_segmentHasAnyTag(segment, const {'CTA'})) {
      return 'close';
    }
    return strategyKind == 'hook' ? 'context' : 'evidence';
  }

  String? _explicitShortsStoryRole(HighlightSegment segment) {
    for (final tag in segment.tags) {
      switch (tag) {
        case 'Story:Hook':
          return 'hook';
        case 'Story:Risk':
          return 'risk';
        case 'Story:Context':
          return 'context';
        case 'Story:Evidence':
          return 'evidence';
        case 'Story:Impact':
          return 'impact';
        case 'Story:Resolution':
          return 'resolution';
        case 'Story:Close':
          return 'close';
      }
    }
    return null;
  }

  int _shortsRoleRank(String role) {
    return switch (role) {
      'hook' => 0,
      'risk' => 1,
      'context' => 1,
      'evidence' => 2,
      'impact' => 3,
      'resolution' => 4,
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
      'resolution' => (0.35, isLast ? 1.20 : 0.80),
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
      'resolution' => 'Story:Resolution',
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
      'resolution' => 'Resolution',
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
    if (roles.contains('impact')) {
      score += 8;
    }
    if (roles.contains('resolution') || roles.contains('close')) {
      score += 8;
    }
    if (roles.contains('hook') &&
        roles.contains('evidence') &&
        roles.contains('impact') &&
        roles.contains('resolution')) {
      score += 10;
    }
    for (var index = 1; index < roles.length; index++) {
      if (_shortsRoleRank(roles[index]) < _shortsRoleRank(roles[index - 1])) {
        score -= 8;
      }
    }
    return score.clamp(0.0, 100.0).toDouble();
  }

  double _shortsCompletionScore(
    List<HighlightSegment> input,
    String strategyKind,
  ) {
    if (input.isEmpty) {
      return 0;
    }
    final roles = [
      for (final segment in input) _shortsStoryRole(segment, strategyKind),
    ];
    final tagText = input
        .expand((segment) => segment.tags)
        .join(' ')
        .toLowerCase();
    final scriptText = input
        .map((segment) => '${segment.reason} ${segment.script}')
        .join(' ')
        .toLowerCase();
    final hasHook =
        roles.first == 'hook' ||
        roles.contains('hook') ||
        _containsAny(scriptText, const ['결과', '핵심', '문제', '왜', '충격']);
    final hasEvidence =
        roles.contains('evidence') ||
        tagText.contains('근거') ||
        tagText.contains('검증팩트') ||
        tagText.contains('출처확인') ||
        _containsAny(scriptText, const ['공식', '출처', '확인', '발표', '보고서']);
    final hasContext =
        roles.contains('context') ||
        tagText.contains('문제해결') ||
        tagText.contains('구체성') ||
        _containsAny(scriptText, const ['원인', '이유', '방법', '차이']);
    final hasConsequence =
        roles.contains('impact') ||
        roles.contains('resolution') ||
        roles.contains('close') ||
        tagText.contains('영향') ||
        tagText.contains('대응') ||
        _containsAny(scriptText, const ['영향', '대응', '결론', '다음', '앞으로']);

    var score = 30.0;
    if (hasHook) {
      score += 20;
    } else {
      score -= 10;
    }
    if (hasEvidence || hasContext) {
      score += 18;
    } else {
      score -= 8;
    }
    if (hasEvidence && hasContext) {
      score += 6;
    }
    if (hasConsequence) {
      score += 18;
    } else {
      score -= 10;
    }
    if (roles.length >= 3) {
      score += 8;
    }
    if (const {'impact', 'resolution', 'close'}.contains(roles.last)) {
      score += 6;
    }
    for (var index = 1; index < roles.length; index++) {
      if (_shortsRoleRank(roles[index]) < _shortsRoleRank(roles[index - 1])) {
        score -= 5;
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
        hookScore: 0,
        completionScore: 0,
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
    final storyIssues = _shortsStoryIssues(
      candidateSegments,
      candidate.strategyKind,
      duration: duration,
    );
    final completionScore = _shortsCompletionScore(
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
        (durationScore * 0.15) +
        (highlightScore * 0.22) +
        (hookScore * 0.18) +
        (signalScore * 0.13) +
        (completionScore * 0.13) +
        (audioScore * 0.10) +
        (captionScore * 0.05) +
        (storyScore * 0.04) -
        riskPenalty -
        offlinePenalty;
    final score = quality.clamp(0.0, 100.0).toDouble();
    return candidate.copyWith(
      qualityScore: score,
      qualityGrade: _shortsGrade(score),
      riskCount: riskCount,
      hookScore: hookScore,
      completionScore: completionScore,
      strengths: _shortsStrengths(
        durationScore: durationScore,
        hookScore: hookScore,
        signalScore: signalScore,
        audioScore: audioScore,
        captionScore: captionScore,
        storyScore: storyScore,
        completionScore: completionScore,
      ),
      issues: _shortsIssues(
        duration: duration,
        riskCount: riskCount,
        fillerCount: fillerCount,
        offlineReviewCount: offlineReviewCount,
        hookScore: hookScore,
        audioScore: audioScore,
        captionScore: captionScore,
        storyScore: storyScore,
        completionScore: completionScore,
        storyIssues: storyIssues,
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
      '검증팩트',
      '영향',
      '문제해결',
      '구체성',
      '비교',
      '대응',
      '발언',
      '유지율',
      'Story:Hook',
      'Story:Context',
      'Story:Evidence',
      'Story:Impact',
      'Story:Resolution',
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

  List<String> _shortsStoryIssues(
    List<HighlightSegment> input,
    String strategyKind, {
    required double duration,
  }) {
    if (input.isEmpty) {
      return const ['No story'];
    }
    final roles = [
      for (final segment in input) _shortsStoryRole(segment, strategyKind),
    ];
    final tagText = input
        .expand((segment) => segment.tags)
        .join(' ')
        .toLowerCase();
    final scriptText = input
        .map((segment) => '${segment.reason} ${segment.script}')
        .join(' ')
        .toLowerCase();
    final hasHook =
        roles.first == 'hook' ||
        roles.contains('hook') ||
        _containsAny(scriptText, const ['결과', '핵심', '문제', '왜', '충격']);
    final hasEvidence =
        roles.contains('evidence') ||
        roles.contains('risk') ||
        tagText.contains('근거') ||
        tagText.contains('검증팩트') ||
        tagText.contains('출처확인') ||
        _containsAny(scriptText, const ['공식', '출처', '확인', '발표', '보고서']);
    final hasContext =
        roles.contains('context') ||
        tagText.contains('문제해결') ||
        tagText.contains('구체성') ||
        _containsAny(scriptText, const ['원인', '이유', '방법', '차이']);
    final hasImpact =
        roles.contains('impact') ||
        tagText.contains('영향') ||
        _containsAny(scriptText, const ['영향', '피해', '우려', '시민', '주민']);
    final hasEnding =
        roles.contains('resolution') ||
        roles.contains('close') ||
        tagText.contains('대응') ||
        _containsAny(scriptText, const ['대응', '결론', '다음', '앞으로']);
    final issues = <String>[];
    final topicIds = input
        .map((segment) => segment.topicId)
        .where((topicId) => topicId > 0)
        .toSet();
    if (topicIds.length > 1) {
      issues.add('Mixed topics');
    }
    if (strategyKind == 'risk' && !roles.contains('risk')) {
      issues.add('Missing risk');
    } else if (strategyKind != 'risk' && !hasHook) {
      issues.add('Missing hook');
    }
    if (!hasEvidence && !hasContext) {
      issues.add('Missing evidence');
    }
    if (duration >= 90 && !hasImpact && !hasEnding) {
      issues.add('Missing impact');
    }
    if (duration >= 90 &&
        !const {'impact', 'resolution', 'close'}.contains(roles.last)) {
      issues.add('Weak ending');
    }
    for (var index = 1; index < roles.length; index++) {
      if (_shortsRoleRank(roles[index]) < _shortsRoleRank(roles[index - 1])) {
        issues.add('Story order');
        break;
      }
    }
    if (roles.length > 1 &&
        roles.take(roles.length - 1).any((role) => role == 'close')) {
      issues.add('Early CTA');
    }
    return issues;
  }

  List<RenderSafetyItem> _buildRenderSafetyChecklist(
    List<HighlightSegment> input, {
    required String aspectRatio,
    required bool requireCaptions,
  }) {
    final checks = <RenderSafetyItem>[];
    final totalDuration = sequenceOutputDuration(input);

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

    final hasNewsSignals = input.any(_segmentHasNewsSignal);
    final hasVerificationSignals = input.any(_segmentHasVerificationSignal);
    if (hasNewsSignals && !hasVerificationSignals) {
      checks.add(
        const RenderSafetyItem(
          label: 'News verification',
          detail: '뉴스형 렌더에는 검증팩트, 근거, 출처확인 또는 발언 태그가 필요합니다',
          status: EditorialCheckStatus.block,
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
      if (_segmentIsTimelineGap(segment)) {
        checks.add(
          RenderSafetyItem(
            label: '$clipLabel gap',
            detail: '검은 무음 갭입니다. 필요 없으면 Close Gaps로 리플 삭제하세요',
            status: EditorialCheckStatus.warn,
            segmentOrder: segment.order,
          ),
        );
        continue;
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

  ShortsExportQueueItem _buildShortsExportQueueItem(
    ShortsCandidate candidate,
    int index,
  ) {
    final safety = _buildRenderSafetyChecklist(
      candidate.segments,
      aspectRatio: '9:16',
      requireCaptions: true,
    );
    final blocks = safety
        .where((item) => item.status == EditorialCheckStatus.block)
        .toList();
    final warnings = safety
        .where((item) => item.status == EditorialCheckStatus.warn)
        .toList();
    final firstIssue = blocks.isNotEmpty
        ? blocks.first
        : warnings.isNotEmpty
        ? warnings.first
        : null;
    return ShortsExportQueueItem(
      candidate: candidate,
      outputName: _shortsOutputName(index),
      durationSeconds: candidate.durationSeconds,
      clipCount: candidate.segments.length,
      blockCount: blocks.length,
      warnCount: warnings.length,
      statusDetail: firstIssue == null
          ? '9:16 render ready'
          : '${firstIssue.label} · ${firstIssue.detail}',
    );
  }

  String _shortsOutputName(int index) =>
      'shorts_${(index + 1).toString().padLeft(2, '0')}.mp4';

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
    required double completionScore,
  }) {
    final strengths = <String>[];
    if (hookScore >= 78) {
      strengths.add('Hook');
    }
    if (storyScore >= 78) {
      strengths.add('Story');
    }
    if (completionScore >= 72) {
      strengths.add('Complete');
    }
    if (signalScore >= 72) {
      strengths.add('Signals');
    }
    if (durationScore >= 78) {
      strengths.add('Runtime');
    }
    if (audioScore >= 90) {
      strengths.add('Audio');
    }
    if (captionScore >= 80) {
      strengths.add('Captions');
    }
    return strengths.take(4).toList();
  }

  List<String> _shortsIssues({
    required double duration,
    required int riskCount,
    required int fillerCount,
    required int offlineReviewCount,
    required double hookScore,
    required double audioScore,
    required double captionScore,
    required double storyScore,
    required double completionScore,
    required List<String> storyIssues,
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
    if (hookScore < 50) {
      issues.add('Weak hook');
    }
    issues.addAll(storyIssues);
    if (completionScore < 55) {
      issues.add('Incomplete');
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
    _markProjectDirty();
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
    _markProjectDirty();
    notifyListeners();
  }

  void deleteShortsCandidate(int id) {
    shortsCandidates = [
      for (final candidate in shortsCandidates)
        if (candidate.id != id) candidate,
    ];
    _markProjectDirty();
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
    _markProjectDirty();
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
      _markProjectDirty();
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
              'output_name': _shortsOutputName(index),
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
    selectedExportProfiles = [value];
    renderUrl = null;
    notifyListeners();
  }

  void setExportProfiles(Set<String> values) {
    final ordered = [
      for (final profile in const ['16:9', '9:16', '1:1'])
        if (values.contains(profile)) profile,
    ];
    if (ordered.isEmpty) {
      return;
    }
    _commitHistory();
    selectedExportProfiles = ordered;
    exportAspectRatio = ordered.first;
    renderUrl = null;
    notifyListeners();
  }

  String _exportProfileLabel(String profile) {
    return switch (profile) {
      '9:16' => 'Shorts 9:16',
      '1:1' => 'Square 1:1',
      _ => 'YouTube 16:9',
    };
  }

  String _exportProfileOutputName(String profile) {
    return switch (profile) {
      '9:16' => 'youtube_shorts_9x16.mp4',
      '1:1' => 'social_square_1x1.mp4',
      _ => 'youtube_highlights_16x9.mp4',
    };
  }

  void zoomTimeline(double delta) {
    timelineZoom = (timelineZoom + delta).clamp(1.0, 6.0).toDouble();
    notifyListeners();
  }

  void fitTimelineZoom() {
    if (timelineZoom == 1.0) {
      return;
    }
    timelineZoom = 1.0;
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
    final endSeconds =
        _previewSourceStartSeconds +
        durationSeconds * (_previewProgramSegment?.playbackSpeed ?? 1.0);
    return seconds >=
            _previewSourceStartSeconds - timecodeFrameDurationSeconds &&
        seconds <= endSeconds - timecodeFrameDurationSeconds;
  }

  double _previewLocalSecondsFor(
    double sourceSeconds,
    VideoPlayerController controller,
  ) {
    final durationSeconds = controller.value.duration.inMilliseconds / 1000;
    final localSeconds =
        (sourceSeconds - _previewSourceStartSeconds) /
        (_previewProgramSegment?.playbackSpeed ?? 1.0);
    if (durationSeconds <= 0) {
      return math.max(0, localSeconds);
    }
    return localSeconds.clamp(0.0, durationSeconds).toDouble();
  }

  Future<void> setPreviewMonitorMode(String mode) async {
    if (mode != 'source' && mode != 'program') {
      return;
    }
    if (mode == 'program' && !canUseProgramMonitor) {
      return;
    }
    if (previewMonitorMode == mode) {
      return;
    }
    _stopReverseShuttleTimer();
    final controller = videoController;
    if (controller != null && controller.value.isInitialized) {
      await controller.pause();
      await controller.setPlaybackSpeed(1.0);
    }
    playbackShuttleDirection = 0;
    playbackShuttleRate = 1.0;
    _previewAutoplayRequested = false;
    _programCutPending = false;
    previewMonitorMode = mode;
    if (mode == 'program') {
      final selectedSpan = _programSpanForOrder(selectedSegmentOrder);
      final target =
          selectedSpan?.sequenceStart ??
          _programPlayheadSeconds.clamp(0.0, outputDurationSeconds).toDouble();
      await _seekProgramTo(target, autoplay: false);
    } else if (_previewProgramSegmentOrder != null) {
      final path = selectedFile?.path;
      if (!kIsWeb && path != null && path.isNotEmpty) {
        await _initializeProxyPreview(
          path,
          focusSeconds: _manualPlayheadSeconds,
        );
      }
    }
    notifyListeners();
  }

  Future<void> seekMonitorTo(double seconds, {bool autoplay = false}) async {
    if (isProgramMonitor) {
      await _seekProgramTo(seconds, autoplay: autoplay);
      return;
    }
    await seekTo(seconds, autoplay: autoplay);
  }

  Future<void> _seekProgramTo(
    double programSeconds, {
    required bool autoplay,
  }) async {
    final total = outputDurationSeconds;
    if (segments.isEmpty || total <= 0) {
      return;
    }
    final clamped = programSeconds.clamp(0.0, total).toDouble();
    final span = _programSpanAt(clamped);
    if (span == null) {
      return;
    }
    _programPlayheadSeconds = clamped;
    _programSegmentOrder = span.segment.order;
    selectedSegmentOrder = span.segment.order;
    final sourceSeconds = sourceTimeForProgramPosition(clamped);
    final path = selectedFile?.path;
    final signature = _programPreviewSignature(span.segment);
    if (!kIsWeb &&
        path != null &&
        path.isNotEmpty &&
        (_previewProgramSegmentOrder != span.segment.order ||
            _previewProgramSegmentSignature != signature ||
            !_proxyContainsSourceTime(sourceSeconds))) {
      await _initializeProxyPreview(
        path,
        focusSeconds: sourceSeconds,
        programSegment: span.segment,
      );
    }
    await seekTo(sourceSeconds, autoplay: false);
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      if (autoplay) {
        _previewAutoplayRequested = true;
        playbackShuttleDirection = 1;
        playbackShuttleRate = 1.0;
      }
      notifyListeners();
      return;
    }
    await controller.setPlaybackSpeed(
      _previewProgramSegmentOrder == null ? span.segment.playbackSpeed : 1.0,
    );
    if (autoplay) {
      await controller.play();
      playbackShuttleDirection = 1;
      playbackShuttleRate = 1.0;
      _scheduleProgramPreviewPrefetch(span.segment);
    }
    notifyListeners();
  }

  Future<void> seekTo(double seconds, {bool autoplay = true}) async {
    var controller = videoController;
    final clamped = _clampTime(seconds);
    _manualPlayheadSeconds = clamped;
    if (_previewUsesProxy && !_proxyContainsSourceTime(clamped)) {
      final path = selectedFile?.path;
      if (!kIsWeb && path != null && path.isNotEmpty) {
        await _initializeProxyPreview(
          path,
          focusSeconds: clamped,
          programSegment: isProgramMonitor ? previewActiveSegment : null,
        );
        controller = videoController;
      }
    }
    if (controller == null || !controller.value.isInitialized) {
      if (autoplay && isPreparingPreview) {
        _previewAutoplayRequested = true;
        playbackShuttleDirection = 1;
        playbackShuttleRate = 1.0;
      }
      notifyListeners();
      return;
    }
    final localSeconds = _previewLocalSecondsFor(clamped, controller);
    await controller.seekTo(
      Duration(milliseconds: (localSeconds * 1000).round()),
    );
    if (autoplay) {
      await controller.play();
      playbackShuttleDirection = 1;
      playbackShuttleRate = 1.0;
    }
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    _stopReverseShuttleTimer();
    if (isProgramMonitor) {
      await _toggleProgramPlayback();
      return;
    }
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      final path = selectedFile?.path;
      if (!kIsWeb && path != null && path.isNotEmpty) {
        _previewAutoplayRequested = !_previewAutoplayRequested;
        playbackShuttleDirection = _previewAutoplayRequested ? 1 : 0;
        if (_previewAutoplayRequested && !isPreparingPreview) {
          unawaited(
            _prepareLocalPreview(path, focusSeconds: _manualPlayheadSeconds),
          );
        }
      } else {
        playbackShuttleDirection = playbackShuttleDirection == 0 ? 1 : 0;
      }
      playbackShuttleRate = 1.0;
      notifyListeners();
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
      _previewAutoplayRequested = false;
      playbackShuttleDirection = 0;
    } else {
      if (await _continueProxyPlaybackIfNeeded()) {
        return;
      }
      await controller.setPlaybackSpeed(1.0);
      await controller.play();
      playbackShuttleDirection = 1;
    }
    playbackShuttleRate = 1.0;
    notifyListeners();
  }

  Future<void> _toggleProgramPlayback() async {
    final controller = videoController;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isPlaying) {
      await controller.pause();
      _previewAutoplayRequested = false;
      playbackShuttleDirection = 0;
      playbackShuttleRate = 1.0;
      notifyListeners();
      return;
    }
    var target = _programPlayheadSeconds;
    if (target >= outputDurationSeconds - timecodeFrameDurationSeconds) {
      target = 0;
    }
    await _seekProgramTo(target, autoplay: true);
  }

  Future<void> _advanceProgramPlayback() async {
    if (_programCutPending || !isProgramMonitor) {
      return;
    }
    final current = _programSpanForOrder(_programSegmentOrder);
    if (current == null) {
      return;
    }
    _programCutPending = true;
    try {
      if (current.index >= segments.length - 1) {
        final controller = videoController;
        if (controller != null && controller.value.isInitialized) {
          await controller.pause();
        }
        _programPlayheadSeconds = outputDurationSeconds;
        playbackShuttleDirection = 0;
        playbackShuttleRate = 1.0;
        notifyListeners();
        return;
      }
      final next = segments[current.index + 1];
      final nextStart = current.sequenceEnd;
      _programSegmentOrder = next.order;
      selectedSegmentOrder = next.order;
      _programPlayheadSeconds = nextStart;
      await _seekProgramTo(nextStart, autoplay: true);
    } finally {
      _programCutPending = false;
    }
  }

  Future<bool> _continueProxyPlaybackIfNeeded() async {
    final controller = videoController;
    final path = selectedFile?.path;
    if (!_previewUsesProxy ||
        _proxyContinuationPending ||
        controller == null ||
        !controller.value.isInitialized ||
        kIsWeb ||
        path == null ||
        path.isEmpty) {
      return false;
    }
    final localDuration = controller.value.duration.inMilliseconds / 1000;
    final localPosition = controller.value.position.inMilliseconds / 1000;
    final programSegment = _previewProgramSegment;
    final proxyEnd =
        _previewSourceStartSeconds +
        localDuration * (programSegment?.playbackSpeed ?? 1.0);
    final sourceEnd = programSegment?.end ?? duration;
    if (localDuration <= 0 ||
        localPosition < localDuration - timecodeFrameDurationSeconds * 2 ||
        sourceEnd <= proxyEnd + timecodeFrameDurationSeconds) {
      return false;
    }

    _proxyContinuationPending = true;
    _previewAutoplayRequested = true;
    try {
      await _initializeProxyPreview(
        path,
        focusSeconds: math.min(
          proxyEnd,
          sourceEnd - timecodeFrameDurationSeconds,
        ),
        autoplay: true,
        programSegment: programSegment,
      );
    } finally {
      _proxyContinuationPending = false;
    }
    final nextController = videoController;
    final activeProgramSegment = previewActiveSegment;
    if (isProgramMonitor &&
        activeProgramSegment != null &&
        nextController != null &&
        nextController.value.isInitialized) {
      await nextController.setPlaybackSpeed(
        _previewProgramSegmentOrder == null
            ? activeProgramSegment.playbackSpeed
            : 1.0,
      );
    }
    final continued =
        nextController != null &&
        nextController.value.isInitialized &&
        _previewUsesProxy &&
        _proxyContainsSourceTime(proxyEnd);
    if (!continued) {
      _previewAutoplayRequested = false;
      playbackShuttleDirection = 0;
      playbackShuttleRate = 1.0;
      notifyListeners();
    } else if (activeProgramSegment != null) {
      _scheduleProgramPreviewPrefetch(activeProgramSegment);
    }
    return true;
  }

  Future<void> togglePreviewMute() async {
    previewMuted = !previewMuted;
    await _applyPreviewAudioSettings();
    notifyListeners();
  }

  Future<void> setPreviewVolume(double value) async {
    previewVolume = value.clamp(0.0, 1.0).toDouble();
    previewMuted = previewVolume <= 0;
    await _applyPreviewAudioSettings();
    notifyListeners();
  }

  Future<void> shuttleForward() async {
    _stopReverseShuttleTimer();
    final nextRate = _nextShuttleRate(1);
    playbackShuttleDirection = 1;
    playbackShuttleRate = nextRate;
    final controller = videoController;
    if (controller != null && controller.value.isInitialized) {
      final sourceRate = isProgramMonitor && _previewProgramSegmentOrder == null
          ? (previewActiveSegment?.playbackSpeed ?? 1.0) * nextRate
          : nextRate;
      await controller.setPlaybackSpeed(sourceRate);
      await controller.play();
      final programSegment = _previewProgramSegment;
      if (programSegment != null) {
        _scheduleProgramPreviewPrefetch(programSegment);
      }
    }
    notifyListeners();
  }

  Future<void> shuttlePause() async {
    _stopReverseShuttleTimer();
    playbackShuttleDirection = 0;
    playbackShuttleRate = 1.0;
    final controller = videoController;
    if (controller != null && controller.value.isInitialized) {
      await controller.pause();
      await controller.setPlaybackSpeed(1.0);
    }
    notifyListeners();
  }

  Future<void> shuttleReverse() async {
    final nextRate = _nextShuttleRate(-1);
    playbackShuttleDirection = -1;
    playbackShuttleRate = nextRate;
    final controller = videoController;
    if (controller != null && controller.value.isInitialized) {
      await controller.pause();
      await controller.setPlaybackSpeed(1.0);
    }
    _startReverseShuttleTimer(nextRate);
    notifyListeners();
  }

  double _nextShuttleRate(int direction) {
    if (playbackShuttleDirection != direction) {
      return 1.0;
    }
    const rates = [1.0, 2.0, 4.0, 8.0];
    final index = rates.indexWhere((rate) => rate == playbackShuttleRate);
    if (index < 0 || index >= rates.length - 1) {
      return rates.last;
    }
    return rates[index + 1];
  }

  void _startReverseShuttleTimer(double rate) {
    _stopReverseShuttleTimer();
    _reverseShuttleTimer = Timer.periodic(const Duration(milliseconds: 120), (
      _,
    ) {
      if (isProgramMonitor) {
        final next = (_programPlayheadSeconds - 0.12 * rate)
            .clamp(0.0, outputDurationSeconds)
            .toDouble();
        if (next <= 0) {
          unawaited(shuttlePause());
          return;
        }
        unawaited(_seekProgramTo(next, autoplay: false));
        return;
      }
      final next = _clampTime(currentPositionSeconds - 0.12 * rate);
      if (next <= 0) {
        unawaited(shuttlePause());
        return;
      }
      unawaited(seekTo(next, autoplay: false));
    });
  }

  void _stopReverseShuttleTimer() {
    _reverseShuttleTimer?.cancel();
    _reverseShuttleTimer = null;
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
      } else if (latest.status == 'cancelled') {
        isUploading = false;
        isRendering = false;
        errorMessage = null;
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
    _markProjectDirty();
    _scheduleTimelineThumbnails(delay: Duration.zero);
  }

  Future<void> _initializePreview(String id) async {
    final revision = ++_previewRevision;
    await _disposeVideoController();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(_apiClient.sourceUrl(id)),
    );
    await controller.initialize();
    await _applyPreviewAudioSettings(controller);
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
    isPreparingPreview = true;
    notifyListeners();
    VideoPlayerController? pendingController;
    try {
      final file = io.File(path);
      if (!await file.exists()) {
        return;
      }
      pendingController = VideoPlayerController.file(file);
      await pendingController.initialize().timeout(
        _directPreviewInitializationTimeout,
      );
      await _applyPreviewAudioSettings(pendingController);
      if (revision != _previewRevision || selectedFile?.path != path) {
        return;
      }
      await _disposeVideoController();
      final controller = pendingController;
      videoController = controller;
      pendingController = null;
      _previewUsesProxy = false;
      _previewSourceStartSeconds = 0;
      _previewSourceDurationSeconds = null;
      final previewDuration = controller.value.duration.inMilliseconds / 1000;
      if (previewDuration > 0 && duration == 0) {
        duration = previewDuration;
      }
      if (_previewAutoplayRequested) {
        await controller.setPlaybackSpeed(1.0);
        await controller.play();
        _previewAutoplayRequested = false;
        playbackShuttleDirection = 1;
        playbackShuttleRate = 1.0;
      }
      controller.addListener(_handleVideoTick);
      notifyListeners();
    } catch (_) {
      if (revision == _previewRevision && selectedFile?.path == path) {
        await _disposeVideoController();
        await _initializeProxyPreview(path);
      }
    } finally {
      await _disposePreviewControllerSafely(pendingController);
      if (revision == _previewRevision && selectedFile?.path == path) {
        isPreparingPreview = false;
        notifyListeners();
      }
    }
  }

  String _programPreviewSignature(HighlightSegment segment) =>
      '$exportAspectRatio|${jsonEncode(segment.toJson())}|'
      '${jsonEncode(videoOverlayTrackVisible ? videoOverlays.where((overlay) => overlay.enabled).map((overlay) => overlay.toJson()).toList() : const [])}|'
      '${jsonEncode(audioClips.where((clip) => clip.enabled).map((clip) => clip.toJson()).toList())}';

  List<VideoOverlayClip> _videoOverlaysForProgramWindow(
    HighlightSegment segment,
    double sourceStart,
    double duration,
  ) {
    final span = _programSpanForOrder(segment.order);
    if (span == null || duration <= 0 || !videoOverlayTrackVisible) {
      return const [];
    }
    final outputWindowOffset =
        (sourceStart - segment.start) / math.max(0.1, segment.playbackSpeed);
    final sequenceWindowStart = span.sequenceStart + outputWindowOffset;
    final sequenceWindowEnd = sequenceWindowStart + duration;
    final mapped = <VideoOverlayClip>[];
    for (final overlay in videoOverlays) {
      if (!overlay.enabled) {
        continue;
      }
      final overlapStart = math.max(overlay.timelineStart, sequenceWindowStart);
      final overlapEnd = math.min(overlay.timelineEnd, sequenceWindowEnd);
      if (overlapEnd - overlapStart < timecodeFrameDurationSeconds / 2) {
        continue;
      }
      final sourceOffset = overlapStart - overlay.timelineStart;
      final mappedSourceStart = snapSecondsToFrame(
        overlay.sourceStart + sourceOffset,
      );
      final mappedDuration = math.min(
        overlapEnd - overlapStart,
        overlay.sourceEnd - mappedSourceStart,
      );
      if (mappedDuration < timecodeFrameDurationSeconds / 2) {
        continue;
      }
      final localStart = snapSecondsToFrame(overlapStart - sequenceWindowStart);
      mapped.add(
        overlay.copyWith(
          timelineStart: localStart,
          timelineEnd: snapSecondsToFrame(localStart + mappedDuration),
          sourceStart: mappedSourceStart,
          sourceEnd: snapSecondsToFrame(mappedSourceStart + mappedDuration),
        ),
      );
    }
    return mapped;
  }

  List<AudioClip> _audioClipsForProgramWindow(
    HighlightSegment segment,
    double sourceStart,
    double duration,
  ) {
    final span = _programSpanForOrder(segment.order);
    if (span == null || duration <= 0) {
      return const [];
    }
    final outputWindowOffset =
        (sourceStart - segment.start) / math.max(0.1, segment.playbackSpeed);
    final sequenceWindowStart = span.sequenceStart + outputWindowOffset;
    final sequenceWindowEnd = sequenceWindowStart + duration;
    final mapped = <AudioClip>[];
    for (final clip in audioClips) {
      if (!clip.enabled) {
        continue;
      }
      final overlapStart = math.max(clip.timelineStart, sequenceWindowStart);
      final overlapEnd = math.min(clip.timelineEnd, sequenceWindowEnd);
      if (overlapEnd - overlapStart < timecodeFrameDurationSeconds / 2) {
        continue;
      }
      final sourceOffset = overlapStart - clip.timelineStart;
      final mappedSourceStart = snapSecondsToFrame(
        clip.sourceStart + sourceOffset,
      );
      final mappedDuration = math.min(
        overlapEnd - overlapStart,
        clip.sourceEnd - mappedSourceStart,
      );
      if (mappedDuration < timecodeFrameDurationSeconds / 2) {
        continue;
      }
      final localStart = snapSecondsToFrame(overlapStart - sequenceWindowStart);
      mapped.add(
        clip.copyWith(
          timelineStart: localStart,
          timelineEnd: snapSecondsToFrame(localStart + mappedDuration),
          sourceStart: mappedSourceStart,
          sourceEnd: snapSecondsToFrame(mappedSourceStart + mappedDuration),
        ),
      );
    }
    return mapped;
  }

  void _refreshProgramPreviewAfterOverlayEdit() {
    if (!isProgramMonitor) {
      return;
    }
    final segment =
        _programSpanAt(_programPlayheadSeconds)?.segment ??
        previewActiveSegment;
    if (segment != null) {
      _scheduleProgramPreviewRefresh(segment);
    }
  }

  ({double sourceStart, double duration}) _programPreviewWindowFor(
    HighlightSegment segment,
    double focusSeconds,
  ) {
    final requestedDuration = math.min(
      _programPreviewWindowSeconds,
      segment.outputDuration,
    );
    final localFocus = ((focusSeconds - segment.start) / segment.playbackSpeed)
        .clamp(0.0, segment.outputDuration)
        .toDouble();
    final maxWindowStart = math.max(
      0.0,
      segment.outputDuration - requestedDuration,
    );
    final outputWindowStart = (localFocus - _programPreviewPreRollSeconds)
        .clamp(0.0, maxWindowStart)
        .toDouble();
    return (
      sourceStart: segment.start + outputWindowStart * segment.playbackSpeed,
      duration: requestedDuration,
    );
  }

  String _previewRequestKey(
    String path,
    double sourceStart,
    double requestedDuration,
    String programSignature,
  ) =>
      '$path|${sourceStart.toStringAsFixed(3)}|'
      '${requestedDuration.toStringAsFixed(3)}|$programSignature';

  void _scheduleProgramPreviewPrefetch(HighlightSegment segment) {
    final path = selectedFile?.path;
    final previewDuration = _previewSourceDurationSeconds;
    if (kIsWeb ||
        path == null ||
        path.isEmpty ||
        previewDuration == null ||
        previewDuration <= 0 ||
        _previewProgramSegmentOrder != segment.order) {
      return;
    }
    final currentWindowEnd =
        _previewSourceStartSeconds + previewDuration * segment.playbackSpeed;
    if (currentWindowEnd >= segment.end - timecodeFrameDurationSeconds) {
      return;
    }
    final nextWindow = _programPreviewWindowFor(segment, currentWindowEnd);
    if (nextWindow.sourceStart <=
        _previewSourceStartSeconds + timecodeFrameDurationSeconds) {
      return;
    }
    final signature = _programPreviewSignature(segment);
    final key = _previewRequestKey(
      path,
      nextWindow.sourceStart,
      nextWindow.duration,
      signature,
    );
    if (_programPreviewPrefetchKey == key &&
        _programPreviewPrefetchFuture != null) {
      return;
    }
    _programPreviewPrefetchKey = key;
    final previewOverlays = _videoOverlaysForProgramWindow(
      segment,
      nextWindow.sourceStart,
      nextWindow.duration,
    );
    final previewAudioClips = _audioClipsForProgramWindow(
      segment,
      nextWindow.sourceStart,
      nextWindow.duration,
    );
    _programPreviewPrefetchFuture = () async {
      try {
        return await _apiClient.createLocalPreview(
          path,
          startSeconds: nextWindow.sourceStart,
          durationSeconds: nextWindow.duration,
          segment: segment,
          videoOverlays: previewOverlays,
          audioClips: previewAudioClips,
          aspectRatio: exportAspectRatio,
        );
      } catch (_) {
        return null;
      }
    }();
  }

  void _scheduleProgramPreviewRefresh(HighlightSegment segment) {
    _programPreviewRefreshTimer?.cancel();
    _programPreviewRefreshTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_refreshProgramPreview(segment.order)),
    );
  }

  Future<void> _refreshProgramPreview(int order) async {
    if (!isProgramMonitor || _programSegmentOrder != order) {
      return;
    }
    final segment = _programSpanForOrder(order)?.segment;
    final path = selectedFile?.path;
    if (segment == null || kIsWeb || path == null || path.isEmpty) {
      return;
    }
    final playhead = _programPlayheadSeconds;
    final sourceSeconds = sourceTimeForProgramPosition(playhead);
    await _initializeProxyPreview(
      path,
      focusSeconds: sourceSeconds,
      programSegment: segment,
    );
    if (isProgramMonitor && _programSegmentOrder == order) {
      await _seekProgramTo(playhead, autoplay: false);
    }
  }

  Future<void> _initializeProxyPreview(
    String path, {
    double focusSeconds = 0,
    bool autoplay = false,
    HighlightSegment? programSegment,
  }) async {
    if (kIsWeb || path.isEmpty) {
      return;
    }
    if (autoplay) {
      _previewAutoplayRequested = true;
    }
    late final double requestedDuration;
    late final double sourceStart;
    if (programSegment != null) {
      final window = _programPreviewWindowFor(programSegment, focusSeconds);
      requestedDuration = window.duration;
      sourceStart = window.sourceStart;
    } else {
      requestedDuration = focusSeconds > 0
          ? _seekProxyPreviewSeconds
          : _initialProxyPreviewSeconds;
      final preRoll = focusSeconds > 0
          ? math.min(2.0, requestedDuration / 4)
          : 0.0;
      sourceStart = math.max(0.0, focusSeconds - preRoll);
    }
    final programSignature = programSegment == null
        ? ''
        : _programPreviewSignature(programSegment);
    final requestKey = _previewRequestKey(
      path,
      sourceStart,
      requestedDuration,
      programSignature,
    );
    final activeRequest = _activeProxyRequest;
    if (_activeProxyRequestKey == requestKey && activeRequest != null) {
      await activeRequest;
      return;
    }

    final revision = ++_previewRevision;
    final prefetchedPreview = _programPreviewPrefetchKey == requestKey
        ? _programPreviewPrefetchFuture
        : null;
    final request = _performProxyPreviewInitialization(
      path,
      revision: revision,
      focusSeconds: focusSeconds,
      sourceStart: sourceStart,
      requestedDuration: requestedDuration,
      programSegment: programSegment,
      programSignature: programSignature,
      prefetchedPreview: prefetchedPreview,
    );
    _activeProxyRequestKey = requestKey;
    _activeProxyRequest = request;
    try {
      await request;
    } finally {
      if (identical(_activeProxyRequest, request)) {
        _activeProxyRequest = null;
        _activeProxyRequestKey = null;
      }
      if (_programPreviewPrefetchKey == requestKey) {
        _programPreviewPrefetchKey = null;
        _programPreviewPrefetchFuture = null;
      }
    }
  }

  Future<void> _performProxyPreviewInitialization(
    String path, {
    required int revision,
    required double focusSeconds,
    required double sourceStart,
    required double requestedDuration,
    required HighlightSegment? programSegment,
    required String programSignature,
    Future<LocalPreviewInfo?>? prefetchedPreview,
  }) async {
    isPreparingPreview = true;
    notifyListeners();
    VideoPlayerController? pendingController;
    var reusedController = false;
    try {
      await _ensureLocalEngineForApi();
      final previewOverlays = programSegment == null
          ? const <VideoOverlayClip>[]
          : _videoOverlaysForProgramWindow(
              programSegment,
              sourceStart,
              requestedDuration,
            );
      final previewAudioClips = programSegment == null
          ? const <AudioClip>[]
          : _audioClipsForProgramWindow(
              programSegment,
              sourceStart,
              requestedDuration,
            );
      LocalPreviewInfo preview;
      if (prefetchedPreview != null) {
        preview =
            await prefetchedPreview ??
            await _apiClient.createLocalPreview(
              path,
              startSeconds: sourceStart,
              durationSeconds: requestedDuration,
              segment: programSegment,
              videoOverlays: previewOverlays,
              audioClips: previewAudioClips,
              aspectRatio: exportAspectRatio,
            );
      } else {
        preview = await _apiClient.createLocalPreview(
          path,
          startSeconds: sourceStart,
          durationSeconds: requestedDuration,
          segment: programSegment,
          videoOverlays: previewOverlays,
          audioClips: previewAudioClips,
          aspectRatio: exportAspectRatio,
        );
      }
      if (revision != _previewRevision || selectedFile?.path != path) {
        return;
      }
      final localPreviewPath = preview.localPath;
      final localPreviewFile = localPreviewPath == null
          ? null
          : io.File(localPreviewPath);
      final localPreviewExists =
          localPreviewFile != null && await localPreviewFile.exists();
      final activeController = videoController;
      final platform = VideoPlayerPlatform.instance;
      if (activeController != null &&
          activeController.value.isInitialized &&
          platform is ReusableVideoPlayerPlatform) {
        final resource = localPreviewExists
            ? localPreviewFile.uri.toString()
            : preview.url;
        try {
          final info = await (platform as ReusableVideoPlayerPlatform)
              .replaceActiveSource(
                resource,
                timeout: _proxyPreviewRecoveryTimeout,
              );
          activeController.value = activeController.value.copyWith(
            duration: info.duration,
            size: info.size,
            position: Duration.zero,
            buffered: const [],
            isInitialized: true,
            isPlaying: false,
            isBuffering: false,
            isCompleted: false,
            errorDescription: null,
          );
          pendingController = activeController;
          reusedController = true;
        } catch (_) {
          pendingController = null;
        }
      }
      if (pendingController == null && localPreviewExists) {
        await _disposeVideoController();
        pendingController = VideoPlayerController.file(localPreviewFile);
        try {
          await pendingController.initialize().timeout(
            _proxyPreviewInitializationTimeout,
          );
        } on TimeoutException {
          await _disposePreviewControllerSafely(pendingController);
          pendingController = null;
          if (revision == _previewRevision && selectedFile?.path == path) {
            await _disposeVideoController();
            pendingController = VideoPlayerController.file(localPreviewFile);
            try {
              await pendingController.initialize().timeout(
                _proxyPreviewRecoveryTimeout,
              );
            } catch (_) {
              await _disposePreviewControllerSafely(pendingController);
              pendingController = null;
            }
          }
        } catch (_) {
          await _disposePreviewControllerSafely(pendingController);
          pendingController = null;
        }
      }
      if (pendingController == null) {
        if (revision != _previewRevision || selectedFile?.path != path) {
          return;
        }
        await _disposeVideoController();
        pendingController = VideoPlayerController.networkUrl(
          Uri.parse(preview.url),
        );
        await pendingController.initialize().timeout(
          _proxyPreviewRecoveryTimeout,
        );
      }
      await _applyPreviewAudioSettings(pendingController);
      if (revision != _previewRevision || selectedFile?.path != path) {
        if (reusedController) {
          pendingController = null;
        }
        return;
      }
      if (!reusedController) {
        await _disposeVideoController();
      }
      final controller = pendingController;
      videoController = controller;
      pendingController = null;
      _previewUsesProxy = true;
      _previewSourceStartSeconds = preview.sourceStart;
      _previewProgramSegmentOrder = programSegment?.order;
      _previewProgramSegmentSignature = programSegment == null
          ? null
          : programSignature;
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
      if (_previewAutoplayRequested) {
        await controller.setPlaybackSpeed(1.0);
        await controller.play();
        _previewAutoplayRequested = false;
        playbackShuttleDirection = 1;
        playbackShuttleRate = 1.0;
      }
      if (!reusedController) {
        controller.addListener(_handleVideoTick);
      }
      if (errorMessage?.startsWith('프리뷰 생성 실패') ?? false) {
        errorMessage = null;
      }
    } catch (error) {
      if (revision == _previewRevision &&
          selectedFile?.path == path &&
          (errorMessage == null ||
              (errorMessage?.startsWith('프리뷰 생성 실패') ?? false))) {
        errorMessage = '프리뷰 생성 실패: $error';
        _previewAutoplayRequested = false;
        playbackShuttleDirection = 0;
        playbackShuttleRate = 1.0;
      }
    } finally {
      await _disposePreviewControllerSafely(pendingController);
      if (revision == _previewRevision && selectedFile?.path == path) {
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
    _previewProgramSegmentOrder = null;
    _previewProgramSegmentSignature = null;
    if (current != null) {
      current.removeListener(_handleVideoTick);
      await _disposePreviewControllerSafely(current);
    }
  }

  Future<void> _disposePreviewControllerSafely(
    VideoPlayerController? controller,
  ) async {
    if (controller == null) {
      return;
    }
    try {
      await controller.dispose().timeout(_previewControllerDisposeTimeout);
    } catch (_) {
      // A failed native player must not leave the editor in a loading state.
    }
  }

  Future<void> _applyPreviewAudioSettings([
    VideoPlayerController? target,
  ]) async {
    final controller = target ?? videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    await controller.setVolume(previewMuted ? 0.0 : previewVolume);
  }

  void _handleVideoTick() {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final sourceSeconds = currentPositionSeconds;
    _manualPlayheadSeconds = sourceSeconds;
    final isPlaying = controller.value.isPlaying;
    if (isProgramMonitor) {
      final span = _programSpanForOrder(_programSegmentOrder);
      if (span != null) {
        final localSource = (sourceSeconds - span.segment.start)
            .clamp(0.0, span.segment.duration)
            .toDouble();
        _programPlayheadSeconds =
            (span.sequenceStart + localSource / span.segment.playbackSpeed)
                .clamp(span.sequenceStart, span.sequenceEnd)
                .toDouble();
        final sourceCutTolerance =
            timecodeFrameDurationSeconds *
            math.max(1.0, span.segment.playbackSpeed);
        if ((isPlaying || controller.value.isCompleted) &&
            sourceSeconds >= span.segment.end - sourceCutTolerance &&
            !_programCutPending) {
          _programPlayheadSeconds = span.sequenceEnd;
          unawaited(_advanceProgramPlayback());
        }
      }
    }
    if (_previewUsesProxy &&
        !isPlaying &&
        playbackShuttleDirection == 1 &&
        !isPreparingPreview &&
        !_programCutPending) {
      unawaited(_continueProxyPlaybackIfNeeded());
    }
    final seconds = monitorPositionSeconds;
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

  TimelineMarker? _nextTimelineMarkerFrom(
    double seconds, {
    bool enabledOnly = false,
  }) {
    final threshold = seconds + timecodeFrameDurationSeconds / 2;
    for (final marker in timelineMarkers) {
      if (enabledOnly && !marker.enabled) {
        continue;
      }
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

  List<double> _timelineEditPoints() {
    final points = <double>{};
    final sourceDuration = timelineSourceDuration;
    if (sourceDuration > 0) {
      points.add(0);
      points.add(_snapToFrame(sourceDuration));
    }
    for (final segment in segments) {
      points.add(_snapToFrame(_clampTime(segment.start)));
      points.add(_snapToFrame(_clampTime(segment.end)));
    }
    final sorted = points.toList()..sort();
    return sorted;
  }

  ({TimelineMarker marker, double start, double end})? _timelineMarkerRange(
    int id, {
    bool enabledOnly = false,
  }) {
    TimelineMarker? marker;
    for (final item in timelineMarkers) {
      if (item.id == id) {
        marker = item;
        break;
      }
    }
    if (marker == null) {
      return null;
    }
    if (enabledOnly && !marker.enabled) {
      return null;
    }
    final sourceDuration = timelineSourceDuration;
    if (sourceDuration <= 0) {
      return null;
    }
    final start = _snapToFrame(_clampProjectTime(marker.seconds));
    final next = _nextTimelineMarkerFrom(start, enabledOnly: enabledOnly);
    final fallbackEnd = math.min(sourceDuration, start + 30.0);
    final end = _snapToFrame(_clampProjectTime(next?.seconds ?? fallbackEnd));
    if (end - start < timecodeFrameDurationSeconds) {
      return null;
    }
    return (marker: marker, start: start, end: end);
  }

  List<({TimelineMarker marker, double start, double end})>
  _timelineMarkerRanges({bool enabledOnly = false}) {
    final ranges = <({TimelineMarker marker, double start, double end})>[];
    for (final marker in timelineMarkers) {
      final range = _timelineMarkerRange(marker.id, enabledOnly: enabledOnly);
      if (range != null) {
        ranges.add(range);
      }
    }
    return ranges;
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
    final focusX = segment.focusX.clamp(0.0, 1.0).toDouble();
    final focusY = segment.focusY.clamp(0.0, 1.0).toDouble();
    final focusConfidence = segment.focusConfidence.clamp(0.0, 1.0).toDouble();
    final motionDuration = (end - start) / playbackSpeed;
    final normalizedMotionKeyframes = <MotionKeyframe>[];
    for (final keyframe in segment.motionKeyframes) {
      normalizedMotionKeyframes.add(
        MotionKeyframe(
          time: _snapToFrame(
            keyframe.time.clamp(0.0, motionDuration).toDouble(),
          ),
          opacity: keyframe.opacity.clamp(0.0, 1.0).toDouble(),
          scale: keyframe.scale.clamp(1.0, 3.0).toDouble(),
          positionX: keyframe.positionX.clamp(-1.0, 1.0).toDouble(),
          positionY: keyframe.positionY.clamp(-1.0, 1.0).toDouble(),
          rotation: keyframe.rotation.clamp(-180.0, 180.0).toDouble(),
        ),
      );
    }
    normalizedMotionKeyframes.sort((a, b) => a.time.compareTo(b.time));
    final motionKeyframes = <MotionKeyframe>[];
    for (final normalized in normalizedMotionKeyframes) {
      if (motionKeyframes.isNotEmpty &&
          (motionKeyframes.last.time - normalized.time).abs() <
              timecodeFrameDurationSeconds / 2) {
        motionKeyframes[motionKeyframes.length - 1] = normalized;
      } else {
        motionKeyframes.add(normalized);
      }
    }
    final transitionType = normalizeClipTransitionType(segment.transitionType);
    final transitionDuration = transitionType == 'cut'
        ? 0.0
        : _snapToFrame(segment.transitionDuration.clamp(0.10, 3.0).toDouble());
    final focusKeyframes =
        segment.focusKeyframes
            .map(
              (keyframe) => ReframeKeyframe(
                time: keyframe.time.clamp(0.0, end - start).toDouble(),
                x: keyframe.x.clamp(0.0, 1.0).toDouble(),
                y: keyframe.y.clamp(0.0, 1.0).toDouble(),
              ),
            )
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    final audioChannel1Enabled =
        segment.audioChannel1Enabled || !segment.audioChannel2Enabled;
    final audioChannel2Enabled = segment.audioChannel2Enabled;
    final normalizedSegment = segment.copyWith(
      start: start,
      end: end,
      playbackSpeed: playbackSpeed,
      transitionType: transitionType,
      transitionDuration: transitionDuration,
      colorBrightness: colorBrightness,
      colorContrast: colorContrast,
      colorSaturation: colorSaturation,
      focusX: focusX,
      focusY: focusY,
      focusConfidence: focusConfidence,
      focusKeyframes: focusKeyframes,
      motionKeyframes: motionKeyframes,
      topicId: math.max(0, segment.topicId),
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

  HighlightSegment _markedEditSegment({
    required int order,
    required String reason,
    required String source,
  }) {
    final start = _snapToFrame(_clampProjectTime(markIn!));
    final end = _snapToFrame(_clampProjectTime(markOut!));
    final audioTargeted = audioTrack1Targeted || audioTrack2Targeted;
    return _normalizeSegmentAudio(
      HighlightSegment(
        order: order,
        start: start,
        end: end,
        reason: reason,
        script: _scriptPreviewFor(start, end),
        source: source,
        videoEnabled: videoTrackTargeted,
        audioStart: start,
        audioEnd: end,
        audioMuted: !audioTargeted,
        audioVolume: audioTargeted ? 1.0 : 0.0,
        audioNormalize: audioTargeted,
        audioLinked: true,
        audioChannel1Enabled: audioTrack1Targeted,
        audioChannel2Enabled: audioTrack2Targeted,
        score: 0,
        tags: const ['manual'],
      ),
    );
  }

  HighlightSegment _splitSegment(
    HighlightSegment segment,
    double splitAt, {
    required bool firstHalf,
  }) {
    final source = segment.source == 'ai' ? 'ai+manual' : segment.source;
    final reasonSuffix = firstHalf ? 'split A' : 'split B';
    final motionKeyframes = _motionKeyframesForSplit(
      segment,
      splitAt,
      firstHalf: firstHalf,
    );
    if (segment.audioLinked) {
      final start = firstHalf ? segment.start : splitAt;
      final end = firstHalf ? splitAt : segment.end;
      return _normalizeSegmentAudio(
        segment.copyWith(
          start: start,
          end: end,
          audioStart: start,
          audioEnd: end,
          transitionType: firstHalf ? segment.transitionType : 'cut',
          transitionDuration: firstHalf ? segment.transitionDuration : 0,
          motionKeyframes: motionKeyframes,
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
        transitionType: firstHalf ? segment.transitionType : 'cut',
        transitionDuration: firstHalf ? segment.transitionDuration : 0,
        motionKeyframes: motionKeyframes,
        reason: '${segment.reason} / $reasonSuffix',
        source: source,
      ),
    );
  }

  List<MotionKeyframe> _motionKeyframesForSplit(
    HighlightSegment segment,
    double splitAt, {
    required bool firstHalf,
  }) {
    if (segment.motionKeyframes.isEmpty) {
      return const [];
    }
    final splitTime = _snapToFrame(
      ((splitAt - segment.start) / segment.playbackSpeed)
          .clamp(0.0, segment.outputDuration)
          .toDouble(),
    );
    final boundary = sampleMotionKeyframes(
      keyframes: segment.motionKeyframes,
      time: splitTime,
      fallback: MotionKeyframe(
        time: splitTime,
        opacity: segment.videoOpacity,
        scale: segment.videoScale,
        positionX: segment.videoPositionX,
        positionY: segment.videoPositionY,
        rotation: segment.videoRotation,
      ),
    );
    final tolerance = timecodeFrameDurationSeconds / 2;
    if (firstHalf) {
      final output = segment.motionKeyframes
          .where((keyframe) => keyframe.time < splitTime - tolerance)
          .toList();
      output.add(boundary.copyWith(time: splitTime));
      return output;
    }
    final output = <MotionKeyframe>[boundary.copyWith(time: 0)];
    output.addAll(
      segment.motionKeyframes
          .where((keyframe) => keyframe.time > splitTime + tolerance)
          .map(
            (keyframe) => keyframe.copyWith(
              time: _snapToFrame(keyframe.time - splitTime),
            ),
          ),
    );
    return output;
  }

  bool _segmentOverlapsRange(
    HighlightSegment segment,
    double start,
    double end,
  ) {
    return segment.start < end && segment.end > start;
  }

  HighlightSegment? _trimSegmentToRange(
    HighlightSegment segment,
    double start,
    double end, {
    required String sourceSuffix,
    required String reasonSuffix,
  }) {
    final snappedStart = _snapToFrame(_clampProjectTime(start));
    final snappedEnd = _snapToFrame(_clampProjectTime(end));
    if (snappedEnd - snappedStart < timecodeFrameDurationSeconds) {
      return null;
    }
    final source = _appendSource(segment.source, sourceSuffix);
    final script = _scriptPreviewFor(snappedStart, snappedEnd);
    final reason = '${segment.reason} / $reasonSuffix';
    if (segment.audioLinked) {
      return _normalizeSegmentAudio(
        segment.copyWith(
          start: snappedStart,
          end: snappedEnd,
          audioStart: snappedStart,
          audioEnd: snappedEnd,
          reason: reason,
          script: script.isEmpty ? segment.script : script,
          source: source,
        ),
      );
    }

    final videoDuration = math.max(
      timecodeFrameDurationSeconds,
      segment.duration,
    );
    final audioDuration = segment.audioDuration;
    final startRatio = ((snappedStart - segment.start) / videoDuration)
        .clamp(0.0, 1.0)
        .toDouble();
    final endRatio = ((snappedEnd - segment.start) / videoDuration)
        .clamp(0.0, 1.0)
        .toDouble();
    final audioStart = _snapToFrame(
      segment.effectiveAudioStart + audioDuration * startRatio,
    );
    final audioEnd = _snapToFrame(
      segment.effectiveAudioStart + audioDuration * endRatio,
    );
    return _normalizeSegmentAudio(
      segment.copyWith(
        start: snappedStart,
        end: snappedEnd,
        audioStart: audioStart,
        audioEnd: audioEnd,
        audioLinked: false,
        reason: reason,
        script: script.isEmpty ? segment.script : script,
        source: source,
      ),
    );
  }

  HighlightSegment? _gapSegmentForRange(
    HighlightSegment segment,
    double start,
    double end,
  ) {
    final snappedStart = _snapToFrame(_clampProjectTime(start));
    final snappedEnd = _snapToFrame(_clampProjectTime(end));
    if (snappedEnd - snappedStart < timecodeFrameDurationSeconds) {
      return null;
    }
    return _normalizeSegmentAudio(
      segment.copyWith(
        start: snappedStart,
        end: snappedEnd,
        reason: 'Lift gap In/Out',
        script: '',
        source: _appendSource(segment.source, 'lift-gap'),
        videoEnabled: false,
        videoFadeIn: 0,
        videoFadeOut: 0,
        audioStart: snappedStart,
        audioEnd: snappedEnd,
        audioMuted: true,
        audioVolume: 0,
        audioPan: 0,
        audioNormalize: false,
        audioLinked: true,
        transitionType: 'cut',
        transitionDuration: 0,
        audioFadeIn: 0,
        audioFadeOut: 0,
        score: 0,
        tags: [...segment.tags, if (!segment.tags.contains('gap')) 'gap'],
      ),
    );
  }

  HighlightSegment? _targetedGapSegmentForRange(
    HighlightSegment segment,
    double start,
    double end,
  ) {
    final snappedStart = _snapToFrame(_clampProjectTime(start));
    final snappedEnd = _snapToFrame(_clampProjectTime(end));
    if (snappedEnd - snappedStart < timecodeFrameDurationSeconds) {
      return null;
    }
    final channel1 = audioTrack1Targeted ? false : segment.audioChannel1Enabled;
    final channel2 = audioTrack2Targeted ? false : segment.audioChannel2Enabled;
    final hasAudio = channel1 || channel2;
    return _normalizeSegmentAudio(
      segment.copyWith(
        start: snappedStart,
        end: snappedEnd,
        reason: 'Targeted lift In/Out',
        script: videoTrackTargeted ? '' : segment.script,
        source: _appendSource(segment.source, 'target-lift'),
        videoEnabled: videoTrackTargeted ? false : segment.videoEnabled,
        videoFadeIn: videoTrackTargeted ? 0 : segment.videoFadeIn,
        videoFadeOut: videoTrackTargeted ? 0 : segment.videoFadeOut,
        audioStart: snappedStart,
        audioEnd: snappedEnd,
        audioMuted: segment.audioMuted || !hasAudio,
        audioVolume: hasAudio ? segment.audioVolume : 0,
        audioPan: hasAudio ? segment.audioPan : 0,
        audioNormalize: hasAudio && segment.audioNormalize,
        audioLinked: true,
        audioChannel1Enabled: channel1,
        audioChannel2Enabled: channel2,
        audioFadeIn: hasAudio ? segment.audioFadeIn : 0,
        audioFadeOut: hasAudio ? segment.audioFadeOut : 0,
        score: videoTrackTargeted && !hasAudio ? 0 : segment.score,
        tags: [
          ...segment.tags,
          if (!segment.tags.contains('target-lift')) 'target-lift',
        ],
      ),
    );
  }

  List<HighlightSegment> _reorderSegments(List<HighlightSegment> input) {
    final ordered = [
      for (var index = 0; index < input.length; index++)
        _normalizeSegmentAudio(
          input[index].copyWith(
            order: index + 1,
            transitionType: index == 0 ? 'cut' : input[index].transitionType,
            transitionDuration: index == 0
                ? 0
                : input[index].transitionDuration,
          ),
        ),
    ];
    for (var index = 1; index < ordered.length; index++) {
      final overlap = effectiveTransitionOverlap(
        ordered[index - 1],
        ordered[index],
      );
      if (ordered[index].transitionType != 'cut' &&
          (ordered[index].transitionDuration - overlap).abs() > 0.001) {
        ordered[index] = ordered[index].copyWith(transitionDuration: overlap);
      }
    }
    return ordered;
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
      if (_segmentIsTimelineGap(segment)) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'Close timeline gap',
            detail: 'Lift로 생긴 검은 무음 구간을 리플 삭제해 타임라인을 붙입니다.',
            severity: AutoFixSeverity.polish,
            action: AutoFixAction.closeGap,
          ),
        );
        continue;
      }
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
      final hasUnverifiedNewsSignal =
          _segmentHasNewsSignal(segment) &&
          !_segmentHasVerificationSignal(segment);

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
      if (segmentHasAudioLengthDrift(segment)) {
        final driftFrames = audioVideoLengthDriftFrames(segment);
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'A/V length drift',
            detail: '비디오와 오디오 길이가 $driftFrames프레임 달라 말소리 컷이 어긋날 수 있습니다.',
            severity: AutoFixSeverity.warn,
            action: AutoFixAction.syncAudioLength,
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
      if (hasUnverifiedNewsSignal) {
        output.add(
          AutoFixReviewItem(
            segmentOrder: segment.order,
            title: 'Needs verification',
            detail: '뉴스형 컷에 검증팩트/근거/출처확인 태그가 없어 수동 확인이 필요합니다.',
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

    if (_segmentIsTimelineGap(next)) {
      final gapNeedsStandardization =
          next.videoEnabled ||
          next.effectiveAudioStart != next.start ||
          next.effectiveAudioEnd != next.end ||
          !next.audioLinked ||
          !next.audioMuted ||
          next.audioVolume != 0 ||
          next.audioPan != 0 ||
          next.audioNormalize ||
          next.videoFadeIn != 0 ||
          next.videoFadeOut != 0 ||
          next.audioFadeIn != 0 ||
          next.audioFadeOut != 0;
      next = next.copyWith(
        videoEnabled: false,
        audioStart: next.start,
        audioEnd: next.end,
        audioLinked: true,
        audioMuted: true,
        audioVolume: 0,
        audioPan: 0,
        audioNormalize: false,
        videoFadeIn: 0,
        videoFadeOut: 0,
        audioFadeIn: 0,
        audioFadeOut: 0,
      );
      final gapChanged = changed || gapNeedsStandardization;
      return (_normalizeSegmentAudio(next), gapChanged);
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
    if (segmentHasAudioLengthDrift(next)) {
      next = _syncSegmentAudioLength(next);
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
      case AutoFixAction.closeGap:
        return _segmentIsTimelineGap(segment) ? null : segment;
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
      case AutoFixAction.syncAudioLength:
        return _syncSegmentAudioLength(segment);
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

  bool _segmentIsTimelineGap(HighlightSegment segment) {
    final source = segment.source.toLowerCase();
    final reason = segment.reason.toLowerCase();
    final hasGapIdentity =
        segment.tags.contains('gap') ||
        source.contains('lift-gap') ||
        reason.contains('lift gap');
    final hasNoVisibleMedia = !segment.videoEnabled;
    final hasNoAudibleMedia =
        segment.audioMuted ||
        segment.audioVolume <= 0.01 ||
        !segment.hasActiveAudioChannel;
    return hasGapIdentity && hasNoVisibleMedia && hasNoAudibleMedia;
  }

  bool _autoFixCanRemoveLastSegment(AutoFixAction action) {
    return action == AutoFixAction.closeGap;
  }

  bool _segmentNeedsAudioMix(HighlightSegment segment) {
    if (!_segmentAudioReady(segment)) {
      return false;
    }
    return !segment.audioNormalize ||
        segment.audioPan.abs() > 0.001 ||
        segment.audioVolume < 0.85 ||
        segment.audioVolume > 1.15;
  }

  HighlightSegment _syncSegmentAudioLength(HighlightSegment segment) {
    final videoFrames = math.max(1, secondsToTimecodeFrame(segment.duration));
    final maxFrame = duration > 0
        ? math.max(videoFrames, secondsToTimecodeFrame(duration))
        : null;
    var audioStartFrame = secondsToTimecodeFrame(segment.effectiveAudioStart);
    var audioEndFrame = audioStartFrame + videoFrames;
    if (maxFrame != null && audioEndFrame > maxFrame) {
      audioEndFrame = maxFrame;
      audioStartFrame = math.max(0, audioEndFrame - videoFrames);
    }
    final audioStart = timecodeFrameToSeconds(audioStartFrame);
    final audioEnd = timecodeFrameToSeconds(audioEndFrame);
    final videoStartFrame = secondsToTimecodeFrame(segment.start);
    final videoEndFrame = secondsToTimecodeFrame(segment.end);
    final shouldRelink =
        segment.audioLinked ||
        (audioStartFrame == videoStartFrame && audioEndFrame == videoEndFrame);
    return _directorSegment(
      _normalizeSegmentAudio(
        segment.copyWith(
          audioStart: audioStart,
          audioEnd: audioEnd,
          audioLinked: shouldRelink,
        ),
      ),
    );
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
          'hook_score': candidate.hookScore,
          'completion_score': candidate.completionScore,
          'risk_count': candidate.riskCount,
          'strengths': candidate.strengths,
          'issues': candidate.issues,
          'story_flow': candidate.storyFlow,
          'story_score': candidate.storyScore,
          'selected': candidate.selected,
        },
    ];
  }

  String _buildShortsCutListCsv(List<ShortsCandidate> candidates) {
    if (candidates.isEmpty) {
      return '';
    }
    final rows = <List<String>>[
      const [
        'candidate_id',
        'candidate_label',
        'selected',
        'readiness',
        'quality_grade',
        'quality_score',
        'hook_score',
        'completion_score',
        'story_score',
        'story_flow',
        'strengths',
        'issues',
        'clip_order',
        'source_in_tc',
        'source_out_tc',
        'source_in_seconds',
        'source_out_seconds',
        'duration_seconds',
        'audio_in_tc',
        'audio_out_tc',
        'story_role',
        'reason',
        'script',
        'tags',
        'video_enabled',
        'audio_muted',
        'audio_channel_1',
        'audio_channel_2',
        'playback_speed',
      ],
    ];
    for (final candidate in candidates) {
      for (final segment in candidate.segments) {
        final role = _storyLabelForRole(
          _shortsStoryRole(segment, candidate.strategyKind),
        );
        rows.add([
          candidate.id.toString(),
          candidate.label,
          candidate.selected ? 'TRUE' : 'FALSE',
          candidate.readinessLabel,
          candidate.qualityGrade,
          candidate.qualityScore.toStringAsFixed(1),
          candidate.hookScore.toStringAsFixed(1),
          candidate.completionScore.toStringAsFixed(1),
          candidate.storyScore.toStringAsFixed(1),
          candidate.storyFlow.join(' > '),
          candidate.strengths.join('; '),
          candidate.issues.join('; '),
          segment.order.toString(),
          formatSeconds(segment.start),
          formatSeconds(segment.end),
          segment.start.toStringAsFixed(3),
          segment.end.toStringAsFixed(3),
          segment.outputDuration.toStringAsFixed(3),
          formatSeconds(segment.effectiveAudioStart),
          formatSeconds(segment.effectiveAudioEnd),
          role,
          segment.reason,
          segment.script,
          segment.tags.join('; '),
          segment.videoEnabled ? 'TRUE' : 'FALSE',
          segment.audioMuted ? 'TRUE' : 'FALSE',
          segment.audioChannel1Enabled ? 'TRUE' : 'FALSE',
          segment.audioChannel2Enabled ? 'TRUE' : 'FALSE',
          segment.playbackSpeed.toStringAsFixed(3),
        ]);
      }
    }
    return rows.map(_csvRow).join('\r\n');
  }

  String _csvRow(List<String> cells) {
    return cells.map(_csvCell).join(',');
  }

  String _csvCell(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!normalized.contains(',') &&
        !normalized.contains('"') &&
        !normalized.contains('\n')) {
      return normalized;
    }
    return '"${normalized.replaceAll('"', '""')}"';
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
        hookScore: _doubleFromProjectJson(
          raw['hook_score'] ?? raw['hookScore'],
          0,
        ),
        completionScore: _doubleFromProjectJson(
          raw['completion_score'] ?? raw['completionScore'],
          0,
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
    required String strategyKind,
    required double minSeconds,
    required double maxSeconds,
  }) {
    final available =
        segments
            .where(
              (segment) =>
                  !used.contains(segment.order) &&
                  (seed.topicId <= 0 || segment.topicId == seed.topicId),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final seedIndex = available.indexWhere(
      (segment) => segment.order == seed.order,
    );
    if (seedIndex < 0) {
      return const [];
    }
    final group = <HighlightSegment>[seed];
    var total = seed.outputDuration;
    total = _addMissingShortsStoryRoles(
      group,
      available,
      strategyKind,
      total: total,
      minSeconds: minSeconds,
      maxSeconds: maxSeconds,
    );
    total = _fillShortsGroupToMinimum(
      group,
      available,
      strategyKind,
      total: total,
      minSeconds: minSeconds,
      maxSeconds: maxSeconds,
    );
    group.sort((a, b) => a.start.compareTo(b.start));
    return group;
  }

  double _addMissingShortsStoryRoles(
    List<HighlightSegment> group,
    List<HighlightSegment> available,
    String strategyKind, {
    required double total,
    required double minSeconds,
    required double maxSeconds,
  }) {
    var nextTotal = total;
    for (final role in _shortsTargetRolesForStrategy(strategyKind)) {
      if (!_shortsGroupNeedsLengthFill(
        group,
        strategyKind,
        total: nextTotal,
        minSeconds: minSeconds,
      )) {
        break;
      }
      if (_shortsGroupContainsRole(group, role, strategyKind)) {
        continue;
      }
      final candidate = _bestShortsRoleCandidate(
        group,
        available,
        role,
        strategyKind,
        total: nextTotal,
        maxSeconds: maxSeconds,
      );
      if (candidate == null) {
        continue;
      }
      group.add(candidate);
      nextTotal += candidate.outputDuration;
    }
    return nextTotal;
  }

  double _fillShortsGroupToMinimum(
    List<HighlightSegment> group,
    List<HighlightSegment> available,
    String strategyKind, {
    required double total,
    required double minSeconds,
    required double maxSeconds,
  }) {
    var nextTotal = total;
    while (_shortsGroupNeedsLengthFill(
      group,
      strategyKind,
      total: nextTotal,
      minSeconds: minSeconds,
    )) {
      final candidates = available
          .where(
            (candidate) =>
                !_shortsGroupContainsSegment(group, candidate) &&
                candidate.outputDuration > 0 &&
                nextTotal + candidate.outputDuration <= maxSeconds + 0.001,
          )
          .toList();
      if (candidates.isEmpty) {
        break;
      }
      candidates.sort((a, b) {
        final scoreCompare = _shortsFillerCandidateScore(
          b,
          group,
          strategyKind,
        ).compareTo(_shortsFillerCandidateScore(a, group, strategyKind));
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.start.compareTo(b.start);
      });
      final next = candidates.first;
      group.add(next);
      nextTotal += next.outputDuration;
    }
    return nextTotal;
  }

  bool _shortsGroupNeedsLengthFill(
    List<HighlightSegment> group,
    String strategyKind, {
    required double total,
    required double minSeconds,
  }) {
    if (total >= minSeconds) {
      return false;
    }
    if (total >= minSeconds * 0.95 &&
        _shortsGroupHasSupportRole(group, strategyKind)) {
      return false;
    }
    return true;
  }

  bool _shortsGroupHasSupportRole(
    List<HighlightSegment> group,
    String strategyKind,
  ) {
    return group.any((segment) {
      final role = _shortsStoryRole(segment, strategyKind);
      return role == 'evidence' || role == 'context' || role == 'risk';
    });
  }

  List<String> _shortsTargetRolesForStrategy(String strategyKind) {
    return switch (strategyKind) {
      'risk' => const ['risk', 'evidence', 'impact', 'resolution'],
      'news' => const ['hook', 'evidence', 'impact', 'resolution'],
      'info' => const ['hook', 'context', 'evidence', 'resolution'],
      _ => const ['hook', 'evidence', 'impact', 'resolution', 'context'],
    };
  }

  HighlightSegment? _bestShortsRoleCandidate(
    List<HighlightSegment> group,
    List<HighlightSegment> available,
    String targetRole,
    String strategyKind, {
    required double total,
    required double maxSeconds,
  }) {
    final candidates = available
        .where(
          (candidate) =>
              !_shortsGroupContainsSegment(group, candidate) &&
              candidate.outputDuration > 0 &&
              total + candidate.outputDuration <= maxSeconds + 0.001 &&
              _shortsStoryRole(candidate, strategyKind) == targetRole,
        )
        .toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) {
      final scoreCompare =
          _shortsRoleCandidateScore(
            b,
            group,
            targetRole,
            strategyKind,
          ).compareTo(
            _shortsRoleCandidateScore(a, group, targetRole, strategyKind),
          );
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.start.compareTo(b.start);
    });
    return candidates.first;
  }

  double _shortsRoleCandidateScore(
    HighlightSegment candidate,
    List<HighlightSegment> group,
    String targetRole,
    String strategyKind,
  ) {
    var score = _shortsSeedScore(strategyKind, candidate);
    final distance = _shortsDistanceToGroup(candidate, group);
    score += 36 - math.min(distance / 12, 36);
    final targetRank = _shortsRoleRank(targetRole);
    final groupStart = group.fold<double>(
      group.first.start,
      (value, segment) => math.min(value, segment.start),
    );
    final groupEnd = group.fold<double>(
      group.first.end,
      (value, segment) => math.max(value, segment.end),
    );
    if (targetRank <= 1 && candidate.start <= groupStart + 90) {
      score += 8;
    }
    if (targetRank >= 3 && candidate.start >= groupEnd - 1) {
      score += 8;
    }
    for (final segment in group) {
      final segmentRank = _shortsRoleRank(
        _shortsStoryRole(segment, strategyKind),
      );
      if (segmentRank < targetRank && candidate.end < segment.start) {
        score -= 18;
      }
      if (segmentRank > targetRank && candidate.start > segment.end) {
        score -= 12;
      }
    }
    if (targetRole != 'risk' &&
        strategyKind != 'risk' &&
        _segmentHasRiskSignal(candidate)) {
      score -= 20;
    }
    return score;
  }

  double _shortsFillerCandidateScore(
    HighlightSegment candidate,
    List<HighlightSegment> group,
    String strategyKind,
  ) {
    final role = _shortsStoryRole(candidate, strategyKind);
    var score = _shortsSeedScore(strategyKind, candidate) * 0.45;
    final distance = _shortsDistanceToGroup(candidate, group);
    score += 42 - math.min(distance / 8, 42);
    if (!_shortsGroupContainsRole(group, role, strategyKind)) {
      score += 24;
    }
    if (role == 'close') {
      score -= 16;
    }
    if (strategyKind != 'risk' && _segmentHasRiskSignal(candidate)) {
      score -= 24;
    }
    return score;
  }

  double _shortsDistanceToGroup(
    HighlightSegment candidate,
    List<HighlightSegment> group,
  ) {
    var distance = double.infinity;
    for (final segment in group) {
      if (candidate.start <= segment.end && candidate.end >= segment.start) {
        return 0;
      }
      if (candidate.end < segment.start) {
        distance = math.min(distance, segment.start - candidate.end);
      } else {
        distance = math.min(distance, candidate.start - segment.end);
      }
    }
    return distance.isFinite ? distance : 0;
  }

  bool _shortsGroupContainsRole(
    List<HighlightSegment> group,
    String role,
    String strategyKind,
  ) {
    return group.any(
      (segment) => _shortsStoryRole(segment, strategyKind) == role,
    );
  }

  bool _shortsGroupContainsSegment(
    List<HighlightSegment> group,
    HighlightSegment candidate,
  ) {
    return group.any((segment) => segment.order == candidate.order);
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
    final durationText = sequenceOutputDuration(input).round();
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

  HighlightSegment? _segmentAtTimelinePoint(double seconds) {
    final frame = secondsToTimecodeFrame(
      _snapToFrame(_clampProjectTime(seconds)),
    );
    for (final segment in segments) {
      final startFrame = secondsToTimecodeFrame(segment.start);
      final endFrame = secondsToTimecodeFrame(segment.end);
      if (frame >= startFrame && frame < endFrame) {
        return segment;
      }
    }
    for (final segment in segments) {
      final startFrame = secondsToTimecodeFrame(segment.start);
      final endFrame = secondsToTimecodeFrame(segment.end);
      if (frame > startFrame && frame <= endFrame) {
        return segment;
      }
    }
    return null;
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
    bool markProjectDirty = true,
  }) {
    final previousSourcePath = selectedFile?.path;
    projectName = project.name;
    if (!keepJob) {
      if (jobId != project.jobId) {
        job = null;
      }
      jobId = project.jobId;
      final restoredPath = project.originalPath;
      final restoredName =
          project.originalFilename ??
          (restoredPath == null
              ? null
              : io.File(restoredPath).uri.pathSegments.last);
      selectedFile = restoredName == null
          ? null
          : PlatformFile(name: restoredName, size: 0, path: restoredPath);
    }
    duration = project.duration;
    _manualPlayheadSeconds = 0;
    previewMonitorMode = 'source';
    _programPlayheadSeconds = 0;
    _programSegmentOrder = null;
    _programCutPending = false;
    segments = _reorderSegments(project.segments);
    videoOverlays = List<VideoOverlayClip>.of(project.videoOverlays);
    audioClips = List<AudioClip>.of(project.audioClips);
    activeVideoTrackCount = project.activeVideoTrackCount.clamp(1, 4).toInt();
    activeAudioTrackCount = project.activeAudioTrackCount.clamp(2, 8).toInt();
    targetedVideoOverlayTrack = activeVideoTrackCount >= 2 ? 2 : 1;
    targetedOverlayAudioTrack = activeAudioTrackCount >= 3 ? 3 : 2;
    videoOverlayTrackTargeted = activeVideoTrackCount >= 2;
    audioTrack3Targeted = activeAudioTrackCount >= 3;
    selectedVideoOverlayId = null;
    selectedAudioClipId = null;
    transcript = List<TranscriptSegment>.of(project.transcript);
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
    selectedExportProfiles = List<String>.of(project.selectedExportProfiles);
    markIn = project.markIn;
    markOut = project.markOut;
    selectedSegmentOrder = segments.isEmpty ? null : segments.first.order;
    renderUrl = null;
    if (resetHistory) {
      _clearHistory();
    }
    if (markProjectDirty) {
      _markProjectDirty();
    }
    if (previousSourcePath != selectedFile?.path) {
      _clearTimelineThumbnails();
    }
    _scheduleTimelineThumbnails(delay: Duration.zero);
  }

  void _scheduleProjectRecoverySave() {
    if (!_projectRecoveryEnabled || _isDisposed || !hasRecoverableProject) {
      return;
    }
    if (_recoverySaveTimer?.isActive ?? false) {
      return;
    }
    _recoverySaveTimer = Timer(_projectRecoveryDebounce, () {
      unawaited(_writeProjectRecoverySnapshot());
    });
  }

  Future<void> _writeProjectRecoverySnapshot() async {
    if (!_projectRecoveryEnabled || _isDisposed || !hasRecoverableProject) {
      return;
    }
    await _awaitRecoveryInitialization();
    if (_isDisposed || !hasRecoverableProject) {
      return;
    }
    final project = projectState;
    final payload = jsonEncode(project.toJson());
    if (payload == _lastRecoveryPayload) {
      return;
    }
    try {
      final snapshot = await _recoveryService.saveProject(project);
      _lastRecoveryPayload = payload;
      if (_isDisposed) {
        return;
      }
      hasRecoverySnapshot = true;
      recoverySnapshotSavedAt = snapshot.savedAt;
      recoveryVersions = await _recoveryService.listVersions();
      super.notifyListeners();
    } catch (_) {
      // Recovery must never interrupt editing.
    }
  }

  _EditorSnapshot _captureSnapshot() {
    return _EditorSnapshot(
      createdAt: DateTime.now(),
      segments: List<HighlightSegment>.of(segments),
      videoOverlays: List<VideoOverlayClip>.of(videoOverlays),
      audioClips: List<AudioClip>.of(audioClips),
      activeVideoTrackCount: activeVideoTrackCount,
      activeAudioTrackCount: activeAudioTrackCount,
      targetedVideoOverlayTrack: targetedVideoOverlayTrack,
      targetedOverlayAudioTrack: targetedOverlayAudioTrack,
      captions: List<CaptionSegment>.of(captions),
      timelineMarkers: List<TimelineMarker>.of(timelineMarkers),
      selectedSegmentOrder: selectedSegmentOrder,
      selectedVideoOverlayId: selectedVideoOverlayId,
      selectedAudioClipId: selectedAudioClipId,
      markIn: markIn,
      markOut: markOut,
      includeCaptions: includeCaptions,
      captionStylePreset: captionStylePreset,
      exportAspectRatio: exportAspectRatio,
      selectedExportProfiles: List<String>.of(selectedExportProfiles),
    );
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    segments = _reorderSegments(snapshot.segments);
    videoOverlays = List<VideoOverlayClip>.of(snapshot.videoOverlays);
    audioClips = List<AudioClip>.of(snapshot.audioClips);
    activeVideoTrackCount = snapshot.activeVideoTrackCount;
    activeAudioTrackCount = snapshot.activeAudioTrackCount;
    targetedVideoOverlayTrack = snapshot.targetedVideoOverlayTrack;
    targetedOverlayAudioTrack = snapshot.targetedOverlayAudioTrack;
    videoOverlayTrackTargeted = targetedVideoOverlayTrack >= 2;
    audioTrack3Targeted = targetedOverlayAudioTrack == 3;
    captions = [
      for (var index = 0; index < snapshot.captions.length; index++)
        snapshot.captions[index].copyWith(order: index + 1),
    ];
    selectedSegmentOrder = snapshot.selectedSegmentOrder;
    selectedVideoOverlayId = snapshot.selectedVideoOverlayId;
    selectedAudioClipId = snapshot.selectedAudioClipId;
    if (selectedSegmentOrder != null &&
        !segments.any((segment) => segment.order == selectedSegmentOrder)) {
      selectedSegmentOrder = segments.isEmpty ? null : segments.first.order;
    }
    if (selectedVideoOverlayId != null &&
        !videoOverlays.any((overlay) => overlay.id == selectedVideoOverlayId)) {
      selectedVideoOverlayId = null;
    }
    if (selectedAudioClipId != null &&
        !audioClips.any((clip) => clip.id == selectedAudioClipId)) {
      selectedAudioClipId = null;
    }
    markIn = snapshot.markIn;
    markOut = snapshot.markOut;
    timelineMarkers = _normalizeTimelineMarkers(snapshot.timelineMarkers);
    includeCaptions = snapshot.includeCaptions;
    captionStylePreset = snapshot.captionStylePreset;
    exportAspectRatio = snapshot.exportAspectRatio;
    selectedExportProfiles = List<String>.of(snapshot.selectedExportProfiles);
  }

  void _commitHistory() {
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _markProjectDirty();
  }

  void _markProjectDirty() {
    _projectRevision += 1;
    _scheduleTimelineThumbnails();
  }

  void _markProjectSaved() {
    _savedProjectRevision = _projectRevision;
  }

  Future<void> _awaitRecoveryInitialization() async {
    final initialization = _recoveryInitialization;
    if (initialization != null) {
      await initialization;
    }
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
    _markProjectDirty();
  }

  String _safeProjectFileName() {
    final base = projectName.trim().isEmpty ? 'autoedit_project' : projectName;
    return base.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
    _scheduleProjectRecoverySave();
  }

  @override
  void dispose() {
    if (_projectRecoveryEnabled) {
      try {
        _recoveryService.markSessionCleanSync();
      } catch (_) {
        // Session recovery must never prevent the editor from closing.
      }
    }
    _isDisposed = true;
    _pollTimer?.cancel();
    _stylePollTimer?.cancel();
    _recoverySaveTimer?.cancel();
    _reverseShuttleTimer?.cancel();
    _timelineThumbnailTimer?.cancel();
    _programPreviewRefreshTimer?.cancel();
    _programPreviewPrefetchKey = null;
    _programPreviewPrefetchFuture = null;
    for (final image in timelineThumbnails.values) {
      image.dispose();
    }
    timelineThumbnails = const {};
    final activeVideoController = videoController;
    videoController = null;
    unawaited(_disposePreviewControllerSafely(activeVideoController));
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

class ShortsExportQueueItem {
  const ShortsExportQueueItem({
    required this.candidate,
    required this.outputName,
    required this.durationSeconds,
    required this.clipCount,
    required this.blockCount,
    required this.warnCount,
    required this.statusDetail,
  });

  final ShortsCandidate candidate;
  final String outputName;
  final double durationSeconds;
  final int clipCount;
  final int blockCount;
  final int warnCount;
  final String statusDetail;

  bool get canRender => blockCount == 0;

  String get statusLabel {
    if (blockCount > 0) {
      return 'Blocked';
    }
    if (warnCount > 0) {
      return 'Warn';
    }
    return 'Ready';
  }
}

enum AutoFixSeverity { block, warn, polish }

enum AutoFixAction {
  restoreVideo,
  enableAudioPair,
  padContext,
  trimLongClip,
  removeWeak,
  closeGap,
  mixAudio,
  syncAudioLength,
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
    this.hookScore = 0,
    this.completionScore = 0,
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
  final double hookScore;
  final double completionScore;
  final int riskCount;
  final List<String> strengths;
  final List<String> issues;
  final List<String> storyFlow;
  final double storyScore;
  final bool selected;

  double get durationSeconds => sequenceOutputDuration(segments);

  bool get hasSeriousReviewIssue =>
      riskCount > 0 ||
      issues.contains('Risk review') ||
      issues.contains('Offline review');

  bool get hasBlockingStoryIssue => issues.any(
    const {
      'Missing risk',
      'Missing hook',
      'Missing evidence',
      'Missing impact',
      'Weak ending',
      'Story order',
      'Early CTA',
      'Mixed topics',
    }.contains,
  );

  bool get isPublishReady =>
      qualityScore >= 70 &&
      storyScore >= 58 &&
      hookScore >= 50 &&
      completionScore >= 55 &&
      !hasSeriousReviewIssue &&
      !hasBlockingStoryIssue &&
      !issues.contains('Story flow') &&
      !issues.contains('Weak hook') &&
      !issues.contains('Incomplete') &&
      !issues.contains('Audio mix');

  bool get needsEditorialReview =>
      !isPublishReady &&
      !issues.contains('No clips') &&
      (qualityScore >= 55 || hasSeriousReviewIssue && qualityScore >= 35);

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
    double? hookScore,
    double? completionScore,
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
      hookScore: hookScore ?? this.hookScore,
      completionScore: completionScore ?? this.completionScore,
      riskCount: riskCount ?? this.riskCount,
      strengths: strengths ?? this.strengths,
      issues: issues ?? this.issues,
      storyFlow: storyFlow ?? this.storyFlow,
      storyScore: storyScore ?? this.storyScore,
      selected: selected ?? this.selected,
    );
  }
}

class _ProgramSpan {
  const _ProgramSpan({
    required this.segment,
    required this.index,
    required this.sequenceStart,
    required this.sequenceEnd,
  });

  final HighlightSegment segment;
  final int index;
  final double sequenceStart;
  final double sequenceEnd;
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.createdAt,
    required this.segments,
    required this.videoOverlays,
    required this.audioClips,
    required this.activeVideoTrackCount,
    required this.activeAudioTrackCount,
    required this.targetedVideoOverlayTrack,
    required this.targetedOverlayAudioTrack,
    required this.captions,
    required this.timelineMarkers,
    required this.selectedSegmentOrder,
    required this.selectedVideoOverlayId,
    required this.selectedAudioClipId,
    required this.markIn,
    required this.markOut,
    required this.includeCaptions,
    required this.captionStylePreset,
    required this.exportAspectRatio,
    required this.selectedExportProfiles,
  });

  final DateTime createdAt;
  final List<HighlightSegment> segments;
  final List<VideoOverlayClip> videoOverlays;
  final List<AudioClip> audioClips;
  final int activeVideoTrackCount;
  final int activeAudioTrackCount;
  final int targetedVideoOverlayTrack;
  final int targetedOverlayAudioTrack;
  final List<CaptionSegment> captions;
  final List<TimelineMarker> timelineMarkers;
  final int? selectedSegmentOrder;
  final String? selectedVideoOverlayId;
  final String? selectedAudioClipId;
  final double? markIn;
  final double? markOut;
  final bool includeCaptions;
  final String captionStylePreset;
  final String exportAspectRatio;
  final List<String> selectedExportProfiles;
}

class EditorHistoryPoint {
  const EditorHistoryPoint({
    required this.depth,
    required this.label,
    required this.detail,
    required this.createdAt,
    this.isCurrent = false,
  });

  final int depth;
  final String label;
  final String detail;
  final DateTime createdAt;
  final bool isCurrent;
}
