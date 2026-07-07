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
  }) async {
    final multipartFile = await _multipartFromPlatformFile(file);
    final formData = FormData.fromMap({'file': multipartFile});
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/upload',
      data: formData,
      onSendProgress: onSendProgress,
      options: Options(contentType: 'multipart/form-data'),
    );
    return UploadJobResponse.fromJson(response.data!);
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
    List<HighlightSegment> segments,
  ) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/jobs/$jobId/render',
      data: {'segments': segments.map((item) => item.toJson()).toList()},
    );
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
