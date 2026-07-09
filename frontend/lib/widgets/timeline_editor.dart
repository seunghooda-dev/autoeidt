import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/highlight_segment.dart';
import '../models/job_models.dart';
import 'time_format.dart';

enum _DragEdge { start, end }

enum _DragTrack { video, audio1, audio2 }

bool _isTimelineGapSegment(HighlightSegment segment) {
  final source = segment.source.toLowerCase();
  final reason = segment.reason.toLowerCase();
  final hasGapIdentity =
      segment.tags.contains('gap') ||
      source.contains('lift-gap') ||
      reason.contains('lift gap');
  final hasNoAudibleMedia =
      segment.audioMuted ||
      segment.audioVolume <= 0.01 ||
      !segment.hasActiveAudioChannel;
  return hasGapIdentity && !segment.videoEnabled && hasNoAudibleMedia;
}

enum _TimelineMenuAction {
  selectionTool,
  razorTool,
  toggleSnapping,
  markIn,
  markOut,
  markClip,
  clearMarks,
  clearIn,
  clearOut,
  liftMarkedRange,
  extractMarkedRange,
  insertMarkedSegment,
  overwriteMarkedSegment,
  stepBackwardFrame,
  stepForwardFrame,
  previousEdit,
  nextEdit,
  jumpToMarkIn,
  jumpToMarkOut,
  jumpToSelectedClipStart,
  jumpToSelectedClipEnd,
  addMarker,
  previousMarker,
  nextMarker,
  deleteMarker,
  clearTimelineMarkers,
  selectClipAtCursor,
  deselectClip,
  selectPreviousClip,
  selectNextClip,
  addEdit,
  addEditAllTracks,
  rippleTrimStart,
  rippleTrimEnd,
  extendStart,
  extendEnd,
  rollIncomingEarlierFrame,
  rollIncomingLaterFrame,
  rollOutgoingEarlierFrame,
  rollOutgoingLaterFrame,
  slipEarlierFrame,
  slipLaterFrame,
  slipEarlierTenFrames,
  slipLaterTenFrames,
  nudgeAudioEarlierFrame,
  nudgeAudioLaterFrame,
  nudgeAudioEarlierTenFrames,
  nudgeAudioLaterTenFrames,
  applyVideoTransition,
  applyAudioTransition,
  rateStretchToMarks,
  split,
  duplicate,
  copySelected,
  cutSelected,
  pasteClipboard,
  delete,
  closeSelectedGap,
  closeTimelineGaps,
  liftSelected,
  extractSelected,
  moveEarlier,
  moveLater,
  toggleAudioLink,
  toggleAudioMute,
  toggleAudioChannel1,
  toggleAudioChannel2,
  toggleAllAudioChannel1,
  toggleAllAudioChannel2,
  soloAudioChannel1,
  soloAudioChannel2,
  toggleVideoTarget,
  toggleAudio1Target,
  toggleAudio2Target,
  toggleVideoLock,
  toggleAudio1Lock,
  toggleAudio2Lock,
  toggleClipEnabled,
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
    required this.timelineMarkers,
    required this.waveform,
    required this.zoom,
    required this.trackHeightScale,
    required this.snappingEnabled,
    required this.videoTrackTargeted,
    required this.audioTrack1Targeted,
    required this.audioTrack2Targeted,
    required this.videoTrackLocked,
    required this.audioTrackLocked,
    required this.audioTrack1Locked,
    required this.audioTrack2Locked,
    required this.razorTool,
    required this.onSegmentChanged,
    required this.onScrub,
    required this.onSegmentSelected,
    this.onSetMarkIn,
    this.onSetMarkOut,
    this.onClearMarks,
    this.onClearMarkIn,
    this.onClearMarkOut,
    this.onLiftMarkedRange,
    this.onExtractMarkedRange,
    this.onInsertMarkedSegment,
    this.onOverwriteMarkedSegment,
    this.onStepBackwardFrame,
    this.onStepForwardFrame,
    this.onJumpToPreviousEdit,
    this.onJumpToNextEdit,
    this.onJumpToMarkIn,
    this.onJumpToMarkOut,
    this.onJumpToSelectedClipStart,
    this.onJumpToSelectedClipEnd,
    this.onSlipSelectedSegmentFrames,
    this.onNudgeSelectedAudioFrames,
    this.onAddMarkerAt,
    this.onJumpToPreviousMarker,
    this.onJumpToNextMarker,
    this.onDeleteMarker,
    this.onClearTimelineMarkers,
    this.onMarkClip,
    this.onSelectClipAt,
    this.onDeselectClip,
    this.onSelectPreviousClip,
    this.onSelectNextClip,
    this.onAddEditAt,
    this.onAddEditAllTracksAt,
    this.onRippleTrimStartTo,
    this.onRippleTrimEndTo,
    this.onExtendStartTo,
    this.onExtendEndTo,
    this.onRollIncomingEditFrames,
    this.onRollOutgoingEditFrames,
    this.onApplyVideoTransition,
    this.onApplyAudioTransition,
    this.onRateStretchToMarks,
    this.onSetSelectionTool,
    this.onSetRazorTool,
    this.onToggleSnapping,
    this.onSplitAt,
    this.onDuplicateSegment,
    this.onCopySegment,
    this.onCutSegment,
    this.onPasteSegment,
    this.hasClipClipboard = false,
    this.onDeleteSegment,
    this.hasTimelineGaps = false,
    this.onCloseSelectedGap,
    this.onCloseTimelineGaps,
    this.onLiftSelectedSegment,
    this.onExtractSelectedSegment,
    this.onMoveSegment,
    this.onToggleAudioLink,
    this.onToggleAudioMute,
    this.onToggleAudioChannel1,
    this.onToggleAudioChannel2,
    this.onToggleAllAudioChannel1,
    this.onToggleAllAudioChannel2,
    this.onSoloAudioChannel1,
    this.onSoloAudioChannel2,
    this.onToggleVideoTarget,
    this.onToggleAudio1Target,
    this.onToggleAudio2Target,
    this.onToggleVideoLock,
    this.onToggleAudio1Lock,
    this.onToggleAudio2Lock,
    this.onToggleClipEnabled,
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
  final List<TimelineMarker> timelineMarkers;
  final List<double> waveform;
  final double zoom;
  final double trackHeightScale;
  final bool snappingEnabled;
  final bool videoTrackTargeted;
  final bool audioTrack1Targeted;
  final bool audioTrack2Targeted;
  final bool videoTrackLocked;
  final bool audioTrackLocked;
  final bool audioTrack1Locked;
  final bool audioTrack2Locked;
  final bool razorTool;
  final ValueChanged<HighlightSegment> onSegmentChanged;
  final ValueChanged<double> onScrub;
  final ValueChanged<int> onSegmentSelected;
  final ValueChanged<double>? onSetMarkIn;
  final ValueChanged<double>? onSetMarkOut;
  final VoidCallback? onClearMarks;
  final VoidCallback? onClearMarkIn;
  final VoidCallback? onClearMarkOut;
  final VoidCallback? onLiftMarkedRange;
  final VoidCallback? onExtractMarkedRange;
  final VoidCallback? onInsertMarkedSegment;
  final VoidCallback? onOverwriteMarkedSegment;
  final VoidCallback? onStepBackwardFrame;
  final VoidCallback? onStepForwardFrame;
  final VoidCallback? onJumpToPreviousEdit;
  final VoidCallback? onJumpToNextEdit;
  final VoidCallback? onJumpToMarkIn;
  final VoidCallback? onJumpToMarkOut;
  final VoidCallback? onJumpToSelectedClipStart;
  final VoidCallback? onJumpToSelectedClipEnd;
  final ValueChanged<int>? onSlipSelectedSegmentFrames;
  final ValueChanged<int>? onNudgeSelectedAudioFrames;
  final ValueChanged<double>? onAddMarkerAt;
  final VoidCallback? onJumpToPreviousMarker;
  final VoidCallback? onJumpToNextMarker;
  final ValueChanged<int>? onDeleteMarker;
  final VoidCallback? onClearTimelineMarkers;
  final VoidCallback? onMarkClip;
  final ValueChanged<double>? onSelectClipAt;
  final VoidCallback? onDeselectClip;
  final VoidCallback? onSelectPreviousClip;
  final VoidCallback? onSelectNextClip;
  final ValueChanged<double>? onAddEditAt;
  final ValueChanged<double>? onAddEditAllTracksAt;
  final ValueChanged<double>? onRippleTrimStartTo;
  final ValueChanged<double>? onRippleTrimEndTo;
  final ValueChanged<double>? onExtendStartTo;
  final ValueChanged<double>? onExtendEndTo;
  final ValueChanged<int>? onRollIncomingEditFrames;
  final ValueChanged<int>? onRollOutgoingEditFrames;
  final VoidCallback? onApplyVideoTransition;
  final VoidCallback? onApplyAudioTransition;
  final VoidCallback? onRateStretchToMarks;
  final VoidCallback? onSetSelectionTool;
  final VoidCallback? onSetRazorTool;
  final VoidCallback? onToggleSnapping;
  final ValueChanged<double>? onSplitAt;
  final VoidCallback? onDuplicateSegment;
  final VoidCallback? onCopySegment;
  final VoidCallback? onCutSegment;
  final VoidCallback? onPasteSegment;
  final bool hasClipClipboard;
  final VoidCallback? onDeleteSegment;
  final bool hasTimelineGaps;
  final VoidCallback? onCloseSelectedGap;
  final VoidCallback? onCloseTimelineGaps;
  final VoidCallback? onLiftSelectedSegment;
  final VoidCallback? onExtractSelectedSegment;
  final ValueChanged<int>? onMoveSegment;
  final VoidCallback? onToggleAudioLink;
  final VoidCallback? onToggleAudioMute;
  final VoidCallback? onToggleAudioChannel1;
  final VoidCallback? onToggleAudioChannel2;
  final VoidCallback? onToggleAllAudioChannel1;
  final VoidCallback? onToggleAllAudioChannel2;
  final VoidCallback? onSoloAudioChannel1;
  final VoidCallback? onSoloAudioChannel2;
  final VoidCallback? onToggleVideoTarget;
  final VoidCallback? onToggleAudio1Target;
  final VoidCallback? onToggleAudio2Target;
  final VoidCallback? onToggleVideoLock;
  final VoidCallback? onToggleAudio1Lock;
  final VoidCallback? onToggleAudio2Lock;
  final VoidCallback? onToggleClipEnabled;
  final VoidCallback? onToggleVideoEnabled;
  final VoidCallback? onResetAudioPan;
  final ValueChanged<double>? onZoomDelta;

  @override
  State<TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineLayout {
  const _TimelineLayout({required double scale})
    : scale = scale < 0.75
          ? 0.75
          : scale > 1.35
          ? 1.35
          : scale;

  final double scale;
  double get videoTop => 42;
  double get laneHeight => 28 * scale;
  double get audio1Top => videoTop + laneHeight + 16;
  double get audio2Top => audio1Top + laneHeight + 8;
  double get footerTop => audio2Top + laneHeight + 8;
  double get canvasHeight => footerTop + 36;
  double get trackBottom => audio2Top + laneHeight;
}

class _TimelineEditorState extends State<TimelineEditor> {
  static const double _snapHitWidth = 10;
  static const double _handleHitWidth = 16;
  static const double _handleVisualWidth = 4;
  static const double _minSegmentSeconds = 1.0;

  int? _activeIndex;
  _DragEdge? _activeEdge;
  _DragTrack? _activeTrack;
  bool _isScrubbing = false;
  final ScrollController _scrollController = ScrollController();
  double _lastViewportWidth = 0;
  double? _pendingZoomFocalRatio;
  double? _pendingZoomViewportX;
  _TimelineLayout get _layout =>
      _TimelineLayout(scale: widget.trackHeightScale);

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
        final layout = _layout;
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
                  height: layout.canvasHeight,
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      layout: layout,
                      duration: widget.duration,
                      segments: widget.segments,
                      playheadSeconds: widget.playheadSeconds,
                      selectedSegmentOrder: widget.selectedSegmentOrder,
                      markIn: widget.markIn,
                      markOut: widget.markOut,
                      timelineMarkers: widget.timelineMarkers,
                      waveform: widget.waveform,
                      activeIndex: _activeIndex,
                      activeEdge: _activeEdge,
                      activeTrack: _activeTrack,
                      videoTrackLocked: widget.videoTrackLocked,
                      audioTrack1Locked:
                          widget.audioTrackLocked || widget.audioTrack1Locked,
                      audioTrack2Locked:
                          widget.audioTrackLocked || widget.audioTrack2Locked,
                      colorScheme: Theme.of(context).colorScheme,
                    ),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: layout.footerTop),
                        child: SizedBox(
                          width: width,
                          child: Text(
                            '원본 ${formatSeconds(widget.duration)}  |  출력 ${formatSeconds(_totalOutputSeconds())}  |  V1/A1/A2 분리 ${_detachedAudioCount()}개',
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
    final seconds = _snapTimelineSeconds(
      _xToSeconds(position.dx, width),
      width,
    );
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
    final marker = _markerAt(position.dx, width);
    final seconds = _snapTimelineSeconds(
      _xToSeconds(position.dx, width),
      width,
    );
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
      items: _contextMenuItems(segment, track, marker),
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _TimelineMenuAction.selectionTool:
        widget.onSetSelectionTool?.call();
      case _TimelineMenuAction.razorTool:
        widget.onSetRazorTool?.call();
      case _TimelineMenuAction.toggleSnapping:
        widget.onToggleSnapping?.call();
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
      case _TimelineMenuAction.liftMarkedRange:
        widget.onLiftMarkedRange?.call();
      case _TimelineMenuAction.extractMarkedRange:
        widget.onExtractMarkedRange?.call();
      case _TimelineMenuAction.insertMarkedSegment:
        widget.onInsertMarkedSegment?.call();
      case _TimelineMenuAction.overwriteMarkedSegment:
        widget.onOverwriteMarkedSegment?.call();
      case _TimelineMenuAction.stepBackwardFrame:
        widget.onStepBackwardFrame?.call();
      case _TimelineMenuAction.stepForwardFrame:
        widget.onStepForwardFrame?.call();
      case _TimelineMenuAction.previousEdit:
        widget.onJumpToPreviousEdit?.call();
      case _TimelineMenuAction.nextEdit:
        widget.onJumpToNextEdit?.call();
      case _TimelineMenuAction.jumpToMarkIn:
        widget.onJumpToMarkIn?.call();
      case _TimelineMenuAction.jumpToMarkOut:
        widget.onJumpToMarkOut?.call();
      case _TimelineMenuAction.jumpToSelectedClipStart:
        widget.onJumpToSelectedClipStart?.call();
      case _TimelineMenuAction.jumpToSelectedClipEnd:
        widget.onJumpToSelectedClipEnd?.call();
      case _TimelineMenuAction.addMarker:
        widget.onAddMarkerAt?.call(seconds);
      case _TimelineMenuAction.previousMarker:
        widget.onJumpToPreviousMarker?.call();
      case _TimelineMenuAction.nextMarker:
        widget.onJumpToNextMarker?.call();
      case _TimelineMenuAction.deleteMarker:
        if (marker != null) {
          widget.onDeleteMarker?.call(marker.id);
        }
      case _TimelineMenuAction.clearTimelineMarkers:
        widget.onClearTimelineMarkers?.call();
      case _TimelineMenuAction.selectClipAtCursor:
        widget.onSelectClipAt?.call(seconds);
      case _TimelineMenuAction.deselectClip:
        widget.onDeselectClip?.call();
      case _TimelineMenuAction.selectPreviousClip:
        widget.onSelectPreviousClip?.call();
      case _TimelineMenuAction.selectNextClip:
        widget.onSelectNextClip?.call();
      case _TimelineMenuAction.addEdit:
        widget.onAddEditAt?.call(seconds);
      case _TimelineMenuAction.addEditAllTracks:
        widget.onAddEditAllTracksAt?.call(seconds);
      case _TimelineMenuAction.rippleTrimStart:
        widget.onRippleTrimStartTo?.call(seconds);
      case _TimelineMenuAction.rippleTrimEnd:
        widget.onRippleTrimEndTo?.call(seconds);
      case _TimelineMenuAction.extendStart:
        widget.onExtendStartTo?.call(seconds);
      case _TimelineMenuAction.extendEnd:
        widget.onExtendEndTo?.call(seconds);
      case _TimelineMenuAction.rollIncomingEarlierFrame:
        widget.onRollIncomingEditFrames?.call(-1);
      case _TimelineMenuAction.rollIncomingLaterFrame:
        widget.onRollIncomingEditFrames?.call(1);
      case _TimelineMenuAction.rollOutgoingEarlierFrame:
        widget.onRollOutgoingEditFrames?.call(-1);
      case _TimelineMenuAction.rollOutgoingLaterFrame:
        widget.onRollOutgoingEditFrames?.call(1);
      case _TimelineMenuAction.slipEarlierFrame:
        widget.onSlipSelectedSegmentFrames?.call(-1);
      case _TimelineMenuAction.slipLaterFrame:
        widget.onSlipSelectedSegmentFrames?.call(1);
      case _TimelineMenuAction.slipEarlierTenFrames:
        widget.onSlipSelectedSegmentFrames?.call(-10);
      case _TimelineMenuAction.slipLaterTenFrames:
        widget.onSlipSelectedSegmentFrames?.call(10);
      case _TimelineMenuAction.nudgeAudioEarlierFrame:
        widget.onNudgeSelectedAudioFrames?.call(-1);
      case _TimelineMenuAction.nudgeAudioLaterFrame:
        widget.onNudgeSelectedAudioFrames?.call(1);
      case _TimelineMenuAction.nudgeAudioEarlierTenFrames:
        widget.onNudgeSelectedAudioFrames?.call(-10);
      case _TimelineMenuAction.nudgeAudioLaterTenFrames:
        widget.onNudgeSelectedAudioFrames?.call(10);
      case _TimelineMenuAction.applyVideoTransition:
        widget.onApplyVideoTransition?.call();
      case _TimelineMenuAction.applyAudioTransition:
        widget.onApplyAudioTransition?.call();
      case _TimelineMenuAction.rateStretchToMarks:
        widget.onRateStretchToMarks?.call();
      case _TimelineMenuAction.split:
        widget.onSplitAt?.call(seconds);
      case _TimelineMenuAction.duplicate:
        widget.onDuplicateSegment?.call();
      case _TimelineMenuAction.copySelected:
        widget.onCopySegment?.call();
      case _TimelineMenuAction.cutSelected:
        widget.onCutSegment?.call();
      case _TimelineMenuAction.pasteClipboard:
        widget.onPasteSegment?.call();
      case _TimelineMenuAction.delete:
        widget.onDeleteSegment?.call();
      case _TimelineMenuAction.closeSelectedGap:
        widget.onCloseSelectedGap?.call();
      case _TimelineMenuAction.closeTimelineGaps:
        widget.onCloseTimelineGaps?.call();
      case _TimelineMenuAction.liftSelected:
        widget.onLiftSelectedSegment?.call();
      case _TimelineMenuAction.extractSelected:
        widget.onExtractSelectedSegment?.call();
      case _TimelineMenuAction.moveEarlier:
        widget.onMoveSegment?.call(-1);
      case _TimelineMenuAction.moveLater:
        widget.onMoveSegment?.call(1);
      case _TimelineMenuAction.toggleAudioLink:
        widget.onToggleAudioLink?.call();
      case _TimelineMenuAction.toggleAudioMute:
        widget.onToggleAudioMute?.call();
      case _TimelineMenuAction.toggleAudioChannel1:
        widget.onToggleAudioChannel1?.call();
      case _TimelineMenuAction.toggleAudioChannel2:
        widget.onToggleAudioChannel2?.call();
      case _TimelineMenuAction.toggleAllAudioChannel1:
        widget.onToggleAllAudioChannel1?.call();
      case _TimelineMenuAction.toggleAllAudioChannel2:
        widget.onToggleAllAudioChannel2?.call();
      case _TimelineMenuAction.soloAudioChannel1:
        widget.onSoloAudioChannel1?.call();
      case _TimelineMenuAction.soloAudioChannel2:
        widget.onSoloAudioChannel2?.call();
      case _TimelineMenuAction.toggleVideoTarget:
        widget.onToggleVideoTarget?.call();
      case _TimelineMenuAction.toggleAudio1Target:
        widget.onToggleAudio1Target?.call();
      case _TimelineMenuAction.toggleAudio2Target:
        widget.onToggleAudio2Target?.call();
      case _TimelineMenuAction.toggleVideoLock:
        widget.onToggleVideoLock?.call();
      case _TimelineMenuAction.toggleAudio1Lock:
        widget.onToggleAudio1Lock?.call();
      case _TimelineMenuAction.toggleAudio2Lock:
        widget.onToggleAudio2Lock?.call();
      case _TimelineMenuAction.toggleClipEnabled:
        widget.onToggleClipEnabled?.call();
      case _TimelineMenuAction.toggleVideoEnabled:
        widget.onToggleVideoEnabled?.call();
      case _TimelineMenuAction.resetAudioPan:
        widget.onResetAudioPan?.call();
    }
  }

  List<PopupMenuEntry<_TimelineMenuAction>> _contextMenuItems(
    HighlightSegment? segment,
    _DragTrack? track,
    TimelineMarker? marker,
  ) {
    final videoLocked = widget.videoTrackLocked;
    final audio1Locked = widget.audioTrackLocked || widget.audioTrack1Locked;
    final audio2Locked = widget.audioTrackLocked || widget.audioTrack2Locked;
    final anyAudioLocked = audio1Locked || audio2Locked;
    final clipEditable = segment != null && !videoLocked && !anyAudioLocked;
    final detachedAudioEditable =
        segment != null &&
        !anyAudioLocked &&
        !segment.audioLinked &&
        widget.onNudgeSelectedAudioFrames != null;
    final showAudioNudge = detachedAudioEditable && _isAudioTrack(track);
    final hasMarkedRange =
        widget.markIn != null &&
        widget.markOut != null &&
        widget.markOut! - widget.markIn! >= timecodeFrameDurationSeconds;
    final canEditMarkedRange =
        hasMarkedRange &&
        !videoLocked &&
        !anyAudioLocked &&
        widget.segments.any(
          (item) => item.start < widget.markOut! && item.end > widget.markIn!,
        );
    final markedTargetsUnlocked =
        (!widget.videoTrackTargeted || !videoLocked) &&
        (!widget.audioTrack1Targeted || !audio1Locked) &&
        (!widget.audioTrack2Targeted || !audio2Locked);
    final canInsertMarked =
        hasMarkedRange &&
        markedTargetsUnlocked &&
        (widget.videoTrackTargeted ||
            widget.audioTrack1Targeted ||
            widget.audioTrack2Targeted) &&
        widget.onInsertMarkedSegment != null;
    final canOverwriteMarked =
        canInsertMarked &&
        segment != null &&
        widget.onOverwriteMarkedSegment != null;
    final showAudioBus = _isAudioTrack(track) && widget.segments.isNotEmpty;
    final allA1Enabled =
        widget.segments.isNotEmpty &&
        widget.segments.every((segment) => segment.audioChannel1Enabled);
    final allA2Enabled =
        widget.segments.isNotEmpty &&
        widget.segments.every((segment) => segment.audioChannel2Enabled);
    final canDisableVideoTarget =
        widget.audioTrack1Targeted || widget.audioTrack2Targeted;
    final canDisableAudio1Target =
        widget.videoTrackTargeted || widget.audioTrack2Targeted;
    final canDisableAudio2Target =
        widget.videoTrackTargeted || widget.audioTrack1Targeted;
    final segmentIndex = segment == null
        ? -1
        : widget.segments.indexWhere((item) => item.order == segment.order);
    final selectedGap = segment != null && _isTimelineGapSegment(segment);
    final canRollIncoming =
        clipEditable &&
        segmentIndex > 0 &&
        widget.onRollIncomingEditFrames != null;
    final canRollOutgoing =
        clipEditable &&
        segmentIndex >= 0 &&
        segmentIndex < widget.segments.length - 1 &&
        widget.onRollOutgoingEditFrames != null;
    final canLiftOrExtractSelected =
        segment != null &&
        (widget.videoTrackTargeted ||
            widget.audioTrack1Targeted ||
            widget.audioTrack2Targeted) &&
        (!widget.videoTrackTargeted || !videoLocked) &&
        (!widget.audioTrack1Targeted || !audio1Locked) &&
        (!widget.audioTrack2Targeted || !audio2Locked);
    final canRateStretch =
        segment != null &&
        hasMarkedRange &&
        !videoLocked &&
        !anyAudioLocked &&
        widget.onRateStretchToMarks != null;
    final trackLabel = _isAudioTrack(track)
        ? '${_audioTrackLabel(track!)} Audio'
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
      if (showAudioNudge) ...[
        _menuHeader('Audio Sync'),
        _menuItem(
          Icons.graphic_eq,
          'Move detached audio earlier 1f',
          _TimelineMenuAction.nudgeAudioEarlierFrame,
          shortcut: 'Ctrl+Alt+Left',
        ),
        _menuItem(
          Icons.graphic_eq,
          'Move detached audio later 1f',
          _TimelineMenuAction.nudgeAudioLaterFrame,
          shortcut: 'Ctrl+Alt+Right',
        ),
        _menuItem(
          Icons.keyboard_double_arrow_left,
          'Move detached audio earlier 10f',
          _TimelineMenuAction.nudgeAudioEarlierTenFrames,
          shortcut: 'Ctrl+Alt+Shift+Left',
        ),
        _menuItem(
          Icons.keyboard_double_arrow_right,
          'Move detached audio later 10f',
          _TimelineMenuAction.nudgeAudioLaterTenFrames,
          shortcut: 'Ctrl+Alt+Shift+Right',
        ),
        const PopupMenuDivider(),
      ],
      if (showAudioBus) ...[
        _menuHeader('Audio Track Bus'),
        _menuItem(
          allA1Enabled
              ? Icons.check_box_outlined
              : Icons.check_box_outline_blank,
          allA1Enabled ? 'Disable all A1' : 'Enable all A1',
          _TimelineMenuAction.toggleAllAudioChannel1,
          enabled: !audio1Locked && widget.onToggleAllAudioChannel1 != null,
        ),
        _menuItem(
          allA2Enabled
              ? Icons.check_box_outlined
              : Icons.check_box_outline_blank,
          allA2Enabled ? 'Disable all A2' : 'Enable all A2',
          _TimelineMenuAction.toggleAllAudioChannel2,
          enabled: !audio2Locked && widget.onToggleAllAudioChannel2 != null,
        ),
        _menuItem(
          Icons.filter_1_outlined,
          'Solo A1 track',
          _TimelineMenuAction.soloAudioChannel1,
          enabled: !anyAudioLocked && widget.onSoloAudioChannel1 != null,
        ),
        _menuItem(
          Icons.filter_2_outlined,
          'Solo A2 track',
          _TimelineMenuAction.soloAudioChannel2,
          enabled: !anyAudioLocked && widget.onSoloAudioChannel2 != null,
        ),
        const PopupMenuDivider(),
      ],
      _menuHeader('Track Targets'),
      _menuItem(
        widget.videoTrackTargeted
            ? Icons.check_box_outlined
            : Icons.check_box_outline_blank,
        widget.videoTrackTargeted ? 'Untarget V1 video' : 'Target V1 video',
        _TimelineMenuAction.toggleVideoTarget,
        shortcut: 'Ctrl+1',
        enabled:
            widget.onToggleVideoTarget != null &&
            (!widget.videoTrackTargeted || canDisableVideoTarget),
      ),
      _menuItem(
        widget.audioTrack1Targeted
            ? Icons.check_box_outlined
            : Icons.check_box_outline_blank,
        widget.audioTrack1Targeted ? 'Untarget A1 audio' : 'Target A1 audio',
        _TimelineMenuAction.toggleAudio1Target,
        shortcut: 'Ctrl+2',
        enabled:
            widget.onToggleAudio1Target != null &&
            (!widget.audioTrack1Targeted || canDisableAudio1Target),
      ),
      _menuItem(
        widget.audioTrack2Targeted
            ? Icons.check_box_outlined
            : Icons.check_box_outline_blank,
        widget.audioTrack2Targeted ? 'Untarget A2 audio' : 'Target A2 audio',
        _TimelineMenuAction.toggleAudio2Target,
        shortcut: 'Ctrl+3',
        enabled:
            widget.onToggleAudio2Target != null &&
            (!widget.audioTrack2Targeted || canDisableAudio2Target),
      ),
      const PopupMenuDivider(),
      _menuHeader('Track Locks'),
      _menuItem(
        widget.videoTrackLocked ? Icons.lock_open : Icons.lock_outline,
        widget.videoTrackLocked ? 'Unlock V1 video' : 'Lock V1 video',
        _TimelineMenuAction.toggleVideoLock,
        shortcut: 'Ctrl+Alt+1',
        enabled: widget.onToggleVideoLock != null,
      ),
      _menuItem(
        audio1Locked ? Icons.lock_open : Icons.lock_outline,
        audio1Locked ? 'Unlock A1 audio' : 'Lock A1 audio',
        _TimelineMenuAction.toggleAudio1Lock,
        shortcut: 'Ctrl+Alt+2',
        enabled: widget.onToggleAudio1Lock != null,
      ),
      _menuItem(
        audio2Locked ? Icons.lock_open : Icons.lock_outline,
        audio2Locked ? 'Unlock A2 audio' : 'Lock A2 audio',
        _TimelineMenuAction.toggleAudio2Lock,
        shortcut: 'Ctrl+Alt+3',
        enabled: widget.onToggleAudio2Lock != null,
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
      _menuItem(
        widget.snappingEnabled ? Icons.grid_on : Icons.grid_off,
        widget.snappingEnabled ? 'Disable snapping' : 'Enable snapping',
        _TimelineMenuAction.toggleSnapping,
        shortcut: 'S',
        enabled: widget.onToggleSnapping != null,
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
      _menuItem(
        Icons.vertical_align_center,
        'Lift In/Out',
        _TimelineMenuAction.liftMarkedRange,
        shortcut: ';',
        enabled: canEditMarkedRange && widget.onLiftMarkedRange != null,
      ),
      _menuItem(
        Icons.playlist_remove,
        'Extract In/Out',
        _TimelineMenuAction.extractMarkedRange,
        shortcut: "'",
        enabled: canEditMarkedRange && widget.onExtractMarkedRange != null,
      ),
      _menuItem(
        Icons.playlist_add,
        'Insert In/Out before clip',
        _TimelineMenuAction.insertMarkedSegment,
        shortcut: ',',
        enabled: canInsertMarked,
      ),
      _menuItem(
        Icons.published_with_changes,
        'Overwrite selected with In/Out',
        _TimelineMenuAction.overwriteMarkedSegment,
        shortcut: '.',
        enabled: canOverwriteMarked,
      ),
      const PopupMenuDivider(),
      _menuHeader('Frame Navigation'),
      _menuItem(
        Icons.keyboard_arrow_left,
        'Step back 1 frame',
        _TimelineMenuAction.stepBackwardFrame,
        shortcut: 'Left',
        enabled: widget.onStepBackwardFrame != null,
      ),
      _menuItem(
        Icons.keyboard_arrow_right,
        'Step forward 1 frame',
        _TimelineMenuAction.stepForwardFrame,
        shortcut: 'Right',
        enabled: widget.onStepForwardFrame != null,
      ),
      _menuItem(
        Icons.vertical_align_top,
        'Previous edit point',
        _TimelineMenuAction.previousEdit,
        shortcut: 'Up',
        enabled: widget.onJumpToPreviousEdit != null,
      ),
      _menuItem(
        Icons.vertical_align_bottom,
        'Next edit point',
        _TimelineMenuAction.nextEdit,
        shortcut: 'Down',
        enabled: widget.onJumpToNextEdit != null,
      ),
      _menuItem(
        Icons.keyboard_tab,
        'Go to In',
        _TimelineMenuAction.jumpToMarkIn,
        shortcut: 'Shift+I',
        enabled: widget.markIn != null && widget.onJumpToMarkIn != null,
      ),
      _menuItem(
        Icons.keyboard_return,
        'Go to Out',
        _TimelineMenuAction.jumpToMarkOut,
        shortcut: 'Shift+O',
        enabled: widget.markOut != null && widget.onJumpToMarkOut != null,
      ),
      _menuItem(
        Icons.first_page,
        'Go to clip start',
        _TimelineMenuAction.jumpToSelectedClipStart,
        shortcut: 'Shift+Home',
        enabled: segment != null && widget.onJumpToSelectedClipStart != null,
      ),
      _menuItem(
        Icons.last_page,
        'Go to clip end',
        _TimelineMenuAction.jumpToSelectedClipEnd,
        shortcut: 'Shift+End',
        enabled: segment != null && widget.onJumpToSelectedClipEnd != null,
      ),
      const PopupMenuDivider(),
      _menuHeader('Timeline Markers'),
      _menuItem(
        Icons.bookmark_add_outlined,
        'Add marker here',
        _TimelineMenuAction.addMarker,
        shortcut: 'M',
        enabled: widget.onAddMarkerAt != null,
      ),
      _menuItem(
        Icons.skip_previous,
        'Previous marker',
        _TimelineMenuAction.previousMarker,
        shortcut: 'Ctrl+Shift+M',
        enabled: _hasPreviousMarker() && widget.onJumpToPreviousMarker != null,
      ),
      _menuItem(
        Icons.skip_next,
        'Next marker',
        _TimelineMenuAction.nextMarker,
        shortcut: 'Shift+M',
        enabled: _hasNextMarker() && widget.onJumpToNextMarker != null,
      ),
      _menuItem(
        Icons.bookmark_remove_outlined,
        marker == null ? 'Delete nearest marker' : 'Delete ${marker.label}',
        _TimelineMenuAction.deleteMarker,
        enabled: marker != null && widget.onDeleteMarker != null,
      ),
      _menuItem(
        Icons.bookmarks_outlined,
        'Clear timeline markers',
        _TimelineMenuAction.clearTimelineMarkers,
        shortcut: 'Ctrl+Alt+M',
        enabled:
            widget.timelineMarkers.isNotEmpty &&
            widget.onClearTimelineMarkers != null,
      ),
      const PopupMenuDivider(),
      _menuItem(
        Icons.ads_click,
        'Select clip at cursor',
        _TimelineMenuAction.selectClipAtCursor,
        shortcut: 'D',
        enabled: segment != null && widget.onSelectClipAt != null,
      ),
      _menuItem(
        Icons.deselect,
        'Deselect clip',
        _TimelineMenuAction.deselectClip,
        shortcut: 'Ctrl+Shift+A',
        enabled:
            widget.selectedSegmentOrder != null &&
            widget.onDeselectClip != null,
      ),
      _menuItem(
        Icons.skip_previous,
        'Select previous clip',
        _TimelineMenuAction.selectPreviousClip,
        shortcut: 'Ctrl+Left',
        enabled:
            widget.segments.length > 1 && widget.onSelectPreviousClip != null,
      ),
      _menuItem(
        Icons.skip_next,
        'Select next clip',
        _TimelineMenuAction.selectNextClip,
        shortcut: 'Ctrl+Right',
        enabled: widget.segments.length > 1 && widget.onSelectNextClip != null,
      ),
      _menuItem(
        Icons.add,
        'Add Edit at cursor',
        _TimelineMenuAction.addEdit,
        shortcut: 'Ctrl+K',
        enabled: segment != null && markedTargetsUnlocked,
      ),
      _menuItem(
        Icons.splitscreen_outlined,
        'Add Edit to all tracks',
        _TimelineMenuAction.addEditAllTracks,
        shortcut: 'Ctrl+Shift+K',
        enabled:
            segment != null &&
            !videoLocked &&
            !anyAudioLocked &&
            widget.onAddEditAllTracksAt != null,
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
      _menuItem(
        Icons.compare_arrows,
        'Roll incoming earlier 1f',
        _TimelineMenuAction.rollIncomingEarlierFrame,
        shortcut: 'Alt+,',
        enabled: canRollIncoming,
      ),
      _menuItem(
        Icons.compare_arrows,
        'Roll incoming later 1f',
        _TimelineMenuAction.rollIncomingLaterFrame,
        shortcut: 'Alt+.',
        enabled: canRollIncoming,
      ),
      _menuItem(
        Icons.swap_horizontal_circle_outlined,
        'Roll outgoing earlier 1f',
        _TimelineMenuAction.rollOutgoingEarlierFrame,
        shortcut: 'Alt+Shift+,',
        enabled: canRollOutgoing,
      ),
      _menuItem(
        Icons.swap_horizontal_circle_outlined,
        'Roll outgoing later 1f',
        _TimelineMenuAction.rollOutgoingLaterFrame,
        shortcut: 'Alt+Shift+.',
        enabled: canRollOutgoing,
      ),
      _menuItem(
        Icons.swap_horiz,
        'Slip source earlier 1f',
        _TimelineMenuAction.slipEarlierFrame,
        shortcut: 'Alt+Left',
        enabled:
            clipEditable &&
            widget.duration > 0 &&
            widget.onSlipSelectedSegmentFrames != null,
      ),
      _menuItem(
        Icons.swap_horiz,
        'Slip source later 1f',
        _TimelineMenuAction.slipLaterFrame,
        shortcut: 'Alt+Right',
        enabled:
            clipEditable &&
            widget.duration > 0 &&
            widget.onSlipSelectedSegmentFrames != null,
      ),
      _menuItem(
        Icons.keyboard_double_arrow_left,
        'Slip source earlier 10f',
        _TimelineMenuAction.slipEarlierTenFrames,
        shortcut: 'Alt+Shift+Left',
        enabled:
            clipEditable &&
            widget.duration > 0 &&
            widget.onSlipSelectedSegmentFrames != null,
      ),
      _menuItem(
        Icons.keyboard_double_arrow_right,
        'Slip source later 10f',
        _TimelineMenuAction.slipLaterTenFrames,
        shortcut: 'Alt+Shift+Right',
        enabled:
            clipEditable &&
            widget.duration > 0 &&
            widget.onSlipSelectedSegmentFrames != null,
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
        enabled: segment != null && !anyAudioLocked,
      ),
      _menuItem(
        Icons.speed,
        'Rate stretch to In/Out',
        _TimelineMenuAction.rateStretchToMarks,
        shortcut: 'R',
        enabled: canRateStretch,
      ),
      const PopupMenuDivider(),
      _menuItem(
        Icons.content_copy,
        'Duplicate clip',
        _TimelineMenuAction.duplicate,
        enabled: clipEditable,
      ),
      _menuItem(
        Icons.copy_all_outlined,
        'Copy clip',
        _TimelineMenuAction.copySelected,
        shortcut: 'Ctrl+C',
        enabled: segment != null && widget.onCopySegment != null,
      ),
      _menuItem(
        Icons.cut_outlined,
        'Cut clip',
        _TimelineMenuAction.cutSelected,
        shortcut: 'Ctrl+X',
        enabled: clipEditable && widget.onCutSegment != null,
      ),
      _menuItem(
        Icons.content_paste_outlined,
        'Paste clip after selection',
        _TimelineMenuAction.pasteClipboard,
        shortcut: 'Ctrl+V',
        enabled: widget.hasClipClipboard && widget.onPasteSegment != null,
      ),
      _menuItem(
        Icons.delete_outline,
        selectedGap ? 'Delete gap' : 'Delete clip',
        _TimelineMenuAction.delete,
        shortcut: 'Delete / Backspace',
        enabled: clipEditable,
      ),
      if (selectedGap)
        _menuItem(
          Icons.join_inner,
          'Ripple delete selected gap',
          _TimelineMenuAction.closeSelectedGap,
          enabled: widget.onCloseSelectedGap != null,
        ),
      _menuItem(
        Icons.compress,
        'Close all black/silent gaps',
        _TimelineMenuAction.closeTimelineGaps,
        enabled: widget.hasTimelineGaps && widget.onCloseTimelineGaps != null,
      ),
      _menuItem(
        Icons.vertical_align_center,
        'Lift selected clip',
        _TimelineMenuAction.liftSelected,
        shortcut: 'Ctrl+;',
        enabled:
            canLiftOrExtractSelected && widget.onLiftSelectedSegment != null,
      ),
      _menuItem(
        Icons.playlist_remove,
        'Extract selected clip',
        _TimelineMenuAction.extractSelected,
        shortcut: "Ctrl+' / Shift+Delete / Shift+Backspace",
        enabled:
            canLiftOrExtractSelected && widget.onExtractSelectedSegment != null,
      ),
      _menuItem(
        Icons.keyboard_arrow_up,
        'Move earlier',
        _TimelineMenuAction.moveEarlier,
        shortcut: 'Ctrl+Up',
        enabled: segment != null,
      ),
      _menuItem(
        Icons.keyboard_arrow_down,
        'Move later',
        _TimelineMenuAction.moveLater,
        shortcut: 'Ctrl+Down',
        enabled: segment != null,
      ),
      const PopupMenuDivider(),
      _menuItem(
        segment != null && (segment.videoEnabled || !segment.audioMuted)
            ? Icons.block
            : Icons.check_circle_outline,
        segment != null && (segment.videoEnabled || !segment.audioMuted)
            ? 'Disable clip'
            : 'Enable clip',
        _TimelineMenuAction.toggleClipEnabled,
        shortcut: 'Shift+E',
        enabled:
            segment != null &&
            !videoLocked &&
            !anyAudioLocked &&
            widget.onToggleClipEnabled != null,
      ),
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
        enabled: segment != null && !anyAudioLocked,
      ),
      _menuItem(
        segment?.audioMuted ?? false
            ? Icons.volume_up_outlined
            : Icons.volume_off_outlined,
        segment?.audioMuted ?? false ? 'Unmute A1/A2' : 'Mute A1/A2',
        _TimelineMenuAction.toggleAudioMute,
        enabled: segment != null && !anyAudioLocked,
      ),
      _menuItem(
        segment?.audioChannel1Enabled ?? true
            ? Icons.check_box_outlined
            : Icons.check_box_outline_blank,
        segment?.audioChannel1Enabled ?? true ? 'Disable A1' : 'Enable A1',
        _TimelineMenuAction.toggleAudioChannel1,
        enabled:
            segment != null &&
            !audio1Locked &&
            ((segment.audioChannel2Enabled) || !segment.audioChannel1Enabled),
      ),
      _menuItem(
        segment?.audioChannel2Enabled ?? true
            ? Icons.check_box_outlined
            : Icons.check_box_outline_blank,
        segment?.audioChannel2Enabled ?? true ? 'Disable A2' : 'Enable A2',
        _TimelineMenuAction.toggleAudioChannel2,
        enabled:
            segment != null &&
            !audio2Locked &&
            ((segment.audioChannel1Enabled) || !segment.audioChannel2Enabled),
      ),
      _menuItem(
        Icons.balance_outlined,
        'Reset A1/A2 pan',
        _TimelineMenuAction.resetAudioPan,
        enabled: segment != null && !anyAudioLocked,
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
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (shortcut != null) ...[
            const SizedBox(width: 14),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  shortcut,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
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
    widget.onScrub(_snapTimelineSeconds(_xToSeconds(x, width), width));
  }

  void _updateDrag(double x, double width) {
    if (_isScrubbing) {
      widget.onScrub(_snapTimelineSeconds(_xToSeconds(x, width), width));
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
    final seconds = _snapTimelineSeconds(_xToSeconds(x, width), width);

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
    final layout = _layout;
    if (y >= layout.videoTop - 10 &&
        y <= layout.videoTop + layout.laneHeight + 10) {
      return _DragTrack.video;
    }
    if (y >= layout.audio1Top - 8 &&
        y <= layout.audio1Top + layout.laneHeight + 8) {
      return _DragTrack.audio1;
    }
    if (y >= layout.audio2Top - 8 &&
        y <= layout.audio2Top + layout.laneHeight + 8) {
      return _DragTrack.audio2;
    }
    return null;
  }

  bool _trackLocked(_DragTrack track) {
    return switch (track) {
      _DragTrack.video => widget.videoTrackLocked,
      _DragTrack.audio1 => widget.audioTrackLocked || widget.audioTrack1Locked,
      _DragTrack.audio2 => widget.audioTrackLocked || widget.audioTrack2Locked,
    };
  }

  bool _isAudioTrack(_DragTrack? track) =>
      track == _DragTrack.audio1 || track == _DragTrack.audio2;

  String _audioTrackLabel(_DragTrack track) =>
      track == _DragTrack.audio2 ? 'A2' : 'A1';

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

  TimelineMarker? _markerAt(double x, double width) {
    TimelineMarker? closest;
    var closestDistance = double.infinity;
    for (final marker in widget.timelineMarkers) {
      final markerX = _secondsToX(marker.seconds, width);
      final distance = (x - markerX).abs();
      if (distance < closestDistance) {
        closest = marker;
        closestDistance = distance;
      }
    }
    return closestDistance <= 10 ? closest : null;
  }

  bool _hasNextMarker() {
    final threshold = widget.playheadSeconds + timecodeFrameDurationSeconds / 2;
    return widget.timelineMarkers.any((marker) => marker.seconds > threshold);
  }

  bool _hasPreviousMarker() {
    final threshold = widget.playheadSeconds - timecodeFrameDurationSeconds / 2;
    return widget.timelineMarkers.any((marker) => marker.seconds < threshold);
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

  double _snapTimelineSeconds(double value, double width) {
    final frameValue = snapSecondsToFrame(value).clamp(0.0, widget.duration);
    if (!widget.snappingEnabled || widget.duration <= 0 || width <= 0) {
      return frameValue.toDouble();
    }

    final x = _secondsToX(frameValue.toDouble(), width);
    var closestSeconds = frameValue.toDouble();
    var closestDistance = double.infinity;
    for (final candidate in _snapCandidateSeconds()) {
      final snappedCandidate = snapSecondsToFrame(
        candidate.clamp(0.0, widget.duration).toDouble(),
      );
      final distance = (x - _secondsToX(snappedCandidate, width)).abs();
      if (distance < closestDistance && distance <= _snapHitWidth) {
        closestDistance = distance;
        closestSeconds = snappedCandidate;
      }
    }
    return closestSeconds;
  }

  List<double> _snapCandidateSeconds() {
    final points = <double>{0.0, widget.duration};
    if (widget.markIn != null) {
      points.add(widget.markIn!);
    }
    if (widget.markOut != null) {
      points.add(widget.markOut!);
    }
    for (final marker in widget.timelineMarkers) {
      if (marker.enabled) {
        points.add(marker.seconds);
      }
    }
    for (final segment in widget.segments) {
      points
        ..add(segment.start)
        ..add(segment.end)
        ..add(segment.effectiveAudioStart)
        ..add(segment.effectiveAudioEnd);
    }
    return points.toList();
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.layout,
    required this.duration,
    required this.segments,
    required this.playheadSeconds,
    required this.selectedSegmentOrder,
    required this.markIn,
    required this.markOut,
    required this.timelineMarkers,
    required this.waveform,
    required this.activeIndex,
    required this.activeEdge,
    required this.activeTrack,
    required this.videoTrackLocked,
    required this.audioTrack1Locked,
    required this.audioTrack2Locked,
    required this.colorScheme,
  });

  static const double _handleVisualWidth =
      _TimelineEditorState._handleVisualWidth;
  static const Color _videoClipColor = Color(0xFFA7F3A1);
  static const Color _videoClipActiveColor = Color(0xFFC6F77B);
  static const Color _audioClipColor = Color(0xFFFFBD7A);
  static const Color _audioClipActiveColor = Color(0xFFFFD49C);
  static const Color _clipTextColor = Color(0xFF11140F);

  final _TimelineLayout layout;
  final double duration;
  final List<HighlightSegment> segments;
  final double playheadSeconds;
  final int? selectedSegmentOrder;
  final double? markIn;
  final double? markOut;
  final List<TimelineMarker> timelineMarkers;
  final List<double> waveform;
  final int? activeIndex;
  final _DragEdge? activeEdge;
  final _DragTrack? activeTrack;
  final bool videoTrackLocked;
  final bool audioTrack1Locked;
  final bool audioTrack2Locked;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(5);
    final trackPaint = Paint()..color = colorScheme.surfaceContainerHighest;
    _drawTrack(canvas, size, layout.videoTop, radius, trackPaint);
    _drawTrack(canvas, size, layout.audio1Top, radius, trackPaint);
    _drawTrack(canvas, size, layout.audio2Top, radius, trackPaint);
    _drawLaneLabel(
      canvas,
      videoTrackLocked ? 'V1 LOCK' : 'V1',
      layout.videoTop,
      _videoClipColor,
    );
    _drawLaneLabel(
      canvas,
      audioTrack1Locked ? 'A1 LOCK' : 'A1',
      layout.audio1Top,
      _audioClipColor,
    );
    _drawLaneLabel(
      canvas,
      audioTrack2Locked ? 'A2 LOCK' : 'A2',
      layout.audio2Top,
      _audioClipColor,
    );

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
    final rect = Rect.fromLTWH(0, top, size.width, layout.laneHeight);
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
      Offset(44, top + layout.laneHeight / 2),
      Offset(size.width, top + layout.laneHeight / 2),
      Paint()
        ..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );
  }

  void _drawLaneLabel(Canvas canvas, String label, double top, Color color) {
    final width = label.length > 2 ? 54.0 : 30.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, top + 6, width, layout.laneHeight - 12),
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
      Offset(
        8 + width / 2 - textPainter.width / 2,
        top + layout.laneHeight / 2 - textPainter.height / 2,
      ),
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
    final centers = <double>[
      layout.audio1Top + layout.laneHeight / 2,
      layout.audio2Top + layout.laneHeight / 2,
    ];
    for (var index = 0; index < waveform.length; index++) {
      final x = index * step;
      final peak = waveform[index].clamp(0.0, 1.0).toDouble();
      final halfHeight = math.max(1.0, peak * layout.laneHeight / 2);
      for (final centerY in centers) {
        canvas.drawLine(
          Offset(x, centerY - halfHeight),
          Offset(x, centerY + halfHeight),
          wavePaint,
        );
      }
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
        layout.videoTop - 7,
        math.max(2, right - left),
        layout.audio2Top - layout.videoTop + layout.laneHeight + 14,
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
        Offset(x, isMajor ? layout.trackBottom + 6 : 38),
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
        top: layout.videoTop,
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
        top: layout.audio1Top,
        start: 0,
        end: duration,
        fill: _audioClipColor,
        border: _audioClipColor,
        radius: radius,
        handlesActive: false,
        label: 'A1 Source',
        track: _DragTrack.audio1,
      );
      _drawClipBlock(
        canvas,
        size,
        top: layout.audio2Top,
        start: 0,
        end: duration,
        fill: _audioClipColor,
        border: _audioClipColor,
        radius: radius,
        handlesActive: false,
        label: 'A2 Source',
        track: _DragTrack.audio2,
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
        top: layout.videoTop,
        start: segment.start,
        end: segment.end,
        fill: segment.videoEnabled
            ? (isActive ? _videoClipActiveColor : _videoClipColor)
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
        border: segment.videoEnabled
            ? (isActive ? _videoClipActiveColor : _videoClipColor)
            : colorScheme.error,
        radius: radius,
        handlesActive: isActive && !_isAudioTrack(activeTrack),
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
      _drawAudioChannelBlock(
        canvas,
        size,
        segment: segment,
        top: layout.audio1Top,
        channelEnabled: segment.audioChannel1Enabled,
        channelLabel: 'A1',
        fill: audioFill,
        border: audioBorder,
        radius: radius,
        handlesActive: isActive && activeTrack != _DragTrack.video,
        track: _DragTrack.audio1,
      );
      _drawAudioChannelBlock(
        canvas,
        size,
        segment: segment,
        top: layout.audio2Top,
        channelEnabled: segment.audioChannel2Enabled,
        channelLabel: 'A2',
        fill: audioFill,
        border: audioBorder,
        radius: radius,
        handlesActive: isActive && activeTrack != _DragTrack.video,
        track: _DragTrack.audio2,
      );
      if (segment.audioPan.abs() > 0.001) {
        _drawPanIndicator(canvas, size, segment);
      }
    }
  }

  bool _isAudioTrack(_DragTrack? track) =>
      track == _DragTrack.audio1 || track == _DragTrack.audio2;

  void _drawAudioChannelBlock(
    Canvas canvas,
    Size size, {
    required HighlightSegment segment,
    required double top,
    required bool channelEnabled,
    required String channelLabel,
    required Color fill,
    required Color border,
    required Radius radius,
    required bool handlesActive,
    required _DragTrack track,
  }) {
    final disabled = segment.audioMuted || !channelEnabled;
    _drawClipBlock(
      canvas,
      size,
      top: top,
      start: segment.effectiveAudioStart,
      end: segment.effectiveAudioEnd,
      fill: disabled
          ? fill.withValues(alpha: 0.22)
          : fill.withValues(alpha: segment.audioLinked ? 0.84 : 0.95),
      border: channelEnabled ? border : colorScheme.outline,
      radius: radius,
      handlesActive: handlesActive,
      disabledPattern: disabled,
      label: disabled
          ? '$channelLabel off C${segment.order}'
          : '$channelLabel C${segment.order}',
      track: track,
    );
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
      layout.laneHeight - 4,
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
          center: Offset(handleX, top + layout.laneHeight / 2),
          width: _handleVisualWidth,
          height: layout.laneHeight + 4,
        ),
        Radius.circular(2),
      );
      canvas.drawRRect(handleRect, handlePaint);
      canvas.drawRRect(handleRect, handleBorder);
      canvas.drawLine(
        Offset(handleX, top + 5),
        Offset(handleX, top + layout.laneHeight - 5),
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
    for (final top in [layout.audio1Top, layout.audio2Top]) {
      final center = Offset(panX, top + layout.laneHeight / 2);
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
  }

  void _drawFadeOverlay(Canvas canvas, Size size, HighlightSegment segment) {
    final left = _secondsToX(segment.start, size.width);
    final right = _secondsToX(segment.end, size.width);
    final clipWidth = math.max(2.0, right - left);
    final fadePaint = Paint()
      ..color = colorScheme.surface.withValues(alpha: 0.38);
    final clipTop = layout.videoTop + 2;
    final clipBottom = layout.videoTop + layout.laneHeight - 2;

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
    for (final marker in timelineMarkers) {
      _drawTimelineMarker(canvas, size, marker);
    }
    final inPoint = markIn;
    final outPoint = markOut;
    if (inPoint != null) {
      _drawMarker(canvas, size, inPoint, 'IN', colorScheme.primary);
    }
    if (outPoint != null) {
      _drawMarker(canvas, size, outPoint, 'OUT', colorScheme.error);
    }
  }

  void _drawTimelineMarker(Canvas canvas, Size size, TimelineMarker marker) {
    final x = _secondsToX(marker.seconds, size.width);
    final markerEnabled = marker.enabled;
    final color = markerEnabled
        ? _timelineMarkerColor(marker.color)
        : colorScheme.onSurfaceVariant;
    final linePaint = Paint()
      ..color = color.withValues(alpha: markerEnabled ? 0.62 : 0.32)
      ..strokeWidth = markerEnabled ? 1.1 : 0.8;
    canvas.drawLine(
      Offset(x, 25),
      Offset(x, layout.trackBottom + 10),
      linePaint,
    );

    final head = Path()
      ..moveTo(x, 27)
      ..lineTo(x - 5, 33)
      ..lineTo(x, 39)
      ..lineTo(x + 5, 33)
      ..close();
    canvas.drawPath(
      head,
      Paint()..color = color.withValues(alpha: markerEnabled ? 1 : 0.55),
    );
    canvas.drawPath(
      head,
      Paint()
        ..color = colorScheme.surface.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: marker.label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: markerEnabled ? FontWeight.w800 : FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 72);
    final labelX = (x + 7)
        .clamp(2.0, math.max(2.0, size.width - textPainter.width - 2))
        .toDouble();
    textPainter.paint(canvas, Offset(labelX, 29));
  }

  Color _timelineMarkerColor(String color) {
    switch (color) {
      case 'cyan':
        return colorScheme.primary;
      case 'green':
        return colorScheme.secondary;
      case 'rose':
        return colorScheme.error;
      case 'violet':
        return const Color(0xFFC084FC);
      case 'amber':
      default:
        return colorScheme.tertiary;
    }
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    final playheadX = _secondsToX(playheadSeconds, size.width);
    final playheadPaint = Paint()
      ..color = colorScheme.onSurface
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playheadX, 4),
      Offset(playheadX, layout.trackBottom + 12),
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
      Offset(x, layout.trackBottom + 10),
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
        layout.scale != oldDelegate.layout.scale ||
        segments != oldDelegate.segments ||
        playheadSeconds != oldDelegate.playheadSeconds ||
        selectedSegmentOrder != oldDelegate.selectedSegmentOrder ||
        markIn != oldDelegate.markIn ||
        markOut != oldDelegate.markOut ||
        timelineMarkers != oldDelegate.timelineMarkers ||
        waveform != oldDelegate.waveform ||
        activeIndex != oldDelegate.activeIndex ||
        activeEdge != oldDelegate.activeEdge ||
        activeTrack != oldDelegate.activeTrack ||
        videoTrackLocked != oldDelegate.videoTrackLocked ||
        audioTrack1Locked != oldDelegate.audioTrack1Locked ||
        audioTrack2Locked != oldDelegate.audioTrack2Locked ||
        colorScheme != oldDelegate.colorScheme;
  }
}
