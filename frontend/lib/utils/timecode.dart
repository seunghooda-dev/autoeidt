const double timecodeFrameRate = 30;
const double timecodeFrameDurationSeconds = 1 / timecodeFrameRate;
const int timecodeFramesPerSecond = 30;
const int timecodeFramesPer24Hours = timecodeFramesPerSecond * 60 * 60 * 24;
final RegExp _timecodePattern = RegExp(
  r'^(\d{1,3}):(\d{2}):(\d{2})([:;.])(\d{2})$',
);

int secondsToTimecodeFrame(double seconds) {
  if (!seconds.isFinite || seconds <= 0) {
    return 0;
  }
  return (seconds * timecodeFrameRate).round();
}

double timecodeFrameToSeconds(int frame) {
  if (frame <= 0) {
    return 0;
  }
  return frame / timecodeFrameRate;
}

double snapSecondsToFrame(double seconds) {
  return timecodeFrameToSeconds(secondsToTimecodeFrame(seconds));
}

String formatFrameAsTimecode(int frame) {
  var frameNumber = frame < 0 ? 0 : frame;
  frameNumber %= timecodeFramesPer24Hours;

  final frames = frameNumber % timecodeFramesPerSecond;
  final totalSeconds = frameNumber ~/ timecodeFramesPerSecond;
  final seconds = totalSeconds % 60;
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;

  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}:'
      '${frames.toString().padLeft(2, '0')}';
}

String formatSeconds(double seconds) {
  return formatFrameAsTimecode(secondsToTimecodeFrame(seconds));
}

String? normalizeTimecodeText(String? timecode) {
  if (timecode == null) {
    return null;
  }
  final value = timecode.trim();
  if (value.isEmpty) {
    return null;
  }

  final match = _timecodePattern.firstMatch(value);
  if (match == null) {
    return value.replaceAll(';', ':').replaceAll('.', ':');
  }

  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!).clamp(0, 59);
  final seconds = int.parse(match.group(3)!).clamp(0, 59);
  final frames = int.parse(
    match.group(5)!,
  ).clamp(0, timecodeFramesPerSecond - 1);
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}:'
      '${frames.toString().padLeft(2, '0')}';
}
