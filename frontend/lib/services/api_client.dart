import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import '../models/highlight_segment.dart';
import '../models/job_models.dart';

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
