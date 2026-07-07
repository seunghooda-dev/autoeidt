class HighlightSegment {
  const HighlightSegment({
    required this.order,
    required this.start,
    required this.end,
    required this.reason,
    this.script = '',
    this.source = 'ai',
  });

  final int order;
  final double start;
  final double end;
  final String reason;
  final String script;
  final String source;

  double get duration => end - start;

  HighlightSegment copyWith({
    int? order,
    double? start,
    double? end,
    String? reason,
    String? script,
    String? source,
  }) {
    return HighlightSegment(
      order: order ?? this.order,
      start: start ?? this.start,
      end: end ?? this.end,
      reason: reason ?? this.reason,
      script: script ?? this.script,
      source: source ?? this.source,
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
