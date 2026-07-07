import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/highlight_segment.dart';
import 'time_format.dart';

enum _DragEdge { start, end }

class TimelineEditor extends StatefulWidget {
  const TimelineEditor({
    super.key,
    required this.duration,
    required this.segments,
    required this.playheadSeconds,
    required this.selectedSegmentOrder,
    required this.markIn,
    required this.markOut,
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
  final ValueChanged<HighlightSegment> onSegmentChanged;
  final ValueChanged<double> onScrub;
  final ValueChanged<int> onSegmentSelected;

  @override
  State<TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineEditorState extends State<TimelineEditor> {
  static const double _handleHitWidth = 16;
  static const double _minSegmentSeconds = 1.0;

  int? _activeIndex;
  _DragEdge? _activeEdge;
  bool _isScrubbing = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              _tap(details.localPosition.dx, constraints.maxWidth),
          onPanStart: (details) =>
              _startDrag(details.localPosition.dx, constraints.maxWidth),
          onPanUpdate: (details) =>
              _updateDrag(details.localPosition.dx, constraints.maxWidth),
          onPanEnd: (_) => _finishDrag(),
          onPanCancel: _finishDrag,
          child: SizedBox(
            height: 126,
            child: CustomPaint(
              painter: _TimelinePainter(
                duration: widget.duration,
                segments: widget.segments,
                playheadSeconds: widget.playheadSeconds,
                selectedSegmentOrder: widget.selectedSegmentOrder,
                markIn: widget.markIn,
                markOut: widget.markOut,
                activeIndex: _activeIndex,
                activeEdge: _activeEdge,
                colorScheme: Theme.of(context).colorScheme,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 98),
                  child: Text(
                    '원본 ${formatSeconds(widget.duration)}  |  선택 클립 합계 ${formatSeconds(_totalOutputSeconds())}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _tap(double x, double width) {
    final hitIndex = _segmentIndexAt(x, width);
    if (hitIndex != null) {
      widget.onSegmentSelected(widget.segments[hitIndex].order);
    }
    widget.onScrub(_snapToTenth(_xToSeconds(x, width)));
  }

  void _startDrag(double x, double width) {
    var closestDistance = double.infinity;
    int? closestIndex;
    _DragEdge? closestEdge;

    for (var index = 0; index < widget.segments.length; index++) {
      final segment = widget.segments[index];
      final startX = _secondsToX(segment.start, width);
      final endX = _secondsToX(segment.end, width);
      final startDistance = (x - startX).abs();
      final endDistance = (x - endX).abs();

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
        _isScrubbing = false;
      });
      if (closestIndex != null) {
        widget.onSegmentSelected(widget.segments[closestIndex].order);
      }
      return;
    }

    final hitIndex = _segmentIndexAt(x, width);
    if (hitIndex != null) {
      widget.onSegmentSelected(widget.segments[hitIndex].order);
    }
    setState(() {
      _activeIndex = null;
      _activeEdge = null;
      _isScrubbing = true;
    });
    widget.onScrub(_snapToTenth(_xToSeconds(x, width)));
  }

  void _updateDrag(double x, double width) {
    if (_isScrubbing) {
      widget.onScrub(_snapToTenth(_xToSeconds(x, width)));
      return;
    }

    final index = _activeIndex;
    final edge = _activeEdge;
    if (index == null || edge == null) {
      return;
    }

    final current = widget.segments[index];
    final seconds = _snapToTenth(_xToSeconds(x, width));

    HighlightSegment updated;
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
    widget.onSegmentChanged(updated);
  }

  void _finishDrag() {
    setState(() {
      _activeIndex = null;
      _activeEdge = null;
      _isScrubbing = false;
    });
  }

  int? _segmentIndexAt(double x, double width) {
    for (var index = widget.segments.length - 1; index >= 0; index--) {
      final segment = widget.segments[index];
      final left = _secondsToX(segment.start, width);
      final right = _secondsToX(segment.end, width);
      if (x >= left && x <= right) {
        return index;
      }
    }
    return null;
  }

  double _totalOutputSeconds() {
    return widget.segments.fold<double>(
      0,
      (total, segment) => total + math.max(0, segment.duration),
    );
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

  double _snapToTenth(double value) => (value * 10).round() / 10;
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.duration,
    required this.segments,
    required this.playheadSeconds,
    required this.selectedSegmentOrder,
    required this.markIn,
    required this.markOut,
    required this.activeIndex,
    required this.activeEdge,
    required this.colorScheme,
  });

  final double duration;
  final List<HighlightSegment> segments;
  final double playheadSeconds;
  final int? selectedSegmentOrder;
  final double? markIn;
  final double? markOut;
  final int? activeIndex;
  final _DragEdge? activeEdge;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final barTop = 44.0;
    final barHeight = 34.0;
    final radius = Radius.circular(6);
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, barTop, size.width, barHeight),
      radius,
    );
    final trackPaint = Paint()..color = colorScheme.surfaceContainerHighest;
    canvas.drawRRect(track, trackPaint);

    final inPoint = markIn;
    final outPoint = markOut;
    if (inPoint != null && outPoint != null && outPoint > inPoint) {
      final left = _secondsToX(inPoint, size.width);
      final right = _secondsToX(outPoint, size.width);
      final rangeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left,
          barTop - 8,
          math.max(2, right - left),
          barHeight + 16,
        ),
        Radius.circular(6),
      );
      canvas.drawRRect(
        rangeRect,
        Paint()..color = colorScheme.tertiary.withValues(alpha: 0.18),
      );
    }

    final tickPaint = Paint()
      ..color = colorScheme.outline
      ..strokeWidth = 1;
    final tickCount = 12;
    for (var i = 0; i <= tickCount; i++) {
      final x = size.width * i / tickCount;
      final top = i % 3 == 0 ? barTop - 8 : barTop - 4;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, barTop + barHeight + 5),
        tickPaint,
      );
    }

    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final left = _secondsToX(segment.start, size.width);
      final right = _secondsToX(segment.end, size.width);
      final rect = Rect.fromLTWH(
        left,
        barTop,
        math.max(2, right - left),
        barHeight,
      );
      final isActive =
          activeIndex == index || selectedSegmentOrder == segment.order;
      final segmentPaint = Paint()
        ..color = isActive ? colorScheme.tertiary : colorScheme.primary;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), segmentPaint);

      final handlePaint = Paint()..color = colorScheme.surface;
      final handleBorder = Paint()
        ..color = isActive ? colorScheme.tertiary : colorScheme.onSurface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final handleX in [left, right]) {
        final handleRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(handleX, barTop + barHeight / 2),
            width: 8,
            height: barHeight + 12,
          ),
          Radius.circular(4),
        );
        canvas.drawRRect(handleRect, handlePaint);
        canvas.drawRRect(handleRect, handleBorder);
      }
    }

    if (inPoint != null) {
      _drawMarker(canvas, size, inPoint, 'IN', colorScheme.primary);
    }
    if (outPoint != null) {
      _drawMarker(canvas, size, outPoint, 'OUT', colorScheme.error);
    }

    final playheadX = _secondsToX(playheadSeconds, size.width);
    final playheadPaint = Paint()
      ..color = colorScheme.onSurface
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playheadX, 4),
      Offset(playheadX, barTop + barHeight + 12),
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
    canvas.drawLine(Offset(x, 22), Offset(x, 88), linePaint);

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
        activeIndex != oldDelegate.activeIndex ||
        activeEdge != oldDelegate.activeEdge ||
        colorScheme != oldDelegate.colorScheme;
  }
}
