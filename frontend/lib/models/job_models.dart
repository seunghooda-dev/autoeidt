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
          .map((item) => HighlightSegment.fromJson(item as Map<String, dynamic>))
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
  });

  final String jobId;
  final double duration;
  final List<HighlightSegment> segments;
  final List<TranscriptSegment> transcript;

  factory TimelineResponse.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'] as List<dynamic>? ?? const [];
    final rawTranscript = json['transcript'] as List<dynamic>? ?? const [];
    return TimelineResponse(
      jobId: json['job_id'] as String,
      duration: (json['duration'] as num).toDouble(),
      segments: rawSegments
          .map((item) => HighlightSegment.fromJson(item as Map<String, dynamic>))
          .toList(),
      transcript: rawTranscript
          .map((item) => TranscriptSegment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
