const double timecodeFrameRate = 30000 / 1001;
const double timecodeFrameDurationSeconds = 1001 / 30000;
const int dropFrameNominalFps = 30;
const int dropFrameCount = 2;
const int dropFrameFramesPerMinute = dropFrameNominalFps * 60 - dropFrameCount;
const int dropFrameFramesPer10Minutes =
    dropFrameNominalFps * 60 * 10 - dropFrameCount * 9;
const int dropFrameFramesPer24Hours = dropFrameFramesPer10Minutes * 6 * 24;

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

String formatFrameAsDropFrameTimecode(int frame) {
  var frameNumber = frame < 0 ? 0 : frame;
  frameNumber %= dropFrameFramesPer24Hours;

  final tenMinuteBlocks = frameNumber ~/ dropFrameFramesPer10Minutes;
  final remainingFrames = frameNumber % dropFrameFramesPer10Minutes;
  final droppedFramesInBlock = remainingFrames < dropFrameCount
      ? 0
      : dropFrameCount *
            ((remainingFrames - dropFrameCount) ~/ dropFrameFramesPerMinute);
  final timecodeFrameNumber =
      frameNumber + dropFrameCount * 9 * tenMinuteBlocks + droppedFramesInBlock;

  final frames = timecodeFrameNumber % dropFrameNominalFps;
  final totalSeconds = timecodeFrameNumber ~/ dropFrameNominalFps;
  final seconds = totalSeconds % 60;
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;

  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')};'
      '${frames.toString().padLeft(2, '0')}';
}

String formatSeconds(double seconds) {
  return formatFrameAsDropFrameTimecode(secondsToTimecodeFrame(seconds));
}
