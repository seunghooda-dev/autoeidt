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

class JobStatusResponse {
  const JobStatusResponse({
    required this.jobId,
    required this.status,
    required this.stage,
    required this.progress,
    required this.message,
    this.duration,
    this.originalFilename,
    this.renderUrl,
    this.error,
    this.styleProfile,
    this.segments = const [],
  });

  final String jobId;
  final String status;
  final String stage;
  final int progress;
  final String message;
  final double? duration;
  final String? originalFilename;
  final String? renderUrl;
  final String? error;
  final StyleProfile? styleProfile;
  final List<HighlightSegment> segments;

  factory JobStatusResponse.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'] as List<dynamic>? ?? const [];
    return JobStatusResponse(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
      stage: json['stage'] as String,
      progress: (json['progress'] as num).toInt(),
      message: json['message'] as String? ?? '',
      duration: (json['duration'] as num?)?.toDouble(),
      originalFilename: json['original_filename'] as String?,
      renderUrl: json['render_url'] as String?,
      error: json['error'] as String?,
      styleProfile: json['style_profile'] == null
          ? null
          : StyleProfile.fromJson(
              json['style_profile'] as Map<String, dynamic>,
            ),
      segments: rawSegments
          .map(
            (item) => HighlightSegment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
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
