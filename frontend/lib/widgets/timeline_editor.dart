import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/highlight_segment.dart';
import 'time_format.dart';

enum _DragEdge { start, end }

enum _DragTrack { video, audio }

enum _TimelineMenuAction {
  markIn,
  markOut,
  clearMarks,
  split,
  duplicate,
  delete,
  moveEarlier,
  moveLater,
  toggleAudioLink,
  toggleAudioMute,
  toggleVideoEnabled,
  resetAudioPan,
}

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
    required this.videoTrackLocked,
    required this.audioTrackLocked,
    required this.onSegmentChanged,
    required this.onScrub,
    required this.onSegmentSelected,
    this.onSetMarkIn,
    this.onSetMarkOut,
    this.onClearMarks,
    this.onSplitAt,
    this.onDuplicateSegment,
    this.onDeleteSegment,
    this.onMoveSegment,
    this.onToggleAudioLink,
    this.onToggleAudioMute,
    this.onToggleVideoEnabled,
    this.onResetAudioPan,
  });

  final double duration;
  final List<HighlightSegment> segments;
  final double playheadSeconds;
  final int? selectedSegmentOrder;
  final double? markIn;
  final double? markOut;
  final List<double> waveform;
  final double zoom;
  final bool videoTrackLocked;
  final bool audioTrackLocked;
  final ValueChanged<HighlightSegment> onSegmentChanged;
  final ValueChanged<double> onScrub;
  final ValueChanged<int> onSegmentSelected;
  final ValueChanged<double>? onSetMarkIn;
  final ValueChanged<double>? onSetMarkOut;
  final VoidCallback? onClearMarks;
  final ValueChanged<double>? onSplitAt;
  final VoidCallback? onDuplicateSegment;
  final VoidCallback? onDeleteSegment;
  final ValueChanged<int>? onMoveSegment;
  final VoidCallback? onToggleAudioLink;
  final VoidCallback? onToggleAudioMute;
  final VoidCallback? onToggleVideoEnabled;
  final VoidCallback? onResetAudioPan;

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
              onSecondaryTapDown: (details) => _showContextMenu(details, width),
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

  Future<void> _showContextMenu(TapDownDetails details, double width) async {
    final position = details.localPosition;
    final track = _trackAt(position.dy);
    final hitIndex = _segmentIndexAt(position.dx, width, track);
    final seconds = _snapToFrame(_xToSeconds(position.dx, width));
    final segment = hitIndex == null ? null : widget.segments[hitIndex];

    if (segment != null) {
      widget.onSegmentSelected(segment.order);
    }

    final action = await showMenu<_TimelineMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: _contextMenuItems(segment, track),
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _TimelineMenuAction.markIn:
        widget.onSetMarkIn?.call(seconds);
      case _TimelineMenuAction.markOut:
        widget.onSetMarkOut?.call(seconds);
      case _TimelineMenuAction.clearMarks:
        widget.onClearMarks?.call();
      case _TimelineMenuAction.split:
        widget.onSplitAt?.call(seconds);
      case _TimelineMenuAction.duplicate:
        widget.onDuplicateSegment?.call();
      case _TimelineMenuAction.delete:
        widget.onDeleteSegment?.call();
      case _TimelineMenuAction.moveEarlier:
        widget.onMoveSegment?.call(-1);
      case _TimelineMenuAction.moveLater:
        widget.onMoveSegment?.call(1);
      case _TimelineMenuAction.toggleAudioLink:
        widget.onToggleAudioLink?.call();
      case _TimelineMenuAction.toggleAudioMute:
        widget.onToggleAudioMute?.call();
      case _TimelineMenuAction.toggleVideoEnabled:
        widget.onToggleVideoEnabled?.call();
      case _TimelineMenuAction.resetAudioPan:
        widget.onResetAudioPan?.call();
    }
  }

  List<PopupMenuEntry<_TimelineMenuAction>> _contextMenuItems(
    HighlightSegment? segment,
    _DragTrack? track,
  ) {
    final videoLocked = widget.videoTrackLocked;
    final audioLocked = widget.audioTrackLocked;
    final clipEditable = segment != null && !videoLocked && !audioLocked;
    final trackLabel = track == _DragTrack.audio
        ? 'A1 Audio'
        : track == _DragTrack.video
        ? 'V1 Video'
        : 'Timeline';
    return [
      PopupMenuItem(
        enabled: false,
        child: Text(
          segment == null ? trackLabel : 'Clip ${segment.order} · $trackLabel',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      const PopupMenuDivider(),
      _menuItem(Icons.start, 'Set In here', _TimelineMenuAction.markIn),
      _menuItem(
        Icons.flag_outlined,
        'Set Out here',
        _TimelineMenuAction.markOut,
      ),
      _menuItem(Icons.clear, 'Clear marks', _TimelineMenuAction.clearMarks),
      const PopupMenuDivider(),
      _menuItem(
        Icons.call_split,
        'Split at cursor',
        _TimelineMenuAction.split,
        enabled: clipEditable,
      ),
      _menuItem(
        Icons.content_copy,
        'Duplicate clip',
        _TimelineMenuAction.duplicate,
        enabled: clipEditable,
      ),
      _menuItem(
        Icons.delete_outline,
        'Delete clip',
        _TimelineMenuAction.delete,
        enabled: clipEditable,
      ),
      _menuItem(
        Icons.keyboard_arrow_up,
        'Move earlier',
        _TimelineMenuAction.moveEarlier,
        enabled: segment != null,
      ),
      _menuItem(
        Icons.keyboard_arrow_down,
        'Move later',
        _TimelineMenuAction.moveLater,
        enabled: segment != null,
      ),
      const PopupMenuDivider(),
      _menuItem(
        segment?.videoEnabled ?? true
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        segment?.videoEnabled ?? true ? 'Hide V1 video' : 'Show V1 video',
        _TimelineMenuAction.toggleVideoEnabled,
        enabled: segment != null && !videoLocked,
      ),
      _menuItem(
        segment?.audioLinked ?? true ? Icons.link_off : Icons.link,
        segment?.audioLinked ?? true ? 'Detach audio' : 'Relink audio',
        _TimelineMenuAction.toggleAudioLink,
        enabled: segment != null && !audioLocked,
      ),
      _menuItem(
        segment?.audioMuted ?? false
            ? Icons.volume_up_outlined
            : Icons.volume_off_outlined,
        segment?.audioMuted ?? false ? 'Unmute A1' : 'Mute A1',
        _TimelineMenuAction.toggleAudioMute,
        enabled: segment != null && !audioLocked,
      ),
      _menuItem(
        Icons.balance_outlined,
        'Reset A1 pan',
        _TimelineMenuAction.resetAudioPan,
        enabled: segment != null && !audioLocked,
      ),
    ];
  }

  PopupMenuItem<_TimelineMenuAction> _menuItem(
    IconData icon,
    String label,
    _TimelineMenuAction action, {
    bool enabled = true,
  }) {
    return PopupMenuItem(
      value: action,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }

  void _startDrag(Offset position, double width) {
    final track = _trackAt(position.dy);
    if (track == null) {
      _beginScrub(position.dx, width);
      return;
    }

    if (_trackLocked(track)) {
      final hitIndex = _segmentIndexAt(position.dx, width, track);
      if (hitIndex != null) {
        widget.onSegmentSelected(widget.segments[hitIndex].order);
      }
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
    if (_trackLocked(track)) {
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

  bool _trackLocked(_DragTrack track) {
    return track == _DragTrack.video
        ? widget.videoTrackLocked
        : widget.audioTrackLocked;
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
        fill: segment.videoEnabled
            ? (isActive ? colorScheme.tertiary : colorScheme.primary)
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
        border: segment.videoEnabled
            ? (isActive ? colorScheme.tertiary : colorScheme.onSurface)
            : colorScheme.error,
        radius: radius,
        handlesActive: isActive && activeTrack != _DragTrack.audio,
        disabledPattern: !segment.videoEnabled,
      );

      final audioFill = segment.audioLinked
          ? colorScheme.secondary
          : colorScheme.tertiary;
      final audioBorder = segment.audioMuted
          ? colorScheme.error
          : segment.audioPan.abs() > 0.001
          ? colorScheme.primary
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
      if (segment.audioPan.abs() > 0.001) {
        _drawPanIndicator(canvas, size, segment);
      }
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
    bool disabledPattern = false,
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
    if (disabledPattern) {
      final patternPaint = Paint()
        ..color = colorScheme.error.withValues(alpha: 0.42)
        ..strokeWidth = 1;
      for (var x = rect.left - rect.height; x < rect.right; x += 10) {
        canvas.drawLine(
          Offset(x, rect.bottom),
          Offset(x + rect.height, rect.top),
          patternPaint,
        );
      }
    }

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

  void _drawPanIndicator(Canvas canvas, Size size, HighlightSegment segment) {
    final left = _secondsToX(segment.effectiveAudioStart, size.width);
    final right = _secondsToX(segment.effectiveAudioEnd, size.width);
    final width = math.max(2.0, right - left);
    final panX =
        left + ((segment.audioPan + 1.0) / 2.0).clamp(0.0, 1.0) * width;
    final center = Offset(panX, _audioTop + _laneHeight / 2);
    canvas.drawCircle(center, 4.5, Paint()..color = colorScheme.surface);
    canvas.drawCircle(
      center,
      3.0,
      Paint()
        ..color = segment.audioPan < 0
            ? colorScheme.primary
            : colorScheme.tertiary,
    );
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
