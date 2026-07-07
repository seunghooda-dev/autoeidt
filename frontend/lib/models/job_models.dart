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
      segments: rawSegments
          .map(
            (item) => HighlightSegment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
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
