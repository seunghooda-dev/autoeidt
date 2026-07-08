import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/highlight_segment.dart';
import 'time_format.dart';

enum _DragEdge { start, end }

enum _DragTrack { video, audio }

enum _TimelineMenuAction {
  selectionTool,
  razorTool,
  markIn,
  markOut,
  markClip,
  clearMarks,
  clearIn,
  clearOut,
  addEdit,
  rippleTrimStart,
  rippleTrimEnd,
  extendStart,
  extendEnd,
  applyVideoTransition,
  applyAudioTransition,
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
    required this.razorTool,
    required this.onSegmentChanged,
    required this.onScrub,
    required this.onSegmentSelected,
    this.onSetMarkIn,
    this.onSetMarkOut,
    this.onClearMarks,
    this.onClearMarkIn,
    this.onClearMarkOut,
    this.onMarkClip,
    this.onAddEditAt,
    this.onRippleTrimStartTo,
    this.onRippleTrimEndTo,
    this.onExtendStartTo,
    this.onExtendEndTo,
    this.onApplyVideoTransition,
    this.onApplyAudioTransition,
    this.onSetSelectionTool,
    this.onSetRazorTool,
    this.onSplitAt,
    this.onDuplicateSegment,
    this.onDeleteSegment,
    this.onMoveSegment,
    this.onToggleAudioLink,
    this.onToggleAudioMute,
    this.onToggleVideoEnabled,
    this.onResetAudioPan,
    this.onZoomDelta,
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
  final bool razorTool;
  final ValueChanged<HighlightSegment> onSegmentChanged;
  final ValueChanged<double> onScrub;
  final ValueChanged<int> onSegmentSelected;
  final ValueChanged<double>? onSetMarkIn;
  final ValueChanged<double>? onSetMarkOut;
  final VoidCallback? onClearMarks;
  final VoidCallback? onClearMarkIn;
  final VoidCallback? onClearMarkOut;
  final VoidCallback? onMarkClip;
  final ValueChanged<double>? onAddEditAt;
  final ValueChanged<double>? onRippleTrimStartTo;
  final ValueChanged<double>? onRippleTrimEndTo;
  final ValueChanged<double>? onExtendStartTo;
  final ValueChanged<double>? onExtendEndTo;
  final VoidCallback? onApplyVideoTransition;
  final VoidCallback? onApplyAudioTransition;
  final VoidCallback? onSetSelectionTool;
  final VoidCallback? onSetRazorTool;
  final ValueChanged<double>? onSplitAt;
  final VoidCallback? onDuplicateSegment;
  final VoidCallback? onDeleteSegment;
  final ValueChanged<int>? onMoveSegment;
  final VoidCallback? onToggleAudioLink;
  final VoidCallback? onToggleAudioMute;
  final VoidCallback? onToggleVideoEnabled;
  final VoidCallback? onResetAudioPan;
  final ValueChanged<double>? onZoomDelta;

  @override
  State<TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineEditorState extends State<TimelineEditor> {
  static const double _handleHitWidth = 16;
  static const double _handleVisualWidth = 4;
  static const double _minSegmentSeconds = 1.0;
  static const double _videoTop = 42;
  static const double _audioTop = 88;
  static const double _laneHeight = 30;

  int? _activeIndex;
  _DragEdge? _activeEdge;
  _DragTrack? _activeTrack;
  bool _isScrubbing = false;
  final ScrollController _scrollController = ScrollController();
  double _lastViewportWidth = 0;
  double? _pendingZoomFocalRatio;
  double? _pendingZoomViewportX;

  @override
  void didUpdateWidget(covariant TimelineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoom == widget.zoom || _pendingZoomFocalRatio == null) {
      return;
    }
    final focalRatio = _pendingZoomFocalRatio!;
    final viewportX = _pendingZoomViewportX ?? 0;
    _pendingZoomFocalRatio = null;
    _pendingZoomViewportX = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          _lastViewportWidth <= 0) {
        return;
      }
      final targetOffset =
          focalRatio * _lastViewportWidth * widget.zoom - viewportX;
      final maxOffset = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(targetOffset.clamp(0.0, maxOffset).toDouble());
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastViewportWidth = constraints.maxWidth;
        final width = constraints.maxWidth * widget.zoom;
        return Listener(
          onPointerSignal: _handlePointerSignal,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: widget.zoom > 1.0,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _tap(details.localPosition, width),
                onSecondaryTapDown: (details) =>
                    _showContextMenu(details, width),
                onPanStart: (details) =>
                    _startDrag(details.localPosition, width),
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
          ),
        );
      },
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    final onZoomDelta = widget.onZoomDelta;
    if (onZoomDelta == null || event is! PointerScrollEvent) {
      return;
    }
    final scrollDy = event.scrollDelta.dy;
    if (scrollDy == 0 || _lastViewportWidth <= 0) {
      return;
    }
    final direction = scrollDy < 0 ? 1.0 : -1.0;
    final notches = (scrollDy.abs() / 120).clamp(1.0, 3.0).toDouble();
    final delta = direction * 0.35 * notches;
    final nextZoom = (widget.zoom + delta).clamp(1.0, 6.0).toDouble();
    if (nextZoom == widget.zoom) {
      return;
    }

    final viewportX = event.localPosition.dx
        .clamp(0.0, _lastViewportWidth)
        .toDouble();
    final currentOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final contentWidth = math.max(_lastViewportWidth * widget.zoom, 1.0);
    _pendingZoomFocalRatio = (currentOffset + viewportX) / contentWidth;
    _pendingZoomViewportX = viewportX;
    onZoomDelta(delta);
  }

  void _tap(Offset position, double width) {
    final track = _trackAt(position.dy);
    final hitIndex = _segmentIndexAt(position.dx, width, track);
    final seconds = _snapToFrame(_xToSeconds(position.dx, width));
    if (hitIndex != null) {
      widget.onSegmentSelected(widget.segments[hitIndex].order);
    }
    if (widget.razorTool && hitIndex != null) {
      widget.onSplitAt?.call(seconds);
      return;
    }
    widget.onScrub(seconds);
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
      case _TimelineMenuAction.selectionTool:
        widget.onSetSelectionTool?.call();
      case _TimelineMenuAction.razorTool:
        widget.onSetRazorTool?.call();
      case _TimelineMenuAction.markIn:
        widget.onSetMarkIn?.call(seconds);
      case _TimelineMenuAction.markOut:
        widget.onSetMarkOut?.call(seconds);
      case _TimelineMenuAction.markClip:
        widget.onMarkClip?.call();
      case _TimelineMenuAction.clearMarks:
        widget.onClearMarks?.call();
      case _TimelineMenuAction.clearIn:
        widget.onClearMarkIn?.call();
      case _TimelineMenuAction.clearOut:
        widget.onClearMarkOut?.call();
      case _TimelineMenuAction.addEdit:
        widget.onAddEditAt?.call(seconds);
      case _TimelineMenuAction.rippleTrimStart:
        widget.onRippleTrimStartTo?.call(seconds);
      case _TimelineMenuAction.rippleTrimEnd:
        widget.onRippleTrimEndTo?.call(seconds);
      case _TimelineMenuAction.extendStart:
        widget.onExtendStartTo?.call(seconds);
      case _TimelineMenuAction.extendEnd:
        widget.onExtendEndTo?.call(seconds);
      case _TimelineMenuAction.applyVideoTransition:
        widget.onApplyVideoTransition?.call();
      case _TimelineMenuAction.applyAudioTransition:
        widget.onApplyAudioTransition?.call();
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
      _menuHeader('Premiere Cut Shortcuts'),
      _menuItem(
        Icons.near_me_outlined,
        'Selection Tool',
        _TimelineMenuAction.selectionTool,
        shortcut: 'V',
      ),
      _menuItem(
        Icons.content_cut,
        'Razor Tool',
        _TimelineMenuAction.razorTool,
        shortcut: 'C',
      ),
      const PopupMenuDivider(),
      _menuItem(
        Icons.start,
        'Set In here',
        _TimelineMenuAction.markIn,
        shortcut: 'I',
      ),
      _menuItem(
        Icons.flag_outlined,
        'Set Out here',
        _TimelineMenuAction.markOut,
        shortcut: 'O',
      ),
      _menuItem(
        Icons.select_all,
        'Mark selected clip',
        _TimelineMenuAction.markClip,
        shortcut: 'X',
        enabled: segment != null,
      ),
      _menuItem(
        Icons.first_page,
        'Clear In',
        _TimelineMenuAction.clearIn,
        shortcut: 'Ctrl+Shift+I',
      ),
      _menuItem(
        Icons.last_page,
        'Clear Out',
        _TimelineMenuAction.clearOut,
        shortcut: 'Ctrl+Shift+O',
      ),
      _menuItem(
        Icons.clear,
        'Clear In/Out',
        _TimelineMenuAction.clearMarks,
        shortcut: 'Ctrl+Shift+X',
      ),
      const PopupMenuDivider(),
      _menuItem(
        Icons.add,
        'Add Edit at cursor',
        _TimelineMenuAction.addEdit,
        shortcut: 'Ctrl+K',
        enabled: segment != null,
      ),
      _menuItem(
        Icons.call_split,
        'Split selected clip',
        _TimelineMenuAction.split,
        shortcut: 'Ctrl+K',
        enabled: clipEditable,
      ),
      _menuItem(
        Icons.keyboard_tab,
        'Ripple trim start',
        _TimelineMenuAction.rippleTrimStart,
        shortcut: 'Q',
        enabled: segment != null && !videoLocked,
      ),
      _menuItem(
        Icons.keyboard_return,
        'Ripple trim end',
        _TimelineMenuAction.rippleTrimEnd,
        shortcut: 'W',
        enabled: segment != null && !videoLocked,
      ),
      _menuItem(
        Icons.keyboard_double_arrow_left,
        'Extend start to cursor',
        _TimelineMenuAction.extendStart,
        shortcut: 'Shift+Q',
        enabled: segment != null && !videoLocked,
      ),
      _menuItem(
        Icons.keyboard_double_arrow_right,
        'Extend end to cursor',
        _TimelineMenuAction.extendEnd,
        shortcut: 'Shift+W',
        enabled: segment != null && !videoLocked,
      ),
      const PopupMenuDivider(),
      _menuItem(
        Icons.gradient,
        'Apply video transition',
        _TimelineMenuAction.applyVideoTransition,
        shortcut: 'Ctrl+D',
        enabled: segment != null && !videoLocked,
      ),
      _menuItem(
        Icons.graphic_eq,
        'Apply audio transition',
        _TimelineMenuAction.applyAudioTransition,
        shortcut: 'Ctrl+Shift+D',
        enabled: segment != null && !audioLocked,
      ),
      const PopupMenuDivider(),
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
        shortcut: 'Delete',
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
        shortcut: 'Ctrl+L',
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

  PopupMenuItem<_TimelineMenuAction> _menuHeader(String label) {
    return PopupMenuItem(
      enabled: false,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }

  PopupMenuItem<_TimelineMenuAction> _menuItem(
    IconData icon,
    String label,
    _TimelineMenuAction action, {
    String? shortcut,
    bool enabled = true,
  }) {
    return PopupMenuItem(
      value: action,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          if (shortcut != null) ...[
            const SizedBox(width: 14),
            Text(
              shortcut,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
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
  static const double _handleVisualWidth =
      _TimelineEditorState._handleVisualWidth;
  static const Color _videoClipColor = Color(0xFFA7F3A1);
  static const Color _videoClipActiveColor = Color(0xFFC6F77B);
  static const Color _audioClipColor = Color(0xFFFFBD7A);
  static const Color _audioClipActiveColor = Color(0xFFFFD49C);
  static const Color _clipTextColor = Color(0xFF11140F);

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
    final radius = Radius.circular(5);
    final trackPaint = Paint()..color = colorScheme.surfaceContainerHighest;
    _drawTrack(canvas, size, _videoTop, radius, trackPaint);
    _drawTrack(canvas, size, _audioTop, radius, trackPaint);
    _drawLaneLabel(canvas, 'V1', _videoTop, _videoClipColor);
    _drawLaneLabel(canvas, 'A1', _audioTop, _audioClipColor);

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
    final rect = Rect.fromLTWH(0, top, size.width, _laneHeight);
    final track = RRect.fromRectAndRadius(rect, radius);
    canvas.drawRRect(track, paint);
    canvas.drawRRect(
      track,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.onSurface.withValues(alpha: 0.05),
            colorScheme.surface.withValues(alpha: 0.12),
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..color = colorScheme.outline.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );
    canvas.drawLine(
      Offset(44, top + _laneHeight / 2),
      Offset(size.width, top + _laneHeight / 2),
      Paint()
        ..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );
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
        style: TextStyle(
          color: _clipTextColor.withValues(alpha: 0.95),
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
    final rulerRect = Rect.fromLTWH(0, 0, size.width, 26);
    canvas.drawRect(
      rulerRect,
      Paint()..color = colorScheme.surface.withValues(alpha: 0.78),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 24, size.width, 1),
      Paint()..color = colorScheme.outline.withValues(alpha: 0.75),
    );

    final tickPaint = Paint()
      ..color = colorScheme.outline.withValues(alpha: 0.80)
      ..strokeWidth = 1;
    final minorTickPaint = Paint()
      ..color = colorScheme.outline.withValues(alpha: 0.32)
      ..strokeWidth = 0.8;
    final majorStep = _tickStepSeconds(size.width);
    final minorStep = math.max(1.0, majorStep / 5);
    for (
      var seconds = 0.0;
      seconds <= duration + minorStep / 2;
      seconds += minorStep
    ) {
      final normalizedSeconds = seconds.clamp(0.0, duration).toDouble();
      final x = _secondsToX(normalizedSeconds, size.width);
      final isMajor =
          (normalizedSeconds / majorStep -
                      (normalizedSeconds / majorStep).round())
                  .abs() <
              0.001 ||
          normalizedSeconds == 0 ||
          normalizedSeconds == duration;
      final top = isMajor ? 24.0 : 29.0;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, isMajor ? _audioTop + _laneHeight + 6 : 38),
        isMajor ? tickPaint : minorTickPaint,
      );
      if (isMajor) {
        _drawRulerTimecode(canvas, size, x, normalizedSeconds);
      }
      if (normalizedSeconds == duration) {
        break;
      }
    }
  }

  double _tickStepSeconds(double width) {
    if (duration <= 0 || width <= 0) {
      return 1;
    }
    final targetStep = duration / math.max(2.0, width / 118);
    const candidates = <double>[
      1,
      2,
      5,
      10,
      15,
      30,
      60,
      120,
      300,
      600,
      900,
      1800,
      3600,
    ];
    for (final candidate in candidates) {
      if (candidate >= targetStep) {
        return candidate;
      }
    }
    return (targetStep / 3600).ceil() * 3600;
  }

  void _drawRulerTimecode(Canvas canvas, Size size, double x, double seconds) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: formatSeconds(seconds),
        style: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.92),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final labelX = (x - textPainter.width / 2)
        .clamp(2.0, math.max(2.0, size.width - textPainter.width - 2))
        .toDouble();
    textPainter.paint(canvas, Offset(labelX, 6));
  }

  void _drawSegments(Canvas canvas, Size size, Radius radius) {
    if (segments.isEmpty && duration > 0) {
      _drawClipBlock(
        canvas,
        size,
        top: _videoTop,
        start: 0,
        end: duration,
        fill: _videoClipColor,
        border: _videoClipColor,
        radius: radius,
        handlesActive: false,
        label: 'V1 Source',
        track: _DragTrack.video,
      );
      _drawClipBlock(
        canvas,
        size,
        top: _audioTop,
        start: 0,
        end: duration,
        fill: _audioClipColor,
        border: _audioClipColor,
        radius: radius,
        handlesActive: false,
        label: 'A1 Source',
        track: _DragTrack.audio,
      );
      return;
    }

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
            ? (isActive ? _videoClipActiveColor : _videoClipColor)
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
        border: segment.videoEnabled
            ? (isActive ? _videoClipActiveColor : _videoClipColor)
            : colorScheme.error,
        radius: radius,
        handlesActive: isActive && activeTrack != _DragTrack.audio,
        disabledPattern: !segment.videoEnabled,
        label: 'V1 C${segment.order}',
        track: _DragTrack.video,
      );
      _drawFadeOverlay(canvas, size, segment);

      final audioFill = segment.audioLinked
          ? (isActive ? _audioClipActiveColor : _audioClipColor)
          : colorScheme.tertiary;
      final audioBorder = segment.audioMuted
          ? colorScheme.error
          : segment.audioPan.abs() > 0.001
          ? colorScheme.primary
          : (isActive ? _audioClipActiveColor : _audioClipColor);
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
        label: segment.audioMuted
            ? 'A1 muted C${segment.order}'
            : 'A1 C${segment.order}',
        track: _DragTrack.audio,
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
    required String label,
    required _DragTrack track,
    bool disabledPattern = false,
  }) {
    final left = _secondsToX(start, size.width);
    final right = _secondsToX(end, size.width);
    final rect = Rect.fromLTWH(
      left,
      top + 2,
      math.max(2, right - left),
      _laneHeight - 4,
    );
    final rrect = RRect.fromRectAndRadius(rect, radius);
    final clipShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [fill.withValues(alpha: 0.98), fill.withValues(alpha: 0.74)],
    ).createShader(rect);
    canvas.drawRRect(rrect, Paint()..shader = clipShader);
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            colorScheme.surface.withValues(alpha: 0.10),
            Colors.transparent,
            colorScheme.surface.withValues(alpha: 0.10),
          ],
        ).createShader(rect),
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

    if (rect.width > 8) {
      canvas.drawLine(
        Offset(rect.left + 3, rect.top + 1),
        Offset(rect.right - 3, rect.top + 1),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.22)
          ..strokeWidth = 1,
      );
    }
    if (track == _DragTrack.video) {
      _drawVideoPresence(canvas, rect);
    } else {
      _drawAudioPresence(canvas, rect);
    }
    _drawClipTimecodeLabel(canvas, rect, label, start, end, track);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = border.withValues(alpha: handlesActive ? 0.86 : 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = handlesActive ? 1.1 : 0.7,
    );

    final handlePaint = Paint()
      ..color = (handlesActive ? border : colorScheme.onSurfaceVariant)
          .withValues(alpha: handlesActive ? 0.95 : 0.72);
    final handleInnerPaint = Paint()
      ..color = colorScheme.surface.withValues(alpha: 0.82)
      ..strokeWidth = 0.8;
    final handleBorder = Paint()
      ..color = colorScheme.surface.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final handleX in [left, right]) {
      final handleRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(handleX, top + _laneHeight / 2),
          width: _handleVisualWidth,
          height: _laneHeight + 4,
        ),
        Radius.circular(2),
      );
      canvas.drawRRect(handleRect, handlePaint);
      canvas.drawRRect(handleRect, handleBorder);
      canvas.drawLine(
        Offset(handleX, top + 5),
        Offset(handleX, top + _laneHeight - 5),
        handleInnerPaint,
      );
    }
  }

  void _drawVideoPresence(Canvas canvas, Rect rect) {
    if (rect.width < 18) {
      return;
    }
    final paint = Paint()
      ..color = _clipTextColor.withValues(alpha: 0.18)
      ..strokeWidth = 0.8;
    final top = rect.top + 4;
    final bottom = rect.top + 10;
    for (var x = rect.left + 14; x < rect.right - 4; x += 18) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  void _drawAudioPresence(Canvas canvas, Rect rect) {
    if (rect.width < 18) {
      return;
    }
    final paint = Paint()
      ..color = _clipTextColor.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    final centerY = rect.center.dy;
    canvas.drawLine(
      Offset(rect.left + 7, centerY),
      Offset(rect.right - 7, centerY),
      paint..color = _clipTextColor.withValues(alpha: 0.12),
    );
    final wavePaint = Paint()
      ..color = _clipTextColor.withValues(alpha: 0.22)
      ..strokeWidth = 0.9;
    for (var x = rect.left + 12; x < rect.right - 6; x += 12) {
      final phase = ((x - rect.left) / 12).round();
      final halfHeight = phase.isEven ? 4.0 : 7.0;
      canvas.drawLine(
        Offset(x, centerY - halfHeight),
        Offset(x, centerY + halfHeight),
        wavePaint,
      );
    }
  }

  void _drawClipTimecodeLabel(
    Canvas canvas,
    Rect rect,
    String label,
    double start,
    double end,
    _DragTrack track,
  ) {
    if (rect.width < 28) {
      return;
    }
    final timeText = '${formatSeconds(start)} - ${formatSeconds(end)}';
    final text = rect.width >= 190
        ? '$label  $timeText'
        : rect.width >= 112
        ? '${track == _DragTrack.video ? 'V' : 'A'}  ${formatSeconds(start)}'
        : label.split(' ').first;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _clipTextColor.withValues(alpha: 0.92),
          fontSize: rect.width >= 112 ? 9 : 8,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, rect.width - 12));
    textPainter.paint(
      canvas,
      Offset(rect.left + 6, rect.center.dy - textPainter.height / 2),
    );
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

  void _drawFadeOverlay(Canvas canvas, Size size, HighlightSegment segment) {
    final left = _secondsToX(segment.start, size.width);
    final right = _secondsToX(segment.end, size.width);
    final clipWidth = math.max(2.0, right - left);
    final fadePaint = Paint()
      ..color = colorScheme.surface.withValues(alpha: 0.38);
    final clipTop = _videoTop + 2;
    final clipBottom = _videoTop + _laneHeight - 2;

    if (segment.videoFadeIn > 0) {
      final fadeEnd = _secondsToX(
        segment.start + segment.videoFadeIn,
        size.width,
      ).clamp(left, right).toDouble();
      final fadeWidth = math.min(clipWidth, fadeEnd - left);
      if (fadeWidth > 1) {
        final path = Path()
          ..moveTo(left, clipTop)
          ..lineTo(left + fadeWidth, clipTop)
          ..lineTo(left, clipBottom)
          ..close();
        canvas.drawPath(path, fadePaint);
      }
    }

    if (segment.videoFadeOut > 0) {
      final fadeStart = _secondsToX(
        segment.end - segment.videoFadeOut,
        size.width,
      ).clamp(left, right).toDouble();
      final fadeWidth = math.min(clipWidth, right - fadeStart);
      if (fadeWidth > 1) {
        final path = Path()
          ..moveTo(right, clipTop)
          ..lineTo(right, clipBottom)
          ..lineTo(right - fadeWidth, clipBottom)
          ..close();
        canvas.drawPath(path, fadePaint);
      }
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
