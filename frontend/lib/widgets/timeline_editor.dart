import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/highlight_segment.dart';
import 'time_format.dart';

enum _DragEdge { start, end }

enum _DragTrack { video, audio }

class TimelineEditor extends StatefulWidget {
  const TimelineEditor({
    super.key,
    required this.duration,
    required this.segments,
    required this.playheadSeconds,
    required this.selectedSegmentOrder,
    required this.markIn,
    required this.markOut,
    required this.waveform,
    required this.zoom,
    required this.onSegmentChanged,
    required this.onScrub,
    required this.onSegmentSelected,
  });

  final double duration;
  final List<HighlightSegment> segments;
  final double playheadSeconds;
  final int? selectedSegmentOrder;
  final double? markIn;
  final double? markOut;
  final List<double> waveform;
  final double zoom;
  final ValueChanged<HighlightSegment> onSegmentChanged;
  final ValueChanged<double> onScrub;
  final ValueChanged<int> onSegmentSelected;

  @override
  State<TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineEditorState extends State<TimelineEditor> {
  static const double _handleHitWidth = 16;
  static const double _minSegmentSeconds = 1.0;
  static const double _videoTop = 42;
  static const double _audioTop = 88;
  static const double _laneHeight = 30;

  int? _activeIndex;
  _DragEdge? _activeEdge;
  _DragTrack? _activeTrack;
  bool _isScrubbing = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * widget.zoom;
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: widget.zoom > 1.0,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _tap(details.localPosition, width),
              onPanStart: (details) => _startDrag(details.localPosition, width),
              onPanUpdate: (details) =>
                  _updateDrag(details.localPosition.dx, width),
              onPanEnd: (_) => _finishDrag(),
              onPanCancel: _finishDrag,
              child: SizedBox(
                width: width,
                height: 168,
                child: CustomPaint(
                  painter: _TimelinePainter(
                    duration: widget.duration,
                    segments: widget.segments,
                    playheadSeconds: widget.playheadSeconds,
                    selectedSegmentOrder: widget.selectedSegmentOrder,
                    markIn: widget.markIn,
                    markOut: widget.markOut,
                    waveform: widget.waveform,
                    activeIndex: _activeIndex,
                    activeEdge: _activeEdge,
                    activeTrack: _activeTrack,
                    colorScheme: Theme.of(context).colorScheme,
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 140),
                      child: SizedBox(
                        width: width,
                        child: Text(
                          '원본 ${formatSeconds(widget.duration)}  |  출력 ${formatSeconds(_totalOutputSeconds())}  |  V1/A1 분리 ${_detachedAudioCount()}개',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _tap(Offset position, double width) {
    final track = _trackAt(position.dy);
    final hitIndex = _segmentIndexAt(position.dx, width, track);
    if (hitIndex != null) {
      widget.onSegmentSelected(widget.segments[hitIndex].order);
    }
    widget.onScrub(_snapToFrame(_xToSeconds(position.dx, width)));
  }

  void _startDrag(Offset position, double width) {
    final track = _trackAt(position.dy);
    if (track == null) {
      _beginScrub(position.dx, width);
      return;
    }

    var closestDistance = double.infinity;
    int? closestIndex;
    _DragEdge? closestEdge;

    for (var index = 0; index < widget.segments.length; index++) {
      final segment = widget.segments[index];
      final startSeconds = track == _DragTrack.video
          ? segment.start
          : segment.effectiveAudioStart;
      final endSeconds = track == _DragTrack.video
          ? segment.end
          : segment.effectiveAudioEnd;
      final startX = _secondsToX(startSeconds, width);
      final endX = _secondsToX(endSeconds, width);
      final startDistance = (position.dx - startX).abs();
      final endDistance = (position.dx - endX).abs();

      if (startDistance < closestDistance) {
        closestDistance = startDistance;
        closestIndex = index;
        closestEdge = _DragEdge.start;
      }
      if (endDistance < closestDistance) {
        closestDistance = endDistance;
        closestIndex = index;
        closestEdge = _DragEdge.end;
      }
    }

    if (closestDistance <= _handleHitWidth) {
      setState(() {
        _activeIndex = closestIndex;
        _activeEdge = closestEdge;
        _activeTrack = track;
        _isScrubbing = false;
      });
      if (closestIndex != null) {
        widget.onSegmentSelected(widget.segments[closestIndex].order);
      }
      return;
    }

    final hitIndex = _segmentIndexAt(position.dx, width, track);
    if (hitIndex != null) {
      widget.onSegmentSelected(widget.segments[hitIndex].order);
    }
    _beginScrub(position.dx, width);
  }

  void _beginScrub(double x, double width) {
    setState(() {
      _activeIndex = null;
      _activeEdge = null;
      _activeTrack = null;
      _isScrubbing = true;
    });
    widget.onScrub(_snapToFrame(_xToSeconds(x, width)));
  }

  void _updateDrag(double x, double width) {
    if (_isScrubbing) {
      widget.onScrub(_snapToFrame(_xToSeconds(x, width)));
      return;
    }

    final index = _activeIndex;
    final edge = _activeEdge;
    final track = _activeTrack;
    if (index == null || edge == null || track == null) {
      return;
    }

    final current = widget.segments[index];
    final seconds = _snapToFrame(_xToSeconds(x, width));

    HighlightSegment updated;
    if (track == _DragTrack.video) {
      if (edge == _DragEdge.start) {
        final maxStart = math.max(0.0, current.end - _minSegmentSeconds);
        final start = seconds.clamp(0.0, maxStart).toDouble();
        updated = current.copyWith(start: start);
      } else {
        final minEnd = math.min(
          widget.duration,
          current.start + _minSegmentSeconds,
        );
        final end = seconds.clamp(minEnd, widget.duration).toDouble();
        updated = current.copyWith(end: end);
      }
    } else {
      if (edge == _DragEdge.start) {
        final maxStart = math.max(
          0.0,
          current.effectiveAudioEnd - _minSegmentSeconds,
        );
        final start = seconds.clamp(0.0, maxStart).toDouble();
        updated = current.copyWith(audioStart: start, audioLinked: false);
      } else {
        final minEnd = math.min(
          widget.duration,
          current.effectiveAudioStart + _minSegmentSeconds,
        );
        final end = seconds.clamp(minEnd, widget.duration).toDouble();
        updated = current.copyWith(audioEnd: end, audioLinked: false);
      }
    }
    widget.onSegmentChanged(updated);
  }

  void _finishDrag() {
    setState(() {
      _activeIndex = null;
      _activeEdge = null;
      _activeTrack = null;
      _isScrubbing = false;
    });
  }

  _DragTrack? _trackAt(double y) {
    if (y >= _videoTop - 10 && y <= _videoTop + _laneHeight + 10) {
      return _DragTrack.video;
    }
    if (y >= _audioTop - 10 && y <= _audioTop + _laneHeight + 10) {
      return _DragTrack.audio;
    }
    return null;
  }

  int? _segmentIndexAt(double x, double width, _DragTrack? track) {
    if (track == null) {
      return null;
    }
    for (var index = widget.segments.length - 1; index >= 0; index--) {
      final segment = widget.segments[index];
      final start = track == _DragTrack.video
          ? segment.start
          : segment.effectiveAudioStart;
      final end = track == _DragTrack.video
          ? segment.end
          : segment.effectiveAudioEnd;
      final left = _secondsToX(start, width);
      final right = _secondsToX(end, width);
      if (x >= left && x <= right) {
        return index;
      }
    }
    return null;
  }

  double _totalOutputSeconds() {
    return widget.segments.fold<double>(
      0,
      (total, segment) => total + math.max(0, segment.outputDuration),
    );
  }

  int _detachedAudioCount() {
    return widget.segments.where((segment) => !segment.audioLinked).length;
  }

  double _secondsToX(double seconds, double width) {
    if (widget.duration <= 0 || width <= 0) {
      return 0;
    }
    return (seconds / widget.duration).clamp(0.0, 1.0) * width;
  }

  double _xToSeconds(double x, double width) {
    if (widget.duration <= 0 || width <= 0) {
      return 0;
    }
    return (x / width).clamp(0.0, 1.0) * widget.duration;
  }

  double _snapToFrame(double value) => snapSecondsToFrame(value);
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.duration,
    required this.segments,
    required this.playheadSeconds,
    required this.selectedSegmentOrder,
    required this.markIn,
    required this.markOut,
    required this.waveform,
    required this.activeIndex,
    required this.activeEdge,
    required this.activeTrack,
    required this.colorScheme,
  });

  static const double _videoTop = _TimelineEditorState._videoTop;
  static const double _audioTop = _TimelineEditorState._audioTop;
  static const double _laneHeight = _TimelineEditorState._laneHeight;

  final double duration;
  final List<HighlightSegment> segments;
  final double playheadSeconds;
  final int? selectedSegmentOrder;
  final double? markIn;
  final double? markOut;
  final List<double> waveform;
  final int? activeIndex;
  final _DragEdge? activeEdge;
  final _DragTrack? activeTrack;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(6);
    final trackPaint = Paint()..color = colorScheme.surfaceContainerHighest;
    _drawTrack(canvas, size, _videoTop, radius, trackPaint);
    _drawTrack(canvas, size, _audioTop, radius, trackPaint);
    _drawLaneLabel(canvas, 'V1', _videoTop, colorScheme.primary);
    _drawLaneLabel(canvas, 'A1', _audioTop, colorScheme.secondary);

    _drawWaveform(canvas, size);
    _drawInOutRange(canvas, size);
    _drawTicks(canvas, size);
    _drawSegments(canvas, size, radius);
    _drawMarkers(canvas, size);
    _drawPlayhead(canvas, size);
  }

  void _drawTrack(
    Canvas canvas,
    Size size,
    double top,
    Radius radius,
    Paint paint,
  ) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, size.width, _laneHeight),
      radius,
    );
    canvas.drawRRect(track, paint);
  }

  void _drawLaneLabel(Canvas canvas, String label, double top, Color color) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, top + 6, 30, _laneHeight - 12),
      Radius.circular(5),
    );
    canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.92));
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(23 - textPainter.width / 2, top + 15 - textPainter.height / 2),
    );
  }

  void _drawWaveform(Canvas canvas, Size size) {
    if (waveform.isEmpty) {
      return;
    }
    final wavePaint = Paint()
      ..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.50)
      ..strokeWidth = 1;
    final step = size.width / waveform.length;
    final centerY = _audioTop + _laneHeight / 2;
    for (var index = 0; index < waveform.length; index++) {
      final x = index * step;
      final peak = waveform[index].clamp(0.0, 1.0).toDouble();
      final halfHeight = math.max(1.0, peak * _laneHeight / 2);
      canvas.drawLine(
        Offset(x, centerY - halfHeight),
        Offset(x, centerY + halfHeight),
        wavePaint,
      );
    }
  }

  void _drawInOutRange(Canvas canvas, Size size) {
    final inPoint = markIn;
    final outPoint = markOut;
    if (inPoint == null || outPoint == null || outPoint <= inPoint) {
      return;
    }
    final left = _secondsToX(inPoint, size.width);
    final right = _secondsToX(outPoint, size.width);
    final rangeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        left,
        _videoTop - 7,
        math.max(2, right - left),
        _audioTop - _videoTop + _laneHeight + 14,
      ),
      Radius.circular(6),
    );
    canvas.drawRRect(
      rangeRect,
      Paint()..color = colorScheme.tertiary.withValues(alpha: 0.18),
    );
  }

  void _drawTicks(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = colorScheme.outline
      ..strokeWidth = 1;
    const tickCount = 12;
    for (var i = 0; i <= tickCount; i++) {
      final x = size.width * i / tickCount;
      final top = i % 3 == 0 ? 26.0 : 30.0;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, _audioTop + _laneHeight + 6),
        tickPaint,
      );
    }
  }

  void _drawSegments(Canvas canvas, Size size, Radius radius) {
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final isActive =
          activeIndex == index || selectedSegmentOrder == segment.order;

      _drawClipBlock(
        canvas,
        size,
        top: _videoTop,
        start: segment.start,
        end: segment.end,
        fill: isActive ? colorScheme.tertiary : colorScheme.primary,
        border: isActive ? colorScheme.tertiary : colorScheme.onSurface,
        radius: radius,
        handlesActive: isActive && activeTrack != _DragTrack.audio,
      );

      final audioFill = segment.audioLinked
          ? colorScheme.secondary
          : colorScheme.tertiary;
      final audioBorder = segment.audioMuted
          ? colorScheme.error
          : (isActive ? colorScheme.tertiary : colorScheme.onSurface);
      _drawClipBlock(
        canvas,
        size,
        top: _audioTop,
        start: segment.effectiveAudioStart,
        end: segment.effectiveAudioEnd,
        fill: segment.audioMuted
            ? audioFill.withValues(alpha: 0.26)
            : audioFill.withValues(alpha: segment.audioLinked ? 0.84 : 0.95),
        border: audioBorder,
        radius: radius,
        handlesActive: isActive && activeTrack != _DragTrack.video,
      );
    }
  }

  void _drawClipBlock(
    Canvas canvas,
    Size size, {
    required double top,
    required double start,
    required double end,
    required Color fill,
    required Color border,
    required Radius radius,
    required bool handlesActive,
  }) {
    final left = _secondsToX(start, size.width);
    final right = _secondsToX(end, size.width);
    final rect = Rect.fromLTWH(
      left,
      top,
      math.max(2, right - left),
      _laneHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = fill,
    );

    final handlePaint = Paint()..color = colorScheme.surface;
    final handleBorder = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = handlesActive ? 1.6 : 1.1;
    for (final handleX in [left, right]) {
      final handleRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(handleX, top + _laneHeight / 2),
          width: 8,
          height: _laneHeight + 10,
        ),
        Radius.circular(4),
      );
      canvas.drawRRect(handleRect, handlePaint);
      canvas.drawRRect(handleRect, handleBorder);
    }
  }

  void _drawMarkers(Canvas canvas, Size size) {
    final inPoint = markIn;
    final outPoint = markOut;
    if (inPoint != null) {
      _drawMarker(canvas, size, inPoint, 'IN', colorScheme.primary);
    }
    if (outPoint != null) {
      _drawMarker(canvas, size, outPoint, 'OUT', colorScheme.error);
    }
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    final playheadX = _secondsToX(playheadSeconds, size.width);
    final playheadPaint = Paint()
      ..color = colorScheme.onSurface
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playheadX, 4),
      Offset(playheadX, _audioTop + _laneHeight + 12),
      playheadPaint,
    );
    final triangle = Path()
      ..moveTo(playheadX, 4)
      ..lineTo(playheadX - 6, 14)
      ..lineTo(playheadX + 6, 14)
      ..close();
    canvas.drawPath(triangle, Paint()..color = colorScheme.onSurface);
  }

  void _drawMarker(
    Canvas canvas,
    Size size,
    double seconds,
    String label,
    Color color,
  ) {
    final x = _secondsToX(seconds, size.width);
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(x, 22),
      Offset(x, _audioTop + _laneHeight + 10),
      linePaint,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelX = (x - textPainter.width / 2)
        .clamp(0.0, size.width)
        .toDouble();
    textPainter.paint(canvas, Offset(labelX, 0));
  }

  double _secondsToX(double seconds, double width) {
    if (duration <= 0 || width <= 0) {
      return 0;
    }
    return (seconds / duration).clamp(0.0, 1.0) * width;
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return duration != oldDelegate.duration ||
        segments != oldDelegate.segments ||
        playheadSeconds != oldDelegate.playheadSeconds ||
        selectedSegmentOrder != oldDelegate.selectedSegmentOrder ||
        markIn != oldDelegate.markIn ||
        markOut != oldDelegate.markOut ||
        waveform != oldDelegate.waveform ||
        activeIndex != oldDelegate.activeIndex ||
        activeEdge != oldDelegate.activeEdge ||
        activeTrack != oldDelegate.activeTrack ||
        colorScheme != oldDelegate.colorScheme;
  }
}
