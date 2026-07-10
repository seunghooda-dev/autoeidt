import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import '../models/highlight_segment.dart';
import '../models/job_models.dart';

class LocalPreviewInfo {
  const LocalPreviewInfo({
    required this.url,
    required this.sourceStart,
    required this.duration,
    this.localPath,
  });

  final String url;
  final double sourceStart;
  final double duration;
  final String? localPath;

  double get sourceEnd => sourceStart + duration;
}

class LocalThumbnailInfo {
  const LocalThumbnailInfo({
    required this.url,
    required this.sourceTime,
    required this.width,
    this.localPath,
    this.cached = false,
  });

  final String url;
  final String? localPath;
  final double sourceTime;
  final int width;
  final bool cached;
}

class ApiClient {
  ApiClient({String? baseUrl, Dio? dio})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://localhost:8000',
          ),
      _dio = dio ?? Dio();

  final String baseUrl;
  final Dio _dio;

  String absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '$baseUrl$path';
  }

  Future<UploadJobResponse> uploadVideo(
    PlatformFile file, {
    required ProgressCallback onSendProgress,
    String? styleId,
  }) async {
    final multipartFile = await _multipartFromPlatformFile(file);
    final formData = FormData.fromMap({
      'file': multipartFile,
      if (styleId != null && styleId.isNotEmpty) 'style_id': styleId,
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/upload',
      data: formData,
      onSendProgress: onSendProgress,
      options: Options(contentType: 'multipart/form-data'),
    );
    return UploadJobResponse.fromJson(response.data!);
  }

  Future<UploadJobResponse> importLocalVideo({
    required String path,
    required String displayName,
    String? styleId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/import-local',
      data: {
        'path': path,
        'display_name': displayName,
        if (styleId != null && styleId.isNotEmpty) 'style_id': styleId,
      },
    );
    return UploadJobResponse.fromJson(response.data!);
  }

  Future<MediaProbeInfo> probeLocalMedia(String path) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/probe-local',
      data: {'path': path},
    );
    return MediaProbeInfo.fromJson(response.data!);
  }

  Future<LocalPreviewInfo> createLocalPreview(
    String path, {
    double startSeconds = 0,
    double? durationSeconds,
  }) async {
    final data = <String, Object>{'path': path, 'start_seconds': startSeconds};
    if (durationSeconds != null) {
      data['duration_seconds'] = durationSeconds;
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/preview-local',
      data: data,
    );
    final previewUrl = response.data?['preview_url'] as String? ?? '';
    if (previewUrl.isEmpty) {
      throw StateError('프리뷰 프록시 URL을 받지 못했습니다.');
    }
    return LocalPreviewInfo(
      url: absoluteUrl(previewUrl),
      sourceStart: _readDouble(response.data?['source_start']),
      duration: _readDouble(response.data?['duration']),
      localPath: response.data?['preview_path'] as String?,
    );
  }

  Future<LocalThumbnailInfo> createLocalThumbnail(
    String path, {
    required double timeSeconds,
    int width = 320,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/thumbnail-local',
      data: {'path': path, 'time_seconds': timeSeconds, 'width': width},
    );
    final thumbnailUrl = response.data?['thumbnail_url'] as String? ?? '';
    if (thumbnailUrl.isEmpty) {
      throw StateError('타임라인 썸네일 URL을 받지 못했습니다.');
    }
    return LocalThumbnailInfo(
      url: absoluteUrl(thumbnailUrl),
      localPath: response.data?['thumbnail_path'] as String?,
      sourceTime: _readDouble(response.data?['source_time']),
      width: (response.data?['width'] as num?)?.toInt() ?? width,
      cached: response.data?['cached'] as bool? ?? false,
    );
  }

  Future<StorageUsageInfo> getStorageUsage({
    String? activeJobId,
    int retentionHours = 24,
  }) async {
    final query = <String, Object>{'retention_hours': retentionHours};
    if (activeJobId != null && activeJobId.isNotEmpty) {
      query['active_job_id'] = activeJobId;
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/api/system/storage',
      queryParameters: query,
    );
    return StorageUsageInfo.fromJson(response.data!);
  }

  Future<StorageCleanupInfo> cleanupSafeStorage({
    String? activeJobId,
    int retentionHours = 24,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/system/storage/cleanup',
      data: {
        if (activeJobId != null && activeJobId.isNotEmpty)
          'active_job_id': activeJobId,
        'retention_hours': retentionHours,
      },
    );
    return StorageCleanupInfo.fromJson(response.data!);
  }

  double _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }

  Future<StyleTrainingResponse> trainStyleProfile({
    required String name,
    List<String> urls = const [],
    List<PlatformFile> files = const [],
    required ProgressCallback onSendProgress,
  }) async {
    final formData = FormData();
    formData.fields.add(MapEntry('name', name));
    for (final url in urls) {
      final trimmed = url.trim();
      if (trimmed.isNotEmpty) {
        formData.fields.add(MapEntry('urls', trimmed));
      }
    }
    for (final file in files) {
      formData.files.add(
        MapEntry('files', await _multipartFromPlatformFile(file)),
      );
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/styles/train',
      data: formData,
      onSendProgress: onSendProgress,
      options: Options(contentType: 'multipart/form-data'),
    );
    return StyleTrainingResponse.fromJson(response.data!);
  }

  Future<StyleTrainingResponse> trainLocalStyleProfile({
    required String name,
    List<String> urls = const [],
    List<String> filePaths = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/styles/train-local',
      data: {'name': name, 'urls': urls, 'file_paths': filePaths},
    );
    return StyleTrainingResponse.fromJson(response.data!);
  }

  Future<StyleProfile> getStyleProfile(String styleId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/api/styles/$styleId',
    );
    return StyleProfile.fromJson(response.data!);
  }

  Future<List<StyleProfile>> listStyleProfiles() async {
    final response = await _dio.get<List<dynamic>>('$baseUrl/api/styles');
    return (response.data ?? const [])
        .map((item) => StyleProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<JobStatusResponse> getJob(String jobId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/api/jobs/$jobId',
    );
    return JobStatusResponse.fromJson(response.data!);
  }

  Future<JobStatusResponse> cancelJob(String jobId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/$jobId/cancel',
    );
    return JobStatusResponse.fromJson(response.data!);
  }

  Future<List<RecentJobSummary>> listRecentJobs({int limit = 30}) async {
    final response = await _dio.get<List<dynamic>>(
      '$baseUrl/api/jobs',
      queryParameters: {'limit': limit},
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) => RecentJobSummary.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<TimelineResponse> getTimeline(String jobId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/api/jobs/$jobId/timeline',
    );
    return TimelineResponse.fromJson(response.data!);
  }

  Future<void> requestRender(
    String jobId,
    List<HighlightSegment> segments, {
    List<CaptionSegment> captions = const [],
    CaptionRenderStyle? captionStyle,
    String aspectRatio = '16:9',
    bool includeCaptions = false,
    String outputName = 'youtube_highlights.mp4',
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/$jobId/render',
      data: {
        'segments': segments.map((item) => item.toJson()).toList(),
        'captions': captions.map((item) => item.toJson()).toList(),
        'caption_style': (captionStyle ?? CaptionRenderStyle.preset('news'))
            .toJson(),
        'aspect_ratio': aspectRatio,
        'include_captions': includeCaptions,
        'output_name': outputName,
      },
    );
  }

  Future<void> requestBatchRender(
    String jobId,
    List<Map<String, dynamic>> items, {
    List<CaptionSegment> captions = const [],
    CaptionRenderStyle? captionStyle,
    String aspectRatio = '9:16',
    bool includeCaptions = true,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/$jobId/batch-render',
      data: {
        'items': items,
        'captions': captions.map((item) => item.toJson()).toList(),
        'caption_style': (captionStyle ?? CaptionRenderStyle.preset('shorts'))
            .toJson(),
        'aspect_ratio': aspectRatio,
        'include_captions': includeCaptions,
      },
    );
  }

  Future<ProjectState> getProject(String jobId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/api/jobs/$jobId/project',
    );
    return ProjectState.fromJson(response.data!);
  }

  Future<ProjectState> saveProject(String jobId, ProjectState project) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/$jobId/project',
      data: project.toJson(),
    );
    return ProjectState.fromJson(response.data!);
  }

  String sourceUrl(String jobId) => '$baseUrl/api/jobs/$jobId/source';

  Future<MultipartFile> _multipartFromPlatformFile(PlatformFile file) async {
    if (file.path != null) {
      return MultipartFile.fromFile(file.path!, filename: file.name);
    }
    if (file.bytes != null) {
      return MultipartFile.fromBytes(file.bytes!, filename: file.name);
    }
    if (file.readStream != null && file.size > 0) {
      return MultipartFile.fromStream(
        () => file.readStream!,
        file.size,
        filename: file.name,
      );
    }
    throw StateError('선택한 파일을 읽을 수 없습니다.');
  }
}
