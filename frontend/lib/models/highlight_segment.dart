import '../utils/timecode.dart';

double _jsonTimelineSeconds(Object? value) {
  if (value is num) {
    return snapSecondsToFrame(value.toDouble());
  }
  if (value is String) {
    return snapSecondsToFrame(double.tryParse(value) ?? 0);
  }
  return 0;
}

double? _jsonOptionalTimelineSeconds(Object? value) {
  if (value == null) {
    return null;
  }
  return _jsonTimelineSeconds(value);
}

class ReframeKeyframe {
  const ReframeKeyframe({required this.time, required this.x, required this.y});

  final double time;
  final double x;
  final double y;

  factory ReframeKeyframe.fromJson(Map<String, dynamic> json) {
    return ReframeKeyframe(
      time: (json['time'] as num?)?.toDouble() ?? 0,
      x: (json['x'] as num?)?.toDouble() ?? 0.5,
      y: (json['y'] as num?)?.toDouble() ?? 0.42,
    );
  }

  Map<String, dynamic> toJson() => {'time': time, 'x': x, 'y': y};
}

class HighlightSegment {
  const HighlightSegment({
    required this.order,
    required this.start,
    required this.end,
    required this.reason,
    this.script = '',
    this.source = 'ai',
    this.videoEnabled = true,
    this.videoFadeIn = 0.0,
    this.videoFadeOut = 0.0,
    this.colorBrightness = 0.0,
    this.colorContrast = 1.0,
    this.colorSaturation = 1.0,
    this.focusX = 0.5,
    this.focusY = 0.42,
    this.focusConfidence = 0.0,
    this.focusKeyframes = const [],
    this.topicId = 0,
    this.audioStart,
    this.audioEnd,
    this.audioMuted = false,
    this.audioVolume = 1.0,
    this.audioPan = 0.0,
    this.audioNormalize = false,
    this.audioLoudnessTarget = -14.0,
    this.audioLinked = true,
    this.audioChannel1Enabled = true,
    this.audioChannel2Enabled = true,
    this.audioSourceChannelLeft = 1,
    this.audioSourceChannelRight = 2,
    this.playbackSpeed = 1.0,
    this.audioFadeIn = 0.0,
    this.audioFadeOut = 0.0,
    this.score = 0.0,
    this.tags = const [],
  });

  final int order;
  final double start;
  final double end;
  final String reason;
  final String script;
  final String source;
  final bool videoEnabled;
  final double videoFadeIn;
  final double videoFadeOut;
  final double colorBrightness;
  final double colorContrast;
  final double colorSaturation;
  final double focusX;
  final double focusY;
  final double focusConfidence;
  final List<ReframeKeyframe> focusKeyframes;
  final int topicId;
  final double? audioStart;
  final double? audioEnd;
  final bool audioMuted;
  final double audioVolume;
  final double audioPan;
  final bool audioNormalize;
  final double audioLoudnessTarget;
  final bool audioLinked;
  final bool audioChannel1Enabled;
  final bool audioChannel2Enabled;
  final int audioSourceChannelLeft;
  final int audioSourceChannelRight;
  final double playbackSpeed;
  final double audioFadeIn;
  final double audioFadeOut;
  final double score;
  final List<String> tags;

  double get duration => end - start;
  double get outputDuration => duration / playbackSpeed;
  double get effectiveAudioStart => audioStart ?? start;
  double get effectiveAudioEnd => audioEnd ?? end;
  double get audioDuration => effectiveAudioEnd - effectiveAudioStart;
  bool get hasActiveAudioChannel =>
      audioChannel1Enabled || audioChannel2Enabled;

  HighlightSegment copyWith({
    int? order,
    double? start,
    double? end,
    String? reason,
    String? script,
    String? source,
    bool? videoEnabled,
    double? videoFadeIn,
    double? videoFadeOut,
    double? colorBrightness,
    double? colorContrast,
    double? colorSaturation,
    double? focusX,
    double? focusY,
    double? focusConfidence,
    List<ReframeKeyframe>? focusKeyframes,
    int? topicId,
    double? audioStart,
    double? audioEnd,
    bool? audioMuted,
    double? audioVolume,
    double? audioPan,
    bool? audioNormalize,
    double? audioLoudnessTarget,
    bool? audioLinked,
    bool? audioChannel1Enabled,
    bool? audioChannel2Enabled,
    int? audioSourceChannelLeft,
    int? audioSourceChannelRight,
    double? playbackSpeed,
    double? audioFadeIn,
    double? audioFadeOut,
    double? score,
    List<String>? tags,
  }) {
    return HighlightSegment(
      order: order ?? this.order,
      start: start ?? this.start,
      end: end ?? this.end,
      reason: reason ?? this.reason,
      script: script ?? this.script,
      source: source ?? this.source,
      videoEnabled: videoEnabled ?? this.videoEnabled,
      videoFadeIn: videoFadeIn ?? this.videoFadeIn,
      videoFadeOut: videoFadeOut ?? this.videoFadeOut,
      colorBrightness: colorBrightness ?? this.colorBrightness,
      colorContrast: colorContrast ?? this.colorContrast,
      colorSaturation: colorSaturation ?? this.colorSaturation,
      focusX: focusX ?? this.focusX,
      focusY: focusY ?? this.focusY,
      focusConfidence: focusConfidence ?? this.focusConfidence,
      focusKeyframes: focusKeyframes ?? this.focusKeyframes,
      topicId: topicId ?? this.topicId,
      audioStart: audioStart ?? this.audioStart,
      audioEnd: audioEnd ?? this.audioEnd,
      audioMuted: audioMuted ?? this.audioMuted,
      audioVolume: audioVolume ?? this.audioVolume,
      audioPan: audioPan ?? this.audioPan,
      audioNormalize: audioNormalize ?? this.audioNormalize,
      audioLoudnessTarget: audioLoudnessTarget ?? this.audioLoudnessTarget,
      audioLinked: audioLinked ?? this.audioLinked,
      audioChannel1Enabled: audioChannel1Enabled ?? this.audioChannel1Enabled,
      audioChannel2Enabled: audioChannel2Enabled ?? this.audioChannel2Enabled,
      audioSourceChannelLeft:
          audioSourceChannelLeft ?? this.audioSourceChannelLeft,
      audioSourceChannelRight:
          audioSourceChannelRight ?? this.audioSourceChannelRight,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      audioFadeIn: audioFadeIn ?? this.audioFadeIn,
      audioFadeOut: audioFadeOut ?? this.audioFadeOut,
      score: score ?? this.score,
      tags: tags ?? this.tags,
    );
  }

  factory HighlightSegment.fromJson(Map<String, dynamic> json) {
    return HighlightSegment(
      order: (json['order'] as num?)?.toInt() ?? 0,
      start: _jsonTimelineSeconds(json['start']),
      end: _jsonTimelineSeconds(json['end']),
      reason: json['reason'] as String? ?? '',
      script: json['script'] as String? ?? '',
      source: json['source'] as String? ?? 'ai',
      videoEnabled:
          (json['video_enabled'] as bool?) ??
          (json['videoEnabled'] as bool?) ??
          true,
      videoFadeIn:
          (json['video_fade_in'] as num?)?.toDouble() ??
          (json['videoFadeIn'] as num?)?.toDouble() ??
          0.0,
      videoFadeOut:
          (json['video_fade_out'] as num?)?.toDouble() ??
          (json['videoFadeOut'] as num?)?.toDouble() ??
          0.0,
      colorBrightness:
          (json['color_brightness'] as num?)?.toDouble() ??
          (json['colorBrightness'] as num?)?.toDouble() ??
          0.0,
      colorContrast:
          (json['color_contrast'] as num?)?.toDouble() ??
          (json['colorContrast'] as num?)?.toDouble() ??
          1.0,
      colorSaturation:
          (json['color_saturation'] as num?)?.toDouble() ??
          (json['colorSaturation'] as num?)?.toDouble() ??
          1.0,
      focusX:
          (json['focus_x'] as num?)?.toDouble() ??
          (json['focusX'] as num?)?.toDouble() ??
          0.5,
      focusY:
          (json['focus_y'] as num?)?.toDouble() ??
          (json['focusY'] as num?)?.toDouble() ??
          0.42,
      focusConfidence:
          (json['focus_confidence'] as num?)?.toDouble() ??
          (json['focusConfidence'] as num?)?.toDouble() ??
          0.0,
      focusKeyframes: (json['focus_keyframes'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReframeKeyframe.fromJson)
          .toList(),
      topicId:
          (json['topic_id'] as num?)?.toInt() ??
          (json['topicId'] as num?)?.toInt() ??
          0,
      audioStart:
          _jsonOptionalTimelineSeconds(json['audio_start']) ??
          _jsonOptionalTimelineSeconds(json['audioStart']),
      audioEnd:
          _jsonOptionalTimelineSeconds(json['audio_end']) ??
          _jsonOptionalTimelineSeconds(json['audioEnd']),
      audioMuted:
          (json['audio_muted'] as bool?) ??
          (json['audioMuted'] as bool?) ??
          false,
      audioVolume:
          (json['audio_volume'] as num?)?.toDouble() ??
          (json['audioVolume'] as num?)?.toDouble() ??
          1.0,
      audioPan:
          (json['audio_pan'] as num?)?.toDouble() ??
          (json['audioPan'] as num?)?.toDouble() ??
          0.0,
      audioNormalize:
          (json['audio_normalize'] as bool?) ??
          (json['audioNormalize'] as bool?) ??
          false,
      audioLoudnessTarget:
          ((json['audio_loudness_target'] as num?)?.toDouble() ??
                  (json['audioLoudnessTarget'] as num?)?.toDouble() ??
                  -14.0)
              .clamp(-24.0, -12.0)
              .toDouble(),
      audioLinked:
          (json['audio_linked'] as bool?) ??
          (json['audioLinked'] as bool?) ??
          true,
      audioChannel1Enabled:
          (json['audio_channel_1_enabled'] as bool?) ??
          (json['audioChannel1Enabled'] as bool?) ??
          true,
      audioChannel2Enabled:
          (json['audio_channel_2_enabled'] as bool?) ??
          (json['audioChannel2Enabled'] as bool?) ??
          true,
      audioSourceChannelLeft:
          ((json['audio_source_channel_left'] as num?)?.toInt() ??
                  (json['audioSourceChannelLeft'] as num?)?.toInt() ??
                  1)
              .clamp(1, 64),
      audioSourceChannelRight:
          ((json['audio_source_channel_right'] as num?)?.toInt() ??
                  (json['audioSourceChannelRight'] as num?)?.toInt() ??
                  2)
              .clamp(1, 64),
      playbackSpeed:
          (json['playback_speed'] as num?)?.toDouble() ??
          (json['playbackSpeed'] as num?)?.toDouble() ??
          1.0,
      audioFadeIn:
          (json['audio_fade_in'] as num?)?.toDouble() ??
          (json['audioFadeIn'] as num?)?.toDouble() ??
          0.0,
      audioFadeOut:
          (json['audio_fade_out'] as num?)?.toDouble() ??
          (json['audioFadeOut'] as num?)?.toDouble() ??
          0.0,
      score:
          (json['score'] as num?)?.toDouble() ??
          (json['highlightScore'] as num?)?.toDouble() ??
          0.0,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order': order,
      'start': snapSecondsToFrame(start),
      'end': snapSecondsToFrame(end),
      'reason': reason,
      'script': script,
      'source': source,
      'video_enabled': videoEnabled,
      'video_fade_in': videoFadeIn,
      'video_fade_out': videoFadeOut,
      'color_brightness': colorBrightness,
      'color_contrast': colorContrast,
      'color_saturation': colorSaturation,
      'focus_x': focusX,
      'focus_y': focusY,
      'focus_confidence': focusConfidence,
      'focus_keyframes': focusKeyframes
          .map((keyframe) => keyframe.toJson())
          .toList(),
      'topic_id': topicId,
      'audio_start': snapSecondsToFrame(effectiveAudioStart),
      'audio_end': snapSecondsToFrame(effectiveAudioEnd),
      'audio_muted': audioMuted,
      'audio_volume': audioVolume,
      'audio_pan': audioPan,
      'audio_normalize': audioNormalize,
      'audio_loudness_target': audioLoudnessTarget,
      'audio_linked': audioLinked,
      'audio_channel_1_enabled': audioChannel1Enabled,
      'audio_channel_2_enabled': audioChannel2Enabled,
      'audio_source_channel_left': audioSourceChannelLeft,
      'audio_source_channel_right': audioSourceChannelRight,
      'playback_speed': playbackSpeed,
      'audio_fade_in': audioFadeIn,
      'audio_fade_out': audioFadeOut,
      'score': score,
      'tags': tags,
    };
  }
}

class TranscriptSegment {
  const TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  final double start;
  final double end;
  final String text;

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      start: _jsonTimelineSeconds(json['start']),
      end: _jsonTimelineSeconds(json['end']),
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start': snapSecondsToFrame(start),
      'end': snapSecondsToFrame(end),
      'text': text,
    };
  }
}

class CaptionSegment {
  const CaptionSegment({
    required this.order,
    required this.start,
    required this.end,
    required this.text,
    this.enabled = true,
  });

  final int order;
  final double start;
  final double end;
  final String text;
  final bool enabled;

  CaptionSegment copyWith({
    int? order,
    double? start,
    double? end,
    String? text,
    bool? enabled,
  }) {
    return CaptionSegment(
      order: order ?? this.order,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
      enabled: enabled ?? this.enabled,
    );
  }

  factory CaptionSegment.fromJson(Map<String, dynamic> json) {
    return CaptionSegment(
      order: (json['order'] as num?)?.toInt() ?? 0,
      start: _jsonTimelineSeconds(json['start']),
      end: _jsonTimelineSeconds(json['end']),
      text: json['text'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order': order,
      'start': snapSecondsToFrame(start),
      'end': snapSecondsToFrame(end),
      'text': text,
      'enabled': enabled,
    };
  }
}
