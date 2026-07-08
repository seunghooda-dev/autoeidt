import 'package:flutter_test/flutter_test.dart';
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
}
