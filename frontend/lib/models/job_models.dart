import 'highlight_segment.dart';

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
    required this.audioStreamCount,
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
  final String? timecode;
  final int audioStreamCount;
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
      timecode: json['timecode'] as String?,
      audioStreamCount: (json['audio_stream_count'] as num?)?.toInt() ?? 0,
      audioSummary: json['audio_summary'] as String? ?? '',
      isMxf: json['is_mxf'] as bool? ?? false,
      mxfOperationalPattern: json['mxf_operational_pattern'] as String? ?? '',
      canAnalyze: json['can_analyze'] as bool? ?? false,
      warnings: rawWarnings.map((item) => item.toString()).toList(),
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
    this.error,
    this.styleProfile,
    this.analysisWarnings = const [],
    this.batchRenderItems = const [],
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
  final String? error;
  final StyleProfile? styleProfile;
  final List<String> analysisWarnings;
  final List<BatchRenderItemResult> batchRenderItems;
  final List<HighlightSegment> segments;

  factory JobStatusResponse.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'] as List<dynamic>? ?? const [];
    final rawBatchItems =
        json['batch_render_items'] as List<dynamic>? ?? const [];
    final rawWarnings = json['analysis_warnings'] as List<dynamic>? ?? const [];
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
    this.path = '',
    this.durationSeconds = 0,
    this.sizeBytes = 0,
  });

  final String label;
  final String outputName;
  final String url;
  final String path;
  final double durationSeconds;
  final int sizeBytes;

  factory BatchRenderItemResult.fromJson(Map<String, dynamic> json) {
    return BatchRenderItemResult(
      label: json['label'] as String? ?? 'Shorts',
      outputName: json['output_name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      path: json['path'] as String? ?? '',
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
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

class ProjectState {
  const ProjectState({
    required this.name,
    required this.duration,
    required this.segments,
    required this.captions,
    required this.waveform,
    this.jobId,
    this.originalFilename,
  });

  final String name;
  final String? jobId;
  final String? originalFilename;
  final double duration;
  final List<HighlightSegment> segments;
  final List<CaptionSegment> captions;
  final List<double> waveform;

  factory ProjectState.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'] as List<dynamic>? ?? const [];
    final rawCaptions = json['captions'] as List<dynamic>? ?? const [];
    final rawWaveform = json['waveform'] as List<dynamic>? ?? const [];
    return ProjectState(
      name: json['name'] as String? ?? 'AutoEdit Project',
      jobId: json['job_id'] as String?,
      originalFilename: json['original_filename'] as String?,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      segments: rawSegments
          .map(
            (item) => HighlightSegment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      captions: rawCaptions
          .map((item) => CaptionSegment.fromJson(item as Map<String, dynamic>))
          .toList(),
      waveform: rawWaveform.map((item) => (item as num).toDouble()).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (jobId != null) 'job_id': jobId,
      if (originalFilename != null) 'original_filename': originalFilename,
      'duration': duration,
      'segments': segments.map((item) => item.toJson()).toList(),
      'captions': captions.map((item) => item.toJson()).toList(),
      'waveform': waveform,
    };
  }
}
