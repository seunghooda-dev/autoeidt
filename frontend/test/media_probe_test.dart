import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/job_models.dart';

void main() {
  test('media probe parses MXF broadcast preflight response', () {
    final probe = MediaProbeInfo.fromJson({
      'path': 'C:/media/news_source.mxf',
      'filename': 'news_source.mxf',
      'container': 'mxf',
      'format_long_name': 'MXF (Material eXchange Format)',
      'duration': 3600.0,
      'bit_rate': 50000000,
      'video_codec': 'mpeg2video',
      'video_codec_long_name': 'MPEG-2 video',
      'width': 1920,
      'height': 1080,
      'frame_rate': 29.97,
      'timecode': '01:00:00;00',
      'audio_stream_count': 8,
      'audio_summary': 'A1 pcm_s24le mono, A2 pcm_s24le mono, +4 more',
      'is_mxf': true,
      'mxf_operational_pattern': 'OP1a-like single-file MXF',
      'can_analyze': true,
      'warnings': ['방송 MXF 다중 오디오 스트림입니다.'],
    });

    expect(probe.isMxf, isTrue);
    expect(probe.canAnalyze, isTrue);
    expect(probe.resolutionLabel, '1920x1080');
    expect(probe.frameRate, 29.97);
    expect(probe.audioStreamCount, 8);
    expect(probe.warnings.single, contains('다중 오디오'));
  });
}
