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
    required this.onSegmentChanged,
  });

  final double duration;
  final List<HighlightSegment> segments;
  final ValueChanged<HighlightSegment> onSegmentChanged;

  @override
  State<TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineEditorState extends State<TimelineEditor> {
  static const double _handleHitWidth = 16;
  static const double _minSegmentSeconds = 1.0;

  int? _activeIndex;
  _DragEdge? _activeEdge;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _startDrag(details.localPosition.dx, constraints.maxWidth),
          onPanUpdate: (details) => _updateDrag(details.localPosition.dx, constraints.maxWidth),
          onPanEnd: (_) => _finishDrag(),
          onPanCancel: _finishDrag,
          child: SizedBox(
            height: 96,
            child: CustomPaint(
              painter: _TimelinePainter(
                duration: widget.duration,
                segments: widget.segments,
                activeIndex: _activeIndex,
                activeEdge: _activeEdge,
                colorScheme: Theme.of(context).colorScheme,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 68),
                  child: Text(
                    '총 길이 ${formatSeconds(widget.duration)}',
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
      });
    }
  }

  void _updateDrag(double x, double width) {
    final index = _activeIndex;
    final edge = _activeEdge;
    if (index == null || edge == null) {
      return;
    }

    final current = widget.segments[index];
    final seconds = _snapToTenth(_xToSeconds(x, width));
    final previousEnd = index == 0 ? 0.0 : widget.segments[index - 1].end + 0.1;
    final nextStart = index == widget.segments.length - 1
        ? widget.duration
        : widget.segments[index + 1].start - 0.1;

    HighlightSegment updated;
    if (edge == _DragEdge.start) {
      final maxStart = math.max(previousEnd, current.end - _minSegmentSeconds);
      final start = seconds.clamp(previousEnd, maxStart).toDouble();
      updated = current.copyWith(start: start);
    } else {
      final minEnd = math.min(nextStart, current.start + _minSegmentSeconds);
      final end = seconds.clamp(minEnd, nextStart).toDouble();
      updated = current.copyWith(end: end);
    }
    widget.onSegmentChanged(updated);
  }

  void _finishDrag() {
    setState(() {
      _activeIndex = null;
      _activeEdge = null;
    });
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
    required this.activeIndex,
    required this.activeEdge,
    required this.colorScheme,
  });

  final double duration;
  final List<HighlightSegment> segments;
  final int? activeIndex;
  final _DragEdge? activeEdge;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final barTop = 22.0;
    final barHeight = 28.0;
    final radius = Radius.circular(6);
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, barTop, size.width, barHeight),
      radius,
    );
    final trackPaint = Paint()..color = const Color(0xFFE5E7EB);
    canvas.drawRRect(track, trackPaint);

    final tickPaint = Paint()
      ..color = const Color(0xFF9CA3AF)
      ..strokeWidth = 1;
    final tickCount = 12;
    for (var i = 0; i <= tickCount; i++) {
      final x = size.width * i / tickCount;
      final top = i % 3 == 0 ? barTop - 8 : barTop - 4;
      canvas.drawLine(Offset(x, top), Offset(x, barTop + barHeight + 5), tickPaint);
    }

    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final left = _secondsToX(segment.start, size.width);
      final right = _secondsToX(segment.end, size.width);
      final rect = Rect.fromLTWH(left, barTop, math.max(2, right - left), barHeight);
      final isActive = activeIndex == index;
      final segmentPaint = Paint()
        ..color = isActive ? colorScheme.tertiary : colorScheme.primary;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), segmentPaint);

      final handlePaint = Paint()..color = Colors.white;
      final handleBorder = Paint()
        ..color = isActive ? colorScheme.tertiary : const Color(0xFF111827)
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
        activeIndex != oldDelegate.activeIndex ||
        activeEdge != oldDelegate.activeEdge ||
        colorScheme != oldDelegate.colorScheme;
  }
}
