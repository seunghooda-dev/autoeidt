class HighlightSegment {
  const HighlightSegment({
    required this.order,
    required this.start,
    required this.end,
    required this.reason,
    this.script = '',
    this.source = 'ai',
    this.audioStart,
    this.audioEnd,
    this.audioMuted = false,
    this.audioVolume = 1.0,
    this.audioLinked = true,
    this.playbackSpeed = 1.0,
    this.audioFadeIn = 0.0,
    this.audioFadeOut = 0.0,
  });

  final int order;
  final double start;
  final double end;
  final String reason;
  final String script;
  final String source;
  final double? audioStart;
  final double? audioEnd;
  final bool audioMuted;
  final double audioVolume;
  final bool audioLinked;
  final double playbackSpeed;
  final double audioFadeIn;
  final double audioFadeOut;

  double get duration => end - start;
  double get outputDuration => duration / playbackSpeed;
  double get effectiveAudioStart => audioStart ?? start;
  double get effectiveAudioEnd => audioEnd ?? end;
  double get audioDuration => effectiveAudioEnd - effectiveAudioStart;

  HighlightSegment copyWith({
    int? order,
    double? start,
    double? end,
    String? reason,
    String? script,
    String? source,
    double? audioStart,
    double? audioEnd,
    bool? audioMuted,
    double? audioVolume,
    bool? audioLinked,
    double? playbackSpeed,
    double? audioFadeIn,
    double? audioFadeOut,
  }) {
    return HighlightSegment(
      order: order ?? this.order,
      start: start ?? this.start,
      end: end ?? this.end,
      reason: reason ?? this.reason,
      script: script ?? this.script,
      source: source ?? this.source,
      audioStart: audioStart ?? this.audioStart,
      audioEnd: audioEnd ?? this.audioEnd,
      audioMuted: audioMuted ?? this.audioMuted,
      audioVolume: audioVolume ?? this.audioVolume,
      audioLinked: audioLinked ?? this.audioLinked,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      audioFadeIn: audioFadeIn ?? this.audioFadeIn,
      audioFadeOut: audioFadeOut ?? this.audioFadeOut,
    );
  }

  factory HighlightSegment.fromJson(Map<String, dynamic> json) {
    return HighlightSegment(
      order: (json['order'] as num?)?.toInt() ?? 0,
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      reason: json['reason'] as String? ?? '',
      script: json['script'] as String? ?? '',
      source: json['source'] as String? ?? 'ai',
      audioStart:
          (json['audio_start'] as num?)?.toDouble() ??
          (json['audioStart'] as num?)?.toDouble(),
      audioEnd:
          (json['audio_end'] as num?)?.toDouble() ??
          (json['audioEnd'] as num?)?.toDouble(),
      audioMuted:
          (json['audio_muted'] as bool?) ??
          (json['audioMuted'] as bool?) ??
          false,
      audioVolume:
          (json['audio_volume'] as num?)?.toDouble() ??
          (json['audioVolume'] as num?)?.toDouble() ??
          1.0,
      audioLinked:
          (json['audio_linked'] as bool?) ??
          (json['audioLinked'] as bool?) ??
          true,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order': order,
      'start': start,
      'end': end,
      'reason': reason,
      'script': script,
      'source': source,
      'audio_start': effectiveAudioStart,
      'audio_end': effectiveAudioEnd,
      'audio_muted': audioMuted,
      'audio_volume': audioVolume,
      'audio_linked': audioLinked,
      'playback_speed': playbackSpeed,
      'audio_fade_in': audioFadeIn,
      'audio_fade_out': audioFadeOut,
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
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      text: json['text'] as String? ?? '',
    );
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
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      text: json['text'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order': order,
      'start': start,
      'end': end,
      'text': text,
      'enabled': enabled,
    };
  }
}
