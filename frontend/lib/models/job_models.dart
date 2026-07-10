import 'highlight_segment.dart';
import '../utils/timecode.dart';

class UploadJobResponse {
  const UploadJobResponse({
    required this.jobId,
    required this.status,
    required this.stage,
    required this.progress,
    this.duration,
  });

  final String jobId;
  final String status;
  final String stage;
  final int progress;
  final double? duration;

  factory UploadJobResponse.fromJson(Map<String, dynamic> json) {
    return UploadJobResponse(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
      stage: json['stage'] as String,
      progress: (json['progress'] as num).toInt(),
      duration: (json['duration'] as num?)?.toDouble(),
    );
  }
}

class MediaProbeInfo {
  const MediaProbeInfo({
    required this.path,
    required this.filename,
    required this.container,
    required this.formatLongName,
    required this.duration,
    required this.bitRate,
    required this.videoCodec,
    required this.videoCodecLongName,
    required this.width,
    required this.height,
    required this.frameRate,
    this.sourceFrameRate = 0,
    this.sourceTimecode,
    this.sourceDropFrame = false,
    this.timelineFrameRate = timecodeFrameRate,
    this.timelineTimecodeMode = 'non_drop',
    this.timelineTimebase = '30p NDF',
    required this.audioStreamCount,
    required this.audioChannelCount,
    required this.audioSummary,
    required this.isMxf,
    required this.mxfOperationalPattern,
    required this.canAnalyze,
    required this.warnings,
    this.timecode,
  });

  final String path;
  final String filename;
  final String container;
  final String formatLongName;
  final double duration;
  final int bitRate;
  final String videoCodec;
  final String videoCodecLongName;
  final int width;
  final int height;
  final double frameRate;
  final double sourceFrameRate;
  final String? sourceTimecode;
  final bool sourceDropFrame;
  final double timelineFrameRate;
  final String timelineTimecodeMode;
  final String timelineTimebase;
  final String? timecode;
  final int audioStreamCount;
  final int audioChannelCount;
  final String audioSummary;
  final bool isMxf;
  final String mxfOperationalPattern;
  final bool canAnalyze;
  final List<String> warnings;

  String get resolutionLabel {
    if (width <= 0 || height <= 0) {
      return 'Unknown';
    }
    return '${width}x$height';
  }

  String get sourceFrameRateLabel {
    final value = sourceFrameRate > 0 ? sourceFrameRate : frameRate;
    return '${value.toStringAsFixed(3)} fps';
  }

  String get timelineTimebaseLabel {
    if (timelineTimebase.trim().isNotEmpty) {
      return timelineTimebase;
    }
    return '${timelineFrameRate.toStringAsFixed(2)}p NDF';
  }

  factory MediaProbeInfo.fromJson(Map<String, dynamic> json) {
    final rawWarnings = json['warnings'] as List<dynamic>? ?? const [];
    return MediaProbeInfo(
      path: json['path'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      container: json['container'] as String? ?? '',
      formatLongName: json['format_long_name'] as String? ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      bitRate: (json['bit_rate'] as num?)?.toInt() ?? 0,
      videoCodec: json['video_codec'] as String? ?? '',
      videoCodecLongName: json['video_codec_long_name'] as String? ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      frameRate: (json['frame_rate'] as num?)?.toDouble() ?? 0,
      sourceFrameRate:
          (json['source_frame_rate'] as num?)?.toDouble() ??
          (json['frame_rate'] as num?)?.toDouble() ??
          0,
      sourceTimecode: json['source_timecode'] as String?,
      sourceDropFrame: json['source_drop_frame'] as bool? ?? false,
      timelineFrameRate: timecodeFrameRate,
      timelineTimecodeMode: 'non_drop',
      timelineTimebase: json['timeline_timebase'] as String? ?? '30p NDF',
      timecode: normalizeTimecodeText(json['timecode'] as String?),
      audioStreamCount: (json['audio_stream_count'] as num?)?.toInt() ?? 0,
      audioChannelCount:
          (json['audio_channel_count'] as num?)?.toInt() ??
          (json['audio_stream_count'] as num?)?.toInt() ??
          0,
      audioSummary: json['audio_summary'] as String? ?? '',
      isMxf: json['is_mxf'] as bool? ?? false,
      mxfOperationalPattern: json['mxf_operational_pattern'] as String? ?? '',
      canAnalyze: json['can_analyze'] as bool? ?? false,
      warnings: rawWarnings.map((item) => item.toString()).toList(),
    );
  }
}

class StorageCategoryInfo {
  const StorageCategoryInfo({
    required this.key,
    required this.label,
    required this.bytes,
    required this.files,
    required this.reclaimableBytes,
    required this.protected,
  });

  final String key;
  final String label;
  final int bytes;
  final int files;
  final int reclaimableBytes;
  final bool protected;

  factory StorageCategoryInfo.fromJson(Map<String, dynamic> json) {
    return StorageCategoryInfo(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      files: (json['files'] as num?)?.toInt() ?? 0,
      reclaimableBytes: (json['reclaimable_bytes'] as num?)?.toInt() ?? 0,
      protected: json['protected'] as bool? ?? false,
    );
  }
}

class StorageUsageInfo {
  const StorageUsageInfo({
    required this.dataDir,
    required this.totalBytes,
    required this.reclaimableBytes,
    required this.retentionHours,
    required this.categories,
    required this.protectedItems,
  });

  final String dataDir;
  final int totalBytes;
  final int reclaimableBytes;
  final int retentionHours;
  final List<StorageCategoryInfo> categories;
  final List<String> protectedItems;

  factory StorageUsageInfo.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'] as List<dynamic>? ?? const [];
    final rawProtected = json['protected_items'] as List<dynamic>? ?? const [];
    return StorageUsageInfo(
      dataDir: json['data_dir'] as String? ?? '',
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      reclaimableBytes: (json['reclaimable_bytes'] as num?)?.toInt() ?? 0,
      retentionHours: (json['retention_hours'] as num?)?.toInt() ?? 24,
      categories: rawCategories
          .whereType<Map>()
          .map(
            (item) =>
                StorageCategoryInfo.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      protectedItems: rawProtected.map((item) => item.toString()).toList(),
    );
  }
}

class StorageCleanupInfo {
  const StorageCleanupInfo({
    required this.freedBytes,
    required this.deletedFiles,
    required this.skippedFiles,
    required this.before,
    required this.after,
  });

  final int freedBytes;
  final int deletedFiles;
  final int skippedFiles;
  final StorageUsageInfo before;
  final StorageUsageInfo after;

  factory StorageCleanupInfo.fromJson(Map<String, dynamic> json) {
    return StorageCleanupInfo(
      freedBytes: (json['freed_bytes'] as num?)?.toInt() ?? 0,
      deletedFiles: (json['deleted_files'] as num?)?.toInt() ?? 0,
      skippedFiles: (json['skipped_files'] as num?)?.toInt() ?? 0,
      before: StorageUsageInfo.fromJson(
        Map<String, dynamic>.from(json['before'] as Map? ?? const {}),
      ),
      after: StorageUsageInfo.fromJson(
        Map<String, dynamic>.from(json['after'] as Map? ?? const {}),
      ),
    );
  }
}

class JobStatusResponse {
  const JobStatusResponse({
    required this.jobId,
    required this.status,
    required this.stage,
    required this.progress,
    required this.message,
    this.duration,
    this.originalFilename,
    this.renderPath,
    this.renderUrl,
    this.renderDurationSeconds,
    this.renderSizeBytes,
    this.renderWarnings = const [],
    this.error,
    this.styleProfile,
    this.analysisWarnings = const [],
    this.batchRenderItems = const [],
    this.renderManifestItems = const [],
    this.segments = const [],
  });

  final String jobId;
  final String status;
  final String stage;
  final int progress;
  final String message;
  final double? duration;
  final String? originalFilename;
  final String? renderPath;
  final String? renderUrl;
  final double? renderDurationSeconds;
  final int? renderSizeBytes;
  final List<String> renderWarnings;
  final String? error;
  final StyleProfile? styleProfile;
  final List<String> analysisWarnings;
  final List<BatchRenderItemResult> batchRenderItems;
  final List<BatchRenderItemResult> renderManifestItems;
  final List<HighlightSegment> segments;

  factory JobStatusResponse.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'] as List<dynamic>? ?? const [];
    final rawBatchItems =
        json['batch_render_items'] as List<dynamic>? ?? const [];
    final rawManifestItems =
        json['render_manifest_items'] as List<dynamic>? ?? const [];
    final rawWarnings = json['analysis_warnings'] as List<dynamic>? ?? const [];
    final rawRenderWarnings =
        json['render_warnings'] as List<dynamic>? ?? const [];
    return JobStatusResponse(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
      stage: json['stage'] as String,
      progress: (json['progress'] as num).toInt(),
      message: json['message'] as String? ?? '',
      duration: (json['duration'] as num?)?.toDouble(),
      originalFilename: json['original_filename'] as String?,
      renderPath: json['render_path'] as String?,
      renderUrl: json['render_url'] as String?,
      renderDurationSeconds: (json['render_duration_seconds'] as num?)
          ?.toDouble(),
      renderSizeBytes: (json['render_size_bytes'] as num?)?.toInt(),
      renderWarnings: rawRenderWarnings.map((item) => item.toString()).toList(),
      error: json['error'] as String?,
      styleProfile: json['style_profile'] == null
          ? null
          : StyleProfile.fromJson(
              json['style_profile'] as Map<String, dynamic>,
            ),
      analysisWarnings: rawWarnings.map((item) => item.toString()).toList(),
      batchRenderItems: rawBatchItems
          .map(
            (item) =>
                BatchRenderItemResult.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      renderManifestItems: rawManifestItems
          .map(
            (item) =>
                BatchRenderItemResult.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      segments: rawSegments
          .map(
            (item) => HighlightSegment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class BatchRenderItemResult {
  const BatchRenderItemResult({
    required this.label,
    required this.outputName,
    required this.url,
    this.kind = 'video',
    this.aspectRatio = '',
    this.path = '',
    this.durationSeconds = 0,
    this.sizeBytes = 0,
    this.warnings = const [],
  });

  final String label;
  final String outputName;
  final String url;
  final String kind;
  final String aspectRatio;
  final String path;
  final double durationSeconds;
  final int sizeBytes;
  final List<String> warnings;
  bool get isManifest => kind == 'manifest';

  factory BatchRenderItemResult.fromJson(Map<String, dynamic> json) {
    final rawWarnings = json['warnings'] as List<dynamic>? ?? const [];
    return BatchRenderItemResult(
      label: json['label'] as String? ?? 'Shorts',
      outputName: json['output_name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      kind: json['kind'] as String? ?? 'video',
      aspectRatio: json['aspect_ratio'] as String? ?? '',
      path: json['path'] as String? ?? '',
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      warnings: rawWarnings.map((item) => item.toString()).toList(),
    );
  }
}

class StyleProfile {
  const StyleProfile({
    required this.styleId,
    required this.name,
    required this.status,
    required this.message,
    required this.progress,
    required this.sourceCount,
    required this.readySourceCount,
    required this.pace,
    required this.averageCutSeconds,
    required this.hookWindowSeconds,
    required this.silenceAggressiveness,
    required this.visualChangeSensitivity,
    required this.targetSegmentSecondsMin,
    required this.targetSegmentSecondsIdeal,
    required this.targetSegmentSecondsMax,
    required this.preferNewsStructure,
    required this.preferShortsStructure,
    required this.transitionStyle,
    required this.scoringWeights,
    required this.sources,
    this.error,
  });

  final String styleId;
  final String name;
  final String status;
  final String message;
  final int progress;
  final int sourceCount;
  final int readySourceCount;
  final String pace;
  final double averageCutSeconds;
  final double hookWindowSeconds;
  final double silenceAggressiveness;
  final double visualChangeSensitivity;
  final double targetSegmentSecondsMin;
  final double targetSegmentSecondsIdeal;
  final double targetSegmentSecondsMax;
  final bool preferNewsStructure;
  final bool preferShortsStructure;
  final String transitionStyle;
  final Map<String, double> scoringWeights;
  final List<StyleReferenceSource> sources;
  final String? error;

  bool get isReady => status == 'ready';
  bool get isActive => status == 'queued' || status == 'processing';

  factory StyleProfile.fromJson(Map<String, dynamic> json) {
    final rawWeights = json['scoring_weights'] as Map<String, dynamic>? ?? {};
    final rawSources = json['sources'] as List<dynamic>? ?? const [];
    return StyleProfile(
      styleId: json['style_id'] as String,
      name: json['name'] as String? ?? 'Reference Style',
      status: json['status'] as String? ?? 'queued',
      message: json['message'] as String? ?? '',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      sourceCount: (json['source_count'] as num?)?.toInt() ?? 0,
      readySourceCount: (json['ready_source_count'] as num?)?.toInt() ?? 0,
      pace: json['pace'] as String? ?? 'balanced',
      averageCutSeconds:
          (json['average_cut_seconds'] as num?)?.toDouble() ?? 6.0,
      hookWindowSeconds:
          (json['hook_window_seconds'] as num?)?.toDouble() ?? 15.0,
      silenceAggressiveness:
          (json['silence_aggressiveness'] as num?)?.toDouble() ?? 0.6,
      visualChangeSensitivity:
          (json['visual_change_sensitivity'] as num?)?.toDouble() ?? 0.5,
      targetSegmentSecondsMin:
          (json['target_segment_seconds_min'] as num?)?.toDouble() ?? 18.0,
      targetSegmentSecondsIdeal:
          (json['target_segment_seconds_ideal'] as num?)?.toDouble() ?? 36.0,
      targetSegmentSecondsMax:
          (json['target_segment_seconds_max'] as num?)?.toDouble() ?? 52.0,
      preferNewsStructure: json['prefer_news_structure'] as bool? ?? true,
      preferShortsStructure: json['prefer_shorts_structure'] as bool? ?? false,
      transitionStyle: json['transition_style'] as String? ?? 'hard_cut',
      scoringWeights: rawWeights.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
      sources: rawSources
          .map(
            (item) =>
                StyleReferenceSource.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      error: json['error'] as String?,
    );
  }
}

class StyleReferenceSource {
  const StyleReferenceSource({
    required this.label,
    required this.kind,
    required this.duration,
    required this.sceneCount,
    required this.averageCutSeconds,
    required this.silenceRatio,
    this.url,
    this.error,
  });

  final String label;
  final String kind;
  final String? url;
  final double duration;
  final int sceneCount;
  final double averageCutSeconds;
  final double silenceRatio;
  final String? error;

  factory StyleReferenceSource.fromJson(Map<String, dynamic> json) {
    return StyleReferenceSource(
      label: json['label'] as String? ?? 'Reference',
      kind: json['kind'] as String? ?? 'file',
      url: json['url'] as String?,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      sceneCount: (json['scene_count'] as num?)?.toInt() ?? 0,
      averageCutSeconds: (json['average_cut_seconds'] as num?)?.toDouble() ?? 0,
      silenceRatio: (json['silence_ratio'] as num?)?.toDouble() ?? 0,
      error: json['error'] as String?,
    );
  }
}

class StyleTrainingResponse {
  const StyleTrainingResponse({
    required this.styleId,
    required this.status,
    required this.progress,
    required this.message,
    this.profile,
  });

  final String styleId;
  final String status;
  final int progress;
  final String message;
  final StyleProfile? profile;

  factory StyleTrainingResponse.fromJson(Map<String, dynamic> json) {
    return StyleTrainingResponse(
      styleId: json['style_id'] as String,
      status: json['status'] as String,
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? '',
      profile: json['profile'] == null
          ? null
          : StyleProfile.fromJson(json['profile'] as Map<String, dynamic>),
    );
  }
}

class CaptionRenderStyle {
  const CaptionRenderStyle({
    required this.preset,
    required this.fontName,
    required this.fontSize,
    required this.primaryColor,
    required this.outlineColor,
    required this.outline,
    required this.shadow,
    required this.alignment,
    required this.marginV,
  });

  final String preset;
  final String fontName;
  final int fontSize;
  final String primaryColor;
  final String outlineColor;
  final int outline;
  final int shadow;
  final int alignment;
  final int marginV;

  factory CaptionRenderStyle.preset(String preset) {
    switch (preset) {
      case 'shorts':
        return const CaptionRenderStyle(
          preset: 'shorts',
          fontName: 'Arial',
          fontSize: 36,
          primaryColor: '&H00FFFFFF',
          outlineColor: '&HCC111111',
          outline: 4,
          shadow: 1,
          alignment: 5,
          marginV: 90,
        );
      case 'minimal':
        return const CaptionRenderStyle(
          preset: 'minimal',
          fontName: 'Arial',
          fontSize: 22,
          primaryColor: '&H00FFFFFF',
          outlineColor: '&H70000000',
          outline: 1,
          shadow: 0,
          alignment: 2,
          marginV: 64,
        );
      case 'news':
      default:
        return const CaptionRenderStyle(
          preset: 'news',
          fontName: 'Arial',
          fontSize: 28,
          primaryColor: '&H00FFFFFF',
          outlineColor: '&HAA000000',
          outline: 3,
          shadow: 0,
          alignment: 2,
          marginV: 76,
        );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'preset': preset,
      'font_name': fontName,
      'font_size': fontSize,
      'primary_color': primaryColor,
      'outline_color': outlineColor,
      'outline': outline,
      'shadow': shadow,
      'alignment': alignment,
      'margin_v': marginV,
    };
  }
}

class TimelineResponse {
  const TimelineResponse({
    required this.jobId,
    required this.duration,
    required this.segments,
    required this.transcript,
    required this.captions,
    required this.waveform,
  });

  final String jobId;
  final double duration;
  final List<HighlightSegment> segments;
  final List<TranscriptSegment> transcript;
  final List<CaptionSegment> captions;
  final List<double> waveform;

  factory TimelineResponse.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'] as List<dynamic>? ?? const [];
    final rawTranscript = json['transcript'] as List<dynamic>? ?? const [];
    final rawCaptions = json['captions'] as List<dynamic>? ?? const [];
    final rawWaveform = json['waveform'] as List<dynamic>? ?? const [];
    return TimelineResponse(
      jobId: json['job_id'] as String,
      duration: (json['duration'] as num).toDouble(),
      segments: rawSegments
          .map(
            (item) => HighlightSegment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      transcript: rawTranscript
          .map(
            (item) => TranscriptSegment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      captions: rawCaptions
          .map((item) => CaptionSegment.fromJson(item as Map<String, dynamic>))
          .toList(),
      waveform: rawWaveform.map((item) => (item as num).toDouble()).toList(),
    );
  }
}

class TimelineMarker {
  const TimelineMarker({
    required this.id,
    required this.seconds,
    required this.label,
    this.color = 'amber',
    this.note = '',
    this.enabled = true,
  });

  final int id;
  final double seconds;
  final String label;
  final String color;
  final String note;
  final bool enabled;

  factory TimelineMarker.fromJson(Map<String, dynamic> json) {
    return TimelineMarker(
      id: _intFromJson(json['id'], 0),
      seconds: snapSecondsToFrame(_doubleFromJson(json['seconds'], 0)),
      label: _stringFromJson(json['label'], 'Marker'),
      color: _stringFromJson(json['color'], 'amber'),
      note: _stringFromJson(json['note'], ''),
      enabled: _boolFromJson(json['enabled'], true),
    );
  }

  TimelineMarker copyWith({
    int? id,
    double? seconds,
    String? label,
    String? color,
    String? note,
    bool? enabled,
  }) {
    return TimelineMarker(
      id: id ?? this.id,
      seconds: seconds ?? this.seconds,
      label: label ?? this.label,
      color: color ?? this.color,
      note: note ?? this.note,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'seconds': snapSecondsToFrame(seconds),
      'label': label,
      'color': color,
      if (note.isNotEmpty) 'note': note,
      'enabled': enabled,
    };
  }
}

double _doubleFromJson(Object? value, double fallback) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}

int _intFromJson(Object? value, int fallback) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

String _stringFromJson(Object? value, String fallback) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return fallback;
}

bool _boolFromJson(Object? value, bool fallback) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return fallback;
}

class ProjectState {
  const ProjectState({
    required this.name,
    required this.duration,
    required this.segments,
    this.transcript = const [],
    required this.captions,
    required this.waveform,
    this.timelineMarkers = const [],
    this.shortsCandidates = const [],
    this.selectedShortsId,
    this.includeCaptions = true,
    this.captionStylePreset = 'news',
    this.exportAspectRatio = '16:9',
    this.selectedExportProfiles = const ['16:9'],
    this.markIn,
    this.markOut,
    this.jobId,
    this.originalFilename,
    this.originalPath,
  }) : timelineFrameRate = timecodeFrameRate,
       timelineTimecodeMode = 'non_drop';

  final String name;
  final String? jobId;
  final String? originalFilename;
  final String? originalPath;
  final double duration;
  final double timelineFrameRate;
  final String timelineTimecodeMode;
  final List<HighlightSegment> segments;
  final List<TranscriptSegment> transcript;
  final List<CaptionSegment> captions;
  final List<double> waveform;
  final List<TimelineMarker> timelineMarkers;
  final List<Map<String, dynamic>> shortsCandidates;
  final int? selectedShortsId;
  final bool includeCaptions;
  final String captionStylePreset;
  final String exportAspectRatio;
  final List<String> selectedExportProfiles;
  final double? markIn;
  final double? markOut;

  factory ProjectState.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'] as List<dynamic>? ?? const [];
    final rawTranscript = json['transcript'] as List<dynamic>? ?? const [];
    final rawCaptions = json['captions'] as List<dynamic>? ?? const [];
    final rawWaveform = json['waveform'] as List<dynamic>? ?? const [];
    final rawTimelineMarkers =
        json['timeline_markers'] as List<dynamic>? ?? const [];
    final rawShortsCandidates =
        json['shorts_candidates'] as List<dynamic>? ?? const [];
    final exportAspectRatio = json['export_aspect_ratio'] as String? ?? '16:9';
    return ProjectState(
      name: json['name'] as String? ?? 'AutoEdit Project',
      jobId: json['job_id'] as String?,
      originalFilename: json['original_filename'] as String?,
      originalPath: json['original_path'] as String?,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      segments: rawSegments
          .map(
            (item) => HighlightSegment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      transcript: rawTranscript
          .whereType<Map>()
          .map(
            (item) =>
                TranscriptSegment.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      captions: rawCaptions
          .map((item) => CaptionSegment.fromJson(item as Map<String, dynamic>))
          .toList(),
      waveform: rawWaveform.map((item) => (item as num).toDouble()).toList(),
      timelineMarkers: rawTimelineMarkers
          .whereType<Map>()
          .map(
            (item) => TimelineMarker.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      shortsCandidates: rawShortsCandidates
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map(_timelineSafeShortsCandidateMap)
          .toList(),
      selectedShortsId: (json['selected_shorts_id'] as num?)?.toInt(),
      includeCaptions: json['include_captions'] as bool? ?? true,
      captionStylePreset: json['caption_style_preset'] as String? ?? 'news',
      exportAspectRatio: exportAspectRatio,
      selectedExportProfiles: _normalizedExportProfiles(
        json['selected_export_profiles'],
        exportAspectRatio,
      ),
      markIn: _optionalTimelineSecondsFromJson(json['mark_in']),
      markOut: _optionalTimelineSecondsFromJson(json['mark_out']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (jobId != null) 'job_id': jobId,
      if (originalFilename != null) 'original_filename': originalFilename,
      if (originalPath != null) 'original_path': originalPath,
      'duration': duration,
      'timeline_frame_rate': timecodeFrameRate,
      'timeline_timecode_mode': 'non_drop',
      'segments': segments.map((item) => item.toJson()).toList(),
      'transcript': transcript.map((item) => item.toJson()).toList(),
      'captions': captions.map((item) => item.toJson()).toList(),
      'waveform': waveform,
      'timeline_markers': timelineMarkers.map((item) => item.toJson()).toList(),
      'shorts_candidates': _timelineSafeShortsCandidateMaps(shortsCandidates),
      if (selectedShortsId != null) 'selected_shorts_id': selectedShortsId,
      'include_captions': includeCaptions,
      'caption_style_preset': captionStylePreset,
      'export_aspect_ratio': exportAspectRatio,
      'selected_export_profiles': selectedExportProfiles,
      if (markIn != null) 'mark_in': snapSecondsToFrame(markIn!),
      if (markOut != null) 'mark_out': snapSecondsToFrame(markOut!),
    };
  }
}

List<String> _normalizedExportProfiles(Object? value, String fallback) {
  const supported = ['16:9', '9:16', '1:1'];
  final requested = value is List
      ? value.map((item) => item.toString()).toSet()
      : <String>{fallback};
  final normalized = [
    for (final profile in supported)
      if (requested.contains(profile)) profile,
  ];
  if (normalized.isNotEmpty) {
    return normalized;
  }
  return supported.contains(fallback) ? [fallback] : const ['16:9'];
}

List<Map<String, dynamic>> _timelineSafeShortsCandidateMaps(
  List<Map<String, dynamic>> input,
) {
  return [for (final raw in input) _timelineSafeShortsCandidateMap(raw)];
}

Map<String, dynamic> _timelineSafeShortsCandidateMap(Map<String, dynamic> raw) {
  final output = Map<String, dynamic>.from(raw);
  final rawSegments = output['segments'];
  if (rawSegments is List) {
    output['segments'] = [
      for (final item in rawSegments)
        if (item is Map)
          _timelineSafeShortsSegmentMap(Map<String, dynamic>.from(item))
        else
          item,
    ];
  }
  return output;
}

Map<String, dynamic> _timelineSafeShortsSegmentMap(Map<String, dynamic> raw) {
  try {
    return HighlightSegment.fromJson(raw).toJson();
  } catch (_) {
    return raw;
  }
}

double? _optionalTimelineSecondsFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  return snapSecondsToFrame(_doubleFromJson(value, 0));
}
