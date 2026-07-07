import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_editor_app/utils/timecode.dart';

void main() {
  test('formats 29.97 drop-frame timecode from exact frame numbers', () {
    expect(formatFrameAsDropFrameTimecode(0), '00:00:00;00');
    expect(formatFrameAsDropFrameTimecode(1799), '00:00:59;29');
    expect(formatFrameAsDropFrameTimecode(1800), '00:01:00;02');
    expect(formatFrameAsDropFrameTimecode(17982), '00:10:00;00');
  });

  test('snaps seconds to a 29.97 frame boundary', () {
    final snapped = snapSecondsToFrame(1);
    expect(secondsToTimecodeFrame(snapped), 30);
    expect(formatSeconds(snapped), '00:00:01;00');
  });
}
