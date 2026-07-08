import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/models/highlight_segment.dart';
import 'package:highlight_editor_app/models/job_models.dart';
import 'package:highlight_editor_app/utils/timecode.dart';

void main() {
  test('formats 30p non-drop timecode from exact frame numbers', () {
    expect(formatFrameAsTimecode(0), '00:00:00:00');
    expect(formatFrameAsTimecode(1799), '00:00:59:29');
    expect(formatFrameAsTimecode(1800), '00:01:00:00');
    expect(formatFrameAsTimecode(18000), '00:10:00:00');
  });

  test('snaps seconds to a 30p frame boundary', () {
    final snapped = snapSecondsToFrame(1);
    expect(secondsToTimecodeFrame(snapped), 30);
    expect(formatSeconds(snapped), '00:00:01:00');
  });

  test('normalizes source drop-frame labels to 30p non-drop timecode', () {
    expect(normalizeTimecodeText('01:02:03;04'), '01:02:03:04');
    expect(normalizeTimecodeText('01:61:99;35'), '01:59:59:29');
    expect(normalizeTimecodeText(''), isNull);
  });

  test('models serialize timeline seconds on a 30p non-drop grid', () {
    final segment = HighlightSegment.fromJson({
      'order': 1,
      'start': 1.001,
      'end': 2.049,
      'reason': 'frame grid',
      'audio_start': 3.016,
      'audio_end': 4.019,
    });
    final project = ProjectState.fromJson({
      'name': '30p Project',
      'duration': 60.0,
      'timeline_frame_rate': 29.97,
      'timeline_timecode_mode': 'drop',
      'segments': [segment.toJson()],
      'captions': [
        {'order': 1, 'start': 5.012, 'end': 6.049, 'text': 'caption'},
      ],
      'timeline_markers': [
        {'id': 1, 'seconds': 7.018, 'label': 'Snap'},
      ],
      'shorts_candidates': [
        {
          'id': 1,
          'label': 'Shorts 01',
          'segments': [
            {'order': 2, 'start': 8.019, 'end': 9.049, 'reason': 'shorts'},
          ],
        },
      ],
      'mark_in': 12.516,
      'mark_out': 58.019,
    });

    expect(secondsToTimecodeFrame(segment.start), 30);
    expect(secondsToTimecodeFrame(segment.end), 61);
    expect(secondsToTimecodeFrame(segment.effectiveAudioStart), 90);
    expect(secondsToTimecodeFrame(segment.effectiveAudioEnd), 121);
    expect(project.timelineFrameRate, 30.0);
    expect(project.timelineTimecodeMode, 'non_drop');
    expect(secondsToTimecodeFrame(project.markIn!), 375);
    expect(secondsToTimecodeFrame(project.markOut!), 1741);
    expect(secondsToTimecodeFrame(project.timelineMarkers.single.seconds), 211);
    expect(secondsToTimecodeFrame(project.captions.single.end), 181);

    final json = project.toJson();
    expect(json['timeline_frame_rate'], 30.0);
    expect(json['timeline_timecode_mode'], 'non_drop');
    expect(secondsToTimecodeFrame(json['mark_out'] as double), 1741);
    expect(
      secondsToTimecodeFrame(
        ((json['segments'] as List).single as Map)['end'] as double,
      ),
      61,
    );
    expect(
      secondsToTimecodeFrame(
        ((((json['shorts_candidates'] as List).single as Map)['segments']
                        as List)
                    .single
                as Map)['end']
            as double,
      ),
      271,
    );
  });
}
